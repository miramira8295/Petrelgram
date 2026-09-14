import { logW } from './log';

// 头插分批（方案 A，2026-09-14）。
//
// 【为什么要分批】Repeat.virtualScroll 的 reRender 只在**旧活跃区间**（可视区 +
// 上下缓存，trace 里的 `keep in [a]-[b]`）那些下标上按 key 认领移了位的行。一次
// 头插 N 行，可视行的新下标落到旧区间之外就认领不到，进空闲池；reusable:false
// 下 canUpdateTryMatch 第一句就返回 -1，同 key 也取不回，只能新建。
// 翻历史每页合并前插 29 行 > List.cachedCount(8) ⇒ 每次翻页可视行整屏新建：
// 13:52 trace 翻页帧 68–104ms，之后 200ms 里还要在帧内重建上方缓存行；进会话后
// 55 个掉帧里 50 个出在这两处（记忆 repeat-prepend-rebuild-threshold）。
//
// 每批不超过 cachedCount 行时，可视行和上方缓存行的新下标仍在旧区间内 ⇒ 被认领、
// 不重建。List 布局时用 needBuild=false 就能取到这些现成节点，上报的区间照样带着
// 缓存区，不会在下一步被 onActiveRange 清掉（list_layout_algorithm
// LayoutCachedForward/Backward）。
//
// 【批与批之间为什么要等】每插 K 行，下方缓存最远的 K 行会被挤出旧区间，由空闲
// 预建补回（trace 里缓存预建全在空闲，不掉帧）。下一批必须等它们补回来，否则保留
// 区间的下沿缩回可视区，屏幕上的行又被挤出去重建。框架不把活跃区间告诉应用，只能
// 按时间等。
//
// 【形状】每次只放出紧贴已显示内容的那一段，也就是 target 的一个后缀——中间态就是
// 「少几页历史」的合法快照，所以预取源 / timelineRows / groups 天然同批推进，不需要
// 另立不变量。续发时拿最近一次传进来的 target 重走一遍发布；期间来的其它发布
// （尾部追加、编辑、裁剪）照常发，头部照样扣着。
//
// 【何时不分】总开关关、宿主此刻不允许（页面隐藏、首屏分级揭示期）、已显示为空、
// 已显示的第一行在新快照里找不到（跳转落地、整窗替换）：原样发布，清掉在途批次。

// 总开关。false = 头插一次发完（回到 2026-09-14 之前的行为）。
export const PREPEND_CHUNK_ENABLED: boolean = true;

// 两批之间至少隔多久。被挤掉的下方缓存要靠空闲预建补回：一行约 6ms，滑动中每帧
// 空闲只有几毫秒，8 行大约要十来帧。先取 120ms；真机 trace 看批次帧里还有没有
// CREATED_NEW_NODE 再调。
export const PREPEND_CHUNK_GAP_MS: number = 120;

// 定时器早到几毫秒也算到点，免得为这几毫秒再排一次。
const GAP_TOLERANCE_MS: number = 4;
const NO_TIMER: number = -1;

export interface PrependChunkClock {
  now(): number;
  schedule(callback: () => void, delayMs: number): number;
  cancel(handle: number): void;
}

// 成员写成函数类型属性（同 TranslationDriverHost）：宿主在页面里用对象字面量实现。
export interface PrependChunkHost {
  // 每批最多插几行：List.cachedCount。
  chunkRows: () => number;
  // 此刻允许分批吗（页面可见、不在首屏分级揭示期）。
  allowed: () => boolean;
  // 到点续发：宿主拿 latestTarget() 重走一次发布。
  republish: () => void;
}

class SystemChunkClock implements PrependChunkClock {
  now(): number {
    return Date.now();
  }

  schedule(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs);
  }

  cancel(handle: number): void {
    clearTimeout(handle);
  }
}

// 已显示的第一行在 target 里的下标，只在 [0, scanTo] 里找；找不到返回 -1。
// hint 是最可能的位置（纯前插时就是新增行数），先试它，省得逐行拼身份串。
export function headOffsetOf<T>(
  displayed: T[], target: T[], identity: (row: T) => string, hint: number, scanTo: number
): number {
  if (displayed.length === 0 || target.length === 0) {
    return -1;
  }
  const first: string = identity(displayed[0]);
  const last: number = Math.min(scanTo, target.length - 1);
  if (hint >= 0 && hint <= last && identity(target[hint]) === first) {
    return hint;
  }
  for (let i = 0; i <= last; i++) {
    if (i !== hint && identity(target[i]) === first) {
      return i;
    }
  }
  return -1;
}

export class PrependChunker<T> {
  private readonly identity: (row: T) => string;
  private readonly enabled: boolean;
  private readonly clock: PrependChunkClock;
  private host: PrependChunkHost | null = null;
  private target: T[] | null = null;
  // 还扣着没发的头部行数。
  private withheld: number = 0;
  // 上一次真正往头部插行的时刻；-1 = 还没插过。
  private lastInsertAt: number = -1;
  private timer: number = NO_TIMER;

  constructor(identity: (row: T) => string, enabled: boolean, clock?: PrependChunkClock) {
    this.identity = identity;
    this.enabled = enabled;
    this.clock = clock ?? new SystemChunkClock();
  }

  bind(host: PrependChunkHost): void {
    this.host = host;
  }

  dispose(): void {
    this.clearPending();
    this.host = null;
    this.target = null;
  }

  pendingRows(): number {
    return this.withheld;
  }

  latestTarget(): T[] | null {
    return this.target;
  }

  // 给定已显示的行和这次想发布的完整快照，返回这次真正该发布的行：
  // target 本身，或扣掉开头若干行之后的后缀。
  shape(displayed: T[], target: T[]): T[] {
    this.target = target;
    const host: PrependChunkHost | null = this.host;
    if (!this.enabled || host === null || !host.allowed() || displayed.length === 0) {
      this.clearPending();
      return target;
    }
    const grow: number = target.length - displayed.length;
    if (grow <= 0 && this.withheld === 0) {
      return target;
    }
    const k: number = Math.max(1, Math.floor(host.chunkRows()));
    const head: number = headOffsetOf<T>(
      displayed, target, this.identity, grow, Math.max(grow, this.withheld) + k);
    if (head <= 0) {
      this.clearPending();
      return target;
    }
    const withhold: number = this.withholdFor(head, k);
    // 一行都不扣就原样返回同一个数组：一次小前插不值得整份拷贝。
    return withhold === 0 ? target : target.slice(withhold);
  }

  // 这次要扣下 target 开头多少行。
  private withholdFor(head: number, k: number): number {
    const now: number = this.clock.now();
    const sinceLast: number = this.lastInsertAt < 0 ? -1 : now - this.lastInsertAt;
    if (sinceLast >= 0 && sinceLast + GAP_TOLERANCE_MS < PREPEND_CHUNK_GAP_MS) {
      // 上一批挤掉的下方缓存还没补回来：这次一行头部都不放，到点再来。
      this.withheld = head;
      this.arm(PREPEND_CHUNK_GAP_MS - sinceLast, false);
      return head;
    }
    this.lastInsertAt = now;
    if (head <= k) {
      if (this.withheld > 0) {
        logW(`[PrependChunk] done last=${head} k=${k} since=${sinceLast}`);
      }
      this.clearPending();
      return 0;
    }
    const left: number = head - k;
    logW(`[PrependChunk] head=${head} k=${k} left=${left} since=${sinceLast}`);
    this.withheld = left;
    this.arm(PREPEND_CHUNK_GAP_MS, true);
    return left;
  }

  private arm(delayMs: number, restart: boolean): void {
    if (this.timer !== NO_TIMER) {
      if (!restart) {
        return;
      }
      this.clock.cancel(this.timer);
    }
    this.timer = this.clock.schedule((): void => {
      this.onTimer();
    }, Math.max(0, delayMs));
  }

  private onTimer(): void {
    this.timer = NO_TIMER;
    const host: PrependChunkHost | null = this.host;
    if (this.withheld > 0 && host !== null && this.target !== null) {
      host.republish();
    }
  }

  private clearPending(): void {
    this.withheld = 0;
    if (this.timer !== NO_TIMER) {
      this.clock.cancel(this.timer);
      this.timer = NO_TIMER;
    }
  }
}
