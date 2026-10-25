import { planHangoutIdeas, windowLabel, type HangoutIdea } from './ai/hangout.js';
import { getLatestSignal, getUserLocation, listEvents, toCalendarEvents, toSignals, useDatabase } from './db/index.js';
import { findPlaces, searchPlaces, type LatLng } from './places/index.js';
import { sharedFreeWindows } from './rules/index.js';
import { nearLocation } from './suggestions.js';
import type { HangoutPlan, HangoutSuggestion, User } from './types.js';

/** Kilometres between two points, near enough for "are they in the same city". */
function km(a: LatLng, b: LatLng): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const x = rad(b.lng - a.lng) * Math.cos(rad((a.lat + b.lat) / 2));
  const y = rad(b.lat - a.lat);
  return Math.sqrt(x * x + y * y) * 6371;
}

/** Halfway between the two when they're in the same city; otherwise wherever the asker is. */
async function meetingPoint(me: User, friend: User): Promise<{ near: string; ll?: LatLng }> {
  const [mine, theirs] = await Promise.all([getUserLocation(me.id), getUserLocation(friend.id)]);
  const signals = useDatabase() ? await getLatestSignal(me.id) : null;
  const near = nearLocation(signals ? toSignals(signals) : null, me.homeLocation, mine?.label ?? theirs?.label);
  if (mine && theirs && km(mine, theirs) < 60) {
    return { near, ll: { lat: (mine.lat + theirs.lat) / 2, lng: (mine.lng + theirs.lng) / 2 } };
  }
  const spot = mine ?? theirs;
  return { near, ll: spot ? { lat: spot.lat, lng: spot.lng } : undefined };
}

/** When nothing could be brainstormed: coffee and a bite, at the first times that work. */
function classics(friend: User, labels: string[]): HangoutIdea[] {
  const when = (i: number) => labels[i] ?? labels[0] ?? 'This weekend';
  const name = friend.name.split(' ')[0];
  return [
    { title: 'Grab coffee and catch up', detail: `An easy hour to hear how ${name}'s been.`, search: 'coffee', shared: false, window: 0, when: when(0), message: `want to grab coffee? ${when(0).toLowerCase()} works for me` },
    { title: 'Get dinner together', detail: 'Somewhere new, no plans after.', search: 'restaurant', shared: false, window: 1, when: when(1), message: `dinner sometime? i'm free ${when(1).toLowerCase()}` },
  ];
}

/**
 * Brainstorms things two friends could do together and when: free times from both calendars
 * (only the gaps, never the events), ideas from both people's interests, a real place for each.
 */
export async function planHangout(me: User, friend: User, avoid: string[] = []): Promise<HangoutPlan> {
  const [myEvents, theirEvents] = useDatabase()
    ? await Promise.all([listEvents(me.id), listEvents(friend.id)])
    : [[], []];
  const windows = sharedFreeWindows(toCalendarEvents(myEvents), toCalendarEvents(theirEvents), { days: 7, minMinutes: 60 });
  const labels = windows.map(windowLabel);
  const { near, ll } = await meetingPoint(me, friend);

  let ideas = await planHangoutIdeas({ me, friend, windows, near, avoid });
  if (ideas.length < 2) ideas = classics(friend, labels);

  const results = await Promise.all(
    ideas.map((idea) => (idea.search === 'coffee' ? findPlaces('coffee', near, ll) : searchPlaces(idea.search, near, ll))),
  );
  // Each idea gets its own place: the first result another idea hasn't taken.
  const used = new Set<string>();
  const suggestions: HangoutSuggestion[] = ideas.map((idea, i) => {
    const place = results[i].find((p) => !used.has(p.name));
    if (place) used.add(place.name);
    const window = idea.window >= 0 ? windows[idea.window] : undefined;
    return {
      title: idea.title,
      detail: idea.detail,
      when: idea.when,
      start: window?.start,
      end: window?.end,
      place,
      basedOn: idea.interest,
      sharedInterest: idea.interest ? idea.shared : undefined,
      message: idea.message,
    };
  });

  return {
    ideas: suggestions,
    freeTimes: labels.slice(0, 6),
    calendars: { mine: myEvents.length > 0, theirs: theirEvents.length > 0 },
  };
}
