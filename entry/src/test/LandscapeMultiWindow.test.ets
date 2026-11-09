import { describe, expect, it } from '@ohos/hypium';
import {
  LANDSCAPE_OWNER_LIVE, LANDSCAPE_OWNER_MEDIA, landscapeMultiWindowApplyFailed,
  requestLandscapeMultiWindow, resetLandscapeMultiWindowForTest
} from '../main/ets/util/landscapeMultiWindow';

// 横向悬浮窗开关的仲裁（SPEC-15）：两处横屏播放共用窗口上的一个开关。
export default function landscapeMultiWindowTest() {
  describe('LandscapeMultiWindow', () => {
    it('第一个持有者进来时开，最后一个走时关', 0, () => {
      resetLandscapeMultiWindowForTest();
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_MEDIA, true)).assertEqual(true);
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_MEDIA, false)).assertEqual(false);
    });

    // 这条是仲裁存在的理由：直播还在横屏，查看器转回竖屏不能把它关掉。
    it('一方退出、另一方还在时不关', 0, () => {
      resetLandscapeMultiWindowForTest();
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_LIVE, true)).assertEqual(true);
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_MEDIA, true)).assertNull();
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_MEDIA, false)).assertNull();
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_LIVE, false)).assertEqual(false);
    });

    it('重复请求不重复碰窗口', 0, () => {
      resetLandscapeMultiWindowForTest();
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_LIVE, true)).assertEqual(true);
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_LIVE, true)).assertNull();
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_MEDIA, false)).assertNull();
    });

    it('推给窗口失败后回滚，下次会再试', 0, () => {
      resetLandscapeMultiWindowForTest();
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_LIVE, true)).assertEqual(true);
      landscapeMultiWindowApplyFailed(true);
      expect(requestLandscapeMultiWindow(LANDSCAPE_OWNER_MEDIA, true)).assertEqual(true);
    });

    it('空持有者名被忽略', 0, () => {
      resetLandscapeMultiWindowForTest();
      expect(requestLandscapeMultiWindow('', true)).assertNull();
    });
  });
}
