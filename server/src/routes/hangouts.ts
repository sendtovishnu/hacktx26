import { Router } from 'express';
import { z } from 'zod';
import { getFriends, useDatabase } from '../db/index.js';
import { planHangout } from '../hangouts.js';
import { getFriendsFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const hangoutsRouter = Router();

// "I just want to hang out": ideas and times for you and a friend. Any circle, any week.
hangoutsRouter.post('/friends/:friendId/hangout', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const friends = useDatabase() ? await getFriends(user.id) : getFriendsFor(user.id);
  const entry = friends.find((f) => f.friend.id === req.params.friendId);
  if (!entry) {
    res.status(404).json({ error: 'You can plan a hangout once you\'re friends.' });
    return;
  }
  const avoid = z.array(z.string().max(80)).max(16).catch([]).parse(req.body?.avoid);
  res.json(await planHangout(user, entry.friend, avoid));
});
