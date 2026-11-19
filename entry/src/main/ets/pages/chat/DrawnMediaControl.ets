import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { drawnColor, DrawnTextLine, DrawnTextLineCache } from './DrawnTextLine';

const DRAWN_CONTROL_WHITE: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };

// A control's hit target/accessibility stay on its native host; its decoration
// is one retained display list. Download/player callbacks never touch row plans.
export class DrawnMediaControl extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private glyphPath: drawing.Path = new drawing.Path();
  private labelCache: DrawnTextLineCache = new DrawnTextLineCache();
  private label: DrawnTextLine | null = null;
  private size: number = 0;
  private glyph: string = '';
  private density: number = 0;
  private progress: number = 0;
  private square: boolean = false;
  private colorEnvironment: string = '';
  private backgroundKey: ResourceColor = '';
  private foregroundKey: ResourceColor = '';
  private background: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private foreground: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private bounds: drawing.RoundRect = new drawing.RoundRect({ left: 0, top: 0, right: 0, bottom: 0 }, 0, 0);
  private arc: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private retryArc: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private lockBody: drawing.RoundRect | null = null;
  private lockArc: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private stopRect: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private pauseLeft: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private pauseRight: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };

  constructor() {
    super(); this.brush.setAntiAlias(true); this.pen.setAntiAlias(true);
    this.pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
    this.pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
  }

  bind(ui: UIContext, environment: string, sizeVp: number, background: ResourceColor,
    foreground: ResourceColor, glyph: string, progress: number = 0, square: boolean = false,
    label: string = ''): DrawnMediaControl {
    this.units.prepare(ui, environment);
    const density = this.units.density;
    const size = sizeVp * density;
    const next = Number.isFinite(progress) ? Math.max(0, Math.min(100, progress)) : 0;
    let dirty = false;
    if (this.density !== density || this.size !== size || this.glyph !== glyph || this.square !== square) {
      this.density = density; this.size = size; this.glyph = glyph; this.square = square;
      this.prepareGeometry(); dirty = true;
    }
    const colorDirty = this.colorEnvironment !== environment;
    this.colorEnvironment = environment;
    if (colorDirty || this.backgroundKey !== background) { this.backgroundKey = background; this.background = drawnColor(background); dirty = true; }
    if (colorDirty || this.foregroundKey !== foreground) { this.foregroundKey = foreground; this.foreground = drawnColor(foreground); dirty = true; }
    const oldLabel = this.label;
    this.label = label === '' ? null : this.labelCache.prepare(label, Math.max(1, size - 8 * density),
      this.units.fp2px(glyph === 'error' ? 22 : glyph === 'percent' ? 9 : label.length > 4 ? 8.5 : 10.5), this.foreground, environment, true);
    // recolor() can mutate a retained paragraph; dirty includes color changes.
    if (dirty || oldLabel !== this.label || this.progress !== next) { this.invalidate(); }
    this.progress = next;
    return this;
  }

  private prepareGeometry(): void {
    const d = this.density, s = this.size, c = s / 2;
    this.pen.setStrokeWidth((this.glyph === 'info' || this.glyph === 'warning' || this.glyph === 'stop' ? 1.4 : 2) * d);
    const radius = this.square ? 13 * d : c;
    this.bounds = new drawing.RoundRect({ left: 0, top: 0, right: s, bottom: s }, radius, radius);
    const inset = this.square ? 4 * d : 5 * d;
    this.arc.left = inset; this.arc.top = inset; this.arc.right = s - inset; this.arc.bottom = s - inset;
    this.retryArc.left = c - 8 * d; this.retryArc.top = c - 8 * d;
    this.retryArc.right = c + 8 * d; this.retryArc.bottom = c + 8 * d;
    this.pauseLeft = { left: c - 6 * d, top: c - 8 * d, right: c - 2 * d, bottom: c + 8 * d };
    this.pauseRight = { left: c + 2 * d, top: c - 8 * d, right: c + 6 * d, bottom: c + 8 * d };
    this.stopRect = { left: c - 2.5 * d, top: c - 2.5 * d, right: c + 2.5 * d, bottom: c + 2.5 * d };
    this.glyphPath.reset();
    this.lockBody = null;
    if (this.glyph === 'play') {
      this.glyphPath.moveTo(c - 5 * d, c - 8 * d); this.glyphPath.lineTo(c + 8 * d, c);
      this.glyphPath.lineTo(c - 5 * d, c + 8 * d); this.glyphPath.close();
    } else if (this.glyph === 'lock' || this.glyph === 'lock-open') {
      this.lockBody = new drawing.RoundRect({ left: c - 7 * d, top: c - d, right: c + 7 * d, bottom: c + 9 * d }, 2 * d, 2 * d);
      this.lockArc.left = c - 5 * d; this.lockArc.top = c - 9 * d; this.lockArc.right = c + 5 * d; this.lockArc.bottom = c + 3 * d;
    } else if (this.glyph === 'phone') {
      this.glyphPath.moveTo(c - 7 * d, c - 8 * d); this.glyphPath.lineTo(c - 3 * d, c - 8 * d);
      this.glyphPath.lineTo(c - d, c - 3 * d); this.glyphPath.lineTo(c - 3 * d, c - d);
      this.glyphPath.lineTo(c + d, c + 3 * d); this.glyphPath.lineTo(c + 3 * d, c + d);
      this.glyphPath.lineTo(c + 8 * d, c + 3 * d); this.glyphPath.lineTo(c + 8 * d, c + 7 * d);
      this.glyphPath.lineTo(c + 5 * d, c + 9 * d); this.glyphPath.lineTo(c + d, c + 8 * d);
      this.glyphPath.lineTo(c - 4 * d, c + 4 * d); this.glyphPath.lineTo(c - 8 * d, c - d);
      this.glyphPath.lineTo(c - 9 * d, c - 5 * d); this.glyphPath.close();
    } else if (this.glyph === 'chevron') {
      this.glyphPath.moveTo(c - 3 * d, c - 6 * d); this.glyphPath.lineTo(c + 3 * d, c);
      this.glyphPath.lineTo(c - 3 * d, c + 6 * d);
    } else if (this.glyph === 'info' || this.glyph === 'warning') {
      this.glyphPath.moveTo(c, c + (this.glyph === 'info' ? -0.5 : -4) * d);
      this.glyphPath.lineTo(c, c + (this.glyph === 'info' ? 4 : 0.5) * d);
    } else if (this.glyph === 'photo') {
      this.glyphPath.moveTo(c - 10 * d, c - 8 * d); this.glyphPath.lineTo(c + 10 * d, c - 8 * d);
      this.glyphPath.lineTo(c + 10 * d, c + 8 * d); this.glyphPath.lineTo(c - 10 * d, c + 8 * d); this.glyphPath.close();
      this.glyphPath.moveTo(c - 9 * d, c + 7 * d); this.glyphPath.lineTo(c - 2 * d, c - d);
      this.glyphPath.lineTo(c + 3 * d, c + 4 * d); this.glyphPath.lineTo(c + 6 * d, c + d); this.glyphPath.lineTo(c + 10 * d, c + 5 * d);
    } else if (this.glyph === 'pin') {
      this.glyphPath.moveTo(c, c + 13 * d);
      this.glyphPath.cubicTo(c - 4 * d, c + 5 * d, c - 10 * d, c + d, c - 10 * d, c - 4 * d);
      this.glyphPath.cubicTo(c - 10 * d, c - 17 * d, c + 10 * d, c - 17 * d, c + 10 * d, c - 4 * d);
      this.glyphPath.cubicTo(c + 10 * d, c + d, c + 4 * d, c + 5 * d, c, c + 13 * d);
      this.glyphPath.close();
    } else if (this.glyph === 'person') {
      this.glyphPath.moveTo(c - 7 * d, c + 8 * d);
      this.glyphPath.cubicTo(c - 7 * d, c - d, c + 7 * d, c - d, c + 7 * d, c + 8 * d);
      this.glyphPath.close();
    } else if (this.glyph === 'retry') {
      this.glyphPath.moveTo(c - 8 * d, c - 9 * d); this.glyphPath.lineTo(c - 8 * d, c - 3 * d);
      this.glyphPath.lineTo(c - 2 * d, c - 3 * d);
    } else if (this.glyph === 'download' || this.glyph === 'upload' || this.glyph === 'save') {
      const sign = this.glyph === 'upload' ? -1 : 1;
      this.glyphPath.moveTo(c, c - sign * 7 * d); this.glyphPath.lineTo(c, c + sign * 5 * d);
      this.glyphPath.moveTo(c - 5 * d, c); this.glyphPath.lineTo(c, c + sign * 5 * d);
      this.glyphPath.lineTo(c + 5 * d, c);
      this.glyphPath.moveTo(c - 8 * d, c + 9 * d); this.glyphPath.lineTo(c + 8 * d, c + 9 * d);
      if (this.glyph === 'save') {
        this.glyphPath.moveTo(c - 8 * d, c + 4 * d); this.glyphPath.lineTo(c - 8 * d, c + 9 * d);
        this.glyphPath.moveTo(c + 8 * d, c + 4 * d); this.glyphPath.lineTo(c + 8 * d, c + 9 * d);
      }
    }
  }

  drawBehind(context: DrawContext): void {
    if (!(this.size > 0)) { return; }
    const c = this.size / 2, canvas = context.canvas;
    if (this.background.alpha > 0) {
      this.brush.setColor(this.background);
      canvas.attachBrush(this.brush); canvas.drawRoundRect(this.bounds); canvas.detachBrush();
    }
    this.pen.setColor(this.foreground);
    if (this.progress > 0) {
      canvas.attachPen(this.pen); canvas.drawArc(this.arc, -90, this.progress * 3.6); canvas.detachPen();
    }
    if (this.label !== null) {
      this.label.paragraph.paint(canvas, (this.size - this.label.widthPx) / 2, (this.size - this.label.heightPx) / 2);
    } else if (this.lockBody !== null) {
      this.brush.setColor(this.foreground); canvas.attachBrush(this.brush); canvas.drawRoundRect(this.lockBody); canvas.detachBrush();
      canvas.attachPen(this.pen); canvas.drawArc(this.lockArc, this.glyph === 'lock' ? 180 : 215, this.glyph === 'lock' ? 180 : 145);
      canvas.drawLine(c + 5 * this.density, c - 3 * this.density, c + 5 * this.density, c);
      if (this.glyph === 'lock') { canvas.drawLine(c - 5 * this.density, c - 3 * this.density, c - 5 * this.density, c); }
      canvas.detachPen();
    } else if (this.glyph === 'info' || this.glyph === 'warning' || this.glyph === 'stop') {
      canvas.attachPen(this.pen); canvas.drawCircle(c, c, Math.max(this.density, c - 1.5 * this.density));
      if (this.glyph !== 'stop') { canvas.drawPath(this.glyphPath); }
      canvas.detachPen(); this.brush.setColor(this.foreground); canvas.attachBrush(this.brush);
      if (this.glyph === 'stop') { canvas.drawRect(this.stopRect); }
      else { canvas.drawCircle(c, c + (this.glyph === 'info' ? -4 : 4) * this.density, this.density * .8); }
      canvas.detachBrush();
    } else if (this.glyph === 'photo') {
      canvas.attachPen(this.pen); canvas.drawPath(this.glyphPath);
      canvas.drawCircle(c + 5 * this.density, c - 3 * this.density, 1.7 * this.density); canvas.detachPen();
    } else if (this.glyph === 'pin') {
      this.brush.setColor(this.foreground); canvas.attachBrush(this.brush); canvas.drawPath(this.glyphPath); canvas.detachBrush();
      this.brush.setColor(DRAWN_CONTROL_WHITE);
      canvas.attachBrush(this.brush); canvas.drawCircle(c, c - 4 * this.density, 3.5 * this.density); canvas.detachBrush();
    } else if (this.glyph === 'play' || this.glyph === 'pause' || this.glyph === 'phone' || this.glyph === 'person') {
      this.brush.setColor(this.foreground); canvas.attachBrush(this.brush);
      if (this.glyph !== 'pause') {
        canvas.drawPath(this.glyphPath);
        if (this.glyph === 'person') { canvas.drawCircle(c, c - 5 * this.density, 3.5 * this.density); }
      }
      else { canvas.drawRect(this.pauseLeft); canvas.drawRect(this.pauseRight); }
      canvas.detachBrush();
    } else if (this.glyph === 'retry' || this.glyph === 'download' || this.glyph === 'upload' || this.glyph === 'save' || this.glyph === 'chevron') {
      canvas.attachPen(this.pen); canvas.drawPath(this.glyphPath);
      if (this.glyph === 'retry') { canvas.drawArc(this.retryArc, -155, 300); }
      canvas.detachPen();
    }
    if (this.glyph === 'label-check') {
      const x = this.size - 7 * this.density, y = x, d = this.density;
      this.brush.setColor(this.foreground);
      canvas.attachBrush(this.brush); canvas.drawCircle(x, y, 8 * d); canvas.detachBrush();
      this.pen.setColor(this.background); canvas.attachPen(this.pen);
      canvas.drawLine(x - 3 * d, y, x - d, y + 2 * d);
      canvas.drawLine(x - d, y + 2 * d, x + 3 * d, y - 3 * d); canvas.detachPen();
    }
  }
}
