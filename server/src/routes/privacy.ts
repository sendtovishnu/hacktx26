import { Router } from 'express';
import {
  getFriends,
  hasIcsEvents,
  listActedNudgesFromUser,
  listProviders,
  useDatabase,
} from '../db/index.js';
import { getFriendsFor, getNudgesFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const privacyRouter = Router();

privacyRouter.get('/privacy', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;

  if (useDatabase()) {
    const providers = await listProviders(user.id);
    const friends = await getFriends(user.id);
    const nudgeLog = await listActedNudgesFromUser(user.id);
    res.json({
      sources: {
        google: providers.includes('google'),
        ics: providers.includes('ics') || (await hasIcsEvents(user.id)),
      },
      friends,
      nudgeLog,
    });
    return;
  }

  const friends = getFriendsFor(user.id);
  const nudgeLog = getNudgesFor(user.id).filter(
    (n) => n.fromUser.id === user.id && n.status === 'acted',
  );
  res.json({
    sources: { google: false, ics: false },
    friends,
    nudgeLog,
  });
});
