import {
  getLatestSignal,
  getNudgeSuggestions,
  getUserLocation,
  latestReaction,
  listEvents,
  respectReaction,
  setNudgeSuggestions,
  toCalendarEvents,
  toSignals,
  useDatabase,
} from './db/index.js';
import { getSignalsFor } from './mocks.js';
import { gestureFor, sharedFreeMinutes } from './rules/index.js';
import { buildPersonalSuggestions, nearLocation } from './suggestions.js';
import type { GestureType, Nudge, Signals, Suggestion, User } from './types.js';

export async function resolveGestureType(nudgeFromId: string, nudgeToId: string): Promise<{
  gestureType: GestureType;
  signals: Signals | null;
}> {
  if (useDatabase()) {
    const row = await getLatestSignal(nudgeFromId);
    const signals = row ? toSignals(row) : null;
    if (!signals) {
      return { gestureType: 'message', signals: null };
    }
    const mins = sharedFreeMinutes(
      toCalendarEvents(await listEvents(nudgeFromId)),
      toCalendarEvents(await listEvents(nudgeToId)),
    );
    return {
      gestureType: await respectReaction(nudgeFromId, nudgeToId, gestureFor(signals, mins)),
      signals,
    };
  }

  const signals = getSignalsFor(nudgeFromId);
  if (!signals) return { gestureType: 'message', signals: null };
  // Mock demo: Maya→Jay has no shared free block → drop_off under crunch.
  const mins =
    nudgeFromId === 'u_maya' && nudgeToId === 'u_jay'
      ? 0
      : sharedFreeMinutes([], []);
  return { gestureType: gestureFor(signals, mins), signals };
}

/**
 * The options a friend sees for a nudge. Built once and saved, because an AI picks them:
 * GET /nudges/:id/suggestions and POST /gestures must agree on what index 2 is.
 */
export async function suggestionsForNudge(nudge: Nudge, friend: User): Promise<Suggestion[]> {
  if (useDatabase()) {
    const saved = await getNudgeSuggestions(nudge.id);
    // Saved before anyone had interests? Rebuild once they do, as long as the friend hasn't acted
    // (after acting, the saved list must stay put so the chosen index still means the same thing).
    const generic = saved?.length && !saved.some((s) => s.basedOn);
    const nowPersonal = (nudge.fromUser.interests?.length ?? 0) > 0;
    if (saved?.length && !(generic && nowPersonal && nudge.status !== 'acted')) return saved;
  }
  const { gestureType, signals } = await resolveGestureType(nudge.fromUser.id, nudge.toFriendId);
  const wantsSpace = useDatabase() && (await latestReaction(nudge.fromUser.id, friend.id)) === 'space';
  // Search where the person being helped is; the friend's spot is next best.
  const loc = (await getUserLocation(nudge.fromUser.id)) ?? (await getUserLocation(friend.id));
  const suggestions = await buildPersonalSuggestions({
    fromUser: nudge.fromUser,
    friend,
    gestureType,
    near: nearLocation(signals, nudge.fromUser.homeLocation, loc?.label),
    nudgeMessage: nudge.message,
    wantsSpace,
    ll: loc ? { lat: loc.lat, lng: loc.lng } : undefined,
  });
  if (useDatabase()) await setNudgeSuggestions(nudge.id, suggestions);
  return suggestions;
}
