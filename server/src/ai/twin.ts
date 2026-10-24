import { z } from 'zod';
import type { Signals, TwinDecision, TwinFriendInput, User } from '../types.js';
import { fixture } from './fixtures.js';
import { generateJSON } from './llm.js';
import { twinPrompt } from './prompts.js';

const decisionsSchema = z.array(
  z.object({
    friend_id: z.string(),
    message: z.string().min(1),
    gesture_type: z.enum(['drop_off', 'hangout', 'message']).catch('drop_off'),
    surprise_note: z.string().min(1),
  }),
);

/**
 * The digital twin, run on Meta Muse Spark (falls back to Gemini, then fixtures).
 * Tier rules are enforced here as well as in the prompt; A's allowedToNudge applies them again.
 */
export async function decideNudges(user: User, signals: Signals, friends: TwinFriendInput[]): Promise<TwinDecision[]> {
  if (signals.supportLevel === 'doing_fine' || user.paused || !user.surpriseOptIn) return [];

  // doing_fine already returned, so both close and closest may be nudged here.
  const eligible = friends.filter((f) => f.tier === 'closest' || f.tier === 'close');
  if (eligible.length === 0) return [];
  const eligibleIds = new Set(eligible.map((f) => f.friend.id));

  const fallback = fixture<TwinDecision[]>('decisions_maya.json')
    .filter((d) => eligibleIds.has(d.friendId))
    .map((d) => ({ friend_id: d.friendId, message: d.message, gesture_type: d.gestureType, surprise_note: d.surpriseNote }));

  const raw = await generateJSON(twinPrompt(user, signals, eligible), decisionsSchema, fallback, 'muse');

  const seen = new Set<string>();
  return raw
    .filter((d) => eligibleIds.has(d.friend_id) && !seen.has(d.friend_id) && seen.add(d.friend_id))
    .map((d) => ({
      friendId: d.friend_id,
      message: d.message,
      gestureType: d.gesture_type,
      surpriseNote: d.surprise_note,
    }));
}
