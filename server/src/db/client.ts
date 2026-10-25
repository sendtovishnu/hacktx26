import 'dotenv/config';
import { readFileSync } from 'node:fs';
import tls from 'node:tls';
import pg from 'pg';

const { Pool } = pg;

function requireDatabaseUrl(): string {
  const url = process.env.DATABASE_URL?.trim();
  if (!url) {
    throw new Error(
      'DATABASE_URL is not set. Copy server/.env.example to server/.env and set a Postgres connection string, then re-run npm run db:reset.',
    );
  }
  return url;
}

const TIMESCALE_CA = readFileSync(new URL('../../certs/timescale-ca.pem', import.meta.url), 'utf8');

/** Shared pg Pool. Lazily created on first use so importing helpers is safe without DATABASE_URL. */
let pool: pg.Pool | null = null;

export function getPool(): pg.Pool {
  if (!pool) {
    // sslmode in the URL would replace the ssl option below, so it is dropped here.
    const url = new URL(requireDatabaseUrl());
    url.searchParams.delete('sslmode');
    pool = new Pool({
      connectionString: url.toString(),
      // Full verification, hostname included. Tiger services without a public certificate
      // are signed by Timescale's own root (certs/timescale-ca.pem); public CAs stay trusted
      // so a later switch to a CA-signed certificate keeps working.
      ssl: { ca: [...tls.rootCertificates, TIMESCALE_CA] },
    });
  }
  return pool;
}

export async function query<T extends pg.QueryResultRow = pg.QueryResultRow>(
  text: string,
  params?: unknown[],
): Promise<pg.QueryResult<T>> {
  return getPool().query<T>(text, params);
}

export async function closePool(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}
