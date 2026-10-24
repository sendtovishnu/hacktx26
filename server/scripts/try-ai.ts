// Runs Person B's four functions on the fixtures. From server/: npx tsx --env-file=.env scripts/try-ai.ts [--save-places]
import { writeFileSync } from 'node:fs';
import { decideNudges, extractSignals, filterEmails } from '../src/ai/index.js';
import { fixture } from '../src/ai/fixtures.js';
import { findPlaces } from '../src/places/index.js';
import type { CalendarEvent, EmailSnippet, TwinFriendInput, User } from '../src/types.js';

const check = (ok: boolean, label: string) => console.log(`${ok ? '✅' : '❌'} ${label}`);
const timed = async <T>(label: string, fn: () => Promise<T>) => {
  const t = Date.now();
  const out = await fn();
  console.log(`\n── ${label} (${Date.now() - t} ms)`);
  return out;
};

const users = fixture<User[]>('users.json');
const [maya, jay, priya] = ['u_maya', 'u_jay', 'u_priya'].map((id) => users.find((u) => u.id === id)!);
const events = fixture<CalendarEvent[]>('events_maya.json');
const emails = fixture<EmailSnippet[]>('emails_maya.json');

console.log(`USE_MOCKS=${process.env.USE_MOCKS ?? 'false'}`);

const kept = filterEmails(emails);
console.log(`\n── filterEmails: kept ${kept.length} of ${emails.length}`);
kept.forEach((e) => console.log(`   ${e.subject}`));
check(!kept.some((e) => /% off|newsletter|\$5/i.test(e.subject)), 'drops newsletters and promos');

const signals = await timed('extractSignals (Gemini)', () => extractSignals(events, kept));
console.log(signals);
check(signals.supportLevel !== 'doing_fine', 'support level is could_use_support or above');
check(signals.stressors.some((s) => /midterm/i.test(s.what) && s.when.length > 0), 'midterm is a stressor');

const friends: TwinFriendInput[] = [
  { friend: jay, tier: 'closest', sharedFreeMinutes: 0 },
  { friend: priya, tier: 'friend', sharedFreeMinutes: 120 },
];
const decisions = await timed('decideNudges (Muse Spark)', () => decideNudges(maya, signals, friends));
console.log(decisions);
check(decisions.length === 1 && decisions[0].friendId === 'u_jay', 'one decision for Jay, none for Priya');
check(decisions.every((d) => d.reason.length > 0), 'every decision has a reason');
check(decisions.every((d) => !/[-—]\s*Jay\s*$/.test(d.surpriseNote)), 'surprise note is an unsigned draft');

const fine = await decideNudges(maya, { ...signals, supportLevel: 'doing_fine' }, friends);
check(fine.length === 0, 'no nudges when doing_fine');

const near = signals.likelyLocation ?? process.env.DEMO_LOCATION ?? 'PCL Library, UT Austin';
const places = await timed(`findPlaces coffee near "${near}" (SerpApi)`, () => findPlaces('coffee', near));
console.log(places);
check(places.length > 0, 'returns nearby coffee shops');

if (process.argv.includes('--save-places') && places.length > 0) {
  writeFileSync('mocks/places_coffee.json', `${JSON.stringify(places, null, 2)}\n`);
  console.log('\nSaved mocks/places_coffee.json');
}
