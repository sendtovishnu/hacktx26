import { google } from 'googleapis';
import ical, { type CalendarComponent, type VEvent } from 'node-ical';
import {
  deleteEmails,
  getConnection,
  query,
  replaceEvents,
  upsertConnection,
  useDatabase,
} from '../db/index.js';
import { getEmailsFor, getEventsFor } from '../mocks.js';
import type { CalendarEvent, EmailSnippet } from '../types.js';

const GOOGLE_SCOPES = [
  'https://www.googleapis.com/auth/calendar.readonly',
  'https://www.googleapis.com/auth/gmail.metadata',
].join(' ');

export function googleStatus(): { configured: boolean } {
  return {
    configured: Boolean(
      process.env.GOOGLE_WEB_CLIENT_ID?.trim() &&
        process.env.GOOGLE_WEB_CLIENT_SECRET?.trim(),
    ),
  };
}

function useMockGooglePath(): boolean {
  return process.env.USE_MOCKS === 'true' || !googleStatus().configured;
}

function oauthClient() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_WEB_CLIENT_ID,
    process.env.GOOGLE_WEB_CLIENT_SECRET,
    process.env.GOOGLE_OAUTH_REDIRECT_URI ?? 'postmessage',
  );
}

/** True when a stored connection has a real access token (not a stub). */
export async function hasRealGoogleTokens(userId: string): Promise<boolean> {
  if (!useDatabase()) return false;
  const conn = await getConnection(userId, 'google');
  return Boolean(conn?.accessToken && conn.accessToken !== 'stub');
}

/**
 * Exchange an auth code for tokens when credentials are present and USE_MOCKS
 * is not forced. Otherwise record an optional stub connection and succeed.
 */
export async function exchangeGoogleAuth(
  userId: string,
  code?: string,
): Promise<{ connected: true; stub?: boolean }> {
  if (useMockGooglePath()) {
    if (useDatabase()) {
      await upsertConnection({
        userId,
        provider: 'google',
        accessToken: 'stub',
        refreshToken: null,
        scopes: GOOGLE_SCOPES,
      });
    }
    return { connected: true, stub: true };
  }

  if (!code?.trim()) {
    throw new Error('Missing authorization code for Google exchange');
  }

  const client = oauthClient();
  const { tokens } = await client.getToken(code);
  if (useDatabase()) {
    await upsertConnection({
      userId,
      provider: 'google',
      accessToken: tokens.access_token ?? null,
      refreshToken: tokens.refresh_token ?? null,
      scopes: tokens.scope ?? GOOGLE_SCOPES,
    });
  }
  return { connected: true };
}

function isVEvent(value: CalendarComponent): value is VEvent {
  return value.type === 'VEVENT';
}

/** Parse an .ics buffer/string into CalendarEvent rows. */
export function parseIcs(data: string | Buffer): CalendarEvent[] {
  const parsed = ical.sync.parseICS(
    typeof data === 'string' ? data : data.toString('utf8'),
  );
  const events: CalendarEvent[] = [];
  for (const value of Object.values(parsed)) {
    if (!value || typeof value !== 'object' || !('type' in value)) continue;
    const component = value as CalendarComponent;
    if (!isVEvent(component)) continue;
    if (component.status === 'CANCELLED') continue;
    const start = component.start ? new Date(component.start) : null;
    const end = component.end
      ? new Date(component.end)
      : start
        ? new Date(start.getTime() + 60 * 60 * 1000)
        : null;
    if (!start || !end || Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
      continue;
    }
    if (end <= start) continue;
    const location =
      typeof component.location === 'string' && component.location.trim()
        ? component.location.trim()
        : undefined;
    events.push({
      title: (component.summary || 'Untitled').toString(),
      start: start.toISOString(),
      end: end.toISOString(),
      ...(location ? { location } : {}),
    });
  }
  events.sort((a, b) => a.start.localeCompare(b.start));
  return events;
}

async function replaceEmails(
  userId: string,
  emails: EmailSnippet[],
): Promise<number> {
  await deleteEmails(userId);
  let count = 0;
  for (const email of emails) {
    await query(
      `INSERT INTO emails (user_id, from_addr, subject, snippet, date)
       VALUES ($1, $2, $3, $4, $5::timestamptz)`,
      [userId, email.from, email.subject, email.snippet, email.date],
    );
    count += 1;
  }
  return count;
}

/** Persist ICS-parsed events for a user (source = ics), keeping google rows. */
export async function storeIcsEvents(
  userId: string,
  events: CalendarEvent[],
): Promise<number> {
  if (!useDatabase()) return events.length;

  const { rows: googleRows } = await query<{
    title: string;
    start: Date | string;
    end: Date | string;
    location: string | null;
  }>(
    `SELECT title, "start", "end", location FROM events WHERE user_id = $1 AND source = 'google'`,
    [userId],
  );

  const toIso = (value: Date | string) =>
    value instanceof Date ? value.toISOString() : new Date(value).toISOString();

  await replaceEvents(userId, [
    ...googleRows.map((row) => ({
      title: row.title,
      start: toIso(row.start),
      end: toIso(row.end),
      location: row.location,
      source: 'google' as const,
    })),
    ...events.map((e) => ({
      title: e.title,
      start: e.start,
      end: e.end,
      location: e.location ?? null,
      source: 'ics' as const,
    })),
  ]);
  return events.length;
}

async function loadMockPayloadIntoDb(userId: string): Promise<{
  events: number;
  emails: number;
}> {
  const events = getEventsFor(userId);
  const emails = getEmailsFor(userId);
  await replaceEvents(
    userId,
    events.map((e) => ({
      title: e.title,
      start: e.start,
      end: e.end,
      location: e.location ?? null,
      source: 'google' as const,
    })),
  );
  const emailCount = await replaceEmails(userId, emails);
  return { events: events.length, emails: emailCount };
}

async function pullGoogleCalendarAndGmail(userId: string): Promise<{
  events: number;
  emails: number;
}> {
  const conn = await getConnection(userId, 'google');
  if (!conn?.accessToken) {
    throw new Error('No Google tokens for user');
  }

  const client = oauthClient();
  client.setCredentials({
    access_token: conn.accessToken,
    refresh_token: conn.refreshToken ?? undefined,
  });
  client.on('tokens', async (tokens) => {
    if (tokens.access_token) {
      await upsertConnection({
        userId,
        provider: 'google',
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token ?? conn.refreshToken,
        scopes: conn.scopes,
      });
    }
  });

  const now = Date.now();
  const weekMs = 7 * 24 * 60 * 60 * 1000;
  const timeMin = new Date(now).toISOString();
  const timeMax = new Date(now + weekMs).toISOString();
  const afterMs = now - weekMs;

  const calendar = google.calendar({ version: 'v3', auth: client });
  const gmail = google.gmail({ version: 'v1', auth: client });

  const calRes = await calendar.events.list({
    calendarId: 'primary',
    timeMin,
    timeMax,
    singleEvents: true,
    orderBy: 'startTime',
    maxResults: 100,
  });

  const events: CalendarEvent[] = [];
  for (const item of calRes.data.items ?? []) {
    const startRaw = item.start?.dateTime ?? item.start?.date;
    const endRaw = item.end?.dateTime ?? item.end?.date;
    if (!startRaw || !endRaw) continue;
    const start = new Date(startRaw);
    const end = new Date(endRaw);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) continue;
    if (end <= start) continue;
    events.push({
      title: item.summary || 'Untitled',
      start: start.toISOString(),
      end: end.toISOString(),
      ...(item.location ? { location: item.location } : {}),
    });
  }

  await replaceEvents(
    userId,
    events.map((e) => ({
      title: e.title,
      start: e.start,
      end: e.end,
      location: e.location ?? null,
      source: 'google' as const,
    })),
  );

  const list = await gmail.users.messages.list({
    userId: 'me',
    q: `after:${Math.floor(afterMs / 1000)}`,
    maxResults: 50,
  });

  const emails: EmailSnippet[] = [];
  for (const msg of list.data.messages ?? []) {
    if (!msg.id) continue;
    const full = await gmail.users.messages.get({
      userId: 'me',
      id: msg.id,
      format: 'metadata',
      metadataHeaders: ['From', 'Subject', 'Date'],
    });
    const headers = full.data.payload?.headers ?? [];
    const getHeader = (name: string) =>
      headers.find((h) => h.name?.toLowerCase() === name.toLowerCase())
        ?.value ?? '';
    const internalDate = full.data.internalDate
      ? new Date(Number(full.data.internalDate))
      : new Date();
    emails.push({
      from: getHeader('From') || 'unknown',
      subject: getHeader('Subject') || '',
      snippet: full.data.snippet ?? '',
      date: internalDate.toISOString(),
    });
  }

  const emailCount = await replaceEmails(userId, emails);
  return { events: events.length, emails: emailCount };
}

/**
 * Ingest Google calendar + gmail metadata for the demo user.
 * Without real tokens (or without DB), load mock/seeded fixtures.
 */
export async function ingestGoogle(userId: string): Promise<{
  events: number;
  emails: number;
  source: 'google' | 'mock';
}> {
  if (!useDatabase()) {
    const events = getEventsFor(userId);
    const emails = getEmailsFor(userId);
    return { events: events.length, emails: emails.length, source: 'mock' };
  }

  if (await hasRealGoogleTokens(userId)) {
    const counts = await pullGoogleCalendarAndGmail(userId);
    return { ...counts, source: 'google' };
  }

  const counts = await loadMockPayloadIntoDb(userId);
  return { ...counts, source: 'mock' };
}
