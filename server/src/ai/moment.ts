import { z } from 'zod';
import type { CalendarEvent, GestureType, User } from '../types.js';
import { generateJSON, useMocks } from './llm.js';

/**
 * Twin to twin: the friend's own twin reads the friend's calendar, plus only the
 * person's busy blocks (no titles) and usual spot, and picks when and where the
 * friend can actually show up. Runs on Muse Spark; returns null if it can't.
 */
export async function planMoment(input: {
  friend: User;
  friendEvents: CalendarEvent[];
  person: User;
  personBusy: { start: string; end: string }[];
  personLocation?: string;
  gestureType: GestureType;
  placeName?: string;
  now?: Date;
}): Promise<string | null> {
  if (useMocks()) return null;
  const friendName = input.friend.name.split(' ')[0];
  const personName = input.person.name.split(' ')[0];
  const now = input.now ?? new Date();
  const local = (iso: string) =>
    new Date(iso).toLocaleString('en-US', {
      timeZone: 'America/Chicago', weekday: 'short', hour: 'numeric', minute: '2-digit',
    });

  const prompt = `You are ${friendName}'s digital twin. ${personName}'s twin says ${personName} could use support, and suggests a ${input.gestureType.replace('_', '-')}${input.placeName ? ` (from ${input.placeName})` : ''}.
Find the best moment in the next 3 days, between 9am and 10pm, when ${friendName} can realistically do it: a gap in ${friendName}'s calendar, ideally when ${friendName} is already near ${personName}, and when ${personName} is not busy.
It is now ${local(now.toISOString())} (America/Chicago).

${friendName}'s calendar (yours to read):
${JSON.stringify(input.friendEvents.map((e) => ({ title: e.title, start: local(e.start), end: local(e.end), location: e.location })))}

${personName} is usually at: ${input.personLocation ?? 'unknown'}
${personName}'s busy times (no details are shared with you):
${JSON.stringify(input.personBusy.map((b) => ({ start: local(b.start), end: local(b.end) })))}

Return JSON only: {"moment": "..."}
"moment" is one short sentence to ${friendName}, second person, naming the day, time and place, and the reason it works, e.g. "Monday 12:50, right after EE 302: you'll pass PCL on the way to lab, and ${personName} is studying there until 1."
Never mention ${personName}'s events or why ${personName} is busy. If there is truly no workable gap, return {"moment": ""}.`;

  const { moment } = await generateJSON(prompt, z.object({ moment: z.string() }), { moment: '' }, 'muse');
  return moment.trim() || null;
}
