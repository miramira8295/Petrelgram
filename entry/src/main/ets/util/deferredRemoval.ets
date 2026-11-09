// 下载中心「取消 / 删除」的撤销（2026-09-15）。
//
// 删缓存、取消下载都不可逆（TDLib 真的把文件删了），所以先不做：把这几条从列表里藏起来，底部给「撤销」，
// 过几秒没撤销才真正执行。新的一批进来时上一批立刻执行（一次只留一个撤销）；页面离开时也立刻执行。
// 执行之后条目继续藏着，直到数据源里确实没有了（forgetMissing）——否则异步删除回来之前会闪回一下。
// 执行失败由调用方 restore 放回。定时器可注入，便于单测。

export type TimerSchedule = (fn: () => void, ms: number) => number;
export type TimerCancel = (id: number) => void;

export interface DeferredBatch {
  ids: string[];
  message: string;
  commit: () => void;
}

export const UNDO_WINDOW_MS: number = 4000;

export class DeferredRemoval {
  private pending: DeferredBatch | null = null;
  private timer: number = -1;
  private hidden: Set<string> = new Set<string>();
  private readonly onChange: () => void;
  private readonly delayMs: number;
  private readonly scheduleFn: TimerSchedule;
  private readonly cancelFn: TimerCancel;

  constructor(onChange: () => void, delayMs: number = UNDO_WINDOW_MS,
    scheduleFn: TimerSchedule = (fn: () => void, ms: number): number => setTimeout(fn, ms),
    cancelFn: TimerCancel = (id: number): void => { clearTimeout(id); }) {
    this.onChange = onChange;
    this.delayMs = delayMs;
    this.scheduleFn = scheduleFn;
    this.cancelFn = cancelFn;
  }

  schedule(batch: DeferredBatch): void {
    this.flush();
    this.pending = batch;
    for (const id of batch.ids) {
      this.hidden.add(id);
    }
    this.timer = this.scheduleFn((): void => {
      this.timer = -1;
      this.flush();
    }, this.delayMs);
    this.onChange();
  }

  undo(): void {
    const batch: DeferredBatch | null = this.pending;
    if (batch === null) {
      return;
    }
    this.clearTimer();
    this.pending = null;
    for (const id of batch.ids) {
      this.hidden.delete(id);
    }
    this.onChange();
  }

  // 立即执行还没执行的那一批。
  flush(): void {
    const batch: DeferredBatch | null = this.pending;
    if (batch === null) {
      return;
    }
    this.clearTimer();
    this.pending = null;
    batch.commit();
    this.onChange();
  }

  // 执行失败：放回列表。
  restore(ids: string[]): void {
    for (const id of ids) {
      this.hidden.delete(id);
    }
    this.onChange();
  }

  // 数据源里已经没有的不用再藏（静默：调用方正在刷新列表）。等待撤销的那一批不动。
  forgetMissing(alive: Set<string>): void {
    const waiting: Set<string> = new Set<string>(this.pending !== null ? this.pending.ids : []);
    for (const id of Array.from(this.hidden)) {
      if (!alive.has(id) && !waiting.has(id)) {
        this.hidden.delete(id);
      }
    }
  }

  isHidden(id: string): boolean {
    return this.hidden.has(id);
  }

  message(): string {
    return this.pending !== null ? this.pending.message : '';
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      this.cancelFn(this.timer);
      this.timer = -1;
    }
  }
}
