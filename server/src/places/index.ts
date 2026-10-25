import { fixture } from '../ai/fixtures.js';
import { useMocks } from '../ai/llm.js';
import type { Place } from '../types.js';
import { searchMaps, type LatLng } from './serpapi.js';

export type { LatLng };

type Kind = 'coffee' | 'matcha' | 'food' | 'dessert';

const QUERY: Record<Kind, string> = { coffee: 'coffee', matcha: 'matcha cafe', food: 'food', dessert: 'dessert' };
const cache = new Map<string, Place[]>();

function fallback(kind: Kind): Place[] {
  try {
    return fixture<Place[]>(`places_${kind}.json`);
  } catch {
    return fixture<Place[]>('places_coffee.json');
  }
}

/** Searches about a kilometre apart share results. */
function cacheKey(query: string, ll?: LatLng): string {
  return ll ? `${query}@${ll.lat.toFixed(2)},${ll.lng.toFixed(2)}` : query;
}

/** Top 3 places near a location, open ones first. Never throws; falls back to fixtures. */
export async function findPlaces(kind: Kind, near: string, ll?: LatLng): Promise<Place[]> {
  if (useMocks()) return fallback(kind);
  const query = ll ? QUERY[kind] : `${QUERY[kind]} near ${near}`;
  const key = cacheKey(query, ll);
  const cached = cache.get(key);
  if (cached) return cached;
  try {
    const places = (await searchMaps(query, ll))
      .sort((a, b) => Number(b.openNow === true) - Number(a.openNow === true))
      .slice(0, 3);
    if (places.length === 0) return fallback(kind);
    cache.set(key, places);
    return places;
  } catch (e) {
    console.warn('[places] SerpApi failed, using fallback:', (e as Error).message);
    return fallback(kind);
  }
}

/** Any search ("bouldering gym", "boba"), for ideas built from interests. Empty on failure, never fixtures. */
export async function searchPlaces(what: string, near: string, ll?: LatLng): Promise<Place[]> {
  if (useMocks()) return [];
  const query = ll ? what : `${what} near ${near}`;
  const key = cacheKey(query, ll);
  const cached = cache.get(key);
  if (cached) return cached;
  try {
    // Google's order is relevance; only push places known to be closed to the back.
    // (Sorting open-first let a 24-hour park beat the climbing gym that was searched for.)
    const places = (await searchMaps(query, ll))
      .sort((a, b) => Number(a.openNow === false) - Number(b.openNow === false))
      .slice(0, 5);
    if (places.length) cache.set(key, places);
    return places;
  } catch (e) {
    console.warn('[places] SerpApi failed:', (e as Error).message);
    return [];
  }
}
