import { DrawnDocumentCardLayout } from './DrawnDocumentCardLayout';
import { DrawnSeekTrack } from './DrawnSeekTrack';
import { DrawnMediaTexts, DrawnMediaTextPlan, DrawnMediaTextPainter } from './DrawnMediaText';
import { DrawnMediaControl } from './DrawnMediaControl';
import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentFileId } from '../../util/drawnDocumentMedia';
import { documentAudioTrack, documentAudioPlaylist } from '../../util/documentAudioTrack';
import { documentFileState, watchDocumentFile, requestDocumentFile, cancelDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { MEDIA_USER_PRIORITY } from '../../util/downloadPriority';
import { getVoicePlayback, VoiceState, localAudioSource, streamAudioSource, audioSourcePlayable } from '../../services/VoicePlayback';
import { publishNowPlaying } from '../../util/nowPlayingChannel';
import { formatVoiceDuration } from '../../util/voiceWaveform';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnDocumentAudioCover } from './DrawnDocumentAudioCover';
import { cachedMusicCover } from '../../services/MusicCoverCache';
import { LiveProgressRing } from './LiveProgressRing';

// Local island: download/playback clocks never invalidate the row paragraph.
@ComponentV2
export struct DrawnDocumentAudio {
  @Require @Param widget: DrawnDocumentWidget;
  @Param chatId: number = 0;
  @Param messageId: number = 0;
  @Param boxWidth: number = 0;
  @Param preparedCard: DrawnDocumentCardLayout | undefined = undefined;
  @Param audioItems: DrawnDocumentWidget[] = [];
  @Event onClaim: () => boolean = (): boolean => true;
  private env = chatEnv;
  private labels: DrawnMediaTexts = new DrawnMediaTexts();
  private labelPainter: DrawnMediaTextPainter = new DrawnMediaTextPainter();
  private controlPainter: DrawnMediaControl = new DrawnMediaControl();
  private seekPainter: DrawnSeekTrack = new DrawnSeekTrack();
  @Local private seekDragging: boolean = false;
  @Local private seekProgress: number = 0;
  private seekGranted: boolean = false;
  private seekGesture: boolean = false;
  @Computed private get shownSeekProgress(): number { return this.seekDragging ? this.seekProgress : this.progress; }
  @Computed private get seekWidth(): number { return Math.max(1, this.boxWidth - 48); }
  @Computed private get seekInset(): number { return Math.min(8, this.seekWidth / 2); }
  private seekCallback(): (fraction: number, mode: SliderChangeMode) => void {
    // generation is a local state root so a rebind refreshes this callback even
    // when the same file stays mounted after a visibility/account transition.
    const generation = this.generation, fileId = documentFileId(this.widget.file);
    return (fraction: number, mode: SliderChangeMode): void => {
      if (generation !== this.generation || fileId <= 0 || !Number.isFinite(fraction)) { return; }
      const value = Math.max(0, Math.min(1, fraction));
      if (mode === SliderChangeMode.Begin) {
        this.seekGesture = true; this.seekGranted = this.onClaim(); this.seekDragging = this.seekGranted;
        if (this.seekGranted) { this.seekProgress = value; }
      } else if (mode === SliderChangeMode.Moving) {
        if (this.seekGranted && this.seekProgress !== value) { this.seekProgress = value; }
      } else if (mode === SliderChangeMode.End) {
        const granted = this.seekGranted; this.seekGesture = false; this.seekGranted = false;
        if (granted && this.progress !== value) { this.progress = value; }
        this.seekDragging = false;
        if (granted) { getVoicePlayback().seek(-fileId, value); }
      } else if (mode === SliderChangeMode.Click) {
        const granted = this.seekGesture ? this.seekGranted : this.onClaim();
        this.seekGesture = false; this.seekGranted = false;
        if (granted && this.progress !== value) { this.progress = value; }
        this.seekDragging = false;
        if (granted) { getVoicePlayback().seek(-fileId, value); }
      }
    };
  }
  @Computed private get paintEnvironment(): string {
    return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get titleLabel(): string { return this.widget.title || this.widget.name || str('preview_music'); }
  @Computed private get subtitleLabel(): string {
    return `${this.widget.performer ?? ''} ${formatVoiceDuration(this.elapsed || (this.widget.duration ?? 0))}`;
  }
  @Computed private get labelPlan(): DrawnMediaTextPlan {
    return (this.preparedCard?.labels ?? this.labels).prepare(this.getUIContext(), this.preparedCard?.environment ?? this.paintEnvironment, Math.max(1, this.boxWidth - 48),
      this.titleLabel, 14, COLOR_TEXT_PRIMARY, this.subtitleLabel, 11, COLOR_TEXT_SECONDARY, 1, false, 1);
  }
  @Local private path: string = '';
  @Local private loading: boolean = false;
  @Local private failed: boolean = false;
  @Local private playing: boolean = false;
  @Local private preparing: boolean = false;
  @Local private progress: number = 0;
  @Local private elapsed: number = 0;
  private offFile: (() => void) | null = null;
  private offVoice: (() => void) | null = null;
  @Local private generation: number = 0;
  private visible: boolean = false;
  @Local private pending: boolean = false;
  private detach(): void {
    this.generation++; this.pending = false;
    this.seekGranted = false; this.seekGesture = false;
    if (this.seekDragging) { this.seekDragging = false; }
    if (this.seekProgress !== 0) { this.seekProgress = 0; }
    this.offFile?.(); this.offFile = null; this.offVoice?.(); this.offVoice = null;
  }
  private bind(): void {
    this.detach(); this.path = ''; this.loading = false; this.failed = false;
    this.playing = false; this.preparing = false; this.progress = 0; this.elapsed = 0;
    const file = this.widget.file; if (file === undefined) { return; }
    const initial = documentFileState(file);
    this.path = initial.path; this.loading = initial.active === true; this.failed = initial.failed;
    if (!this.visible) { return; }
    const owner = this.generation, id = -documentFileId(file);
    this.offFile = watchDocumentFile(file, (state: DocumentFileState): void => {
      if (owner !== this.generation) { return; }
      if (this.path !== state.path) { this.path = state.path; }
      if (this.loading !== (state.active === true)) { this.loading = state.active === true; }
      if (this.failed !== state.failed) { this.failed = state.failed; }
      if (state.failed) { this.pending = false; }
      if (state.path !== '' && this.pending) {
        this.pending = false;
        if (this.onClaim()) { this.play(); }
      }
    }, true);
    this.offVoice = getVoicePlayback().subscribe((state: VoiceState): void => {
      if (owner !== this.generation) { return; }
      const mine = state.mode === 'music' && state.playingId === id;
      const playing = mine && state.status === 'playing', preparing = mine && state.status === 'loading';
      const progress = mine && state.durationMs > 0 ? Math.max(0, Math.min(1, state.positionMs / state.durationMs)) : 0;
      const elapsed = mine ? Math.floor(state.positionMs / 1000) : 0;
      if (this.playing !== playing) { this.playing = playing; }
      if (this.preparing !== preparing) { this.preparing = preparing; }
      if (this.progress !== progress) { this.progress = progress; }
      if (this.elapsed !== elapsed) { this.elapsed = elapsed; }
    });
  }
  @Monitor('widget', 'chatId', 'messageId') onSourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.detach(); }
  private play(): void {
    const track = documentAudioTrack(this.widget, this.chatId, this.messageId, this.path);
    const source = this.path !== '' ? localAudioSource(this.path) : streamAudioSource(track.fileId, track.fileSize, track.mimeType);
    if (!audioSourcePlayable(source)) {
      if (this.widget.file !== undefined) { this.pending = true; requestDocumentFile(this.widget.file, MEDIA_USER_PRIORITY, true); }
      return;
    }
    const playlist = documentAudioPlaylist(this.audioItems, this.chatId, this.messageId);
    getVoicePlayback().setDocumentPlaylist(playlist);
    getVoicePlayback().toggleDocumentMusic(track.fileId, source, track.durationSec);
    publishNowPlaying({ chatId: track.chatId, messageId: track.messageId, sourceMessageId: track.sourceMessageId,
      documentTrack: track, documentPlaylist: playlist, title: track.title, performer: track.artist, coverPath: cachedMusicCover(track.coverFileId), path: track.localPath, durationSec: track.durationSec });
  }
  private tap(): void {
    if (!this.onClaim()) { return; }
    if (this.pending && this.loading && this.widget.file !== undefined) {
      this.pending = false; cancelDocumentFile(this.widget.file); return;
    }
    this.play();
  }
  build() {
    Row({ space: 8 }) {
      Stack() {
        DrawnDocumentAudioCover({ fileId: this.widget.coverFileId ?? 0, mini: this.widget.coverMini ?? '' });
        if (this.pending && this.loading) { LiveProgressRing({ fileId: documentFileId(this.widget.file), ringSize: 36 }); }
        else if (this.preparing) { DrawnLoadingSpinner({ ringSize: 30, ringColor: COLOR_PRIMARY }); }
        else { Row().width(40).height(40).hitTestBehavior(HitTestMode.None)
          .drawModifier(this.controlPainter.bind(this.getUIContext(), this.paintEnvironment, 40,
            '#00000000', COLOR_PRIMARY, this.playing ? 'pause' : 'play')); }
      }.width(40).height(48).onClick((): void => this.tap())
        .accessibilityLevel('yes').accessibilityText(str(this.playing ? 'lvp_pause' : this.failed ? 'live_media_retry_now' : 'lvp_play'));
      Column({ space: 1 }) {
        Row().width(this.labelPlan.width).height(this.labelPlan.height)
          .drawModifier(this.labelPainter.bind(this.labelPlan))
          .accessibilityText(`${this.titleLabel}. ${this.subtitleLabel}`);
        // NONE removes native thumb/shadow; transparent tracks keep the native
        // input and value semantics without duplicate visuals or a new host.
        Slider({ value: this.shownSeekProgress, min: 0, max: 1, step: 0.001, style: SliderStyle.NONE })
          .height(20).width('100%').padding({ left: this.seekInset, right: this.seekInset })
          .trackColor('#00000000').selectedColor('#00000000').trackThickness(2)
          .drawModifier(this.seekPainter.bind(this.getUIContext(), this.paintEnvironment, this.seekWidth, 20,
            this.shownSeekProgress, this.seekDragging, COLOR_PRIMARY, '#4DB7CDE3'))
          .onChange(this.seekCallback());
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width(this.boxWidth).height(this.preparedCard?.height ?? 72)
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } });
  }
}
