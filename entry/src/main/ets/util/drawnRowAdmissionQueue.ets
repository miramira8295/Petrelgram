// One heavy row publication per actual FrameCallback timestamp, shared by all
// albums. Intrusive FIFO: O(1) enqueue/cancel/take, no tombstones or history scans.
export class DrawnRowWork {
  previous: DrawnRowWork | null = null;
  next: DrawnRowWork | null = null;
  owner: DrawnRowAdmissionQueue | null = null;
  schedule: ((task: (frame: number) => void) => void) | null = null;
  run: ((waitMs: number, visible: boolean) => void) | null = null;
  since: number = 0;
  urgent: boolean = false;
}

export class DrawnRowAdmissionQueue {
  private heads: Array<DrawnRowWork | null> = [null, null];
  private tails: Array<DrawnRowWork | null> = [null, null];
  private urgentStreak: number = 0;
  private count: number = 0;
  private posted: boolean = false;
  private draining: boolean = false;
  private frame: number = -1;
  private token: number = 0;
  private completed: number = 0;
  private cancelled: number = 0;
  private overflow: number = 0;
  private duplicateFrames: number = 0;
  private maxWait: number = 0;
  private clock: () => number;
  private failed: (error: Error) => void;
  private capacity: number;
  constructor(clock: () => number, failed: (error: Error) => void, capacity: number = 128) {
    this.clock = clock; this.failed = failed; this.capacity = capacity;
  }

  enqueue(schedule: (task: (frame: number) => void) => void, run: (waitMs: number, visible: boolean) => void, urgent: boolean = false): DrawnRowWork | null {
    if (this.count >= this.capacity) { this.overflow++; return null; }
    const work = new DrawnRowWork();
    work.owner = this; work.schedule = schedule; work.run = run; work.since = this.clock();
    this.append(work, urgent); this.count++; this.post(); return work;
  }
  cancel(work: DrawnRowWork): void {
    if (work.owner !== this) { return; }
    this.remove(work); this.cancelled++;
  }
  private append(work: DrawnRowWork, urgent: boolean): void {
    const lane = urgent ? 1 : 0;
    work.urgent = urgent; work.previous = this.tails[lane]; work.next = null;
    if (work.previous !== null) { work.previous.next = work; } else { this.heads[lane] = work; }
    this.tails[lane] = work;
  }
  private unlink(work: DrawnRowWork): void {
    const lane = work.urgent ? 1 : 0;
    if (work.previous !== null) { work.previous.next = work.next; } else { this.heads[lane] = work.next; }
    if (work.next !== null) { work.next.previous = work.previous; } else { this.tails[lane] = work.previous; }
    work.previous = null; work.next = null;
  }
  priority(work: DrawnRowWork, urgent: boolean): void {
    if (work.owner !== this || work.urgent === urgent) { return; }
    this.unlink(work); this.append(work, urgent);
  }
  private remove(work: DrawnRowWork): void {
    this.unlink(work); work.owner = null; work.run = null; work.schedule = null;
    this.count--;
    if (this.count === 0) { this.urgentStreak = 0; }
  }
  private post(): void {
    if (this.posted || this.draining || this.count === 0) { return; }
    const head = this.heads[1] ?? this.heads[0];
    const schedule = head?.schedule;
    if (schedule === null || schedule === undefined) { return; }
    this.posted = true;
    const token = ++this.token;
    schedule((frame: number): void => {
      if (!this.posted || token !== this.token) { return; }
      this.posted = false;
      // Cancellation followed by re-enqueue must not grant a second row in the
      // same VSync. A stale/duplicate native callback never drains new work.
      if (frame >= 0 && frame <= this.frame) { this.duplicateFrames++; this.post(); return; }
      if (this.count === 0) { return; }
      if (frame >= 0) { this.frame = frame; }
      this.draining = true;
      try {
        const urgent = this.heads[1] !== null && (this.heads[0] === null || this.urgentStreak < 3);
        const work = urgent ? this.heads[1] : this.heads[0];
        if (work === null) { return; }
        this.urgentStreak = urgent ? this.urgentStreak + 1 : 0;
        const run = work.run;
        const waitMs = Math.max(0, this.clock() - work.since);
        this.maxWait = Math.max(this.maxWait, waitMs);
        this.remove(work);
        try { run?.(waitMs, work.urgent); } catch (error) { this.failed(error as Error); }
        this.completed++;
      } finally { this.draining = false; this.post(); }
    });
  }
  summary(): string {
    return `\nrow admission: pending=${this.count} published=${this.completed} cancelled=${this.cancelled}` +
      ` overflow=${this.overflow} duplicateFrames=${this.duplicateFrames} maxWaitMs=${this.maxWait}`;
  }
}
