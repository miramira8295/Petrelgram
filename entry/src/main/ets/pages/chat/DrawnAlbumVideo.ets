import { DrawnMediaPosition } from './DrawnMediaPosition';
import { subscribeThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { DrawnStage, drawnStageMetrics } from '../../util/drawnStageMetrics';
import { DrawnSlotContent } from './DrawnSlotContent';
import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { VideoBubbleSurface } from './VideoBubbleSurface';
import { PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO } from './playSlot';
import { DrawnVideoMetaMemo } from './DrawnVideoMeta';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnVideoDecoration } from './DrawnVideoDecoration';
import { a11yRuntimeState } from '../../util/a11yState';

// Only slots that have hosted video/live content allocate this island.
// Empty/photo reuse keeps the shell but releases sources. Bitmap ownership remains on the row;
// the player/visibility lifecycle is independent of caption parsing and paint.
@ComponentV2
export struct DrawnAlbumVideo {
  // Legacy grid supplies a direct cell; whole-row rendering passes the stable
  // publication channel. Read its @Trace value here, never in the parent row.
  @Param cell: AlbumCellRenderData | undefined = undefined;
  @Param content: DrawnSlotContent | undefined = undefined;
  private get currentCell(): AlbumCellRenderData | undefined {
    // Read synchronously: a late player callback can arrive before Monitor.
    // Computed would still expose its previous-frame cached payload here.
    // An empty staged channel must NOT revive a legacy/previous payload.
    return this.content !== undefined ? this.content.cell : this.cell;
  }
  @Param thumbReady: boolean = false;
  @Param sendState: string = '';
  @Param mediaWidth: number = 0;
  @Param mediaHeight: number = 0;
  private get slotWidth(): number {
    return this.content !== undefined ? this.content.width : this.mediaWidth || this.currentCell?.width || 0;
  }
  private get slotHeight(): number {
    return this.content !== undefined ? this.content.height : this.mediaHeight || this.currentCell?.height || 0;
  }
  private get slotThumbReady(): boolean {
    return this.content !== undefined ? this.content.thumbReady : this.thumbReady;
  }
  private uploading(): boolean { return this.sendState !== '' ? this.sendState === 'sending' : this.currentCell?.uploading === true; }
  @Require @Param actions: MessageBubbleActions;
  private decoration: DrawnVideoDecoration = new DrawnVideoDecoration();
  private metaMemo: DrawnVideoMetaMemo = new DrawnVideoMetaMemo();
  private a11y = a11yRuntimeState;
  private active: boolean = false;
  @Local private posterPath: string = '';
  private posterFileId: number = -1;
  private posterChatId: number = 0;
  private posterMessageId: number = 0;
  private posterGeneration: number = 0;
  private posterUnsubscribe: (() => void) | null = null;

  private releasePoster(): void {
    this.posterGeneration++;
    if (this.posterUnsubscribe !== null) { this.posterUnsubscribe(); this.posterUnsubscribe = null; }
    this.posterFileId = -1; this.posterChatId = 0; this.posterMessageId = 0;
    if (this.posterPath !== '') { this.posterPath = ''; }
  }
  private syncPoster(c: AlbumCellRenderData | undefined): void {
    if (!this.active || c === undefined) { this.releasePoster(); return; }
    const fileId = c.thumbFileId;
    if (this.posterFileId !== fileId || this.posterChatId !== c.chatId || this.posterMessageId !== c.messageId) {
      this.releasePoster();
      this.posterFileId = fileId; this.posterChatId = c.chatId; this.posterMessageId = c.messageId;
      const generation = this.posterGeneration;
      if (fileId > 0) {
        this.posterUnsubscribe = subscribeThumbPath(fileId, (path: string): void => {
          const current = this.currentCell;
          // Check current input synchronously, before nullable Monitor delivery.
          // A/B/A callbacks and callbacks after recycle must not restore old posters.
          if (!this.active || generation !== this.posterGeneration || current?.chatId !== c.chatId ||
            current?.messageId !== c.messageId || current?.thumbFileId !== fileId) { return; }
          if (this.posterPath !== path) { this.posterPath = path; }
        });
      }
    }
    const path = (fileId > 0 ? thumbPathFor(fileId) : '') || c.thumbPath;
    if (this.posterPath !== path) { this.posterPath = path; }
  }
  private attachedChat: number = 0;
  private attachedId: number = 0;
  private attachedIndex: number = -1;
  private mediaPosition: DrawnMediaPosition = new DrawnMediaPosition();
  private generation: number = 0;
  private bindingIdentity: string = '';
  private generationCell: AlbumCellRenderData | undefined = undefined;
  private generationUploading: boolean = false;
  private generationValid: boolean = false;

  private release(): void {
    if (this.attachedId !== 0) { this.actions.onMediaGone(this.attachedId, this.attachedIndex); }
    this.attachedChat = 0; this.attachedId = 0; this.attachedIndex = -1;
  }
  private attach(): void {
    const c = this.currentCell;
    this.syncPoster(c);
    // Empty staged channels and duplicate monitor/lifecycle calls are common
    // during recursive reuse. Invalidate old callbacks before taking any hit.
    this.observationGeneration(c);
    if (!this.active || c === undefined || !c.isVideo || this.uploading()) { this.release(); return; }
    if (this.attachedChat === c.chatId && this.attachedId === c.messageId && this.attachedIndex === c.idx) {
      drawnStageMetrics.skip(DrawnStage.VideoAttach); return;
    }
    const traced = drawnStageMetrics.begin(DrawnStage.VideoAttach);
    try {
      this.release(); this.attachedChat = c.chatId; this.attachedId = c.messageId; this.attachedIndex = c.idx;
    } finally { drawnStageMetrics.end(traced); }
  }
  // The channel is optional for legacy cells and may be empty while staged.
  // Monitor a valid computed root instead of a nullable nested path. Callback
  // guards still read currentCell synchronously, before Monitor delivery.
  @Computed
  private get observedCell(): AlbumCellRenderData | undefined { return this.currentCell; }
  @Monitor('observedCell', 'sendState')
  private changed(): void { this.attach(); }
  aboutToAppear(): void { this.active = true; this.attach(); }
  aboutToReuse(): void { this.active = true; this.attach(); }
  aboutToRecycle(): void {
    this.active = false; this.generation++; this.bindingIdentity = '';
    this.generationCell = undefined; this.generationValid = false; this.releasePoster(); this.release();
  }
  aboutToDisappear(): void { this.aboutToRecycle(); }

  private observationGeneration(c: AlbumCellRenderData | undefined): number {
    const uploading = this.uploading();
    // AlbumCellRenderData is immutable. Repeated callbacks for its current
    // snapshot need neither string construction nor a new retained object.
    if (this.generationValid && this.generationCell === c && this.generationUploading === uploading) {
      return this.generation;
    }
    const key = c === undefined ? '' : `${c.chatId}:${c.messageId}:${c.idx}:${c.width}:${c.height}:` +
      `${c.videoFileId}:${c.inlineFileId}:${c.isPlaySlot}:${uploading}`;
    if (key !== this.bindingIdentity) { this.bindingIdentity = key; this.generation++; }
    this.generationCell = c; this.generationUploading = uploading; this.generationValid = true;
    return this.generation;
  }
  private accepts(c: AlbumCellRenderData | undefined, generation: number): boolean {
    const now = this.currentCell;
    return this.active && !this.uploading() && generation === this.generation && c !== undefined && now !== undefined && now.isVideo &&
      now.chatId === c.chatId && now.messageId === c.messageId && now.idx === c.idx &&
      now.width === c.width && now.height === c.height && now.videoFileId === c.videoFileId &&
      now.inlineFileId === c.inlineFileId && now.isPlaySlot === c.isPlaySlot;
  }
  private ratioCallback(c: AlbumCellRenderData | undefined): (visible: boolean, ratio: number) => void {
    const generation = this.observationGeneration(c);
    return (_visible: boolean, ratio: number): void => {
      if (!this.accepts(c, generation) || c === undefined) { return; }
      if (ratio <= 0) { this.actions.onMediaGone(c.messageId, c.idx); }
      else {
        const center = this.mediaPosition.center(this.getUIContext());
        if (center !== undefined) { this.actions.onMediaRatio(c.messageId, c.idx, ratio, center); }
      }
    };
  }
  private positionCallback(c: AlbumCellRenderData | undefined): (ms: number) => void {
    const generation = this.observationGeneration(c);
    return (ms: number): void => {
      if (this.accepts(c, generation) && c !== undefined && this.currentCell?.isPlaySlot) {
        this.actions.onPlaySlotPositionChanged(c.messageId, c.idx, ms);
      }
    };
  }
  private endedCallback(c: AlbumCellRenderData | undefined): () => void {
    const generation = this.observationGeneration(c);
    return (): void => {
      if (this.accepts(c, generation) && c !== undefined && this.currentCell?.isPlaySlot) { this.actions.onPlaySlotEnded(c.messageId, c.idx); }
    };
  }
  // Keep observedCell as the nullable Monitor anchor. Label rendering reads
  // currentCell/langEpoch directly; the ordinary numeric memo survives reuse.
  private get meta(): string {
    const c = this.currentCell;
    const epoch = chatEnv.langEpoch;
    if (c === undefined || epoch < 0) { return ''; }
    return this.metaMemo.prepare(c.videoFileSize, c.videoDuration, c.width >= 112, epoch);
  }

  build() {
    // Keep the physical island and its fixed-size shell during staged reuse.
    // Undefined input means no old decoration/player/visibility registration.
    Stack() {
      if (!this.uploading() && this.currentCell?.isPlaySlot && (this.currentCell?.videoFileId ?? 0) !== 0) {
        VideoBubbleSurface({ fileId: this.currentCell?.inlineFileId || this.currentCell?.videoFileId || 0,
          fileSize: this.currentCell?.inlineFileId ? this.currentCell?.inlineFileSize ?? 0 : this.currentCell?.videoFileSize ?? 0,
          mimeType: this.currentCell?.videoMimeType ?? '', posterPath: this.posterPath,
          muted: this.currentCell?.autoplayMuted ?? false, startPositionMs: this.currentCell?.playSlotStartMs ?? 0,
          onPositionChanged: this.positionCallback(this.currentCell), onEnded: this.endedCallback(this.currentCell) })
          .width(this.currentCell?.width ?? 0).height(this.currentCell?.height ?? 0).borderRadius(6).clip(true)
          .hitTestBehavior(HitTestMode.None);
      }
      if (this.currentCell !== undefined && this.a11y.active && !this.uploading() && !this.currentCell?.isLive && this.slotThumbReady &&
        !(this.currentCell?.isPlaySlot && (this.currentCell?.videoFileId ?? 0) !== 0)) {
        Stack() {
          Circle({ width: Math.min(40, Math.min(this.currentCell?.width ?? 0, this.currentCell?.height ?? 0) * .46),
            height: Math.min(40, Math.min(this.currentCell?.width ?? 0, this.currentCell?.height ?? 0) * .46) })
            .fill('#73000000').stroke('#24FFFFFF').strokeWidth(1);
          SymbolGlyph($r('sys.symbol.play_fill')).fontSize(Math.min(40,
            Math.min(this.currentCell?.width ?? 0, this.currentCell?.height ?? 0) * .46) * .42).fontColor([Color.White]).margin({ left: 2 });
        }
      }
      if (this.currentCell?.isLive) {
        Row({ space: 3 }) {
          SymbolGlyph($r('sys.symbol.livephoto')).fontSize(12).fontColor([Color.White]);
          Text($r('app.string.cp_live_photo')).fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
        }.height(18).padding({ left: 5, right: 6 }).backgroundColor('#66000000').borderRadius(9).position({ x: 6, y: 6 });
      }
      if (this.a11y.active && this.meta !== '') {
        Text(this.meta).fontSize(10.5).fontColor(Color.White).backgroundColor('#66000000').borderRadius(6)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: Math.max(24, (this.currentCell?.width ?? 0) - 12) })
          .position({ x: 6, y: Math.max(6, (this.currentCell?.height ?? 0) - 23) });
      }
    }.width(this.slotWidth).height(this.slotHeight).hitTestBehavior(HitTestMode.None)
    .drawModifier(this.decoration.bind(this.getUIContext(), this.slotWidth, this.slotHeight, this.a11y.active ? '' : this.meta,
      this.currentCell !== undefined && !this.a11y.active && !this.uploading() && !this.currentCell?.isLive && this.slotThumbReady &&
        !(this.currentCell?.isPlaySlot && (this.currentCell?.videoFileId ?? 0) !== 0),
      `${chatEnv.langEpoch}:${textMeasureEnvironment.epoch}`))
    .onVisibleAreaApproximateChange({ ratios: [0, PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, .9], expectedUpdateInterval: 200 },
      this.ratioCallback(this.currentCell)).id(this.mediaPosition.nodeId);
  }
}
