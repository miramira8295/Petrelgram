import { UIContext } from '@kit.ArkUI';
import { OneShotFrameCallback } from './oneShotFrameCallback';
import { DrawnFrameQueue, DrawnFrameWork } from './drawnFrameQueue';
import { DrawnStage, drawnStageMetrics } from './drawnStageMetrics';
import { logW } from './log';

// Shared by all drawn albums, including simultaneous entering rows. Queue
// nodes own the context only while pending; cancellation unlinks immediately.
export const drawnMediaActivation = new DrawnFrameQueue((): number => Date.now(),
  (error: Error): void => { logW(`DrawnMediaActivation: ${error.message}`); });

export function enqueueDrawnMedia(ui: UIContext, run: () => void, visible: boolean): DrawnFrameWork | null {
  return drawnMediaActivation.enqueue((task: () => void): void => {
    try { ui.postDelayedFrameCallback(new OneShotFrameCallback(task), 1); }
    catch (error) {
      logW(`DrawnMediaActivation: frame unavailable: ${(error as Error).message}`);
      // A destroyed window must not strand work belonging to another live row.
      // Exceptional fallback only; cancelled generations remain no-ops.
      setTimeout(task, 16);
    }
  }, (): void => {
    const traced = drawnStageMetrics.begin(DrawnStage.Activation);
    try { run(); } finally { drawnStageMetrics.end(traced); }
  }, visible);
}
