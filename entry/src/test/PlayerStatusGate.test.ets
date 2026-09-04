import { describe, expect, it } from '@ohos/hypium';
import { shouldShowPlayerStatus } from '../main/ets/util/playerStatusGate';

export default function playerStatusGateTest() {
  describe('playerStatusGate', () => {
    // issue #192：实况照片起播快，延迟门没到就已经就绪，一个字都不该出现。
    it('起播前、延迟未到：不显示', 0, () => {
      expect(shouldShowPlayerStatus('正在准备视频', false, false, false)).assertFalse();
    });

    it('起播前、延迟已过：显示（真慢的时候还是要给反馈）', 0, () => {
      expect(shouldShowPlayerStatus('正在准备视频', false, true, false)).assertTrue();
    });

    // 播放途中卡顿/重连不走延迟门：画面停住却什么都不说更糟。
    it('播放中：不等延迟门，立刻显示', 0, () => {
      expect(shouldShowPlayerStatus('缓冲中…', false, false, true)).assertTrue();
    });

    it('状态为空：任何情况都不显示', 0, () => {
      expect(shouldShowPlayerStatus('', false, true, true)).assertFalse();
    });

    it('出错时不显示：错误有自己的 UI，叠着会互相盖', 0, () => {
      expect(shouldShowPlayerStatus('正在重连', true, true, true)).assertFalse();
    });
  });
}
