import { Router } from 'express';
import multer from 'multer';
import { z } from 'zod';
import {
  deletePhoto,
  getPhoto,
  getUser,
  listUsers,
  matchContacts,
  savePhoto,
  searchUsers,
  useDatabase,
} from '../db/index.js';
import { getUsers } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const usersRouter = Router();

usersRouter.get('/users', requireDemoUser, async (_req, res) => {
  if (useDatabase()) {
    res.json(await listUsers());
    return;
  }
  res.json(getUsers());
});

usersRouter.get('/me', requireDemoUser, async (req, res) => {
  const demoUserId = (req as DemoRequest).demoUser.id;
  if (useDatabase()) {
    const user = await getUser(demoUserId);
    if (!user) {
      res.status(404).json({ error: `Unknown demo user: ${demoUserId}` });
      return;
    }
    res.json(user);
    return;
  }
  res.json((req as DemoRequest).demoUser);
});

usersRouter.get('/users/search', requireDemoUser, async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.slice(0, 100) : '';
  if (!useDatabase()) {
    const term = q.toLowerCase();
    res.json(getUsers().filter((u) => u.name.toLowerCase().includes(term) || u.email.toLowerCase().includes(term)));
    return;
  }
  res.json(await searchUsers((req as DemoRequest).demoUser.id, q));
});

const contactsBody = z.object({
  phones: z.array(z.string().max(40)).max(5000).default([]),
  emails: z.array(z.string().max(200)).max(5000).default([]),
});

// Matches your phone's contacts against people on Twin. The lists are compared and dropped, never stored.
usersRouter.post('/contacts/match', requireDemoUser, async (req, res) => {
  const body = contactsBody.safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  if (!useDatabase()) {
    res.json([]);
    return;
  }
  res.json(await matchContacts((req as DemoRequest).demoUser.id, body.data.phones, body.data.emails));
});

const photoUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => cb(null, /^image\/(jpeg|png|heic)$/.test(file.mimetype)),
});

// Stored in Postgres, not on disk, because Render's disk is wiped on every deploy.
usersRouter.post('/me/photo', requireDemoUser, photoUpload.single('photo'), async (req, res) => {
  if (!req.file) {
    res.status(400).json({ error: 'Send a JPEG as the "photo" field.' });
    return;
  }
  if (!useDatabase()) {
    res.json((req as DemoRequest).demoUser);
    return;
  }
  res.json(await savePhoto((req as DemoRequest).demoUser.id, req.file.buffer));
});

usersRouter.delete('/me/photo', requireDemoUser, async (req, res) => {
  if (!useDatabase()) {
    res.json((req as DemoRequest).demoUser);
    return;
  }
  res.json(await deletePhoto((req as DemoRequest).demoUser.id));
});

// Public like any profile picture, so AsyncImage can load it without auth headers.
usersRouter.get('/photos/:userId', async (req, res) => {
  const jpeg = useDatabase() ? await getPhoto(req.params.userId) : null;
  if (!jpeg) {
    res.status(404).end();
    return;
  }
  // The URL carries ?v=<updated time>, so a new photo is a new URL and this can be cached.
  res.type('image/jpeg').set('Cache-Control', 'public, max-age=31536000, immutable').send(jpeg);
});
