export type ProgressSchedule = (tick: () => void, ms: number) => number;
export type ProgressCancel = (id: number) => void;

// Hidden controls still publish resume/quality-switch positions, at 1 Hz.
// Paused players rely on explicit seek/completion updates, with no idle timer.
export class VideoProgressClock {
  private timer: number = -1;
  private intervalMs: number = 0;
  private generation: number = 0;
  private tick: () => void;
  private schedule: ProgressSchedule;
  private cancel: ProgressCancel;

  constructor(tick: () => void,
    schedule: ProgressSchedule = (callback: () => void, ms: number): number => setInterval(callback, ms),
    cancel: ProgressCancel = (id: number): void => { clearInterval(id); }) {
    this.tick = tick;
    this.schedule = schedule;
    this.cancel = cancel;
  }

  sync(running: boolean, controlsVisible: boolean): void {
    const ms: number = running ? (controlsVisible ? 350 : 1000) : 0;
    if (ms === this.intervalMs) { return; }
    this.stop();
    if (ms === 0) { return; }
    this.intervalMs = ms;
    const generation: number = this.generation;
    this.timer = this.schedule((): void => {
      if (generation === this.generation) { this.tick(); }
    }, ms);
  }

  stop(): void {
    this.generation++;
    if (this.timer !== -1) {
      this.cancel(this.timer);
      this.timer = -1;
    }
    this.intervalMs = 0;
  }
}
