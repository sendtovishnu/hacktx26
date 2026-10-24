import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import {
  getUser,
  upsertGoogleUser,
  useDatabase,
} from '../db/index.js';
import {
  exchangeGoogleAuth,
  exchangeGoogleAuthWeb,
  exchangeIosCode,
  exchangeWebCode,
  fetchGoogleProfile,
  getGoogleAuthUrl,
  googleStatus,
  hasRealGoogleTokens,
  ingestGoogle,
  storeGoogleTokens,
  webRedirectUri,
  type GoogleTokenSet,
} from '../google/index.js';
import { getUserById as getMockUser } from '../mocks.js';
import { requireDemoUser, type DemoRequest } from '../middleware.js';
import type { User } from '../types.js';

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

function setSessionCookie(res: Response, userId: string): void {
  res.append(
    'Set-Cookie',
    `session_user=${encodeURIComponent(userId)}; Path=/; Max-Age=${60 * 60 * 24 * 30}; HttpOnly; SameSite=Lax; Secure`,
  );
  res.append(
    'Set-Cookie',
    `oauth_demo_user=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax; Secure`,
  );
}

async function loginWithGoogleTokens(
  tokens: GoogleTokenSet,
): Promise<{ user: User; created: boolean; ingest: { events: number; emails: number; source: string } }> {
  if (!tokens.access_token) {
    throw new Error('Google did not return an access token');
  }
  if (!useDatabase()) {
    throw new Error('DATABASE_URL is required for Continue with Google');
  }
  const profile = await fetchGoogleProfile(tokens.access_token);
  const { user, created } = await upsertGoogleUser(profile);
  await storeGoogleTokens(user.id, tokens);
  const ingest = await ingestGoogle(user.id);
  return { user, created, ingest };
}

/** iOS / API: exchange a Google auth code, create or find the user, sync calendar+mail. */
authRouter.post('/auth/google/continue', async (req, res) => {
  const body = z
    .object({
      code: z.string().optional(),
      serverAuthCode: z.string().optional(),
      /** ios = empty redirect_uri (native SDK); web = registered redirect URI */
      flow: z.enum(['ios', 'web']).optional(),
    })
    .safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  const code = (body.data.code ?? body.data.serverAuthCode ?? '').trim();
  if (!code) {
    res.status(400).json({ error: 'Missing code / serverAuthCode' });
    return;
  }
  if (!googleStatus().configured) {
    res.status(503).json({ error: 'Google OAuth is not configured on the server' });
    return;
  }

  try {
    const flow = body.data.flow ?? 'ios';
    const tokens =
      flow === 'web' ? await exchangeWebCode(code) : await exchangeIosCode(code);
    const result = await loginWithGoogleTokens(tokens);
    setSessionCookie(res, result.user.id);
    res.json({
      connected: true,
      created: result.created,
      user: result.user,
      events: result.ingest.events,
      emails: result.ingest.emails,
      source: result.ingest.source,
    });
  } catch (err) {
    res.status(400).json({
      error: err instanceof Error ? err.message : 'Google continue failed',
    });
  }
});

/** Attach Google to an already signed-in demo/API user (Account → Connect). */
authRouter.post('/auth/google/exchange', requireDemoUser, async (req, res) => {
  const user = (req as DemoRequest).demoUser;
  const body = z
    .object({
      code: z.string().optional(),
      serverAuthCode: z.string().optional(),
      idToken: z.string().optional(),
      flow: z.enum(['ios', 'web']).optional(),
    })
    .safeParse(req.body ?? {});
  if (!body.success) {
    res.status(400).json({ error: body.error.flatten() });
    return;
  }
  const code = (body.data.code ?? body.data.serverAuthCode ?? '').trim();

  try {
    if (body.data.flow === 'web' && code) {
      await exchangeGoogleAuthWeb(user.id, code);
    } else {
      await exchangeGoogleAuth(user.id, code || undefined);
    }
    res.json({ connected: true });
  } catch (err) {
    res.status(400).json({
      error: err instanceof Error ? err.message : 'Google exchange failed',
    });
  }
});

/**
 * Start browser Google OAuth.
 * ?user=u_maya|u_jay|u_priya attaches to a demo user.
 * No user (or user=signup) = Continue with Google → create/login a real account.
 */
authRouter.get('/auth/google/start', (req, res) => {
  const raw = firstQuery(req.query.user) || 'signup';
  const state = isDemoUserId(raw) ? raw : 'signup';
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
    res.setHeader(
      'Set-Cookie',
      `oauth_demo_user=${encodeURIComponent(state)}; Path=/; Max-Age=600; HttpOnly; SameSite=Lax; Secure`,
    );
    res.redirect(getGoogleAuthUrl(state));
  } catch (err) {
    res
      .status(500)
      .type('html')
      .send(errorPage(err instanceof Error ? err.message : 'Could not start Google sign-in'));
  }
});

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
  const stateRaw = firstQuery(req.query.state) || readCookie(req, 'oauth_demo_user');
  const isSignup = !stateRaw || stateRaw === 'signup' || !isDemoUserId(stateRaw);
  const demoUserId = isDemoUserId(stateRaw) ? stateRaw : '';

  console.log('[google/callback]', {
    hasCode: Boolean(code),
    state: stateRaw || '(none)',
    mode: isSignup ? 'signup' : 'demo',
    keys: Object.keys(req.query),
    redirectUri: webRedirectUri(),
  });

  if (!code) {
    if (demoUserId && (await hasRealGoogleTokens(demoUserId))) {
      const user = useDatabase() ? await getUser(demoUserId) : getMockUser(demoUserId) ?? null;
      if (user) {
        res.type('html').send(
          successPage({
            name: user.name,
            userId: user.id,
            events: 0,
            emails: 0,
            source: 'google',
            alreadyConnected: true,
            created: false,
          }),
        );
        return;
      }
    }
    res.status(400).type('html').send(
      errorPage(
        `Google came back without an auth code (query keys: <code>${Object.keys(req.query).join(', ') || '(none)'}</code>).
         Add this Authorized redirect URI on the Web client:<br><code>${webRedirectUri()}</code><br><br>
         Then start again from the <a href="/">home page</a> (don’t refresh this URL).`,
      ),
    );
    return;
  }

  try {
    if (isSignup) {
      const tokens = await exchangeWebCode(code);
      const result = await loginWithGoogleTokens(tokens);
      setSessionCookie(res, result.user.id);
      res.type('html').send(
        successPage({
          name: result.user.name,
          userId: result.user.id,
          events: result.ingest.events,
          emails: result.ingest.emails,
          source: result.ingest.source,
          created: result.created,
        }),
      );
      return;
    }

    // Demo-user attach path (Maya / Jay / Priya)
    const user = useDatabase()
      ? await getUser(demoUserId)
      : getMockUser(demoUserId) ?? null;
    if (!user) {
      res.status(404).type('html').send(errorPage(`Unknown demo user ${demoUserId}`));
      return;
    }
    await exchangeGoogleAuthWeb(demoUserId, code);
    const ingest = await ingestGoogle(demoUserId);
    setSessionCookie(res, demoUserId);
    res.type('html').send(
      successPage({
        name: user.name,
        userId: demoUserId,
        events: ingest.events,
        emails: ingest.emails,
        source: ingest.source,
        created: false,
      }),
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Google connect failed';
    const hint = /redirect_uri/i.test(message)
      ? `<br><br>Add this exact Authorized redirect URI:<br><code>${webRedirectUri()}</code>`
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
     <p><a href="/">Back home</a> · <a href="/api/auth/google/start">Continue with Google</a></p></div>`,
  );
}

function successPage(opts: {
  name: string;
  userId: string;
  events: number;
  emails: number;
  source: string;
  created: boolean;
  alreadyConnected?: boolean;
}): string {
  const headline = opts.created ? 'Account created' : 'Signed in';
  const syncLine = opts.alreadyConnected
    ? `<p>Google is already connected. Use the iOS app with this user id.</p>`
    : `<p>Synced <strong>${opts.events}</strong> calendar events and <strong>${opts.emails}</strong> emails
          (source: <code>${opts.source}</code>).</p>`;
  return layout(
    headline,
    `<h1 class="ok">${headline}</h1>
     <div class="card">
       <p><strong>${opts.name}</strong></p>
       <p>User id for the app: <code>${opts.userId}</code></p>
       ${syncLine}
       <p>In the iOS app, set the demo/user id to that value (or use Continue with Google there), then open Twin.</p>
       <p><a href="/">Home</a> · <a href="/api/auth/google/start">Sign in as someone else</a></p>
     </div>`,
  );
}
