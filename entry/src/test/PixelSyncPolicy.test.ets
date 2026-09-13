import { describe, it, expect } from '@ohos/hypium';
import { syncDecodeEligible, SYNC_DECODE_MAX_PX } from '../main/ets/util/pixelSyncPolicy';

// #137：发送者头像首帧先画首字母、解码落地才换图。小图改成同步解码（官方对
// "图片刷新闪烁"的处方是 syncLoad），但只对很小的目标开放，大图仍走 taskpool。
export default function pixelSyncPolicyTest(): void {
  describe('pixelSyncPolicy', (): void => {
    it('头像尺寸（38vp×3 ≈ 114px）可同步；缩略图/大图不可以', 0, (): void => {
      expect(syncDecodeEligible(114, 114)).assertTrue();
      expect(syncDecodeEligible(SYNC_DECODE_MAX_PX, SYNC_DECODE_MAX_PX)).assertTrue();
      expect(syncDecodeEligible(SYNC_DECODE_MAX_PX + 1, 10)).assertFalse();
      expect(syncDecodeEligible(320, 320)).assertFalse();
    });
    it('非法尺寸不同步', 0, (): void => {
      expect(syncDecodeEligible(0, 50)).assertFalse();
      expect(syncDecodeEligible(50, -1)).assertFalse();
    });
  });
}
