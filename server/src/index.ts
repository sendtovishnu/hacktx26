import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import { apiRouter } from './routes/index.js';

const port = Number(process.env.PORT ?? 3000);
const app = express();

app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.use('/api', apiRouter);

app.listen(port, '0.0.0.0', () => {
  console.log(`hacktx26 server listening on http://0.0.0.0:${port}`);
});
