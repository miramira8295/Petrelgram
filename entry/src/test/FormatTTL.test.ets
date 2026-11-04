import { afterEach, describe, it, expect } from '@ohos/hypium';
import { formatTTL } from '../main/ets/util/formatTTL';
import { refreshLocale, setLocaleForTest } from '../main/ets/util/intlFormat';

export default function formatTTLTest() {
  describe('formatTTL', () => {
    afterEach(() => {
      refreshLocale();
    });
    it('disabled_empty', 0, () => {
      expect(formatTTL(0)).assertEqual('');
      expect(formatTTL(-5)).assertEqual('');
    });
    it('seconds', 0, () => {
      setLocaleForTest('zh-CN');
      expect(formatTTL(30)).assertEqual('30秒');
      setLocaleForTest('en-US');
      expect(formatTTL(30)).assertEqual('30s');
    });
    it('minutes', 0, () => {
      setLocaleForTest('zh-CN');
      expect(formatTTL(900)).assertEqual('15分');
      setLocaleForTest('en-US');
      expect(formatTTL(900)).assertEqual('15m');
    });
    it('hours', 0, () => {
      setLocaleForTest('zh-CN');
      expect(formatTTL(10800)).assertEqual('3时');
      setLocaleForTest('zh-Hant');
      expect(formatTTL(10800)).assertEqual('3時');
      setLocaleForTest('en-US');
      expect(formatTTL(10800)).assertEqual('3h');
    });
    it('days', 0, () => {
      setLocaleForTest('zh-CN');
      expect(formatTTL(172800)).assertEqual('2天');
      setLocaleForTest('en-US');
      expect(formatTTL(172800)).assertEqual('2d');
    });
    it('weeks', 0, () => {
      setLocaleForTest('zh-CN');
      expect(formatTTL(604800)).assertEqual('1周');
      setLocaleForTest('zh-Hant');
      expect(formatTTL(604800)).assertEqual('1週');
      setLocaleForTest('en-US');
      expect(formatTTL(604800)).assertEqual('1w');
    });
    it('months_and_years', 0, () => {
      setLocaleForTest('zh-CN');
      expect(formatTTL(2592000)).assertEqual('1月');
      expect(formatTTL(2678400)).assertEqual('1月');
      expect(formatTTL(31536000)).assertEqual('1年');
      setLocaleForTest('en-US');
      expect(formatTTL(2592000)).assertEqual('1mo');
      expect(formatTTL(2678400)).assertEqual('1mo');
      expect(formatTTL(31536000)).assertEqual('1y');
    });
  });
}
