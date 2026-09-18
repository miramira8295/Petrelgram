import { getVoicePlayback, VoiceState } from '../../services/VoicePlayback';
import { formatFileSize } from '../../util/formatFileSize';
import { formatVoiceDuration } from '../../util/voiceWaveform';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { musicFormatLabel, musicTrackKey } from '../../util/musicTrackModel';
import { subscribeMusicCollections, trackInAnyCollection } from '../../store/MusicCollectionStore';
import { voiceWaveformBars } from '../../util/voiceWaveform';

// P4 批 5：迁 @ComponentV2（配方同批 1~4）。复用在 aboutToReuse 同步重挂；
// @Monitor 兜非复用路径（挂错 = 进度条在动、其实播的不是它）。
// 成员 @Styles 迁全局（V2 不支持成员 @Styles，四组均无状态依赖）。
// 2026-09-18 改版（用户给的设计稿）：封面 + 曲名/副标题 + 播放键 / 波形 + 时长 /
// 「已下载」「已收藏」两枚胶囊。配文照旧在卡片下方由 MessageBubble 画。
const COVER: number = 44;
const PLAY_BTN: number = 42;
const WAVE_BARS: number = 34;
const WAVE_BAR_W: number = 2.5;
const WAVE_GAP: number = 2;
const WAVE_H: number = 24;

// 一枚状态胶囊的全部内容。做成结构是为了让 @Builder 只收**一个**参数——
// 多参 @Builder 不会随状态刷新（见 [[arkui-silent-reactivity-traps]]）。
interface MusicChipSpec {
  icon: string;
  label: string;
  color: ResourceColor;
  enabled: boolean;
  action: () => void;
}

@Styles
function musicControlNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }

@Styles
function musicControlPressedStyle() { .scale({ x: 0.92, y: 0.92 }).opacity(0.82) }

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
  // 2026-09-18 改版：卡片自带「下载保存」「添加到收藏夹」两枚状态胶囊。
  @Param chatId: number = 0;
  @Param mimeType: string = '';
  @Param onSave: () => void = (): void => {};
  @Param onFavorite: () => void = (): void => {};

  @Local playbackStatus: string = 'idle';
  @Local progress: number = 0;
  @Local elapsedSec: number = 0;
  @Local resolvedDurationSec: number = 0;
  @Local playbackFailed: boolean = false;
  @Local finished: boolean = false;
  @Local dragging: boolean = false;
  @Local dragProgress: number = 0;
  // 这首在不在任一合集里。**必须在复用时重算**：它不进行 key，靠旧行对象带过来
  // 就是"另一首歌的收藏态"（见 [[side-channel-row-pattern]]）。
  @Local favorited: boolean = false;
  private unsub: (() => void) | null = null;
  private unsubFavorites: (() => void) | null = null;
  private waveWidth: number = 1;

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
    this.attachFavorites(this.chatId, targetId);
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
    if (this.unsubFavorites !== null) {
      this.unsubFavorites();
      this.unsubFavorites = null;
    }
  }

  // 收藏态跟着合集走：在别处（音乐中心）加了/移出，这张卡片也要跟着变。
  private attachFavorites(chatId: number, messageId: number): void {
    const key: string = musicTrackKey(chatId, messageId);
    this.unsubFavorites = subscribeMusicCollections((): void => {
      this.favorited = trackInAnyCollection(key);
    });
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

  // 副标题：演唱者 · 格式 · 大小。格式用 util/musicTrackModel 那套映射，
  // 和音乐中心的信息格是同一份判据。
  private subtitleLabel(): string {
    const parts: string[] = [this.displayPerformer()];
    const format: string = musicFormatLabel(this.mimeType, this.fileName);
    if (format !== '') {
      parts.push(format);
    }
    if (this.fileSize > 0) {
      parts.push(formatFileSize(this.fileSize));
    }
    return parts.join(' · ');
  }

  // 波形。音乐消息**没有** TDLib 波形（那是语音条独有的），所以按文件 id 生成
  // 一份稳定的形状——同一首歌每次进来长得一样，靠的是 voiceWaveformBars 的
  // 种子回退分支，不是随机数。
  private waveBars(): number[] {
    return voiceWaveformBars('', WAVE_BARS, this.audioFileId !== 0 ? this.audioFileId : this.msgId);
  }

  private shownProgress(): number {
    return this.dragging ? this.dragProgress : this.progress;
  }

  @Builder
  private coverArt(): void {
    Stack() {
      if (this.coverPath !== '') {
        Image(this.coverPath.startsWith('/') ? `file://${this.coverPath}` : this.coverPath)
          .draggable(false)
          .width(COVER).height(COVER).borderRadius(12).objectFit(ImageFit.Cover);
      } else {
        Column()
          .width(COVER).height(COVER).borderRadius(12)
          // 比卡片底色重一档，封面块才分得出来（卡片是 #20/#1A 那一档）。
          .backgroundColor(this.isOutgoing ? '#4755A24D' : '#3D3390EC');
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(20).fontColor([this.accent()])
          .opacity(this.coverFailed ? 0.5 : 1);
      }
    }
    .width(COVER).height(COVER);
  }

  // 右侧那颗主按钮：播放 / 暂停 / 下载 / 转圈 / 重试，一个位置管全部状态。
  @Builder
  private playControl(): void {
    Stack() {
      Circle({ width: PLAY_BTN, height: PLAY_BTN }).fill(this.accent());
      if (this.downloadActive || this.loadingPlayback()) {
        if (this.downloadActive && this.downloadProgress > 0) {
          Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Ring })
            .width(PLAY_BTN - 14).height(PLAY_BTN - 14)
            .color(Color.White).style({ strokeWidth: 2 });
        } else {
          LoadingProgress().width(21).height(21).color(Color.White);
        }
      } else {
        SymbolGlyph($r(this.playing() ? 'sys.symbol.pause_fill'
          : ((this.downloadFailed || this.playbackFailed)
            ? 'sys.symbol.arrow_counterclockwise' : 'sys.symbol.play_fill')))
          .fontSize(19).fontColor([Color.White]);
      }
    }
    .width(PLAY_BTN).height(PLAY_BTN)
    .stateStyles({ normal: musicControlNormalStyle, pressed: musicControlPressedStyle })
    .animation({ duration: 110, curve: Curve.EaseOut })
    .accessibilityText(this.statusLabel())
    .onClick((): void => {
      if (!this.sourceUnavailable()) {
        this.onToggle();
      }
    });
  }

  // 一枚状态胶囊。已完成态是"陈述"（勾/心 + 完成时的文案），未完成态是"动作"。
  @Builder
  private chip(spec: MusicChipSpec): void {
    Row({ space: 4 }) {
      SymbolGlyph($r(spec.icon)).fontSize(12).fontColor([spec.color]);
      Text(spec.label).fontSize(11).fontWeight(FontWeight.Medium).fontColor(spec.color)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .height(20)
    .alignItems(VerticalAlign.Center)
    .opacity(spec.enabled ? 1 : 0.45)
    .enabled(spec.enabled)
    .accessibilityText(spec.label)
    .onClick((): void => { spec.action(); });
  }

  private downloadChip(): MusicChipSpec {
    if (this.downloadActive) {
      return {
        icon: 'sys.symbol.arrow_down', color: COLOR_TEXT_SECONDARY,
        label: this.downloadProgress > 0
          ? str('downloading_pct', this.downloadProgress) : str('downloading'),
        enabled: false, action: (): void => {}
      };
    }
    if (this.downloadFailed) {
      return {
        icon: 'sys.symbol.exclamationmark_circle', color: '#D95B57',
        label: str('download_failed_tap'), enabled: true, action: (): void => { this.onToggle(); }
      };
    }
    // 已在本地：陈述，点一下仍可另存到设备（下载中心之外的那份副本）。
    return this.localReady()
      ? {
        icon: 'sys.symbol.checkmark', color: '#3FA96A',
        label: str('music_downloaded'), enabled: true, action: (): void => { this.onSave(); }
      }
      : {
        icon: 'sys.symbol.arrow_down_circle', color: COLOR_TEXT_SECONDARY,
        label: str('music_save'), enabled: true, action: (): void => { this.onSave(); }
      };
  }

  private favoriteChip(): MusicChipSpec {
    return this.favorited
      ? {
        icon: 'sys.symbol.heart_fill', color: '#E8619D',
        label: str('music_favorited'), enabled: true, action: (): void => { this.onFavorite(); }
      }
      : {
        icon: 'sys.symbol.heart', color: COLOR_TEXT_SECONDARY,
        label: str('music_favorite'), enabled: true, action: (): void => { this.onFavorite(); }
      };
  }

  build() {
    Column({ space: 0 }) {
      // 一行：封面 · 曲名/副标题 · 播放键
      Row({ space: 10 }) {
        this.coverArt();
        Column({ space: 2 }) {
          Text(this.displayTitle())
            .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
          Text(this.subtitleLabel())
            .fontSize(11.5).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start);
        this.playControl();
      }
      .width('100%').alignItems(VerticalAlign.Center);

      // 二行：波形 + 时长。波形按下即定位，和音乐中心的进度条同一套手感。
      Row({ space: 8 }) {
        Row({ space: WAVE_GAP }) {
          ForEach(this.waveBars(), (height: number, index: number): void => {
            Column()
              .width(WAVE_BAR_W)
              .height(Math.max(3, height))
              .borderRadius(WAVE_BAR_W / 2)
              .backgroundColor(index / WAVE_BARS <= this.shownProgress()
                ? this.accent()
                : (this.isOutgoing ? '#4D9FCB98' : '#4DB7CDE3'));
          }, (height: number, index: number): string => `${index}`);
        }
        .layoutWeight(1)
        .height(WAVE_H)
        .alignItems(VerticalAlign.Center)
        .onAreaChange((_old: Area, area: Area): void => {
          this.waveWidth = Math.max(1, Number(area.width));
        })
        .onTouch((event: TouchEvent): void => { this.onWaveTouch(event); });
        Text(this.durationLabel())
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%').margin({ top: 8 })
      .alignItems(VerticalAlign.Center);

      // 分割线：把「保存 / 收藏」这排动作和上面的曲目信息分开（用户 2026-09-18）。
      // 颜色跟着强调色走而不是用 divider 资源——卡片本身已经是一层强调色叠加，
      // 灰线压上去会发脏。
      Divider()
        .color(this.isOutgoing ? '#3355A24D' : '#2E3390EC')
        .strokeWidth(0.8)
        .margin({ top: 9 });

      // 三行：两枚胶囊。时间戳压在气泡右下角，所以这一行右边留空。
      Row({ space: 14 }) {
        this.chip(this.downloadChip());
        this.chip(this.favoriteChip());
      }
      // 时间戳压在气泡右下角，只让这一行让开它——卡片底色仍然铺满整宽。
      .width('100%').margin({ top: 8 })
      .padding({ right: 26 })
      .alignItems(VerticalAlign.Center);
    }
    // 灌满气泡的内容宽（2026-09-18 用户：横向铺满、加底色）。用 maxWidth 而不是
    // 按内容收缩：曲名长短不一，收缩会让同一串音频消息宽窄参差。
    .width(this.maxWidth)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .borderRadius(14)
    // 底色：把音频区和下面的配文分开。用强调色的低透明度叠加，深浅两种模式下
    // 都是"比气泡稍重一档"，不必各配一套实色。
    .backgroundColor(this.isOutgoing ? '#2055A24D' : '#1A3390EC');
  }

  // 播放中显示"已播/总长"，其余显示总长——和设计稿右侧那个 04:12 一致。
  private durationLabel(): string {
    if (this.currentTrack() && !this.finished) {
      return `${formatVoiceDuration(this.elapsedSec)} / ${this.totalLabel()}`;
    }
    return this.totalLabel();
  }

  private onWaveTouch(event: TouchEvent): void {
    if (!this.currentTrack() || this.resolvedDuration() <= 0) {
      return;
    }
    const fraction: number = Math.max(0, Math.min(1, event.touches[0].x / this.waveWidth));
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.dragging = true;
      this.dragProgress = fraction;
      return;
    }
    this.dragging = false;
    this.progress = fraction;
    this.elapsedSec = Math.floor(fraction * this.resolvedDuration());
    this.onSeek(fraction);
  }
}
