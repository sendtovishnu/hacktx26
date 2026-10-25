import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { decideNudges, extractSignals, filterEmails, planMoment } from '../ai/index.js';
import {
  deleteEmails,
  deleteSummaryOverride,
  addTwinEntry,
  coveredInputs,
  deleteUnactedNudgesFrom,
  deleteTwinEntry,
  deleteUnactedNudgesTo,
  listTwinEntries,
  markCovered,
  markEntriesRead,
  getFriends,
  getLatestSignal,
  getSummaryOverride,
  insertNudge,
  latestReaction,
  listEmails,
  listEvents,
  recentGesturesBetween,
  saveSignals,
  setNudgeMoment,
  setSummaryOverride,
  toCalendarEvents,
  toEmailSnippets,
  toSignals,
  useDatabase,
} from '../db/index.js';
import { findPlaces } from '../places/index.js';
import { nearLocation } from '../suggestions.js';
import {
  getEmailsFor,
  getEventsFor,
  getFriendsFor,
  getSignalsFor,
} from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import {
  allowedToNudge,
  canShareContext,
  gestureFor,
  sharedFreeMinutes,
} from '../rules/index.js';
import type { CalendarEvent, GestureType, Signals, TwinFriendInput, User } from '../types.js';

export const twinRouter = Router();

/** What friends hear uses the person's own wording when they've edited it. */
async function withOverride(userId: string, signals: Signals): Promise<Signals> {
  const override = await getSummaryOverride(userId);
  return override ? { ...signals, ...override } : signals;
}

const gestureWords: Record<string, string> = {
  drop_off: 'a drop-off',
  hangout: 'a study break together',
  message: 'a note',
};

/** Pay it forward: what `user` recently did for `friend`, if anything. */
async function showedUpFor(user: User, friend: User): Promise<string | undefined> {
  const [latest] = await recentGesturesBetween(user.id, friend.id);
  if (!latest) return undefined;
  const what = gestureWords[latest.type] ?? 'something kind';
  return latest.placeName ? `${what} from ${latest.placeName}` : what;
}

/**
 * Twin to twin, in the background: the friend's twin plans when and where they
 * can show up, so the person's refresh doesn't wait on it. The friend's app
 * picks the moment up on its next poll.
 */
function planMomentInBackground(args: {
  nudgeId: string;
  person: User;
  personEvents: CalendarEvent[];
  signals: Signals;
  friend: User;
  friendEvents: CalendarEvent[];
  gestureType: GestureType;
}): void {
  void (async () => {
    const near = nearLocation(args.signals, args.person.homeLocation);
    const [place] = args.gestureType === 'message' ? [] : await findPlaces('coffee', near);
    const moment = await planMoment({
      friend: args.friend,
      friendEvents: args.friendEvents,
      person: args.person,
      personBusy: args.personEvents.map(({ start, end }) => ({ start, end })),
      personLocation: args.signals.likelyLocation ?? args.person.homeLocation,
      gestureType: args.gestureType,
      placeName: place?.name,
    });
    if (moment) await setNudgeMoment(args.nudgeId, moment);
  })().catch((err) => console.warn('[twin] moment planning failed:', (err as Error).message));
}

const refreshBody = z.object({
  checkin: z.string().optional(),
});

twinRouter.post('/twin/refresh', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = refreshBody.safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  const checkin = body.data.checkin;

  try {
    if (useDatabase()) {
      const dbEvents = await listEvents(user.id);
      const dbEmails = await listEmails(user.id);
      const entries = await listTwinEntries(user.id);
      const events = toCalendarEvents(dbEvents);
      const emails = filterEmails(toEmailSnippets(dbEmails));
      // What they've added to their twin counts like a check-in, every refresh, until they delete it.
      const told = [checkin, ...entries.map((e) => e.text)].filter((t): t is string => Boolean(t?.trim()));
      await saveSignals(user.id, await extractSignals(events, emails, told.length ? told.join('" and "') : undefined));
      // Now part of the twin's read of the week, so the app moves them up out of "waiting".
      await markEntriesRead(user.id);
      const signals = await withOverride(user.id, toSignals((await getLatestSignal(user.id))!));

      const friendEntries = await getFriends(user.id);
      const friends: TwinFriendInput[] = [];
      const eventsByFriend = new Map<string, CalendarEvent[]>();
      for (const entry of friendEntries) {
        const friendEvents = toCalendarEvents(await listEvents(entry.friend.id));
        eventsByFriend.set(entry.friend.id, friendEvents);
        friends.push({
          friend: entry.friend,
          tier: entry.tier,
          sharedFreeMinutes: sharedFreeMinutes(events, friendEvents),
          showedUpForThem: await showedUpFor(user, entry.friend),
          lastReaction: (await latestReaction(user.id, entry.friend.id)) ?? undefined,
        });
      }

      // A friend hears about each thing once. Only friends with something new are considered,
      // and a nudge marks everything it was based on as told.
      const inputKeys = [
        ...dbEvents.map((e) => `event:${e.title}|${e.start}`),
        ...dbEmails.map((e) => `email:${e.fromAddr}|${e.subject}|${e.date}`),
        ...entries.map((e) => `entry:${e.id}`),
        ...(checkin?.trim() ? [`checkin:${checkin.trim().toLowerCase()}`] : []),
      ];
      const covered = await coveredInputs(user.id);
      const hasNews = (friendId: string) => inputKeys.some((k) => !covered.get(friendId)?.has(k));
      const candidates = friends.filter((f) => hasNews(f.friend.id));

      let decisions = candidates.length ? await decideNudges(user, signals, candidates) : [];
      decisions = decisions.filter((d) => {
        const friend = candidates.find((f) => f.friend.id === d.friendId);
        if (!friend) return false;
        return allowedToNudge(friend.tier, signals.supportLevel);
      });

      decisions = decisions.map((d) => {
        const friend = friends.find((f) => f.friend.id === d.friendId);
        const mins = friend?.sharedFreeMinutes ?? 0;
        // The person said they needed space last time: a note, not a visit.
        const gestureType = friend?.lastReaction === 'space' ? 'message' : gestureFor(signals, mins);
        return { ...d, gestureType };
      });

      const withdrawn = user.paused || !user.surpriseOptIn || signals.supportLevel === 'doing_fine';
      if (withdrawn) {
        decisions = [];
        // Doing fine, or not open to support: open nudges are taken back. Coverage stays, so nothing repeats.
        await deleteUnactedNudgesFrom(user.id);
      }

      for (const decision of decisions) {
        const friend = friends.find((f) => f.friend.id === decision.friendId);
        const contextLevel = friend ? canShareContext(friend.tier) : null;
        if (!friend || !contextLevel) continue;
        const nudgeId = `n_${randomUUID()}`;
        await deleteUnactedNudgesTo(user.id, decision.friendId);
        await insertNudge({
          id: nudgeId,
          fromUserId: user.id,
          toFriendId: decision.friendId,
          message: decision.message,
          contextLevel,
          status: 'sent',
          draftNote: decision.surpriseNote,
          reason: decision.reason,
        });
        await markCovered(user.id, decision.friendId, inputKeys);
        planMomentInBackground({
          nudgeId,
          person: user,
          personEvents: events,
          signals,
          friend: friend.friend,
          friendEvents: eventsByFriend.get(friend.friend.id) ?? [],
          gestureType: decision.gestureType,
        });
      }

      await deleteEmails(user.id);

      // Nothing new for anyone: friends already know about everything this refresh read.
      const nothingNew = !withdrawn && inputKeys.length > 0 && candidates.length === 0;
      res.json({ signals, nudgesSent: decisions.length, nothingNew });
      return;
    }

    // Mock fallback — same decision rules, no persistence.
    const events: CalendarEvent[] = getEventsFor(user.id);
    const emails = filterEmails(getEmailsFor(user.id));
    const signals = await extractSignals(events, emails, checkin);
    const friends: TwinFriendInput[] = getFriendsFor(user.id).map((f) => ({
      friend: f.friend,
      tier: f.tier,
      sharedFreeMinutes:
        user.id === 'u_maya' && f.friend.id === 'u_jay'
          ? 0
          : sharedFreeMinutes(events, getEventsFor(f.friend.id)),
    }));

    let decisions = await decideNudges(user, signals, friends);
    decisions = decisions.filter((d) => {
      const friend = friends.find((f) => f.friend.id === d.friendId);
      if (!friend) return false;
      return allowedToNudge(friend.tier, signals.supportLevel);
    });
    decisions = decisions.map((d) => {
      const friend = friends.find((f) => f.friend.id === d.friendId);
      return {
        ...d,
        gestureType: gestureFor(signals, friend?.sharedFreeMinutes ?? 0),
      };
    });
    if (user.paused || !user.surpriseOptIn) decisions = [];

    res.json({ signals, nudgesSent: decisions.length });
  } catch (err) {
    res.status(500).json({
      error: err instanceof Error ? err.message : 'Twin refresh failed',
    });
  }
});

twinRouter.get('/twin', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  if (useDatabase()) {
    const row = await getLatestSignal(user.id);
    res.json({ signals: row ? await withOverride(user.id, toSignals(row)) : null });
    return;
  }
  res.json({ signals: getSignalsFor(user.id) });
});

// The person rewrites what each tier hears. Friend-tier people hear nothing,
// so the app's summaryForFriend is accepted but not stored.
const summariesBody = z.object({
  summaryForClosest: z.string().trim().min(1).max(200),
  summaryForClose: z.string().trim().min(1).max(200),
  summaryForFriend: z.string().optional(),
});

twinRouter.patch('/twin/summaries', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = summariesBody.safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  if (!useDatabase()) {
    res.status(501).json({ error: 'Editing summaries needs the database' });
    return;
  }
  await setSummaryOverride(user.id, body.data.summaryForClosest, body.data.summaryForClose);
  const row = await getLatestSignal(user.id);
  res.json({ signals: row ? await withOverride(user.id, toSignals(row)) : null });
});

twinRouter.delete('/twin/summaries', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  if (!useDatabase()) {
    res.status(501).json({ error: 'Editing summaries needs the database' });
    return;
  }
  await deleteSummaryOverride(user.id);
  const row = await getLatestSignal(user.id);
  res.json({ signals: row ? toSignals(row) : null });
});

// Things the person tells their twin directly. Each is read on every refresh until deleted.
twinRouter.get('/twin/entries', requireDemoUser, async (req, res) => {
  if (!useDatabase()) {
    res.json([]);
    return;
  }
  res.json(await listTwinEntries((req as DemoRequest).demoUser.id));
});

twinRouter.post('/twin/entries', requireDemoUser, async (req, res) => {
  const body = z.object({ text: z.string().trim().min(1).max(500) }).safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: 'Write something for your twin (up to 500 characters).' });
    return;
  }
  if (!useDatabase()) {
    res.status(501).json({ error: 'Adding to your twin needs the database' });
    return;
  }
  res.status(201).json(await addTwinEntry((req as DemoRequest).demoUser.id, body.data.text));
});

twinRouter.delete('/twin/entries/:id', requireDemoUser, async (req, res) => {
  if (!useDatabase()) {
    res.json({ ok: true });
    return;
  }
  const ok = await deleteTwinEntry((req as DemoRequest).demoUser.id, req.params.id);
  res.status(ok ? 200 : 404).json(ok ? { ok } : { error: 'Not found' });
});
