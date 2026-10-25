import { findPlaces } from './places/index.js';
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

/** Near string for place search: likelyLocation, else DEMO_LOCATION. */
export function nearLocation(signals?: Signals | null, fallbackHome?: string): string {
  return (
    signals?.likelyLocation?.trim() ||
    process.env.DEMO_LOCATION?.trim() ||
    fallbackHome?.trim() ||
    'PCL Library UT Austin'
  );
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
}): Promise<Suggestion[]> {
  const { fromUser, gestureType, near, nudgeMessage, wantsSpace } = input;
  const drink = fromUser.preferences.coffeeOrder ?? 'coffee';
  const [places, matchaPlaces] =
    wantsSpace
      ? [[], []]
      : await Promise.all([findPlaces('coffee', near), findPlaces('matcha', near)]);

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
