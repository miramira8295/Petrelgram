// The on-screen size of a message's inline media.
//
// Shared rather than a method on MessageBubble because the prefetcher has to
// arrive at exactly the same numbers: the pixel cache is keyed by path AND
// target size, so a prefetch computed even one pixel differently decodes into a
// second entry that the bubble never asks for — twice the work and no benefit.
//
// It is computable ahead of layout on purpose: every input is the window width
// or a field of the message, never a measured width.

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

// Extreme source ratios stay visible through Cover cropping without producing
// an unusably narrow/tall bubble. An unknown photo is square; an unknown video
// starts at 16:9 so its placeholder does not jump once the size is known.
export function mediaRatio(photoW: number, photoH: number, isVideo: boolean): number {
  if (photoW > 0 && photoH > 0) {
    return Math.max(0.56, Math.min(2.1, photoW / photoH));
  }
  return isVideo ? 16 / 9 : 1;
}

export function mediaBoxFor(
  screenW: number, photoW: number, photoH: number, isVideo: boolean
): MediaBox {
  const maxW = mediaThumbWidth(screenW);
  const maxH = maxW * MEDIA_MAX_HEIGHT_RATIO;
  const ratio = mediaRatio(photoW, photoH, isVideo);
  // 宽度钉死在气泡宽度，横竖一视同仁。
  //
  // 原来超高时是「压高度 + 按比例缩宽度」，结果竖图只占气泡宽度的 67%，
  // 同一屏里比横图窄一截。多出来的高度交给 ImageFit.Cover 裁掉——这也是
  // 官方客户端的做法，点开就是完整图。
  const width = maxW;
  const height = Math.min(width / ratio, maxH);
  return { width, height };
}
