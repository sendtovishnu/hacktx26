import { Router, type Request } from 'express';
import { z } from 'zod';
import {
  acceptFriendRequest,
  closeFriendRequest,
  createInvite,
  getInviter,
  listFriendRequests,
  redeemInvite,
  sendFriendRequest,
  useDatabase,
} from '../db/index.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import { nudgeNewFriendship } from '../twinNudges.js';

export const friendRequestsRouter = Router();

const tierSchema = z.enum(['friend', 'close', 'closest']);

// Requests live in Postgres; the iOS app's MockAPI covers the no-server demo.
friendRequestsRouter.use(['/friend-requests', '/invites'], (_req, res, next) => {
  if (useDatabase()) {
    next();
    return;
  }
  res.status(503).json({ error: 'Friend requests need DATABASE_URL set on the server.' });
});

friendRequestsRouter.get('/friend-requests', requireDemoUser, async (req, res) => {
  res.json(await listFriendRequests((req as DemoRequest).demoUser.id));
});

friendRequestsRouter.post('/friend-requests', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z.object({ toUserId: z.string(), tier: tierSchema }).safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  const result = await sendFriendRequest(user.id, body.data.toUserId, body.data.tier);
  if (result.status === 'not_found') {
    res.status(404).json({ error: 'That person isn\'t on CloseMates.' });
    return;
  }
  if (result.status === 'already_friends') {
    res.status(409).json({ error: 'You\'re already friends.' });
    return;
  }
  // They had already asked you: you're friends now, so each twin may share a week it already read.
  if (result.status === 'accepted') nudgeNewFriendship(user, result.friend.friend);
  res.status(201).json(result);
});

friendRequestsRouter.post('/friend-requests/:id/accept', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z.object({ tier: tierSchema }).safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  const friend = await acceptFriendRequest(req.params.id, user.id, body.data.tier);
  if (!friend) {
    res.status(404).json({ error: 'That request is no longer pending.' });
    return;
  }
  // A refresh from before you were friends still counts: each twin may tell the other now.
  nudgeNewFriendship(user, friend.friend);
  res.json(friend);
});

friendRequestsRouter.post('/friend-requests/:id/decline', requireDemoUser, async (req, res) => {
  const ok = await closeFriendRequest(req.params.id, (req as DemoRequest).demoUser.id, 'declined');
  res.status(ok ? 200 : 404).json(ok ? { ok } : { error: 'That request is no longer pending.' });
});

friendRequestsRouter.delete('/friend-requests/:id', requireDemoUser, async (req, res) => {
  const ok = await closeFriendRequest(req.params.id, (req as DemoRequest).demoUser.id, 'cancelled');
  res.status(ok ? 200 : 404).json(ok ? { ok } : { error: 'That request is no longer pending.' });
});

friendRequestsRouter.post('/invites', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({
      tier: tierSchema,
      channel: z.enum(['sms', 'email', 'link']),
      contact: z.string().trim().max(200).optional(),
    })
    .safeParse(req.body);
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  const { tier, channel } = body.data;
  const contact = normalizeContact(channel, body.data.contact);
  if (channel !== 'link' && !contact) {
    res.status(400).json({ error: channel === 'email' ? 'Enter a valid email.' : 'Enter a valid phone number.' });
    return;
  }
  const code = await createInvite(user.id, tier, channel, contact);
  const url = `${publicBase(req)}/i/${code}`;
  const firstName = user.name.split(' ')[0];
  res.status(201).json({
    code,
    url,
    message: `${firstName} wants to be friends on CloseMates, so you can show up for each other. Join here: ${url}`,
  });
});

friendRequestsRouter.post('/invites/:code/redeem', requireDemoUser, async (req, res) => {
  const result = await redeemInvite(req.params.code, (req as DemoRequest).demoUser.id);
  const errors = {
    not_found: [404, 'That invite link isn\'t valid.'],
    used: [410, 'Someone else already used this invite. Ask for a new one.'],
    own_invite: [400, 'This is your own invite. Send it to a friend.'],
  } as const;
  if (result.status in errors) {
    const [code, error] = errors[result.status as keyof typeof errors];
    res.status(code).json({ error });
    return;
  }
  res.json(result);
});

/** Public page an invite link lands on. Its button opens the app with the code. */
export const inviteLandingRouter = Router();

inviteLandingRouter.get('/i/:code', async (req, res) => {
  const code = req.params.code;
  const inviter = useDatabase() && /^[\w-]{4,32}$/.test(code) ? await getInviter(code) : null;
  const appLink = `twin://invite/${encodeURIComponent(code)}`;
  const title = inviter ? `${escapeHtml(inviter.name.split(' ')[0])} invited you to CloseMates` : 'CloseMates invite';
  const body = inviter
    ? `<p>CloseMates quietly lets your closest people know when you could use them, with a real way to help.</p>
       <p><a class="button" href="${appLink}">Open in CloseMates</a></p>
       <p class="muted">Don't have CloseMates yet? Ask ${escapeHtml(inviter.name.split(' ')[0])} to get you on the beta, then come back and tap the button.</p>`
    : `<p>This invite link isn't valid anymore. Ask your friend for a new one.</p>`;
  res.status(inviter ? 200 : 404).type('html').send(`<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<style>
  body{font-family:ui-sans-serif,system-ui,sans-serif;max-width:28rem;margin:4rem auto;padding:0 1.25rem;line-height:1.5;color:#2b2420;background:#faf6f0;text-align:center}
  h1{font-size:1.6rem;margin-bottom:.5rem}
  .button{display:inline-block;margin-top:.5rem;padding:.85rem 1.6rem;border-radius:999px;background:#c8643b;color:#fff;text-decoration:none;font-weight:600}
  .muted{color:#7a6e66;font-size:.9rem}
</style>
</head>
<body><h1>${title}</h1>${body}</body>
</html>`);
});

function normalizeContact(channel: string, raw?: string): string | null {
  if (!raw) return null;
  if (channel === 'email') return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw) ? raw.toLowerCase() : null;
  if (channel === 'sms') {
    const digits = raw.replace(/[^\d+]/g, '');
    return digits.replace(/\D/g, '').length >= 7 ? digits : null;
  }
  return null;
}

/** Render and tunnels terminate https in front of the server, so trust the forwarded scheme. */
function publicBase(req: Request): string {
  const proto = req.header('x-forwarded-proto')?.split(',')[0] ?? req.protocol;
  return `${proto}://${req.get('host')}`;
}

function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}
