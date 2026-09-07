import { describe, expect, it } from '@ohos/hypium';
import {
  CHIP_GAP, CHIP_ICON_VP, CHIP_MARGIN_R, CHIP_PAD_H, REACTIONS_TIME_GAP, reactionChipWidth,
  reactionsRowMaxWidth, reactionsRowWidth, timeOverlayWidth
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
    // ── 时间戳同行占位（真机 2026-09-04：五个 chip 的频道消息把「下午07:57」
    // 挤出了气泡右边缘）────────────────────────────────────────────────

    it('时间戳宽度 = 时刻；已编辑与状态图标各自加一段', 0, (): void => {
      expect(timeOverlayWidth(30, 0, false, false)).assertEqual(30);
      // 自己发的多一枚 12 的状态图标 + 4 的间距。
      expect(timeOverlayWidth(30, 0, false, true)).assertEqual(46);
      // 「已编辑」标签 + 4 的间距。
      expect(timeOverlayWidth(30, 24, true, false)).assertEqual(58);
      expect(timeOverlayWidth(30, 24, true, true)).assertEqual(74);
    });

    it('反应条上限先扣掉时间戳和那 6 的间距', 0, (): void => {
      expect(reactionsRowMaxWidth(264, 30)).assertEqual(264 - 30 - REACTIONS_TIME_GAP);
    });

    // 这条是整组的目的：扣完之后，一行排开的自然宽必须留得下时间戳。
    it('顶满的反应条不再吃掉时间戳的位置', 0, (): void => {
      const inlineMax: number = 264;
      const timeVp: number = 34;
      const chips: number[] = [60, 60, 60, 60, 60];   // 自然宽 300 > 264
      const w: number = reactionsRowWidth(chips, reactionsRowMaxWidth(inlineMax, timeVp));
      expect(w + timeVp + REACTIONS_TIME_GAP <= inlineMax).assertTrue();
    });

    // 放得下的时候一切照旧——绝大多数消息只有一两个 chip，不该因为这次改动变窄。
    it('放得下时宽度不受影响', 0, (): void => {
      const natural: number = reactionsRowWidth([60], 264);
      expect(reactionsRowWidth([60], reactionsRowMaxWidth(264, 34))).assertEqual(natural);
    });

    it('气泡比一个 chip 还窄时不会扣成负数', 0, (): void => {
      expect(reactionsRowMaxWidth(40, 34) > 0).assertTrue();
      expect(reactionsRowMaxWidth(40, 34) <= 40).assertTrue();
      expect(reactionsRowMaxWidth(0, 34) >= 0).assertTrue();
    });
    it('没有 chip 时为 0', 0, (): void => {
      expect(reactionsRowWidth([], 264)).assertEqual(0);
    });
  });
}
