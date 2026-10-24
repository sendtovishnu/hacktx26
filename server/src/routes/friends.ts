import { Router } from 'express';
import { z } from 'zod';
import { getFriendsFor, getUserById } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { FriendEntry, Tier } from '../types.js';

export const friendsRouter = Router();

const tierSchema = z.enum(['friend', 'close', 'closest']);

friendsRouter.get('/friends', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  res.json(getFriendsFor(user.id));
});

friendsRouter.post('/friends', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({ friendId: z.string(), tier: tierSchema })
    .safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  const friend = getUserById(body.data.friendId);
  if (!friend) {
    res.status(404).json({ error: 'Friend not found' });
    return;
  }
  const entry: FriendEntry = { friend, tier: body.data.tier as Tier };
  // Stub: echo accepted entry (no persistence yet)
  void user;
  res.status(201).json(entry);
});

friendsRouter.patch('/friends/:friendId', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const friendId = req.params.friendId;
  const body = z.object({ tier: tierSchema }).safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  const existing = getFriendsFor(user.id).find((f) => f.friend.id === friendId);
  const friend = existing?.friend ?? getUserById(friendId);
  if (!friend) {
    res.status(404).json({ error: 'Friend not found' });
    return;
  }
  res.json({ friend, tier: body.data.tier } satisfies FriendEntry);
});
