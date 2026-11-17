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
  @Param audioItems: DrawnDocumentWidget[] = [];
  @Event onClaim: () => boolean = (): boolean => true;
  @Local private path: string = '';
  @Local private loading: boolean = false;
  @Local private failed: boolean = false;
  @Local private playing: boolean = false;
  @Local private preparing: boolean = false;
  @Local private progress: number = 0;
  @Local private elapsed: number = 0;
  private offFile: (() => void) | null = null;
  private offVoice: (() => void) | null = null;
  private generation: number = 0;
  private visible: boolean = false;
  @Local private pending: boolean = false;
  private detach(): void {
    this.generation++; this.pending = false;
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
        else if (this.preparing) { LoadingProgress().width(30).height(30).color(COLOR_PRIMARY); }
        else { Text(this.playing ? 'Ⅱ' : '▶').fontSize(21).fontColor(COLOR_PRIMARY); }
      }.width(40).height(48).onClick((): void => this.tap())
        .accessibilityLevel('yes').accessibilityText(str(this.playing ? 'lvp_pause' : this.failed ? 'live_media_retry_now' : 'lvp_play'));
      Column({ space: 1 }) {
        Text(this.widget.title || this.widget.name || str('preview_music')).fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${this.widget.performer ?? ''} ${formatVoiceDuration(this.elapsed || (this.widget.duration ?? 0))}`)
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Slider({ value: this.progress, min: 0, max: 1, step: 0.001 }).height(20).width('100%')
          .onChange((fraction: number, mode: SliderChangeMode): void => {
            if ((mode === SliderChangeMode.End || mode === SliderChangeMode.Click) && this.onClaim()) {
              getVoicePlayback().seek(-documentFileId(this.widget.file), fraction);
            }
          });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width(this.boxWidth).height(72)
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } });
  }
}
