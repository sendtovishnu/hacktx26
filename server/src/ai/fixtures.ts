import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// mocks/ lives in server/; works whether the process starts in server/ or the repo root.
const dirs = [join(process.cwd(), 'mocks'), join(process.cwd(), 'server', 'mocks')];

export function fixture<T>(file: string): T {
  const dir = dirs.find((d) => existsSync(join(d, file)));
  if (!dir) throw new Error(`fixture not found: mocks/${file}`);
  return JSON.parse(readFileSync(join(dir, file), 'utf8')) as T;
}
