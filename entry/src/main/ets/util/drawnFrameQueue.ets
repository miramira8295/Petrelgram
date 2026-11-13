// Intrusive two-lane queue: enqueue/cancel/promote/dequeue are O(1). Work is
// bounded globally, not per row. No tombstones, history scans or Array.shift.
export class DrawnFrameWork {
  previous: DrawnFrameWork | null = null;
  next: DrawnFrameWork | null = null;
  owner: DrawnFrameQueue | null = null;
  urgent: boolean = false;
  run: (() => void) | null = null;
  schedule: ((task: () => void) => void) | null = null;
  since: number = 0;
}

export class DrawnFrameQueue {
  private heads: Array<DrawnFrameWork | null> = [null, null];
  private tails: Array<DrawnFrameWork | null> = [null, null];
  private count: number = 0;
  private posted: boolean = false;
  private draining: boolean = false;
  private urgentStreak: number = 0;
  private completed: number = 0;
  private cancelled: number = 0;
  private overflow: number = 0;
  private maxWait: number = 0;
  private clock: () => number;
  private failed: (error: Error) => void;
  private maxPerFrame: number;
  private budgetMs: number;
  private capacity: number;
  constructor(clock: () => number, failed: (error: Error) => void,
    maxPerFrame: number = 2, budgetMs: number = 1, capacity: number = 256) {
    this.clock = clock; this.failed = failed; this.maxPerFrame = maxPerFrame;
    this.budgetMs = budgetMs; this.capacity = capacity;
  }

  enqueue(schedule: (task: () => void) => void, run: () => void, urgent: boolean): DrawnFrameWork | null {
    if (this.count >= this.capacity) { this.overflow++; return null; }
    const work = new DrawnFrameWork();
    work.owner = this; work.run = run; work.schedule = schedule; work.since = this.clock();
    this.append(work, urgent); this.count++; this.post(); return work;
  }
  private append(work: DrawnFrameWork, urgent: boolean): void {
    const lane = urgent ? 1 : 0;
    work.urgent = urgent; work.previous = this.tails[lane]; work.next = null;
    if (work.previous !== null) { work.previous.next = work; } else { this.heads[lane] = work; }
    this.tails[lane] = work;
  }
  private unlink(work: DrawnFrameWork): void {
    const lane = work.urgent ? 1 : 0;
    if (work.previous !== null) { work.previous.next = work.next; } else { this.heads[lane] = work.next; }
    if (work.next !== null) { work.next.previous = work.previous; } else { this.tails[lane] = work.previous; }
    work.next = null; work.previous = null;
  }
  priority(work: DrawnFrameWork, urgent: boolean): void {
    if (work.owner !== this || work.urgent === urgent) { return; }
    this.unlink(work); this.append(work, urgent);
  }
  cancel(work: DrawnFrameWork): void {
    if (work.owner !== this) { return; }
    this.remove(work); this.cancelled++;
  }
  private remove(work: DrawnFrameWork): void {
    this.unlink(work); this.count--; work.owner = null; work.run = null; work.schedule = null;
    // Keep the one posted callback even when cancellation empties the queue.
    // Repeated reuse before the next VSync must not allocate N frame callbacks.
    // The callback owns only this queue, never the cancelled row/context.
    if (this.count === 0) { this.urgentStreak = 0; }
  }
  private post(): void {
    if (this.posted || this.draining || this.count === 0) { return; }
    const head = this.heads[1] ?? this.heads[0];
    const schedule = head?.schedule;
    if (schedule === null || schedule === undefined) { return; }
    this.posted = true;
    schedule((): void => {
      if (!this.posted) { return; }
      this.posted = false; this.drain();
    });
  }
  private drain(): void {
    this.draining = true;
    const start = this.clock(), limit = Math.min(this.maxPerFrame, this.count);
    try {
      for (let i = 0; i < limit; i++) {
        // A synchronous job cannot be preempted. The count cap still holds if
        // the millisecond clock moves backwards; this is not a frame deadline.
        if (i > 0 && this.clock() - start >= this.budgetMs) { break; }
        const urgent = this.heads[1] !== null && (this.heads[0] === null || this.urgentStreak < 3);
        const work = urgent ? this.heads[1] : this.heads[0];
        if (work === null) { break; }
        this.urgentStreak = urgent ? this.urgentStreak + 1 : 0;
        const run = work.run;
        this.maxWait = Math.max(this.maxWait, this.clock() - work.since);
        this.remove(work);
        try { run?.(); } catch (error) { this.failed(error as Error); }
        this.completed++;
      }
    } finally { this.draining = false; this.post(); }
  }
  summary(): string {
    return `\nframe activation: pending=${this.count} completed=${this.completed} cancelled=${this.cancelled}` +
      ` overflow=${this.overflow} maxWaitMs=${this.maxWait}`;
  }
}
