import { z } from 'zod';
import type { Signals, TwinDecision, TwinFriendInput, User } from '../types.js';
import { fixture } from './fixtures.js';
import { generateJSON } from './llm.js';
import { twinPrompt } from './prompts.js';

/**
 * TwinDecision plus Muse's explanation for the privacy log. `reason` is extra to the
 * shared contract until it's added to types.ts; callers typed as TwinDecision still work.
 */
export type ExplainedDecision = TwinDecision & { reason: string };

const decisionsSchema = z.array(
  z.object({
    friend_id: z.string(),
    message: z.string().min(1),
    // A's gestureFor rule overrides this anyway, so don't reject a decision over it.
    gesture_type: z.enum(['drop_off', 'hangout', 'message']).catch('drop_off' as const),
    surprise_note: z.string().min(1),
    reason: z.string().optional(),
  }),
);

function defaultReason(f: TwinFriendInput, signals: Signals): string {
  const first = f.friend.name.split(' ')[0];
  const told = f.tier === 'closest' ? signals.summaryForClosest : signals.summaryForClose;
  return `Told ${first} (your ${f.tier} friend): "${told}".`;
}

/**
 * The digital twin, run on Meta Muse Spark (falls back to Gemini, then fixtures).
 * Tier rules are enforced here as well as in the prompt; A's allowedToNudge applies them again.
 * surpriseNote is a starter draft for the friend to edit before sending.
 */
export async function decideNudges(user: User, signals: Signals, friends: TwinFriendInput[]): Promise<ExplainedDecision[]> {
  if (signals.supportLevel === 'doing_fine' || user.paused || !user.surpriseOptIn) return [];

  // doing_fine already returned, so both close and closest may be nudged here.
  const eligible = friends.filter((f) => f.tier === 'closest' || f.tier === 'close');
  if (eligible.length === 0) return [];
  const byId = new Map(eligible.map((f) => [f.friend.id, f]));

  const fallback = fixture<TwinDecision[]>('decisions_maya.json')
    .filter((d) => byId.has(d.friendId))
    .map((d) => ({ friend_id: d.friendId, message: d.message, gesture_type: d.gestureType, surprise_note: d.surpriseNote }));

  const raw = await generateJSON<z.infer<typeof decisionsSchema>>(twinPrompt(user, signals, eligible), decisionsSchema, fallback, 'muse');

  const seen = new Set<string>();
  return raw
    .filter((d) => byId.has(d.friend_id) && !seen.has(d.friend_id) && seen.add(d.friend_id))
    .map((d) => ({
      friendId: d.friend_id,
      message: d.message,
      gestureType: d.gesture_type,
      surpriseNote: d.surprise_note,
      reason: d.reason?.trim() || defaultReason(byId.get(d.friend_id)!, signals),
    }));
}
