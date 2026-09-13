// 删除动画的旁路通道（issue #149）。
//
// 【为什么不用 transition】行的 disappear transition 没法在删除发生之后临时武装：
// 被删的那个节点不会再 rebuild，它用的是上一次 build 时记下的 TransitionEffect。
// 而常驻一个 disappear 效果又不行——Repeat 虚拟滚动把滚出去的行也销毁，那样滚动
// 时每一行都会淡一下（官方 FAQ faqs-arkui-1136 记的就是这个现象）。
//
// 所以顺序反过来：**删之前**先把要走的行标出来淡出（调用方用 animateTo 包住这次
// 标记，透明度/缩放就滑过去），~200ms 后 TDLib 的 updateDeleteMessages 到达，
// publishGroupsNow 里现成的 isInteriorRowRemoval + animateTo 负责把下面的行收上来。
// 两段自然接在一起。
//
// 一个 ChatPage 一条通道，只有被标记的行收到回调。
export class RowLeaveChannel {
  private leaving: Set<number> = new Set<number>();
  private listeners: Map<number, Set<(strength: number) => void>> = new Map();

  value(rowId: number): number {
    return this.leaving.has(rowId) ? 1 : 0;
  }

  mark(rowIds: number[]): void {
    for (const rowId of rowIds) {
      if (this.leaving.has(rowId)) {
        continue;
      }
      this.leaving.add(rowId);
      this.emit(rowId, 1);
    }
  }

  // 删除失败、或换了会话：把标记撤掉，行恢复原样。
  clear(): void {
    const marked: number[] = Array.from(this.leaving);
    this.leaving.clear();
    for (const rowId of marked) {
      this.emit(rowId, 0);
    }
  }

  subscribe(rowId: number, callback: (strength: number) => void): () => void {
    let callbacks: Set<(strength: number) => void> | undefined = this.listeners.get(rowId);
    if (callbacks === undefined) {
      callbacks = new Set();
      this.listeners.set(rowId, callbacks);
    }
    callbacks.add(callback);
    callback(this.value(rowId));
    return (): void => {
      const current: Set<(strength: number) => void> | undefined = this.listeners.get(rowId);
      if (current !== undefined) {
        current.delete(callback);
        if (current.size === 0) {
          this.listeners.delete(rowId);
        }
      }
    };
  }

  private emit(rowId: number, strength: number): void {
    this.listeners.get(rowId)?.forEach((callback: (strength: number) => void): void => {
      callback(strength);
    });
  }
}
