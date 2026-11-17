import { MessageEntry } from '../../store/MessageEntry';
import { LiveProgressRing } from './LiveProgressRing';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { COLOR_PRIMARY } from '../../util/theme';

// Only the decoded image and its live progress are native. Text, card geometry,
// outline and hit targets belong to the existing drawn row, not another shell.
@ComponentV2
export struct DrawnPreviewImage {
  @Require @Param msg: MessageEntry;
  @Require @Param plan: DrawnRichTextLayout | null;
  build() {
    Stack() {
      if (this.msg.linkPhotoPath !== '') {
        Image(this.msg.linkPhotoPath.startsWith('/') ? `file://${this.msg.linkPhotoPath}` : this.msg.linkPhotoPath)
          .width(this.plan?.previewImage?.width ?? 0).height(this.plan?.previewImage?.height ?? 0)
          .objectFit(ImageFit.Cover).draggable(false);
      } else if (this.msg.linkPhotoFailed) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(24).fontColor([COLOR_PRIMARY]);
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
