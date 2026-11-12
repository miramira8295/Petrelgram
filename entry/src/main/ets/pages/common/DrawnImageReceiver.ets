import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { image } from '@kit.ImageKit';

interface DrawnImageSize { width: number; height: number; }
// Cached PixelMaps are immutable. Repeated avatars/album owners share metadata
// without keeping a bitmap alive after the existing pixel cache releases it.
const imageSizes: WeakMap<image.PixelMap, DrawnImageSize> = new WeakMap();

// Telegram's ImageReceiver split, adapted to ArkUI: CachedImageSession owns
// loading/references; this receiver only paints its currently owned PixelMap.
// The existing container owns backdrop, per-corner clipping and gestures.
export class DrawnImageReceiver extends DrawModifier {
  private pixels: image.PixelMap | undefined = undefined;
  private pixelWidth: number = 0;
  private pixelHeight: number = 0;
  private width: number = 0;
  private height: number = 0;
  private fit: ImageFit = ImageFit.Cover;
  private enabled: boolean = false;
  private sampling: drawing.SamplingOptions | undefined = undefined;
  private source: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private target: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };

  // Called synchronously by the session publisher, before it releases the old
  // handle. Never recover pixels from a deferred build callback or after dispose.
  setPixels(pixels: image.PixelMap | undefined, width: number = 0, height: number = 0): void {
    if (this.pixels === pixels) { return; }
    this.pixels = pixels;
    this.pixelWidth = 0;
    this.pixelHeight = 0;
    if (pixels !== undefined) {
      try {
        let size = imageSizes.get(pixels);
        if (size === undefined && width > 0 && height > 0) {
          size = { width, height };
          imageSizes.set(pixels, size);
        }
        if (size === undefined) {
          const info = pixels.getImageInfoSync();
          size = { width: info.size.width, height: info.size.height };
          imageSizes.set(pixels, size);
        }
        this.pixelWidth = size.width;
        this.pixelHeight = size.height;
      } catch (_error) {
        // Metadata unavailable: the owner retains its native Image fallback.
      }
    }
    this.prepareRects();
    this.invalidate();
  }

  canDraw(pixels: image.PixelMap | undefined, fit: ImageFit): boolean {
    return (fit === ImageFit.Cover || fit === ImageFit.Contain) &&
      (pixels === undefined || (pixels === this.pixels && this.pixelWidth > 0 && this.pixelHeight > 0));
  }

  bind(ui: UIContext, widthVp: number, heightVp: number, fit: ImageFit,
    enabled: boolean, density: number = ui.vp2px(1)): DrawnImageReceiver {
    const width = widthVp * density;
    const height = heightVp * density;
    if (this.width !== width || this.height !== height || this.fit !== fit || this.enabled !== enabled) {
      this.width = width; this.height = height; this.fit = fit; this.enabled = enabled;
      if (enabled && this.sampling === undefined) {
        this.sampling = new drawing.SamplingOptions(drawing.FilterMode.FILTER_MODE_LINEAR);
      }
      this.prepareRects();
      this.invalidate();
    }
    return this;
  }

  private prepareRects(): void {
    const w = this.pixelWidth, h = this.pixelHeight;
    if (!(w > 0 && h > 0 && this.width > 0 && this.height > 0)) { return; }
    this.source.left = 0; this.source.top = 0; this.source.right = w; this.source.bottom = h;
    this.target.left = 0; this.target.top = 0;
    this.target.right = this.width; this.target.bottom = this.height;
    if (this.fit === ImageFit.Cover) {
      const scale = Math.max(this.width / w, this.height / h);
      const cropWidth = this.width / scale, cropHeight = this.height / scale;
      this.source.left = (w - cropWidth) / 2; this.source.top = (h - cropHeight) / 2;
      this.source.right = this.source.left + cropWidth;
      this.source.bottom = this.source.top + cropHeight;
    } else if (this.fit === ImageFit.Contain) {
      const scale = Math.min(this.width / w, this.height / h);
      this.target.left = (this.width - w * scale) / 2;
      this.target.top = (this.height - h * scale) / 2;
      this.target.right = this.target.left + w * scale;
      this.target.bottom = this.target.top + h * scale;
    }
  }

  // Front is after the container backdrop, before child placeholders.
  drawFront(context: DrawContext): void {
    if (!this.enabled || this.pixels === undefined || this.pixelWidth <= 0 || this.pixelHeight <= 0 ||
      !(this.width > 0 && this.height > 0)) { return; }
    // O(1), no decode, metadata query, traversal or per-frame native allocation.
    context.canvas.drawImageRectWithSrc(this.pixels, this.source, this.target, this.sampling);
  }
}
