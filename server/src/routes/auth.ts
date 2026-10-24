import { Router } from 'express';
import { z } from 'zod';
import { getUser, useDatabase } from '../db/index.js';
import {
  exchangeGoogleAuth,
  exchangeGoogleAuthWeb,
  getGoogleAuthUrl,
  googleStatus,
  ingestGoogle,
  webRedirectUri,
} from '../google/index.js';
import { getUserById as getMockUser } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const authRouter = Router();

const DEMO_USER_IDS = ['u_maya', 'u_jay', 'u_priya'] as const;

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

/** Start browser Google OAuth for a demo user. */
authRouter.get('/auth/google/start', (req, res) => {
  const userId = String(req.query.user ?? 'u_maya');
  if (!DEMO_USER_IDS.includes(userId as (typeof DEMO_USER_IDS)[number])) {
    res.status(400).type('html').send(errorPage('Pick a demo user: u_maya, u_jay, or u_priya.'));
    return;
  }
  if (!googleStatus().configured) {
    res
      .status(503)
      .type('html')
      .send(
        errorPage(
          'Google OAuth is not configured. Set GOOGLE_WEB_CLIENT_ID and GOOGLE_WEB_CLIENT_SECRET in server/.env.',
        ),
      );
    return;
  }
  try {
    res.redirect(getGoogleAuthUrl(userId));
  } catch (err) {
    res
      .status(500)
      .type('html')
      .send(errorPage(err instanceof Error ? err.message : 'Could not start Google sign-in'));
  }
});

/**
 * OAuth callback from Google (browser). Exchanges the code, stores tokens,
 * pulls calendar + Gmail, then shows a success page.
 */
authRouter.get('/auth/google/callback', async (req, res) => {
  const error = typeof req.query.error === 'string' ? req.query.error : '';
  if (error) {
    res
      .status(400)
      .type('html')
      .send(errorPage(`Google denied access: ${error}. ${req.query.error_description ?? ''}`));
    return;
  }

  const code = typeof req.query.code === 'string' ? req.query.code : '';
  const userId = typeof req.query.state === 'string' ? req.query.state : '';
  if (!code || !DEMO_USER_IDS.includes(userId as (typeof DEMO_USER_IDS)[number])) {
    res
      .status(400)
      .type('html')
      .send(errorPage('Missing code or demo user state from Google. Start again from the home page.'));
    return;
  }

  const user = useDatabase() ? await getUser(userId) : getMockUser(userId) ?? null;
  if (!user) {
    res.status(404).type('html').send(errorPage(`Unknown demo user ${userId}`));
    return;
  }

  try {
    await exchangeGoogleAuthWeb(userId, code);
    const ingest = await ingestGoogle(userId);
    res.type('html').send(
      successPage({
        name: user.name,
        userId,
        events: ingest.events,
        emails: ingest.emails,
        source: ingest.source,
      }),
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Google connect failed';
    const hint = /redirect_uri/i.test(message)
      ? ` Add this exact Authorized redirect URI on your Google Web client: <code>${webRedirectUri()}</code>`
      : '';
    res.status(400).type('html').send(errorPage(`${message}.${hint}`));
  }
});

function layout(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<style>
  body{font-family:ui-sans-serif,system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1.25rem;line-height:1.5;color:#111;background:#fafafa}
  code{background:#f3f4f6;padding:.1rem .35rem;border-radius:.25rem;font-size:.9em;word-break:break-all}
  a{color:#0b57d0}
  .card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:1.25rem 1.5rem;margin:1rem 0}
  .ok{color:#067647}.bad{color:#b42318}
</style>
</head>
<body>${body}</body>
</html>`;
}

function errorPage(message: string): string {
  return layout(
    'Google connect failed',
    `<h1 class="bad">Could not connect Google</h1>
     <div class="card"><p>${message}</p>
     <p><a href="/">Back home</a></p></div>`,
  );
}

function successPage(opts: {
  name: string;
  userId: string;
  events: number;
  emails: number;
  source: string;
}): string {
  return layout(
    'Google connected',
    `<h1 class="ok">Connected</h1>
     <div class="card">
       <p><strong>${opts.name}</strong> (<code>${opts.userId}</code>) is linked to Google.</p>
       <p>Synced <strong>${opts.events}</strong> calendar events and <strong>${opts.emails}</strong> emails
          (source: <code>${opts.source}</code>).</p>
       <p>The iOS app can use this same account via <code>X-Demo-User: ${opts.userId}</code> —
          tap Refresh my twin next.</p>
       <p><a href="/">Connect another demo user</a></p>
     </div>`,
  );
}
