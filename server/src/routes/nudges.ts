import { Router } from 'express';
import {
  getLatestSignal,
  getNudge,
  listEvents,
  listNudgesToUser,
  respectReaction,
  toCalendarEvents,
  toSignals,
  useDatabase,
} from '../db/index.js';
import { getNudgeById, getNudgesFor, getSignalsFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import { gestureFor, sharedFreeMinutes } from '../rules/index.js';
import { buildSuggestions, nearLocation } from '../suggestions.js';
import type { GestureType, Signals } from '../types.js';

export const nudgesRouter = Router();

async function resolveGestureType(nudgeFromId: string, nudgeToId: string): Promise<{
  gestureType: GestureType;
  signals: Signals | null;
}> {
  if (useDatabase()) {
    const row = await getLatestSignal(nudgeFromId);
    const signals = row ? toSignals(row) : null;
    if (!signals) {
      return { gestureType: 'message', signals: null };
    }
    const mins = sharedFreeMinutes(
      toCalendarEvents(await listEvents(nudgeFromId)),
      toCalendarEvents(await listEvents(nudgeToId)),
    );
    return {
      gestureType: await respectReaction(nudgeFromId, nudgeToId, gestureFor(signals, mins)),
      signals,
    };
  }

  const signals = getSignalsFor(nudgeFromId);
  if (!signals) return { gestureType: 'message', signals: null };
  // Mock demo: Maya→Jay has no shared free block → drop_off under crunch.
  const mins =
    nudgeFromId === 'u_maya' && nudgeToId === 'u_jay'
      ? 0
      : sharedFreeMinutes([], []);
  return { gestureType: gestureFor(signals, mins), signals };
}

nudgesRouter.get('/nudges', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  if (useDatabase()) {
    res.json(await listNudgesToUser(user.id));
    return;
  }
  res.json(getNudgesFor(user.id).filter((n) => n.toFriendId === user.id));
});

nudgesRouter.get('/nudges/:id/suggestions', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const nudge = useDatabase()
    ? await getNudge(req.params.id)
    : getNudgeById(req.params.id);

  if (!nudge) {
    res.status(404).json({ error: 'Nudge not found' });
    return;
  }
  if (nudge.toFriendId !== user.id) {
    res.status(403).json({ error: 'Nudge is not addressed to this user' });
    return;
  }

  try {
    const { gestureType, signals } = await resolveGestureType(
      nudge.fromUser.id,
      nudge.toFriendId,
    );
    const near = nearLocation(signals, nudge.fromUser.homeLocation);
    const suggestions = await buildSuggestions({
      fromUser: nudge.fromUser,
      gestureType,
      near,
      nudgeMessage: nudge.message,
    });
    res.json(suggestions);
  } catch (err) {
    res.status(500).json({
      error: err instanceof Error ? err.message : 'Suggestions failed',
    });
  }
});
