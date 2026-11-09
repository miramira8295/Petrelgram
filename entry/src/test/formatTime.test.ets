import { describe, it, expect, afterEach } from '@ohos/hypium';
import { formatClockTime, formatTime } from '../main/ets/util/formatTime';
import {
  clockTime, fullDate, monthDay, refreshLocale, setHourCycleForTest, setLocaleForTest, weekdayShort
} from '../main/ets/util/intlFormat';

// Built from local components so the clock assertions do not depend on the
// runner's time zone. 2026-08-06 09:05:00 local.
const MINUTE_BASE = Math.floor(new Date(2026, 7, 6, 9, 5, 0).getTime() / 1000);

const NOW = 1783512000;

// formatTime's own logic is branch selection — which of the four renderings a
// timestamp gets. The renderings themselves are Intl's job, so the assertions
// name the expected primitive rather than a hardcoded Chinese string; pinning
// "周二" here would only re-test ICU and would break the moment the app runs in
// another language.
export default function formatTimeTest() {
  describe('formatTime', () => {
    it('empty_for_zero', 0, () => {
      expect(formatTime(0, NOW)).assertEqual('');
    });
    it('same_day_hh_mm', 0, () => {
      expect(formatTime(NOW, NOW)).assertEqual(clockTime(new Date(NOW * 1000)));
    });
    it('message_clock_is_hh_mm_even_for_old_messages', 0, () => {
      const old = NOW - 400 * 86400;
      expect(formatClockTime(old)).assertEqual(clockTime(new Date(old * 1000)));
      expect(formatClockTime(0)).assertEqual('');
    });
    it('within_week_weekday', 0, () => {
      const t = NOW - 3 * 86400;
      expect(formatTime(t, NOW)).assertEqual(weekdayShort(new Date(t * 1000)));
    });
    it('same_year_month_day', 0, () => {
      const t = NOW - 100 * 86400;
      const d = new Date(t * 1000);
      const n = new Date(NOW * 1000);
      if (d.getFullYear() === n.getFullYear()) {
        expect(formatTime(t, NOW)).assertEqual(monthDay(d));
      } else {
        expect(formatTime(t, NOW)).assertEqual(fullDate(d));
      }
    });
    it('older_numeric', 0, () => {
      const t = NOW - 400 * 86400;
      expect(formatTime(t, NOW)).assertEqual(fullDate(new Date(t * 1000)));
    });
    // The four branches must actually differ; without this the test above would
    // still pass if every branch returned the same thing.
    it('four_branches_are_distinct', 0, () => {
      const sameDay = formatTime(NOW, NOW);
      const week = formatTime(NOW - 3 * 86400, NOW);
      const year = formatTime(NOW - 100 * 86400, NOW);
      const older = formatTime(NOW - 400 * 86400, NOW);
      expect(sameDay === week).assertFalse();
      expect(week === year).assertFalse();
      expect(year === older).assertFalse();
    });
  });
}

// The bubble clock is memoised per minute bucket, because a message timestamp
// never changes but its row is rebuilt constantly. These guard the two ways a
// cache goes wrong: showing a stale string, and dropping the right one.
export function formatClockCacheTest() {
  describe('formatClockTime_cache', () => {
    afterEach(() => {
      refreshLocale();
    });

    it('same_minute_any_second_renders_alike', 0, () => {
      setLocaleForTest('zh-CN');
      setHourCycleForTest(true);
      const first = formatClockTime(MINUTE_BASE);
      expect(first).assertEqual('09:05');
      expect(formatClockTime(MINUTE_BASE + 1)).assertEqual(first);
      expect(formatClockTime(MINUTE_BASE + 59)).assertEqual(first);
    });

    it('next_minute_renders_differently', 0, () => {
      setLocaleForTest('zh-CN');
      setHourCycleForTest(true);
      expect(formatClockTime(MINUTE_BASE)).assertEqual('09:05');
      expect(formatClockTime(MINUTE_BASE + 60)).assertEqual('09:06');
      expect(formatClockTime(MINUTE_BASE + 3600)).assertEqual('10:05');
    });

    // A cached string belongs to the locale and hour cycle that produced it.
    it('locale_and_hour_cycle_switches_invalidate', 0, () => {
      setLocaleForTest('zh-CN');
      setHourCycleForTest(true);
      const h24 = formatClockTime(MINUTE_BASE);
      expect(h24).assertEqual('09:05');

      setHourCycleForTest(false);
      const h12 = formatClockTime(MINUTE_BASE);
      expect(h12 === h24).assertFalse();

      setLocaleForTest('en-US');
      setHourCycleForTest(false);
      const en = formatClockTime(MINUTE_BASE);
      expect(en.indexOf('AM') >= 0 || en.indexOf('am') >= 0).assertTrue();

      setLocaleForTest('zh-CN');
      setHourCycleForTest(true);
      expect(formatClockTime(MINUTE_BASE)).assertEqual(h24);
    });

    // Far more distinct minutes than the cache holds: evicted buckets must be
    // recomputed, not lost, and the newest ones must still be right.
    it('stays_correct_past_the_capacity', 0, () => {
      setLocaleForTest('zh-CN');
      setHourCycleForTest(true);
      const oldest = MINUTE_BASE;
      const oldestText = formatClockTime(oldest);
      // One Date reused across the sweep: building 4096 of them is exactly what
      // the linter's reuse-date rule is about, and the loop only needs a cursor.
      const probe = new Date(0);
      for (let i = 1; i <= 4096; i++) {
        const t = MINUTE_BASE + i * 60;
        probe.setTime(t * 1000);
        expect(formatClockTime(t)).assertEqual(clockTime(probe));
      }
      expect(formatClockTime(oldest)).assertEqual(oldestText);
      expect(formatClockTime(oldest)).assertEqual(clockTime(new Date(oldest * 1000)));
    });

    it('empty_for_invalid_timestamps', 0, () => {
      expect(formatClockTime(0)).assertEqual('');
      expect(formatClockTime(-1)).assertEqual('');
      expect(formatClockTime(Number.NaN)).assertEqual('');
    });
  });
}
