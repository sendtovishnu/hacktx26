import type { NextFunction, Request, Response } from 'express';
import { getUser, useDatabase } from './db/index.js';
import { getUserById } from './mocks.js';
import type { User } from './types.js';

export type DemoRequest = Request & { demoUser: User };

function readCookie(req: Request, name: string): string {
  const raw = req.headers.cookie ?? '';
  const match = raw.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1]) : '';
}

/** Resolve the current user from X-Demo-User / X-User-Id, or a session cookie. */
export function resolveUserId(req: Request): string | null {
  const header =
    req.header('X-Demo-User')?.trim() ||
    req.header('X-User-Id')?.trim() ||
    '';
  if (header) return header;
  const cookie = readCookie(req, 'session_user').trim();
  return cookie || null;
}

export async function requireDemoUser(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const header = resolveUserId(req);
  if (!header) {
    res.status(401).json({
      error: 'Missing X-Demo-User / X-User-Id header (or session cookie)',
    });
    return;
  }

  if (useDatabase()) {
    const user = await getUser(header);
    if (!user) {
      res.status(404).json({ error: `Unknown user: ${header}` });
      return;
    }
    (req as DemoRequest).demoUser = user;
    next();
    return;
  }

  const user = getUserById(header);
  if (!user) {
    res.status(404).json({ error: `Unknown user: ${header}` });
    return;
  }
  (req as DemoRequest).demoUser = user;
  next();
}
