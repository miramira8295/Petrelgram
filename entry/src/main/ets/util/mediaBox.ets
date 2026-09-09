// The on-screen size of a message's inline media.
//
// Shared rather than a method on MessageBubble because the prefetcher has to
// arrive at exactly the same numbers: the pixel cache is keyed by path AND
// target size, so a prefetch computed even one pixel differently decodes into a
// second entry that the bubble never asks for — twice the work and no benefit.
//
// It is computable ahead of layout on purpose: every input is the chat content
// column width (util/chatContentWidth — the window width on phones, the right
// column in split view) or a field of the message, never a per-row measurement.

export const MEDIA_MAX_WIDTH: number = 280;
export const MEDIA_MAX_HEIGHT_RATIO: number = 1.2;

export interface MediaBox {
  width: number;
  height: number;
}

export function bubbleMaxWidth(screenW: number): number {
  return screenW * 0.78;
}

export function inlineMaxWidth(screenW: number): number {
  return bubbleMaxWidth(screenW) - 16;
}

export function mediaThumbWidth(screenW: number): number {
  return Math.min(MEDIA_MAX_WIDTH, inlineMaxWidth(screenW));
}

// 照片的极端比例靠 Cover 裁切消化，所以夹得比较紧，免得气泡窄成一条。
// 视频不能裁——播放器只会在框里留黑边——所以夹得宽一些，尽量按真实比例走。
// 尺寸未知时照片按正方形、视频按 16:9，免得尺寸到货后占位跳一下。
const PHOTO_RATIO_MIN: number = 0.56;
const PHOTO_RATIO_MAX: number = 2.1;
const VIDEO_RATIO_MIN: number = 0.4;
const VIDEO_RATIO_MAX: number = 2.4;

export function mediaRatio(photoW: number, photoH: number, isVideo: boolean): number {
  if (photoW > 0 && photoH > 0) {
    const lo: number = isVideo ? VIDEO_RATIO_MIN : PHOTO_RATIO_MIN;
    const hi: number = isVideo ? VIDEO_RATIO_MAX : PHOTO_RATIO_MAX;
    return Math.max(lo, Math.min(hi, photoW / photoH));
  }
  return isVideo ? 16 / 9 : 1;
}

export function mediaBoxFor(
  screenW: number, photoW: number, photoH: number, isVideo: boolean
): MediaBox {
  const maxW = mediaThumbWidth(screenW);
  const maxH = maxW * MEDIA_MAX_HEIGHT_RATIO;
  const ratio = mediaRatio(photoW, photoH, isVideo);
  // **宽度钉死在气泡宽度，横竖、照片视频一视同仁。** 多出来的高度交给
  // ImageFit.Cover 裁掉——官方客户端也是这么做的，点开就是完整画面。
  //
  // 【视频为什么也这样了】原来视频是例外：高度顶到上限时把宽度按比例收回来，
  // 理由是"播放器不会裁画面，框比视频扁就左右留黑边"。后果是一条 9:19.5 的
  // 竖视频只有 153vp 宽，而同一条消息的气泡被长配文撑到 277vp，媒体缩在气泡
  // 左边一小块（用户 2026-09-09 截图："媒体应该和气泡一样宽吧"）。
  //
  // 既然选了裁，就得**从头裁到尾**：内嵌播放位的渲染面同步改成 Cover
  // （StreamingVideoPlayer.surfaceWidth/Height，只在 embedded 下），否则静态
  // 缩略图是裁的、一点播放变回留黑边，尺寸当场跳一下——那正是上一版注释
  // 要避开的东西，只是解法从"收窄框"换成了"播放也裁"。
  // 全屏播放器不受影响：那一侧永远按真实比例留黑边，不裁。
  // 宽度一律钉死气泡宽度，横竖、图片视频一视同仁；超出的高度交给 Cover 裁掉。
  return { width: maxW, height: Math.min(maxW / ratio, maxH) };
}
