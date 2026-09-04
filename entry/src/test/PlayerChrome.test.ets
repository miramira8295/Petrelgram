import { describe, expect, it } from '@ohos/hypium';
import {
  DEFAULT_SPEED_IDX, SPEEDS, SPEED_LABELS, formatMs, formatSpeed
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
  });
}
