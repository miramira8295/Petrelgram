// 会话时间线里「此刻该不该动」的总闸：滚动、首屏分帧、页面不可见时统一暂停。
//
// 【为什么单独成文件】原来住在 TgsStickerView 里（那个文件里的 TODO 写着
// "这道闸其实已经不只属于贴纸了，将来该搬进 util"），订阅方已经有三类：TGS
// 贴纸、GIF（SmartLoopVideo）、以及新的原生 TGS 渲染。留在组件文件里还会让
// 组件之间互相 import——TgsStickerView ↔ TgsNativeStickerView 正好成环。
//
// ChatPage 直接驱动它，而不是把一个高频滚动标志塞进每个气泡的参数树。
type ChatGateListener = (suspended: boolean) => void;

let suspended: boolean = false;
let listeners: ChatGateListener[] = [];

export function setChatAnimationSuspended(next: boolean): void {
  if (suspended === next) {
    return;
  }
  suspended = next;
  for (const listener of listeners) {
    listener(next);
  }
}

export function chatAnimationSuspended(): boolean {
  return suspended;
}

// 订阅时立刻回调一次当前值：挂载在滑动中途的行不能默认"门是开的"。
export function subscribeChatAnimationGate(listener: ChatGateListener): () => void {
  listeners = [...listeners, listener];
  listener(suspended);
  return (): void => {
    listeners = listeners.filter((l: ChatGateListener): boolean => l !== listener);
  };
}

// 名额腾出来了：叫醒因为超预算被推迟的视图（只有 lottie 那条路有名额的概念）。
// 只在门开着时广播；各监听器自己判断"正在播的不动、推迟的才重试"。
export function wakeChatAnimationListeners(): void {
  if (suspended) {
    return;
  }
  for (const listener of listeners) {
    listener(false);
  }
}
