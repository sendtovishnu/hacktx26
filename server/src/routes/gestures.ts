import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import {
  getGesture,
  getLatestSignal,
  getNudge,
  getNudgeDraftNote,
  insertGesture,
  latestReaction,
  revealGesture,
  listEvents,
  respectReaction,
  toCalendarEvents,
  toSignals,
  updateNudgeStatus,
  useDatabase,
} from '../db/index.js';
import { getNudgeById, getUserById } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import { gestureFor, sharedFreeMinutes } from '../rules/index.js';
import {
  buildSuggestions,
  nearLocation,
  surpriseNoteFor,
} from '../suggestions.js';
import type { Gesture, GestureType, Signals } from '../types.js';

export const gesturesRouter = Router();

const bodySchema = z.object({
  nudgeId: z.string().min(1),
  suggestionIndex: z.number().int().nonnegative(),
  // The friend's own words; falls back to Muse's draft, then the template.
  note: z.string().trim().min(1).max(500).optional(),
});

gesturesRouter.post('/gestures', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = bodySchema.safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }

  const { nudgeId, suggestionIndex } = body.data;

  try {
    if (useDatabase()) {
      const nudge = await getNudge(nudgeId);
      if (!nudge) {
        res.status(404).json({ error: 'Nudge not found' });
        return;
      }
      if (nudge.toFriendId !== user.id) {
        res.status(403).json({ error: 'Only the nudged friend can act' });
        return;
      }

      const signalRow = await getLatestSignal(nudge.fromUser.id);
      const signals: Signals | null = signalRow ? toSignals(signalRow) : null;
      const mins = signals
        ? sharedFreeMinutes(
            toCalendarEvents(await listEvents(nudge.fromUser.id)),
            toCalendarEvents(await listEvents(nudge.toFriendId)),
          )
        : 0;
      // Must match what GET /nudges/:id/suggestions offered, so the index points at the same choice.
      const gestureType: GestureType = signals
        ? await respectReaction(nudge.fromUser.id, user.id, gestureFor(signals, mins))
        : 'message';
      const near = nearLocation(signals, nudge.fromUser.homeLocation);
      // Same inputs as GET /nudges/:id/suggestions, so the index points at the same choice.
      const wantsSpace = (await latestReaction(nudge.fromUser.id, user.id)) === 'space';
      const suggestions = await buildSuggestions({
        fromUser: nudge.fromUser,
        gestureType,
        near,
        nudgeMessage: nudge.message,
        wantsSpace,
      });
      const choice = suggestions[suggestionIndex];
      if (!choice) {
        res.status(400).json({ error: 'Invalid suggestionIndex' });
        return;
      }

      const id = `g_${randomUUID()}`;
      const deliveredAt = new Date().toISOString();
      const note =
        body.data.note ??
        (await getNudgeDraftNote(nudgeId)) ??
        surpriseNoteFor(choice, nudge.fromUser);
      await insertGesture({
        id,
        nudgeId,
        fromFriendId: user.id,
        type: choice.gestureType,
        placeName: choice.place?.name ?? null,
        placeAddress: choice.place?.address ?? null,
        note,
        deliveredAt,
        // A note arrives as it's sent; only something planned can wait to be a surprise.
        surprise: choice.gestureType !== 'message' && (nudge.fromUser.surprisesOn ?? true),
      });
      await updateNudgeStatus(nudgeId, 'acted');

      const saved = await getGesture(id);
      res.status(201).json(
        saved ??
          ({
            id,
            nudgeId,
            fromFriend: user,
            type: choice.gestureType,
            place: choice.place,
            note,
            deliveredAt,
          } satisfies Gesture),
      );
      return;
    }

    // Mock fallback — no persistence beyond response.
    const nudge = getNudgeById(nudgeId);
    if (!nudge) {
      res.status(404).json({ error: 'Nudge not found' });
      return;
    }
    if (nudge.toFriendId !== user.id) {
      res.status(403).json({ error: 'Only the nudged friend can act' });
      return;
    }
    if (!getUserById(nudge.fromUser.id)) {
      res.status(404).json({ error: 'Helped user not found' });
      return;
    }

    const signals = null as Signals | null;
    const gestureType: GestureType =
      nudge.fromUser.id === 'u_maya' && nudge.toFriendId === 'u_jay'
        ? 'drop_off'
        : 'message';
    const near = nearLocation(signals, nudge.fromUser.homeLocation);
    const suggestions = await buildSuggestions({
      fromUser: nudge.fromUser,
      gestureType,
      near,
      nudgeMessage: nudge.message,
    });
    const choice = suggestions[suggestionIndex];
    if (!choice) {
      res.status(400).json({ error: 'Invalid suggestionIndex' });
      return;
    }

    const gesture: Gesture = {
      id: `g_${Date.now()}`,
      nudgeId,
      fromFriend: user,
      type: choice.gestureType,
      place: choice.place,
      note: surpriseNoteFor(choice, nudge.fromUser),
      deliveredAt: new Date().toISOString(),
    };
    res.status(201).json(gesture);
  } catch (err) {
    res.status(500).json({
      error: err instanceof Error ? err.message : 'Gesture failed',
    });
  }
});

// A surprise stays hidden until the friend says it happened; then the person gets the note.
gesturesRouter.post('/gestures/:id/delivered', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  if (!useDatabase()) {
    res.json({ ok: true });
    return;
  }
  const ok = await revealGesture(req.params.id, user.id);
  res.status(ok ? 200 : 404).json(ok ? { ok } : { error: 'Nothing to mark delivered.' });
});
