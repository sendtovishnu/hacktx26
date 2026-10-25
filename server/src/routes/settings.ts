import { Router } from 'express';
import { z } from 'zod';
import { setLocationSharing, setUserLocation, updateSettings, useDatabase } from '../db/index.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { User } from '../types.js';

export const settingsRouter = Router();

settingsRouter.patch('/settings', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({
      surpriseOptIn: z.boolean().optional(),
      // Same setting as surpriseOptIn, under the name the app shows.
      openToSupport: z.boolean().optional(),
      surprisesOn: z.boolean().optional(),
      phone: z.string().trim().max(30).nullable().optional(),
      interests: z.array(z.string().trim().min(1).max(40)).max(40).optional(),
      // From the app's location permission; used only to search near the person, never shown to friends.
      locationSharing: z.enum(['nobody', 'closest', 'close', 'friends']).optional(),
      location: z
        .object({ lat: z.number().min(-90).max(90), lng: z.number().min(-180).max(180), label: z.string().max(80).optional() })
        .optional(),
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
    if (body.data.location) await setUserLocation(user.id, body.data.location);
    if (body.data.locationSharing) await setLocationSharing(user.id, body.data.locationSharing);
    const updated = await updateSettings(user.id, {
      surpriseOptIn: body.data.openToSupport ?? body.data.surpriseOptIn,
      surprisesOn: body.data.surprisesOn,
      phone: body.data.phone === '' ? null : body.data.phone,
      interests: body.data.interests,
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
