// TGS 原生渲染的播放节律：渲多大、按什么帧率播、此刻该是第几帧。
//
// 【背景】2026-09-14 在设备上读了 25 个真实 .tgs 的头：24 个是 60fps × 3 秒 =
// **180 帧**、512×512。所以两件事必须在这里定死：
//   · 渲染尺寸按显示尺寸走，不按贴纸原生的 512（每帧内存是尺寸的平方）；
//   · 播放帧率封顶，不跟着源的 60fps 跑——60fps 意味着每 16.7ms 要渲一帧，
//     而一帧的代价是"渲染 + 反预乘 + 建 PixelMap"。30fps 肉眼与 60 差别很小，
//     CPU 直接减半。
export const TGS_RENDER_MIN_PX: number = 96;
export const TGS_RENDER_MAX_PX: number = 256;
export const TGS_MAX_FPS: number = 30;
// 省电/减少动效档位下的帧率。再低会看出一顿一顿，不如干脆停住（那条路由
// powerSuspended 管，不在这里）。
export const TGS_LOW_FPS: number = 15;

// 渲染尺寸（像素）。box 是显示盒子的 vp 宽，density 是屏幕密度。
// 偶数对齐：行距按 width*4 算，奇数宽度在某些缩放路径上会错位一列。
export function tgsRenderSize(boxVp: number, density: number): number {
  const raw: number = Math.round(boxVp * (density > 0 ? density : 1));
  const clamped: number = Math.min(TGS_RENDER_MAX_PX, Math.max(TGS_RENDER_MIN_PX, raw));
  return clamped % 2 === 0 ? clamped : clamped - 1;
}

// 实际播放帧率：不超过源帧率，也不超过封顶。
export function tgsPlaybackFps(sourceFps: number, lowPower: boolean): number {
  const cap: number = lowPower ? TGS_LOW_FPS : TGS_MAX_FPS;
  if (sourceFps <= 0) {
    return cap;
  }
  return Math.min(sourceFps, cap);
}

// 起播到现在过了 elapsedMs，此刻该显示第几帧（按**源**帧率算，播放帧率只决定
// 我们多久去要一帧）。
//
// 时间轴按源帧率走、而不是按播放帧率累加，是为了让 30fps 播放的贴纸和 60fps
// 的走完同样的 3 秒——按播放帧率累加会让动画整体变慢一倍。
export function tgsFrameIndexAt(
  elapsedMs: number, sourceFps: number, totalFrames: number, loop: boolean
): number {
  if (totalFrames <= 0) {
    return 0;
  }
  const fps: number = sourceFps > 0 ? sourceFps : TGS_MAX_FPS;
  const raw: number = Math.floor(Math.max(0, elapsedMs) * fps / 1000);
  if (raw < totalFrames) {
    return raw;
  }
  return loop ? raw % totalFrames : totalFrames - 1;
}

// 下一帧该在多久之后要。返回的是毫秒，至少 1——0 会让定时器变成忙等。
export function tgsNextDelayMs(playbackFps: number): number {
  const fps: number = playbackFps > 0 ? playbackFps : TGS_MAX_FPS;
  return Math.max(1, Math.round(1000 / fps));
}

// 播完了没有（只对不循环的有意义）。
export function tgsFinished(elapsedMs: number, sourceFps: number, totalFrames: number): boolean {
  if (totalFrames <= 0) {
    return true;
  }
  const fps: number = sourceFps > 0 ? sourceFps : TGS_MAX_FPS;
  return elapsedMs * fps / 1000 >= totalFrames;
}
