import { z } from 'zod';
import type { CalendarEvent, EmailSnippet, Signals } from '../types.js';
import { fixture } from './fixtures.js';
import { generateJSON } from './llm.js';
import { extractionPrompt } from './prompts.js';

const MAX_EMAILS = 30;

const DROP_SENDER = /no-?reply|newsletter|news@|marketing|promo|deals|offers|mailer|@(e|em|email|mail)\./i;
const DROP_SUBJECT = /% off|\bsale\b|unsubscribe|promo|coupon|deal|newsletter|limited time|order|shipped/i;
const KEEP = new RegExp(
  [
    '\\.edu\\b', 'canvas', 'instructure', 'gradescope', 'piazza', 'blackboard',
    'midterm', 'final', 'exam', 'quiz', 'test', 'due', 'deadline', 'assignment', 'homework', 'hw\\d',
    'lab', 'project', 'essay', 'paper', 'grade', 'office hours', 'review session', 'study', 'interview',
    'invitation', 'invite', 'calendar', 'rescheduled', 'moved', 'reminder',
  ].join('|'),
  'i',
);

/** Keeps school, deadline, assignment and calendar-invite emails; drops marketing. Newest first, max 30. */
export function filterEmails(emails: EmailSnippet[]): EmailSnippet[] {
  return emails
    .filter((e) => {
      const text = `${e.from} ${e.subject} ${e.snippet}`;
      // Calendar invites come from no-reply senders, so check them before the sender drop.
      if (/^invitation:|updated invitation/i.test(e.subject)) return true;
      if (DROP_SENDER.test(e.from) || DROP_SUBJECT.test(e.subject)) return false;
      return KEEP.test(text);
    })
    .sort((a, b) => Date.parse(b.date) - Date.parse(a.date))
    .slice(0, MAX_EMAILS);
}

const extractionSchema = z.object({
  support_level: z.enum(['doing_fine', 'could_use_support', 'struggling']),
  stressors: z.array(z.object({ what: z.string(), when: z.string() })).default([]),
  busy_hours_next_3_days: z.coerce.number(),
  likely_location: z.string().nullish(),
  summary_for_closest: z.string(),
  summary_for_close: z.string(),
});

export async function extractSignals(
  events: CalendarEvent[],
  emails: EmailSnippet[],
  checkin?: string,
): Promise<Signals> {
  const fallback = fixture<Signals>('signals_maya.json');
  const snake = await generateJSON(
    extractionPrompt(events, emails, checkin),
    extractionSchema,
    toSnake(fallback),
    'gemini',
  );
  return {
    supportLevel: snake.support_level,
    stressors: snake.stressors,
    busyHoursNext3Days: snake.busy_hours_next_3_days,
    likelyLocation: snake.likely_location ?? undefined,
    summaryForClosest: snake.summary_for_closest,
    summaryForClose: snake.summary_for_close,
  };
}

function toSnake(s: Signals): z.infer<typeof extractionSchema> {
  return {
    support_level: s.supportLevel,
    stressors: s.stressors,
    busy_hours_next_3_days: s.busyHoursNext3Days,
    likely_location: s.likelyLocation,
    summary_for_closest: s.summaryForClosest,
    summary_for_close: s.summaryForClose,
  };
}
