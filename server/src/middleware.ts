import type { NextFunction, Request, Response } from 'express';
import { getUser, getUserBySession, useDatabase } from './db/index.js';
import { getUserById } from './mocks.js';
import type { User } from './types.js';

export type DemoRequest = Request & { demoUser: User };

export async function requireDemoUser(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  // A signed-in Google account wins over the demo header.
  const bearer = req.header('Authorization')?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (bearer && useDatabase()) {
    const user = await getUserBySession(bearer);
    if (!user) {
      res.status(401).json({ error: 'Session expired. Sign in again.' });
      return;
    }
    (req as DemoRequest).demoUser = user;
    next();
    return;
  }

  const header = req.header('X-Demo-User');
  if (!header) {
    res.status(401).json({ error: 'Missing X-Demo-User header' });
    return;
  }

  if (useDatabase()) {
    const user = await getUser(header);
    if (!user) {
      res.status(404).json({ error: `Unknown demo user: ${header}` });
      return;
    }
    (req as DemoRequest).demoUser = user;
    next();
    return;
  }

  const user = getUserById(header);
  if (!user) {
    res.status(404).json({ error: `Unknown demo user: ${header}` });
    return;
  }
  (req as DemoRequest).demoUser = user;
  next();
}
