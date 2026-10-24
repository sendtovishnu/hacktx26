import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { decideNudges, extractSignals, filterEmails } from '../ai/index.js';
import {
  deleteEmails,
  deleteUnactedNudgesFrom,
  getFriends,
  getLatestSignal,
  insertNudge,
  listEmails,
  listEvents,
  saveSignals,
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
import {
  allowedToNudge,
  canShareContext,
  gestureFor,
  sharedFreeMinutes,
} from '../rules/index.js';
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
      const events = toCalendarEvents(dbEvents);
      const emails = filterEmails(toEmailSnippets(dbEmails));
      const signals = await extractSignals(events, emails, checkin);
      await saveSignals(user.id, signals);

      const friendEntries = await getFriends(user.id);
      const friends: TwinFriendInput[] = [];
      for (const entry of friendEntries) {
        const friendEvents = toCalendarEvents(await listEvents(entry.friend.id));
        friends.push({
          friend: entry.friend,
          tier: entry.tier,
          sharedFreeMinutes: sharedFreeMinutes(events, friendEvents),
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
        return { ...d, gestureType: gestureFor(signals, mins) };
      });

      if (user.paused || !user.surpriseOptIn) {
        decisions = [];
      }

      await deleteUnactedNudgesFrom(user.id);
      for (const decision of decisions) {
        const friend = friends.find((f) => f.friend.id === decision.friendId);
        const contextLevel = friend ? canShareContext(friend.tier) : null;
        if (!contextLevel) continue;
        await insertNudge({
          id: `n_${randomUUID()}`,
          fromUserId: user.id,
          toFriendId: decision.friendId,
          message: decision.message,
          contextLevel,
          status: 'sent',
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
    res.json({ signals: row ? toSignals(row) : null });
    return;
  }
  res.json({ signals: getSignalsFor(user.id) });
});
