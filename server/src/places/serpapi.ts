import type { Place } from '../types.js';

const TIMEOUT_MS = 10_000;

interface LocalResult {
  title?: string;
  address?: string;
  rating?: number;
  open_state?: string;
  place_id?: string;
}

// "Open ⋅ Closes 10 PM" and "Closes soon" mean open; "Closed" and "Opens 7 AM" do not.
function isOpen(openState?: string): boolean | undefined {
  if (!openState) return undefined;
  return /^open(?!s)|^open 24|closes soon/i.test(openState.trim());
}

function mapsUrl(r: LocalResult): string {
  const q = new URLSearchParams({ api: '1', query: `${r.title ?? ''} ${r.address ?? ''}`.trim() });
  if (r.place_id) q.set('query_place_id', r.place_id);
  return `https://www.google.com/maps/search/?${q}`;
}

export async function searchMaps(query: string): Promise<Place[]> {
  const url = new URL('https://serpapi.com/search.json');
  url.search = new URLSearchParams({
    engine: 'google_maps',
    type: 'search',
    q: query,
    api_key: process.env.SERPAPI_KEY ?? '',
  }).toString();

  const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS) });
  const body = (await res.json()) as { local_results?: LocalResult[]; error?: string };
  if (!res.ok || body.error) throw new Error(`SerpApi ${res.status}: ${body.error ?? 'request failed'}`);

  return (body.local_results ?? [])
    .filter((r) => r.title && r.address)
    .map((r) => ({
      name: r.title!,
      address: r.address!,
      rating: r.rating,
      openNow: isOpen(r.open_state),
      mapsUrl: mapsUrl(r),
    }));
}
