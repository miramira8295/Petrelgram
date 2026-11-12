import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { drawnAnimationPlaying, drawnAnimationDownloadExpected } from '../../util/drawnAnimationPolicy';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { DrawnImageSlot } from './DrawnMediaController';
import { DrawnSingleInlineFile } from '../../util/drawnSingleInlineFile';
import { VideoBubbleSurface } from './VideoBubbleSurface';
import { PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, slotKey } from './playSlot';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { publishThumbPath, thumbPathFor } from '../../util/mediaThumbChannel';
import { posterFor, requestPoster, subscribePoster } from '../../util/videoPosterStore';
import { formatFileSize } from '../../util/formatFileSize';
import { formatMediaDuration } from '../../util/mediaDuration';
import { isLivePhotoVideo } from '../../util/livePhoto';
import { chatEnv } from '../../util/chatEnvMirror';
import { str } from '../../util/strings';

// Only videos allocate this component. Progress, poster generation, visibility
// and native playback never enter body parsing or the row layout cache.
@ComponentV2
export struct DrawnSingleMediaVideo {
  @Require @Param msg: MessageEntry;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param slot: DrawnImageSlot | undefined = undefined;
  @Param mediaWidth: number = 0;
  @Param mediaHeight: number = 0;
  @Param thumbReady: boolean = false;
  @Param sendState: string = '';
  @Param reportAccessibility: boolean = false;
  @Event onLabelChanged: (label: string) => void = (_label: string): void => {};
  @Local private mediaVisible: boolean = true;
  private requestedDownload: boolean = false;
  private env = chatEnv;
  @Local private progress: number = 0;
  @Local private poster: string = '';
  private files: DrawnSingleInlineFile = new DrawnSingleInlineFile();
  private active: boolean = false;
  private binding: string = '';
  private generation: number = 0;
  private observationKey: string = '';
  private observationEpoch: number = 0;
  private candidateId: number = 0;
  private centerY: number = 0;
  private boundSlot: DrawnImageSlot | undefined = undefined;
  private unsubProgress: (() => void) | null = null;
  private unsubPoster: (() => void) | null = null;

  private inputKey(): string {
    const m = this.msg;
    return `${this.data.chatId}:${m.rowId}:${m.id}:${m.videoFileId}:${m.photoFileId}:${m.videoPath}:${m.isAnimation}`;
  }
  private accepts(key: string, generation: number): boolean {
    return this.active && this.generation === generation && this.binding === key && this.inputKey() === key;
  }
  private setPoster(path: string): void {
    this.poster = path;
    if (path !== '') {
      if (this.msg.photoFileId > 0) { publishThumbPath(this.msg.photoFileId, path); }
      this.slot?.updateLocalPath(path);
    }
  }
  private attach(): void {
    if (!this.active) { return; }
    this.observationGeneration();
    const key = this.inputKey();
    if (this.binding === key) {
      if (this.boundSlot !== this.slot) { this.boundSlot = this.slot; this.slot?.updateLocalPath(this.poster); }
      this.progress = progressForOr(this.msg.videoFileId, this.msg.videoProgress);
      this.syncCandidate(); this.requestDownload();
      return;
    }
    this.detach(); this.binding = key; this.boundSlot = this.slot;
    const generation = this.generation;
    this.syncCandidate();
    this.mediaVisible = true; this.requestedDownload = false;
    this.progress = progressForOr(this.msg.videoFileId, this.msg.videoProgress);
    if (this.msg.videoFileId > 0) {
      this.unsubProgress = subscribeProgress(this.msg.videoFileId, (value: number): void => {
        if (this.accepts(key, generation) && this.progress !== value) { this.progress = value; }
      });
    }
    const path = this.msg.isAnimation ? '' : this.msg.videoPath;
    this.setPoster(path !== '' ? posterFor(path) : '');
    if (path !== '') {
      this.unsubPoster = subscribePoster(path, (poster: string): void => {
        if (this.accepts(key, generation)) { this.setPoster(poster); }
      });
      requestPoster(path, this.msg.videoFileSize, 0);
    }
    this.requestDownload(); this.publishLabel();
  }
  private syncCandidate(): void {
    const id = this.msg.isAnimation || this.sendState === 'sending' ? 0 : this.msg.id;
    if (id === this.candidateId) { return; }
    if (this.candidateId !== 0) { this.actions.onMediaGone(this.candidateId, -1); }
    this.candidateId = id;
  }
  private detach(): void {
    this.generation++; this.observationEpoch++; this.observationKey = '';
    if (this.unsubProgress !== null) { this.unsubProgress(); this.unsubProgress = null; }
    if (this.unsubPoster !== null) { this.unsubPoster(); this.unsubPoster = null; }
    if (this.candidateId !== 0) { this.actions.onMediaGone(this.candidateId, -1); }
    this.candidateId = 0; this.centerY = 0; this.binding = ''; this.boundSlot = undefined;
  }
  @Monitor('msg', 'data', 'slot', 'mediaWidth', 'mediaHeight', 'sendState')
  private changed(): void { this.attach(); }
  aboutToAppear(): void { this.active = true; this.attach(); }
  aboutToReuse(): void { this.active = true; this.attach(); }
  aboutToRecycle(): void { this.active = false; this.detach(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }

  private playing(): boolean { return !this.msg.isAnimation && this.sendState !== 'sending' && this.data.playSlotKey === slotKey(this.msg.id, -1); }
  @Computed
  private get animationPlaying(): boolean { return this.sendState !== 'sending' && drawnAnimationPlaying(this.msg, this.data, this.env, this.mediaVisible); }
  @Computed
  private get downloadExpected(): boolean { return this.sendState !== 'sending' && drawnAnimationDownloadExpected(this.msg, this.data, this.env); }
  @Monitor('downloadExpected')
  private downloadPolicyChanged(): void {
    if (!this.downloadExpected) { this.requestedDownload = false; }
    this.requestDownload();
  }
  private requestDownload(): void {
    if (!this.active || !this.downloadExpected || !this.mediaVisible || this.requestedDownload) { return; }
    this.requestedDownload = true;
    this.actions.onAutoplayVideoNeedDownload(this.msg.id);
  }
  private animationFailedCallback(): () => void {
    const epoch = this.observationGeneration(), key = this.inputKey(), id = this.msg.id;
    return (): void => {
      if (this.acceptsObservation(epoch, key) && this.msg.isAnimation && this.animationPlaying) {
        this.actions.onAnimationPlaybackFailed(id);
      }
    };
  }
  private observationGeneration(): number {
    const fileId = this.msg.isAnimation ? this.msg.videoFileId : this.files.prepare(this.msg).fileId;
    const key = `${this.inputKey()}:${this.mediaWidth}:${this.mediaHeight}:${this.playing()}:${fileId}:${this.animationPlaying}:${this.sendState === 'sending'}`;
    if (this.observationKey !== key) { this.observationKey = key; this.observationEpoch++; }
    return this.observationEpoch;
  }
  private acceptsObservation(epoch: number, key: string): boolean {
    return this.active && epoch === this.observationGeneration() && key === this.inputKey();
  }
  private ratioCallback(): (visible: boolean, ratio: number) => void {
    const epoch = this.observationGeneration(), key = this.inputKey(), id = this.msg.id;
    return (_visible: boolean, ratio: number): void => {
      if (!this.acceptsObservation(epoch, key)) { return; }
      const visible = _visible && ratio > .02;
      if (this.mediaVisible !== visible) { this.mediaVisible = visible; if (visible) { this.requestDownload(); } }
      if (this.msg.isAnimation || this.sendState === 'sending') { return; }
      if (ratio <= 0) { this.actions.onMediaGone(id, -1); }
      else { this.actions.onMediaRatio(id, -1, ratio, this.centerY); }
    };
  }
  private areaCallback(): (old: Area, area: Area) => void {
    const epoch = this.observationGeneration(), key = this.inputKey();
    return (_old: Area, area: Area): void => {
      if (this.acceptsObservation(epoch, key)) { this.centerY = Number(area.globalPosition.y) + Number(area.height) / 2; }
    };
  }
  private positionCallback(): (ms: number) => void {
    const epoch = this.observationGeneration(), key = this.inputKey(), id = this.msg.id;
    return (ms: number): void => {
      if (this.acceptsObservation(epoch, key) && this.playing()) { this.actions.onPlaySlotPositionChanged(id, -1, ms); }
    };
  }
  private endedCallback(): () => void {
    const epoch = this.observationGeneration(), key = this.inputKey(), id = this.msg.id;
    return (): void => {
      if (this.acceptsObservation(epoch, key) && this.playing()) { this.actions.onPlaySlotEnded(id, -1); }
    };
  }
  @Computed
  private get accessibilityLabel(): string {
    if (!this.reportAccessibility || this.env.langEpoch < 0) { return ''; }
    const unavailable = this.msg.videoFileId === 0 && this.msg.videoPath === '';
    if (this.msg.isAnimation) {
      if (unavailable) { return str('mb_gif_unavailable'); }
      if (this.msg.videoFailed || this.data.animationPlaybackFailed) { return str('mb_gif_failed'); }
      if (this.downloading() || this.downloadExpected) {
        return this.progress > 0 ? str('mb_gif_downloaded_pct', this.progress) : str('mb_gif_loading');
      }
      return this.animationPlaying ? str('mb_gif_playing') : str('mb_gif_paused');
    }
    if (unavailable) { return str('mb_video_unavailable'); }
    if (this.msg.videoFailed) { return str('mb_video_failed'); }
    if (this.downloading()) { return str('mb_video_downloaded_pct', this.progress); }
    if (this.msg.photoFailed) { return str('mb_video_cover_failed'); }
    return this.msg.videoDuration > 0 ? str('mb_video_duration', formatMediaDuration(this.msg.videoDuration)) : str('mb_tap_play_video');
  }
  @Monitor('accessibilityLabel')
  private publishLabel(): void { if (this.active && this.reportAccessibility) { this.onLabelChanged(this.accessibilityLabel); } }
  private downloading(): boolean { return this.msg.videoPath === '' && this.progress > 0 && this.progress < 100; }
  private live(): boolean { return isLivePhotoVideo(this.msg.videoFileName, this.msg.videoDuration); }
  @Computed
  private get meta(): string {
    const epoch = chatEnv.langEpoch;
    if (epoch < 0) { return ''; }
    if (this.msg.isAnimation) { return this.msg.videoDuration > 0 ? `GIF · ${formatMediaDuration(this.msg.videoDuration)}` : 'GIF'; }
    const duration = this.msg.videoDuration > 0 ? formatMediaDuration(this.msg.videoDuration) : '';
    const detail = this.sendState === 'sending'
      ? this.progress > 0 && this.progress < 100 ? `${this.progress}%` : this.msg.videoFileSize > 0 ? formatFileSize(this.msg.videoFileSize) : ''
      : this.msg.videoPath !== '' ? str('mb_video_cached') : this.downloading() ? `${this.progress}%`
      : this.msg.videoFileSize > 0 ? formatFileSize(this.msg.videoFileSize) : '';
    return duration !== '' && detail !== '' ? `${duration} · ${detail}` : duration || detail;
  }
  @Builder
  badge(size: number) {
    Stack() {
      Circle({ width: size, height: size }).fill('#78000000').stroke('#24FFFFFF').strokeWidth(1);
      if (this.downloading()) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Ring }).width(size).height(size).color(Color.White);
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(size * .34).fontColor([Color.White]).margin({ left: 2 });
      } else if (this.downloadExpected) {
        LoadingProgress().width(size * .62).height(size * .62).color(Color.White);
      } else if (this.msg.videoFailed || this.data.animationPlaybackFailed) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(size * .4).fontColor([Color.White]);
      } else if (this.msg.videoFileId === 0 && this.msg.videoPath === '') {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(size * .4).fontColor([Color.White]);
      } else {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(size * .42).fontColor([Color.White]).margin({ left: 2 });
      }
    }.width(size).height(size);
  }
  build() {
    Stack() {
      if (this.playing() && this.msg.videoFileId !== 0) {
        VideoBubbleSurface({ fileId: this.files.prepare(this.msg).fileId, fileSize: this.files.prepare(this.msg).fileSize,
          mimeType: this.msg.videoMimeType, sourceWidth: this.msg.photoWidth, sourceHeight: this.msg.photoHeight,
          posterPath: this.poster || this.msg.photoPath || thumbPathFor(this.msg.photoFileId),
          muted: this.data.autoplayMuted, startPositionMs: this.data.playSlotStartMs,
          onPositionChanged: this.positionCallback(), onEnded: this.endedCallback() })
          .width(this.mediaWidth).height(this.mediaHeight).clip(true).hitTestBehavior(HitTestMode.None);
      } else if (this.animationPlaying) {
        SmartLoopVideo({ videoPath: this.msg.videoPath, thumbPath: this.msg.photoPath || thumbPathFor(this.msg.photoFileId),
          boxWidth: this.mediaWidth, boxHeight: this.mediaHeight, powerCategory: 'gif', scrollGated: true,
          forcePlay: this.data.animationForcePlay, onPlaybackFailed: this.animationFailedCallback() })
          .hitTestBehavior(HitTestMode.None);
      } else if (!this.live() && this.sendState !== 'sending' && (this.thumbReady || this.poster !== '')) {
        this.badge(Math.min(56, Math.min(this.mediaWidth, this.mediaHeight) * .34));
      }
      if (this.live()) {
        Row({ space: 3 }) {
          SymbolGlyph($r('sys.symbol.livephoto')).fontSize(12).fontColor([Color.White]);
          Text($r('app.string.cp_live_photo')).fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
        }.height(18).padding({ left: 5, right: 6 }).backgroundColor('#66000000').borderRadius(9).position({ x: 6, y: 6 });
      }
      if (this.meta !== '') {
        Text(this.meta).fontSize(11).fontColor(Color.White).backgroundColor('#66000000').borderRadius(8)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 }).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: Math.max(24, this.mediaWidth - 12) })
          .position({ x: 6, y: Math.max(6, this.mediaHeight - 24) });
      }
    }.width(this.mediaWidth).height(this.mediaHeight).hitTestBehavior(HitTestMode.None)
    .onVisibleAreaApproximateChange({ ratios: [0, .08, PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, .9],
      expectedUpdateInterval: 200 }, this.ratioCallback()).onAreaChange(this.areaCallback());
  }
}
