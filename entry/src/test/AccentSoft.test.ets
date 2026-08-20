import { describe, expect, it } from '@ohos/hypium';
import { accentSoftOf } from '../main/ets/util/theme';

export default function accentSoftTest() {
  describe('accentSoft', () => {
    it('自定义强调色按 12% alpha 合成', 0, () => {
      expect(accentSoftOf('#3390EC')).assertEqual('#1F3390EC');
      expect(accentSoftOf('#7BC862')).assertEqual('#1F7BC862');
    });

    it('非 6 位十六进制不当字符串处理，退回资源淡底', 0, () => {
      // 只有 '#RRGGBB' 这一种形态来自强调色设置；其余（Resource、带 alpha 的
      // 字符串、空串）都不该被拼成一个非法颜色值。
      const odd: string[] = ['', '#333', '#1F3390EC', 'red'];
      for (const v of odd) {
        expect(typeof accentSoftOf(v) === 'string').assertFalse();
      }
    });
  });
}
