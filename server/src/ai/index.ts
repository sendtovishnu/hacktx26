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

const useMocks = () => process.env.USE_MOCKS !== 'false';

/** STUB — Person B owns real impl */
export function filterEmails(emails: EmailSnippet[]): EmailSnippet[] {
  if (useMocks()) {
    return emails.filter(
      (e) =>
        !/newsletter|promo|% off/i.test(e.subject) &&
        !/newsletter|promo/i.test(e.from),
    );
  }
  return emails;
}

/** STUB — Person B owns real impl */
export async function extractSignals(
  events: CalendarEvent[],
  emails: EmailSnippet[],
  checkin?: string,
): Promise<Signals> {
  void events;
  void emails;
  void checkin;
  if (useMocks()) {
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
  throw new Error('extractSignals not implemented without USE_MOCKS');
}

/** STUB — Person B owns real impl */
export async function decideNudges(
  user: User,
  signals: Signals,
  friends: TwinFriendInput[],
): Promise<TwinDecision[]> {
  void signals;
  void friends;
  if (useMocks()) {
    return getDecisionsFor(user.id);
  }
  throw new Error('decideNudges not implemented without USE_MOCKS');
}

/** Helper used by ingest stubs */
export function mockIngestPayload(userId: string) {
  return {
    events: getEventsFor(userId),
    emails: filterEmails(getEmailsFor(userId)),
  };
}
