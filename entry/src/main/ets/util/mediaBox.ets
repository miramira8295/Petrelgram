// The on-screen size of a message's inline media.
//
// Shared rather than a method on MessageBubble because the prefetcher has to
// arrive at exactly the same numbers: the pixel cache is keyed by path AND
// target size, so a prefetch computed even one pixel differently decodes into a
// second entry that the bubble never asks for — twice the work and no benefit.
//
// It is computable ahead of layout on purpose: every input is the chat content
// column width (util/chatContentWidth — the window width on phones, the right
// column in split view), a field of the message, or the fixed device type,
// never a per-row measurement.

import { deviceInfo } from '@kit.BasicServicesKit';

// 设备类型在进程内不变；折叠手机也按系统报告的 phone 处理，不按窗口宽度猜测。
const MEDIA_DEVICE_TYPE: string = deviceInfo.deviceType;
const MEDIA_MAX_WIDTH: number = 280;
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

export function inlineMaxWidth(screenW: number,
  avatarGutter: number = BUBBLE_AVATAR_GUTTER_VP): number {
  return Math.max(0, bubbleMaxWidth(screenW, avatarGutter) - 16);
}

// 手机媒体铺满可用气泡宽；其他设备保留原来的 280vp 上限。
// 展示、预取、估高及源图档位统一走这里，避免同一媒体出现两套目标尺寸。
export function mediaThumbWidth(screenW: number,
  avatarGutter: number = BUBBLE_AVATAR_GUTTER_VP,
  deviceType: string = MEDIA_DEVICE_TYPE): number {
  const available: number = inlineMaxWidth(screenW, avatarGutter);
  return deviceType === 'phone' ? available : Math.min(MEDIA_MAX_WIDTH, available);
}

// 照片使用消息中已有的 TDLib photoSize 比例，不依赖异步解码回调改变布局。
// 无有效元数据时保留正方形占位；视频维持现有的比例夹取与裁切策略。
const VIDEO_RATIO_MIN: number = 0.4;
const VIDEO_RATIO_MAX: number = 2.4;

export function mediaRatio(photoW: number, photoH: number, isVideo: boolean): number {
  if (Number.isFinite(photoW) && Number.isFinite(photoH) && photoW > 0 && photoH > 0) {
    const ratio: number = photoW / photoH;
    if (Number.isFinite(ratio) && ratio > 0) {
      return isVideo ? Math.max(VIDEO_RATIO_MIN, Math.min(VIDEO_RATIO_MAX, ratio)) : ratio;
    }
  }
  return isVideo ? 16 / 9 : 1;
}

export function mediaBoxFor(
  screenW: number, photoW: number, photoH: number, isVideo: boolean,
  avatarGutter: number = BUBBLE_AVATAR_GUTTER_VP,
  deviceType: string = MEDIA_DEVICE_TYPE
): MediaBox {
  const maxW = mediaThumbWidth(screenW, avatarGutter, deviceType);
  const maxH = maxW * MEDIA_MAX_HEIGHT_RATIO;
  const ratio = mediaRatio(photoW, photoH, isVideo);
  // 照片同时适配宽高上限：高度触顶时宽度必须按同一比例缩小。
  // 横图、竖图及极端长图都完整展示；最大尺寸仍沿用聊天列的既有约束。
  // 视频的内嵌播放渲染面依赖原来的满宽裁切，保持该分支的几何不变。
  const height: number = Math.min(maxW / ratio, maxH);
  return { width: isVideo ? maxW : Math.min(maxW, height * ratio), height };
}
