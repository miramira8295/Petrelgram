import { AlbumCellRenderData } from '../../util/albumCellRenderData';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { VideoBubbleSurface } from './VideoBubbleSurface';
import { PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO } from './playSlot';
import { formatFileSize } from '../../util/formatFileSize';
import { formatMediaDuration } from '../../util/mediaDuration';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnVideoDecoration } from './DrawnVideoDecoration';
import { a11yRuntimeState } from '../../util/a11yState';

// Only video cells allocate this island. Bitmap ownership remains on the row;
// the player/visibility lifecycle is independent of caption parsing and paint.
@ComponentV2
export struct DrawnAlbumVideo {
  @Param cell: AlbumCellRenderData | undefined = undefined;
  @Param thumbReady: boolean = false;
  @Param sendState: string = '';
  private uploading(): boolean { return this.sendState !== '' ? this.sendState === 'sending' : this.cell?.uploading === true; }
  @Require @Param actions: MessageBubbleActions;
  private decoration: DrawnVideoDecoration = new DrawnVideoDecoration();
  private a11y = a11yRuntimeState;
  private active: boolean = false;
  private attachedChat: number = 0;
  private attachedId: number = 0;
  private attachedIndex: number = -1;
  private centerY: number = 0;
  private generation: number = 0;
  private bindingIdentity: string = '';

  private release(): void {
    if (this.attachedId !== 0) { this.actions.onMediaGone(this.attachedId, this.attachedIndex); }
    this.attachedChat = 0; this.attachedId = 0; this.attachedIndex = -1; this.centerY = 0;
  }
  private attach(): void {
    const c = this.cell;
    this.observationGeneration(c);
    if (!this.active || c === undefined || !c.isVideo || this.uploading()) { this.release(); return; }
    if (this.attachedChat !== c.chatId || this.attachedId !== c.messageId || this.attachedIndex !== c.idx) {
      this.release(); this.attachedChat = c.chatId; this.attachedId = c.messageId; this.attachedIndex = c.idx;
    }
  }
  @Monitor('cell', 'sendState')
  private changed(): void { this.attach(); }
  aboutToAppear(): void { this.active = true; this.attach(); }
  aboutToReuse(): void { this.active = true; this.attach(); }
  aboutToRecycle(): void { this.active = false; this.generation++; this.bindingIdentity = ''; this.release(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }

  private observationGeneration(c: AlbumCellRenderData | undefined): number {
    const key = c === undefined ? '' : `${c.chatId}:${c.messageId}:${c.idx}:${c.width}:${c.height}:` +
      `${c.videoFileId}:${c.inlineFileId}:${c.isPlaySlot}:${this.uploading()}`;
    if (key !== this.bindingIdentity) { this.bindingIdentity = key; this.generation++; }
    return this.generation;
  }
  private accepts(c: AlbumCellRenderData | undefined, generation: number): boolean {
    const now = this.cell;
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
      else { this.actions.onMediaRatio(c.messageId, c.idx, ratio, this.centerY); }
    };
  }
  private areaCallback(c: AlbumCellRenderData | undefined): (old: Area, area: Area) => void {
    const generation = this.observationGeneration(c);
    return (_old: Area, area: Area): void => {
      if (this.accepts(c, generation)) { this.centerY = Number(area.globalPosition.y) + Number(area.height) / 2; }
    };
  }
  private positionCallback(c: AlbumCellRenderData | undefined): (ms: number) => void {
    const generation = this.observationGeneration(c);
    return (ms: number): void => {
      if (this.accepts(c, generation) && c !== undefined && this.cell?.isPlaySlot) {
        this.actions.onPlaySlotPositionChanged(c.messageId, c.idx, ms);
      }
    };
  }
  private endedCallback(c: AlbumCellRenderData | undefined): () => void {
    const generation = this.observationGeneration(c);
    return (): void => {
      if (this.accepts(c, generation) && c !== undefined && this.cell?.isPlaySlot) { this.actions.onPlaySlotEnded(c.messageId, c.idx); }
    };
  }
  @Computed
  private get meta(): string {
    const c = this.cell;
    const epoch = chatEnv.langEpoch;
    if (c === undefined || epoch < 0) { return ''; }
    const size = c.videoFileSize > 0 ? formatFileSize(c.videoFileSize) : '';
    const duration = c.videoDuration > 0 ? formatMediaDuration(c.videoDuration) : '';
    return duration !== '' && size !== '' && c.width >= 112 ? `${duration} · ${size}` : size || duration;
  }

  build() {
    if (this.cell !== undefined) {
      Stack() {
        if (!this.uploading() && this.cell?.isPlaySlot && (this.cell?.videoFileId ?? 0) !== 0) {
          VideoBubbleSurface({ fileId: this.cell?.inlineFileId || this.cell?.videoFileId || 0,
            fileSize: this.cell?.inlineFileId ? this.cell?.inlineFileSize ?? 0 : this.cell?.videoFileSize ?? 0,
            mimeType: this.cell?.videoMimeType ?? '', posterPath: this.cell?.thumbPath ?? '',
            muted: this.cell?.autoplayMuted ?? false, startPositionMs: this.cell?.playSlotStartMs ?? 0,
            onPositionChanged: this.positionCallback(this.cell), onEnded: this.endedCallback(this.cell) })
            .width(this.cell?.width ?? 0).height(this.cell?.height ?? 0).borderRadius(6).clip(true)
            .hitTestBehavior(HitTestMode.None);
        }
        if (this.a11y.active && !this.uploading() && !this.cell?.isLive && this.thumbReady &&
          !(this.cell?.isPlaySlot && (this.cell?.videoFileId ?? 0) !== 0)) {
          Stack() {
            Circle({ width: Math.min(40, Math.min(this.cell?.width ?? 0, this.cell?.height ?? 0) * .46),
              height: Math.min(40, Math.min(this.cell?.width ?? 0, this.cell?.height ?? 0) * .46) })
              .fill('#73000000').stroke('#24FFFFFF').strokeWidth(1);
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(Math.min(40,
              Math.min(this.cell?.width ?? 0, this.cell?.height ?? 0) * .46) * .42).fontColor([Color.White]).margin({ left: 2 });
          }
        }
        if (this.cell?.isLive) {
          Row({ space: 3 }) {
            SymbolGlyph($r('sys.symbol.livephoto')).fontSize(12).fontColor([Color.White]);
            Text($r('app.string.cp_live_photo')).fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }.height(18).padding({ left: 5, right: 6 }).backgroundColor('#66000000').borderRadius(9).position({ x: 6, y: 6 });
        }
        if (this.a11y.active && this.meta !== '') {
          Text(this.meta).fontSize(10.5).fontColor(Color.White).backgroundColor('#66000000').borderRadius(6)
            .padding({ left: 5, right: 5, top: 1, bottom: 1 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: Math.max(24, (this.cell?.width ?? 0) - 12) })
            .position({ x: 6, y: Math.max(6, (this.cell?.height ?? 0) - 23) });
        }
      }.width(this.cell?.width ?? 0).height(this.cell?.height ?? 0).hitTestBehavior(HitTestMode.None)
      .drawModifier(this.decoration.bind(this.getUIContext(), this.cell?.width ?? 0, this.cell?.height ?? 0, this.a11y.active ? '' : this.meta,
        !this.a11y.active && !this.uploading() && !this.cell?.isLive && this.thumbReady &&
          !(this.cell?.isPlaySlot && (this.cell?.videoFileId ?? 0) !== 0),
        `${chatEnv.langEpoch}:${textMeasureEnvironment.epoch}`))
      .onVisibleAreaApproximateChange({ ratios: [0, PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, .9], expectedUpdateInterval: 200 },
        this.ratioCallback(this.cell)).onAreaChange(this.areaCallback(this.cell));
    }
  }
}
