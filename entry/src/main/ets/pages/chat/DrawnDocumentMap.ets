import { TdObject } from '../../tdkit/TdTypes';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentMapFile } from '../../util/documentMapCache';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { str } from '../../util/strings';

@ComponentV2
export struct DrawnDocumentMap {
  @Require @Param widget: DrawnDocumentWidget;
  @Param chatId: number = 0;
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Event onOpen: () => void = (): void => {};
  @Local private path: string = '';
  private off: (() => void) | null = null;
  private generation: number = 0;
  private visible: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  private bind(): void {
    this.detach(); this.path = '';
    if (!this.visible) { return; }
    const owner = this.generation;
    documentMapFile(this.widget, this.chatId, this.boxWidth, this.boxHeight).then((file: TdObject): void => {
      if (owner !== this.generation || !this.visible) { return; }
      this.path = documentFileState(file).path;
      this.off = watchDocumentFile(file, (state: DocumentFileState): void => { if (owner === this.generation) { this.path = state.path; } });
      requestDocumentFile(file, THUMBNAIL_PRIORITY);
    }).catch((): void => { /* The coordinate/pin remains actionable without a thumbnail. */ });
  }
  @Monitor('widget', 'chatId', 'boxWidth', 'boxHeight') onSourceChanged(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.detach(); }
  build() {
    Stack() {
      if (this.path !== '') { Image(`file://${this.path}`).width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Cover).draggable(false); }
      SymbolGlyph($r('sys.symbol.mappin_and_rectangle')).fontSize(30).fontColor(['#DD534D']).hitTestBehavior(HitTestMode.None);
    }.width(this.boxWidth).height(this.boxHeight).backgroundColor($r('app.color.surface_alt')).clip(true)
      .accessibilityText(`${str('loc_location')} ${this.widget.latitude}, ${this.widget.longitude}`)
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } })
      .onClick((): void => this.onOpen());
  }
}
