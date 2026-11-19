import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';

class DrawnProgressLabels {
  private environment: string = '';
  private entries: Map<string, DrawnTextLine> = new Map();
  prepare(content: string, maxPx: number, fontPx: number, color: common2D.Color, environment: string): DrawnTextLine {
    if (this.environment !== environment) { this.environment = environment; this.entries.clear(); }
    const key = `${content}:${maxPx}:${fontPx}:${color.alpha}:${color.red}:${color.green}:${color.blue}`;
    const hit = this.entries.get(key);
    if (hit !== undefined) { return hit; }
    const line = new DrawnTextLineCache().prepare(content, maxPx, fontPx, color, environment, true);
    if (this.entries.size >= 256) { this.entries.delete(this.entries.keys().next().value as string); }
    this.entries.set(key, line); return line;
  }
}
// Percent labels can be shared across all images on a display. The UI is weakly
// owned and each environment keeps at most 256 immutable native paragraphs.
const progressLabels: WeakMap<UIContext, DrawnProgressLabels> = new WeakMap();
function labelPool(ui: UIContext): DrawnProgressLabels {
  let pool = progressLabels.get(ui);
  if (pool === undefined) { pool = new DrawnProgressLabels(); progressLabels.set(ui, pool); }
  return pool;
}

// A retained radial display list. Size/font/style changes prepare geometry;
// progress is O(1), never changes the host's measured size or outer row plan.
export class DrawnProgressRing extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private pen: drawing.Pen = new drawing.Pen();
  private label: DrawnTextLine | null = null;
  private arc: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private size: number = 0;
  private stroke: number = 0;
  private progress: number = -1;
  private spinner: boolean = false;
  private colorKey: ResourceColor = '';
  private environment: string = '';
  private color: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  constructor() { super(); this.pen.setAntiAlias(true); this.pen.setCapStyle(drawing.CapStyle.ROUND_CAP); }
  bind(ui: UIContext, environment: string, sizeVp: number, color: ResourceColor, progress: number,
    showLabel: boolean = false, spinner: boolean = false, strokeVp: number = 2.5): DrawnProgressRing {
    const units = this.units.prepare(ui, environment), size = sizeVp * units.density;
    const stroke = strokeVp * units.density;
    const next = Number.isFinite(progress) ? Math.max(0, Math.min(100, progress)) : 0;
    let dirty = this.progress !== next || this.spinner !== spinner;
    if (this.size !== size || this.stroke !== stroke) {
      this.size = size; this.stroke = stroke;
      this.arc.left = this.arc.top = stroke / 2;
      this.arc.right = this.arc.bottom = Math.max(stroke / 2, size - stroke / 2);
      this.pen.setStrokeWidth(stroke); dirty = true;
    }
    if (this.colorKey !== color || this.environment !== environment) {
      this.colorKey = color; this.environment = environment; this.color = drawnColor(color);
      this.pen.setColor(this.color); dirty = true;
    }
    const label = showLabel ? labelPool(ui).prepare(`${next}%`, Math.max(1, size - 4 * units.density),
      units.fp2px(Math.max(10, sizeVp * .25)), this.color, environment) : null;
    if (label !== this.label) { this.label = label; dirty = true; }
    this.progress = next; this.spinner = spinner;
    if (dirty) { this.invalidate(); } return this;
  }
  drawBehind(context: DrawContext): void {
    if (!(this.size > 0)) { return; }
    const c = context.canvas;
    if (this.spinner || this.progress > 0) {
      c.attachPen(this.pen); c.drawArc(this.arc, -90, this.spinner ? 270 : this.progress * 3.6); c.detachPen();
    }
    this.label?.paragraph.paint(c, (this.size - this.label.widthPx) / 2, (this.size - this.label.heightPx) / 2);
  }
}
