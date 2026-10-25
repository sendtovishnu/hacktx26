import type {
  CalendarEvent,
  GestureType,
  Signals,
  SupportLevel,
  Tier,
} from '../types.js';

const TZ = 'America/Chicago';
const WINDOW_START_HOUR = 9;
const WINDOW_END_HOUR = 22;
const HANGOUT_MIN_MINUTES = 30;

/** Placeholder used by privacy routes — closest/close can share context; friend cannot. */
export function canShareContext(tier: Tier): 'closest' | 'close' | null {
  if (tier === 'closest') return 'closest';
  if (tier === 'close') return 'close';
  return null;
}

type Interval = { start: number; end: number };

function chicagoYmd(date: Date): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

function zoneOffsetMs(instant: Date): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: TZ,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(instant);
  const get = (type: string) =>
    Number(parts.find((p) => p.type === type)?.value ?? '0');
  const asIfUtc = Date.UTC(
    get('year'),
    get('month') - 1,
    get('day'),
    get('hour'),
    get('minute'),
    get('second'),
  );
  return asIfUtc - instant.getTime();
}

/** Wall-clock America/Chicago → UTC Date. */
function chicagoWallToUtc(
  ymd: string,
  hour: number,
  minute = 0,
  second = 0,
): Date {
  const [y, m, d] = ymd.split('-').map(Number);
  const guess = new Date(Date.UTC(y, m - 1, d, hour, minute, second));
  const corrected = new Date(
    Date.UTC(y, m - 1, d, hour, minute, second) - zoneOffsetMs(guess),
  );
  return new Date(
    Date.UTC(y, m - 1, d, hour, minute, second) - zoneOffsetMs(corrected),
  );
}

function addChicagoDays(ymd: string, days: number): string {
  const [y, m, d] = ymd.split('-').map(Number);
  const noonUtc = new Date(Date.UTC(y, m - 1, d + days, 12, 0, 0));
  return chicagoYmd(noonUtc);
}

function mergeIntervals(intervals: Interval[]): Interval[] {
  if (intervals.length === 0) return [];
  const sorted = [...intervals].sort((a, b) => a.start - b.start);
  const out: Interval[] = [{ ...sorted[0]! }];
  for (let i = 1; i < sorted.length; i++) {
    const cur = sorted[i]!;
    const last = out[out.length - 1]!;
    if (cur.start <= last.end) {
      last.end = Math.max(last.end, cur.end);
    } else {
      out.push({ ...cur });
    }
  }
  return out;
}

function clipToWindow(
  events: CalendarEvent[],
  windowStart: number,
  windowEnd: number,
): Interval[] {
  const busy: Interval[] = [];
  for (const event of events) {
    const start = new Date(event.start).getTime();
    const end = new Date(event.end).getTime();
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) continue;
    const clippedStart = Math.max(start, windowStart);
    const clippedEnd = Math.min(end, windowEnd);
    if (clippedEnd > clippedStart) {
      busy.push({ start: clippedStart, end: clippedEnd });
    }
  }
  return mergeIntervals(busy);
}

function freeWithinWindow(
  busy: Interval[],
  windowStart: number,
  windowEnd: number,
): Interval[] {
  const free: Interval[] = [];
  let cursor = windowStart;
  for (const block of busy) {
    if (block.start > cursor) {
      free.push({ start: cursor, end: block.start });
    }
    cursor = Math.max(cursor, block.end);
  }
  if (cursor < windowEnd) {
    free.push({ start: cursor, end: windowEnd });
  }
  return free;
}

function intersectFree(a: Interval[], b: Interval[]): Interval[] {
  const out: Interval[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length && j < b.length) {
    const start = Math.max(a[i]!.start, b[j]!.start);
    const end = Math.min(a[i]!.end, b[j]!.end);
    if (end > start) out.push({ start, end });
    if (a[i]!.end < b[j]!.end) i += 1;
    else j += 1;
  }
  return out;
}

/**
 * Longest shared free block between 9am and 10pm America/Chicago
 * over the next 3 calendar days (today + 2). Returns minutes.
 */
export function sharedFreeMinutes(
  a: CalendarEvent[],
  b: CalendarEvent[],
): number {
  const today = chicagoYmd(new Date());
  let longestMs = 0;

  for (let dayOffset = 0; dayOffset < 3; dayOffset++) {
    const ymd = addChicagoDays(today, dayOffset);
    const windowStart = chicagoWallToUtc(ymd, WINDOW_START_HOUR).getTime();
    const windowEnd = chicagoWallToUtc(ymd, WINDOW_END_HOUR).getTime();

    const freeA = freeWithinWindow(
      clipToWindow(a, windowStart, windowEnd),
      windowStart,
      windowEnd,
    );
    const freeB = freeWithinWindow(
      clipToWindow(b, windowStart, windowEnd),
      windowStart,
      windowEnd,
    );
    for (const block of intersectFree(freeA, freeB)) {
      longestMs = Math.max(longestMs, block.end - block.start);
    }
  }

  return Math.floor(longestMs / 60_000);
}

/**
 * Crunch (could_use_support / struggling) with no 30-min block → drop_off;
 * 30+ → hangout; otherwise message or hangout.
 */
export function gestureFor(
  signals: Signals,
  sharedFreeMinutesValue: number,
): GestureType {
  const crunch =
    signals.supportLevel === 'could_use_support' ||
    signals.supportLevel === 'struggling';

  if (crunch) {
    return sharedFreeMinutesValue >= HANGOUT_MIN_MINUTES
      ? 'hangout'
      : 'drop_off';
  }

  return sharedFreeMinutesValue >= HANGOUT_MIN_MINUTES ? 'hangout' : 'message';
}

/**
 * closest: any support level except doing_fine;
 * close: could_use_support and up;
 * friend: never.
 */
export function allowedToNudge(
  tier: Tier,
  supportLevel: SupportLevel,
): boolean {
  if (tier === 'friend') return false;
  if (supportLevel === 'doing_fine') return false;
  if (tier === 'closest') return true;
  // close: could_use_support and struggling
  return (
    supportLevel === 'could_use_support' || supportLevel === 'struggling'
  );
}

/**
 * Every block both people are free for at least `minMinutes`, 9am–10pm America/Chicago,
 * from now through the next `days` days. For planning a hangout: only free time, never events.
 */
export function sharedFreeWindows(
  a: CalendarEvent[],
  b: CalendarEvent[],
  opts: { days?: number; minMinutes?: number; now?: Date } = {},
): { start: string; end: string }[] {
  const days = opts.days ?? 7;
  const minMs = (opts.minMinutes ?? 60) * 60_000;
  const now = (opts.now ?? new Date()).getTime();
  // Nothing that starts in the next half hour: too soon to plan.
  const earliest = Math.ceil((now + 30 * 60_000) / (15 * 60_000)) * 15 * 60_000;
  const today = chicagoYmd(new Date(now));
  const out: { start: string; end: string }[] = [];

  for (let dayOffset = 0; dayOffset < days; dayOffset++) {
    const ymd = addChicagoDays(today, dayOffset);
    const windowStart = Math.max(chicagoWallToUtc(ymd, WINDOW_START_HOUR).getTime(), earliest);
    const windowEnd = chicagoWallToUtc(ymd, WINDOW_END_HOUR).getTime();
    if (windowEnd - windowStart < minMs) continue;
    const freeA = freeWithinWindow(clipToWindow(a, windowStart, windowEnd), windowStart, windowEnd);
    const freeB = freeWithinWindow(clipToWindow(b, windowStart, windowEnd), windowStart, windowEnd);
    for (const block of intersectFree(freeA, freeB)) {
      if (block.end - block.start >= minMs) {
        out.push({ start: new Date(block.start).toISOString(), end: new Date(block.end).toISOString() });
      }
    }
  }
  return out;
}
