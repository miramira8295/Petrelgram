import { describe, expect, it } from '@ohos/hypium';
import {
  BOTTOM_DRAWER_HEIGHT, DRAWER_INSET, EMOJI_CONTENT_HEIGHT, EMOJI_DRAWER_HEIGHT,
  EMOJI_TAB_BAR_HEIGHT, drawerBottomInset
} from '../main/ets/util/drawerMetrics';

export default function drawerMetricsTest() {
  describe('drawerMetrics', () => {
    it('抽屉下沿让出整条导航手势带，标签栏不落进系统手势区', 0, (): void => {
      // issue #154：原来只让一半、封顶 12，「表情 / 贴纸 / GIF」那条整个躺在
      // 手势带里，点标签误触小白条。
      expect(drawerBottomInset(28)).assertEqual(28);
      expect(drawerBottomInset(43.6)).assertEqual(44);
    });

    it('没有手势带（bottomSafe = 0）时仍留最小浮起间距', 0, (): void => {
      expect(drawerBottomInset(0)).assertEqual(DRAWER_INSET);
      expect(drawerBottomInset(3)).assertEqual(DRAWER_INSET);
    });

    it('媒体抽屉有独立高度，内容区与主分类条严格相加', 0, (): void => {
      expect(EMOJI_DRAWER_HEIGHT > BOTTOM_DRAWER_HEIGHT).assertTrue();
      expect(EMOJI_CONTENT_HEIGHT + EMOJI_TAB_BAR_HEIGHT).assertEqual(EMOJI_DRAWER_HEIGHT);
    });
  });
}
