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
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private labelCache: DrawnTextLineCache = new DrawnTextLineCache();
  private label: DrawnTextLine | null = null;
  private background: drawing.RoundRect | null = null;
  private triangle: drawing.Path | null = null;
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

  bind(ui: UIContext, width: number, height: number, content: string,
    play: boolean, environment: string): DrawnVideoDecoration {
    if (this.density > 0 && width === this.mediaWidth && height === this.mediaHeight &&
      content === this.content && play === this.play && environment === this.environment) { return this; }
    const metricsChanged = this.density === 0 || this.environment !== environment;
    if (metricsChanged) {
      this.density = ui.vp2px(1); this.fontPx = ui.fp2px(10.5);
      this.brush.setAntiAlias(true); this.pen.setAntiAlias(true);
      this.pen.setStrokeWidth(this.density); this.pen.setColor(VIDEO_PLAY_STROKE);
    }
    const geometryChanged = metricsChanged || width !== this.mediaWidth || height !== this.mediaHeight;
    if (geometryChanged) {
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
    if (this.label !== null && this.background !== null) {
      this.brush.setColor(VIDEO_BADGE_FILL); canvas.attachBrush(this.brush);
      canvas.drawRoundRect(this.background); canvas.detachBrush();
      this.label.paragraph.paint(canvas, 11 * this.density, this.labelY + this.density);
    }
  }
}
