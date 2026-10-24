import { Router } from 'express';
import { z } from 'zod';
import { getFriends, upsertFriendship, useDatabase } from '../db/index.js';
import { getFriendsFor, getUserById } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { FriendEntry, Tier } from '../types.js';

export const friendsRouter = Router();

const tierSchema = z.enum(['friend', 'close', 'closest']);

friendsRouter.get('/friends', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  if (useDatabase()) {
    res.json(await getFriends(user.id));
    return;
  }
  res.json(getFriendsFor(user.id));
});

friendsRouter.post('/friends', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({ friendId: z.string(), tier: tierSchema })
    .safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }

  if (useDatabase()) {
    const entry = await upsertFriendship(user.id, body.data.friendId, body.data.tier);
    if (!entry) {
      res.status(404).json({ error: 'Friend not found' });
      return;
    }
    res.status(201).json(entry);
    return;
  }

  const friend = getUserById(body.data.friendId);
  if (!friend) {
    res.status(404).json({ error: 'Friend not found' });
    return;
  }
  const entry: FriendEntry = { friend, tier: body.data.tier as Tier };
  res.status(201).json(entry);
});

friendsRouter.patch('/friends/:friendId', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const friendId = req.params.friendId;
  const body = z.object({ tier: tierSchema }).safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }

  if (useDatabase()) {
    const entry = await upsertFriendship(user.id, friendId, body.data.tier);
    if (!entry) {
      res.status(404).json({ error: 'Friend not found' });
      return;
    }
    res.json(entry);
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
