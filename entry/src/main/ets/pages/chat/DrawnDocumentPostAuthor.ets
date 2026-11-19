import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { DrawnMediaTexts, DrawnMediaTextPlan, DrawnMediaTextPainter } from './DrawnMediaText';
import { DrawnMediaPlaceholder } from './DrawnMediaPlaceholder';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { documentFileId } from '../../util/drawnDocumentMedia';
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
  private labels: DrawnMediaTexts = new DrawnMediaTexts();
  private labelPainter: DrawnMediaTextPainter = new DrawnMediaTextPainter();
  private specs: CachedImageSpecCache = new CachedImageSpecCache();
  @Computed private get hasAvatar(): boolean { return this.widget.avatar !== undefined || (this.widget.avatarMini ?? '') !== ''; }
  @Computed private get nameLabel(): string { return this.widget.name || str('mb_web_link'); }
  @Computed private get paintEnvironment(): string {
    return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get labelPlan(): DrawnMediaTextPlan {
    return this.labels.prepare(this.getUIContext(), this.paintEnvironment, Math.max(1, this.boxWidth - (this.hasAvatar ? 50 : 0)),
      this.nameLabel, 15, COLOR_TEXT_PRIMARY, this.dateLabel, 12, COLOR_TEXT_SECONDARY, 1, true, 3);
  }
  @Computed private get imageSpec(): CachedImageSpec {
    return this.specs.prepare({ path: this.path !== '' ? this.path : (this.widget.avatarMini ?? ''),
      boxWidth: 40, boxHeight: 40, radius: 20, fit: ImageFit.Cover, drawOnCanvas: true,
      sourceKey: `document-author:${this.widget.key}:${documentFileId(this.widget.avatar)}` });
  }
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
      if (this.hasAvatar) {
        Stack() {
          if (this.path !== '' || (this.widget.avatarMini ?? '') !== '') {
            CachedImage({ spec: this.imageSpec });
          } else { DrawnMediaPlaceholder({ primary: String.fromCodePoint(this.widget.name.codePointAt(0) ?? 32),
            primarySize: 18, primaryColor: COLOR_PRIMARY, boxWidth: 40, boxHeight: 40 }); }
        }.width(40).height(40).borderRadius(20).clip(true).backgroundColor($r('app.color.surface_alt'))
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
      }
      Row().width(this.labelPlan.width).height(this.labelPlan.height)
        .drawModifier(this.labelPainter.bind(this.labelPlan))
        .accessibilityText(`${this.nameLabel}. ${this.dateLabel}`);
    }.width(this.boxWidth).height(56)
      .onVisibleAreaChange([0], (visible: boolean): void => { if (this.visible !== visible) { this.visible = visible; this.bind(); } })
      .onClick((): void => this.onOpen());
  }
}
