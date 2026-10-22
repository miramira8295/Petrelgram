// 删除动画的旁路通道（issue #149）。
//
// 【为什么不用 transition】行的 disappear transition 没法在删除发生之后临时武装：
// 被删的那个节点不会再 rebuild，它用的是上一次 build 时记下的 TransitionEffect。
// 而常驻一个 disappear 效果又不行——Repeat 虚拟滚动把滚出去的行也销毁，那样滚动
// 时每一行都会淡一下（官方 FAQ faqs-arkui-1136 记的就是这个现象）。
//
// 本地确认删除时先通过play等待可见气泡消散，再提交TDLib删除；
// 数据到达后由消息列表原有的补位动画收起空位。
//
// 一个 ChatPage 一条通道，只有被标记的行收到回调。
export interface DeleteRowGroup { head: DeleteRowHead; memberIds: number[]; }
interface DeleteRowHead { rowId: number; contentType?: string; }

// 相册只删部分成员时不能隐藏整组，保留原行由数据更新重排。
export function wholeDeleteRowIds(groups: DeleteRowGroup[], ids: number[]): number[] {
  const selected = new Set(ids);
  return groups.filter((group: DeleteRowGroup): boolean => group.memberIds.length > 0 &&
    group.head.contentType !== 'system' && group.head.contentType !== 'hidden' &&
    group.memberIds.every((id: number): boolean => selected.has(id)))
    .map((group: DeleteRowGroup): number => group.head.rowId);
}

export class RowLeaveChannel {
  private leaving: Set<number> = new Set<number>();
  private listeners: Map<number, Set<(strength: number) => void>> = new Map();
  private pending: Map<number, () => void> = new Map();
  private budget: number = 3200;

  particleBudget(): number { return this.budget; }

  // 仅等待已挂载的行；离屏回收、取消或超时都必须释放删除请求。
  async play(rowIds: number[], enabled: boolean): Promise<void> {
    if (!enabled) { return; }
    const visible = Array.from(new Set(rowIds)).filter((id: number): boolean =>
      (this.listeners.get(id)?.size ?? 0) > 0);
    if (visible.length === 0) { return; }
    this.budget = Math.max(128, Math.floor(3200 / visible.length));
    const waits: Promise<void>[] = visible.map((id: number): Promise<void> => new Promise<void>((resolve) => {
      this.pending.set(id, resolve);
    }));
    const timer = setTimeout((): void => {
      for (const id of visible) { this.complete(id); }
    }, 2200);
    try {
      this.mark(visible);
      await Promise.all(waits);
    } finally { clearTimeout(timer); }
  }

  complete(rowId: number): void {
    const done = this.pending.get(rowId);
    this.pending.delete(rowId);
    done?.();
  }

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
  restore(rowId: number): void {
    this.complete(rowId);
    if (this.leaving.delete(rowId)) { this.emit(rowId, 0); }
  }

  clear(): void {
    for (const rowId of Array.from(this.pending.keys())) { this.complete(rowId); }
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
          this.complete(rowId);
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
