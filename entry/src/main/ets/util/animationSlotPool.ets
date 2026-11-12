// 同时在动的名额池：满了排队，让出的名额直接转给**最后排进来的**那一格。
//
// 贴纸面板往哪边滑，最新挂上的格子就在哪边刚进屏幕；先排队的多半已经被滑走，
// 滑走的格子会撤销排队，不会白占。
//
// 起初只给 WebM 帧序列用（名额满了不退回 ijkplayer，见 AlphaWebmStickerView 文件头那段
// 「不再退回 ijkplayer」的注释）；同日起 TGS 与 WebM 共用，按区域分池，见 util/stickerAnimationBudget。
class AnimationSlotWaiter {
  previous: AnimationSlotWaiter | null = null;
  next: AnimationSlotWaiter | null = null;
  callback: (() => void) | null;
  queued: boolean = true;
  constructor(callback: () => void) { this.callback = callback; }
}

export class AnimationSlotPool {
  private readonly capacity: number;
  private live: number = 0;
  private tail: AnimationSlotWaiter | null = null;
  private waiting: number = 0;

  constructor(capacity: number) { this.capacity = Math.max(0, Math.floor(capacity)); }
  liveCount(): number { return this.live; }
  waitingCount(): number { return this.waiting; }
  tryAcquire(): boolean {
    if (this.live >= this.capacity) { return false; }
    this.live++; return true;
  }

  // Intrusive LIFO list: add, cancel and grant each unlink in O(1). Cancellation
  // drops the closure immediately, not a tombstone retained until a future pop.
  wait(onGranted: () => void): () => void {
    const entry = new AnimationSlotWaiter(onGranted);
    entry.previous = this.tail;
    if (this.tail !== null) { this.tail.next = entry; }
    this.tail = entry; this.waiting++;
    return (): void => { this.unlink(entry); };
  }
  private unlink(entry: AnimationSlotWaiter): void {
    if (!entry.queued) { return; }
    if (entry.previous !== null) { entry.previous.next = entry.next; }
    if (entry.next !== null) { entry.next.previous = entry.previous; }
    else { this.tail = entry.previous; }
    entry.previous = null; entry.next = null; entry.callback = null; entry.queued = false; this.waiting--;
  }
  releaseQuietly(): void { if (this.live > 0) { this.live--; } }
  release(): void {
    if (this.live <= 0) { return; }
    const entry = this.tail;
    if (entry === null) { this.live--; return; }
    const callback = entry.callback;
    this.unlink(entry);
    // Ownership is transferred before user code; reentrant cancellation/release
    // sees the final queue state, preserving the original grant order/counts.
    if (callback !== null) { callback(); }
  }
}
