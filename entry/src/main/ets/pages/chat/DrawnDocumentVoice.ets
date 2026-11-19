import { DrawnDocumentCardLayout } from './DrawnDocumentCardLayout';
import { DrawnCardBar } from './DrawnCardBar';
import { COLOR_PRIMARY } from '../../util/theme';
import { DrawnMediaTexts, DrawnMediaTextPlan, DrawnMediaTextPainter } from './DrawnMediaText';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentFileId } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { MEDIA_USER_PRIORITY } from '../../util/downloadPriority';
import { getVoicePlayback } from '../../services/VoicePlayback';
import { VoiceBubble } from './VoiceBubble';
import { LiveProgressRing } from './LiveProgressRing';
import { str } from '../../util/strings';

@Styles
function documentVoiceNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }
@Styles
function documentVoicePressedStyle() { .scale({ x: .98, y: .98 }).opacity(.82) }

@ComponentV2
export struct DrawnDocumentVoice {
  private paintEnv = chatEnv;
  private labels: DrawnMediaTexts = new DrawnMediaTexts();
  private labelPainter: DrawnMediaTextPainter = new DrawnMediaTextPainter();
  private buttonPainter: DrawnCardBar = new DrawnCardBar();
  @Computed private get paintEnvironment(): string {
    return `${this.paintEnv.appearanceEpoch}:${this.paintEnv.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get buttonWidth(): number { return Math.min(Math.max(1, this.boxWidth), this.labelPlan.width + 32); }
  @Computed private get buttonHeight(): number { return Math.max(40, this.labelPlan.height + 16); }
  private requestCallback(): () => void {
    const generation = this.generation;
    return (): void => { if (generation === this.generation) { this.request(); } };
  }
  @Computed private get labelPlan(): DrawnMediaTextPlan {
    return (this.preparedCard?.labels ?? this.labels).prepare(this.getUIContext(),
      this.preparedCard?.environment ?? this.paintEnvironment,
      Math.max(1, this.boxWidth - 32), str(this.failed ? 'live_media_retry_now' : 'preview_voice'),
      16, '#FFFFFF', '', 11, '#FFFFFF', 1, true, 0, 0, true);
  }
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 0;
  @Param preparedCard: DrawnDocumentCardLayout | undefined = undefined;
  @Event onClaim: () => boolean = (): boolean => true;
  @Local private path: string = '';
  @Local private failed: boolean = false;
  @Local private loading: boolean = false;
  @Local private visible: boolean = false;
  private off: (() => void) | null = null;
  @Local private generation: number = 0;
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
    if (!this.onClaim() || this.widget.file === undefined || this.loading || this.pending) { return; }
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
        Button() {
          Row().width(this.labelPlan.width).height(Math.min(this.labelPlan.height, this.buttonHeight - 16))
            .hitTestBehavior(HitTestMode.None)
            .drawModifier(this.labelPainter.bind(this.labelPlan, this.buttonHeight - 16));
        }
        .width(this.buttonWidth).height(this.buttonHeight).padding(0).backgroundColor('#00000000')
        .drawModifier(this.buttonPainter.bind(this.getUIContext(), {
          width: this.buttonWidth, height: this.buttonHeight, environment: this.paintEnvironment,
          background: COLOR_PRIMARY, radius: this.buttonHeight / 2
        }))
        .stateStyles({ normal: documentVoiceNormalStyle, pressed: documentVoicePressedStyle })
        .accessibilityText(str(this.failed ? 'live_media_retry_now' : 'preview_voice'))
        .onClick(this.requestCallback());
      }
    }.width(this.boxWidth).height(this.preparedCard?.height ?? 72)
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } });
  }
}
