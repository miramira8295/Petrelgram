import { common } from '@kit.AbilityKit';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentFileId } from '../../util/drawnDocumentMedia';
import { documentFileState, watchDocumentFile, requestDocumentFile, cancelDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { MEDIA_USER_PRIORITY } from '../../util/downloadPriority';
import { fileOpenMimeType, displayFileName } from '../../util/fileMessage';
import { formatFileSize } from '../../util/formatFileSize';
import { openLocalFile } from '../../util/openLocalFile';
import { downloadSaveService } from '../../services/DownloadSaveNotification';
import { showToast } from '../../util/toast';
import { str } from '../../util/strings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LiveProgressRing } from './LiveProgressRing';

@ComponentV2
export struct DrawnDocumentFile {
  @Require @Param widget: DrawnDocumentWidget;
  @Param chatId: number = 0;
  @Param messageId: number = 0;
  @Param boxWidth: number = 0;
  @Event onClaim: () => boolean = (): boolean => true;
  @Local private path: string = '';
  @Local private failed: boolean = false;
  @Local private downloading: boolean = false;
  private off: (() => void) | null = null;
  private generation: number = 0;
  private pending: string = '';
  private opening: boolean = false;
  private visible: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; this.pending = ''; this.opening = false; }
  private bind(): void {
    this.detach(); this.path = ''; this.failed = false; this.downloading = false;
    const file = this.widget.file; if (file === undefined) { return; }
    const state = documentFileState(file); this.path = state.path; this.failed = state.failed; this.downloading = state.active === true;
    if (!this.visible) { return; }
    const owner = this.generation;
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
    Row({ space: 10 }) {
      Stack() {
        if (this.downloading) { LiveProgressRing({ fileId: documentFileId(this.widget.file), ringSize: 38 }); }
        else { SymbolGlyph(this.failed ? $r('sys.symbol.arrow_clockwise') : this.path !== '' ? $r('sys.symbol.doc') : $r('sys.symbol.arrow_down'))
          .fontSize(26).fontColor([COLOR_PRIMARY]); }
      }.width(44).height(44);
      Column({ space: 4 }) {
        Text(displayFileName(this.widget.name)).fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Text(this.failed ? str('download_failed_tap') : formatFileSize(this.widget.size)).fontSize(11)
          .fontColor(COLOR_TEXT_SECONDARY).maxLines(1).width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.square_and_arrow_down')).fontSize(18); }
        .width(32).height(32).accessibilityText(str('file_save_as')).onClick((): void => this.tap(true));
    }.width(this.boxWidth).height(72).padding(8).borderRadius(8)
      .onClick((): void => this.tap(false))
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } });
  }
}
