import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { VoiceBubble } from './VoiceBubble';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';

// Android separates document layout from its radial transfer state. Keep the
// existing file actions in a local island; progress never enters the row plan.
@ComponentV2
export struct DrawnVoiceMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Param boxWidth: number = 262;
  @Param sendState: string = '';
  @Event onClaim: () => boolean = (): boolean => false;
  @Local private progress: number = 0;
  private off: (() => void) | null = null;
  private generation: number = 0;
  private active: boolean = false;

  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  private bind(): void {
    this.detach();
    this.progress = progressForOr(this.msg.videoFileId, this.msg.videoProgress);
    if (!this.active) { return; }
    const generation = this.generation;
    this.off = subscribeProgress(this.msg.videoFileId, (progress: number): void => {
      if (generation === this.generation && this.progress !== progress) { this.progress = progress; }
    });
  }
  @Computed private get sourceIdentity(): string { return `${this.msg.id}:${this.msg.videoFileId}`; }
  @Monitor('sourceIdentity') private sourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.active = true; this.bind(); }
  aboutToReuse(): void { this.active = true; this.bind(); }
  aboutToRecycle(): void { this.active = false; this.detach(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }

  build() {
    VoiceBubble({ msgId: this.msg.id, durationSec: this.msg.videoDuration, isOutgoing: this.msg.isOutgoing,
      voiceFileId: this.msg.videoFileId, voicePath: this.msg.videoPath, downloadProgress: this.progress,
      downloadFailed: this.msg.videoFailed, waveform: this.msg.voiceWaveform, listened: this.msg.voiceListened,
      waveformWidth: Math.max(1, this.boxWidth - 78), allowTranscription: false,
      onBeforeControl: (): boolean => this.sendState !== 'sending' && this.onClaim(),
      onNeedDownload: (): void => { this.actions.onVoiceTap(this.msg.id); },
      onPlaybackStarted: (): void => { this.actions.onVoicePlaybackStarted(this.msg.id); }
    });
  }
}
