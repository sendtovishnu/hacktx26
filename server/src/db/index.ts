import type { FriendEntry, Tier, User } from '../types.js';
import { closePool, getPool, query } from './client.js';

export { closePool, getPool, query };
export { dbStatus };

function dbStatus(): { configured: boolean } {
  return { configured: Boolean(process.env.DATABASE_URL?.trim()) };
}

type UserRow = {
  id: string;
  name: string;
  email: string;
  home_location: string;
  preferences: User['preferences'] | string;
  surprise_opt_in: boolean;
  paused: boolean;
};

type FriendshipRow = {
  friend_id: string;
  tier: Tier;
  id: string;
  name: string;
  email: string;
  home_location: string;
  preferences: User['preferences'] | string;
  surprise_opt_in: boolean;
  paused: boolean;
};

function parsePreferences(value: UserRow['preferences']): User['preferences'] {
  if (typeof value === 'string') {
    return JSON.parse(value) as User['preferences'];
  }
  return value;
}

export function mapUser(row: UserRow): User {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    homeLocation: row.home_location,
    preferences: parsePreferences(row.preferences),
    surpriseOptIn: row.surprise_opt_in,
    paused: row.paused,
  };
}

export async function listUsers(): Promise<User[]> {
  const { rows } = await query<UserRow>('SELECT * FROM users ORDER BY name');
  return rows.map(mapUser);
}

export async function getUser(id: string): Promise<User | null> {
  const { rows } = await query<UserRow>('SELECT * FROM users WHERE id = $1', [id]);
  return rows[0] ? mapUser(rows[0]) : null;
}

export async function getFriends(userId: string): Promise<FriendEntry[]> {
  const { rows } = await query<FriendshipRow>(
    `SELECT f.friend_id, f.tier, u.id, u.name, u.email, u.home_location,
            u.preferences, u.surprise_opt_in, u.paused
     FROM friendships f
     JOIN users u ON u.id = f.friend_id
     WHERE f.user_id = $1
     ORDER BY
       CASE f.tier WHEN 'closest' THEN 0 WHEN 'close' THEN 1 ELSE 2 END,
       u.name`,
    [userId],
  );
  return rows.map((row) => ({
    friend: mapUser(row),
    tier: row.tier,
  }));
}

export async function upsertFriendship(
  userId: string,
  friendId: string,
  tier: Tier,
): Promise<FriendEntry | null> {
  await query(
    `INSERT INTO friendships (user_id, friend_id, tier)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, friend_id) DO UPDATE SET tier = EXCLUDED.tier`,
    [userId, friendId, tier],
  );
  const friend = await getUser(friendId);
  if (!friend) return null;
  return { friend, tier };
}

export type SettingsPatch = {
  surpriseOptIn?: boolean;
  paused?: boolean;
  homeLocation?: string;
  preferences?: Partial<User['preferences']>;
};

export async function updateSettings(
  userId: string,
  patch: SettingsPatch,
): Promise<User | null> {
  const current = await getUser(userId);
  if (!current) return null;

  const next: User = {
    ...current,
    surpriseOptIn: patch.surpriseOptIn ?? current.surpriseOptIn,
    paused: patch.paused ?? current.paused,
    homeLocation: patch.homeLocation ?? current.homeLocation,
    preferences: {
      ...current.preferences,
      ...patch.preferences,
    },
  };

  const { rows } = await query<UserRow>(
    `UPDATE users
     SET surprise_opt_in = $2,
         paused = $3,
         home_location = $4,
         preferences = $5::jsonb
     WHERE id = $1
     RETURNING *`,
    [
      userId,
      next.surpriseOptIn,
      next.paused,
      next.homeLocation,
      JSON.stringify(next.preferences),
    ],
  );
  return rows[0] ? mapUser(rows[0]) : null;
}

export type DbEvent = {
  id: number;
  userId: string;
  title: string;
  start: string;
  end: string;
  location: string | null;
  source: 'google' | 'ics';
};

type EventRow = {
  id: number;
  user_id: string;
  title: string;
  start: Date | string;
  end: Date | string;
  location: string | null;
  source: 'google' | 'ics';
};

function toIso(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function mapEvent(row: EventRow): DbEvent {
  return {
    id: row.id,
    userId: row.user_id,
    title: row.title,
    start: toIso(row.start),
    end: toIso(row.end),
    location: row.location,
    source: row.source,
  };
}

export async function listEvents(userId: string): Promise<DbEvent[]> {
  const { rows } = await query<EventRow>(
    `SELECT id, user_id, title, "start", "end", location, source
     FROM events
     WHERE user_id = $1
     ORDER BY "start"`,
    [userId],
  );
  return rows.map(mapEvent);
}

export async function replaceEvents(
  userId: string,
  events: Array<{
    title: string;
    start: string;
    end: string;
    location?: string | null;
    source: 'google' | 'ics';
  }>,
): Promise<DbEvent[]> {
  await query('DELETE FROM events WHERE user_id = $1', [userId]);
  const out: DbEvent[] = [];
  for (const event of events) {
    const { rows } = await query<EventRow>(
      `INSERT INTO events (user_id, title, "start", "end", location, source)
       VALUES ($1, $2, $3::timestamptz, $4::timestamptz, $5, $6)
       RETURNING id, user_id, title, "start", "end", location, source`,
      [
        userId,
        event.title,
        event.start,
        event.end,
        event.location ?? null,
        event.source,
      ],
    );
    if (rows[0]) out.push(mapEvent(rows[0]));
  }
  return out;
}

export type DbEmail = {
  id: number;
  userId: string;
  fromAddr: string;
  subject: string;
  snippet: string;
  date: string;
};

type EmailRow = {
  id: number;
  user_id: string;
  from_addr: string;
  subject: string;
  snippet: string;
  date: Date | string;
};

function mapEmail(row: EmailRow): DbEmail {
  return {
    id: row.id,
    userId: row.user_id,
    fromAddr: row.from_addr,
    subject: row.subject,
    snippet: row.snippet,
    date: toIso(row.date),
  };
}

export async function listEmails(userId: string): Promise<DbEmail[]> {
  const { rows } = await query<EmailRow>(
    `SELECT id, user_id, from_addr, subject, snippet, date
     FROM emails WHERE user_id = $1 ORDER BY date DESC`,
    [userId],
  );
  return rows.map(mapEmail);
}

export async function deleteEmails(userId: string): Promise<void> {
  await query('DELETE FROM emails WHERE user_id = $1', [userId]);
}

export async function upsertConnection(input: {
  userId: string;
  provider: string;
  accessToken?: string | null;
  refreshToken?: string | null;
  scopes?: string | null;
}): Promise<void> {
  await query(
    `INSERT INTO connections (user_id, provider, access_token, refresh_token, scopes)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (user_id, provider) DO UPDATE SET
       access_token = EXCLUDED.access_token,
       refresh_token = COALESCE(EXCLUDED.refresh_token, connections.refresh_token),
       scopes = COALESCE(EXCLUDED.scopes, connections.scopes)`,
    [
      input.userId,
      input.provider,
      input.accessToken ?? null,
      input.refreshToken ?? null,
      input.scopes ?? null,
    ],
  );
}

export async function getConnection(
  userId: string,
  provider: string,
): Promise<{
  userId: string;
  provider: string;
  accessToken: string | null;
  refreshToken: string | null;
  scopes: string | null;
} | null> {
  const { rows } = await query<{
    user_id: string;
    provider: string;
    access_token: string | null;
    refresh_token: string | null;
    scopes: string | null;
  }>(
    `SELECT user_id, provider, access_token, refresh_token, scopes
     FROM connections WHERE user_id = $1 AND provider = $2`,
    [userId, provider],
  );
  const row = rows[0];
  if (!row) return null;
  return {
    userId: row.user_id,
    provider: row.provider,
    accessToken: row.access_token,
    refreshToken: row.refresh_token,
    scopes: row.scopes,
  };
}

export async function insertSignal(input: {
  userId: string;
  supportLevel: string;
  stressors: unknown;
  busyHours: number;
  likelyLocation?: string | null;
  summaryForClosest: string;
  summaryForClose: string;
}): Promise<number> {
  const { rows } = await query<{ id: number }>(
    `INSERT INTO signals (
       user_id, support_level, stressors, busy_hours,
       likely_location, summary_for_closest, summary_for_close
     ) VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7)
     RETURNING id`,
    [
      input.userId,
      input.supportLevel,
      JSON.stringify(input.stressors),
      input.busyHours,
      input.likelyLocation ?? null,
      input.summaryForClosest,
      input.summaryForClose,
    ],
  );
  return rows[0]!.id;
}

export async function getLatestSignal(userId: string): Promise<{
  id: number;
  userId: string;
  supportLevel: string;
  stressors: unknown;
  busyHours: number;
  likelyLocation: string | null;
  summaryForClosest: string;
  summaryForClose: string;
  createdAt: string;
} | null> {
  const { rows } = await query<{
    id: number;
    user_id: string;
    support_level: string;
    stressors: unknown;
    busy_hours: number;
    likely_location: string | null;
    summary_for_closest: string;
    summary_for_close: string;
    created_at: Date | string;
  }>(
    `SELECT * FROM signals WHERE user_id = $1 ORDER BY created_at DESC LIMIT 1`,
    [userId],
  );
  const row = rows[0];
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    supportLevel: row.support_level,
    stressors: row.stressors,
    busyHours: row.busy_hours,
    likelyLocation: row.likely_location,
    summaryForClosest: row.summary_for_closest,
    summaryForClose: row.summary_for_close,
    createdAt: toIso(row.created_at),
  };
}

export async function insertNudge(input: {
  id: string;
  fromUserId: string;
  toFriendId: string;
  message: string;
  contextLevel: 'closest' | 'close';
  status?: 'sent' | 'seen' | 'acted';
}): Promise<void> {
  await query(
    `INSERT INTO nudges (id, from_user_id, to_friend_id, message, context_level, status)
     VALUES ($1, $2, $3, $4, $5, $6)
     ON CONFLICT (id) DO UPDATE SET
       message = EXCLUDED.message,
       context_level = EXCLUDED.context_level,
       status = EXCLUDED.status`,
    [
      input.id,
      input.fromUserId,
      input.toFriendId,
      input.message,
      input.contextLevel,
      input.status ?? 'sent',
    ],
  );
}

export async function updateNudgeStatus(
  id: string,
  status: 'sent' | 'seen' | 'acted',
): Promise<boolean> {
  const { rowCount } = await query(`UPDATE nudges SET status = $2 WHERE id = $1`, [
    id,
    status,
  ]);
  return (rowCount ?? 0) > 0;
}

export async function listNudgesForUser(userId: string): Promise<
  Array<{
    id: string;
    fromUserId: string;
    toFriendId: string;
    message: string;
    contextLevel: 'closest' | 'close';
    status: 'sent' | 'seen' | 'acted';
    createdAt: string;
  }>
> {
  const { rows } = await query<{
    id: string;
    from_user_id: string;
    to_friend_id: string;
    message: string;
    context_level: 'closest' | 'close';
    status: 'sent' | 'seen' | 'acted';
    created_at: Date | string;
  }>(
    `SELECT * FROM nudges
     WHERE from_user_id = $1 OR to_friend_id = $1
     ORDER BY created_at DESC`,
    [userId],
  );
  return rows.map((row) => ({
    id: row.id,
    fromUserId: row.from_user_id,
    toFriendId: row.to_friend_id,
    message: row.message,
    contextLevel: row.context_level,
    status: row.status,
    createdAt: toIso(row.created_at),
  }));
}

export async function insertGesture(input: {
  id: string;
  nudgeId: string;
  fromFriendId: string;
  type: string;
  placeName?: string | null;
  placeAddress?: string | null;
  note: string;
  deliveredAt?: string;
}): Promise<void> {
  await query(
    `INSERT INTO gestures (
       id, nudge_id, from_friend_id, type, place_name, place_address, note, delivered_at
     ) VALUES ($1, $2, $3, $4, $5, $6, $7, COALESCE($8::timestamptz, now()))
     ON CONFLICT (id) DO UPDATE SET
       note = EXCLUDED.note,
       place_name = EXCLUDED.place_name,
       place_address = EXCLUDED.place_address`,
    [
      input.id,
      input.nudgeId,
      input.fromFriendId,
      input.type,
      input.placeName ?? null,
      input.placeAddress ?? null,
      input.note,
      input.deliveredAt ?? null,
    ],
  );
}

export async function listGesturesForUser(userId: string): Promise<
  Array<{
    id: string;
    nudgeId: string;
    fromFriendId: string;
    type: string;
    placeName: string | null;
    placeAddress: string | null;
    note: string;
    deliveredAt: string;
  }>
> {
  const { rows } = await query<{
    id: string;
    nudge_id: string;
    from_friend_id: string;
    type: string;
    place_name: string | null;
    place_address: string | null;
    note: string;
    delivered_at: Date | string;
  }>(
    `SELECT g.*
     FROM gestures g
     JOIN nudges n ON n.id = g.nudge_id
     WHERE g.from_friend_id = $1 OR n.to_friend_id = $1 OR n.from_user_id = $1
     ORDER BY g.delivered_at DESC`,
    [userId],
  );
  return rows.map((row) => ({
    id: row.id,
    nudgeId: row.nudge_id,
    fromFriendId: row.from_friend_id,
    type: row.type,
    placeName: row.place_name,
    placeAddress: row.place_address,
    note: row.note,
    deliveredAt: toIso(row.delivered_at),
  }));
}
