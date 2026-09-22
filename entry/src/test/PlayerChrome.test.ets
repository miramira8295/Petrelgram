import { describe, expect, it } from '@ohos/hypium';
import {
  DEFAULT_SPEED_IDX, HOLD_SEEK_STEP_MS, QUICK_SEEK_MS, SPEEDS, SPEED_LABELS,
  formatMs, formatSpeed, nextSeekFeedbackMs
} from '../main/ets/util/playerChrome';

export default function playerChromeTest() {
  describe('playerChrome', () => {
    it('一小时以内给 m:ss', 0, () => {
      expect(formatMs(0)).assertEqual('0:00');
      expect(formatMs(9_000)).assertEqual('0:09');
      expect(formatMs(75_000)).assertEqual('1:15');
    });

    it('超过一小时给 h:mm:ss（分钟补零）', 0, () => {
      expect(formatMs(3_600_000)).assertEqual('1:00:00');
      expect(formatMs(3_725_000)).assertEqual('1:02:05');
    });

    it('负数当 0，不出现 -0:00 这种', 0, () => {
      expect(formatMs(-5_000)).assertEqual('0:00');
    });

    it('吞吐按量级换单位', 0, () => {
      expect(formatSpeed(512)).assertEqual('512 B/s');
      expect(formatSpeed(2048)).assertEqual('2 KB/s');
      expect(formatSpeed(3 * 1024 * 1024)).assertEqual('3.0 MB/s');
    });

    // 两套引擎共用同一张倍速表，档位数和默认档必须对得上，
    // 否则切引擎时胶囊上的文字会和实际速度错位。
    it('倍速表与标签一一对应，默认档是 1.0x', 0, () => {
      expect(SPEEDS.length).assertEqual(SPEED_LABELS.length);
      expect(SPEEDS[DEFAULT_SPEED_IDX]).assertEqual('1.0');
      expect(SPEED_LABELS[DEFAULT_SPEED_IDX]).assertEqual('1.0x');
    });
    // issue #160 的后续（2026-09-22）：长按连续快进的步长和双击拆开了。
    // 共用 15 秒时按住不放是每 400ms 跳 15 秒 = 37 倍速的连续瞬移，停不住。
    it('长按步长远小于双击步长', 0, () => {
      expect(HOLD_SEEK_STEP_MS < QUICK_SEEK_MS).assertTrue();
      expect(HOLD_SEEK_STEP_MS).assertEqual(2000);
      expect(QUICK_SEEK_MS).assertEqual(15000);
    });

    // 角标不能写死秒数：长按按住两秒实际走了 10 秒，写死就在撒谎。
    it('同一侧连着跳，角标的量累加', 0, () => {
      expect(nextSeekFeedbackMs(false, 0, 0, 2000)).assertEqual(2000);
      expect(nextSeekFeedbackMs(true, 1, 2000, 2000)).assertEqual(4000);
      expect(nextSeekFeedbackMs(true, 1, 4000, 2000)).assertEqual(6000);
    });

    it('角标已淡出就从头算', 0, () => {
      expect(nextSeekFeedbackMs(false, 1, 6000, 2000)).assertEqual(2000);
    });

    // 从"快进 6 秒"接着数到"后退 8 秒"没有意义。
    it('换一侧从头算', 0, () => {
      expect(nextSeekFeedbackMs(true, 1, 6000, -2000)).assertEqual(2000);
      expect(nextSeekFeedbackMs(true, -1, 6000, 2000)).assertEqual(2000);
    });

    it('双击那一下也走同一条：一次 15 秒', 0, () => {
      expect(nextSeekFeedbackMs(false, 0, 0, QUICK_SEEK_MS)).assertEqual(15000);
      expect(nextSeekFeedbackMs(false, 0, 0, -QUICK_SEEK_MS)).assertEqual(15000);
    });
  });
}
