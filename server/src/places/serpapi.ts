import type { Place } from '../types.js';

const TIMEOUT_MS = 10_000;

interface LocalResult {
  title?: string;
  address?: string;
  rating?: number;
  open_state?: string;
  place_id?: string;
  gps_coordinates?: { latitude?: number; longitude?: number };
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

export type LatLng = { lat: number; lng: number };

/** With `ll`, Google searches around that point; without it, a vague "near" can land in another city. */
export async function searchMaps(query: string, ll?: LatLng): Promise<Place[]> {
  const url = new URL('https://serpapi.com/search.json');
  const params: Record<string, string> = {
    engine: 'google_maps',
    type: 'search',
    q: query,
    api_key: process.env.SERPAPI_KEY ?? '',
  };
  if (ll) params.ll = `@${ll.lat.toFixed(5)},${ll.lng.toFixed(5)},14z`;
  url.search = new URLSearchParams(params).toString();

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
      lat: r.gps_coordinates?.latitude,
      lng: r.gps_coordinates?.longitude,
    }));
}
