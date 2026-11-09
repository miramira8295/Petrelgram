// 群聊头像动画的「停车」闸（2026-09-18）。
//
// 【它解决的是退场那一帧】真机 trace（scripted 三进三出）：退出会话时最差帧
// 47–57ms，固定落在切换开始后 ~620ms，也就是转场动画刚结束、列表重新露脸的
// 那一刻。那一帧里 466 次 aboutToBeDeleted，单节点最贵的正是
// SenderAnimatedLayer —— 17 个 / 17.3ms，**平均 1.02ms/个**，而 MessageBubble
// 只有 0.29、MessageRowHost 0.09。它贵是因为里面挂着一路 AVPlayer（AvLoopVideo），
// 整棵树同步销毁时这些播放器一起结账，还带出几笔 34–53ms 的 JsRelease。
//
// 【和滚动闸的区别】chatAnimationGate 是「暂停」：播放器留着，只是不出帧——
// 滚动停下来要立刻能接着放，重建播放器反而更贵。这道闸是「卸下」：让
// SenderAnimatedLayer 主动交还名额、把 AvLoopVideo 从树上摘掉，于是播放器在
// **转场那 600ms 里**被逐个释放，而不是全挤在最后一帧。
//
// 两道闸互不替代，所以是两个独立信号。

export type SenderAnimationParkListener = (parked: boolean) => void;

let parked: boolean = false;
const listeners: Set<SenderAnimationParkListener> = new Set<SenderAnimationParkListener>();

export function senderAnimationsParked(): boolean {
  return parked;
}

// 订阅并**立刻回调一次当前值**：转场途中挂上来的行不能默认"没停车"。
export function subscribeSenderAnimationPark(listener: SenderAnimationParkListener): () => void {
  listeners.add(listener);
  listener(parked);
  return (): void => { listeners.delete(listener); };
}

export function parkSenderAnimations(next: boolean): void {
  if (parked === next) {
    return;
  }
  parked = next;
  listeners.forEach((listener: SenderAnimationParkListener): void => { listener(next); });
}

// 只给单测用：模块级状态在同一个进程里跨用例活着。
export function resetSenderAnimationPark(): void {
  parked = false;
  listeners.clear();
}
