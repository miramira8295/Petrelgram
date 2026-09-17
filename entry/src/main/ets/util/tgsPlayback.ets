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
// 会话里单发的大表情（2026-09-17 用户定）：跟随源帧率，最高 60。官方 LTPO 实践把
// 「聊天表情包动效」归在"跟随源帧率"一类；普通贴纸仍封顶 30——所有 TGS 共用一条
// 原生渲染队列，一屏贴纸都跑 60 会把它压垮。
export const TGS_HIGH_FPS: number = 60;

// 渲染尺寸（像素）。box 是显示盒子的 vp 宽，density 是屏幕密度。
// 偶数对齐：行距按 width*4 算，奇数宽度在某些缩放路径上会错位一列。
export function tgsRenderSize(boxVp: number, density: number): number {
  const raw: number = Math.round(boxVp * (density > 0 ? density : 1));
  const clamped: number = Math.min(TGS_RENDER_MAX_PX, Math.max(TGS_RENDER_MIN_PX, raw));
  return clamped % 2 === 0 ? clamped : clamped - 1;
}

// 实际播放帧率：不超过源帧率，也不超过封顶。
export function tgsPlaybackFps(sourceFps: number, lowPower: boolean, highRate: boolean = false): number {
  const cap: number = lowPower ? TGS_LOW_FPS : (highRate ? TGS_HIGH_FPS : TGS_MAX_FPS);
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

// 哪些贴纸走高帧率。只有会话气泡里单发的大表情（MessageBubble 对 isEmojiSticker
// 传 'emojiChat'）；状态小图标是 'emojiStatus'、面板格子是 'sticker'/'emojiPicker'。
export function tgsHighRateCategory(powerCategory: string): boolean {
  return powerCategory === 'emojiChat';
}

// 期望帧率范围。不直接用 ArkUI 的 ExpectedFrameRateRange：这个文件要在宿主上跑单测。
export interface TgsRateRange {
  expected: number;
  min: number;
  max: number;
}

// 共享时钟的期望帧率范围（util/stickerFrameClock 只建一个 displaySync）。
//   expected = 在播里最高的帧率；
//   min      = 一半，系统扛不住时可以自己降档（官方 LTPO 实践：优先满足 expected，
//              满足不了就在 min~max 之间选）；
//   max      = expected，贴纸源不会比这更快，没必要让系统往上跑。
// 官方同时明确不建议三个值都锁在最高——那会废掉系统的可变帧率。
export function tgsClockRange(fpsList: number[]): TgsRateRange {
  let expected: number = 0;
  for (const fps of fpsList) {
    if (fps > expected) {
      expected = fps;
    }
  }
  return { expected: expected, min: Math.floor(expected / 2), max: expected };
}

// 这一拍该不该给这张贴纸要帧。时钟按全体最高帧率跳，30fps 的贴纸在 60Hz 下隔一拍
// 才要。时刻是 displaySync 的 targetTimestamp 换成的浮点毫秒，判据留四分之一个
// 间隔的余量，不能因为差零点几微秒就错过一拍。
export function tgsFrameDue(lastRequestMs: number, targetMs: number, playbackFps: number): boolean {
  if (lastRequestMs < 0) {
    return true;
  }
  const fps: number = playbackFps > 0 ? playbackFps : TGS_MAX_FPS;
  return targetMs - lastRequestMs >= (1000 / fps) * 0.75;
}
