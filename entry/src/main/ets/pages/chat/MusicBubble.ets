import { getVoicePlayback, VoiceState } from '../../services/VoicePlayback';
import { formatFileSize } from '../../util/formatFileSize';
import { formatVoiceDuration } from '../../util/voiceWaveform';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// P4 批 5：迁 @ComponentV2（配方同批 1~4）。复用在 aboutToReuse 同步重挂；
// @Monitor 兜非复用路径（挂错 = 进度条在动、其实播的不是它）。
// 成员 @Styles 迁全局（V2 不支持成员 @Styles，四组均无状态依赖）。
@Styles
function musicControlNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }

@Styles
function musicControlPressedStyle() { .scale({ x: 0.92, y: 0.92 }).opacity(0.82) }

@Styles
function musicSkipNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }

@Styles
function musicSkipPressedStyle() { .scale({ x: 0.9, y: 0.9 }).opacity(0.65) }

@ComponentV2
export struct MusicBubble {
  @Param msgId: number = 0;
  @Param durationSec: number = 0;
  @Param isOutgoing: boolean = false;
  @Param audioFileId: number = 0;
  @Param audioPath: string = '';
  @Param fileSize: number = 0;
  @Param fileName: string = '';
  @Param title: string = '';
  @Param performer: string = '';
  @Param coverPath: string = '';
  @Param coverFailed: boolean = false;
  @Param downloadProgress: number = 0;
  @Param downloadFailed: boolean = false;
  @Param downloadActive: boolean = false;
  @Param queuePosition: number = 0;
  @Param queueLength: number = 0;
  @Param hasPrevious: boolean = false;
  @Param hasNext: boolean = false;
  @Param maxWidth: number = 250;
  @Param onToggle: () => void = (): void => {};
  @Param onPrevious: () => void = (): void => {};
  @Param onNext: () => void = (): void => {};
  @Param onSeek: (fraction: number) => void = (): void => {};

  @Local playbackStatus: string = 'idle';
  @Local progress: number = 0;
  @Local elapsedSec: number = 0;
  @Local resolvedDurationSec: number = 0;
  @Local playbackFailed: boolean = false;
  @Local finished: boolean = false;
  @Local dragging: boolean = false;
  @Local dragProgress: number = 0;
  private unsub: (() => void) | null = null;

  private attachPlayback(targetId: number, durationSec: number): void {
    this.detachPlayback();
    this.playbackStatus = 'idle';
    this.progress = 0;
    this.elapsedSec = 0;
    this.resolvedDurationSec = Math.max(0, durationSec);
    this.playbackFailed = false;
    this.finished = false;
    this.dragging = false;
    this.dragProgress = 0;
    this.unsub = getVoicePlayback().subscribe((state: VoiceState): void => {
      const mine: boolean = state.mode === 'music' && state.playingId === targetId;
      this.playbackFailed = state.mode === 'music' && state.errorId === targetId;
      if (mine) {
        this.playbackStatus = state.status;
        if (state.durationMs > 0) {
          this.resolvedDurationSec = Math.max(1, Math.ceil(state.durationMs / 1000));
        }
        if (!this.dragging) {
          this.progress = state.durationMs > 0
            ? Math.min(1, Math.max(0, state.positionMs / state.durationMs)) : 0;
        }
        this.elapsedSec = Math.max(0, Math.floor(state.positionMs / 1000));
        if (state.status === 'loading' || state.status === 'playing') {
          this.finished = false;
        }
      } else {
        this.playbackStatus = 'idle';
        if (!this.finished && !this.dragging) {
          this.progress = 0;
          this.elapsedSec = 0;
        }
      }
      if (state.mode === 'music' && state.completedId === targetId) {
        this.finished = true;
        this.progress = 1;
        this.elapsedSec = this.resolvedDuration();
      }
    });
  }

  private detachPlayback(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
  }

  @Monitor('msgId')
  onMsgIdChanged(): void {
    this.attachPlayback(this.msgId, this.durationSec);
  }

  aboutToAppear(): void {
    this.attachPlayback(this.msgId, this.durationSec);
  }

  aboutToRecycle(): void {
    this.detachPlayback();
  }

  aboutToReuse(): void {
    // @Param 已是新值：attachPlayback 自带全套状态重播种，同步做即可。
    this.attachPlayback(this.msgId, this.durationSec);
  }

  aboutToDisappear(): void {
    this.detachPlayback();
  }

  private accent(): ResourceColor {
    return this.isOutgoing ? '#55A24D' : COLOR_PRIMARY;
  }

  private resolvedDuration(): number {
    return this.resolvedDurationSec > 0
      ? this.resolvedDurationSec : Math.max(0, this.durationSec);
  }

  private sourceUnavailable(): boolean {
    return this.audioFileId === 0 && this.audioPath === '';
  }

  private localReady(): boolean {
    return this.audioPath !== '';
  }

  private loadingPlayback(): boolean {
    return this.playbackStatus === 'loading';
  }

  private playing(): boolean {
    return this.playbackStatus === 'playing';
  }

  private paused(): boolean {
    return this.playbackStatus === 'paused';
  }

  private currentTrack(): boolean {
    return this.playbackStatus !== 'idle';
  }

  private displayTitle(): string {
    const named: string = this.title.trim();
    if (named !== '') {
      return named;
    }
    const file: string = this.fileName.trim();
    if (file === '') {
      return str('music_audio');
    }
    const dot: number = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  private displayPerformer(): string {
    const artist: string = this.performer.trim();
    return artist !== '' ? artist : str('music_unknown_artist');
  }

  private totalLabel(): string {
    const duration: number = this.resolvedDuration();
    return duration > 0 ? formatVoiceDuration(duration) : '—:—';
  }

  private queueLabel(): string {
    return this.queuePosition > 0 && this.queueLength > 1
      ? `${this.queuePosition}/${this.queueLength}` : '';
  }

  private statusLabel(): string {
    if (this.sourceUnavailable()) {
      return str('music_unavailable');
    }
    if (this.downloadFailed) {
      return str('download_failed_tap');
    }
    if (this.downloadActive) {
      return this.downloadProgress > 0
        ? str('downloading_pct', this.downloadProgress) : str('downloading');
    }
    if (this.playbackFailed) {
      return str('play_failed_tap');
    }
    if (this.loadingPlayback()) {
      return str('opening');
    }
    if (this.playing() || this.paused() || this.finished) {
      return `${formatVoiceDuration(this.elapsedSec)} / ${this.totalLabel()}`;
    }
    const size: string = this.fileSize > 0 ? formatFileSize(this.fileSize) : '';
    if (!this.localReady()) {
      return size !== '' ? str('music_tap_download_size', this.totalLabel(), size)
        : str('music_tap_download', this.totalLabel());
    }
    return size !== '' ? `${this.totalLabel()} · ${size}` : this.totalLabel();
  }

  private onSeekChange(value: number, mode: SliderChangeMode): void {
    if (!this.localReady() || this.resolvedDuration() <= 0) {
      return;
    }
    const fraction: number = Math.max(0, Math.min(1, value));
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.dragging = true;
      this.dragProgress = fraction;
      return;
    }
    this.dragging = false;
    this.progress = fraction;
    this.elapsedSec = Math.floor(fraction * this.resolvedDuration());
    this.onSeek(fraction);
  }

  @Builder
  private coverControl(): void {
    Stack() {
      if (this.coverPath !== '') {
        Image(this.coverPath.startsWith('/') ? `file://${this.coverPath}` : this.coverPath).draggable(false)
          .width(52).height(52)
          .borderRadius(13)
          .objectFit(ImageFit.Cover);
      } else {
        Column()
          .width(52).height(52)
          .borderRadius(13)
          .linearGradient({
            angle: 145,
            colors: this.isOutgoing
              ? [['#74BF69', 0], ['#3E8844', 1]]
              : [['#65B8F5', 0], ['#3278D8', 1]]
          });
        Text('♫')
          .fontSize(25)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .opacity(this.coverFailed ? 0.72 : 0.94);
      }
      Circle({ width: 31, height: 31 })
        .fill('#A8000000');
      if (this.downloadActive || this.loadingPlayback()) {
        if (this.downloadActive && this.downloadProgress > 0) {
          Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Ring })
            .width(27).height(27)
            .color(Color.White)
            .style({ strokeWidth: 2 });
          Text(`${this.downloadProgress}`)
            .fontSize(8.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White);
        } else {
          LoadingProgress().width(18).height(18).color(Color.White);
        }
      } else {
        SymbolGlyph($r(this.playing() ? 'sys.symbol.pause'
          : ((this.downloadFailed || this.playbackFailed || this.finished)
            ? 'sys.symbol.arrow_counterclockwise'
            : (this.localReady() ? 'sys.symbol.play_fill' : 'sys.symbol.arrow_down'))))
          .fontSize(16)
          .fontColor([Color.White]);
      }
    }
    .width(52).height(52)
    .stateStyles({ normal: musicControlNormalStyle, pressed: musicControlPressedStyle })
    .animation({ duration: 110, curve: Curve.EaseOut })
    .accessibilityText(this.statusLabel())
    .onClick((): void => {
      if (!this.sourceUnavailable()) {
        this.onToggle();
      }
    });
  }

  @Builder
  private skipControl(label: string, enabled: boolean, previous: boolean): void {
    Text(label)
      .width(22).height(22)
      .borderRadius(11)
      .textAlign(TextAlign.Center)
      .fontSize(18)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.accent())
      .backgroundColor(this.isOutgoing ? '#1655A24D' : '#143390EC')
      .opacity(enabled ? 1 : 0.34)
      .stateStyles({ normal: musicSkipNormalStyle, pressed: musicSkipPressedStyle })
      .animation({ duration: 100, curve: Curve.EaseOut })
      .accessibilityText(previous ? $r('app.string.music_previous') : $r('app.string.music_next'))
      .onClick((): void => {
        if (enabled) {
          if (previous) {
            this.onPrevious();
          } else {
            this.onNext();
          }
        }
      });
  }

  build() {
    Row({ space: 9 }) {
      this.coverControl();
      Column({ space: 2 }) {
        Text(this.displayTitle())
          .fontSize(14.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%');
        Row({ space: 4 }) {
          Text(this.displayPerformer())
            .fontSize(11.5)
            .fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (this.queueLabel() !== '') {
            Text(this.queueLabel())
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accent());
          }
        }
        .width('100%')
        .height(17)
        .alignItems(VerticalAlign.Center);
        Slider({
          value: this.dragging ? this.dragProgress : this.progress,
          min: 0,
          max: 1,
          step: 0.001
        })
          .width('100%')
          .height(14)
          .trackColor(this.isOutgoing ? '#459FCB98' : '#45B7CDE3')
          .selectedColor(this.accent())
          .blockColor(this.accent())
          .blockSize({ width: 10, height: 10 })
          .enabled(this.currentTrack() && this.localReady() && this.resolvedDuration() > 0)
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.onSeekChange(value, mode);
          });
        Row({ space: 4 }) {
          Text(this.statusLabel())
            .fontSize(10.5)
            .fontColor(this.downloadFailed || this.playbackFailed
              ? '#D95B57' : COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (this.queueLength > 1 && this.currentTrack()) {
            this.skipControl('‹', this.hasPrevious, true);
            this.skipControl('›', this.hasNext, false);
          }
        }
        .width('100%')
        .height(22)
        .alignItems(VerticalAlign.Center);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .width(Math.max(190, Math.min(262, this.maxWidth)))
    .alignItems(VerticalAlign.Top)
    // The message timestamp is overlaid at the bubble's lower-right. Keep the
    // music card clear of it just like the voice waveform does.
    .padding({ top: 1, bottom: 9, right: 31 });
  }
}
