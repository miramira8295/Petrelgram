import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { DrawnSlotActivation } from './DrawnSlotActivation';

// The video island does not render progress rings, failure/retry or selection.
// Those remain on the live tile channels. All other fields stay conservative.
// O(1), no copy: retain the published immutable input when only these change.
export function sameDrawnVideoContent(a: AlbumCellRenderData | undefined, b: AlbumCellRenderData): boolean {
  return a !== undefined && (a === b || (a.idx === b.idx && a.width === b.width && a.height === b.height &&
    a.chatId === b.chatId && a.messageId === b.messageId && a.thumbPath === b.thumbPath &&
    a.thumbFileId === b.thumbFileId && a.mini === b.mini && a.isVideo === b.isVideo && a.isLive === b.isLive &&
    a.videoFileId === b.videoFileId && a.videoFileSize === b.videoFileSize && a.videoDuration === b.videoDuration &&
    a.videoMimeType === b.videoMimeType && a.inlineFileId === b.inlineFileId && a.inlineFileSize === b.inlineFileSize &&
    a.uploading === b.uploading && a.isPlaySlot === b.isPlaySlot && a.autoplayMuted === b.autoplayMuted &&
    a.playSlotStartMs === b.playSlotStartMs));
}

// A physical slot owns its publication channel. Geometry/bitmap binding is
// immediate; only the video/live decoration and visibility input is staged.
// Never expose the previous message while a replacement is waiting.
@ObservedV2
export class DrawnSlotContent {
  @Trace cell: AlbumCellRenderData | undefined = undefined;
  // Latch once per physical slot, after its first admitted video/live payload.
  // Photo reuse clears cell and releases playback, but keeps the cheap island.
  @Trace hostReady: boolean = false;
  @Trace width: number = 0;
  @Trace height: number = 0;
  @Trace thumbReady: boolean = false;

  // Physical-slot presentation, independent of staged message publication.
  // Equal updates do not invalidate the video island; no snapshot allocation.
  setGeometry(width: number, height: number): void {
    if (this.width !== width) { this.width = width; }
    if (this.height !== height) { this.height = height; }
  }
  setThumbReady(ready: boolean): void {
    if (this.thumbReady !== ready) { this.thumbReady = ready; }
  }
  private target: AlbumCellRenderData | undefined = undefined;
  private pending: boolean = false;
  private active: boolean = false;
  private staged: boolean = false;
  private activation: DrawnSlotActivation;
  private publish = (): void => {
    if (!this.active || !this.pending) { return; }
    this.pending = false; this.cell = this.target;
    if (this.target !== undefined && !this.hostReady) { this.hostReady = true; }
  };
  constructor(activation: DrawnSlotActivation) { this.activation = activation; }

  bind(next: AlbumCellRenderData, staged: boolean): void {
    if (this.active && sameDrawnVideoContent(this.target, next) && this.staged === staged) { return; }
    const previous = this.target;
    const changed = !this.active || previous?.chatId !== next.chatId || previous?.messageId !== next.messageId;
    this.active = true; this.staged = staged; this.target = next.isVideo || next.isLive ? next : undefined;
    const defer = this.target !== undefined && staged && !next.isPlaySlot && !next.uploading && (changed || this.pending);
    if (defer) {
      this.pending = true;
      this.cell = undefined;
      this.activation.scheduleContent(this.publish);
    } else {
      this.pending = false;
      this.activation.scheduleContent(null);
      this.cell = this.target;
      if (this.target !== undefined && !this.hostReady) { this.hostReady = true; }
    }
  }
  recycle(): void {
    this.active = false; this.pending = false; this.target = undefined;
    this.activation.scheduleContent(null);
    // The parent freezes on recycle. Clear the old payload before its next
    // recursive V2 reset, rather than letting a child restart an old player.
    this.cell = undefined;
    this.setThumbReady(false);
  }
}
