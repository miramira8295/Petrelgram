import { AlbumGroup } from './collapseAlbums';
import { hiTraceMeter } from '@kit.PerformanceAnalysisKit';

// Fixed cardinality, no message data or retained samples. Disabled by default;
// disabled calls never access a clock, AppStorage, trace API or observed state.
export enum DrawnStage { Layout, Attach, Media, Background, Foreground, Avatar, TileFrames, BackgroundPaint, ForegroundPaint, AvatarPaint, Activation, RowReuse, RowInput, RowLayoutChanged, PresentationAttach, TileAttributes, CanvasAttributes, VideoAttach, AlbumCanvasBind, AlbumCanvasPaint, RowGeometry, RowPublish, RowTarget, ScrollStop, ScrollStopState, ScrollStopEffects, ScrollStopDecode, ScrollStopFlush, ScrollStopTrim, ScrollStopAnimations, ScrollStopVisible, ScrollStopPlay, ScrollStopCache, ScrollStopSchedule, ScrollStopHistory, VisibleBottom, VisibleRead, VisiblePinned, VisibleTranslation, VisibleMedia, ScrollIndex, ScrollDid, LoadOlder, LoadNewer, GroupsPublish, LazySetRows, ReadMentions, ReadViewed, ReplyResolve }
const STAGE_NAMES: string[] = ['PG/layout', 'PG/attach', 'PG/media', 'PG/background-bind',
  'PG/foreground-bind', 'PG/avatar-bind', 'PG/tile-frames', 'PG/background-paint', 'PG/foreground-paint', 'PG/avatar-paint', 'PG/media-activation',
  'PG/row-reuse', 'PG/row-input', 'PG/row-layout-changed', 'PG/presentation-attach',
  'PG/tile-attributes', 'PG/canvas-attributes', 'PG/video-attach', 'PG/album-canvas-bind', 'PG/album-canvas-paint', 'PG/row-geometry', 'PG/row-publish', 'PG/row-target',
  'PG/scroll-stop', 'PG/scroll-stop/state', 'PG/scroll-stop/effects', 'PG/scroll-stop/decode',
  'PG/scroll-stop/flush', 'PG/scroll-stop/trim', 'PG/scroll-stop/animations', 'PG/scroll-stop/visible',
  'PG/scroll-stop/play', 'PG/scroll-stop/cache', 'PG/scroll-stop/schedule', 'PG/scroll-stop/history', 'PG/visible/bottom', 'PG/visible/read',
  'PG/visible/pinned', 'PG/visible/translation', 'PG/visible/media', 'PG/list/index', 'PG/list/did',
  'PG/list/load-older', 'PG/list/load-newer', 'PG/list/publish', 'PG/list/lazy-set',
  'PG/read/mentions', 'PG/read/viewed', 'PG/reply/resolve'];

// One primary cause per actual invalidate (plan takes precedence over state).
// Framework-triggered drawing is counted separately by the paint stages.
export enum DrawnInvalidation { BackgroundPlan, Shadow, ForegroundPlan, Status, Footer, Press, AvatarPlan, AvatarImage }
const INVALIDATION_NAMES: string[] = ['background/plan', 'background/shadow', 'foreground/plan',
  'foreground/status', 'foreground/footer', 'foreground/press', 'avatar/plan', 'avatar/image'];

export enum DrawnRowChangeSource { List, Presentation }
const CHANGE_SOURCES: string[] = ['list', 'presentation'];
const CHANGE_FIELDS: string[] = ['identity', 'content', 'chrome', 'thumbnail', 'failure', 'transfer', 'video', 'translation', 'members', 'reference'];
const CHANGE_NAMES: string[] = CHANGE_SOURCES.flatMap((source: string): string[] =>
  CHANGE_FIELDS.map((field: string): string => `PG/change/${source}/${field}`));

export class DrawnStageMetrics {
  private enabled: boolean = false;
  private rowChanges: number[] = new Array<number>(CHANGE_NAMES.length).fill(0);
  private changedField(source: DrawnRowChangeSource, field: number): void {
    const index = source * CHANGE_FIELDS.length + field;
    this.rowChanges[index]++;
    this.markRoute(CHANGE_NAMES[index]);
  }
  // Called only at actual snapshot publication. Disabled: O(1), no field reads.
  // Enabled: one pass over media members, no entity parsing or history scan.
  rowChanged(source: DrawnRowChangeSource, before: AlbumGroup, next: AlbumGroup): void {
    if (!this.enabled || before === next) { return; }
    const a = before.head, b = next.head;
    if (a.rowId !== b.rowId || a.id !== b.id || a.contentType !== b.contentType) { this.changedField(source, 0); }
    if (before.key !== next.key) { this.changedField(source, 1); }
    if (before.dateLabel !== next.dateLabel || before.showAvatar !== next.showAvatar ||
      before.showSenderName !== next.showSenderName || before.initialDeferred !== next.initialDeferred) { this.changedField(source, 2); }
    let thumb = a.photoPath !== b.photoPath || a.linkPhotoPath !== b.linkPhotoPath;
    let failure = a.photoFailed !== b.photoFailed || a.videoFailed !== b.videoFailed;
    let members = before.memberIds.length !== next.memberIds.length;
    const count = Math.max(before.memberIds.length, next.memberIds.length);
    for (let i = 0; i < count; i++) {
      thumb = thumb || before.photoPaths[i] !== next.photoPaths[i];
      failure = failure || before.photoFailed[i] !== next.photoFailed[i];
      members = members || before.memberIds[i] !== next.memberIds[i] || before.photoFileIds[i] !== next.photoFileIds[i];
    }
    if (thumb) { this.changedField(source, 3); }
    if (failure) { this.changedField(source, 4); }
    if (a.mediaDownloadActive !== b.mediaDownloadActive || a.linkPhotoDownloadActive !== b.linkPhotoDownloadActive ||
      a.stickerDownloadActive !== b.stickerDownloadActive) { this.changedField(source, 5); }
    if (a.videoPath !== b.videoPath || a.videoFileId !== b.videoFileId) { this.changedField(source, 6); }
    if (a.translatedText !== b.translatedText || a.translatedLang !== b.translatedLang ||
      a.translationHidden !== b.translationHidden) { this.changedField(source, 7); }
    if (members) { this.changedField(source, 8); }
    this.changedField(source, 9); // all reference replacements, not an 'unchanged' verdict
  }
  private traceOutput: boolean = true;
  private calls: number[] = new Array<number>(STAGE_NAMES.length).fill(0);
  private untraced: number[] = new Array<number>(STAGE_NAMES.length).fill(0);
  private skips: number[] = new Array<number>(STAGE_NAMES.length).fill(0);
  private invalidations: number[] = [0, 0, 0, 0, 0, 0, 0, 0];
  invalidated(reason: DrawnInvalidation): void { if (this.enabled) { this.invalidations[reason]++; } }
  isEnabled(): boolean { return this.enabled; }
  setEnabled(enabled: boolean): void { this.enabled = enabled; }
  // Method sampling must not repeatedly sample the instrumentation itself.
  // Counters remain available; a diagnostic owner restores the previous mode.
  setTraceOutput(enabled: boolean): boolean {
    const previous = this.traceOutput; this.traceOutput = enabled; return previous;
  }
  begin(stage: DrawnStage): boolean {
    if (!this.enabled) { return false; }
    this.calls[stage]++;
    if (!this.traceOutput) { this.untraced[stage]++; return false; }
    hiTraceMeter.startSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL, STAGE_NAMES[stage]);
    return true;
  }
  markRoute(name: string): void {
    if (!this.enabled || !this.traceOutput) { return; }
    hiTraceMeter.startSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL, name);
    hiTraceMeter.finishSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL);
  }
  end(started: boolean): void {
    // Pair even if the switch changes while a synchronous callback is running.
    if (started) { hiTraceMeter.finishSyncTrace(hiTraceMeter.HiTraceOutputLevel.COMMERCIAL); }
  }
  skip(stage: DrawnStage): void { if (this.enabled) { this.skips[stage]++; } }
  reset(): void { this.rowChanges.fill(0); this.calls.fill(0); this.untraced.fill(0); this.skips.fill(0); this.invalidations.fill(0); }
  summary(): string {
    let result = '';
    for (let i = 0; i < CHANGE_NAMES.length; i++) {
      if (this.rowChanges[i] !== 0) { result += `[DrawnRowChange] reason=${CHANGE_NAMES[i]} calls=${this.rowChanges[i]}\n`; }
    }
    for (let i = 0; i < STAGE_NAMES.length; i++) {
      if (this.calls[i] !== 0 || this.skips[i] !== 0) {
        result += `[DrawnStage] scope=process_since_log_clear stage=${STAGE_NAMES[i]}` +
          ` calls=${this.calls[i]} skips=${this.skips[i]} untraced=${this.untraced[i]} timing=system_trace\n`;
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
