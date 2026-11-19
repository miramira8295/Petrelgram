import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { drawnColor } from './DrawnTextLine';

// Native Slider owns input/keyboard/accessibility; this retained display list
// owns only its track and thumb. Progress is O(1), without geometry allocation.
export class DrawnSeekTrack extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private track: drawing.Pen = new drawing.Pen();
  private fill: drawing.Pen = new drawing.Pen();
  private thumb: drawing.Brush = new drawing.Brush();
  private color: ResourceColor = '';
  private background: ResourceColor = '';
  private environment: string = '';
  private density: number = 0;
  private width: number = 0;
  private height: number = 0;
  private left: number = 0;
  private right: number = 0;
  private y: number = 0;
  private radius: number = 0;
  private fraction: number = 0;
  private dragging: boolean = false;
  constructor() {
    super(); this.track.setAntiAlias(true); this.fill.setAntiAlias(true); this.thumb.setAntiAlias(true);
    this.track.setCapStyle(drawing.CapStyle.ROUND_CAP); this.fill.setCapStyle(drawing.CapStyle.ROUND_CAP);
  }
  bind(ui: UIContext, environment: string, width: number, height: number, fraction: number,
    dragging: boolean, color: ResourceColor, background: ResourceColor): DrawnSeekTrack {
    const d = this.units.prepare(ui, environment).density;
    const progress = Number.isFinite(fraction) ? Math.max(0, Math.min(1, fraction)) : 0;
    let dirty = false;
    if (this.density !== d || this.width !== width || this.height !== height) {
      this.width = width; this.height = height; this.density = d;
      this.left = Math.min(8, Math.max(0, width) / 2) * d;
      this.right = Math.max(this.left, width * d - this.left); this.y = height * d / 2;
      this.radius = Math.max(0, Math.min(8, width / 2, height / 2)) * d;
      this.track.setStrokeWidth(2 * d); this.fill.setStrokeWidth(2 * d); dirty = true;
    }
    if (this.environment !== environment || this.color !== color || this.background !== background) {
      const foreground: common2D.Color = drawnColor(color);
      this.track.setColor(drawnColor(background)); this.fill.setColor(foreground); this.thumb.setColor(foreground);
      this.color = color; this.background = background; this.environment = environment; dirty = true;
    }
    if (dirty || this.fraction !== progress || this.dragging !== dragging) {
      this.fraction = progress; this.dragging = dragging; this.invalidate();
    }
    return this;
  }
  drawForeground(context: DrawContext): void {
    if (!(this.width > 0 && this.height > 0)) { return; }
    const c = context.canvas, x = this.left + (this.right - this.left) * this.fraction;
    c.attachPen(this.track); c.drawLine(this.left, this.y, this.right, this.y); c.detachPen();
    if (this.fraction > 0) { c.attachPen(this.fill); c.drawLine(this.left, this.y, x, this.y); c.detachPen(); }
    c.attachBrush(this.thumb); c.drawCircle(x, this.y, this.radius * (this.dragging ? 1 : .75)); c.detachBrush();
  }
}
