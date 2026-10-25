import { Router } from 'express';
import { z } from 'zod';
import { areFriends, friendLocations, getFriends, upsertFriendship, useDatabase } from '../db/index.js';
import { getFriendsFor, getUserById } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { FriendEntry } from '../types.js';

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

// Friendships are created by accepting a request (routes/friendRequests.ts), never directly.

friendsRouter.patch('/friends/:friendId', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const friendId = req.params.friendId;
  const body = z.object({ tier: tierSchema }).safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }

  if (useDatabase()) {
    // Changing a circle never creates a friendship; that takes an accepted request.
    if (!(await areFriends(user.id, friendId))) {
      res.status(404).json({ error: 'Friend not found' });
      return;
    }
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

// Map tab: friends whose sharing setting covers the circle they put you in.
friendsRouter.get('/friends/locations', requireDemoUser, async (req, res) => {
  if (!useDatabase()) {
    res.json([]);
    return;
  }
  res.json(await friendLocations((req as DemoRequest).demoUser.id));
});
