import { Router } from 'express';
import { z } from 'zod';
import { listSurprisesForUser, setGestureReaction, useDatabase } from '../db/index.js';
import { getSurprisesFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const surprisesRouter = Router();

surprisesRouter.get('/surprises', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  if (useDatabase()) {
    // Surprises (surprisesOn) only appear once the friend marks them delivered.
    res.json(await listSurprisesForUser(user.id));
    return;
  }
  res.json(getSurprisesFor(user.id));
});

const reactionBody = z.object({ reaction: z.enum(['helped', 'space']) });

// The person helped tells their twin how it landed, so it can do better next time.
surprisesRouter.post('/surprises/:id/reaction', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = reactionBody.safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  if (!useDatabase()) {
    res.json({ ok: true });
    return;
  }
  const saved = await setGestureReaction(req.params.id, user.id, body.data.reaction);
  if (!saved) {
    res.status(404).json({ error: 'Surprise not found' });
    return;
  }
  res.json({ ok: true });
});
