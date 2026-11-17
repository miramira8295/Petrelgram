import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { documentFileState, watchDocumentFile, requestDocumentFile, DocumentFileState } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { fullDate } from '../../util/intlFormat';
import { chatEnv } from '../../util/chatEnvMirror';
import { str } from '../../util/strings';

// ArticleViewer's embedded-post header: optional 40vp avatar, author and date.
// Avatar delivery updates this island only; no row paragraph invalidation.
@ComponentV2
export struct DrawnDocumentPostAuthor {
  @Require @Param widget: DrawnDocumentWidget;
  @Param boxWidth: number = 0;
  @Event onOpen: () => void = (): void => {};
  @Local private path: string = '';
  private off: (() => void) | null = null;
  private generation: number = 0;
  private visible: boolean = false;
  private env = chatEnv;
  @Computed private get dateLabel(): string {
    const epoch = this.env.langEpoch;
    return this.widget.date ? fullDate(new Date(this.widget.date * 1000)) : '';
  }
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
    Row({ space: 10 }) {
      if (this.widget.avatar !== undefined || (this.widget.avatarMini ?? '') !== '') {
        Stack() {
          if (this.path !== '' || (this.widget.avatarMini ?? '') !== '') {
            Image(this.path !== '' ? (this.path.startsWith('/') ? `file://${this.path}` : this.path) : this.widget.avatarMini)
              .width(40).height(40).objectFit(ImageFit.Cover).draggable(false);
          } else { Text(String.fromCodePoint(this.widget.name.codePointAt(0) ?? 32)).fontSize(18).fontColor(COLOR_PRIMARY); }
        }.width(40).height(40).borderRadius(20).clip(true).backgroundColor($r('app.color.surface_alt'))
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
      }
      Column({ space: 3 }) {
        Text(this.widget.name || str('mb_web_link')).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (this.dateLabel !== '') { Text(this.dateLabel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1); }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width(this.boxWidth).height(56)
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } })
      .onClick((): void => this.onOpen());
  }
}
