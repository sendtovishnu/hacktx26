import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { closePool, query } from './client.js';
import { seed } from './seed.js';

const schemaPath = join(dirname(fileURLToPath(import.meta.url)), 'schema.sql');

async function reset(): Promise<void> {
  const schemaSql = readFileSync(schemaPath, 'utf8');
  console.log('Applying schema.sql …');
  await query(schemaSql);
  console.log('Seeding …');
  await seed();
  console.log('db:reset complete.');
}

reset()
  .catch((err) => {
    console.error(err instanceof Error ? err.message : err);
    process.exitCode = 1;
  })
  .finally(() => closePool());
