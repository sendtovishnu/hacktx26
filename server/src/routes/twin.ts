import { Router } from 'express';
import { decideNudges, extractSignals, filterEmails } from '../ai/index.js';
import {
  getDecisionsFor,
  getEmailsFor,
  getEventsFor,
  getFriendsFor,
  getSignalsFor,
} from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { TwinFriendInput } from '../types.js';

export const twinRouter = Router();

twinRouter.post('/twin/refresh', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const events = getEventsFor(user.id);
  const emails = filterEmails(getEmailsFor(user.id));
  const signals = await extractSignals(events, emails);
  const friends: TwinFriendInput[] = getFriendsFor(user.id).map((f) => ({
    friend: f.friend,
    tier: f.tier,
    // Demo: Jay has no free overlap tomorrow with Maya
    sharedFreeMinutes:
      user.id === 'u_maya' && f.friend.id === 'u_jay' ? 0 : 45,
  }));
  const decisions = await decideNudges(user, signals, friends);
  res.json({ signals, decisions, refreshedAt: new Date().toISOString() });
});

twinRouter.get('/twin', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const signals = getSignalsFor(user.id);
  const decisions = getDecisionsFor(user.id);
  res.json({
    userId: user.id,
    signals,
    decisions,
  });
});
