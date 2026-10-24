import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import { googleStatus, webRedirectUri } from './google/index.js';
import { apiRouter } from './routes/index.js';

const port = Number(process.env.PORT ?? 3000);
const app = express();

app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.get('/', (_req, res) => {
  const googleReady = googleStatus().configured;
  res.type('html').send(`<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>hacktx26 API</title>
<style>
  body{font-family:ui-sans-serif,system-ui,sans-serif;max-width:42rem;margin:3rem auto;padding:0 1.25rem;line-height:1.5;color:#111;background:#fafafa}
  code{background:#f3f4f6;padding:.1rem .35rem;border-radius:.25rem;font-size:.9em;word-break:break-all}
  a{color:#0b57d0}
  .card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:1.25rem 1.5rem;margin:1.25rem 0}
  .btn{display:inline-block;margin:.35rem .5rem .35rem 0;padding:.55rem 1rem;border-radius:8px;background:#0b57d0;color:#fff;text-decoration:none;font-weight:600}
  .btn.secondary{background:#fff;color:#0b57d0;border:1px solid #0b57d0}
  .muted{color:#667085;font-size:.95rem}
  h1{margin-bottom:.35rem}
</style>
</head>
<body>
  <h1>hacktx26</h1>
  <p class="muted">Digital Twin Friend Network API — cloud demo host for Person C’s iOS app.</p>

  <div class="card">
    <h2>Connect Google Calendar + Gmail</h2>
    <p>Sign in as a demo user in the browser. Tokens stay on the server; the iPhone only needs the demo user picker.</p>
    ${
      googleReady
        ? `<p>
      <a class="btn" href="/api/auth/google/start?user=u_maya">Connect as Maya</a>
      <a class="btn secondary" href="/api/auth/google/start?user=u_jay">Jay</a>
      <a class="btn secondary" href="/api/auth/google/start?user=u_priya">Priya</a>
    </p>
    <p class="muted">Google may warn the app is unverified — test users tap <strong>Advanced → Continue</strong>.</p>
    <p class="muted">Redirect URI (must be listed on the Web OAuth client):<br><code>${webRedirectUri()}</code></p>`
        : `<p class="muted">Google OAuth is not configured on this server yet.</p>`
    }
  </div>

  <div class="card">
    <h2>Person C — point the iOS app here</h2>
    <p>Base URL: <code>${process.env.PUBLIC_BASE_URL?.replace(/\/$/, '') || '(this host)'}</code></p>
    <ol>
      <li>Privacy → Developer: turn off <strong>Use mock data</strong></li>
      <li>Set server URL to the base URL above (or the current Cloudflare tunnel)</li>
      <li>Pick Maya / Jay / Priya in the demo user picker</li>
      <li>After someone connects Google above, Twin → <strong>Refresh my twin</strong></li>
    </ol>
    <p class="muted">You do not need to rebuild with Google client IDs for this cloud path — browser connect handles Calendar/Gmail.</p>
  </div>

  <div class="card">
    <h2>API checks</h2>
    <ul>
      <li><a href="/health">/health</a></li>
      <li><a href="/api/users">/api/users</a></li>
    </ul>
  </div>
</body>
</html>`);
});

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.use('/api', apiRouter);

app.listen(port, '0.0.0.0', () => {
  console.log(`hacktx26 server listening on http://0.0.0.0:${port}`);
  if (googleStatus().configured) {
    console.log(`Google web redirect URI: ${webRedirectUri()}`);
  }
});
