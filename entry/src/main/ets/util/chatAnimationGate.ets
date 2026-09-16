import {
  AnimationGate, AnimationGateCancel, AnimationGateListener, AnimationGateOnScreen, AnimationGateSchedule
} from './animationGate';

// 会话时间线里「此刻该不该动」的总闸：滚动、首屏分帧、页面不可见时统一暂停。
//
// 【为什么单独成文件】原来住在 TgsStickerView 里（那个文件里的 TODO 写着
// "这道闸其实已经不只属于贴纸了，将来该搬进 util"），订阅方已经有三类：TGS
// 贴纸、GIF（SmartLoopVideo）、以及新的原生 TGS 渲染。留在组件文件里还会让
// 组件之间互相 import——TgsStickerView ↔ TgsNativeStickerView 正好成环。
//
// ChatPage 直接驱动它，而不是把一个高频滚动标志塞进每个气泡的参数树。
//
// 【关闸一起关，开闸排队放】（2026-09-15）原来开闸是同一个任务里把所有订阅者
// 一口气叫醒：几个 GIF 播放器同时 play()、几张原生 TGS 同时开始要帧、透明 webm
// 同时起定时器——停稳后 140ms 那一下全挤在一起。用户实测「自己手机不卡、别的设备
// 卡」，正是这种一次性尖峰在弱设备上的样子。现在关闸照旧同一刻全部生效（停下来
// 很便宜、也必须立刻停），开闸改成逐个放出：屏幕上的先放，不知道在不在屏幕上的
// 其次，屏幕外的最后；两个之间隔 CHAT_GATE_RELEASE_STAGGER_MS。
//
// 逻辑本体在 util/animationGate（同日贴纸抽屉也要一道，收成了类）；这里是会话
// 那一个实例，对外的函数签名保持原样。

// 开闸时相邻两个订阅者之间的间隔。改成 0 就退回"同一拍全放"的旧行为。
export const CHAT_GATE_RELEASE_STAGGER_MS: number = 48;

const chatGate: AnimationGate = new AnimationGate(CHAT_GATE_RELEASE_STAGGER_MS);

export function setChatAnimationSuspended(next: boolean): void {
  chatGate.setSuspended(next);
}

export function chatAnimationSuspended(): boolean {
  return chatGate.isSuspended();
}

// 订阅时立刻回调一次当前值：挂载在滑动中途的行不能默认"门是开的"。
export function subscribeChatAnimationGate(listener: AnimationGateListener,
  onScreen?: AnimationGateOnScreen): () => void {
  return chatGate.subscribe(listener, onScreen);
}

// 名额腾出来了：叫醒因为超预算被推迟的视图（只有 lottie 那条路有名额的概念）。
export function wakeChatAnimationListeners(): void {
  chatGate.wake();
}

// ---- 仅供单测 ----
export function setChatGateTimersForTest(nextSchedule: AnimationGateSchedule,
  nextCancel: AnimationGateCancel): void {
  chatGate.setTimersForTest(nextSchedule, nextCancel);
}

export function resetChatAnimationGateForTest(): void {
  chatGate.resetForTest();
}
