import { getCoffeePlaces } from '../mocks.js';
import type { Place } from '../types.js';

/** STUB — Person B owns real impl. Fixtures so USE_MOCKS=false demos still work. */
export async function findPlaces(
  kind: 'coffee' | 'food' | 'dessert',
  near: string,
): Promise<Place[]> {
  void near;
  if (kind === 'coffee') return getCoffeePlaces();
  return [];
}
