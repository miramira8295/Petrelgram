import { describe, it, expect } from '@ohos/hypium';
import {
  tgsRenderSize, tgsPlaybackFps, tgsFrameIndexAt, tgsNextDelayMs, tgsFinished,
  tgsHighRateCategory, tgsClockRange, tgsFrameDue, TgsRateRange,
  TGS_RENDER_MAX_PX, TGS_RENDER_MIN_PX, TGS_MAX_FPS, TGS_LOW_FPS, TGS_HIGH_FPS
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
    // 2026-09-17 用户定：单发的大表情开 60fps，其余照旧封顶 30，省电一律 15。
    it('大表情可到 60fps，普通贴纸仍封顶 30，省电一律 15', 0, (): void => {
      expect(tgsPlaybackFps(60, false, true)).assertEqual(TGS_HIGH_FPS);
      expect(tgsPlaybackFps(60, false, false)).assertEqual(TGS_MAX_FPS);
      // 旧的两参调用不受影响
      expect(tgsPlaybackFps(60, false)).assertEqual(TGS_MAX_FPS);
      expect(tgsPlaybackFps(60, true, true)).assertEqual(TGS_LOW_FPS);
      // 源本身只有 30fps 的，开高帧率也不会超过源
      expect(tgsPlaybackFps(30, false, true)).assertEqual(30);
    });

    // 只有会话气泡里单发的大表情走高帧率。状态小图标、面板格子、普通贴纸都不走——
    // 所有 TGS 共用一条原生渲染队列，小图标一屏几十个全跑 60fps 会把它压垮。
    it('只有会话里的大表情走高帧率', 0, (): void => {
      expect(tgsHighRateCategory('emojiChat')).assertTrue();
      expect(tgsHighRateCategory('sticker')).assertFalse();
      expect(tgsHighRateCategory('emojiStatus')).assertFalse();
      expect(tgsHighRateCategory('emoji')).assertFalse();
    });

    // 一个共享时钟驱动全部贴纸：期望帧率取在播里最高的那个；下限给一半，系统扛不住
    // 时可以自己降档（官方 LTPO 实践：优先满足 expected，满足不了在 min~max 间选）；
    // 上限等于期望——贴纸源不会比这更快，没必要让系统往上跑。
    it('共享时钟的期望帧率范围', 0, (): void => {
      const a: TgsRateRange = tgsClockRange([30, 60, 30]);
      expect(a.expected).assertEqual(60);
      expect(a.min).assertEqual(30);
      expect(a.max).assertEqual(60);
      const b: TgsRateRange = tgsClockRange([30]);
      expect(b.expected).assertEqual(30);
      expect(b.min).assertEqual(15);
      expect(b.max).assertEqual(30);
      const c: TgsRateRange = tgsClockRange([]);
      expect(c.expected).assertEqual(0);
      expect(c.min).assertEqual(0);
      expect(c.max).assertEqual(0);
    });

    // 时钟按全体最高帧率跳，30fps 的贴纸要隔一拍才要一帧。时刻来自 displaySync 的
    // targetTimestamp，是浮点毫秒，不能因为差零点几微秒就错过一拍。
    it('这一拍该不该要帧', 0, (): void => {
      expect(tgsFrameDue(-1, 1000, 30)).assertTrue();              // 从没要过
      expect(tgsFrameDue(1000, 1016.667, 30)).assertFalse();       // 60Hz 下隔一拍
      expect(tgsFrameDue(1000, 1033.333, 30)).assertTrue();        // 隔两拍
      expect(tgsFrameDue(1000, 1016.667, 60)).assertTrue();        // 60fps 每拍都要
      expect(tgsFrameDue(1000, 1033.3329, 30)).assertTrue();       // 浮点误差
    });
  });
}
