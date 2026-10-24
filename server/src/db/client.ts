import 'dotenv/config';
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

/** Shared pg Pool. Lazily created on first use so importing helpers is safe without DATABASE_URL. */
let pool: pg.Pool | null = null;

export function getPool(): pg.Pool {
  if (!pool) {
    // Managed Postgres (Tiger) often presents a chain Cursor/cloud egress
    // rewrites; rejectUnauthorized:false keeps demos working without shipping CA bundles.
    pool = new Pool({
      connectionString: requireDatabaseUrl(),
      ssl: { rejectUnauthorized: false },
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
