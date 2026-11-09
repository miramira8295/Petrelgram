import { describe, expect, it } from '@ohos/hypium';
import { streamReadAheadBytes } from '../main/ets/util/streamReadAhead';

const MB: number = 1024 * 1024;

export default function streamReadAheadTest() {
  describe('streamReadAhead', () => {
    // 下载提前量按「秒」算（2026-10-10）：固定 6MB 对 4K（约 12Mbps）只够 4 秒，网络一抖就卡。
    it('Wi-Fi 提前 60 秒、封顶 64MB', 0, (): void => {
      // 4Mbps：60s = 30MB
      expect(streamReadAheadBytes(4_000_000 / 8 * 600, 600_000, false)).assertEqual(30_000_000);
      // 12Mbps：60s = 90MB → 封顶 64MB
      expect(streamReadAheadBytes(1_500_000 * 600, 600_000, false)).assertEqual(64 * MB);
    });

    it('流量提前 20 秒、封顶 24MB', 0, (): void => {
      expect(streamReadAheadBytes(4_000_000 / 8 * 600, 600_000, true)).assertEqual(10_000_000);
      expect(streamReadAheadBytes(1_500_000 * 600, 600_000, true)).assertEqual(24 * MB);
    });

    it('最少 6MB；时长或大小未知按 6MB', 0, (): void => {
      expect(streamReadAheadBytes(1_000_000, 600_000, false)).assertEqual(6 * MB);
      expect(streamReadAheadBytes(500 * MB, 0, false)).assertEqual(6 * MB);
      expect(streamReadAheadBytes(0, 60_000, true)).assertEqual(6 * MB);
    });
  });
}
