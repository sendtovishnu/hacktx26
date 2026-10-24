import { getCoffeePlaces } from '../mocks.js';
import type { Place } from '../types.js';

const useMocks = () => process.env.USE_MOCKS !== 'false';

/** STUB — Person B owns real impl */
export async function findPlaces(
  kind: 'coffee' | 'food' | 'dessert',
  near: string,
): Promise<Place[]> {
  void near;
  if (useMocks()) {
    if (kind === 'coffee') return getCoffeePlaces();
    return [];
  }
  throw new Error('findPlaces not implemented without USE_MOCKS');
}
