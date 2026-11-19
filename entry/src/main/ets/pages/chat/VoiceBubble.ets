import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnCardBar } from './DrawnCardBar';
import { DrawnMediaControl } from './DrawnMediaControl';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnAudioWaveform } from './DrawnAudioWaveform';
import { AudioClock, IDLE_AUDIO_CLOCK } from '../../util/audioClock';
import { getVoicePlayback, VoiceState } from '../../services/VoicePlayback';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { formatVoiceDuration, voiceWaveformBars } from '../../util/voiceWaveform';
import { str } from '../../util/strings';

// 成员 @Styles 迁全局（V2 不支持成员 @Styles，四组均无状态依赖）。
@Styles
function voiceControlNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }

@Styles
function voiceControlPressedStyle() { .scale({ x: 0.91, y: 0.91 }).opacity(0.82) }

@Styles
function voiceSpeedNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }

@Styles
function voiceSpeedPressedStyle() { .scale({ x: 0.94, y: 0.94 }).opacity(0.68) }

const WAVEFORM_BAR_COUNT: number = 34;
const WAVEFORM_WIDTH: number = 132;

// P4 批 5：迁 @ComponentV2（配方同批 1~4）。复用在 aboutToReuse 同步重挂；
// @Monitor 兜非复用路径（挂错 = 跟着别的那条语音的播放状态走）。
@ComponentV2
export struct VoiceBubble {
  private infoPainter: DrawnCardBar = new DrawnCardBar();
  private speedPainter: DrawnCardBar = new DrawnCardBar();
  private dotPainter: DrawnMediaControl = new DrawnMediaControl();
  private controlPainter: DrawnMediaControl = new DrawnMediaControl();
  private paintEnv = chatEnv;
  @Computed private get paintEnvironment(): string {
    return `${this.paintEnv.appearanceEpoch}:${this.paintEnv.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Param waveformWidth: number = WAVEFORM_WIDTH;
  @Param allowTranscription: boolean = true;
  @Event onBeforeControl: () => boolean = (): boolean => true;
  @Param documentFileId: number = 0;
  @Param msgId: number = 0;
  @Param durationSec: number = 0;
  @Param isOutgoing: boolean = false;
  @Param voiceFileId: number = 0;
  @Param voicePath: string = '';
  @Param downloadProgress: number = 0;
  @Param downloadFailed: boolean = false;
  @Param waveform: string = '';
  @Param listened: boolean = true;
  // 语音转文字：'' 未识别 / pending 识别中 / done 已完成 / error 失败
  @Param speechState: string = '';
  @Param speechText: string = '';
  @Event onRecognizeTap: () => void = (): void => {};
  @Param onNeedDownload: () => void = (): void => {};
  @Param onPlaybackStarted: () => void = (): void => {};
  private get progress(): number { return this.clock.progress; }
  private get elapsedSec(): number { return this.clock.elapsed; }

  private setClock(progress: number, elapsed: number): void {
    if (this.clock.progress !== progress || this.clock.elapsed !== elapsed) {
      this.clock = { progress: progress, elapsed: elapsed };
    }
  }

  @Local playbackStatus: string = 'idle';
  @Local finished: boolean = false;
  // 进度比例 + 秒数永远成对写（4 处全是相邻两行），合成一个快照：一次赋值、
  // 一次通知，而不是每次播放进度回调都跑两遍依赖遍历。
  @Local private clock: AudioClock = IDLE_AUDIO_CLOCK;
  @Local resolvedDurationSec: number = 0;
  @Local speed: number = 1;
  @Local playbackFailed: boolean = false;
  @Local locallyListened: boolean = false;
  private playbackStartedReported: boolean = false;
  private unsub: (() => void) | null = null;

  private attachPlayback(targetId: number, durationSec: number, listened: boolean): void {
    this.detachPlayback();
    this.playbackStatus = 'idle';
    this.finished = false;
    this.setClock(0, 0);
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
        this.setClock(state.durationMs > 0
          ? Math.min(1, Math.max(0, state.positionMs / state.durationMs)) : 0,
          Math.max(0, Math.floor(state.positionMs / 1000)));
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
          this.setClock(0, 0);
        }
      }
      if (state.mode === 'voice' && state.completedId === targetId) {
        this.finished = true;
        this.setClock(1, this.resolvedDuration());
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
    this.attachPlayback(this.msgId, this.durationSec, this.listened);
  }

  aboutToAppear(): void {
    this.attachPlayback(this.msgId, this.durationSec, this.listened);
  }

  aboutToRecycle(): void {
    this.detachPlayback();
  }

  aboutToReuse(): void {
    // @Param 已是新值：attachPlayback 自带全套状态重播种，同步做即可。
    this.attachPlayback(this.msgId, this.durationSec, this.listened);
  }

  aboutToDisappear(): void {
    this.detachPlayback();
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

  @Computed private get waveformBars(): number[] {
    return voiceWaveformBars(this.waveform, WAVEFORM_BAR_COUNT, this.msgId);
  }

  private waveUnits: DrawnTextUnits = new DrawnTextUnits();
  private wavePainter: DrawnAudioWaveform = new DrawnAudioWaveform();

  private speedLabel(): string {
    return this.speed === 1 ? '1x' : `${this.speed}x`;
  }

  private onPlayTap(): void {
    if (!this.onBeforeControl()) { return; }
    if (this.sourceUnavailable()) {
      return;
    }
    if (this.voicePath === '') {
      this.onNeedDownload();
      return;
    }
    if (this.documentFileId > 0) {
      getVoicePlayback().toggleDocumentVoice(this.documentFileId, this.voicePath, this.resolvedDuration());
    } else { getVoicePlayback().toggle(this.msgId, this.voicePath, this.resolvedDuration()); }
  }

  private onSpeedTap(): void {
    if (!this.onBeforeControl()) { return; }
    if (this.voicePath === '') {
      return;
    }
    this.speed = getVoicePlayback().cycleSpeed(this.msgId);
  }

  @Builder
  private playControl(): void {
    Stack() {
      if ((this.downloading() && this.downloadProgress <= 0) || this.loadingPlayback()) {
        DrawnLoadingSpinner({ ringSize: 20, ringColor: Color.White });
      }
    }
    .width(38).height(38)
    .drawModifier(this.controlPainter.bind(this.getUIContext(), this.paintEnvironment, 38,
      this.sourceUnavailable() ? '#AEB6BF' : (this.downloadFailed || this.playbackFailed ? '#E86C68' : this.accent()),
      '#FFFFFF', this.downloading() ? 'percent' : this.loadingPlayback() ? '' : this.playing() ? 'pause'
        : (this.finished || this.downloadFailed || this.playbackFailed) ? 'retry' : 'play',
      this.downloading() ? this.downloadProgress : 0, false,
      this.downloading() && this.downloadProgress > 0 ? `${this.downloadProgress}` : ''))
    .stateStyles({
      normal: voiceControlNormalStyle,
      pressed: voiceControlPressedStyle
    })
    .animation({ duration: 110, curve: Curve.EaseOut })
    .accessibilityText(this.timeLabel())
    .onClick((): void => {
      this.onPlayTap();
    });
  }

  private recognizeSpeech(): void {
    // A completed/pending recognition must not dispatch again if an old
    // control receives the final click while its branch is being replaced.
    if (this.speechState === 'pending' || this.speechState === 'done') {
      return;
    }
    this.onRecognizeTap();
  }

  @Builder
  private recognizeControl() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.character_square')).fontSize(13)
          .fontColor([this.speechSecondaryColor()]);
        Text($r('app.string.voice_transcribe')).fontSize(12.5).fontColor(this.speechSecondaryColor());
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .hitTestBehavior(HitTestMode.None);
    }
    .width(this.waveformWidth)
    .height(32)
    .padding({ left: 0, right: 8 })
    .borderRadius(6)
    .backgroundColor(Color.Transparent)
    .accessibilityText($r('app.string.voice_transcribe_sub'))
    .onClick((): void => { this.recognizeSpeech(); });
  }

  // 转文字入口与结果。放在波形下方而不是挤进那一行——识别文本可能很长，
  // 塞进气泡内的横向空间会把波形压没。
  @Builder
  speechArea() {
    if (this.speechState === 'pending') {
      Row({ space: 6 }) {
        DrawnLoadingSpinner({ ringSize: 13, ringColor: this.accent() });
        Text(this.speechText !== '' ? this.speechText : $r('app.string.voice_transcribing'))
          .fontSize(13).fontColor(this.speechSecondaryColor())
          .maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.width(this.waveformWidth).alignItems(VerticalAlign.Top);
    } else if (this.speechState === 'done') {
      Text(this.speechText).fontSize(13.5).lineHeight(19)
        .fontColor(this.speechPrimaryColor())
        .width(this.waveformWidth)
        .textAlign(TextAlign.Start);
    } else if (this.speechState === 'error') {
      Column({ space: 2 }) {
        Text(this.speechText !== '' ? this.speechText : $r('app.string.voice_transcribe_failed'))
          .fontSize(12.5).fontColor('#FF3B30').width(this.waveformWidth);
        this.recognizeControl();
      }
      .alignItems(HorizontalAlign.Start);
    } else {
      this.recognizeControl();
    }
  }

  build() {
    Column({ space: 4 }) {
    Row({ space: 9 }) {
      this.playControl();
      Column({ space: 3 }) {
        Row()
          .width(this.waveformWidth)
          .height(22)
          .drawModifier(this.wavePainter.bind(this.waveformBars, this.progress,
            this.waveUnits.prepare(this.getUIContext(), this.paintEnvironment).density, this.accent(), this.inactiveWaveColor(), true, this.paintEnvironment));
        Row({ space: 5 }) {
          Row()
            .layoutWeight(1).height(20)
            .drawModifier(this.infoPainter.bind(this.getUIContext(), {
              width: Math.max(1, this.waveformWidth - (this.showUnlistenedDot() ? 11 : 0) - (this.voicePath !== '' ? 47 : 0)),
              height: 20, environment: this.paintEnvironment, left: this.timeLabel(), leftFont: 11.5,
              leftColor: this.downloadFailed || this.playbackFailed ? '#D95B57' : COLOR_TEXT_SECONDARY
            }))
            .accessibilityText(this.timeLabel());
          if (this.showUnlistenedDot()) {
            Row().width(6).height(6)
              .drawModifier(this.dotPainter.bind(this.getUIContext(), this.paintEnvironment, 6, this.accent(), '#00000000', ''));
          }
          if (this.voicePath !== '') {
            Row()
              .width(42).height(20)
              .drawModifier(this.speedPainter.bind(this.getUIContext(), {
                width: 42, height: 20, environment: this.paintEnvironment, center: this.speedLabel(), centerFont: 10.5,
                centerColor: this.accent(), background: this.isOutgoing ? '#1755A24D' : '#163390EC', radius: 10
              }))
              .stateStyles({
                normal: voiceSpeedNormalStyle,
                pressed: voiceSpeedPressedStyle
              })
              .animation({ duration: 100, curve: Curve.EaseOut })
              .accessibilityText(str('voice_speed_a11y', this.speedLabel()))
              .onClick((): void => {
                this.onSpeedTap();
              });
          }
        }
        .width(this.waveformWidth)
        .height(20)
        .alignItems(VerticalAlign.Center);
      }
      .alignItems(HorizontalAlign.Start);
    }
    .alignItems(VerticalAlign.Center)
    .padding({ top: 1, right: 31 });
      if (this.allowTranscription) { this.speechArea(); }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 9 });
  }
}
