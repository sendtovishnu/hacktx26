import {
  getDecisionsFor,
  getEmailsFor,
  getEventsFor,
  getSignalsFor,
} from '../mocks.js';
import type {
  CalendarEvent,
  EmailSnippet,
  Signals,
  TwinDecision,
  TwinFriendInput,
  User,
} from '../types.js';

/** STUB — Person B owns real impl. Fixtures so USE_MOCKS=false demos still work. */
export function filterEmails(emails: EmailSnippet[]): EmailSnippet[] {
  return emails.filter(
    (e) =>
      !/newsletter|promo|% off/i.test(e.subject) &&
      !/newsletter|promo/i.test(e.from),
  );
}

/** STUB — Person B owns real impl. Fixtures so USE_MOCKS=false demos still work. */
export async function extractSignals(
  events: CalendarEvent[],
  emails: EmailSnippet[],
  checkin?: string,
): Promise<Signals> {
  void events;
  void emails;
  void checkin;
  return (
    getSignalsFor('u_maya') ?? {
      supportLevel: 'doing_fine',
      stressors: [],
      busyHoursNext3Days: 0,
      summaryForClosest: 'No signals yet.',
      summaryForClose: 'No signals yet.',
    }
  );
}

/** STUB — Person B owns real impl. Fixtures so USE_MOCKS=false demos still work. */
export async function decideNudges(
  user: User,
  signals: Signals,
  friends: TwinFriendInput[],
): Promise<TwinDecision[]> {
  void signals;
  void friends;
  return getDecisionsFor(user.id);
}

/** Helper used by ingest stubs */
export function mockIngestPayload(userId: string) {
  return {
    events: getEventsFor(userId),
    emails: filterEmails(getEmailsFor(userId)),
  };
}
