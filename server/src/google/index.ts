/** Placeholder — Person A wires Google OAuth + Calendar/Gmail ingest later. */
export function googleStatus(): { configured: boolean } {
  return {
    configured: Boolean(
      process.env.GOOGLE_WEB_CLIENT_ID && process.env.GOOGLE_WEB_CLIENT_SECRET,
    ),
  };
}
