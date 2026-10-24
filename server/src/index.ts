import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import { apiRouter } from './routes/index.js';

const port = Number(process.env.PORT ?? 3000);
const app = express();

app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.get('/', (_req, res) => {
  res.type('html').send(`<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>hacktx26 API</title>
<style>
  body{font-family:ui-sans-serif,system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1.25rem;line-height:1.5;color:#111}
  code{background:#f3f4f6;padding:.1rem .35rem;border-radius:.25rem}
  a{color:#0b57d0}
</style>
</head>
<body>
  <h1>hacktx26 API</h1>
  <p>Server is up. This is the backend for the Digital Twin Friend Network — there is no web UI here.</p>
  <p>Point the iOS app at this base URL and call <code>/api/*</code> with header <code>X-Demo-User: u_maya</code> (or <code>u_jay</code> / <code>u_priya</code>).</p>
  <ul>
    <li><a href="/health">/health</a></li>
    <li><a href="/api/users">/api/users</a></li>
    <li><a href="/api/me">/api/me</a> (needs <code>X-Demo-User</code>)</li>
  </ul>
</body>
</html>`);
});

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.use('/api', apiRouter);

app.listen(port, '0.0.0.0', () => {
  console.log(`hacktx26 server listening on http://0.0.0.0:${port}`);
});
