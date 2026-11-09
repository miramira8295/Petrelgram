import { describe, it, expect } from '@ohos/hypium';
import {
  BIRTHDAY_FALLBACK_YEAR, birthdayPickerDate
} from '../main/ets/util/birthdayPicker';

// 生日选择器的初始日期。这一组存在的理由是一次实测缺陷：`selected` 原来写死
// 2000-01-01，存过生日之后再点开转盘还是停在那儿，用户以为没存上。

export default function birthdayPickerTest() {
  describe('birthdayPicker', () => {

    it('存过生日就停在那一天', 0, (): void => {
      const d: Date = birthdayPickerDate(5, 3, 1990) as Date;
      expect(d.getFullYear()).assertEqual(1990);
      expect(d.getMonth()).assertEqual(2); // 月份 0 起
      expect(d.getDate()).assertEqual(5);
    });

    it('缺年份时用占位年，不能落到 1900', 0, (): void => {
      // TDLib 的 birthdate 里 year 是可选的。直接 new Date(0, ...) 会被解释成
      // 1900 年，转盘一开就滚到最底下。
      const d: Date = birthdayPickerDate(5, 3, 0) as Date;
      expect(d.getFullYear()).assertEqual(BIRTHDAY_FALLBACK_YEAR);
      expect(d.getMonth()).assertEqual(2);
      expect(d.getDate()).assertEqual(5);
    });

    it('没存过生日返回 null，调用方退回自己的默认值', 0, (): void => {
      expect(birthdayPickerDate(0, 0, 0) === null).assertTrue();
      expect(birthdayPickerDate(0, 3, 1990) === null).assertTrue();
      expect(birthdayPickerDate(5, 0, 1990) === null).assertTrue();
    });

    it('越界的月日不当有效值', 0, (): void => {
      expect(birthdayPickerDate(5, 13, 1990) === null).assertTrue();
      expect(birthdayPickerDate(32, 3, 1990) === null).assertTrue();
      expect(birthdayPickerDate(-1, 3, 1990) === null).assertTrue();
    });

    it('月份是 1 起的（TDLib 口径），别差一个月', 0, (): void => {
      // 12 月传 12，不是 11
      expect((birthdayPickerDate(31, 12, 1990) as Date).getMonth()).assertEqual(11);
      expect((birthdayPickerDate(1, 1, 1990) as Date).getMonth()).assertEqual(0);
    });
  });
}
