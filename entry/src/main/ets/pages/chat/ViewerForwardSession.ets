import { TdObject } from '../../tdkit/TdTypes';
import { VideoPlaybackControls } from '../../util/floatingVideoRuntime';
import { pushSheetDismiss } from '../../util/sheetDismissStack';

// Viewer IDs from downloads/documents are synthetic: resolve to the original
// message before opening the picker. Never send a local row ID to TDLib.
export interface ViewerForwardSource {
  chatId: number;
  messageId: number;
  threadRootId: number;
  canRemoveCaption: boolean;
}

export interface ViewerForwardHost {
  // false = media with caption; true = media only; null = cancelled.
  choose: () => Promise<boolean | null>;
  properties: (source: ViewerForwardSource) => Promise<TdObject>;
  isCurrent: () => boolean;
  controls: () => VideoPlaybackControls | null;
  denied: () => void;
  failed: (error: Object) => void;
}

// One request and one fixed-size source snapshot per user action. No timeline
// traversal, media decoding, polling or per-frame state writes.
@ObservedV2
export class ViewerForwardSession {
  @Trace source: ViewerForwardSource | null = null;
  @Trace checking: boolean = false;
  removeCaption: boolean = false;
  private epoch: number = 0;
  private unregister: (() => void) | null = null;
  private resume: (() => void) | null = null;

  open(candidate: ViewerForwardSource | null, host: ViewerForwardHost): void {
    if (this.checking || this.source !== null || candidate === null ||
      candidate.chatId === 0 || candidate.messageId <= 0 || !host.isCurrent()) { return; }
    const source: ViewerForwardSource = { chatId: candidate.chatId, messageId: candidate.messageId,
      threadRootId: candidate.threadRootId, canRemoveCaption: candidate.canRemoveCaption };
    const epoch: number = ++this.epoch;
    this.checking = true;
    this.unregister = pushSheetDismiss((): void => { this.close(); });
    this.prepare(source, host, epoch);
  }

  private async prepare(source: ViewerForwardSource, host: ViewerForwardHost, epoch: number): Promise<void> {
    try {
      const choice: boolean | null = await host.choose();
      if (epoch !== this.epoch) { return; }
      if (choice === null || !host.isCurrent()) { this.close(false); return; }
      const properties: TdObject = await host.properties(source);
      if (epoch !== this.epoch) { return; }
      if (!host.isCurrent()) { this.close(false); return; }
      if (properties['can_be_forwarded'] !== true) {
        this.close(false);
        host.denied();
        return;
      }
      const controls: VideoPlaybackControls | null = host.controls();
      if (controls?.snapshot()?.playing === true) {
        controls.toggle();
        this.resume = (): void => {
          if (host.isCurrent() && host.controls() === controls && controls.snapshot()?.playing === false) {
            controls.toggle();
          }
        };
      }
      this.removeCaption = choice;
      this.checking = false;
      this.source = source;
    } catch (error) {
      if (epoch !== this.epoch) { return; }
      const current: boolean = host.isCurrent();
      this.close(false);
      if (current) { host.failed(error as Object); }
    }
  }

  close(resumePlayback: boolean = true): void {
    this.epoch++;
    this.unregister?.();
    this.unregister = null;
    this.checking = false;
    this.source = null;
    this.removeCaption = false;
    const resume: (() => void) | null = this.resume;
    this.resume = null;
    if (resumePlayback) { resume?.(); }
  }
}
