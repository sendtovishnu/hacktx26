import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { decideNudges, extractSignals, filterEmails, planMoment } from '../ai/index.js';
import {
  deleteEmails,
  deleteSummaryOverride,
  deleteUnactedNudgesFrom,
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
      const events = toCalendarEvents(dbEvents);
      const emails = filterEmails(toEmailSnippets(dbEmails));
      await saveSignals(user.id, await extractSignals(events, emails, checkin));
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

      let decisions = await decideNudges(user, signals, friends);
      decisions = decisions.filter((d) => {
        const friend = friends.find((f) => f.friend.id === d.friendId);
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

      if (user.paused || !user.surpriseOptIn) {
        decisions = [];
      }

      await deleteUnactedNudgesFrom(user.id);
      for (const decision of decisions) {
        const friend = friends.find((f) => f.friend.id === decision.friendId);
        const contextLevel = friend ? canShareContext(friend.tier) : null;
        if (!friend || !contextLevel) continue;
        const nudgeId = `n_${randomUUID()}`;
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

      res.json({ signals, nudgesSent: decisions.length });
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
