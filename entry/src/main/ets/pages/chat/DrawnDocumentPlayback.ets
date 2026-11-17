import { DrawnDocumentMedia } from '../../util/drawnDocumentMedia';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { DocumentPlaybackLease } from '../../util/documentPlaybackLease';
import { subscribeChatAnimationGate, chatAnimationSuspended } from '../../util/chatAnimationGate';
import { subscribeSenderAnimationPark, senderAnimationsParked } from '../../util/senderAnimationPark';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { MEDIA_PREFETCH_PRIORITY } from '../../util/downloadPriority';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { VideoBubbleSurface } from './VideoBubbleSurface';

// Lifecycle and download changes are confined to this media island. Ordinary
// videos use the existing streaming player; only GIFs request a whole file.
@ComponentV2
export struct DrawnDocumentPlayback {
  @Require @Param media: DrawnDocumentMedia;
  @Param pageActive: boolean = true;
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Param posterPath: string = '';
  @Local private active: boolean = false;
  @Local private animationPath: string = '';
  private env: ChatEnvMirror = chatEnv;
  private visible: boolean = false;
  private attached: boolean = false;
  private suspended: boolean = true;
  private parked: boolean = false;
  private failed: boolean = false;
  private generation: number = 0;
  private offGate: (() => void) | null = null;
  private offPark: (() => void) | null = null;
  private offFile: (() => void) | null = null;
  private lease: DocumentPlaybackLease = new DocumentPlaybackLease((active: boolean): void => {
    this.active = active;
    if (active) { this.loadAnimation(); } else { this.generation++; this.offFile?.(); this.offFile = null; }
  });
  @Computed private get autoAllowed(): boolean {
    return !this.env.powerSaving && !this.env.reduceAnim &&
      (this.media.kind === 'animation' ? this.env.autoplayGif : this.env.autoplayVideo);
  }
  private sync(): void {
    this.lease.update(this.attached && this.pageActive && this.visible && !this.parked && !this.failed && this.autoAllowed, this.suspended);
  }
  @Monitor('autoAllowed', 'pageActive') onPolicyChanged(): void { this.sync(); }
  @Monitor('media') onSourceChanged(): void {
    this.generation++; this.lease.dispose(); this.offFile?.(); this.offFile = null;
    this.animationPath = ''; this.failed = false; this.sync();
  }
  private loadAnimation(): void {
    if (this.media.kind !== 'animation' || this.offFile !== null) { return; }
    const owner = this.generation, file = this.media.file;
    this.animationPath = documentFileState(file).path;
    this.offFile = watchDocumentFile(file, (state: DocumentFileState): void => {
      if (owner !== this.generation || !this.active) { return; }
      this.animationPath = state.path;
      if (state.failed) { this.failed = true; this.sync(); }
    });
    requestDocumentFile(file, MEDIA_PREFETCH_PRIORITY);
  }
  aboutToAppear(): void {
    this.attached = true; this.suspended = chatAnimationSuspended(); this.parked = senderAnimationsParked();
    this.offGate = subscribeChatAnimationGate((paused: boolean): void => { this.suspended = paused; this.sync(); }, (): boolean => this.visible);
    this.offPark = subscribeSenderAnimationPark((parked: boolean): void => { this.parked = parked; this.sync(); });
  }
  aboutToDisappear(): void {
    this.attached = false; this.visible = false; this.generation++; this.lease.dispose();
    this.offGate?.(); this.offGate = null; this.offPark?.(); this.offPark = null; this.offFile?.(); this.offFile = null;
  }
  private completionFor(owner: DrawnDocumentMedia, generation: number): () => void {
    return (): void => {
      if (this.media !== owner || this.generation !== generation || !this.active) { return; }
      this.failed = true; this.sync();
    };
  }
  build() {
    Stack() {
      if (this.active && this.media.kind === 'video') {
        VideoBubbleSurface({ fileId: this.media.file['id'] as number, fileSize: this.media.size,
          mimeType: this.media.mimeType, sourceWidth: this.media.width, sourceHeight: this.media.height,
          posterPath: this.posterPath, loopPlayback: true, onEnded: this.completionFor(this.media, this.generation) })
          .width(this.boxWidth).height(this.boxHeight).hitTestBehavior(HitTestMode.None);
      } else if (this.active && this.animationPath !== '') {
        SmartLoopVideo({ videoPath: this.animationPath, thumbPath: this.posterPath,
          boxWidth: this.boxWidth, boxHeight: this.boxHeight, powerCategory: 'gif', scrollGated: true,
          onPlaybackFailed: this.completionFor(this.media, this.generation) }).hitTestBehavior(HitTestMode.None);
      }
    }.width(this.boxWidth).height(this.boxHeight).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
    .onVisibleAreaChange([0, 0.5], (visible: boolean, ratio: number): void => {
      const next = visible && ratio >= 0.5;
      if (this.visible !== next) { this.visible = next; this.sync(); }
    });
  }
}
