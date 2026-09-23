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

// 消息行到屏幕边的留白。MessageBubble / LightweightPlainTextBubble 的行内边距
// 都从这里取，不能各写各的——宽度公式要减掉同一个值。
// 群聊里它同时是**头像到屏幕边**的距离。
export const BUBBLE_ROW_SIDE_VP: number = 4;
// 发送者头像的直径，以及它和气泡之间的间隙。
//
// 【为什么要在这里定，而不是各写各的】头像位 = 直径 + 间隙，而这个和既是
// 「不画头像那行的占位内边距」，又是宽度公式要减掉的量，还是头像元素自己的
// margin。三处写死同一个数字，改一处漏两处就会出现「带头像那行比别的行窄」
// 或「气泡压到头像上」。
export const BUBBLE_AVATAR_SIZE_VP: number = 38;
export const BUBBLE_AVATAR_GAP_VP: number = 3;
// 群聊来信给头像留的位。
export const BUBBLE_AVATAR_GUTTER_VP: number = BUBBLE_AVATAR_SIZE_VP + BUBBLE_AVATAR_GAP_VP;
// 气泡对侧必须留出的最小空白。没有它，长消息会顶到另一边，一眼看不出是"谁发的"。
export const BUBBLE_OPPOSITE_MIN_GAP_VP: number = 28;

// 气泡最宽能到多少。
//
// 【原来是 screenW * 0.78，那个系数其实只对群聊来信成立】
// 当时的值：440 − 5(行边距) − 44(头像位) − 48(对侧留白) = 343 = 0.78 × 440。
// 也就是说这个系数把**头像位**算进了每一条消息，而发出去的消息和私聊来信
// 根本没有头像位，于是白白少了 44vp 宽——表现为长消息左边空一大块
// （用户 2026-09-23：「我发出去的消息距离左侧也应该更窄一点」）。
//
// 改成按实际占位算：avatarGutter 传 0 的行（发出的、私聊来信）能宽出 44vp，
// 群聊来信一个像素不变。
//
// 【默认值为什么是「有头像位」】util/initialMessageStage 那个首屏高度估算拿不到
// 逐行的会话类型，只能按最窄的一档估。估窄 ⇒ 估出的行数偏多 ⇒ 高度偏高，
// 这是安全的方向（占位比真实高，落地时收缩，不会出现内容被裁掉）。
export function bubbleMaxWidth(screenW: number,
  avatarGutter: number = BUBBLE_AVATAR_GUTTER_VP): number {
  const reserved: number = BUBBLE_ROW_SIDE_VP + Math.max(0, avatarGutter) +
    BUBBLE_OPPOSITE_MIN_GAP_VP;
  return Math.max(0, screenW - reserved);
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
