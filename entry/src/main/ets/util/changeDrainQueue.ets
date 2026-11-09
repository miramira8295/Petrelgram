// 列表 CHANGE 通知的分帧队列（2026-09-15，贴纸抽屉）。
//
// 缩略图和动画源是一批批落地的：refreshGrid 去抖 80ms 后把到达的格子一次性全报成
// CHANGE，十几个格子就在同一个 VSync 里重建、建图、重测 Grid。这里只负责"攒下标、
// 按优先级取一小批"：可视范围内的先取（按下标顺序），不够再取离可视范围最近的。
// 定时与通知由数据源自己做，这个类是纯逻辑，可单测。
export class ChangeDrainQueue {
  private pending: Set<number> = new Set();

  add(index: number): void {
    if (index >= 0) {
      this.pending.add(index);
    }
  }

  clear(): void {
    this.pending.clear();
  }

  size(): number {
    return this.pending.size;
  }

  // 取出下一批并从队列里删掉。[first, last] 是可视范围（调用方可以自己加上预加载的行）。
  takeBatch(first: number, last: number, limit: number): number[] {
    if (limit <= 0 || this.pending.size === 0) {
      return [];
    }
    const inside: number[] = [];
    const outside: number[] = [];
    this.pending.forEach((index: number): void => {
      if (index >= first && index <= last) {
        inside.push(index);
      } else {
        outside.push(index);
      }
    });
    inside.sort((a: number, b: number): number => a - b);
    outside.sort((a: number, b: number): number => this.distance(a, first, last) - this.distance(b, first, last));
    const batch: number[] = [...inside, ...outside].slice(0, limit);
    for (const index of batch) {
      this.pending.delete(index);
    }
    return batch;
  }

  private distance(index: number, first: number, last: number): number {
    return index < first ? first - index : index - last;
  }
}
