import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type {
  CalendarEvent,
  EmailSnippet,
  FriendEntry,
  Gesture,
  GestureType,
  Nudge,
  Place,
  Signals,
  Tier,
  TwinDecision,
  User,
} from './types.js';

const mocksDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'mocks');

function loadJson<T>(filename: string): T {
  return JSON.parse(readFileSync(join(mocksDir, filename), 'utf8')) as T;
}

type FriendRow = { friendId: string; tier: Tier };
type FriendsMap = Record<string, FriendRow[]>;
type NudgeRow = {
  id: string;
  fromUserId: string;
  toFriendId: string;
  message: string;
  contextLevel: 'closest' | 'close';
  status: 'sent' | 'seen' | 'acted';
  createdAt: string;
};
type GestureRow = {
  id: string;
  nudgeId: string;
  fromFriendId: string;
  toUserId: string;
  type: GestureType;
  placeName?: string;
  note: string;
  deliveredAt: string;
};

const users = loadJson<User[]>('users.json');
const friendsMap = loadJson<FriendsMap>('friends.json');
const eventsMaya = loadJson<CalendarEvent[]>('events_maya.json');
const emailsMaya = loadJson<EmailSnippet[]>('emails_maya.json');
const signalsMaya = loadJson<Signals>('signals_maya.json');
const decisionsMaya = loadJson<TwinDecision[]>('decisions_maya.json');
const placesCoffee = loadJson<Place[]>('places_coffee.json');
const nudgeRows = loadJson<NudgeRow[]>('nudges.json');
const gestureRows = loadJson<GestureRow[]>('gestures.json');

export function getUsers(): User[] {
  return users;
}

export function getUserById(id: string): User | undefined {
  return users.find((u) => u.id === id);
}

export function getFriendsFor(userId: string): FriendEntry[] {
  const rows = friendsMap[userId] ?? [];
  return rows
    .map((row) => {
      const friend = getUserById(row.friendId);
      if (!friend) return null;
      return { friend, tier: row.tier };
    })
    .filter((entry): entry is FriendEntry => entry !== null);
}

export function getEventsFor(userId: string): CalendarEvent[] {
  if (userId === 'u_maya') return eventsMaya;
  return [];
}

export function getEmailsFor(userId: string): EmailSnippet[] {
  if (userId === 'u_maya') return emailsMaya;
  return [];
}

export function getSignalsFor(userId: string): Signals | null {
  if (userId === 'u_maya') return signalsMaya;
  return null;
}

export function getDecisionsFor(userId: string): TwinDecision[] {
  if (userId === 'u_maya') return decisionsMaya;
  return [];
}

export function getCoffeePlaces(): Place[] {
  return placesCoffee;
}

export function getNudgesFor(userId: string): Nudge[] {
  return nudgeRows
    .filter((row) => row.fromUserId === userId || row.toFriendId === userId)
    .map((row): Nudge | null => {
      const fromUser = getUserById(row.fromUserId);
      if (!fromUser) return null;
      return {
        id: row.id,
        fromUser,
        toFriendId: row.toFriendId,
        message: row.message,
        contextLevel: row.contextLevel,
        status: row.status,
        createdAt: row.createdAt,
      };
    })
    .filter((n): n is Nudge => n !== null);
}

export function getNudgeById(id: string): Nudge | undefined {
  const row = nudgeRows.find((n) => n.id === id);
  if (!row) return undefined;
  const fromUser = getUserById(row.fromUserId);
  if (!fromUser) return undefined;
  return {
    id: row.id,
    fromUser,
    toFriendId: row.toFriendId,
    message: row.message,
    contextLevel: row.contextLevel,
    status: row.status,
    createdAt: row.createdAt,
  };
}

export function getGesturesFor(userId: string): Gesture[] {
  const out: Gesture[] = [];
  for (const row of gestureRows) {
    if (row.toUserId !== userId && row.fromFriendId !== userId) continue;
    const fromFriend = getUserById(row.fromFriendId);
    if (!fromFriend) continue;
    const gesture: Gesture = {
      id: row.id,
      nudgeId: row.nudgeId,
      fromFriend,
      type: row.type,
      note: row.note,
      deliveredAt: row.deliveredAt,
    };
    if (row.placeName) {
      const place = placesCoffee.find((p) => p.name === row.placeName);
      if (place) gesture.place = place;
    }
    out.push(gesture);
  }
  return out;
}

export function getSurprisesFor(userId: string): Gesture[] {
  const user = getUserById(userId);
  if (!user?.surpriseOptIn) return [];
  return getGesturesFor(userId).filter((g) => g.fromFriend.id !== userId);
}
