import { Router } from 'express';
import { z } from 'zod';
import { exchangeGoogleAuth } from '../google/index.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const authRouter = Router();

authRouter.post('/auth/google/exchange', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({ code: z.string().optional(), idToken: z.string().optional() })
    .safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }

  try {
    await exchangeGoogleAuth(user.id, body.data.code);
    res.json({ connected: true });
  } catch (err) {
    res.status(400).json({
      error: err instanceof Error ? err.message : 'Google exchange failed',
    });
  }
});
