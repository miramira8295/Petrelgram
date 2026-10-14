export const BACKDROP_PHASE_MS: number = 4200;
export type PhaseSchedule = (tick: () => void, intervalMs: number) => number;
export type PhaseCancel = (id: number) => void;

function schedulePhase(tick: () => void, intervalMs: number): number {
  return setInterval(tick, intervalMs);
}

function cancelPhase(id: number): void {
  clearInterval(id);
}

// 只负责相位时钟；停止后由组件撤下动态节点，终止已提交给渲染服务的动画。
export class BackdropPhaseClock {
  private timer: number = -1;
  private generation: number = 0;
  private tick: () => void;
  private schedule: PhaseSchedule;
  private cancel: PhaseCancel;

  constructor(tick: () => void, schedule: PhaseSchedule = schedulePhase, cancel: PhaseCancel = cancelPhase) {
    this.tick = tick;
    this.schedule = schedule;
    this.cancel = cancel;
  }

  setRunning(running: boolean): void {
    if (!running) {
      this.generation++;
      if (this.timer !== -1) {
        this.cancel(this.timer);
        this.timer = -1;
      }
      return;
    }
    if (this.timer !== -1) {
      return;
    }
    const generation: number = ++this.generation;
    this.timer = this.schedule((): void => {
      if (generation === this.generation) {
        this.tick();
      }
    }, BACKDROP_PHASE_MS);
  }
}
