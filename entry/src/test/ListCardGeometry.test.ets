import { describe, expect, it } from '@ohos/hypium';
import {
  HOME_CARD_INSET_VP, HOME_CARD_MARGIN_VP, cardDividerStartVp, listContentStartVp
} from '../main/ets/util/listCardGeometry';

// 联系人页「整块底色卡片 + 内列表」的几何。2026-09-15。

export default function listCardGeometryTest() {
  describe('listCardGeometry', () => {
    it('内容起始线 = 卡片外边距 + 内缩', 0, (): void => {
      expect(listContentStartVp()).assertEqual(16);
    });

    // 2026-09-18 用户把首页卡片外沿改成 6vp，并**明确选择头像跟着一起左移**：
    // 首页从此是 6+8 = 14vp，不再和联系人页/标题栏的 16vp 起始线重合。这条用例
    // 从「两者相等」改成钉住这个有意的差值，免得以后有人当成 bug 顺手"修"回去。
    it('首页卡片起始线 14vp，比联系人页的 16vp 靠左 2vp（有意）', 0, (): void => {
      expect(HOME_CARD_MARGIN_VP + HOME_CARD_INSET_VP).assertEqual(14);
      expect(listContentStartVp() - (HOME_CARD_MARGIN_VP + HOME_CARD_INSET_VP)).assertEqual(2);
    });

    it('分隔线从文字列起', 0, (): void => {
      expect(cardDividerStartVp(46, 12)).assertEqual(62);
      expect(cardDividerStartVp(56, 12)).assertEqual(72);
    });
  });
}
