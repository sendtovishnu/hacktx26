/**
 * Small unit-style checks for rules — run with:
 *   npx tsx src/rules/rules.test.ts
 */
import type { CalendarEvent, Signals } from '../types.js';
import {
  allowedToNudge,
  gestureFor,
  sharedFreeMinutes,
} from './index.js';

let failed = 0;

function assert(cond: boolean, msg: string): void {
  if (cond) {
    console.log(`  ok  ${msg}`);
  } else {
    failed += 1;
    console.error(`  FAIL ${msg}`);
  }
}

function chicagoWall(ymd: string, hour: number, minute = 0): string {
  // Fixed CDT offset matches demo mocks (late Oct).
  const hh = String(hour).padStart(2, '0');
  const mm = String(minute).padStart(2, '0');
  return `${ymd}T${hh}:${mm}:00-05:00`;
}

const todayParts = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Chicago',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
}).formatToParts(new Date());
const y = todayParts.find((p) => p.type === 'year')!.value;
const m = todayParts.find((p) => p.type === 'month')!.value;
const d = todayParts.find((p) => p.type === 'day')!.value;
const today = `${y}-${m}-${d}`;
const tomorrowDate = new Date(Date.UTC(Number(y), Number(m) - 1, Number(d) + 1, 12));
const tomorrow = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Chicago',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
}).format(tomorrowDate);

console.log('sharedFreeMinutes');
{
  const bothFree: CalendarEvent[] = [];
  const minutes = sharedFreeMinutes(bothFree, bothFree);
  // Longest continuous block is one full day window (9–22), not the sum of days.
  assert(minutes === 13 * 60, `empty calendars → ${minutes} (expect 780)`);

  const aBusyMorning: CalendarEvent[] = [
    {
      title: 'A busy',
      start: chicagoWall(tomorrow, 9, 0),
      end: chicagoWall(tomorrow, 12, 0),
    },
  ];
  const bBusyAfternoon: CalendarEvent[] = [
    {
      title: 'B busy',
      start: chicagoWall(tomorrow, 14, 0),
      end: chicagoWall(tomorrow, 18, 0),
    },
  ];
  const overlap = sharedFreeMinutes(aBusyMorning, bBusyAfternoon);
  // Shared free tomorrow includes 12–14 (120) among other gaps; longest across 3 days
  // is still a full free day on other days = 780, so longest is 780.
  assert(overlap === 13 * 60, `partial busy → longest ${overlap} (expect 780)`);

  const jayBlocks: CalendarEvent[] = [];
  for (let h = 9; h < 22; h++) {
    jayBlocks.push({
      title: `block ${h}`,
      start: chicagoWall(today, h, 0),
      end: chicagoWall(today, h + 1, 0),
    });
    jayBlocks.push({
      title: `block ${h} t+1`,
      start: chicagoWall(tomorrow, h, 0),
      end: chicagoWall(tomorrow, h + 1, 0),
    });
  }
  const dayAfter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Chicago',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(Date.UTC(Number(y), Number(m) - 1, Number(d) + 2, 12)));
  for (let h = 9; h < 22; h++) {
    jayBlocks.push({
      title: `block ${h} t+2`,
      start: chicagoWall(dayAfter, h, 0),
      end: chicagoWall(dayAfter, h + 1, 0),
    });
  }
  const none = sharedFreeMinutes([], jayBlocks);
  assert(none === 0, `fully busy friend → ${none} (expect 0)`);
}

console.log('gestureFor');
{
  const crunch: Signals = {
    supportLevel: 'could_use_support',
    stressors: [],
    busyHoursNext3Days: 10,
    summaryForClosest: 'x',
    summaryForClose: 'y',
  };
  assert(gestureFor(crunch, 0) === 'drop_off', 'crunch + 0 → drop_off');
  assert(gestureFor(crunch, 29) === 'drop_off', 'crunch + 29 → drop_off');
  assert(gestureFor(crunch, 30) === 'hangout', 'crunch + 30 → hangout');

  const fine: Signals = { ...crunch, supportLevel: 'doing_fine' };
  assert(gestureFor(fine, 0) === 'message', 'fine + 0 → message');
  assert(gestureFor(fine, 45) === 'hangout', 'fine + 45 → hangout');
}

console.log('allowedToNudge');
{
  assert(!allowedToNudge('friend', 'struggling'), 'friend never');
  assert(!allowedToNudge('closest', 'doing_fine'), 'closest + fine → false');
  assert(allowedToNudge('closest', 'could_use_support'), 'closest + crunch → true');
  assert(allowedToNudge('closest', 'struggling'), 'closest + struggling → true');
  assert(!allowedToNudge('close', 'doing_fine'), 'close + fine → false');
  assert(allowedToNudge('close', 'could_use_support'), 'close + could_use → true');
  assert(allowedToNudge('close', 'struggling'), 'close + struggling → true');
}

if (failed > 0) {
  console.error(`\n${failed} assertion(s) failed`);
  process.exit(1);
}
console.log('\nAll rules checks passed.');
