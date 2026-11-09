import { AnimationGate, AnimationGateListener, AnimationGateOnScreen } from './animationGate';
import { CHAT_GATE_RELEASE_STAGGER_MS, subscribeChatAnimationGate } from './chatAnimationGate';

// 贴纸抽屉的动画闸门（2026-09-15）。用户：「这个区域滑动的时候应该也是暂停的，
// 然后屏幕优先策略队列逐帧播放」——和会话时间线同一套：滑动时全部定格，停稳后
// 屏幕上的先放、逐个起播。与会话那道互不牵连，见 util/animationGate 的文件头。
//
// 停下后等一小会儿再开闸：fling 收尾、回弹、连续两次快滑之间都会先报停再报开始，
// 立刻开闸等于刚放出一两个又全部关掉，白付一次起播。数值与会话那边一致
// （ChatPage.scheduleChatTgsResume 的 140ms）。
export const STICKER_PANEL_RESUME_DELAY_MS: number = 140;

const panelGate: AnimationGate = new AnimationGate(CHAT_GATE_RELEASE_STAGGER_MS);
let resumeTimer: number = -1;

function cancelResume(): void {
  if (resumeTimer !== -1) {
    panelGate.cancelDeferred(resumeTimer);
    resumeTimer = -1;
  }
}

export function pauseStickerPanelForScroll(): void {
  cancelResume();
  panelGate.setSuspended(true);
}

export function resumeStickerPanelAfterScroll(): void {
  cancelResume();
  resumeTimer = panelGate.defer((): void => {
    resumeTimer = -1;
    panelGate.setSuspended(false);
  }, STICKER_PANEL_RESUME_DELAY_MS);
}

// 抽屉收起/销毁：别让下次打开时格子一挂上就看到"门关着"。
export function resetStickerPanelGate(): void {
  cancelResume();
  panelGate.setSuspended(false);
}

export function stickerPanelSuspended(): boolean {
  return panelGate.isSuspended();
}

// 按所在区域订阅：抽屉里的格子订阅这一道，会话时间线里的订阅会话那道。
export function subscribeAnimationGateFor(panel: boolean, listener: AnimationGateListener,
  onScreen?: AnimationGateOnScreen): () => void {
  return panel ? panelGate.subscribe(listener, onScreen) : subscribeChatAnimationGate(listener, onScreen);
}

// ---- 仅供单测 ----
export function stickerPanelGateForTest(): AnimationGate {
  return panelGate;
}

export function resetStickerPanelGateForTest(): void {
  resumeTimer = -1;
  panelGate.resetForTest();
}
