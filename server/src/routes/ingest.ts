import { Router } from 'express';
import { z } from 'zod';
import { mockIngestPayload } from '../ai/index.js';
import { getEmailsFor, getEventsFor } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const ingestRouter = Router();

ingestRouter.post('/ingest/google', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const payload = mockIngestPayload(user.id);
  res.json({
    ok: true,
    source: 'google',
    userId: user.id,
    events: payload.events,
    emails: payload.emails,
    stub: true,
  });
});

ingestRouter.post('/ingest/ics', requireDemoUser, (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({ ics: z.string().optional(), url: z.string().url().optional() })
    .safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  res.json({
    ok: true,
    source: 'ics',
    userId: user.id,
    events: getEventsFor(user.id),
    emails: getEmailsFor(user.id),
    stub: true,
  });
});
