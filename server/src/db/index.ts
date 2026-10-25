import type {
  CalendarEvent,
  EmailSnippet,
  FriendEntry,
  Gesture,
  GestureType,
  Nudge,
  Place,
  Signals,
  SupportLevel,
  Tier,
  User,
} from '../types.js';
import { randomBytes } from 'node:crypto';
import { closePool, getPool, query } from './client.js';

export { closePool, getPool, query };
export { dbStatus, useDatabase };

function dbStatus(): { configured: boolean } {
  return { configured: Boolean(process.env.DATABASE_URL?.trim()) };
}

/**
 * Prefer Postgres when DATABASE_URL is set, unless USE_MOCKS=true.
 * Demos stay on mocks when USE_MOCKS=true or DATABASE_URL is missing.
 */
function useDatabase(): boolean {
  if (process.env.USE_MOCKS === 'true') return false;
  return dbStatus().configured;
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

// Real accounts: Google sign-in creates the user and a session token the app sends as a Bearer header.
let sessionsReady: Promise<unknown> | null = null;
function ensureSessions(): Promise<unknown> {
  sessionsReady ??= query(`
    CREATE TABLE IF NOT EXISTS sessions (
      token TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );`);
  return sessionsReady;
}

/** Finds the user with this email (so a seeded demo email keeps its data), or creates one. */
export async function findOrCreateUserByEmail(
  email: string,
  name: string,
): Promise<{ user: User; created: boolean }> {
  const existing = await query<UserRow>('SELECT * FROM users WHERE lower(email) = lower($1)', [email]);
  if (existing.rows[0]) return { user: mapUser(existing.rows[0]), created: false };
  const id = `u_${randomBytes(6).toString('hex')}`;
  const { rows } = await query<UserRow>(
    `INSERT INTO users (id, name, email, preferences) VALUES ($1, $2, $3, $4::jsonb) RETURNING *`,
    [id, name, email, JSON.stringify({ likes: 'company' })],
  );
  return { user: mapUser(rows[0]), created: true };
}

export async function createSession(userId: string): Promise<string> {
  await ensureSessions();
  const token = randomBytes(32).toString('hex');
  await query('INSERT INTO sessions (token, user_id) VALUES ($1, $2)', [token, userId]);
  return token;
}

export async function getUserBySession(token: string): Promise<User | null> {
  await ensureSessions();
  const { rows } = await query<UserRow>(
    'SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = $1',
    [token],
  );
  return rows[0] ? mapUser(rows[0]) : null;
}

export async function deleteSession(token: string): Promise<void> {
  await ensureSessions();
  await query('DELETE FROM sessions WHERE token = $1', [token]);
}

// Friend requests and invites. A friendship exists only once both people have chosen a circle:
// the sender picks theirs when sending, the recipient when accepting.
let friendRequestsReady: Promise<unknown> | null = null;
function ensureFriendRequests(): Promise<unknown> {
  friendRequestsReady ??= query(`
    CREATE TABLE IF NOT EXISTS friend_requests (
      id TEXT PRIMARY KEY,
      from_user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      to_user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      from_tier TEXT NOT NULL CHECK (from_tier IN ('friend', 'close', 'closest')),
      status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      responded_at TIMESTAMPTZ,
      CHECK (from_user_id <> to_user_id)
    );
    CREATE UNIQUE INDEX IF NOT EXISTS friend_requests_one_pending
      ON friend_requests (from_user_id, to_user_id) WHERE status = 'pending';
    CREATE TABLE IF NOT EXISTS invites (
      code TEXT PRIMARY KEY,
      from_user_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
      from_tier TEXT NOT NULL CHECK (from_tier IN ('friend', 'close', 'closest')),
      channel TEXT NOT NULL CHECK (channel IN ('sms', 'email', 'link')),
      contact TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      redeemed_by TEXT REFERENCES users (id) ON DELETE SET NULL,
      redeemed_at TIMESTAMPTZ
    );`);
  return friendRequestsReady;
}

export type FriendRequest = { id: string; user: User; createdAt: string };

type FriendRequestRow = UserRow & { request_id: string; request_created_at: Date };

function mapFriendRequest(row: FriendRequestRow): FriendRequest {
  return { id: row.request_id, user: mapUser(row), createdAt: row.request_created_at.toISOString() };
}

/** Pending requests both ways, plus your sent requests accepted in the last day (for "X accepted"). */
export async function listFriendRequests(userId: string): Promise<{
  incoming: FriendRequest[];
  outgoing: FriendRequest[];
  accepted: FriendRequest[];
}> {
  await ensureFriendRequests();
  const select = (otherSide: 'from_user_id' | 'to_user_id', mine: 'from_user_id' | 'to_user_id', where: string) =>
    query<FriendRequestRow>(
      `SELECT r.id AS request_id, r.created_at AS request_created_at, u.*
       FROM friend_requests r JOIN users u ON u.id = r.${otherSide}
       WHERE r.${mine} = $1 AND ${where}
       ORDER BY r.created_at DESC`,
      [userId],
    );
  const [incoming, outgoing, accepted] = await Promise.all([
    select('from_user_id', 'to_user_id', `r.status = 'pending'`),
    select('to_user_id', 'from_user_id', `r.status = 'pending'`),
    select('to_user_id', 'from_user_id', `r.status = 'accepted' AND r.responded_at > now() - interval '1 day'`),
  ]);
  return {
    incoming: incoming.rows.map(mapFriendRequest),
    outgoing: outgoing.rows.map(mapFriendRequest),
    accepted: accepted.rows.map(mapFriendRequest),
  };
}

export async function areFriends(a: string, b: string): Promise<boolean> {
  const { rowCount } = await query(
    'SELECT 1 FROM friendships WHERE user_id = $1 AND friend_id = $2',
    [a, b],
  );
  return (rowCount ?? 0) > 0;
}

async function getFriendRequest(id: string): Promise<FriendRequest | null> {
  const { rows } = await query<FriendRequestRow>(
    `SELECT r.id AS request_id, r.created_at AS request_created_at, u.*
     FROM friend_requests r JOIN users u ON u.id = r.to_user_id WHERE r.id = $1`,
    [id],
  );
  return rows[0] ? mapFriendRequest(rows[0]) : null;
}

export type SendRequestResult =
  | { status: 'pending'; request: FriendRequest }
  | { status: 'accepted'; friend: FriendEntry }
  | { status: 'already_friends' }
  | { status: 'not_found' };

/**
 * Sends a request with the circle the sender chose. If the other person already asked,
 * this accepts theirs instead, since both sides have now chosen.
 */
export async function sendFriendRequest(fromId: string, toId: string, tier: Tier): Promise<SendRequestResult> {
  await ensureFriendRequests();
  if (fromId === toId || !(await getUser(toId))) return { status: 'not_found' };
  if (await areFriends(fromId, toId)) return { status: 'already_friends' };

  const reverse = await query<{ id: string }>(
    `SELECT id FROM friend_requests WHERE from_user_id = $1 AND to_user_id = $2 AND status = 'pending'`,
    [toId, fromId],
  );
  if (reverse.rows[0]) {
    const friend = await acceptFriendRequest(reverse.rows[0].id, fromId, tier);
    if (friend) return { status: 'accepted', friend };
  }

  const id = `fr_${randomBytes(8).toString('hex')}`;
  const { rows } = await query<{ id: string }>(
    `INSERT INTO friend_requests (id, from_user_id, to_user_id, from_tier) VALUES ($1, $2, $3, $4)
     ON CONFLICT (from_user_id, to_user_id) WHERE status = 'pending'
     DO UPDATE SET from_tier = EXCLUDED.from_tier
     RETURNING id`,
    [id, fromId, toId, tier],
  );
  const request = await getFriendRequest(rows[0].id);
  return request ? { status: 'pending', request } : { status: 'not_found' };
}

/** Only the recipient can accept. Creates both directions of the friendship. */
export async function acceptFriendRequest(id: string, userId: string, tier: Tier): Promise<FriendEntry | null> {
  await ensureFriendRequests();
  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query<{ from_user_id: string; from_tier: Tier }>(
      `UPDATE friend_requests SET status = 'accepted', responded_at = now()
       WHERE id = $1 AND to_user_id = $2 AND status = 'pending'
       RETURNING from_user_id, from_tier`,
      [id, userId],
    );
    const request = rows[0];
    if (!request) {
      await client.query('ROLLBACK');
      return null;
    }
    const upsert = `INSERT INTO friendships (user_id, friend_id, tier) VALUES ($1, $2, $3)
      ON CONFLICT (user_id, friend_id) DO UPDATE SET tier = EXCLUDED.tier`;
    await client.query(upsert, [request.from_user_id, userId, request.from_tier]);
    await client.query(upsert, [userId, request.from_user_id, tier]);
    await client.query('COMMIT');
    const friend = await getUser(request.from_user_id);
    return friend ? { friend, tier } : null;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/** Decline (recipient) or cancel (sender). Returns false if there was nothing pending to close. */
export async function closeFriendRequest(id: string, userId: string, as: 'declined' | 'cancelled'): Promise<boolean> {
  await ensureFriendRequests();
  const column = as === 'declined' ? 'to_user_id' : 'from_user_id';
  const { rowCount } = await query(
    `UPDATE friend_requests SET status = $3, responded_at = now()
     WHERE id = $1 AND ${column} = $2 AND status = 'pending'`,
    [id, userId, as],
  );
  return (rowCount ?? 0) > 0;
}

export type InviteChannel = 'sms' | 'email' | 'link';

export async function createInvite(
  fromId: string,
  tier: Tier,
  channel: InviteChannel,
  contact: string | null,
): Promise<string> {
  await ensureFriendRequests();
  const code = randomBytes(6).toString('base64url');
  await query(
    'INSERT INTO invites (code, from_user_id, from_tier, channel, contact) VALUES ($1, $2, $3, $4, $5)',
    [code, fromId, tier, channel, contact],
  );
  return code;
}

export async function getInviter(code: string): Promise<User | null> {
  await ensureFriendRequests();
  const { rows } = await query<UserRow>(
    'SELECT u.* FROM invites i JOIN users u ON u.id = i.from_user_id WHERE i.code = $1',
    [code],
  );
  return rows[0] ? mapUser(rows[0]) : null;
}

export type RedeemResult =
  | { status: 'not_found' | 'used' | 'own_invite' }
  | { status: 'friends'; inviter: User }
  | { status: 'pending'; inviter: User; request: FriendRequest };

/**
 * Opening an invite turns it into a friend request from the inviter, waiting for you to accept.
 * Each invite works once, so a forwarded link can't be reused by someone else.
 */
export async function redeemInvite(code: string, userId: string): Promise<RedeemResult> {
  await ensureFriendRequests();
  const { rows } = await query<{ from_user_id: string; from_tier: Tier; redeemed_by: string | null }>(
    'SELECT from_user_id, from_tier, redeemed_by FROM invites WHERE code = $1',
    [code],
  );
  const invite = rows[0];
  if (!invite) return { status: 'not_found' };
  if (invite.from_user_id === userId) return { status: 'own_invite' };
  if (invite.redeemed_by && invite.redeemed_by !== userId) return { status: 'used' };
  const inviter = await getUser(invite.from_user_id);
  if (!inviter) return { status: 'not_found' };

  await query(
    'UPDATE invites SET redeemed_by = $2, redeemed_at = COALESCE(redeemed_at, now()) WHERE code = $1',
    [code, userId],
  );
  const result = await sendFriendRequest(invite.from_user_id, userId, invite.from_tier);
  if (result.status === 'pending') {
    // The request is from the inviter, so show the inviter on the recipient's side.
    return { status: 'pending', inviter, request: { ...result.request, user: inviter } };
  }
  return { status: 'friends', inviter };
}

/** Email invites wait for that address to sign in, so the person doesn't need the link. */
export async function claimEmailInvites(user: User): Promise<void> {
  await ensureFriendRequests();
  const { rows } = await query<{ code: string }>(
    `SELECT code FROM invites
     WHERE channel = 'email' AND lower(contact) = lower($1) AND redeemed_by IS NULL AND from_user_id <> $2`,
    [user.email, user.id],
  );
  for (const { code } of rows) await redeemInvite(code, user.id);
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

export function toCalendarEvents(events: DbEvent[]): CalendarEvent[] {
  return events.map((e) => ({
    title: e.title,
    start: e.start,
    end: e.end,
    location: e.location ?? undefined,
  }));
}

export function toEmailSnippets(emails: DbEmail[]): EmailSnippet[] {
  return emails.map((e) => ({
    from: e.fromAddr,
    subject: e.subject,
    snippet: e.snippet,
    date: e.date,
  }));
}

export async function replaceEmails(
  userId: string,
  emails: EmailSnippet[],
): Promise<DbEmail[]> {
  await query('DELETE FROM emails WHERE user_id = $1', [userId]);
  const out: DbEmail[] = [];
  for (const email of emails) {
    const { rows } = await query<EmailRow>(
      `INSERT INTO emails (user_id, from_addr, subject, snippet, date)
       VALUES ($1, $2, $3, $4, $5::timestamptz)
       RETURNING id, user_id, from_addr, subject, snippet, date`,
      [userId, email.from, email.subject, email.snippet, email.date],
    );
    if (rows[0]) out.push(mapEmail(rows[0]));
  }
  return out;
}

export async function deleteEmails(userId: string): Promise<void> {
  await query('DELETE FROM emails WHERE user_id = $1', [userId]);
}

export async function listProviders(userId: string): Promise<string[]> {
  const { rows } = await query<{ provider: string }>(
    `SELECT provider FROM connections WHERE user_id = $1`,
    [userId],
  );
  return rows.map((r) => r.provider);
}

export async function hasIcsEvents(userId: string): Promise<boolean> {
  const { rows } = await query<{ ok: number }>(
    `SELECT 1 AS ok FROM events WHERE user_id = $1 AND source = 'ics' LIMIT 1`,
    [userId],
  );
  return rows.length > 0;
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

export type DbSignal = {
  id: number;
  userId: string;
  supportLevel: SupportLevel;
  stressors: Signals['stressors'];
  busyHours: number;
  likelyLocation: string | null;
  summaryForClosest: string;
  summaryForClose: string;
  createdAt: string;
};

type SignalRow = {
  id: number;
  user_id: string;
  support_level: string;
  stressors: unknown;
  busy_hours: number;
  likely_location: string | null;
  summary_for_closest: string;
  summary_for_close: string;
  created_at: Date | string;
};

function parseStressors(value: unknown): Signals['stressors'] {
  if (typeof value === 'string') {
    return JSON.parse(value) as Signals['stressors'];
  }
  return (value ?? []) as Signals['stressors'];
}

function mapSignal(row: SignalRow): DbSignal {
  return {
    id: row.id,
    userId: row.user_id,
    supportLevel: row.support_level as SupportLevel,
    stressors: parseStressors(row.stressors),
    busyHours: row.busy_hours,
    likelyLocation: row.likely_location,
    summaryForClosest: row.summary_for_closest,
    summaryForClose: row.summary_for_close,
    createdAt: toIso(row.created_at),
  };
}

export function toSignals(row: DbSignal): Signals {
  return {
    supportLevel: row.supportLevel,
    stressors: row.stressors,
    busyHoursNext3Days: row.busyHours,
    likelyLocation: row.likelyLocation ?? undefined,
    summaryForClosest: row.summaryForClosest,
    summaryForClose: row.summaryForClose,
  };
}

export async function getLatestSignal(userId: string): Promise<DbSignal | null> {
  const { rows } = await query<SignalRow>(
    `SELECT * FROM signals WHERE user_id = $1 ORDER BY created_at DESC LIMIT 1`,
    [userId],
  );
  return rows[0] ? mapSignal(rows[0]) : null;
}

export async function saveSignals(
  userId: string,
  signals: Signals,
): Promise<DbSignal> {
  const id = await insertSignal({
    userId,
    supportLevel: signals.supportLevel,
    stressors: signals.stressors,
    busyHours: signals.busyHoursNext3Days,
    likelyLocation: signals.likelyLocation ?? null,
    summaryForClosest: signals.summaryForClosest,
    summaryForClose: signals.summaryForClose,
  });
  const latest = await getLatestSignal(userId);
  if (!latest || latest.id !== id) {
    throw new Error('Failed to read back saved signals');
  }
  return latest;
}

type NudgeRow = {
  id: string;
  from_user_id: string;
  to_friend_id: string;
  message: string;
  context_level: 'closest' | 'close';
  status: 'sent' | 'seen' | 'acted';
  created_at: Date | string;
  draft_note?: string | null;
  reason?: string | null;
  moment?: string | null;
};

export type DbNudge = {
  id: string;
  fromUserId: string;
  toFriendId: string;
  message: string;
  contextLevel: 'closest' | 'close';
  status: 'sent' | 'seen' | 'acted';
  createdAt: string;
  draftNote?: string;
  reason?: string;
  moment?: string;
};

function mapNudgeRow(row: NudgeRow): DbNudge {
  return {
    id: row.id,
    fromUserId: row.from_user_id,
    toFriendId: row.to_friend_id,
    message: row.message,
    contextLevel: row.context_level,
    status: row.status,
    createdAt: toIso(row.created_at),
    draftNote: row.draft_note ?? undefined,
    reason: row.reason ?? undefined,
    moment: row.moment ?? undefined,
  };
}

async function hydrateNudge(row: DbNudge): Promise<Nudge | null> {
  const fromUser = await getUser(row.fromUserId);
  if (!fromUser) return null;
  return {
    id: row.id,
    fromUser,
    toFriendId: row.toFriendId,
    message: row.message,
    contextLevel: row.contextLevel,
    status: row.status,
    createdAt: row.createdAt,
    draftNote: row.draftNote,
    reason: row.reason,
    moment: row.moment,
  };
}

// Databases created before these existed get them on first use, so no reset is needed.
let twinExtrasReady: Promise<unknown> | null = null;
export function ensureTwinExtras(): Promise<unknown> {
  twinExtrasReady ??= query(`
    ALTER TABLE nudges ADD COLUMN IF NOT EXISTS draft_note TEXT;
    ALTER TABLE nudges ADD COLUMN IF NOT EXISTS reason TEXT;
    ALTER TABLE nudges ADD COLUMN IF NOT EXISTS moment TEXT;
    ALTER TABLE gestures ADD COLUMN IF NOT EXISTS reaction TEXT;
    ALTER TABLE gestures ADD COLUMN IF NOT EXISTS reacted_at TIMESTAMPTZ;
    CREATE TABLE IF NOT EXISTS summary_overrides (
      user_id TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
      summary_for_closest TEXT NOT NULL,
      summary_for_close TEXT NOT NULL
    );`);
  return twinExtrasReady;
}

export async function insertNudge(input: {
  id: string;
  fromUserId: string;
  toFriendId: string;
  message: string;
  contextLevel: 'closest' | 'close';
  status?: 'sent' | 'seen' | 'acted';
  draftNote?: string;
  reason?: string;
}): Promise<void> {
  await ensureTwinExtras();
  await query(
    `INSERT INTO nudges (id, from_user_id, to_friend_id, message, context_level, status, draft_note, reason)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     ON CONFLICT (id) DO UPDATE SET
       message = EXCLUDED.message,
       context_level = EXCLUDED.context_level,
       status = EXCLUDED.status,
       draft_note = EXCLUDED.draft_note,
       reason = EXCLUDED.reason`,
    [
      input.id,
      input.fromUserId,
      input.toFriendId,
      input.message,
      input.contextLevel,
      input.status ?? 'sent',
      input.draftNote ?? null,
      input.reason ?? null,
    ],
  );
}

/** Muse's starter surprise note for a nudge, if the twin wrote one. */
export async function getNudgeDraftNote(id: string): Promise<string | null> {
  await ensureTwinExtras();
  const { rows } = await query<{ draft_note: string | null }>(
    `SELECT draft_note FROM nudges WHERE id = $1`,
    [id],
  );
  return rows[0]?.draft_note ?? null;
}

/** Saves the moment the friend's twin found for showing up. */
export async function setNudgeMoment(id: string, moment: string): Promise<void> {
  await ensureTwinExtras();
  await query(`UPDATE nudges SET moment = $2 WHERE id = $1`, [id, moment]);
}

/** The person's own wording for what each tier hears; survives twin refreshes. */
export async function getSummaryOverride(
  userId: string,
): Promise<{ summaryForClosest: string; summaryForClose: string } | null> {
  await ensureTwinExtras();
  const { rows } = await query<{ summary_for_closest: string; summary_for_close: string }>(
    `SELECT summary_for_closest, summary_for_close FROM summary_overrides WHERE user_id = $1`,
    [userId],
  );
  const row = rows[0];
  return row ? { summaryForClosest: row.summary_for_closest, summaryForClose: row.summary_for_close } : null;
}

export async function setSummaryOverride(userId: string, closest: string, close: string): Promise<void> {
  await ensureTwinExtras();
  await query(
    `INSERT INTO summary_overrides (user_id, summary_for_closest, summary_for_close)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id) DO UPDATE SET
       summary_for_closest = EXCLUDED.summary_for_closest,
       summary_for_close = EXCLUDED.summary_for_close`,
    [userId, closest, close],
  );
}

export async function deleteSummaryOverride(userId: string): Promise<void> {
  await ensureTwinExtras();
  await query(`DELETE FROM summary_overrides WHERE user_id = $1`, [userId]);
}

/** Gestures `fromUserId` gave `toUserId` in the last two weeks, newest first. */
export async function recentGesturesBetween(
  fromUserId: string,
  toUserId: string,
): Promise<{ type: string; placeName: string | null; deliveredAt: string }[]> {
  const { rows } = await query<{ type: string; place_name: string | null; delivered_at: Date | string }>(
    `SELECT g.type, g.place_name, g.delivered_at
     FROM gestures g JOIN nudges n ON n.id = g.nudge_id
     WHERE g.from_friend_id = $1 AND n.from_user_id = $2
       AND g.delivered_at > now() - interval '14 days'
     ORDER BY g.delivered_at DESC`,
    [fromUserId, toUserId],
  );
  return rows.map((r) => ({ type: r.type, placeName: r.place_name, deliveredAt: toIso(r.delivered_at) }));
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

export async function deleteUnactedNudgesFrom(userId: string): Promise<void> {
  await query(
    `DELETE FROM nudges WHERE from_user_id = $1 AND status <> 'acted'`,
    [userId],
  );
}

export async function getNudge(id: string): Promise<Nudge | null> {
  const { rows } = await query<NudgeRow>(`SELECT * FROM nudges WHERE id = $1`, [id]);
  const row = rows[0];
  if (!row) return null;
  return hydrateNudge(mapNudgeRow(row));
}

export async function listNudgesForUser(userId: string): Promise<DbNudge[]> {
  const { rows } = await query<NudgeRow>(
    `SELECT * FROM nudges
     WHERE from_user_id = $1 OR to_friend_id = $1
     ORDER BY created_at DESC`,
    [userId],
  );
  return rows.map(mapNudgeRow);
}

/** Nudges addressed to this user (inbox). */
export async function listNudgesToUser(userId: string): Promise<Nudge[]> {
  const { rows } = await query<NudgeRow>(
    `SELECT * FROM nudges WHERE to_friend_id = $1 ORDER BY created_at DESC`,
    [userId],
  );
  const out: Nudge[] = [];
  for (const row of rows) {
    const nudge = await hydrateNudge(mapNudgeRow(row));
    // The reason is written for the sender's privacy log, not for the friend.
    if (nudge) out.push({ ...nudge, reason: undefined });
  }
  return out;
}

/** Acted nudges this user previously sent (privacy log). */
export async function listActedNudgesFromUser(userId: string): Promise<Nudge[]> {
  const { rows } = await query<NudgeRow>(
    `SELECT * FROM nudges
     WHERE from_user_id = $1 AND status = 'acted'
     ORDER BY created_at DESC`,
    [userId],
  );
  const out: Nudge[] = [];
  for (const row of rows) {
    const nudge = await hydrateNudge(mapNudgeRow(row));
    if (nudge) out.push(nudge);
  }
  return out;
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

type GestureRow = {
  id: string;
  nudge_id: string;
  from_friend_id: string;
  type: string;
  place_name: string | null;
  place_address: string | null;
  note: string;
  delivered_at: Date | string;
  reaction?: 'helped' | 'space' | null;
};

export type DbGesture = {
  id: string;
  nudgeId: string;
  fromFriendId: string;
  type: string;
  placeName: string | null;
  placeAddress: string | null;
  note: string;
  deliveredAt: string;
  reaction?: 'helped' | 'space';
};

function mapGestureRow(row: GestureRow): DbGesture {
  return {
    id: row.id,
    nudgeId: row.nudge_id,
    fromFriendId: row.from_friend_id,
    type: row.type,
    placeName: row.place_name,
    placeAddress: row.place_address,
    note: row.note,
    deliveredAt: toIso(row.delivered_at),
    reaction: row.reaction ?? undefined,
  };
}

/**
 * The person helped tells their twin how a surprise landed. Only they can react,
 * and only to gestures made for them. Returns false if it isn't theirs.
 */
export async function setGestureReaction(
  gestureId: string,
  userId: string,
  reaction: 'helped' | 'space',
): Promise<boolean> {
  await ensureTwinExtras();
  const { rowCount } = await query(
    `UPDATE gestures g SET reaction = $3, reacted_at = now()
     FROM nudges n
     WHERE g.id = $1 AND n.id = g.nudge_id AND n.from_user_id = $2`,
    [gestureId, userId, reaction],
  );
  return (rowCount ?? 0) > 0;
}

/** How `personId` last reacted to something `friendId` did for them, if they did. */
export async function latestReaction(
  personId: string,
  friendId: string,
): Promise<'helped' | 'space' | null> {
  await ensureTwinExtras();
  const { rows } = await query<{ reaction: 'helped' | 'space' }>(
    `SELECT g.reaction FROM gestures g JOIN nudges n ON n.id = g.nudge_id
     WHERE n.from_user_id = $1 AND g.from_friend_id = $2 AND g.reaction IS NOT NULL
     ORDER BY g.reacted_at DESC LIMIT 1`,
    [personId, friendId],
  );
  return rows[0]?.reaction ?? null;
}

/** "I needed space" last time means a note instead of showing up, whatever the free-time rule says. */
export async function respectReaction(
  personId: string,
  friendId: string,
  gestureType: GestureType,
): Promise<GestureType> {
  return (await latestReaction(personId, friendId)) === 'space' ? 'message' : gestureType;
}

async function hydrateGesture(row: DbGesture): Promise<Gesture | null> {
  const fromFriend = await getUser(row.fromFriendId);
  if (!fromFriend) return null;
  const gesture: Gesture = {
    id: row.id,
    nudgeId: row.nudgeId,
    fromFriend,
    type: row.type as GestureType,
    note: row.note,
    deliveredAt: row.deliveredAt,
    reaction: row.reaction,
  };
  if (row.placeName) {
    const place: Place = {
      name: row.placeName,
      address: row.placeAddress ?? row.placeName,
    };
    gesture.place = place;
  }
  return gesture;
}

export async function listGesturesForUser(userId: string): Promise<DbGesture[]> {
  const { rows } = await query<GestureRow>(
    `SELECT g.*
     FROM gestures g
     JOIN nudges n ON n.id = g.nudge_id
     WHERE g.from_friend_id = $1 OR n.to_friend_id = $1 OR n.from_user_id = $1
     ORDER BY g.delivered_at DESC`,
    [userId],
  );
  return rows.map(mapGestureRow);
}

/** Gestures that help this user (they were the twin/nudge subject). */
export async function listSurprisesForUser(userId: string): Promise<Gesture[]> {
  const { rows } = await query<GestureRow>(
    `SELECT g.*
     FROM gestures g
     JOIN nudges n ON n.id = g.nudge_id
     WHERE n.from_user_id = $1
     ORDER BY g.delivered_at DESC`,
    [userId],
  );
  const out: Gesture[] = [];
  for (const row of rows) {
    const gesture = await hydrateGesture(mapGestureRow(row));
    if (gesture) out.push(gesture);
  }
  return out;
}

export async function getGesture(id: string): Promise<Gesture | null> {
  const { rows } = await query<GestureRow>(`SELECT * FROM gestures WHERE id = $1`, [
    id,
  ]);
  const row = rows[0];
  if (!row) return null;
  return hydrateGesture(mapGestureRow(row));
}
