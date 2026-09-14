import { describe, it, expect } from '@ohos/hypium';
import {
  tgsRenderSize, tgsPlaybackFps, tgsFrameIndexAt, tgsNextDelayMs, tgsFinished,
  TGS_RENDER_MAX_PX, TGS_RENDER_MIN_PX, TGS_MAX_FPS, TGS_LOW_FPS
} from '../main/ets/util/tgsPlayback';

export default function tgsPlaybackTest() {
  describe('tgsPlayback', () => {
    it('渲染尺寸按显示尺寸走，上下都封顶且为偶数', 0, (): void => {
      // 会话气泡 ~170vp × 3 = 510px → 封到 256
      expect(tgsRenderSize(170, 3)).assertEqual(TGS_RENDER_MAX_PX);
      // 面板格子 ~64vp × 3 = 192px
      expect(tgsRenderSize(64, 3)).assertEqual(192);
      // 太小的抬到下限
      expect(tgsRenderSize(10, 3)).assertEqual(TGS_RENDER_MIN_PX);
      // 奇数抹平
      expect(tgsRenderSize(41, 3) % 2).assertEqual(0);
    });

    it('播放帧率不超过源、也不超过封顶', 0, (): void => {
      expect(tgsPlaybackFps(60, false)).assertEqual(TGS_MAX_FPS);
      expect(tgsPlaybackFps(24, false)).assertEqual(24);   // 源更低就跟源
      expect(tgsPlaybackFps(60, true)).assertEqual(TGS_LOW_FPS);
      expect(tgsPlaybackFps(0, false)).assertEqual(TGS_MAX_FPS);  // 源帧率读不到
    });

    it('时间轴按源帧率算——30fps 播放的贴纸也要 3 秒走完', 0, (): void => {
      // 60fps、180 帧的贴纸：第 1 秒末应该在第 60 帧附近
      expect(tgsFrameIndexAt(1000, 60, 180, true)).assertEqual(60);
      expect(tgsFrameIndexAt(2999, 60, 180, true)).assertEqual(179);
    });

    it('循环的绕回去，不循环的停在最后一帧', 0, (): void => {
      expect(tgsFrameIndexAt(3000, 60, 180, true)).assertEqual(0);
      expect(tgsFrameIndexAt(3000, 60, 180, false)).assertEqual(179);
      expect(tgsFrameIndexAt(10000, 60, 180, false)).assertEqual(179);
    });

    it('边界：没有帧、负时间', 0, (): void => {
      expect(tgsFrameIndexAt(100, 60, 0, true)).assertEqual(0);
      expect(tgsFrameIndexAt(-5, 60, 180, true)).assertEqual(0);
    });

    it('下一帧的间隔至少 1ms（0 会变成忙等）', 0, (): void => {
      expect(tgsNextDelayMs(30)).assertEqual(33);
      expect(tgsNextDelayMs(0)).assertEqual(33);
      expect(tgsNextDelayMs(10000) >= 1).assertTrue();
    });

    it('播完的判据只看时间和源帧率', 0, (): void => {
      expect(tgsFinished(2999, 60, 180)).assertFalse();
      expect(tgsFinished(3000, 60, 180)).assertTrue();
      expect(tgsFinished(0, 60, 0)).assertTrue();
    });
  });
}
