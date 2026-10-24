import { Router } from 'express';
import { getFriendsFor } from '../mocks.js';
import { canShareContext } from '../rules/index.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const privacyRouter = Router();

privacyRouter.get('/privacy', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const friends = getFriendsFor(user.id).map((f) => ({
    friendId: f.friend.id,
    tier: f.tier,
    sharedContext: canShareContext(f.tier),
  }));
  res.json({
    userId: user.id,
    paused: user.paused,
    surpriseOptIn: user.surpriseOptIn,
    friends,
  });
});
