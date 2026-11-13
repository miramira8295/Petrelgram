import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { DrawnSlotActivation } from './DrawnSlotActivation';

// A physical slot owns its publication channel. Geometry/bitmap binding is
// immediate; only the video/live decoration and visibility input is staged.
// Never expose the previous message while a replacement is waiting.
@ObservedV2
export class DrawnSlotContent {
  @Trace cell: AlbumCellRenderData | undefined = undefined;
  private target: AlbumCellRenderData | undefined = undefined;
  private pending: boolean = false;
  private active: boolean = false;
  private staged: boolean = false;
  private activation: DrawnSlotActivation;
  private publish = (): void => {
    if (!this.active || !this.pending) { return; }
    this.pending = false; this.cell = this.target;
  };
  constructor(activation: DrawnSlotActivation) { this.activation = activation; }

  bind(next: AlbumCellRenderData, staged: boolean): void {
    if (this.active && this.target === next && this.staged === staged) { return; }
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
    }
  }
  recycle(): void {
    this.active = false; this.pending = false; this.target = undefined;
    this.activation.scheduleContent(null);
    // The parent freezes on recycle. Clear the old payload before its next
    // recursive V2 reset, rather than letting a child restart an old player.
    this.cell = undefined;
  }
}
