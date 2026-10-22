import { describe, expect, it } from '@ohos/hypium';
import { forgetPlayedOnce, markPlayedOnce, playedOnce, resetPlayedOnceForTest } from '../main/ets/util/stickerPlayedOnce';

// 骰子/老虎机只播一次（2026-10-10）：播过的再出现（滑回来、行复用、消息更新）直接定格结果。
export default function stickerPlayedOnceTest() {
  describe('stickerPlayedOnce', () => {
    it('没播过 → 播过', 0, (): void => {
      resetPlayedOnceForTest();
      expect(playedOnce('dice:1:42')).assertFalse();
      markPlayedOnce('dice:1:42');
      expect(playedOnce('dice:1:42')).assertTrue();
      expect(playedOnce('dice:1:43')).assertFalse();
    });

    it('重播只重置当前消息，播放后恢复一次性记录', 0, (): void => {
      resetPlayedOnceForTest();
      markPlayedOnce('chat1:dice1');
      markPlayedOnce('chat1:dice2');
      forgetPlayedOnce('chat1:dice1');
      expect(playedOnce('chat1:dice1')).assertFalse();
      expect(playedOnce('chat1:dice2')).assertTrue();
      markPlayedOnce('chat1:dice1');
      expect(playedOnce('chat1:dice1')).assertTrue();
    });

    it('空键不记：没有身份的一律照常播', 0, (): void => {
      resetPlayedOnceForTest();
      markPlayedOnce('');
      expect(playedOnce('')).assertFalse();
    });

    it('有上限：太多了丢最早的，不无限长', 0, (): void => {
      resetPlayedOnceForTest();
      for (let i = 0; i < 600; i++) {
        markPlayedOnce(`k${i}`);
      }
      expect(playedOnce('k0')).assertFalse();
      expect(playedOnce('k599')).assertTrue();
    });
  });
}
