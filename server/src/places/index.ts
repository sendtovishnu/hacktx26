import { fixture } from '../ai/fixtures.js';
import { useMocks } from '../ai/llm.js';
import type { Place } from '../types.js';
import { searchMaps } from './serpapi.js';

type Kind = 'coffee' | 'food' | 'dessert';

const QUERY: Record<Kind, string> = { coffee: 'coffee', food: 'food', dessert: 'dessert' };
const cache = new Map<string, Place[]>();

function fallback(kind: Kind): Place[] {
  try {
    return fixture<Place[]>(`places_${kind}.json`);
  } catch {
    return fixture<Place[]>('places_coffee.json');
  }
}

/** Top 3 places near a location, open ones first. Never throws; falls back to fixtures. */
export async function findPlaces(kind: Kind, near: string): Promise<Place[]> {
  if (useMocks()) return fallback(kind);
  const query = `${QUERY[kind]} near ${near}`;
  const cached = cache.get(query);
  if (cached) return cached;
  try {
    const places = (await searchMaps(query))
      .sort((a, b) => Number(b.openNow === true) - Number(a.openNow === true))
      .slice(0, 3);
    if (places.length === 0) return fallback(kind);
    cache.set(query, places);
    return places;
  } catch (e) {
    console.warn('[places] SerpApi failed, using fallback:', (e as Error).message);
    return fallback(kind);
  }
}
