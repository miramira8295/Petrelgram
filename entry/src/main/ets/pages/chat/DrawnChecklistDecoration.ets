import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { drawnColor } from './DrawnTextLine';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// One checkbox display list per retained task. Completion changes do not
// allocate paths/round-rects or invalidate any task paragraph.
export class DrawnChecklistDecoration extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private fill: drawing.Brush = new drawing.Brush();
  private outline: drawing.Pen = new drawing.Pen();
  private tick: drawing.Pen = new drawing.Pen();
  private accent: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private disabled: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private shape: drawing.RoundRect | null = null;
  private environment: string = '';
  private density: number = 0;
  private width: number = 0;
  private size: number = 0;
  private top: number = 0;
  private left: number = 0;
  private completed: boolean = false;
  private pending: boolean = false;
  private allowed: boolean = false;
  constructor() {
    super(); this.fill.setAntiAlias(true); this.outline.setAntiAlias(true); this.tick.setAntiAlias(true);
    this.tick.setCapStyle(drawing.CapStyle.ROUND_CAP); this.tick.setJoinStyle(drawing.JoinStyle.ROUND_JOIN);
    this.tick.setColor({ alpha: 255, red: 255, green: 255, blue: 255 });
  }
  bind(ui: UIContext, environment: string, width: number, size: number, top: number,
    completed: boolean, pending: boolean, allowed: boolean): DrawnChecklistDecoration {
    const d = this.units.prepare(ui, environment).density;
    let dirty = false;
    if (this.environment !== environment) {
      this.accent = drawnColor(COLOR_PRIMARY); this.disabled = drawnColor(COLOR_TEXT_SECONDARY);
      this.environment = environment; dirty = true;
    }
    if (this.width !== width || this.size !== size || this.top !== top || this.density !== d) {
      this.left = (width - size) * d / 2;
      this.shape = new drawing.RoundRect({ left: this.left, top: top * d,
        right: this.left + size * d, bottom: (top + size) * d }, size * d / 5, size * d / 5);
      this.tick.setStrokeWidth(Math.min(1.7, Math.max(.01, size / 10)) * d);
      this.outline.setStrokeWidth(Math.min(1.4, Math.max(.01, size / 12)) * d);
      this.width = width; this.size = size; this.top = top; this.density = d; dirty = true;
    }
    if (dirty || this.allowed !== allowed) {
      this.fill.setColor(allowed ? this.accent : this.disabled); this.outline.setColor(allowed ? this.accent : this.disabled);
    }
    if (dirty || this.completed !== completed || this.pending !== pending || this.allowed !== allowed) {
      this.completed = completed; this.pending = pending; this.allowed = allowed; this.invalidate();
    }
    return this;
  }
  drawBehind(context: DrawContext): void {
    if (this.shape === null || this.pending) { return; }
    const c = context.canvas;
    if (this.completed) {
      c.attachBrush(this.fill); c.drawRoundRect(this.shape); c.detachBrush();
      const s = this.size * this.density, x = this.left, y = this.top * this.density;
      c.attachPen(this.tick); c.drawLine(x + s * .22, y + s * .5, x + s * .43, y + s * .7);
      c.drawLine(x + s * .43, y + s * .7, x + s * .8, y + s * .28); c.detachPen();
    } else { c.attachPen(this.outline); c.drawRoundRect(this.shape); c.detachPen(); }
  }
}
