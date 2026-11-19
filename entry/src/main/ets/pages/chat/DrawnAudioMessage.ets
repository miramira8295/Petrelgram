import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { musicCardFor } from './DrawnMusicCardLayout';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { MusicBubble } from './MusicBubble';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';

// Android separates document layout from its radial transfer state. Keep the
// existing file actions in a local island; progress never enters the row plan.
@ComponentV2
export struct DrawnAudioMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Param boxWidth: number = 262;
  @Param widget: DrawnDocumentWidget | undefined = undefined;
  @Require @Param data: MessageBubbleRenderData;
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
    MusicBubble({ preparedCard: musicCardFor(this.widget), msgId: this.msg.id, durationSec: this.msg.videoDuration, isOutgoing: this.msg.isOutgoing,
      audioFileId: this.msg.videoFileId, audioPath: this.msg.videoPath, fileSize: this.msg.videoFileSize,
      fileName: this.msg.videoFileName, title: this.msg.audioTitle, performer: this.msg.audioPerformer,
      coverPath: this.msg.photoPath, coverMini: this.msg.audioCoverMini, coverFailed: this.msg.photoFailed,
      downloadProgress: this.progress, downloadFailed: this.msg.videoFailed, downloadActive: this.msg.mediaDownloadActive,
      queuePosition: this.data.audioQueuePosition, queueLength: this.data.audioQueueLength,
      hasPrevious: this.data.audioHasPrevious, hasNext: this.data.audioHasNext, maxWidth: this.boxWidth,
      chatId: this.data.chatId, mimeType: this.msg.videoMimeType,
      onToggle: (): void => { if (this.onClaim()) { this.actions.onAudioTap(this.msg.id); } },
      onPrevious: (): void => { if (this.onClaim()) { this.actions.onAudioPrevious(this.msg.id); } },
      onNext: (): void => { if (this.onClaim()) { this.actions.onAudioNext(this.msg.id); } },
      onBeforeSeek: (): boolean => this.onClaim(),
      onSeek: (fraction: number): void => { this.actions.onAudioSeek(this.msg.id, fraction); },
      onSave: (): void => { if (this.onClaim()) { this.actions.onAudioSave(this.msg.id); } },
      onFavorite: (): void => { if (this.onClaim()) { this.actions.onAudioFavorite(this.msg.id); } }
    });
  }
}
