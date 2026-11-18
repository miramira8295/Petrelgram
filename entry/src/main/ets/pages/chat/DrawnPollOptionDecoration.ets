import { DrawContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { drawnColor, DrawnTextLine, DrawnTextLineCache } from './DrawnTextLine';

// Shared by the options of one poll. Color belongs in the key because native
// paragraph color is mutable, while multiple option surfaces retain each line.
export class DrawnPollPercentLabels {
  private lines: Map<string, DrawnTextLine> = new Map<string, DrawnTextLine>();
  private environment: string = '';
  private fontPx: number = 0;
  private maxPx: number = 0;

  prepare(percentage: number, accent: string, fontPx: number, maxPx: number,
    environment: string): DrawnTextLine {
    if (this.environment !== environment || this.fontPx !== fontPx || this.maxPx !== maxPx) {
      this.lines.clear();
      this.environment = environment; this.fontPx = fontPx; this.maxPx = maxPx;
    }
    const percent = Number.isFinite(percentage) ? Math.max(0, Math.min(100, Math.round(percentage))) : 0;
    const key = `${percent}:${accent}`;
    const cached = this.lines.get(key);
    if (cached !== undefined) { return cached; }
    const line = new DrawnTextLineCache().prepare(`${percent}%`, maxPx, fontPx, drawnColor(accent), environment, true);
    if (this.lines.size >= 128) { this.lines.delete(this.lines.keys().next().value as string); }
    this.lines.set(key, line);
    return line;
  }
}

// Decorations share the option's existing paint surface. Results never alter
// its layout width, and painting does not allocate brushes, pens or paragraphs.
export class DrawnPollOptionDecoration extends DrawModifier {
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private density: number = 0;
  private colorKey: string = '';
  private accent: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private barColor: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private readonly white: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
  private bar: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private state: string = '';
  private marked: boolean = false;
  private percentage: number = 0;
  private label: DrawnTextLine | null = null;

  constructor() {
    super();
    this.brush.setAntiAlias(true);
    this.pen.setAntiAlias(true);
    this.pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
  }

  bind(density: number, accent: string, state: string, marked: boolean, percentage: number, label: DrawnTextLine | null = null): DrawnPollOptionDecoration {
    const next = Number.isFinite(percentage) ? Math.max(0, Math.min(100, percentage)) : 0;
    let dirty = false;
    if (this.density !== density) {
      this.density = density;
      this.pen.setStrokeWidth(1.5 * density);
      dirty = true;
    }
    if (this.colorKey !== accent) {
      this.colorKey = accent;
      this.accent = drawnColor(accent);
      this.barColor = { alpha: Math.round(this.accent.alpha / 2), red: this.accent.red,
        green: this.accent.green, blue: this.accent.blue };
      dirty = true;
    }
    if (this.state !== state || this.marked !== marked || this.percentage !== next || this.label !== label) { dirty = true; }
    this.state = state;
    this.marked = marked;
    this.percentage = next;
    this.label = label;
    if (dirty) { this.invalidate(); }
    return this;
  }

  drawBehind(context: DrawContext): void {
    const density = this.density;
    if (!(density > 0)) { return; }
    const size = context.sizeInPixel;
    const canvas = context.canvas;
    const x = 19 * density, y = size.height / 2;
    if (this.label !== null) {
      this.label.paragraph.paint(canvas, Math.max(0, size.width - 49 * density),
        Math.max(0, (size.height - this.label.heightPx) / 2));
    }
    if (this.percentage > 0) {
      this.bar.right = size.width * this.percentage / 100;
      this.bar.top = Math.max(0, size.height - 3 * density);
      this.bar.bottom = size.height;
      this.brush.setColor(this.barColor);
      canvas.attachBrush(this.brush); canvas.drawRect(this.bar); canvas.detachBrush();
    }
    if (this.marked) {
      this.brush.setColor(this.accent);
      canvas.attachBrush(this.brush); canvas.drawCircle(x, y, 10 * density); canvas.detachBrush();
    }
    this.pen.setColor(this.accent);
    canvas.attachPen(this.pen); canvas.drawCircle(x, y, 10 * density); canvas.detachPen();
    if (this.state === 'selected') {
      this.brush.setColor(this.white);
      canvas.attachBrush(this.brush); canvas.drawCircle(x, y, 3.5 * density); canvas.detachBrush();
    } else if (this.state === 'correct' || this.state === 'wrong' || this.state === 'vote') {
      this.pen.setColor(this.white);
      canvas.attachPen(this.pen);
      if (this.state === 'wrong') {
        canvas.drawLine(x - 3 * density, y - 3 * density, x + 3 * density, y + 3 * density);
        canvas.drawLine(x - 3 * density, y + 3 * density, x + 3 * density, y - 3 * density);
      } else {
        canvas.drawLine(x - 4 * density, y, x - density, y + 3 * density);
        canvas.drawLine(x - density, y + 3 * density, x + 4 * density, y - 3 * density);
      }
      canvas.detachPen();
    }
  }
}
