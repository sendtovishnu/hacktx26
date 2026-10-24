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
}): Promise<Suggestion[]> {
  const { fromUser, gestureType, near, nudgeMessage } = input;
  const drink = fromUser.preferences.coffeeOrder ?? 'coffee';
  const places =
    gestureType === 'message' ? [] : await findPlaces('coffee', near);

  const out: Suggestion[] = [];

  if (gestureType === 'drop_off') {
    for (const place of places.slice(0, 2)) {
      out.push({
        gestureType: 'drop_off',
        title: `Drop off ${article(drink)} from ${place.name}`,
        detail: `${fromUser.name} is at ${near} — a quick drop-off won't cost study time.`,
        place,
      });
    }
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
      title: `Sit with ${fromUser.name} at ${spot.name}`,
      detail: `${fromUser.name} likes company — a quiet study buddy helps.`,
      place: spot,
    });
    if (places[1]) {
      out.push({
        gestureType: 'hangout',
        title: `Meet at ${places[1].name}`,
        detail: `Take a short break together near ${near}.`,
        place: places[1],
      });
    }
    out.push({
      gestureType: 'message',
      title: `Send ${fromUser.name} a note`,
      detail: nudgeMessage,
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

  return out.slice(0, 3);
}

/** Surprise note shown to the helped user after a gesture is sent. */
export function surpriseNoteFor(
  choice: Suggestion,
  helped: User,
): string {
  switch (choice.gestureType) {
    case 'drop_off': {
      const drink = helped.preferences.coffeeOrder ?? 'coffee';
      const from = choice.place ? ` from ${choice.place.name}` : '';
      return `${capitalizeFirst(article(drink))}${from} is on its way to you. You've got this!`;
    }
    case 'hangout':
      return 'Your study break is booked. Come grab a breather!';
    case 'message':
      return "Rooting for you this week. You're going to do great.";
  }
}
