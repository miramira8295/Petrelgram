import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';

// Fixed-size local overlay. File progress only records an arc; playback/source
// transitions rebuild its tiny glyph path, never media/body geometry.
export class DrawnSingleVideoBadge extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private borderPen: drawing.Pen = new drawing.Pen();
  private ringPen: drawing.Pen = new drawing.Pen();
  private path: drawing.Path = new drawing.Path();
  private white: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
  private fill: common2D.Color = { alpha: 120, red: 0, green: 0, blue: 0 };
  private border: common2D.Color = { alpha: 36, red: 255, green: 255, blue: 255 };
  private arc: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private size: number = 0;
  private density: number = 0;
  private state: string = '';
  private progress: number = 0;
  constructor() {
    super(); this.brush.setAntiAlias(true); this.pen.setAntiAlias(true);
    this.pen.setCapStyle(drawing.CapStyle.ROUND_CAP); this.pen.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    this.borderPen.setAntiAlias(true); this.borderPen.setColor(this.border);
    this.ringPen.setAntiAlias(true); this.ringPen.setColor(this.white);
    this.pen.setColor(this.white);
  }
  bind(ui: UIContext, environment: string, sizeVp: number, state: string, progress: number): DrawnSingleVideoBadge {
    const d = this.units.prepare(ui, environment).density, size = Math.max(0, sizeVp) * d;
    const percent = state === 'download' && Number.isFinite(progress) ? Math.max(0, Math.min(100, progress)) : 0;
    if (size !== this.size || d !== this.density || state !== this.state) {
      this.size = size; this.density = d; this.state = state;
      this.borderPen.setStrokeWidth(d); this.ringPen.setStrokeWidth(2 * d); this.pen.setStrokeWidth(1.6 * d);
      const c = size / 2, icon = size * (state === 'download' ? .34 : .42);
      this.path.reset();
      if (state === 'play' || state === 'download') {
        const x = c + d;
        this.path.moveTo(x - icon * .35, c - icon / 2); this.path.lineTo(x + icon * .5, c);
        this.path.lineTo(x - icon * .35, c + icon / 2); this.path.close();
      } else if (state === 'retry') {
        this.path.moveTo(c - icon * .45, c - icon * .5); this.path.lineTo(c - icon * .45, c - icon * .12);
        this.path.lineTo(c - icon * .07, c - icon * .12);
      } else if (state === 'warning') {
        this.path.moveTo(c, c - icon * .25); this.path.lineTo(c, c + icon * .1);
      }
      const inset = Math.min(2 * d, size / 4);
      this.arc = { left: inset, top: inset, right: size - inset, bottom: size - inset };
      this.progress = percent; this.invalidate();
    } else if (percent !== this.progress) { this.progress = percent; this.invalidate(); }
    return this;
  }
  drawBehind(context: DrawContext): void {
    if (!(this.size > 0)) { return; }
    const c = this.size / 2, canvas = context.canvas, icon = this.size * .42;
    this.brush.setColor(this.fill);
    canvas.attachBrush(this.brush); canvas.attachPen(this.borderPen);
    canvas.drawCircle(c, c, Math.max(0, c - this.density / 2)); canvas.detachPen(); canvas.detachBrush();
    this.brush.setColor(this.white);
    if (this.state === 'download' && this.progress > 0) {
      canvas.attachPen(this.ringPen);
      canvas.drawArc(this.arc, -90, this.progress * 3.6); canvas.detachPen();
    }
    if (this.state === 'play' || this.state === 'download') {
      canvas.attachBrush(this.brush); canvas.drawPath(this.path); canvas.detachBrush();
    } else if (this.state === 'retry' || this.state === 'warning') {
      canvas.attachPen(this.pen); canvas.drawPath(this.path);
      if (this.state === 'retry') {
        canvas.save(); canvas.translate(c, c); canvas.scale(icon / Math.max(1, this.size - 4 * this.density), icon / Math.max(1, this.size - 4 * this.density));
        canvas.translate(-c, -c); canvas.drawArc(this.arc, -155, 300); canvas.restore();
      } else {
        canvas.drawCircle(c, c, icon / 2); canvas.detachPen();
        canvas.attachBrush(this.brush); canvas.drawCircle(c, c + icon * .3, .8 * this.density); canvas.detachBrush(); return;
      }
      canvas.detachPen();
    }
  }
}
