import { CachedImage } from '../common/CachedImage';
import { StaticMiniThumbnail } from '../common/StaticMiniThumbnail';
import { CachedImageSpec, CachedImageSpecCache } from '../../util/cachedImageSpec';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnTileCorners } from './DrawnBubblePlan';
import { DrawnBubblePainter, DrawnBubbleForeground } from './DrawnBubblePainter';
import { DrawnCanvasAttributes } from './DrawnNativeAttributes';

// Created only by the menu builder. DrawModifier instances must not be attached
// to both the timeline and the popup: invalidation belongs to one native node.
export class DrawnMenuPaintState {
  readonly background: DrawnBubblePainter = new DrawnBubblePainter();
  readonly foreground: DrawnBubbleForeground = new DrawnBubbleForeground();
  readonly attributes: DrawnCanvasAttributes = new DrawnCanvasAttributes();
}

// A menu retains its own decoded-image cache reference. Never borrow a slot's
// PixelMap: recycling that slot can release it while the menu is animating out.
// This component starts no downloads, playback, polling or progress listeners.
@ComponentV2
export struct DrawnMenuMedia {
  @Param path: string = '';
  @Param mini: string = '';
  @Param sourceKey: string = '';
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  @Param corners: DrawnTileCorners | undefined = undefined;
  @Param contain: boolean = false;
  @Param alternative: string = '';
  private specs: CachedImageSpecCache = new CachedImageSpecCache();
  private spec(): CachedImageSpec {
    return this.specs.prepare({ path: this.path, sourceKey: this.sourceKey,
      boxWidth: this.boxWidth, boxHeight: this.boxHeight,
      fit: this.contain ? ImageFit.Contain : ImageFit.Cover, opaque: !this.contain });
  }
  build() {
    Stack() {
      if (this.path !== '') {
        CachedImage({ spec: this.spec() });
      } else if (this.mini !== '') {
        StaticMiniThumbnail({ source: this.mini, boxW: this.boxWidth, boxH: this.boxHeight });
      } else if (this.alternative !== '') {
        Text(this.alternative).fontSize(Math.min(52, this.boxHeight * .6)).maxLines(1);
      }
    }.width(this.boxWidth).height(this.boxHeight)
      .backgroundColor(this.contain ? Color.Transparent : '#FFD7DCE2')
      .borderRadius(this.corners ?? 0).clip(true).hitTestBehavior(HitTestMode.None);
  }
}

@ComponentV2
export struct DrawnMenuSticker {
  @Require @Param msg: MessageEntry;
  @Param boxWidth: number = 0;
  @Param boxHeight: number = 0;
  private path(): string {
    // TGS/WebM are animation sources, not raster images. Their server thumbnail
    // is the static menu cover; only a static sticker may use its source file.
    return this.msg.photoPath || (this.msg.stickerFormat !== 'tgs' && this.msg.stickerFormat !== 'webm'
      ? this.msg.stickerPath : '');
  }
  build() {
    DrawnMenuMedia({ path: this.path(), mini: this.msg.photoMini,
      sourceKey: `menu-sticker:${this.msg.rowId}:${this.msg.stickerFileId}:${this.msg.photoFileId}`,
      boxWidth: this.boxWidth, boxHeight: this.boxHeight, contain: true,
      alternative: this.msg.text || '◇' });
  }
}
