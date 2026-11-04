import { afterEach, describe, it, expect } from '@ohos/hypium';
import { formatTTL } from '../main/ets/util/formatTTL';
import { installStrings, resetStrings, StringSource } from '../main/ets/util/strings';

// 单位符号现在来自资源（ttl_badge_*），所以这里装一个假 source：既能断言"选了
// 哪个单位"，也能断言数字与单位的拼接。不装 source 时 str() 返回 key 本身，
// 那一路单独测一次——它保证桶的选择与文案无关。
class UnitStrings implements StringSource {
  private zh: boolean;

  constructor(zh: boolean) {
    this.zh = zh;
  }

  get(key: string, _args: Array<string | number>): string {
    if (this.zh) {
      if (key === 'ttl_badge_sec') { return '秒'; }
      if (key === 'ttl_badge_min') { return '分'; }
      if (key === 'ttl_badge_hour') { return '时'; }
      if (key === 'ttl_badge_day') { return '天'; }
      if (key === 'ttl_badge_week') { return '周'; }
      if (key === 'ttl_badge_month') { return '月'; }
      return '年';
    }
    if (key === 'ttl_badge_sec') { return 's'; }
    if (key === 'ttl_badge_min') { return 'm'; }
    if (key === 'ttl_badge_hour') { return 'h'; }
    if (key === 'ttl_badge_day') { return 'd'; }
    if (key === 'ttl_badge_week') { return 'w'; }
    if (key === 'ttl_badge_month') { return 'mo'; }
    return 'y';
  }

  plural(key: string, count: number, _args: Array<string | number>): string {
    return `${key}:${count}`;
  }
}

export default function formatTTLTest() {
  describe('formatTTL', () => {
    afterEach(() => {
      resetStrings();
    });
    it('disabled_empty', 0, () => {
      expect(formatTTL(0)).assertEqual('');
      expect(formatTTL(-5)).assertEqual('');
    });
    it('without_strings_source_reports_the_unit_key', 0, () => {
      // 没有 source（宿主单测的常态）时 str() 返回 key：这样断言的是"选了哪个
      // 单位"，换文案不会把测试带崩。
      expect(formatTTL(30)).assertEqual('30ttl_badge_sec');
      expect(formatTTL(900)).assertEqual('15ttl_badge_min');
      expect(formatTTL(10800)).assertEqual('3ttl_badge_hour');
      expect(formatTTL(172800)).assertEqual('2ttl_badge_day');
      expect(formatTTL(604800)).assertEqual('1ttl_badge_week');
      expect(formatTTL(2592000)).assertEqual('1ttl_badge_month');
      expect(formatTTL(31536000)).assertEqual('1ttl_badge_year');
    });
    it('seconds', 0, () => {
      installStrings(new UnitStrings(true));
      expect(formatTTL(30)).assertEqual('30秒');
      installStrings(new UnitStrings(false));
      expect(formatTTL(30)).assertEqual('30s');
    });
    it('minutes', 0, () => {
      installStrings(new UnitStrings(true));
      expect(formatTTL(900)).assertEqual('15分');
      installStrings(new UnitStrings(false));
      expect(formatTTL(900)).assertEqual('15m');
    });
    it('hours', 0, () => {
      installStrings(new UnitStrings(true));
      expect(formatTTL(10800)).assertEqual('3时');
      installStrings(new UnitStrings(false));
      expect(formatTTL(10800)).assertEqual('3h');
    });
    it('days', 0, () => {
      installStrings(new UnitStrings(true));
      expect(formatTTL(172800)).assertEqual('2天');
      installStrings(new UnitStrings(false));
      expect(formatTTL(172800)).assertEqual('2d');
    });
    it('weeks', 0, () => {
      installStrings(new UnitStrings(true));
      expect(formatTTL(604800)).assertEqual('1周');
      installStrings(new UnitStrings(false));
      expect(formatTTL(604800)).assertEqual('1w');
    });
    it('months_and_years', 0, () => {
      installStrings(new UnitStrings(true));
      expect(formatTTL(2592000)).assertEqual('1月');
      expect(formatTTL(2678400)).assertEqual('1月');
      expect(formatTTL(31536000)).assertEqual('1年');
      installStrings(new UnitStrings(false));
      expect(formatTTL(2592000)).assertEqual('1mo');
      expect(formatTTL(2678400)).assertEqual('1mo');
      expect(formatTTL(31536000)).assertEqual('1y');
    });
  });
}
