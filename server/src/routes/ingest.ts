import { Router } from 'express';
import multer from 'multer';
import {
  ingestGoogle,
  parseIcs,
  storeIcsEvents,
} from '../google/index.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const ingestRouter = Router();

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const name = file.originalname?.toLowerCase() ?? '';
    const ok =
      name.endsWith('.ics') ||
      file.mimetype === 'text/calendar' ||
      file.mimetype === 'application/octet-stream' ||
      file.mimetype === 'text/plain';
    if (ok) cb(null, true);
    else cb(new Error('Only .ics calendar files are accepted'));
  },
});

ingestRouter.post('/ingest/google', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  try {
    const result = await ingestGoogle(user.id);
    res.json({
      ok: true,
      userId: user.id,
      events: result.events,
      emails: result.emails,
      source: result.source,
    });
  } catch (err) {
    res.status(500).json({
      error: err instanceof Error ? err.message : 'Google ingest failed',
    });
  }
});

ingestRouter.post(
  '/ingest/ics',
  requireDemoUser,
  (req, res, next) => {
    upload.single('file')(req, res, (err) => {
      if (err) {
        res.status(400).json({
          error: err instanceof Error ? err.message : 'Upload failed',
        });
        return;
      }
      next();
    });
  },
  async (req, res) => {
    const user = (req as DemoRequest).demoUser;
    const file = req.file;
    if (!file?.buffer?.length) {
      res.status(400).json({
        error: 'Missing multipart file field "file" (.ics)',
      });
      return;
    }

    try {
      const events = parseIcs(file.buffer);
      const stored = await storeIcsEvents(user.id, events);
      res.json({
        ok: true,
        source: 'ics',
        userId: user.id,
        events: stored,
      });
    } catch (err) {
      res.status(400).json({
        error: err instanceof Error ? err.message : 'ICS parse failed',
      });
    }
  },
);
