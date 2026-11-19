import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { documentFileId } from '../../util/drawnDocumentMedia';
import { DrawnInlineIconDecoration } from './DrawnInlineIconDecoration';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { DrawnInlineIcon, DrawnInlineIconPlacement, drawnInlineIconAnimated } from '../../util/drawnInlineIcon';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { DocumentFileState, documentFileState, watchDocumentFile, requestDocumentFile } from '../../util/documentFileChannel';
import { THUMBNAIL_PRIORITY } from '../../util/downloadPriority';

// Inline documents are fixed-size paragraph placeholders, like Android image
// spans. The shared receiver owns pixels; arrival never invalidates a paragraph.
@ComponentV2
struct DrawnInlineIconImage {
  @Require @Param icon: DrawnInlineIcon;
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Local private path: string = '';
  private specs: CachedImageSpecCache = new CachedImageSpecCache();
  private placeholder: DrawnInlineIconDecoration = new DrawnInlineIconDecoration();
  private env = chatEnv;
  @Computed private get imageSpec(): CachedImageSpec {
    return this.specs.prepare({ path: this.path, boxWidth: this.boxWidth, boxHeight: this.boxHeight,
      fit: ImageFit.Contain, opaque: false, drawOnCanvas: true,
      sourceKey: `inline-document:${documentFileId(this.icon.file)}` });
  }
  private placeholderForPaint(): DrawnInlineIconDecoration {
    return this.placeholder.bind(this.getUIContext(),
      `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`, this.boxWidth, this.boxHeight);
  }
  private off: (() => void) | null = null;
  private generation: number = 0;
  private visible: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  private bind(): void {
    this.detach(); this.path = documentFileState(this.icon.file).path;
    if (!this.visible) { return; }
    const owner = this.generation;
    this.off = watchDocumentFile(this.icon.file, (state: DocumentFileState): void => {
      if (owner === this.generation && this.path !== state.path) { this.path = state.path; }
    });
    requestDocumentFile(this.icon.file, THUMBNAIL_PRIORITY);
  }
  @Monitor('icon') onIconChanged(): void { this.bind(); }
  aboutToAppear(): void { this.bind(); }
  aboutToDisappear(): void { this.visible = false; this.detach(); }
  build() {
    Stack() {
      if (this.path !== '' && drawnInlineIconAnimated(this.icon, this.path)) {
        Image(this.path.startsWith('/') ? `file://${this.path}` : this.path)
          .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain).draggable(false);
      } else if (this.path !== '') {
        CachedImage({ spec: this.imageSpec });
      } else {
        Row().width(this.boxWidth).height(this.boxHeight).drawModifier(this.placeholderForPaint());
      }
    }.width(this.boxWidth).height(this.boxHeight).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onVisibleAreaChange([0], (visible: boolean): void => {
        if (this.visible !== visible) { this.visible = visible; this.bind(); }
      });
  }
}
@ComponentV2
export struct DrawnInlineIconLayer {
  @Require @Param plan: DrawnRichTextLayout | null;
  private empty: DrawnInlineIconPlacement[] = [];
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.plan?.icons ?? this.empty, (item: DrawnInlineIconPlacement) => {
        DrawnInlineIconImage({ icon: item.icon, boxWidth: item.width, boxHeight: item.height })
          .position({ x: item.x, y: item.y }).hitTestBehavior(HitTestMode.None);
      }, (item: DrawnInlineIconPlacement, index: number): string => `${index}:${item.icon.file['id']}`);
    }.width(this.plan?.widthVp ?? 0).height(this.plan?.heightVp ?? 0)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
