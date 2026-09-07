import { describe, expect, it } from '@ohos/hypium';
import {
  CHAT_SWIPE_ACTION_HEIGHT, CHAT_SWIPE_BUTTON_VP, CHAT_SWIPE_COMMIT_DELAY_MS, CHAT_SWIPE_EDGE_EFFECT,
  CHAT_SWIPE_RADIUS_VP, CHAT_SWIPE_TRIGGER_VP, CHAT_SWIPE_VERTICAL_GUTTER_VP,
  archiveSwipeVisual, muteSwipeVisual, readSwipeVisual
} from '../main/ets/util/chatListSwipe';

export default function chatListSwipeTest() {
  describe('chatListSwipe', () => {
    it('已读状态决定标记动作图标', 0, (): void => {
      expect(readSwipeVisual(true).symbol).assertEqual('sys.symbol.checkmark_circle');
      expect(readSwipeVisual(false).symbol).assertEqual('sys.symbol.circle');
      expect(readSwipeVisual(true).background).assertEqual(readSwipeVisual(false).background);
    });

    it('静音状态决定静音动作图标', 0, (): void => {
      expect(muteSwipeVisual(false).symbol).assertEqual('sys.symbol.bell_slash');
      expect(muteSwipeVisual(true).symbol).assertEqual('sys.symbol.bell');
      expect(muteSwipeVisual(false).background).assertEqual(muteSwipeVisual(true).background);
    });

    it('归档与取消归档共用同一视觉规格', 0, (): void => {
      expect(archiveSwipeVisual(false).symbol).assertEqual(archiveSwipeVisual(true).symbol);
      expect(archiveSwipeVisual(false).background).assertEqual(archiveSwipeVisual(true).background);
    });

    it('主列表与文件夹列表共用固定动作几何', 0, (): void => {
      expect(CHAT_SWIPE_BUTTON_VP).assertEqual(76);
      expect(CHAT_SWIPE_ACTION_HEIGHT).assertEqual('calc(100% - 6vp)');
      expect(CHAT_SWIPE_VERTICAL_GUTTER_VP).assertEqual(3);
      expect(CHAT_SWIPE_RADIUS_VP).assertEqual(16);
    });

    it('长滑使用整块确认动画并在额外一个按钮宽度后执行', 0, (): void => {
      expect(CHAT_SWIPE_EDGE_EFFECT).assertEqual(SwipeEdgeEffect.Spring);
      expect(CHAT_SWIPE_TRIGGER_VP).assertEqual(CHAT_SWIPE_BUTTON_VP);
      expect(CHAT_SWIPE_COMMIT_DELAY_MS).assertLarger(400);
    });
  });
}
