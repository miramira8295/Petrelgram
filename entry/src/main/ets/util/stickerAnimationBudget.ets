import { AnimationSlotPool } from './animationSlotPool';

// 贴纸动画的同时播放名额：TGS（原生 rlottie、lottie 兜底）与 WebM 帧序列**共用**（2026-09-15）。
//
// 原来各算各的——WebM 帧序列 12 张、原生 TGS 完全不设限（它的文件头写着"这里没有这个上限"）、
// lottie 面板 14 张 / 会话 4 张——同屏可能 12 张 WebM 叠上不限量的 TGS。扫描时的采样里 GPU
// 平均 71%、六成采样点满载，与此吻合：每一张在动的贴纸每帧都要合成一次画布。
//
// 按所在区域分池：贴纸抽屉一池、会话时间线一池、其余零散调用点（资料页、标题栏的表情状态等）
// 一池，互不挤占。只给在屏幕上的格子名额，滑出屏幕立刻归还；拿不到的显示缩略图或定格在当前帧，
// 名额让出时转给最后排队的。以后可以按"像素面积 × 帧率"加权，现在先按个数。
export const PANEL_ANIMATION_SLOTS: number = 8;
export const CHAT_ANIMATION_SLOTS: number = 4;
export const OTHER_ANIMATION_SLOTS: number = 8;

const panelSlots: AnimationSlotPool = new AnimationSlotPool(PANEL_ANIMATION_SLOTS);
const chatSlots: AnimationSlotPool = new AnimationSlotPool(CHAT_ANIMATION_SLOTS);
const otherSlots: AnimationSlotPool = new AnimationSlotPool(OTHER_ANIMATION_SLOTS);

// chatTimeline / panelGated 在一个组件的生命周期里是常量，所以取到的一直是同一个池。
export function stickerAnimationSlots(chatTimeline: boolean, panelGated: boolean): AnimationSlotPool {
  if (panelGated) {
    return panelSlots;
  }
  return chatTimeline ? chatSlots : otherSlots;
}
