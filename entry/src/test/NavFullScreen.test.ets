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

    // 顶栏收不收，和上面那条盖不盖满窗口是**互补**的：查看器开着时两条路各走
    // 一条，绝不会同时为真，也绝不会同时为假。
    it('单栏下查看器开着必须收起标题栏——框架标题栏画在内容区之上，盖不住', 0, (): void => {
      expect(viewerHidesTitleBar(false, true)).assertTrue();
    });

    it('分栏走 bindContentCover，模态本来就在标题栏之上，不许再收一次', 0, (): void => {
      expect(viewerHidesTitleBar(true, true)).assertFalse();
    });

    it('查看器没开时标题栏必须在，否则聊天页永远没有顶栏', 0, (): void => {
      expect(viewerHidesTitleBar(false, false)).assertFalse();
      expect(viewerHidesTitleBar(true, false)).assertFalse();
    });

    it('两条路互斥：查看器开着时恰好一条为真', 0, (): void => {
      for (const split of [true, false]) {
        const full: boolean = viewerFullScreenWanted(split, true);
        const hide: boolean = viewerHidesTitleBar(split, true);
        expect(full !== hide).assertTrue();
      }
    });
  });
}
