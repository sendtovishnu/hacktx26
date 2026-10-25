import { randomUUID } from 'node:crypto';
import { decideNudges, planMoment } from './ai/index.js';
import {
  coveredInputs,
  deleteUnactedNudgesFrom,
  deleteUnactedNudgesTo,
  getFriends,
  getLatestSignal,
  getNudge,
  getSummaryOverride,
  getUserLocation,
  insertNudge,
  latestReaction,
  listEvents,
  listTwinEntries,
  markCovered,
  recentGesturesBetween,
  setNudgeMoment,
  toCalendarEvents,
  toSignals,
  type DbEmail,
} from './db/index.js';
import { suggestionsForNudge } from './nudgeSuggestions.js';
import { allowedToNudge, canShareContext, sharedFreeMinutes } from './rules/index.js';
import { nearLocation } from './suggestions.js';
import type { CalendarEvent, Signals, TwinFriendInput, User } from './types.js';

/** What friends hear uses the person's own wording when they've edited it. */
export async function withOverride(userId: string, signals: Signals): Promise<Signals> {
  const override = await getSummaryOverride(userId);
  return override ? { ...signals, ...override } : signals;
}

const gestureWords: Record<string, string> = {
  drop_off: 'a drop-off',
  hangout: 'a study break together',
  message: 'a note',
};

/** Pay it forward: what `user` recently did for `friend`, if anything. */
async function showedUpFor(user: User, friend: User): Promise<string | undefined> {
  const [latest] = await recentGesturesBetween(user.id, friend.id);
  if (!latest) return undefined;
  const what = gestureWords[latest.type] ?? 'something kind';
  return latest.placeName ? `${what} from ${latest.placeName}` : what;
}

/**
 * Twin to twin, in the background: build the friend's suggestions (from both people's interests),
 * then have the friend's twin find when they can do the top one. Both are ready by the time the
 * friend opens the nudge, and the moment names the same thing the first suggestion does.
 */
function planMomentInBackground(args: {
  nudgeId: string;
  person: User;
  personEvents: CalendarEvent[];
  signals: Signals;
  friend: User;
  friendEvents: CalendarEvent[];
}): void {
  void (async () => {
    const nudge = await getNudge(args.nudgeId);
    if (!nudge) return;
    const [top] = await suggestionsForNudge(nudge, args.friend);
    const loc = await getUserLocation(args.person.id);
    const moment = await planMoment({
      friend: args.friend,
      friendEvents: args.friendEvents,
      person: args.person,
      personBusy: args.personEvents.map(({ start, end }) => ({ start, end })),
      personLocation: nearLocation(args.signals, args.person.homeLocation, loc?.label),
      gestureType: top?.gestureType ?? 'message',
      placeName: top?.place?.name,
      activity: top?.title,
    });
    if (moment) await setNudgeMoment(args.nudgeId, moment);
  })().catch((err) => console.warn('[twin] moment planning failed:', (err as Error).message));
}

/**
 * Decides which friends hear about the person's latest twin read, and nudges them.
 * A friend hears about each input (event, email, thing they told their twin) once; only friends
 * with something new are considered, and a nudge marks everything it was based on as told.
 *
 * Runs after a refresh (all friends), and when a friendship starts (just the new friend), so
 * someone added after a refresh still hears about the week.
 */
export async function nudgeFriends(
  user: User,
  opts: { emails?: DbEmail[]; checkin?: string; onlyFriendIds?: string[]; fromRefresh?: boolean } = {},
): Promise<{ nudgesSent: number; nothingNew: boolean; withdrawn: boolean } | null> {
  const row = await getLatestSignal(user.id);
  if (!row) return null;
  const signals = await withOverride(user.id, toSignals(row));
  const dbEvents = await listEvents(user.id);
  const events = toCalendarEvents(dbEvents);
  const entries = await listTwinEntries(user.id);

  const friendEntries = (await getFriends(user.id)).filter(
    (e) => !opts.onlyFriendIds || opts.onlyFriendIds.includes(e.friend.id),
  );
  const friends: TwinFriendInput[] = [];
  const eventsByFriend = new Map<string, CalendarEvent[]>();
  for (const entry of friendEntries) {
    const friendEvents = toCalendarEvents(await listEvents(entry.friend.id));
    eventsByFriend.set(entry.friend.id, friendEvents);
    friends.push({
      friend: entry.friend,
      tier: entry.tier,
      sharedFreeMinutes: sharedFreeMinutes(events, friendEvents),
      showedUpForThem: await showedUpFor(user, entry.friend),
      lastReaction: (await latestReaction(user.id, entry.friend.id)) ?? undefined,
    });
  }

  const inputKeys = [
    ...dbEvents.map((e) => `event:${e.title}|${e.start}`),
    ...(opts.emails ?? []).map((e) => `email:${e.fromAddr}|${e.subject}|${e.date}`),
    ...entries.map((e) => `entry:${e.id}`),
    ...(opts.checkin?.trim() ? [`checkin:${opts.checkin.trim().toLowerCase()}`] : []),
  ];
  // Nothing itemized (say, a read built only from emails that are now deleted): the read itself
  // is the one thing to tell, once.
  if (inputKeys.length === 0) inputKeys.push('twin-read');

  const covered = await coveredInputs(user.id);
  const hasNews = (friendId: string) => inputKeys.some((k) => !covered.get(friendId)?.has(k));
  const candidates = friends.filter((f) => hasNews(f.friend.id));

  const withdrawn = user.paused || !user.surpriseOptIn || signals.supportLevel === 'doing_fine';
  if (withdrawn) {
    // Doing fine, or not open to support: open nudges are taken back after a refresh.
    // Coverage stays, so nothing repeats later.
    if (opts.fromRefresh) await deleteUnactedNudgesFrom(user.id);
    return { nudgesSent: 0, nothingNew: false, withdrawn };
  }

  let decisions = candidates.length ? await decideNudges(user, signals, candidates) : [];
  decisions = decisions.filter((d) => {
    const friend = candidates.find((f) => f.friend.id === d.friendId);
    return friend ? allowedToNudge(friend.tier, signals.supportLevel) : false;
  });

  for (const decision of decisions) {
    const friend = friends.find((f) => f.friend.id === decision.friendId);
    const contextLevel = friend ? canShareContext(friend.tier) : null;
    if (!friend || !contextLevel) continue;
    const nudgeId = `n_${randomUUID()}`;
    await deleteUnactedNudgesTo(user.id, decision.friendId);
    await insertNudge({
      id: nudgeId,
      fromUserId: user.id,
      toFriendId: decision.friendId,
      message: decision.message,
      contextLevel,
      status: 'sent',
      draftNote: decision.surpriseNote,
      reason: decision.reason,
    });
    await markCovered(user.id, decision.friendId, inputKeys);
    planMomentInBackground({
      nudgeId,
      person: user,
      personEvents: events,
      signals,
      friend: friend.friend,
      friendEvents: eventsByFriend.get(friend.friend.id) ?? [],
    });
  }

  // The Friends circle hears only the person's own line, word for word, and only if they wrote one.
  // The twin never writes for this circle, so these friends never learn more than that.
  let friendNudges = 0;
  const friendLine = signals.summaryForFriend?.trim();
  if (friendLine) {
    const first = user.name.split(' ')[0];
    const line = friendLine.charAt(0).toLowerCase() + friendLine.slice(1).replace(/[.!]+$/, '');
    for (const friend of candidates.filter((f) => f.tier === 'friend')) {
      const nudgeId = `n_${randomUUID()}`;
      await deleteUnactedNudgesTo(user.id, friend.friend.id);
      await insertNudge({
        id: nudgeId,
        fromUserId: user.id,
        toFriendId: friend.friend.id,
        message: `${first}'s week: ${line}. A kind word might be nice.`,
        contextLevel: 'friend',
        status: 'sent',
        draftNote: 'thinking of you this week. hope it gets lighter soon',
        reason: `Told ${friend.friend.name.split(' ')[0]} (your Friends circle) your own line: "${friendLine}".`,
      });
      await markCovered(user.id, friend.friend.id, inputKeys);
      planMomentInBackground({
        nudgeId,
        person: user,
        personEvents: events,
        signals,
        friend: friend.friend,
        friendEvents: eventsByFriend.get(friend.friend.id) ?? [],
      });
      friendNudges += 1;
    }
  }

  return { nudgesSent: decisions.length + friendNudges, nothingNew: candidates.length === 0, withdrawn };
}

/** A friendship just started: each side's twin may tell the other about a week already read. */
export function nudgeNewFriendship(a: User, b: User): void {
  void (async () => {
    await nudgeFriends(a, { onlyFriendIds: [b.id] });
    await nudgeFriends(b, { onlyFriendIds: [a.id] });
  })().catch((err) => console.warn('[twin] new-friend nudge failed:', (err as Error).message));
}
