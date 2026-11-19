import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { fileCardFor } from './DrawnFileCardLayout';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { FileBubble } from './FileBubble';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';

// Android separates document layout from its radial transfer state. Keep the
// existing file actions in a local island; progress never enters the row plan.
@ComponentV2
export struct DrawnFileMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Param widget: DrawnDocumentWidget | undefined = undefined;
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
    FileBubble({ fileId: this.msg.videoFileId, fileName: this.msg.videoFileName,
      mimeType: this.msg.videoMimeType, fileSize: this.msg.videoFileSize, filePath: this.msg.videoPath,
      downloadProgress: this.progress, downloadFailed: this.msg.videoFailed,
      downloadActive: this.msg.mediaDownloadActive, uploading: this.sendState === 'sending',
      thumbnailId: this.msg.photoFileId, thumbnailPath: this.msg.photoPath, mini: this.msg.photoMini,
      preparedCard: fileCardFor(this.widget), maxWidth: this.boxWidth, fitAvailableWidth: true,
      onOpen: (): void => { if (this.onClaim()) { this.actions.onFileTap(this.msg.id); } },
      onSave: (): void => { if (this.onClaim()) { this.actions.onFileSave(this.msg.id); } },
      onPause: (): void => { if (this.onClaim()) { this.actions.onFilePause(this.msg.id); } }
    });
  }
}
