import { Router } from 'express';
import { listSurprisesForUser, useDatabase } from '../db/index.js';
import { getSurprisesFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const surprisesRouter = Router();

surprisesRouter.get('/surprises', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  if (useDatabase()) {
    if (!user.surpriseOptIn) {
      res.json([]);
      return;
    }
    res.json(await listSurprisesForUser(user.id));
    return;
  }
  res.json(getSurprisesFor(user.id));
});
