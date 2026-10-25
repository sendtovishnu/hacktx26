import { z } from 'zod';
import type { GestureType, User } from '../types.js';
import { generateJSON } from './llm.js';

/** One way the friend could show up, before a real place is found for it. */
export type Idea = {
  gestureType: Exclude<GestureType, 'message'>;
  title: string;
  detail: string;
  /** What to search Google Maps for, like "bouldering gym" or "boba tea". */
  search: string;
  /** What gets brought on a drop-off, so the note can name it. */
  item?: string;
  /** The interest it's built on, e.g. "Climbing". */
  interest: string;
  /** True when both people listed that interest. */
  shared: boolean;
};

const ideasSchema = z.array(
  z.object({
    gesture_type: z.enum(['drop_off', 'hangout']),
    interest: z.string().min(1).max(40),
    title: z.string().min(1).max(80),
    detail: z.string().min(1).max(160),
    search: z.string().min(2).max(60),
    item: z.string().max(40).nullish(),
  }),
);

const norm = (s: string) => s.trim().toLowerCase();

/** Interests both people listed, in the helped person's order. */
export function sharedInterests(a: string[], b: string[]): string[] {
  const theirs = new Set(b.map(norm));
  return a.filter((i) => theirs.has(norm(i)));
}

/**
 * Ideas built on what the two people have in common, or, if nothing, on what the person being
 * helped loves. Activities count as much as food and drink. `prefer` is what the twin thinks fits
 * the week (no shared free time means a drop-off), so those come first.
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
  const shared = sharedInterests(helpedInterests, friend.interests ?? []);
  const focus = shared.length ? shared : helpedInterests;
  if (focus.length === 0) return [];

  const first = (u: User) => u.name.split(' ')[0];
  const basis = shared.length
    ? `${first(helped)} and ${first(friend)} both love: ${shared.join(', ')}.`
    : `${first(helped)} loves: ${helpedInterests.join(', ')}. (${first(friend)} shares none of these.)`;
  const prompt = `A friend wants to show up for someone having a hard week. Suggest 3 specific, local, low-effort ways.

${basis}
Build EVERY idea on one of those interests, and only those. Name it in "interest", spelled exactly as listed.
"search" is what to type into Google Maps:
  for a hangout, where to do it: Climbing -> "bouldering gym", Museums -> "art museum";
  for a drop-off, where to get the item: climbing chalk -> "outdoor gear store", a book -> "bookstore", boba -> "boba tea".
Not just food and drink: include an activity they can do together (a hangout at a place for that interest),
and drop-offs of something tied to an interest (a book, a plant, a treat).

What the twin told ${first(friend)}: "${nudgeMessage}"
They're near: ${near}.
${prefer === 'drop_off' ? `${first(helped)} has no free time, so lead with drop-offs, but still include one short activity.` : ''}
${prefer === 'hangout' ? `They share free time, so lead with activities together.` : ''}

Return JSON only, an array of 3:
[{"gesture_type": "drop_off" | "hangout",
  "interest": "Climbing",
  "title": "Go bouldering together" (under 8 words, no place name),
  "detail": "one short sentence on why it fits ${first(helped)}",
  "search": "bouldering gym",
  "item": "a small succulent" (what's brought, for drop-offs; null for hangouts)}]`;

  const raw = await generateJSON<z.infer<typeof ideasSchema>>(prompt, ideasSchema, [], 'gemini');
  // Keep only ideas that really come from the focus interests.
  const byName = new Map(focus.map((i) => [norm(i), i]));
  return raw
    .filter((i) => byName.has(norm(i.interest)))
    .slice(0, 3)
    .map((i) => ({
      gestureType: i.gesture_type,
      title: i.title,
      detail: i.detail,
      search: i.search,
      item: i.item ?? undefined,
      interest: byName.get(norm(i.interest))!,
      shared: shared.length > 0,
    }));
}
