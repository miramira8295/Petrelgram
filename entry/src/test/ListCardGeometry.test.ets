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

    it('首页卡片 8+8 与联系人 12+4 落在同一条起始线上', 0, (): void => {
      expect(HOME_CARD_MARGIN_VP + HOME_CARD_INSET_VP).assertEqual(listContentStartVp());
    });

    it('分隔线从文字列起', 0, (): void => {
      expect(cardDividerStartVp(46, 12)).assertEqual(62);
      expect(cardDividerStartVp(56, 12)).assertEqual(72);
    });
  });
}
