import { describe, expect, it } from '@ohos/hypium';
import {
  FULL_SCREEN_OVERLAY_API, fullScreenOverlayWinsAt, viewerFullScreenWanted
} from '../main/ets/util/navFullScreen';

export default function navFullScreenTest() {
  describe('navFullScreen', () => {
    it('fullScreenOverlay 是 API 26 起，低版本必须挡住——取方法那一步就会抛', 0, (): void => {
      expect(fullScreenOverlayWinsAt(FULL_SCREEN_OVERLAY_API)).assertTrue();
      expect(fullScreenOverlayWinsAt(FULL_SCREEN_OVERLAY_API + 1)).assertTrue();
      expect(fullScreenOverlayWinsAt(FULL_SCREEN_OVERLAY_API - 1)).assertFalse();
      // 本应用底线
      expect(fullScreenOverlayWinsAt(20)).assertFalse();
    });

    it('只有「分栏 + 查看器开着」才要盖满窗口（issue #139）', 0, (): void => {
      expect(viewerFullScreenWanted(true, true)).assertTrue();
    });

    it('单栏下 ChatPage 本来就占满窗口，不挂这一手', 0, (): void => {
      expect(viewerFullScreenWanted(false, true)).assertFalse();
    });

    it('查看器没开时必须是 false，否则左栏再也回不来', 0, (): void => {
      expect(viewerFullScreenWanted(true, false)).assertFalse();
      expect(viewerFullScreenWanted(false, false)).assertFalse();
    });
  });
}
