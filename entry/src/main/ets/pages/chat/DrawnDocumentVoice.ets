import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentFileId } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { MEDIA_USER_PRIORITY } from '../../util/downloadPriority';
import { getVoicePlayback } from '../../services/VoicePlayback';
import { VoiceBubble } from './VoiceBubble';
import { LiveProgressRing } from './LiveProgressRing';
import { str } from '../../util/strings';

@ComponentV2
export struct DrawnDocumentVoice {
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 0;
  @Event onClaim: () => boolean = (): boolean => true;
  @Local private path: string = '';
  @Local private failed: boolean = false;
  @Local private loading: boolean = false;
  @Local private visible: boolean = false;
  private off: (() => void) | null = null;
  private generation: number = 0;
  private pending: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; this.pending = false; }
  private bind(): void {
    this.detach(); this.path = ''; this.failed = false; this.loading = false;
    const file = this.widget.file; if (file === undefined) { return; }
    const initial = documentFileState(file); this.path = initial.path; this.failed = initial.failed; this.loading = initial.active === true;
    if (!this.visible) { return; }
    const owner = this.generation;
    this.off = watchDocumentFile(file, (state: DocumentFileState): void => {
      if (owner !== this.generation) { return; }
      this.path = state.path; this.failed = state.failed; this.loading = state.active === true;
      if (state.failed) { this.pending = false; }
      if (state.path !== '' && this.pending) {
        this.pending = false;
        getVoicePlayback().toggleDocumentVoice(documentFileId(file), state.path, this.widget.duration ?? 0);
      }
    }, true);
  }
  @Monitor('widget') onSourceChanged(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.detach(); }
  private request(): void {
    if (!this.onClaim() || this.widget.file === undefined || this.loading) { return; }
    this.pending = true; requestDocumentFile(this.widget.file, MEDIA_USER_PRIORITY, true);
  }
  build() {
    Stack() {
      if (this.visible && this.path !== '') {
        VoiceBubble({ msgId: -documentFileId(this.widget.file), documentFileId: documentFileId(this.widget.file),
          allowTranscription: false, onBeforeControl: (): boolean => this.onClaim(),
          waveformWidth: Math.max(24, Math.min(132, this.boxWidth - 84)),
          durationSec: this.widget.duration ?? 0, waveform: this.widget.waveform ?? '', voiceFileId: documentFileId(this.widget.file),
          voicePath: this.path, onNeedDownload: (): void => this.request() });
      } else if (this.loading) {
        LiveProgressRing({ fileId: documentFileId(this.widget.file), ringSize: 34 });
      } else {
        Button(str(this.failed ? 'live_media_retry_now' : 'preview_voice')).onClick((): void => this.request());
      }
    }.width(this.boxWidth).height(72)
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } });
  }
}
