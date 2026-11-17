import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';

// ArticleViewer's 44vp related-article thumbnail. Text/hit target stay in Canvas.
// Avatar delivery updates this island only; no row paragraph invalidation.
@ComponentV2
export struct DrawnDocumentArticleImage {
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 44;
  @Param boxHeight: number = 44;
  @Local private path: string = '';
  private off: (() => void) | null = null;
  private generation: number = 0;
  private visible: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  private bind(): void {
    this.detach(); this.path = '';
    const file = this.widget.avatar;
    if (file === undefined) { return; }
    this.path = documentFileState(file).path;
    if (!this.visible) { return; }
    const owner = this.generation;
    this.off = watchDocumentFile(file, (state: DocumentFileState): void => {
      if (owner === this.generation && this.path !== state.path) { this.path = state.path; }
    });
    requestDocumentFile(file, THUMBNAIL_PRIORITY);
  }
  @Monitor('widget') onSourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.detach(); }
  build() {
    Stack() {
      if (this.path !== '' || (this.widget.avatarMini ?? '') !== '') {
        Image(this.path !== '' ? (this.path.startsWith('/') ? `file://${this.path}` : this.path) : this.widget.avatarMini)
          .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Cover).draggable(false);
      }
    }.width(this.boxWidth).height(this.boxHeight).borderRadius(6).clip(true).backgroundColor($r('app.color.surface_alt'))
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onVisibleAreaChange([0], (visible: boolean): void => {
        if (this.visible !== visible) { this.visible = visible; this.bind(); }
      });
  }
}
