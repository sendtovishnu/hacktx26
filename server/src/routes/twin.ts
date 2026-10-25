import { Router } from 'express';
import { z } from 'zod';
import { decideNudges, extractSignals, filterEmails } from '../ai/index.js';
import {
  addTwinEntry,
  deleteEmails,
  deleteSummaryOverride,
  deleteTwinEntry,
  getLatestSignal,
  listEmails,
  listEvents,
  listTwinEntries,
  markEntriesRead,
  saveSignals,
  setSummaryOverride,
  toCalendarEvents,
  toEmailSnippets,
  toSignals,
  useDatabase,
} from '../db/index.js';
import {
  getEmailsFor,
  getEventsFor,
  getFriendsFor,
  getSignalsFor,
} from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import { allowedToNudge, gestureFor, sharedFreeMinutes } from '../rules/index.js';
import { nudgeFriends, withOverride } from '../twinNudges.js';
import type { CalendarEvent, TwinFriendInput } from '../types.js';

export const twinRouter = Router();

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

      const result = await nudgeFriends(user, { emails: dbEmails, checkin, fromRefresh: true });
      await deleteEmails(user.id);

      // Nothing new for anyone: friends already know about everything this refresh read.
      res.json({
        signals,
        nudgesSent: result?.nudgesSent ?? 0,
        nothingNew: result ? !result.withdrawn && result.nothingNew : false,
      });
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
