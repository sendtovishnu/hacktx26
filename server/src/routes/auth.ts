import { Router, type Request } from 'express';
import { z } from 'zod';
import { getUser, useDatabase } from '../db/index.js';
import {
  exchangeGoogleAuth,
  exchangeGoogleAuthWeb,
  getGoogleAuthUrl,
  googleStatus,
  hasRealGoogleTokens,
  ingestGoogle,
  webRedirectUri,
} from '../google/index.js';
import { getUserById as getMockUser } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';

export const authRouter = Router();

const DEMO_USER_IDS = ['u_maya', 'u_jay', 'u_priya'] as const;
type DemoUserId = (typeof DEMO_USER_IDS)[number];

function isDemoUserId(value: string): value is DemoUserId {
  return (DEMO_USER_IDS as readonly string[]).includes(value);
}

function firstQuery(value: unknown): string {
  if (typeof value === 'string') return value;
  if (Array.isArray(value) && typeof value[0] === 'string') return value[0];
  return '';
}

function readCookie(req: Request, name: string): string {
  const raw = req.headers.cookie ?? '';
  const match = raw.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1]) : '';
}

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
  const userId = firstQuery(req.query.user) || 'u_maya';
  if (!isDemoUserId(userId)) {
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
    // Cookie survives Google's redirect even if `state` is dropped.
    res.setHeader(
      'Set-Cookie',
      `oauth_demo_user=${encodeURIComponent(userId)}; Path=/; Max-Age=600; HttpOnly; SameSite=Lax; Secure`,
    );
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
  const qError = firstQuery(req.query.error);
  const qErrorDesc = firstQuery(req.query.error_description);
  if (qError) {
    res
      .status(400)
      .type('html')
      .send(errorPage(`Google denied access: ${qError}. ${qErrorDesc}`));
    return;
  }

  const code = firstQuery(req.query.code);
  const stateUser = firstQuery(req.query.state);
  const cookieUser = readCookie(req, 'oauth_demo_user');
  const userId = isDemoUserId(stateUser)
    ? stateUser
    : isDemoUserId(cookieUser)
      ? cookieUser
      : '';

  console.log('[google/callback]', {
    hasCode: Boolean(code),
    state: stateUser || '(none)',
    cookie: cookieUser || '(none)',
    keys: Object.keys(req.query),
    redirectUri: webRedirectUri(),
  });

  if (!code) {
    // Refresh after a successful connect, or opening the callback URL cold.
    if (userId && (await hasRealGoogleTokens(userId))) {
      const user = useDatabase() ? await getUser(userId) : getMockUser(userId) ?? null;
      if (user) {
        res.type('html').send(
          successPage({
            name: user.name,
            userId,
            events: 0,
            emails: 0,
            source: 'google',
            alreadyConnected: true,
          }),
        );
        return;
      }
    }
    res.status(400).type('html').send(
      errorPage(
        `Google came back without an auth code (query keys: <code>${Object.keys(req.query).join(', ') || '(none)'}</code>).
         This usually means the redirect URI is wrong, or the page was refreshed after the one-time code was used.<br><br>
         In Google Cloud → Web client → <strong>Authorized redirect URIs</strong>, add exactly:<br>
         <code>${webRedirectUri()}</code><br><br>
         Then start again from the <a href="/">home page</a> (don’t refresh this URL).`,
      ),
    );
    return;
  }

  if (!userId) {
    res.status(400).type('html').send(
      errorPage(
        `Got a Google code but no demo user (state=<code>${stateUser || '(empty)'}</code>, cookie=<code>${cookieUser || '(empty)'}</code>).
         Start again from the <a href="/">home page</a> and use Connect as Maya / Jay / Priya.`,
      ),
    );
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
    res.setHeader(
      'Set-Cookie',
      'oauth_demo_user=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax; Secure',
    );
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
      ? `<br><br>Add this exact Authorized redirect URI on your Google Web client:<br><code>${webRedirectUri()}</code>`
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
     <p><a href="/">Back home</a> · <a href="/api/auth/google/start?user=u_maya">Try Maya again</a></p></div>`,
  );
}

function successPage(opts: {
  name: string;
  userId: string;
  events: number;
  emails: number;
  source: string;
  alreadyConnected?: boolean;
}): string {
  const syncLine = opts.alreadyConnected
    ? `<p>Google is already connected for this demo user. Open the iOS app and tap <strong>Refresh my twin</strong>.</p>`
    : `<p>Synced <strong>${opts.events}</strong> calendar events and <strong>${opts.emails}</strong> emails
          (source: <code>${opts.source}</code>).</p>`;
  return layout(
    'Google connected',
    `<h1 class="ok">Connected</h1>
     <div class="card">
       <p><strong>${opts.name}</strong> (<code>${opts.userId}</code>) is linked to Google.</p>
       ${syncLine}
       <p>The iOS app uses this via <code>X-Demo-User: ${opts.userId}</code>.</p>
       <p><a href="/">Connect another demo user</a></p>
     </div>`,
  );
}
