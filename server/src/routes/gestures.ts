import { Router } from 'express';
import { z } from 'zod';
import { getUserById } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { Gesture, Place } from '../types.js';

export const gesturesRouter = Router();

gesturesRouter.post('/gestures', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({
      nudgeId: z.string(),
      type: z.enum(['drop_off', 'hangout', 'message']),
      note: z.string().default(''),
      place: z
        .object({
          name: z.string(),
          address: z.string(),
          rating: z.number().optional(),
          openNow: z.boolean().optional(),
          mapsUrl: z.string().optional(),
        })
        .optional(),
      toUserId: z.string().optional(),
    })
    .safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }

  const gesture: Gesture = {
    id: `g_${Date.now()}`,
    nudgeId: body.data.nudgeId,
    fromFriend: user,
    type: body.data.type,
    place: body.data.place as Place | undefined,
    note: body.data.note,
    deliveredAt: new Date().toISOString(),
  };

  // Ensure toUser exists when provided (stub validation)
  if (body.data.toUserId && !getUserById(body.data.toUserId)) {
    res.status(404).json({ error: 'Recipient not found' });
    return;
  }

  res.status(201).json(gesture);
});
