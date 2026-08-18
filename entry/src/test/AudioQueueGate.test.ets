import { describe, expect, it } from '@ohos/hypium';
import { audioQueueApplies } from '../main/ets/util/audioQueueGate';

// 这个闸门的作用不是省几次计算，而是切断"每一行的 build 都依赖整个 messages
// 数组"这条链路。放开任何一个非音频类型，滑动时的整行重建量就会重新被
// store notify 的频率乘上可见行数。
export default function audioQueueGateTest() {
  describe('audioQueueGate', () => {
    it('applies to audio messages', 0, () => {
      expect(audioQueueApplies('audio')).assertTrue();
    });

    it('does not apply to any media type that renders in the list', 0, () => {
      const others: string[] = [
        'photo', 'video', 'voice', 'file', 'sticker', 'animation',
        'text', 'location', 'venue', 'contact', 'poll', 'dice',
        'system', 'hidden', 'videoNote', 'story', 'game', 'invoice'
      ];
      for (const t of others) {
        expect(audioQueueApplies(t)).assertFalse();
      }
    });

    it('does not apply to an unknown or empty type', 0, () => {
      expect(audioQueueApplies('')).assertFalse();
      expect(audioQueueApplies('Audio')).assertFalse();
    });
  });
}
