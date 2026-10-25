import { z } from 'zod';
import type { GestureType, User } from '../types.js';
import { generateJSON } from './llm.js';

/** One way the friend could show up, before a real place is found for it. */
export type Idea = {
  gestureType: Exclude<GestureType, 'message'>;
  title: string;
  detail: string;
  /** What to search Google Maps for, like "boba tea" or "bouldering gym". */
  search: string;
  /** What gets brought on a drop-off, so the note can name it. */
  item?: string;
};

const ideasSchema = z.array(
  z.object({
    gesture_type: z.enum(['drop_off', 'hangout']),
    title: z.string().min(1).max(80),
    detail: z.string().min(1).max(160),
    search: z.string().min(2).max(60),
    item: z.string().max(40).nullish(),
  }),
);

/**
 * Ideas built from both people's interests: something the person would love, that the friend
 * would enjoy doing or bringing. `prefer` is what the twin thinks fits the week (no shared
 * free time means a drop-off, not a hangout), so those come first.
 */
export async function planIdeas(input: {
  helped: User;
  friend: User;
  prefer: GestureType;
  nudgeMessage: string;
  near: string;
}): Promise<Idea[]> {
  const { helped, friend, prefer, nudgeMessage, near } = input;
  const helpedInterests = helped.interests ?? [];
  const friendInterests = friend.interests ?? [];
  if (helpedInterests.length === 0 && friendInterests.length === 0) return [];

  const first = (u: User) => u.name.split(' ')[0];
  const prompt = `A friend wants to show up for someone having a hard week. Suggest 3 specific, local, low-effort ways.

${first(helped)} (needs support) is into: ${helpedInterests.join(', ') || 'unknown'}.
${helped.preferences.coffeeOrder ? `${first(helped)}'s usual order: ${helped.preferences.coffeeOrder}.` : ''}
${first(friend)} (the friend helping) is into: ${friendInterests.join(', ') || 'unknown'}.
What the twin told ${first(friend)}: "${nudgeMessage}"
They're near: ${near}.
${prefer === 'drop_off' ? `${first(helped)} has no free time, so lead with drop-offs (bring something to them).` : ''}
${prefer === 'hangout' ? `They share free time, so lead with a short hangout.` : ''}

Lean on what ${first(helped)} loves, and where you can, something they both like.
Return JSON only, an array of 3:
[{"gesture_type": "drop_off" | "hangout",
  "title": "Bring boba from a tea shop" (under 8 words, no place name),
  "detail": "one short sentence on why it fits ${first(helped)}",
  "search": "boba tea" (what to type into Google Maps, 1-3 words),
  "item": "boba" (what's brought, for drop-offs; null for hangouts)}]`;

  const raw = await generateJSON<z.infer<typeof ideasSchema>>(prompt, ideasSchema, [], 'gemini');
  return raw.slice(0, 3).map((i) => ({
    gestureType: i.gesture_type,
    title: i.title,
    detail: i.detail,
    search: i.search,
    item: i.item ?? undefined,
  }));
}
