import { i18n } from '@kit.LocalizationKit';

// Dates, times and numbers are *formatting*, not copy. English is not a word
// swap but a structure swap — "3月5日" → "Mar 5", 24-hour → AM/PM, "1234.5" →
// "1,234.5" — so putting "${m}月${d}日" in string.json would produce English
// that is grammatical and still wrong. Those go through Intl; only the
// surrounding sentence ("最近上线于 %1$s") lives in string.json.
//
// @ohos.intl is deprecated since API 20 in favour of the standard global Intl,
// which is what this module uses.

// Used when the platform API is unavailable — host unit tests, where nothing
// installs an application context. Keeping it zh-CN means the existing date
// assertions stay meaningful instead of silently becoming locale-dependent.
const FALLBACK_LOCALE = 'zh-CN';

// Left to ICU. zh-CN's own default is 12-hour with 上午/下午, which is not what
// the app has ever shown, so on a device the system setting decides instead —
// this value only applies when there is no platform to ask.
const AUTO_HOUR_CYCLE = 'auto';

let localeTag: string = '';
let hourCycle: string = '';
// Building a formatter loads ICU pattern data, and formatTime() runs once per
// chat row on every list rebuild, so each one is built once and reused.
let clockFmt: Intl.DateTimeFormat | null = null;
let weekdayFmt: Intl.DateTimeFormat | null = null;
let monthDayFmt: Intl.DateTimeFormat | null = null;
let fullDateFmt: Intl.DateTimeFormat | null = null;
let monthDayTimeFmt: Intl.DateTimeFormat | null = null;
let fullDateTimeFmt: Intl.DateTimeFormat | null = null;

// Message bubbles render the same clock string over and over: a timestamp is
// immutable, and every row rebuild re-formats it. What the clock shows only
// depends on the minute the timestamp falls in, so results are memoised per
// minute bucket (floor(unixSec / 60)).
//
// The cache lives here rather than in formatTime.ets because the string is a
// function of locale *and* hour cycle, both of which are owned by this module
// and can change at runtime (language switch, test seams). A cache placed
// outside would have no way to observe those and would go stale forever.
const CLOCK_CACHE_CAPACITY = 1024;
let clockCache: Map<number, string> = new Map<number, string>();
// FIFO: a fixed-size ring of the cached keys in insertion order. Scrolling
// walks a timeline in one direction, so plain insertion order evicts what the
// viewport already left; an LRU's extra bookkeeping would buy nothing here.
let clockCacheRing: number[] = [];
let clockCacheNext: number = 0;

function clearClockCache(): void {
  clockCache = new Map<number, string>();
  clockCacheRing = [];
  clockCacheNext = 0;
}

// 日期族（星期/月日/全日期）的天级结果缓存。同一天的所有时间戳共享同一张
// 标签，而每次发布/翻页都会对全部分组重算 dateLabel——cpuprofile 实测
// （20260902T115345）monthDay 一族的 format() 在 15s 滚动里累计 ~80ms。
// 与 clockCache 同一套 FIFO 思路：时间线单向走，插入序淘汰即可。
const DAY_CACHE_CAPACITY = 512;

class DayLabelCache {
  private cache: Map<number, string> = new Map<number, string>();
  private ring: number[] = [];
  private next: number = 0;

  get(key: number): string | undefined {
    return this.cache.get(key);
  }

  put(key: number, text: string): void {
    if (this.cache.size >= DAY_CACHE_CAPACITY) {
      this.cache.delete(this.ring[this.next]);
      this.ring[this.next] = key;
    } else {
      this.ring.push(key);
    }
    this.cache.set(key, text);
    this.next = (this.next + 1) % DAY_CACHE_CAPACITY;
  }

  clear(): void {
    this.cache = new Map<number, string>();
    this.ring = [];
    this.next = 0;
  }
}

const weekdayCache: DayLabelCache = new DayLabelCache();
const monthDayCache: DayLabelCache = new DayLabelCache();
const fullDateCache: DayLabelCache = new DayLabelCache();

// 本地日的整数身份（年/月/日各占一段位）。星期由日期唯一决定，同 key 可用。
function dayKey(d: Date): number {
  return d.getFullYear() * 512 + d.getMonth() * 32 + d.getDate();
}

function putClockCache(bucket: number, text: string): void {
  if (clockCache.size >= CLOCK_CACHE_CAPACITY) {
    clockCache.delete(clockCacheRing[clockCacheNext]);
    clockCacheRing[clockCacheNext] = bucket;
  } else {
    clockCacheRing.push(bucket);
  }
  clockCache.set(bucket, text);
  clockCacheNext = (clockCacheNext + 1) % CLOCK_CACHE_CAPACITY;
}

export function currentLocale(): string {
  if (localeTag === '') {
    let tag: string = '';
    try {
      tag = i18n.System.getAppPreferredLanguage();
    } catch (e) {
      tag = '';
    }
    localeTag = tag !== '' ? tag : FALLBACK_LOCALE;
  }
  return localeTag;
}

// 12- or 24-hour clock is a device setting, not a property of the language:
// the same zh-CN user may want either. Reading it here is also what keeps the
// hardcoded language-code comparison that the platform guidance forbids out of
// this file — nothing here ever asks "is the locale Chinese?".
function resolvedHourCycle(): string {
  if (hourCycle === '') {
    try {
      hourCycle = i18n.System.is24HourClock() ? 'h23' : 'h12';
    } catch (e) {
      hourCycle = AUTO_HOUR_CYCLE;
    }
  }
  return hourCycle;
}

function withHourCycle(opts: Intl.DateTimeFormatOptions): Intl.DateTimeFormatOptions {
  // Written out rather than assigned from the variable: hourCycle is a union of
  // string literals, and a plain string does not satisfy it.
  const hc = resolvedHourCycle();
  if (hc === 'h23') {
    opts.hourCycle = 'h23';
  } else if (hc === 'h12') {
    opts.hourCycle = 'h12';
  }
  return opts;
}

// Must be called after i18n.System.setAppPreferredLanguage(): resources reload
// themselves, but the formatters cached here still carry the old locale and
// would keep rendering dates in the language the user just left.
export function refreshLocale(): void {
  localeTag = '';
  hourCycle = '';
  clockFmt = null;
  weekdayFmt = null;
  monthDayFmt = null;
  fullDateFmt = null;
  monthDayTimeFmt = null;
  fullDateTimeFmt = null;
  clearClockCache();
  weekdayCache.clear();
  monthDayCache.clear();
  fullDateCache.clear();
}

// Test seams: force a locale and a clock without a running platform.
export function setLocaleForTest(tag: string): void {
  refreshLocale();
  localeTag = tag;
}

export function setHourCycleForTest(use24: boolean): void {
  hourCycle = use24 ? 'h23' : 'h12';
  clockFmt = null;
  monthDayTimeFmt = null;
  fullDateTimeFmt = null;
  clearClockCache();
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

// 2-digit rather than numeric hours: it keeps zh-CN at the "09:05" the app has
// always shown, instead of quietly switching every timestamp to "9:05".
export function clockTime(d: Date): string {
  if (clockFmt === null) {
    try {
      const opts: Intl.DateTimeFormatOptions = { hour: '2-digit', minute: '2-digit' };
      clockFmt = new Intl.DateTimeFormat(currentLocale(), withHourCycle(opts));
    } catch (e) {
      return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
    }
  }
  return clockFmt.format(d);
}

// Cached form of clockTime() for a Unix timestamp in seconds. Seconds below the
// minute never reach the rendering, so they are dropped before lookup. Invalid
// or non-positive timestamps have no clock to show and yield an empty string,
// which is also what the callers already returned for them.
export function clockTimeAt(unixSec: number): string {
  if (!Number.isFinite(unixSec) || unixSec <= 0) {
    return '';
  }
  const bucket = Math.floor(unixSec / 60);
  const cached = clockCache.get(bucket);
  if (cached !== undefined) {
    return cached;
  }
  const text = clockTime(new Date(bucket * 60000));
  putClockCache(bucket, text);
  return text;
}

// zh-CN "周二", en-US "Tue".
export function weekdayShort(d: Date): string {
  const key: number = dayKey(d);
  const cached: string | undefined = weekdayCache.get(key);
  if (cached !== undefined) {
    return cached;
  }
  if (weekdayFmt === null) {
    try {
      const opts: Intl.DateTimeFormatOptions = { weekday: 'short' };
      weekdayFmt = new Intl.DateTimeFormat(currentLocale(), opts);
    } catch (e) {
      return '';
    }
  }
  const text: string = weekdayFmt.format(d);
  weekdayCache.put(key, text);
  return text;
}

// month:'short' rather than 'numeric' — zh-CN renders numeric M/d as "7/6",
// losing the 月/日 the app shows today; 'short' gives "7月6日" and "Jul 6".
export function monthDay(d: Date): string {
  const key: number = dayKey(d);
  const cached: string | undefined = monthDayCache.get(key);
  if (cached !== undefined) {
    return cached;
  }
  if (monthDayFmt === null) {
    try {
      const opts: Intl.DateTimeFormatOptions = { month: 'short', day: 'numeric' };
      monthDayFmt = new Intl.DateTimeFormat(currentLocale(), opts);
    } catch (e) {
      return `${d.getMonth() + 1}/${d.getDate()}`;
    }
  }
  const text: string = monthDayFmt.format(d);
  monthDayCache.put(key, text);
  return text;
}

// zh-CN "2024年12月31日", en-US "Dec 31, 2024".
export function fullDate(d: Date): string {
  const key: number = dayKey(d);
  const cached: string | undefined = fullDateCache.get(key);
  if (cached !== undefined) {
    return cached;
  }
  if (fullDateFmt === null) {
    try {
      const opts: Intl.DateTimeFormatOptions = {
        year: 'numeric', month: 'short', day: 'numeric'
      };
      fullDateFmt = new Intl.DateTimeFormat(currentLocale(), opts);
    } catch (e) {
      return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()}`;
    }
  }
  const text: string = fullDateFmt.format(d);
  fullDateCache.put(key, text);
  return text;
}

// Date and time in one formatter rather than two joined by a space: the
// separator and the order are locale business — zh-CN wants "2024年12月31日
// 09:05", en-US wants "Dec 31, 2024, 9:05 AM" with a comma.
export function monthDayTime(d: Date): string {
  if (monthDayTimeFmt === null) {
    try {
      const opts: Intl.DateTimeFormatOptions = {
        month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
      };
      monthDayTimeFmt = new Intl.DateTimeFormat(currentLocale(), withHourCycle(opts));
    } catch (e) {
      return `${monthDay(d)} ${clockTime(d)}`;
    }
  }
  return monthDayTimeFmt.format(d);
}

export function fullDateTime(d: Date): string {
  if (fullDateTimeFmt === null) {
    try {
      const opts: Intl.DateTimeFormatOptions = {
        year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit'
      };
      fullDateTimeFmt = new Intl.DateTimeFormat(currentLocale(), withHourCycle(opts));
    } catch (e) {
      return `${fullDate(d)} ${clockTime(d)}`;
    }
  }
  return fullDateTimeFmt.format(d);
}

// Only the number: the unit symbol stays a resource string. B/KB/MB/GB are not
// reliably present in every ICU build's unit data, and CLDR's own short forms
// ("532 byte") read worse than the symbols the app already uses. What Intl is
// genuinely needed for here is the decimal separator — "1,2 MB" in German.
export function decimal(value: number, fractionDigits: number): string {
  try {
    const opts: Intl.NumberFormatOptions = {
      minimumFractionDigits: fractionDigits, maximumFractionDigits: fractionDigits
    };
    return new Intl.NumberFormat(currentLocale(), opts).format(value);
  } catch (e) {
    return value.toFixed(fractionDigits);
  }
}

// Trailing zeros dropped rather than padded — "1.5 TON", not "1.500 TON".
export function decimalUpTo(value: number, maxFractionDigits: number): string {
  try {
    const opts: Intl.NumberFormatOptions = {
      minimumFractionDigits: 0, maximumFractionDigits: maxFractionDigits
    };
    return new Intl.NumberFormat(currentLocale(), opts).format(value);
  } catch (e) {
    return value.toFixed(maxFractionDigits).replace(/\.?0+$/, '');
  }
}

// Gift values come from TDLib in USD cents regardless of where the user is, so
// the currency is fixed and only its presentation is localised: "$12.34" in
// en-US, "US$12.34" in zh-CN — the disambiguating prefix matters when the
// reader's own currency also uses a dollar sign.
export function usd(cents: number): string {
  const amount = cents / 100;
  try {
    const opts: Intl.NumberFormatOptions = { style: 'currency', currency: 'USD' };
    return new Intl.NumberFormat(currentLocale(), opts).format(amount);
  } catch (e) {
    return `$${amount.toFixed(2)}`;
  }
}
