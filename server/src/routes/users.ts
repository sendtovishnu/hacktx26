import { Router } from 'express';
import { getUser, listUsers, useDatabase } from '../db/index.js';
import { getUsers } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const usersRouter = Router();

usersRouter.get('/users', requireDemoUser, async (_req, res) => {
  if (useDatabase()) {
    res.json(await listUsers());
    return;
  }
  res.json(getUsers());
});

usersRouter.get('/me', requireDemoUser, async (req, res) => {
  const demoUserId = (req as DemoRequest).demoUser.id;
  if (useDatabase()) {
    const user = await getUser(demoUserId);
    if (!user) {
      res.status(404).json({ error: `Unknown demo user: ${demoUserId}` });
      return;
    }
    res.json(user);
    return;
  }
  res.json((req as DemoRequest).demoUser);
});
