import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { DrawnMediaRetry } from './DrawnMediaRetry';
import { MessageEntry } from '../../store/MessageEntry';
import { LiveProgressRing } from './LiveProgressRing';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { COLOR_PRIMARY } from '../../util/theme';

// Preview pixels use the shared retained receiver. Download state stays local;
// text, card geometry and hit targets belong to the existing drawn row.
@ComponentV2
export struct DrawnPreviewImage {
  @Require @Param msg: MessageEntry;
  @Require @Param plan: DrawnRichTextLayout | null;
  private specs: CachedImageSpecCache = new CachedImageSpecCache();
  @Computed private get imageSpec(): CachedImageSpec {
    return this.specs.prepare({ path: this.msg.linkPhotoPath,
      boxWidth: this.plan?.previewImage?.width ?? 0, boxHeight: this.plan?.previewImage?.height ?? 0,
      fit: ImageFit.Cover, opaque: false, drawOnCanvas: true,
      sourceKey: `web-preview:${this.msg.rowId}:${this.msg.id}:${this.msg.linkPhotoFileId}` });
  }
  build() {
    Stack() {
      if (this.msg.linkPhotoPath !== '') {
        CachedImage({ spec: this.imageSpec });
      } else if (this.msg.linkPhotoFailed) {
        DrawnMediaRetry({ labelKey: '', iconSize: 24, paddingX: 0, paddingY: 0, tone: '#00000000', foreground: COLOR_PRIMARY });
      } else {
        LiveProgressRing({ fileId: this.msg.linkPhotoFileId, initialPercent: this.msg.linkPhotoProgress, ringSize: 30 });
      }
    }
    .width(this.plan?.previewImage?.width ?? 0).height(this.plan?.previewImage?.height ?? 0)
    .backgroundColor($r('app.color.surface_alt')).borderRadius(8).clip(true)
    .position({ x: this.plan?.previewImage?.x ?? 0, y: this.plan?.previewImage?.y ?? 0 })
    .hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
  }
}
