import { describe, expect, it } from '@ohos/hypium';
import { DOCK_SIDE_PADDING, dockSidePadding } from '../main/ets/util/mainTabsWidth';

export default function mainTabsWidthTest() {
  describe('dockSidePadding', () => {
    it('四格时就是基准留白', 0, (): void => {
      expect(dockSidePadding(360, 4)).assertEqual(DOCK_SIDE_PADDING);
    });
    it('三格时把空出的一格均摊到两侧', 0, (): void => {
      // 360 - 80 = 280 内宽，每格 70；少一格 → 每侧多 35
      expect(dockSidePadding(360, 3)).assertEqual(75);
    });
    it('宽度未知或异常时退回基准', 0, (): void => {
      expect(dockSidePadding(0, 3)).assertEqual(DOCK_SIDE_PADDING);
      expect(dockSidePadding(Number.NaN, 3)).assertEqual(DOCK_SIDE_PADDING);
      expect(dockSidePadding(60, 3)).assertEqual(DOCK_SIDE_PADDING);
      expect(dockSidePadding(360, 0)).assertEqual(DOCK_SIDE_PADDING);
    });
  });
}
