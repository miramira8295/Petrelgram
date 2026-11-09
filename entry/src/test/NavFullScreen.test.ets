import { describe, expect, it } from '@ohos/hypium';
import {
  FULL_SCREEN_OVERLAY_API, fullScreenOverlayWinsAt, viewerFullScreenWanted, viewerHidesTitleBar
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

    it('查看器开着必须收起标题栏——框架标题栏画在内容区之上，单栏分栏都一样', 0, (): void => {
      expect(viewerHidesTitleBar(true)).assertTrue();
    });

    it('查看器没开时标题栏必须在，否则聊天页永远没有顶栏', 0, (): void => {
      expect(viewerHidesTitleBar(false)).assertFalse();
    });

    // #201：分栏不再走 bindContentCover，查看器在页面内——既要盖满窗口，也要收标题栏。
    it('分栏下查看器开着：盖满窗口与收标题栏同时成立', 0, (): void => {
      expect(viewerFullScreenWanted(true, true) && viewerHidesTitleBar(true)).assertTrue();
    });
  });
}
