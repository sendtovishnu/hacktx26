import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { EmailSnippet, Tier, User } from '../types.js';
import { query } from './client.js';

const here = dirname(fileURLToPath(import.meta.url));
const mocksDir = join(here, '..', '..', 'mocks');

function loadJson<T>(filename: string): T {
  return JSON.parse(readFileSync(join(mocksDir, filename), 'utf8')) as T;
}

type FriendRow = { friendId: string; tier: Tier };
type FriendsMap = Record<string, FriendRow[]>;
type MockEvent = {
  title: string;
  start: string;
  end: string;
  location?: string;
};

const chicagoDateFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Chicago',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/** Today + `offset` days in America/Chicago as YYYY-MM-DD. */
function chicagoDatePlus(offset: number): string {
  const today = chicagoDateFmt.format(new Date()); // YYYY-MM-DD
  const [y, m, d] = today.split('-').map(Number);
  // UTC noon on the target calendar day → same calendar day in Chicago (UTC-5/-6).
  const next = new Date(Date.UTC(y, m - 1, d + offset, 12, 0, 0));
  return chicagoDateFmt.format(next);
}

/** Tomorrow in America/Chicago as YYYY-MM-DD. */
export function tomorrowChicagoDate(): string {
  return chicagoDatePlus(1);
}

/**
 * Contiguous busy blocks for Jay covering 09:00–22:00 America/Chicago on `day`
 * so there is no ≥30 min free window to overlap with Maya.
 */
function jayBusyBlocksOn(day: string): MockEvent[] {
  // Fixed -05:00 matches mock event style (CDT; demo dates are mid/late Oct).
  const t = (hh: number, mm: number) =>
    `${day}T${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}:00-05:00`;

  return [
    {
      title: 'EE 302 lecture',
      start: t(9, 0),
      end: t(10, 30),
      location: 'EER 1.518',
    },
    {
      title: 'Lab section — circuits',
      start: t(10, 30),
      end: t(12, 0),
      location: 'EER 0.822',
    },
    {
      title: 'Study group lunch',
      start: t(12, 0),
      end: t(13, 0),
      location: 'Jester Dining',
    },
    {
      title: 'Internship standup + coding block',
      start: t(13, 0),
      end: t(15, 0),
      location: 'West Campus (remote)',
    },
    {
      title: 'Algorithms problem set',
      start: t(15, 0),
      end: t(17, 0),
      location: 'PCL Library UT Austin',
    },
    {
      title: 'Gym + commute',
      start: t(17, 0),
      end: t(18, 30),
      location: 'Gregory Gym',
    },
    {
      title: 'IEEE club meeting',
      start: t(18, 30),
      end: t(20, 30),
      location: 'EER 3.646',
    },
    {
      title: 'Night study — systems midterm',
      start: t(20, 30),
      end: t(22, 0),
      location: 'Houndstooth Coffee',
    },
  ];
}

export async function seed(): Promise<void> {
  const users = loadJson<User[]>('users.json');
  const friendsMap = loadJson<FriendsMap>('friends.json');
  const mayaEvents = loadJson<MockEvent[]>('events_maya.json');
  const mayaEmails = loadJson<EmailSnippet[]>('emails_maya.json');

  for (const user of users) {
    await query(
      `INSERT INTO users (
         id, name, email, home_location, preferences, surprise_opt_in, paused
       ) VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7)`,
      [
        user.id,
        user.name,
        user.email,
        user.homeLocation,
        JSON.stringify(user.preferences),
        user.surpriseOptIn,
        user.paused,
      ],
    );
  }

  for (const [userId, rows] of Object.entries(friendsMap)) {
    for (const row of rows) {
      await query(
        `INSERT INTO friendships (user_id, friend_id, tier)
         VALUES ($1, $2, $3)`,
        [userId, row.friendId, row.tier],
      );
    }
  }

  // Maya calendar from mocks (ICS ingest path).
  for (const event of mayaEvents) {
    await query(
      `INSERT INTO events (user_id, title, "start", "end", location, source)
       VALUES ($1, $2, $3::timestamptz, $4::timestamptz, $5, 'ics')`,
      [
        'u_maya',
        event.title,
        event.start,
        event.end,
        event.location ?? null,
      ],
    );
  }

  // Jay: fully busy 9am–10pm today and the next 2 days, the same 3-day window
  // sharedFreeMinutes checks → no 30+ min free overlap with Maya → drop-off.
  const jayDays = [0, 1, 2].map(chicagoDatePlus);
  const jayDay = `${jayDays[0]}..${jayDays[2]}`;
  for (const event of jayDays.flatMap(jayBusyBlocksOn)) {
    await query(
      `INSERT INTO events (user_id, title, "start", "end", location, source)
       VALUES ($1, $2, $3::timestamptz, $4::timestamptz, $5, 'ics')`,
      [
        'u_jay',
        event.title,
        event.start,
        event.end,
        event.location ?? null,
      ],
    );
  }

  // Temporary inbox for Maya — twin refresh filters then deletes these.
  for (const email of mayaEmails) {
    await query(
      `INSERT INTO emails (user_id, from_addr, subject, snippet, date)
       VALUES ($1, $2, $3, $4, $5::timestamptz)`,
      ['u_maya', email.from, email.subject, email.snippet, email.date],
    );
  }

  // Do NOT seed nudges / gestures / signals — twin refresh creates those.
  console.log(
    `Seeded ${users.length} users, friendships from friends.json, ${mayaEvents.length} Maya events, ${mayaEmails.length} Maya emails, Jay busy blocks for ${jayDay} (America/Chicago).`,
  );
}
