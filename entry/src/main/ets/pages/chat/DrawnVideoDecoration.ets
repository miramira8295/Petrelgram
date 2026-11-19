import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextLine, DrawnTextLineCache } from './DrawnTextLine';

const VIDEO_BADGE_WHITE: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
const VIDEO_BADGE_FILL: common2D.Color = { alpha: 102, red: 0, green: 0, blue: 0 };
const VIDEO_PLAY_FILL: common2D.Color = { alpha: 115, red: 0, green: 0, blue: 0 };
const VIDEO_PLAY_STROKE: common2D.Color = { alpha: 36, red: 255, green: 255, blue: 255 };

// One modifier on the existing video island. Fixed geometry, one bounded label
// cache, and no path construction or paragraph layout in the drawing callback.
export class DrawnVideoDecoration extends DrawModifier {
  private ui: UIContext | null = null;
  private liveCache: DrawnTextLineCache = new DrawnTextLineCache();
  private liveLabel: DrawnTextLine | null = null;
  private liveBackground: drawing.RoundRect | null = null;
  private livePen: drawing.Pen | null = null;
  private liveContent: string = '';
  private liveFontPx: number = 0;
  private liveHeight: number = 0;
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private labelCache: DrawnTextLineCache = new DrawnTextLineCache();
  private label: DrawnTextLine | null = null;
  private background: drawing.RoundRect | null = null;
  private triangle: drawing.Path | null = null;
  private triangleDirty: boolean = true;
  private environment: string = '';
  private density: number = 0;
  private fontPx: number = 0;
  private mediaWidth: number = 0;
  private mediaHeight: number = 0;
  private content: string = '';
  private play: boolean = false;
  private centerX: number = 0;
  private centerY: number = 0;
  private radius: number = 0;
  private labelY: number = 0;

  constructor() { super(); this.brush.setAntiAlias(true); this.pen.setAntiAlias(true); }
  get metaWidthVp(): number { return this.label && this.density > 0 ? this.label.widthPx / this.density + 10 : 0; }
  get metaHeightVp(): number { return this.label && this.density > 0 ? this.label.heightPx / this.density + 2 : 0; }
  get liveWidthVp(): number { return this.liveLabel && this.density > 0 ? this.liveLabel.widthPx / this.density + 26 : 0; }
  get liveHeightVp(): number { return this.liveHeight; }

  bind(ui: UIContext, width: number, height: number, content: string,
    play: boolean, environment: string, liveContent: string = ''): DrawnVideoDecoration {
    if (this.ui === ui && this.density > 0 && liveContent === this.liveContent && width === this.mediaWidth && height === this.mediaHeight &&
      content === this.content && play === this.play && environment === this.environment) { return this; }
    const metricsChanged = this.ui !== ui || this.density === 0 || this.environment !== environment;
    if (metricsChanged) {
      this.density = ui.vp2px(1); this.fontPx = ui.fp2px(10.5);
      this.liveFontPx = 0;
      this.pen.setStrokeWidth(this.density); this.pen.setColor(VIDEO_PLAY_STROKE);
    }
    const geometryChanged = metricsChanged || width !== this.mediaWidth || height !== this.mediaHeight;
    if (geometryChanged) { this.triangleDirty = true; }
    // A pending slot has exact dimensions but nothing to paint yet. Do not
    // rebuild native paths synchronously only to hide them until publication.
    if (play && this.triangleDirty) {
      const diameter = Math.min(40, Math.min(width, height) * .46) * this.density;
      this.centerX = width * this.density / 2; this.centerY = height * this.density / 2;
      this.radius = diameter / 2;
      const icon = diameter * .42;
      const x = this.centerX + this.density;
      this.triangle = new drawing.Path();
      this.triangle.moveTo(x - icon * .35, this.centerY - icon / 2);
      this.triangle.lineTo(x + icon * .5, this.centerY);
      this.triangle.lineTo(x - icon * .35, this.centerY + icon / 2);
      this.triangle.close();
      this.triangleDirty = false;
    }
    if (geometryChanged || content !== this.content) {
      this.label = content === '' ? null : this.labelCache.prepare(content,
        (Math.max(24, width - 12) - 10) * this.density, this.fontPx, VIDEO_BADGE_WHITE, environment);
      this.labelY = Math.max(6, height - 23) * this.density;
      this.background = this.label === null ? null : new drawing.RoundRect({
        left: 6 * this.density, top: this.labelY,
        right: 16 * this.density + this.label.widthPx,
        bottom: this.labelY + this.label.heightPx + 2 * this.density
      }, 6 * this.density, 6 * this.density);
    }
    if (liveContent !== '' && this.liveFontPx === 0) {
      this.liveFontPx = ui.fp2px(10);
      if (this.livePen === null) {
        this.livePen = new drawing.Pen(); this.livePen.setAntiAlias(true); this.livePen.setColor(VIDEO_BADGE_WHITE);
      }
      this.livePen.setStrokeWidth(this.density);
    }
    if (geometryChanged || liveContent !== this.liveContent) {
      this.liveLabel = liveContent === '' ? null : this.liveCache.prepare(liveContent,
        Math.max(1, width - 38) * this.density, this.liveFontPx, VIDEO_BADGE_WHITE, environment, true);
      this.liveHeight = this.liveLabel ? Math.max(18, this.liveLabel.heightPx / this.density + 4) : 0;
      this.liveBackground = this.liveLabel ? new drawing.RoundRect({ left: 6 * this.density, top: 6 * this.density,
        right: (6 + this.liveWidthVp) * this.density, bottom: (6 + this.liveHeight) * this.density }, 9 * this.density, 9 * this.density) : null;
    }
    this.ui = ui; this.liveContent = liveContent;
    this.mediaWidth = width; this.mediaHeight = height; this.content = content;
    this.play = play; this.environment = environment;
    this.invalidate();
    return this;
  }

  // Foreground is after children, including the native player. drawFront would
  // be before children and could hide duration/file size behind the surface.
  drawForeground(context: DrawContext): void {
    const canvas = context.canvas;
    if (this.play && this.triangle !== null) {
      this.brush.setColor(VIDEO_PLAY_FILL); canvas.attachBrush(this.brush); canvas.attachPen(this.pen);
      canvas.drawCircle(this.centerX, this.centerY, this.radius);
      canvas.detachPen(); canvas.detachBrush();
      this.brush.setColor(VIDEO_BADGE_WHITE); canvas.attachBrush(this.brush);
      canvas.drawPath(this.triangle); canvas.detachBrush();
    }
    if (this.liveLabel && this.liveBackground && this.livePen) {
      this.brush.setColor(VIDEO_BADGE_FILL); canvas.attachBrush(this.brush); canvas.drawRoundRect(this.liveBackground); canvas.detachBrush();
      canvas.attachPen(this.livePen);
      canvas.drawCircle(17 * this.density, (6 + this.liveHeight / 2) * this.density, 5 * this.density);
      canvas.drawCircle(17 * this.density, (6 + this.liveHeight / 2) * this.density, 2.4 * this.density); canvas.detachPen();
      this.liveLabel.paragraph.paint(canvas, 26 * this.density,
        (6 + this.liveHeight / 2) * this.density - this.liveLabel.heightPx / 2);
    }
    if (this.label !== null && this.background !== null) {
      this.brush.setColor(VIDEO_BADGE_FILL); canvas.attachBrush(this.brush);
      canvas.drawRoundRect(this.background); canvas.detachBrush();
      this.label.paragraph.paint(canvas, 11 * this.density, this.labelY + this.density);
    }
  }
}
