import { describe, it, expect, afterEach } from '@ohos/hypium';
import {
  clockTime, decimal, decimalUpTo, fullDate, fullDateTime, monthDay, refreshLocale, setHourCycleForTest,
  setLocaleForTest, weekdayShort
} from '../main/ets/util/intlFormat';

// 2026-08-06 is a Thursday. Built from local components so the clock assertions
// do not depend on the runner's time zone.
const D = new Date(2026, 7, 6, 9, 5, 0);

// This suite is the one that fails loudly if the runtime has no Intl or no
// locale data: ICU falls back to the default locale silently rather than
// throwing, so the en-US expectations below are what catches a missing data
// bundle. Everything else in the app would just quietly render Chinese dates.
export default function intlFormatTest() {
  describe('intlFormat', () => {
    afterEach(() => {
      refreshLocale();
    });

    it('formats_zh_cn_dates', 0, () => {
      setLocaleForTest('zh-CN');
      setHourCycleForTest(true);
      expect(clockTime(D)).assertEqual('09:05');
      expect(weekdayShort(D)).assertEqual('周四');
      expect(monthDay(D)).assertEqual('8月6日');
      expect(fullDate(D)).assertEqual('2026年8月6日');
    });

    it('formats_en_us_dates', 0, () => {
      setLocaleForTest('en-US');
      expect(weekdayShort(D)).assertEqual('Thu');
      expect(monthDay(D)).assertEqual('Aug 6');
      expect(fullDate(D)).assertEqual('Aug 6, 2026');
    });

    // 12- vs 24-hour follows the device setting, not the language: the same
    // zh-CN user may want either, and a translated format string could never
    // produce the AM/PM form at all.
    it('clock_follows_the_device_hour_setting', 0, () => {
      setLocaleForTest('zh-CN');
      setHourCycleForTest(true);
      const h24 = clockTime(D);
      setHourCycleForTest(false);
      const h12 = clockTime(D);
      expect(h24).assertEqual('09:05');
      expect(h12 === h24).assertFalse();

      setLocaleForTest('en-US');
      setHourCycleForTest(false);
      const en = clockTime(D);
      expect(en.indexOf('AM') >= 0 || en.indexOf('am') >= 0).assertTrue();
    });

    it('combines_date_and_time_per_locale', 0, () => {
      setLocaleForTest('zh-CN');
      setHourCycleForTest(true);
      const zh = fullDateTime(D);
      expect(zh.indexOf('2026') >= 0).assertTrue();
      expect(zh.indexOf('09:05') >= 0).assertTrue();
    });

    it('groups_and_separates_numbers', 0, () => {
      setLocaleForTest('zh-CN');
      expect(decimal(1234.5, 1)).assertEqual('1,234.5');
      expect(decimal(24.34, 1)).assertEqual('24.3');
    });

    it('cached_number_formatters_clear_on_locale_switch', 0, () => {
      setLocaleForTest('en-US'); expect(decimal(1234.5, 1)).assertEqual('1,234.5');
      setLocaleForTest('de-DE'); expect(decimal(1234.5, 1)).assertEqual('1.234,5');
      setLocaleForTest('en-US'); expect(decimal(1234.5, 1)).assertEqual('1,234.5');
    });

    it('fixed_and_variable_precision_do_not_share_the_wrong_formatter', 0, () => {
      setLocaleForTest('en-US');
      expect(decimal(1.5, 2)).assertEqual('1.50');
      expect(decimalUpTo(1.5, 2)).assertEqual('1.5');
      expect(decimal(1.5, 0)).assertEqual('2');
      expect(decimal(1.5, 2)).assertEqual('1.50');
    });

    it('reusing_a_formatter_never_reuses_the_previous_number', 0, () => {
      setLocaleForTest('en-US');
      expect(decimal(12.3, 1)).assertEqual('12.3');
      expect(decimal(45.6, 1)).assertEqual('45.6');
      expect(decimalUpTo(-12.25, 2)).assertEqual('-12.25');
      expect(decimalUpTo(0, 2)).assertEqual('0');
    });

    // No platform installed a locale, and no test forced one: everything must
    // still render rather than throw, because this is the state every host unit
    // test runs in.
    it('falls_back_without_a_platform_locale', 0, () => {
      refreshLocale();
      expect(clockTime(D).length > 0).assertTrue();
      expect(fullDate(D).length > 0).assertTrue();
    });
  });
}
