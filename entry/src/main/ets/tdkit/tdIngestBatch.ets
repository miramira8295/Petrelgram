// worker 侧的批投递（A 批 3）。
//
// 【为什么】真机 spike 实测（2026-11-06，Mate 70 Pro+）：冷启动后约 100 秒收到
// 1.5 万条更新。改造前每一条都是一次 postMessage、在 UI 侧占一个任务；把窗口
// 内的多条合成一个批次，跨线程次数从「条数」降到「批数」，UI 侧的任务排队
// 也从 1.5 万次变成几百次。解析本身没省（那是 batch 内每条还是要做的），
// 省的是投递与调度这两层固定开销。
//
// 【顺序是铁律】批内相对顺序 = 到达顺序，批与批之间也按发出顺序到达（worker
// 的 postMessage 单队列 FIFO）。调用方（TdWorker）在把不可交换事件并入批次前
// 必须先冲掉合并积压，这一条不变。
//
// 【响应不吃窗口】带 @extra 的响应要尽快回到 UI 的 pending 表：先冲掉已排队的
// 那一批，再单独投递响应本身，既保序又不给请求-响应加最多一个窗口的延迟。
// 这个判据放在调用方（TdWorker），本文件只管攒与发。

export const BATCH_WINDOW_MS: number = 8;
export const BATCH_MAX_ITEMS: number = 64;

export interface BatchTimerFns {
  setTimeout: (cb: () => void, ms: number) => number;
  clearTimeout: (id: number) => void;
}

export class TdIngestBatch {
  private items: object[] = [];
  private timerId: number = -1;
  private emit: (items: object[]) => void;
  private timer: BatchTimerFns;
  private windowMs: number;
  private maxItems: number;

  constructor(emit: (items: object[]) => void, timer: BatchTimerFns,
    windowMs: number = BATCH_WINDOW_MS, maxItems: number = BATCH_MAX_ITEMS) {
    this.emit = emit;
    this.timer = timer;
    this.windowMs = windowMs;
    this.maxItems = maxItems;
  }

  pending(): number {
    return this.items.length;
  }

  // 攒一条。到上限立即发（风暴时不依赖定时器），否则等窗口到点。
  push(obj: object): void {
    this.items.push(obj);
    if (this.items.length >= this.maxItems) {
      this.flush();
      return;
    }
    if (this.timerId === -1) {
      this.timerId = this.timer.setTimeout((): void => {
        this.timerId = -1;
        this.flush();
      }, this.windowMs);
    }
  }

  // 立即发掉当前积压（响应屏障、销毁前都走这里）。空批不发。
  flush(): void {
    if (this.timerId !== -1) {
      this.timer.clearTimeout(this.timerId);
      this.timerId = -1;
    }
    if (this.items.length === 0) {
      return;
    }
    const out: object[] = this.items;
    this.items = [];
    this.emit(out);
  }

  // 账号切换/销毁：旧账号的积压直接丢掉，不发给新运行时。
  reset(): void {
    if (this.timerId !== -1) {
      this.timer.clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.items = [];
  }
}
