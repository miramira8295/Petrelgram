import { hiTraceMeter } from '@kit.PerformanceAnalysisKit';

// Fixed cardinality, no message data or retained samples. Disabled by default;
// disabled calls never access a clock, AppStorage, trace API or observed state.
export enum DrawnStage { Layout, Attach, Media, Background, Foreground, Avatar, TileFrames, BackgroundPaint, ForegroundPaint, AvatarPaint, Activation }
const STAGE_NAMES: string[] = ['PG/layout', 'PG/attach', 'PG/media', 'PG/background-bind',
  'PG/foreground-bind', 'PG/avatar-bind', 'PG/tile-frames', 'PG/background-paint', 'PG/foreground-paint', 'PG/avatar-paint', 'PG/media-activation'];

// One primary cause per actual invalidate (plan takes precedence over state).
// Framework-triggered drawing is counted separately by the paint stages.
export enum DrawnInvalidation { BackgroundPlan, Shadow, ForegroundPlan, Status, Footer, Press, AvatarPlan, AvatarImage }
const INVALIDATION_NAMES: string[] = ['background/plan', 'background/shadow', 'foreground/plan',
  'foreground/status', 'foreground/footer', 'foreground/press', 'avatar/plan', 'avatar/image'];

export class DrawnStageMetrics {
  private enabled: boolean = false;
  private calls: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  private skips: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  private invalidations: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  invalidated(reason: DrawnInvalidation): void { if (this.enabled) { this.invalidations[reason]++; } }
  setEnabled(enabled: boolean): void { this.enabled = enabled; }
  begin(stage: DrawnStage): boolean {
    if (!this.enabled) { return false; }
    this.calls[stage]++;
    hiTraceMeter.startSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL, STAGE_NAMES[stage]);
    return true;
  }
  markRoute(name: string): void {
    if (!this.enabled) { return; }
    hiTraceMeter.startSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL, name);
    hiTraceMeter.finishSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL);
  }
  end(started: boolean): void {
    // Pair even if the switch changes while a synchronous callback is running.
    if (started) { hiTraceMeter.finishSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL); }
  }
  skip(stage: DrawnStage): void { if (this.enabled) { this.skips[stage]++; } }
  reset(): void { this.calls.fill(0); this.skips.fill(0); this.invalidations.fill(0); }
  summary(): string {
    let result = '';
    for (let i = 0; i < STAGE_NAMES.length; i++) {
      if (this.calls[i] !== 0 || this.skips[i] !== 0) {
        result += `[DrawnStage] scope=process_since_log_clear stage=${STAGE_NAMES[i]}` +
          ` calls=${this.calls[i]} skips=${this.skips[i]} timing=system_trace\n`;
      }
    }
    for (let i = 0; i < INVALIDATION_NAMES.length; i++) {
      if (this.invalidations[i] !== 0) {
        result += `[DrawnInvalidation] scope=process_since_log_clear reason=${INVALIDATION_NAMES[i]}` +
          ` calls=${this.invalidations[i]}\n`;
      }
    }
    return result;
  }
}
export const drawnStageMetrics: DrawnStageMetrics = new DrawnStageMetrics();
