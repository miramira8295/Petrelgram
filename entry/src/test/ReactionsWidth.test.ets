import { describe, expect, it } from '@ohos/hypium';
import {
  CHIP_GAP, CHIP_ICON_VP, CHIP_MARGIN_R, CHIP_PAD_H, reactionChipWidth, reactionsRowWidth
} from '../main/ets/util/reactionsWidth';

export default function reactionsWidthTest() {
  describe('reactionsWidth', () => {
    it('单个 chip = 内边距 + 图标 + 间距 + 计数 + 内边距 + 右外边距', 0, (): void => {
      expect(reactionChipWidth(CHIP_ICON_VP, 8))
        .assertEqual(CHIP_PAD_H + CHIP_ICON_VP + CHIP_GAP + 8 + CHIP_PAD_H + CHIP_MARGIN_R);
    });
    it('一个反应不会把短消息顶到最大宽（issue #100）', 0, (): void => {
      // 👍 3：约 15 + 8 的内容，整条不到 50vp，远小于 264 的上限。
      const w = reactionsRowWidth([reactionChipWidth(15, 8)], 264);
      expect(w < 60).assertTrue();
      expect(w > 40).assertTrue();
    });
    it('多个 chip 相加，留 2vp 余量并向上取整', 0, (): void => {
      expect(reactionsRowWidth([40.2, 40.2], 264)).assertEqual(Math.ceil(80.4) + 2);
    });
    it('超过上限就封顶——那时交给 wrap 换行', 0, (): void => {
      expect(reactionsRowWidth([100, 100, 100], 264)).assertEqual(264);
    });
    it('没有 chip 时为 0', 0, (): void => {
      expect(reactionsRowWidth([], 264)).assertEqual(0);
    });
  });
}
