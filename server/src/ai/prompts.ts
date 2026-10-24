import type { CalendarEvent, EmailSnippet, Signals, TwinFriendInput, User } from '../types.js';

export function extractionPrompt(events: CalendarEvent[], emails: EmailSnippet[], checkin?: string, now = new Date()) {
  return `You analyze one student's upcoming week to see whether they could use support from friends.
Today is ${now.toISOString()}.

Return JSON only:
{
  "support_level": "doing_fine" | "could_use_support" | "struggling",
  "stressors": [{"what": "Midterm in M 408D", "when": "2026-10-27"}],
  "busy_hours_next_3_days": number,
  "likely_location": "PCL library",
  "summary_for_closest": "Midterm Tuesday and a packed study week",
  "summary_for_close": "Busy, stressful week"
}

Rules: describe situations, never diagnose mental health. Do not quote emails.
Ignore details about other people that are not about this student.
"when" is a YYYY-MM-DD date. likely_location is where they spend the most time this week, or null.
summary_for_closest is under 12 words; summary_for_close is under 6 words and names no specifics.

Calendar, next 7 days:
${JSON.stringify(events)}

Recent emails (sender, subject, snippet):
${JSON.stringify(emails.map(({ from, subject, snippet }) => ({ from, subject, snippet })))}
${checkin ? `\nThe student's own check-in: "${checkin}"` : ''}`;
}

export function twinPrompt(user: User, signals: Signals, friends: TwinFriendInput[]) {
  const name = user.name.split(' ')[0];
  const prefs = [
    user.preferences.coffeeOrder && `coffee order: ${user.preferences.coffeeOrder}`,
    user.preferences.likes === 'company' ? 'prefers company over space' : 'prefers space over company',
  ].filter(Boolean).join(', ');

  const friendLines = friends.map((f) => ({
    friend_id: f.friend.id,
    name: f.friend.name.split(' ')[0],
    tier: f.tier,
    shared_free_minutes: f.sharedFreeMinutes,
    may_hear: f.tier === 'closest' ? signals.summaryForClosest : signals.summaryForClose,
    ...(f.showedUpForThem ? { you_showed_up_for_them: f.showedUpForThem } : {}),
  }));

  return `You are ${name}'s digital twin. Decide whether any friends should be nudged to support ${name}.

Only nudge friends ranked close or closest. Closest may hear summary_for_closest; close may hear summary_for_close only. Never nudge for doing_fine.
Each friend's "may_hear" is the only information about ${name}'s week you may put in their message. Never mention calendars, emails or exact events beyond it.

For each friend you nudge, return a JSON array of:
{"friend_id": "...", "message": "...", "gesture_type": "drop_off" | "hangout" | "message", "surprise_note": "...", "reason": "..."}
Return [] if no one should be nudged.

"message" is what the friend reads: 1-2 warm sentences suggesting how to help.
"surprise_note" is a starter draft the friend will edit and send to ${name} in their own words. Write it as that friend texting a close friend: 1-2 short, casual sentences, no signature, no greeting card language. It arrives together with the gesture (for a drop-off, alongside the coffee), so it never asks permission or asks a question. Example: "figured you'd be living at PCL rn, oat latte for the grind. you've got tuesday"
"reason" is for ${name}'s privacy log, read later by ${name}: one plain sentence addressed to them as "you" saying why you chose this friend and this gesture, and what they were told. Example: "Told Jay (your closest friend) that you have a midterm Tuesday and a packed week; suggested a coffee drop-off since you two have no free time together."
If a friend has "you_showed_up_for_them", ${name} recently did that for them. Mention it once, lightly, in their message so it feels like their turn to return the favor (e.g. "${name} brought you a latte before your midterm; now it's their rough week"). Never make it sound like a debt. Prefer these friends when deciding whom to nudge.
If shared_free_minutes is 30 or more, prefer "hangout"; otherwise prefer "drop_off".
Use ${name}'s preferences (${prefs}) to make it personal, naturally: name the drink, but never recite the preferences themselves.
Describe situations, never diagnose mental health.

${name}'s week:
support_level: ${signals.supportLevel}
summary_for_closest: ${signals.summaryForClosest}
summary_for_close: ${signals.summaryForClose}
likely_location: ${signals.likelyLocation ?? 'unknown'}

Friends:
${JSON.stringify(friendLines)}`;
}
