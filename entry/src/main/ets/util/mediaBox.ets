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
  // 照片：宽度钉死在气泡宽度，横竖一视同仁。
  //
  // 原来超高时是「压高度 + 按比例缩宽度」，结果竖图只占气泡宽度的 67%，
  // 同一屏里比横图窄一截。多出来的高度交给 ImageFit.Cover 裁掉——这也是
  // 官方客户端的做法，点开就是完整图。
  //
  // 视频：**不能这么办**。播放器不会裁画面，只会把视频按真实比例塞进这个框，
  // 框比视频扁就左右留黑边，缩略图那侧又被 Cover 裁掉上下——用户看到的就是
  // 「缩略图被拉伸、一播放两边黑」。所以竖视频宁可窄一点，也要让框和画面
  // 同比例：高度顶到上限时，把宽度按比例一起收回来。
  const width = maxW;
  const height = Math.min(width / ratio, maxH);
  if (isVideo && height < width / ratio - 0.001) {
    return { width: height * ratio, height };
  }
  return { width, height };
}
