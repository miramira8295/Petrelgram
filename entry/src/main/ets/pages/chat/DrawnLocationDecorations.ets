import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnMediaControl } from './DrawnMediaControl';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';
import { COLOR_TEXT_PRIMARY } from '../../util/theme';

// Optional map placeholder only. Real snapshots retain their own image receiver
// and download ownership. All roads/pin/labels are retained drawing commands.
export class DrawnLocationPreview extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private pin: DrawnMediaControl = new DrawnMediaControl();
  private labels: DrawnTextLineCache = new DrawnTextLineCache();
  private label: DrawnTextLine | null = null;
  private environment: string = '';
  private width: number = 0;
  private density: number = 0;
  private valid: boolean = false;
  private content: string = '';
  private bounds: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private validColor: common2D.Color = drawnColor('#DCE9DF');
  private invalidColor: common2D.Color = drawnColor('#E4E7EA');
  private roadColor: common2D.Color = drawnColor('#C5D7C9');
  private labelColor: common2D.Color = drawnColor('#737B84');
  constructor() { super(); this.brush.setAntiAlias(true); this.pen.setAntiAlias(true); this.pen.setColor(this.roadColor); }
  bind(ui: UIContext, environment: string, width: number, valid: boolean, content: string): DrawnLocationPreview {
    const d = this.units.prepare(ui, environment).density;
    const dirty = this.environment !== environment || this.width !== width || this.density !== d || this.valid !== valid || this.content !== content;
    if (!dirty) { return this; }
    this.bounds = { left: 0, top: 0, right: width * d, bottom: 104 * d }; this.pen.setStrokeWidth(3 * d);
    this.label = valid ? null : this.labels.prepare(content, Math.max(1, width - 24) * d,
      this.units.fp2px(11), this.labelColor, environment);
    this.pin.bind(ui, environment, 30, '#00000000', valid ? '#3390EC' : '#8E969F', 'pin');
    this.width = width; this.density = d; this.valid = valid; this.content = content; this.environment = environment;
    this.invalidate(); return this;
  }
  drawBehind(context: DrawContext): void {
    const c = context.canvas, d = this.density;
    this.brush.setColor(this.valid ? this.validColor : this.invalidColor); c.attachBrush(this.brush); c.drawRect(this.bounds); c.detachBrush();
    if (this.valid) {
      c.attachPen(this.pen);
      c.drawLine(0, 25 * d, this.width * d, 75 * d); c.drawLine(0, 80 * d, this.width * d, 20 * d);
      c.drawLine(this.width * .35 * d, 0, this.width * .6 * d, 104 * d); c.detachPen();
    }
    c.save(); c.translate((this.width - 30) * d / 2, (this.valid ? 37 : 25) * d); this.pin.drawBehind(context); c.restore();
    this.label?.paragraph.paint(c, (this.width * d - this.label.widthPx) / 2, 63 * d);
  }
}

// Local live-state badge. Clock ticks with unchanged active/ended state cannot
// reshape its label or allocate geometry. Width uses the same measured label.
export class DrawnLocationBadge extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private labels: DrawnTextLineCache = new DrawnTextLineCache();
  private label: DrawnTextLine | null = null;
  private brush: drawing.Brush = new drawing.Brush();
  private fill: common2D.Color = drawnColor('#EFFFFFFF');
  private activeColor: common2D.Color = drawnColor('#32B66A');
  private endedColor: common2D.Color = drawnColor('#929AA3');
  private textColor: common2D.Color = { alpha: 255, red: 0, green: 0, blue: 0 };
  private shape: drawing.RoundRect | null = null;
  private environment: string = '';
  private density: number = 0;
  private active: boolean = false;
  widthVp: number = 0;
  heightVp: number = 0;
  constructor() { super(); this.brush.setAntiAlias(true); }
  bind(ui: UIContext, environment: string, content: string, active: boolean, width: number): DrawnLocationBadge {
    const d = this.units.prepare(ui, environment).density;
    if (this.environment !== environment) { this.textColor = drawnColor(COLOR_TEXT_PRIMARY); }
    const label = this.labels.prepare(content, Math.max(1, width - 44) * d, this.units.fp2px(10.5), this.textColor, environment, true);
    const dirty = this.environment !== environment || this.density !== d || this.label !== label || this.active !== active;
    if (!dirty) { return this; }
    this.widthVp = label.widthPx / d + 28; this.heightVp = Math.max(7, label.heightPx / d) + 8;
    this.shape = new drawing.RoundRect({ left: 0, top: 0, right: this.widthVp * d, bottom: this.heightVp * d }, 12 * d, 12 * d);
    this.environment = environment; this.density = d; this.label = label; this.active = active;
    this.invalidate(); return this;
  }
  drawBehind(context: DrawContext): void {
    if (this.label === null || this.shape === null) { return; }
    const c = context.canvas, d = this.density;
    this.brush.setColor(this.fill); c.attachBrush(this.brush); c.drawRoundRect(this.shape); c.detachBrush();
    this.brush.setColor(this.active ? this.activeColor : this.endedColor); c.attachBrush(this.brush);
    c.drawCircle(11.5 * d, this.heightVp * d / 2, 3.5 * d); c.detachBrush();
    this.label.paragraph.paint(c, 20 * d, (this.heightVp * d - this.label.heightPx) / 2);
  }
}

export class DrawnLocationStop extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private labels: DrawnTextLineCache = new DrawnTextLineCache();
  private label: DrawnTextLine | null = null;
  private control: DrawnMediaControl = new DrawnMediaControl();
  private brush: drawing.Brush = new drawing.Brush();
  private foreground: common2D.Color = drawnColor('#D95B57');
  private shape: drawing.RoundRect | null = null;
  private width: number = 0;
  private height: number = 34;
  private density: number = 0;
  private glyphX: number = 0;
  constructor() { super(); this.brush.setAntiAlias(true); this.brush.setColor(drawnColor('#14D95B57')); }
  bind(ui: UIContext, environment: string, content: string, width: number, height: number = 34): DrawnLocationStop {
    const d = this.units.prepare(ui, environment).density;
    const label = this.labels.prepare(content, Math.max(1, width - 38) * d, this.units.fp2px(13), this.foreground, environment, true);
    this.control.bind(ui, environment, 16, '#00000000', '#D95B57', 'stop');
    if (this.width === width && this.height === height && this.density === d && this.label === label) { return this; }
    this.shape = new drawing.RoundRect({ left: 0, top: 0, right: width * d, bottom: height * d }, 8 * d, 8 * d);
    this.glyphX = Math.max(0, (width * d - label.widthPx - 22 * d) / 2);
    this.width = width; this.height = height; this.density = d; this.label = label; this.invalidate(); return this;
  }
  drawBehind(context: DrawContext): void {
    if (this.label === null || this.shape === null) { return; }
    const c = context.canvas, d = this.density;
    c.attachBrush(this.brush); c.drawRoundRect(this.shape); c.detachBrush();
    c.save(); c.translate(this.glyphX, (this.height - 16) / 2 * d); this.control.drawBehind(context); c.restore();
    this.label.paragraph.paint(c, this.glyphX + 22 * d, (this.height * d - this.label.heightPx) / 2);
  }
}
