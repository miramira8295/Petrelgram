import { describe, expect, it } from '@ohos/hypium';
import holdRewindTest from './HoldRewind.test';
import {
  DEFAULT_SPEED_IDX, QUICK_SEEK_MS, holdSpeedAt, holdSpeedCap, holdSpeedMuted, SPEEDS, SPEED_LABELS,
  formatMs, formatSpeed, nextSeekFeedbackMs
} from '../main/ets/util/playerChrome';

export default function playerChromeTest() {
  holdRewindTest();
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
    it('双击跳 15 秒', 0, () => {
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

    // 按住加速（2026-10-10 用户定）：从 2 倍起，越按越快，封顶 8 倍。
    it('按住越久越快：2→3→4→6→8→16→32', 0, () => {
      expect(holdSpeedAt(0, 32)).assertEqual(2);
      expect(holdSpeedAt(1499, 32)).assertEqual(2);
      expect(holdSpeedAt(1500, 32)).assertEqual(3);
      expect(holdSpeedAt(2500, 32)).assertEqual(4);
      expect(holdSpeedAt(3500, 32)).assertEqual(6);
      expect(holdSpeedAt(4500, 32)).assertEqual(8);
      expect(holdSpeedAt(5499, 32)).assertEqual(8);
      expect(holdSpeedAt(5500, 32)).assertEqual(16);
      expect(holdSpeedAt(6500, 32)).assertEqual(32);
      expect(holdSpeedAt(60_000, 32)).assertEqual(32);
      expect(holdSpeedAt(-10, 32)).assertEqual(2);
    });

    // 边下边播的视频网络跟不上高倍速（32× 每秒要读几十 MB），封顶 8×；整份在本地才放开到 32×。
    it('封顶：边下边播 8×、本地 32×', 0, () => {
      expect(holdSpeedAt(60_000, holdSpeedCap(false))).assertEqual(8);
      expect(holdSpeedAt(60_000, holdSpeedCap(true))).assertEqual(32);
    });

    it('16× 及以上静音（声音已听不出内容）', 0, () => {
      expect(holdSpeedMuted(8)).assertFalse();
      expect(holdSpeedMuted(16)).assertTrue();
      expect(holdSpeedMuted(32)).assertTrue();
    });
  });
}
