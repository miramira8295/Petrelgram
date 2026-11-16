import { FrameCallback, UIContext } from '@kit.ArkUI';
import { DrawnRowAdmissionQueue, DrawnRowWork } from './drawnRowAdmissionQueue';
import { DrawnStage, drawnStageMetrics } from './drawnStageMetrics';
import { logW } from './log';

class DrawnRowFrameCallback extends FrameCallback {
  private task: (frame: number) => void;
  constructor(task: (frame: number) => void) { super(); this.task = task; }
  onFrame(frameTimeInNano: number): void { this.task(frameTimeInNano); }
}
export const drawnRowAdmission = new DrawnRowAdmissionQueue((): number => Date.now(),
  (error: Error): void => { logW(`DrawnRowAdmission: ${error.message}`); });

export function enqueueDrawnRow(ui: UIContext, run: () => void, visible: boolean): DrawnRowWork | null {
  return drawnRowAdmission.enqueue((task: (frame: number) => void): void => {
    try { ui.postDelayedFrameCallback(new DrawnRowFrameCallback(task), 1); }
    catch (error) {
      logW(`DrawnRowAdmission: frame unavailable: ${(error as Error).message}`);
      // Exceptional window failure only: do not invent a VSync timestamp or
      // strand other owners. The trace distinguishes this from frame admission.
      setTimeout((): void => {
        drawnStageMetrics.markRoute('PG/row-admit-no-vsync'); task(-1);
      }, 16);
    }
  }, (waitMs: number, isVisible: boolean): void => {
    const traced = drawnStageMetrics.begin(DrawnStage.RowPublish);
    try {
      drawnStageMetrics.markRoute(isVisible ? 'PG/row-publish-visible' : 'PG/row-publish-predict');
      drawnStageMetrics.markRoute(waitMs <= 8 ? 'PG/row-wait-0-8ms' : waitMs <= 16 ? 'PG/row-wait-9-16ms'
        : waitMs <= 33 ? 'PG/row-wait-17-33ms' : waitMs <= 66 ? 'PG/row-wait-34-66ms' : 'PG/row-wait-67plus');
      run();
    } finally { drawnStageMetrics.end(traced); }
  }, visible);
}
