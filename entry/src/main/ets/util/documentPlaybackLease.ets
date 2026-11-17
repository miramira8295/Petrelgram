import { AnimationSlotPool } from './animationSlotPool';

// Bounded native-player admission, shared across all structured documents.
// Pool wait/cancel/grant are O(1). Scroll closes admission but retains an
// existing surface; the player's existing chat gate pauses it without flashes.
const slots: AnimationSlotPool = new AnimationSlotPool(1);
export class DocumentPlaybackLease {
  private held: boolean = false;
  private waiting: (() => void) | null = null;
  private eligible: boolean = false;
  private suspended: boolean = true;
  private generation: number = 0;
  private changed: (active: boolean) => void;
  constructor(changed: (active: boolean) => void) { this.changed = changed; }
  update(eligible: boolean, suspended: boolean): void {
    this.eligible = eligible; this.suspended = suspended;
    if (!eligible) { this.release(); return; }
    if (suspended) { this.waiting?.(); this.waiting = null; return; }
    if (this.held || this.waiting !== null) { return; }
    if (slots.tryAcquire()) { this.held = true; this.changed(true); return; }
    const generation = this.generation;
    this.waiting = slots.wait((): void => {
      this.waiting = null;
      if (generation !== this.generation || !this.eligible || this.suspended) { slots.release(); return; }
      this.held = true; this.changed(true);
    });
  }
  private release(): void {
    this.generation++; this.waiting?.(); this.waiting = null;
    if (this.held) { this.held = false; this.changed(false); slots.release(); }
  }
  dispose(): void { this.eligible = false; this.release(); }
}
