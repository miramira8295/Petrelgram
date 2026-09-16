// 「此刻该不该动」的闸门：滚动时统一暂停，停稳后逐个放出。
//
// 原来只有会话时间线一道，是 util/chatAnimationGate 里的模块级单例。2026-09-15
// 贴纸抽屉也要同样的待遇（滑动时暂停、停下后屏幕上的先放），而两道闸必须互不
// 牵连：会话列表停了不能把还在滑的抽屉放开，反过来也一样。所以逻辑收成一个类，
// 会话和抽屉各持一个实例。
//
// 【关闸一起关，开闸排队放】关闸同一刻全部生效（停下来很便宜、也必须立刻停）；
// 开闸逐个放出：屏幕上的先放，不知道在不在屏幕上的其次，屏幕外的最后，相邻两个
// 之间隔 staggerMs。为什么要排队见 chatAnimationGate 的文件头。
export type AnimationGateListener = (suspended: boolean) => void;
// 订阅方此刻在不在屏幕上。只用来排开闸的先后，不参与"放不放"。
export type AnimationGateOnScreen = () => boolean;
export type AnimationGateSchedule = (run: () => void, delayMs: number) => number;
export type AnimationGateCancel = (id: number) => void;

interface AnimationGateEntry {
  listener: AnimationGateListener;
  onScreen: AnimationGateOnScreen | null;
  active: boolean;
}

function defaultSchedule(run: () => void, delayMs: number): number {
  return setTimeout(run, delayMs);
}

function defaultCancel(id: number): void {
  clearTimeout(id);
}

export class AnimationGate {
  private readonly staggerMs: number;
  private suspended: boolean = false;
  private entries: AnimationGateEntry[] = [];
  private releaseQueue: AnimationGateEntry[] = [];
  private releaseTimer: number = -1;
  private schedule: AnimationGateSchedule = defaultSchedule;
  private cancel: AnimationGateCancel = defaultCancel;

  // staggerMs 为 0 就是"同一拍全放"。
  constructor(staggerMs: number) {
    this.staggerMs = staggerMs;
  }

  setSuspended(next: boolean): void {
    if (this.suspended === next) {
      return;
    }
    this.suspended = next;
    if (next) {
      this.cancelRelease();
      for (const entry of this.entries.slice()) {
        entry.listener(true);
      }
      return;
    }
    this.releaseQueue = this.releaseOrder(this.entries);
    this.releaseNext();
  }

  isSuspended(): boolean {
    return this.suspended;
  }

  // 订阅时立刻回调一次当前值：挂载在滑动中途的格子不能默认"门是开的"。
  subscribe(listener: AnimationGateListener, onScreen?: AnimationGateOnScreen): () => void {
    const entry: AnimationGateEntry = { listener: listener, onScreen: onScreen ?? null, active: true };
    this.entries = [...this.entries, entry];
    listener(this.suspended);
    return (): void => {
      entry.active = false;
      this.entries = this.entries.filter((e: AnimationGateEntry): boolean => e !== entry);
    };
  }

  // 名额腾出来了：叫醒因为超预算被推迟的视图。只在门开着时广播；还在开闸队列里
  // 排着的不叫，它们会按顺序被放出来，别让这一下插队。
  wake(): void {
    if (this.suspended) {
      return;
    }
    for (const entry of this.entries.slice()) {
      if (this.releaseQueue.indexOf(entry) < 0) {
        entry.listener(false);
      }
    }
  }

  // 走同一套（可注入的）定时器：调用方的"延迟开闸"在单测里也能一步步推进。
  defer(run: () => void, delayMs: number): number {
    return this.schedule(run, delayMs);
  }

  cancelDeferred(id: number): void {
    this.cancel(id);
  }

  // ---- 仅供单测 ----
  setTimersForTest(nextSchedule: AnimationGateSchedule, nextCancel: AnimationGateCancel): void {
    this.schedule = nextSchedule;
    this.cancel = nextCancel;
  }

  resetForTest(): void {
    this.suspended = false;
    this.entries = [];
    this.releaseQueue = [];
    this.releaseTimer = -1;
    this.schedule = defaultSchedule;
    this.cancel = defaultCancel;
  }

  // 屏幕上的 → 不知道的 → 屏幕外的；同一档内保持订阅顺序。
  private releaseRank(entry: AnimationGateEntry): number {
    if (entry.onScreen === null) {
      return 1;
    }
    return entry.onScreen() ? 0 : 2;
  }

  private releaseOrder(list: AnimationGateEntry[]): AnimationGateEntry[] {
    const ranked: AnimationGateEntry[][] = [[], [], []];
    for (const entry of list) {
      ranked[this.releaseRank(entry)].push(entry);
    }
    return [...ranked[0], ...ranked[1], ...ranked[2]];
  }

  private releaseNext(): void {
    this.releaseTimer = -1;
    while (this.releaseQueue.length > 0) {
      const entry: AnimationGateEntry = this.releaseQueue.shift() as AnimationGateEntry;
      if (!entry.active) {
        continue;
      }
      if (this.suspended) {
        this.releaseQueue = [];
        return;
      }
      entry.listener(false);
      if (this.releaseQueue.length > 0) {
        if (this.staggerMs <= 0) {
          continue;
        }
        this.releaseTimer = this.schedule((): void => { this.releaseNext(); }, this.staggerMs);
      }
      return;
    }
  }

  private cancelRelease(): void {
    if (this.releaseTimer !== -1) {
      this.cancel(this.releaseTimer);
      this.releaseTimer = -1;
    }
    this.releaseQueue = [];
  }
}
