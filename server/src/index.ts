import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import { googleStatus, webRedirectUri } from './google/index.js';
import { apiRouter } from './routes/index.js';

const port = Number(process.env.PORT ?? 3000);
const app = express();
const publicBase = (process.env.PUBLIC_BASE_URL ?? '').replace(/\/$/, '');

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '2mb' }));

app.get('/', (_req, res) => {
  const googleReady = googleStatus().configured;
  res.type('html').send(`<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>hacktx26</title>
<style>
  body{font-family:ui-sans-serif,system-ui,sans-serif;max-width:42rem;margin:3rem auto;padding:0 1.25rem;line-height:1.5;color:#111;background:#fafafa}
  code{background:#f3f4f6;padding:.1rem .35rem;border-radius:.25rem;font-size:.9em;word-break:break-all}
  a{color:#0b57d0}
  .card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:1.25rem 1.5rem;margin:1.25rem 0}
  .btn{display:inline-block;margin:.35rem .5rem .35rem 0;padding:.7rem 1.15rem;border-radius:10px;background:#0b57d0;color:#fff;text-decoration:none;font-weight:600}
  .btn.secondary{background:#fff;color:#0b57d0;border:1px solid #0b57d0}
  .muted{color:#667085;font-size:.95rem}
  h1{margin-bottom:.35rem}
</style>
</head>
<body>
  <h1>Twin</h1>
  <p class="muted">Digital Twin Friend Network — sign in with Google to create your account and sync Calendar + Gmail.</p>

  <div class="card">
    <h2>Continue with Google</h2>
    <p>Opens Google sign-in, creates a Twin user from your Google profile (or signs you back in), then syncs the next 7 days of calendar and email.</p>
    ${
      googleReady
        ? `<p><a class="btn" href="/api/auth/google/start">Continue with Google</a></p>
    <p class="muted">Unverified app warning is normal — tap <strong>Advanced → Continue</strong>.</p>
    <p class="muted">Redirect URI on the Web client must be:<br><code>${webRedirectUri()}</code></p>`
        : `<p class="muted">Google OAuth is not configured on this server yet.</p>`
    }
  </div>

  <div class="card">
    <h2>HackTX demo users</h2>
    <p class="muted">Optional: attach Google to a seeded persona instead of creating a new account.</p>
    ${
      googleReady
        ? `<p>
      <a class="btn secondary" href="/api/auth/google/start?user=u_maya">Maya</a>
      <a class="btn secondary" href="/api/auth/google/start?user=u_jay">Jay</a>
      <a class="btn secondary" href="/api/auth/google/start?user=u_priya">Priya</a>
    </p>`
        : ''
    }
  </div>

  <div class="card">
    <h2>Person C — iOS app</h2>
    <p>Base URL: <code>${publicBase || '(this host)'}</code></p>
    <ol>
      <li>Turn off mock data; set the server URL above</li>
      <li>On the sign-in screen tap <strong>Continue with Google</strong> (creates a real user), or pick a demo chip</li>
      <li>Twin → Refresh my twin</li>
    </ol>
  </div>

  <div class="card">
    <h2>API</h2>
    <ul>
      <li><a href="/health">/health</a></li>
      <li><a href="/api/users">/api/users</a></li>
      <li><code>POST /api/auth/google/continue</code> — <code>{ "serverAuthCode": "…" }</code> or <code>{ "code": "…", "flow": "web" }</code></li>
    </ul>
  </div>
</body>
</html>`);
});

app.get('/health', (_req, res) => {
  res.json({ ok: true, google: googleStatus().configured });
});

app.use('/api', apiRouter);

app.listen(port, '0.0.0.0', () => {
  console.log(`hacktx26 server listening on http://0.0.0.0:${port}`);
  if (googleStatus().configured) {
    console.log(`Google web redirect URI: ${webRedirectUri()}`);
  }
});
