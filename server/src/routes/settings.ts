import { Router } from 'express';
import { z } from 'zod';
import { updateSettings, useDatabase } from '../db/index.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { User } from '../types.js';

export const settingsRouter = Router();

settingsRouter.patch('/settings', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({
      surpriseOptIn: z.boolean().optional(),
      paused: z.boolean().optional(),
      preferences: z
        .object({
          coffeeOrder: z.string().optional(),
          likes: z.enum(['company', 'space']).optional(),
        })
        .optional(),
      homeLocation: z.string().optional(),
    })
    .safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }

  if (useDatabase()) {
    const updated = await updateSettings(user.id, {
      surpriseOptIn: body.data.surpriseOptIn,
      paused: body.data.paused,
      homeLocation: body.data.homeLocation,
      preferences: body.data.preferences,
    });
    if (!updated) {
      res.status(404).json({ error: `Unknown demo user: ${user.id}` });
      return;
    }
    res.json(updated);
    return;
  }

  const updated: User = {
    ...user,
    surpriseOptIn: body.data.surpriseOptIn ?? user.surpriseOptIn,
    paused: body.data.paused ?? user.paused,
    homeLocation: body.data.homeLocation ?? user.homeLocation,
    preferences: {
      ...user.preferences,
      ...body.data.preferences,
    },
  };
  res.json(updated);
});
