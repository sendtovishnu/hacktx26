import { Router } from 'express';
import { z } from 'zod';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const authRouter = Router();

authRouter.post('/auth/google/exchange', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({ code: z.string().optional(), idToken: z.string().optional() })
    .safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  res.json({
    ok: true,
    userId: user.id,
    provider: 'google',
    stub: true,
    message: 'Google token exchange stub — Person A wires real OAuth later.',
  });
});
