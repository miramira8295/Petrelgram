import { FileBubble } from './FileBubble';
import { DrawnDocumentCardLayout } from './DrawnDocumentCardLayout';
import { documentFilePath } from '../../util/drawnDocumentMedia';
import { subscribeProgress, progressForOr } from '../../util/mediaProgressChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { common } from '@kit.AbilityKit';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentFileId } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, cancelDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { MEDIA_USER_PRIORITY } from '../../util/downloadPriority';
import { fileOpenMimeType } from '../../util/fileMessage';
import { openLocalFile } from '../../util/openLocalFile';
import { downloadSaveService } from '../../services/DownloadSaveNotification';
import { showToast } from '../../util/toast';

@ComponentV2
export struct DrawnDocumentFile {
  @Require @Param widget: DrawnDocumentWidget;
  @Param chatId: number = 0;
  @Param messageId: number = 0;
  @Param boxWidth: number = 0;
  @Event onClaim: () => boolean = (): boolean => true;
  @Param preparedCard: DrawnDocumentCardLayout | undefined = undefined;
  @Local private progress: number = 0;
  @Local private thumbnailPath: string = '';
  private offThumb: (() => void) | null = null;
  private offProgress: (() => void) | null = null;
  @Local private path: string = '';
  @Local private failed: boolean = false;
  @Local private downloading: boolean = false;
  private off: (() => void) | null = null;
  private generation: number = 0;
  private pending: string = '';
  private opening: boolean = false;
  private visible: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; this.offProgress?.(); this.offProgress = null; this.offThumb?.(); this.offThumb = null; this.pending = ''; this.opening = false; }
  private bind(): void {
    this.detach(); this.thumbnailPath = documentFilePath(this.widget.thumbnailFile); this.path = ''; this.failed = false; this.downloading = false;
    const file = this.widget.file; if (file === undefined) { return; }
    const state = documentFileState(file); this.path = state.path; this.failed = state.failed; this.downloading = state.active === true;
    this.progress = progressForOr(documentFileId(file), state.progress);
    if (!this.visible) { return; }
    const owner = this.generation;
    this.offProgress = subscribeProgress(documentFileId(file), (value: number): void => {
      if (owner === this.generation && this.progress !== value) { this.progress = value; }
    });
    // Covers use their own request/receiver; never download the original here.
    if (this.widget.thumbnailFile !== undefined) {
      this.thumbnailPath = documentFileState(this.widget.thumbnailFile).path;
      this.offThumb = watchDocumentFile(this.widget.thumbnailFile, (next: DocumentFileState): void => {
        if (owner === this.generation && this.thumbnailPath !== next.path) { this.thumbnailPath = next.path; }
      });
      requestDocumentFile(this.widget.thumbnailFile, THUMBNAIL_PRIORITY);
    }
    this.off = watchDocumentFile(file, (next: DocumentFileState): void => {
      if (owner !== this.generation) { return; }
      this.path = next.path; this.failed = next.failed; this.downloading = next.active === true;
      if (next.failed) { this.pending = ''; }
      if (next.path !== '' && this.pending !== '') {
        const save = this.pending === 'save'; this.pending = ''; this.open(save);
      }
    }, true);
  }
  @Monitor('widget') onSourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.detach(); }
  private open(save: boolean): void {
    if (this.path === '' || this.opening) { return; }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (save) { downloadSaveService.saveDownloadedFile(context, this.path, this.widget.name); return; }
    this.opening = true; const owner = this.generation;
    openLocalFile(context, this.path, fileOpenMimeType(this.widget.name, this.widget.mimeType)).then((opened: boolean): void => {
      if (owner !== this.generation) { return; }
      this.opening = false;
      if (!opened) { showToast($r('app.string.cp_no_app_for_file'), 1800); }
    });
  }
  private tap(save: boolean): void {
    if (!this.onClaim() || this.widget.file === undefined) { return; }
    if (this.path !== '') { this.open(save); return; }
    if (save) {
      this.pending = '';
      downloadSaveService.saveRemoteFile(this.getUIContext().getHostContext() as common.UIAbilityContext,
        documentFileId(this.widget.file), this.chatId, this.messageId, this.widget.name);
      return;
    }
    if (this.downloading) { this.pending = ''; cancelDocumentFile(this.widget.file); return; }
    this.pending = save ? 'save' : 'open';
    requestDocumentFile(this.widget.file, MEDIA_USER_PRIORITY, true);
  }
  build() {
    FileBubble({ fileId: documentFileId(this.widget.file), fileName: this.widget.name,
      mimeType: this.widget.mimeType, fileSize: this.widget.size, filePath: this.path,
      thumbnailId: documentFileId(this.widget.thumbnailFile), thumbnailPath: this.thumbnailPath,
      mini: this.widget.thumbnailMini ?? '', preparedCard: this.preparedCard?.file,
      downloadProgress: this.progress, downloadFailed: this.failed, downloadActive: this.downloading,
      maxWidth: this.boxWidth, fitAvailableWidth: true,
      onOpen: (): void => this.tap(false), onPause: (): void => this.tap(false), onSave: (): void => this.tap(true) })
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } });
  }
}
