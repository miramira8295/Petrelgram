// 长按快退使用离散跳转；目标独立于原生进度，防止迟到的进度把下一跳推回去。
export const HOLD_REWIND_INTERVAL_MS: number = 400;
export const HOLD_REWIND_STEP_MS: number = 2000;
export const HOLD_REWIND_TIMEOUT_MS: number = 5000;

export class HoldRewindState {
  active: boolean = false;
  targetMs: number = 0;
  private resumePlaying: boolean = false;
  private nextAt: number = 0;
  private pendingSince: number = -1;

  start(positionMs: number, playing: boolean): void {
    if (this.active) {
      return;
    }
    this.active = true;
    this.targetMs = Math.max(0, Math.floor(positionMs));
    this.resumePlaying = playing;
    this.nextAt = 0;
    // 上一次手势/普通 seek 可能还没完成，不能在这里清掉 pending。
  }

  seekStarted(now: number): void {
    this.pendingSince = now;
  }

  seekCompleted(): void {
    this.pendingSince = -1;
  }

  timedOut(now: number): boolean {
    return this.active && this.pendingSince >= 0 && now - this.pendingSince >= HOLD_REWIND_TIMEOUT_MS;
  }

  // -1 表示本轮无需发 seek；慢跳转不补发「欠下的」步数。
  nextTarget(now: number): number {
    if (!this.active || this.pendingSince >= 0 || now < this.nextAt || this.targetMs <= 0) {
      return -1;
    }
    this.targetMs = Math.max(0, this.targetMs - HOLD_REWIND_STEP_MS);
    this.nextAt = now + HOLD_REWIND_INTERVAL_MS;
    this.seekStarted(now);
    return this.targetMs;
  }

  stop(allowResume: boolean): boolean {
    const resume: boolean = this.active && this.resumePlaying && allowResume;
    this.active = false;
    this.resumePlaying = false;
    return resume;
  }

  reset(): void {
    this.stop(false);
    this.seekCompleted();
    this.targetMs = 0;
    this.nextAt = 0;
  }
}
