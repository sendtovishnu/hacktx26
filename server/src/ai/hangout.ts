import { z } from 'zod';
import type { User } from '../types.js';
import { generateJSON } from './llm.js';
import { sharedInterests } from './ideas.js';

/** One way two friends could spend time together, before a real place is found for it. */
export type HangoutIdea = {
  title: string;
  detail: string;
  /** What to search Google Maps for, like "bouldering gym". */
  search: string;
  /** The interest it's built on, if any. */
  interest?: string;
  /** True when both people listed that interest. */
  shared: boolean;
  /** Index into the free windows it was planned for; -1 when there were none. */
  window: number;
  /** "Saturday, 2–4pm" */
  when: string;
  /** A text the person could send their friend to suggest it. */
  message: string;
};

const ideasSchema = z.array(
  z.object({
    interest: z.string().max(40).nullish(),
    title: z.string().min(1).max(80),
    detail: z.string().min(1).max(160),
    search: z.string().min(2).max(60),
    window: z.number().int(),
    when: z.string().min(1).max(60),
    message: z.string().min(1).max(240),
  }),
);

const norm = (s: string) => s.trim().toLowerCase();
const first = (u: User) => u.name.split(' ')[0];

/** "Sat, Oct 31, 2:00 – 5:30 PM" in Austin time. */
export function windowLabel(w: { start: string; end: string }): string {
  const tz = 'America/Chicago';
  const day = new Date(w.start).toLocaleDateString('en-US', { timeZone: tz, weekday: 'short', month: 'short', day: 'numeric' });
  const time = (iso: string) => new Date(iso).toLocaleTimeString('en-US', { timeZone: tz, hour: 'numeric', minute: '2-digit' });
  return `${day}, ${time(w.start)} – ${time(w.end)}`;
}

/**
 * Just for fun, nothing to do with a hard week: things two friends could do together, built on
 * what they both love, each fitted into a time they're both free. Only the shared free windows
 * reach the model, never what's on either calendar.
 */
export async function planHangoutIdeas(input: {
  me: User;
  friend: User;
  windows: { start: string; end: string }[];
  near: string;
  /** Ideas already shown, for "Brainstorm more". */
  avoid?: string[];
}): Promise<HangoutIdea[]> {
  const { me, friend, windows, near, avoid = [] } = input;
  const mine = me.interests ?? [];
  const theirs = friend.interests ?? [];
  const shared = sharedInterests(mine, theirs);
  const all = [...new Set([...shared, ...mine, ...theirs].map((i) => i.trim()))];

  const basis = shared.length
    ? `They both love: ${shared.join(', ')}.${mine.length || theirs.length ? ` Also, ${first(me)} likes: ${mine.join(', ') || 'nothing listed'}; ${first(friend)} likes: ${theirs.join(', ') || 'nothing listed'}.` : ''}`
    : all.length
      ? `${first(me)} likes: ${mine.join(', ') || 'nothing listed'}. ${first(friend)} likes: ${theirs.join(', ') || 'nothing listed'}. No overlap, so find things both would enjoy.`
      : `Neither listed interests, so suggest easy classics most friends enjoy.`;
  const times = windows.length
    ? windows.map((w, i) => `${i}: ${windowLabel(w)}`).join('\n')
    : 'None known (calendars not connected). Use -1 for "window" and suggest a natural time like "Saturday afternoon".';

  const prompt = `${first(me)} wants to hang out with their friend ${first(friend)}, just for fun. Brainstorm 4 specific, local things they could do together.

${basis}
Build most ideas on interests they share; mix it up: at least one activity (not just food or coffee), and one low-key option.
"interest" names the interest it's built on, spelled exactly as listed, or null.
"search" is what to type into Google Maps to find where to do it: Climbing -> "bouldering gym", Movies -> "movie theater", Board games -> "board game cafe".

Times they're BOTH free (Austin time):
${times}
Give each idea the window index that suits it best (a museum in the afternoon, dinner in the evening, a long hike on a long free block), spread ideas across different windows when you can, and fit the activity inside it.
"when" is short and specific, inside that window, e.g. "Sat, 2–4pm".

They're near: ${near}.
${avoid.length ? `They've already seen these, so suggest different things: ${avoid.join('; ')}.\n` : ''}
Return JSON only, an array of 4:
[{"interest": "Climbing" or null,
  "title": "Go bouldering" (under 7 words, no place name),
  "detail": "one short sentence on why it's fun for them",
  "search": "bouldering gym",
  "window": 0,
  "when": "Sat, 2–4pm",
  "message": "a casual text ${first(me)} could send ${first(friend)} suggesting it, with the day and time: lowercase, friendly, no names, no signature"}]`;

  const raw = await generateJSON<z.infer<typeof ideasSchema>>(prompt, ideasSchema, [], 'gemini');
  const byName = new Map(all.map((i) => [norm(i), i]));
  return raw.slice(0, 4).map((i) => {
    const interest = i.interest ? byName.get(norm(i.interest)) : undefined;
    const window = windows.length && i.window >= 0 && i.window < windows.length ? i.window : windows.length ? 0 : -1;
    return {
      title: i.title,
      detail: i.detail,
      search: i.search,
      interest,
      shared: interest ? shared.some((s) => norm(s) === norm(interest)) : false,
      window,
      when: i.when,
      message: i.message,
    };
  });
}
