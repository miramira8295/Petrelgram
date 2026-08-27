// 复用路径上「下一帧再读新参数」的共享队列。
//
// 为什么需要它（真机 CPU profile，滚动聊天列表）：一条被复用的消息行会为它下面
// 的每个组件各建一个 setTimeout(0)——CachedImage.aboutToReuse ≈ 393ms、
// MessageBubble.aboutToReuse ≈ 273ms、ReusableMessageBubble.aboutToReuse ≈ 254ms，
// 合计约 776ms 自耗时，上层 traverseChildDoRecycleOrReuse 占主线程 JS 的 28.7%。
// 一帧里复用 N 行就是 N×(3~4) 个定时器，每个都单独进一次 JS 事件循环。
//
// **这些定时器的语义必须保留，只许合并、不许删。** 父级 ReusableMessageBubble
// 是 @ReusableV2，它的 aboutToReuse **没有入参**（官方《@ReusableV2装饰器：V2
// 组件复用》），reuseParam(params, key) 因此恒为 undefined；复用时的状态重置也
// **不触发 @Monitor / @Watch**（同一篇「复用前的组件内状态变量重置」：重置过程中
// 产生的变量变化不会触发回调）。也就是说，延后一帧再读 this.* 是旁路订阅重新
// 挂载的**唯一已知路径**。删掉 = 复用出来的行永远停在静态快照上。
//
// 这里只做一件事：把那 N×(3~4) 个定时器合并成**一帧一个**。
//
// 三条不变式：
//   1. 一帧只起一个定时器。已经起过就只往队列里塞，不再起。
//   2. 同一个 owner 后写覆盖先写。组件在回调跑之前又被复用了一次时，只有最后
//      那次的回调该跑——这就是「用组件序号防止过期回调」。Map 按 ownerId 存，
//      set 天然是覆盖语义。
//   3. 执行前先把 Map 换成新的空 Map，再遍历旧的。回调里再 enqueue 要进**下一
//      帧**，不能追加进当前这一批——否则一次 flush 可能无限接下去，把「合并成
//      一帧」变成「一帧里跑完所有后续帧的活」。
//
// 逐个 try/catch：一个组件的回调抛错不能吞掉后面所有组件的重挂。

import { logE } from './log';

// 定时器可注入，纯粹是为了可测：单测注入一个手动 flush 的假调度器，就能在没有
// 事件循环的宿主环境里断言「N 次 enqueue 只起 1 个定时器」这类时序性质。
// 生产环境永远用默认实现。
export type NextFrameScheduler = (run: () => void) => void;

const defaultScheduler: NextFrameScheduler = (run: () => void): void => {
  setTimeout((): void => { run(); }, 0);
};

let scheduler: NextFrameScheduler = defaultScheduler;
let pending: Map<number, () => void> = new Map<number, () => void>();
let armed: boolean = false;
let ownerSeq: number = 0;

// 每个组件实例构造时取一次，存成私有字段。
//
// 为什么可以存成无装饰器私有字段：@Reusable / @ReusableV2 复用的是**同一个组件
// 对象**，构造器不会重跑，而官方的「复用前的组件内状态变量重置」表最后一行写明
// 「常量：包括 readonly 的常量，不重置」——无装饰器成员按常量处理。所以 ownerId
// 在整个实例生命周期里稳定，正是不变式 2 需要的。
export function nextFrameOwnerId(): number {
  ownerSeq++;
  return ownerSeq;
}

function runBatch(): void {
  // 先解除武装、再换空 Map，最后才遍历旧的：这样回调里的 enqueue 会重新武装一
  // 个新定时器，并落进新 Map（不变式 3）。
  armed = false;
  const batch: Map<number, () => void> = pending;
  pending = new Map<number, () => void>();
  batch.forEach((task: () => void, ownerId: number): void => {
    try {
      task();
    } catch (e) {
      logE(`nextFrameQueue owner=${ownerId} task failed: ${e}`);
    }
  });
}

// 把 task 排到下一帧。同一个 ownerId 重复排队时，只有最后一次会跑。
export function enqueueNextFrame(ownerId: number, task: () => void): void {
  pending.set(ownerId, task);
  if (armed) {
    return;
  }
  armed = true;
  scheduler(runBatch);
}

// 撤掉这个 owner 还没跑的那一条。组件被回收进复用池或销毁时调用：那时
// aboutToRecycle / aboutToDisappear 已经退订并清了状态，过期回调再跑一次会把
// 订阅重新挂到一个不在树上的组件实例上——没人再去退订它。
export function cancelNextFrame(ownerId: number): void {
  pending.delete(ownerId);
}

// —— 以下两个只给单测用 ——
export function setNextFrameScheduler(next: NextFrameScheduler): void {
  scheduler = next;
}

// 队列是模块级状态，用例之间必须能清干净，否则一条用例的残留会污染下一条。
export function resetNextFrameQueue(): void {
  pending = new Map<number, () => void>();
  armed = false;
  scheduler = defaultScheduler;
}

export function pendingNextFrameCount(): number {
  return pending.size;
}
