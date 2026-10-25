import { planIdeas } from './ai/ideas.js';
import { findPlaces, searchPlaces, type LatLng } from './places/index.js';
import type {
  GestureType,
  Place,
  Signals,
  Suggestion,
  User,
} from './types.js';

function article(word: string): string {
  const first = word.trim().charAt(0).toLowerCase();
  return `${'aeiou'.includes(first) ? 'an' : 'a'} ${word}`;
}

function capitalizeFirst(text: string): string {
  if (!text) return text;
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/**
 * Near string for place search and prompts. The city from the phone's location keeps a vague
 * "library" from landing in another state; DEMO_LOCATION is the last resort.
 */
export function nearLocation(signals?: Signals | null, fallbackHome?: string, city?: string): string {
  const spot = signals?.likelyLocation?.trim();
  if (city) return spot ? `${spot}, ${city}` : city;
  return spot || process.env.DEMO_LOCATION?.trim() || fallbackHome?.trim() || 'PCL Library UT Austin';
}

/**
 * Build 2–3 suggestion cards driven by the nudge's gesture type.
 * drop_off / hangout pull coffee places; message is always available.
 */
export async function buildSuggestions(input: {
  fromUser: User;
  gestureType: GestureType;
  near: string;
  nudgeMessage: string;
  /** They said they needed space last time, so only notes, no visits. */
  wantsSpace?: boolean;
  /** Search around this point when the app shared a location. */
  ll?: LatLng;
}): Promise<Suggestion[]> {
  const { fromUser, gestureType, near, nudgeMessage, wantsSpace, ll } = input;
  const drink = fromUser.preferences.coffeeOrder ?? 'coffee';
  const [places, matchaPlaces] =
    wantsSpace
      ? [[], []]
      : await Promise.all([findPlaces('coffee', near, ll), findPlaces('matcha', near, ll)]);

  const out: Suggestion[] = [];
  // Coffee and matcha are both on the table, so the friend can pick what fits.
  const dropOffs = (): Suggestion[] => {
    const list: Suggestion[] = [];
    if (places[0]) {
      list.push({
        gestureType: 'drop_off',
        title: `Bring ${article(drink)} from ${places[0].name}`,
        detail: `${fromUser.name} is at ${near}. A quick drop-off won't cost study time.`,
        place: places[0],
        item: drink,
      });
    }
    const matchaSpot = matchaPlaces[0] ?? places[1];
    if (matchaSpot) {
      list.push({
        gestureType: 'drop_off',
        title: `Bring a matcha from ${matchaSpot.name}`,
        detail: `Something green and calming, dropped off near ${near}.`,
        place: matchaSpot,
        item: 'matcha',
      });
    }
    return list;
  };

  if (gestureType === 'drop_off') {
    out.push(...dropOffs());
    out.push({
      gestureType: 'message',
      title: `Send ${fromUser.name} a note`,
      detail: nudgeMessage,
    });
  } else if (gestureType === 'hangout') {
    const spot: Place = places[0] ?? {
      name: near,
      address: near,
      openNow: true,
    };
    out.push({
      gestureType: 'hangout',
      title: `Plan a hangout at ${spot.name}`,
      detail: `${fromUser.name} likes company. A short break together helps.`,
      place: spot,
    });
    out.push(...dropOffs());
    out.push({
      gestureType: 'message',
      title: `Send ${fromUser.name} a note`,
      detail: nudgeMessage,
    });
  } else if (!wantsSpace) {
    // No calendar to go on: lead with a note, but coffee, matcha and a hangout are still options.
    out.push({
      gestureType: 'message',
      title: `Send ${fromUser.name} a note`,
      detail: nudgeMessage,
    });
    out.push(...dropOffs());
    const spot: Place = places[0] ?? { name: near, address: near, openNow: true };
    out.push({
      gestureType: 'hangout',
      title: `Plan a hangout at ${spot.name}`,
      detail: `A short break together near ${near}.`,
      place: spot,
    });
  } else {
    out.push({
      gestureType: 'message',
      title: `Send ${fromUser.name} a check-in`,
      detail: nudgeMessage,
    });
    out.push({
      gestureType: 'message',
      title: 'Cheer them on',
      detail: `A short message saying you're rooting for ${fromUser.name} this week.`,
    });
    if (places[0] || near) {
      out.push({
        gestureType: 'message',
        title: 'Offer a rain check',
        detail: `Let ${fromUser.name} know you're free later near ${near}.`,
      });
    }
  }

  return out.slice(0, 4);
}

/** Surprise note shown to the helped user after a gesture is sent. */
export function surpriseNoteFor(
  choice: Suggestion,
  helped: User,
): string {
  switch (choice.gestureType) {
    case 'drop_off': {
      const drink = choice.item ?? helped.preferences.coffeeOrder ?? 'coffee';
      const from = choice.place ? ` from ${choice.place.name}` : '';
      return `${capitalizeFirst(article(drink))}${from} is on its way to you. You've got this!`;
    }
    case 'hangout':
      return 'Your study break is booked. Come grab a breather!';
    case 'message':
      return "Rooting for you this week. You're going to do great.";
  }
}

/**
 * Suggestions built on what the two people have in common (or what the person loves): the twin
 * picks ideas, SerpApi finds a real place for each, near where the person is. Falls back to the coffee and matcha set when there are no interests or
 * nothing is found. A note is always the last option.
 */
export async function buildPersonalSuggestions(input: {
  fromUser: User;
  friend: User;
  gestureType: GestureType;
  near: string;
  nudgeMessage: string;
  wantsSpace?: boolean;
  ll?: LatLng;
}): Promise<Suggestion[]> {
  const { fromUser, friend, gestureType, near, nudgeMessage, wantsSpace, ll } = input;
  if (wantsSpace) return buildSuggestions(input);

  const ideas = await planIdeas({ helped: fromUser, friend, prefer: gestureType, nudgeMessage, near });
  const results = await Promise.all(ideas.map((idea) => searchPlaces(idea.search, near, ll)));
  // Each idea gets its own place: the first result another idea hasn't taken.
  const used = new Set<string>();
  const found = ideas.map((idea, i) => {
    const place = results[i].find((p) => !used.has(p.name));
    if (place) used.add(place.name);
    return { idea, place };
  });
  const personal: Suggestion[] = found
    .filter((f): f is typeof f & { place: Place } => Boolean(f.place))
    .map(({ idea, place }) => ({
      gestureType: idea.gestureType,
      title: idea.title,
      detail: idea.detail,
      place,
      item: idea.item,
      basedOn: idea.interest,
      sharedInterest: idea.shared,
    }));
  if (personal.length < 2) return buildSuggestions(input);

  // What fits the week goes first: a drop-off when there's no shared free time.
  personal.sort((a, b) => Number(b.gestureType === gestureType) - Number(a.gestureType === gestureType));
  return [
    ...personal,
    { gestureType: 'message', title: `Send ${fromUser.name} a note`, detail: nudgeMessage },
  ];
}
