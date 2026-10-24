import { Router } from 'express';
import { getSurprisesFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const surprisesRouter = Router();

surprisesRouter.get('/surprises', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  res.json(getSurprisesFor(user.id));
});
