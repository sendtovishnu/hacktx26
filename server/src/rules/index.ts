import type { Tier } from '../types.js';

/** Placeholder — Person A wires share/privacy rules later. */
export function canShareContext(tier: Tier): 'closest' | 'close' | null {
  if (tier === 'closest') return 'closest';
  if (tier === 'close') return 'close';
  return null;
}
