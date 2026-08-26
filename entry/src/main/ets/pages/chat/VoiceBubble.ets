import { getVoicePlayback, VoiceState } from '../../services/VoicePlayback';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { formatVoiceDuration, voiceWaveformBars } from '../../util/voiceWaveform';
import { str } from '../../util/strings';
import { reuseParam } from '../../util/reuseParams';

const WAVEFORM_BAR_COUNT: number = 34;
const WAVEFORM_WIDTH: number = 132;

@Component
export struct VoiceBubble {
  @Prop msgId: number = 0;
  @Prop durationSec: number = 0;
  @Prop isOutgoing: boolean = false;
  @Prop voiceFileId: number = 0;
  @Prop voicePath: string = '';
  @Prop downloadProgress: number = 0;
  @Prop downloadFailed: boolean = false;
  @Prop waveform: string = '';
  @Prop listened: boolean = true;
  // 语音转文字：'' 未识别 / pending 识别中 / done 已完成 / error 失败
  @Prop speechState: string = '';
  @Prop speechText: string = '';
  onRecognizeTap: () => void = (): void => {};
  onNeedDownload: () => void = (): void => {};
  onPlaybackStarted: () => void = (): void => {};
  @State playbackStatus: string = 'idle';
  @State finished: boolean = false;
  @State progress: number = 0;
  @State elapsedSec: number = 0;
  @State resolvedDurationSec: number = 0;
  @State speed: number = 1;
  @State playbackFailed: boolean = false;
  @State locallyListened: boolean = false;
  private playbackStartedReported: boolean = false;
  private unsub: (() => void) | null = null;

  private attachPlayback(targetId: number, durationSec: number, listened: boolean): void {
    this.detachPlayback();
    this.playbackStatus = 'idle';
    this.finished = false;
    this.progress = 0;
    this.elapsedSec = 0;
    this.speed = 1;
    this.playbackFailed = false;
    this.playbackStartedReported = false;
    this.locallyListened = listened;
    this.resolvedDurationSec = Math.max(0, durationSec);
    this.unsub = getVoicePlayback().subscribe((state: VoiceState): void => {
      const mine: boolean = state.mode === 'voice' && state.playingId === targetId;
      this.speed = state.speed;
      this.playbackFailed = state.mode === 'voice' && state.errorId === targetId;
      if (mine) {
        this.playbackStatus = state.status;
        if (state.durationMs > 0) {
          this.resolvedDurationSec = Math.max(1, Math.ceil(state.durationMs / 1000));
        }
        this.progress = state.durationMs > 0
          ? Math.min(1, Math.max(0, state.positionMs / state.durationMs)) : 0;
        this.elapsedSec = Math.max(0, Math.floor(state.positionMs / 1000));
        if (state.status === 'loading') {
          this.finished = false;
        }
        if (state.status === 'playing' && !this.playbackStartedReported) {
          this.playbackStartedReported = true;
          this.locallyListened = true;
          this.onPlaybackStarted();
        }
      } else {
        this.playbackStatus = 'idle';
        if (!this.finished) {
          this.progress = 0;
          this.elapsedSec = 0;
        }
      }
      if (state.mode === 'voice' && state.completedId === targetId) {
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

  aboutToAppear(): void {
    this.attachPlayback(this.msgId, this.durationSec, this.listened);
  }

  aboutToRecycle(): void {
    this.detachPlayback();
    this.playbackStatus = 'idle';
  }

  aboutToReuse(params: Record<string, Object>): void {
    // reuseParam：params 是 {} 还是 undefined 都安全，取不到就落到下面的
    // setTimeout 兜底（P3 批 2 第 1 项，见 util/reuseParams.ets）。
    const msgId: number | undefined = reuseParam(params, 'msgId') as number | undefined;
    const durationSec: number | undefined =
      reuseParam(params, 'durationSec') as number | undefined;
    const listened: boolean | undefined = reuseParam(params, 'listened') as boolean | undefined;
    if (msgId !== undefined) {
      this.attachPlayback(msgId, durationSec ?? 0, listened ?? true);
      return;
    }
    setTimeout((): void => {
      this.attachPlayback(this.msgId, this.durationSec, this.listened);
    }, 0);
  }

  aboutToDisappear(): void {
    this.detachPlayback();
  }

  @Styles
  private controlNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private controlPressedStyle(): void {
    .scale({ x: 0.91, y: 0.91 })
    .opacity(0.82)
  }

  @Styles
  private speedNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private speedPressedStyle(): void {
    .scale({ x: 0.94, y: 0.94 })
    .opacity(0.68)
  }

  private accent(): ResourceColor {
    return this.isOutgoing ? '#55A24D' : COLOR_PRIMARY;
  }

  // 转文字区的文字颜色。气泡内不能用全局的文本色——发出的消息是绿底，
  // 次级灰在上面几乎看不见。
  private speechPrimaryColor(): ResourceColor {
    return this.isOutgoing ? '#1B3D17' : COLOR_TEXT_PRIMARY;
  }

  private speechSecondaryColor(): ResourceColor {
    return this.isOutgoing ? '#4C7A45' : COLOR_TEXT_SECONDARY;
  }

  private inactiveWaveColor(): ResourceColor {
    return this.isOutgoing ? '#9FCB98' : '#B7CDE3';
  }

  private resolvedDuration(): number {
    return this.resolvedDurationSec > 0 ? this.resolvedDurationSec : Math.max(0, this.durationSec);
  }

  private sourceUnavailable(): boolean {
    return this.voiceFileId === 0 && this.voicePath === '';
  }

  private downloading(): boolean {
    return this.voicePath === '' && !this.downloadFailed && !this.sourceUnavailable();
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

  private showUnlistenedDot(): boolean {
    return !this.isOutgoing && !this.listened && !this.locallyListened;
  }

  private timeLabel(): string {
    if (this.sourceUnavailable()) {
      return str('voice_unavailable');
    }
    if (this.downloadFailed) {
      return str('download_failed_tap');
    }
    if (this.downloading()) {
      return this.downloadProgress > 0
        ? str('downloading_pct', this.downloadProgress) : str('voice_loading');
    }
    if (this.playbackFailed) {
      return str('play_failed_tap');
    }
    if (this.loadingPlayback()) {
      return str('opening');
    }
    const duration: number = this.resolvedDuration();
    const total: string = duration > 0 ? formatVoiceDuration(duration) : '—:—';
    if (this.playing() || this.paused()) {
      return `${formatVoiceDuration(this.elapsedSec)} / ${total}`;
    }
    if (this.finished) {
      return `${total} / ${total}`;
    }
    return total;
  }

  private bars(): number[] {
    return voiceWaveformBars(this.waveform, WAVEFORM_BAR_COUNT, this.msgId);
  }

  private playedBarCount(): number {
    return Math.round(Math.max(0, Math.min(1, this.progress)) * WAVEFORM_BAR_COUNT);
  }

  private speedLabel(): string {
    return this.speed === 1 ? '1x' : `${this.speed}x`;
  }

  private onPlayTap(): void {
    if (this.sourceUnavailable()) {
      return;
    }
    if (this.voicePath === '') {
      this.onNeedDownload();
      return;
    }
    getVoicePlayback().toggle(this.msgId, this.voicePath, this.resolvedDuration());
  }

  private onSpeedTap(): void {
    if (this.voicePath === '') {
      return;
    }
    this.speed = getVoicePlayback().cycleSpeed(this.msgId);
  }

  @Builder
  private playControl(): void {
    Stack() {
      Circle({ width: 38, height: 38 })
        .fill(this.sourceUnavailable() ? '#AEB6BF'
          : (this.downloadFailed || this.playbackFailed ? '#E86C68' : this.accent()));
      if (this.downloading()) {
        if (this.downloadProgress > 0) {
          Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Ring })
            .width(32).height(32).color(Color.White).style({ strokeWidth: 2 });
          Text(`${this.downloadProgress}`)
            .fontSize(9).fontWeight(FontWeight.Medium).fontColor(Color.White);
        } else {
          LoadingProgress().width(20).height(20).color(Color.White);
        }
      } else if (this.loadingPlayback()) {
        LoadingProgress().width(20).height(20).color(Color.White);
      } else {
        SymbolGlyph($r(this.playing() ? 'sys.symbol.pause'
          : ((this.finished || this.downloadFailed || this.playbackFailed)
            ? 'sys.symbol.arrow_counterclockwise' : 'sys.symbol.play_fill')))
          .fontSize(this.sourceUnavailable() ? 16 : 17)
          .fontColor([Color.White]);
      }
    }
    .width(38).height(38)
    .stateStyles({
      normal: this.controlNormalStyle,
      pressed: this.controlPressedStyle
    })
    .animation({ duration: 110, curve: Curve.EaseOut })
    .accessibilityText(this.timeLabel())
    .onClick((): void => {
      this.onPlayTap();
    });
  }

  // 转文字入口与结果。放在波形下方而不是挤进那一行——识别文本可能很长，
  // 塞进气泡内的横向空间会把波形压没。
  @Builder
  speechArea() {
    if (this.speechState === 'pending') {
      Row({ space: 6 }) {
        LoadingProgress().width(13).height(13).color(this.accent());
        Text(this.speechText !== '' ? this.speechText : $r('app.string.voice_transcribing'))
          .fontSize(13).fontColor(this.speechSecondaryColor())
          .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.width(WAVEFORM_WIDTH).alignItems(VerticalAlign.Top);
    } else if (this.speechState === 'done') {
      Text(this.speechText).fontSize(13.5).lineHeight(19)
        .fontColor(this.speechPrimaryColor())
        .width(WAVEFORM_WIDTH)
        .textAlign(TextAlign.Start);
    } else if (this.speechState === 'error') {
      Text(this.speechText !== '' ? this.speechText : $r('app.string.voice_transcribe_failed'))
        .fontSize(12.5).fontColor('#FF3B30').width(WAVEFORM_WIDTH);
    } else {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.character_square')).fontSize(13)
          .fontColor([this.speechSecondaryColor()]);
        Text($r('app.string.voice_transcribe')).fontSize(12.5).fontColor(this.speechSecondaryColor());
      }
      .padding({ top: 3, bottom: 3, right: 8 })
      .accessibilityText($r('app.string.voice_transcribe_sub'))
      .onClick((): void => { this.onRecognizeTap(); });
    }
  }

  build() {
    Column({ space: 4 }) {
    Row({ space: 9 }) {
      this.playControl();
      Column({ space: 3 }) {
        Row({ space: 1.8 }) {
          ForEach(this.bars(), (height: number, index: number) => {
            Column()
              .width(2.1)
              .height(height)
              .borderRadius(1.1)
              .backgroundColor(index < this.playedBarCount()
                ? this.accent() : this.inactiveWaveColor());
          }, (height: number, index: number): string => `${index}_${height}`);
        }
        .width(WAVEFORM_WIDTH)
        .height(22)
        .alignItems(VerticalAlign.Center);
        Row({ space: 5 }) {
          Text(this.timeLabel())
            .fontSize(11.5)
            .fontColor(this.downloadFailed || this.playbackFailed ? '#D95B57' : COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          if (this.showUnlistenedDot()) {
            Circle({ width: 6, height: 6 }).fill(this.accent());
          }
          if (this.voicePath !== '') {
            Text(this.speedLabel())
              .fontSize(10.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.accent())
              .height(20)
              .padding({ left: 6, right: 6 })
              .borderRadius(10)
              .backgroundColor(this.isOutgoing ? '#1755A24D' : '#163390EC')
              .stateStyles({
                normal: this.speedNormalStyle,
                pressed: this.speedPressedStyle
              })
              .animation({ duration: 100, curve: Curve.EaseOut })
              .accessibilityText(str('voice_speed_a11y', this.speedLabel()))
              .onClick((): void => {
                this.onSpeedTap();
              });
          }
        }
        .width(WAVEFORM_WIDTH)
        .height(20)
        .alignItems(VerticalAlign.Center);
      }
      .alignItems(HorizontalAlign.Start);
    }
    .alignItems(VerticalAlign.Center)
    .padding({ top: 1, right: 31 });
      this.speechArea();
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 9 });
  }
}
