import { describe, expect, it } from '@ohos/hypium';
import { accentSoftOf, onPrimaryOf } from '../main/ets/util/theme';

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
    // 2026-09-10 用户截图：删除确认框的确认按钮成了一块纯白空按钮——强调色是
    // 用户自由取的（ColorPickerSheet 任意 hex），而全仓 38 处把压在强调色上的
    // 前景写死成 Color.White。判据是"救不可读"而不是"取最大对比"：按纯 WCAG
    // 取黑白里对比高的那个，连默认蓝 #3390EC 都会翻黑，等于顺手改了默认外观。
    it('强调色之上的前景：只在白字读不出来时才换黑', 0, () => {
      // 两个默认强调色必须留在白字这一侧，否则用户手选同色时观感和默认不一致。
      expect(onPrimaryOf('#3390EC')).assertEqual(Color.White);
      expect(onPrimaryOf('#57A8F2')).assertEqual(Color.White);
      // 深色、以及 Material 那类高饱和粉红，白字都读得出来。
      expect(onPrimaryOf('#000000')).assertEqual(Color.White);
      expect(onPrimaryOf('#E91E63')).assertEqual(Color.White);
      // 真正会出事的那些：纯白（截图里那块空按钮）、浅灰、亮黄、亮绿。
      expect(onPrimaryOf('#FFFFFF')).assertEqual(Color.Black);
      expect(onPrimaryOf('#F5F5F5')).assertEqual(Color.Black);
      expect(onPrimaryOf('#FFD400')).assertEqual(Color.Black);
      expect(onPrimaryOf('#00E676')).assertEqual(Color.Black);
      // 没自定义时 COLOR_PRIMARY 是 Resource，算不了亮度，一律白色。
      expect(onPrimaryOf($r('app.color.primary'))).assertEqual(Color.White);
      // 脏输入不能把界面判成黑字。
      expect(onPrimaryOf('#GGGGGG')).assertEqual(Color.White);
      expect(onPrimaryOf('#ABC')).assertEqual(Color.White);
    });

  });
}
