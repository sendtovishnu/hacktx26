/** Placeholder — Person A wires Postgres + plain SQL later. */
export function dbStatus(): { configured: boolean } {
  return { configured: Boolean(process.env.DATABASE_URL) };
}
