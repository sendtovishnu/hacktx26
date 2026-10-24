import { Router } from 'express';
import { getUsers } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const usersRouter = Router();

usersRouter.get('/users', requireDemoUser, (_req, res) => {
  res.json(getUsers());
});

usersRouter.get('/me', requireDemoUser, (req, res) => {
  res.json((req as DemoRequest).demoUser);
});
