export { filterEmails, extractSignals } from './extract.js';
export { decideNudges } from './twin.js';
export { planMoment } from './moment.js';

// Kept from Person A's scaffold stub.
import { getEmailsFor, getEventsFor } from '../mocks.js';
import { filterEmails } from './extract.js';

/** Helper used by ingest stubs */
export function mockIngestPayload(userId: string) {
  return {
    events: getEventsFor(userId),
    emails: filterEmails(getEmailsFor(userId)),
  };
}
