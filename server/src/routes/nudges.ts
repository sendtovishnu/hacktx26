import { Router } from 'express';
import { getNudge, listNudgesToUser, useDatabase } from '../db/index.js';
import { getNudgeById, getNudgesFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import { suggestionsForNudge } from '../nudgeSuggestions.js';

export const nudgesRouter = Router();

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
    res.json(await suggestionsForNudge(nudge, user));
  } catch (err) {
    res.status(500).json({
      error: err instanceof Error ? err.message : 'Suggestions failed',
    });
  }
});
