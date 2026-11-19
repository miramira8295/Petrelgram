import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';
import { DrawnMediaControl } from './DrawnMediaControl';

// One overlay above the required native video surface. Player/download updates
// repaint decorations, never remeasure the duration or recreate the player.
export class DrawnVideoNoteOverlay extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private labels: DrawnTextLineCache = new DrawnTextLineCache();
  private label: DrawnTextLine | null = null;
  private control: DrawnMediaControl = new DrawnMediaControl();
  private brush: drawing.Brush = new drawing.Brush();
  private background: drawing.RoundRect | null = null;
  private white: common2D.Color = { alpha: 255, red: 255, green: 255, blue: 255 };
  private side: number = 0;
  private density: number = 0;
  private playing: boolean = false;
  private progress: number = -1;
  private labelX: number = 0;
  private labelY: number = 0;
  constructor() { super(); this.brush.setAntiAlias(true); this.brush.setColor(drawnColor('#66000000')); }
  bind(ui: UIContext, environment: string, side: number, playing: boolean, progress: number,
    pending: boolean, duration: string): DrawnVideoNoteOverlay {
    const units = this.units.prepare(ui, environment), d = units.density;
    const percent = pending && progress > 0 && progress < 100 ? progress : 0;
    const label = this.labels.prepare(duration, Math.max(1, side - 20) * d, units.fp2px(11), this.white, environment);
    const shapeChanged = this.side !== side || this.density !== d || this.label !== label;
    const dirty = shapeChanged || this.playing !== playing || this.progress !== percent;
    this.control.bind(ui, environment, 56, '#00000000', '#FFFFFF', playing ? '' : 'play', percent);
    if (shapeChanged) {
      const width = Math.min(side * d, label.widthPx + 14 * d), height = Math.max(18 * d, label.heightPx + 4 * d);
      const left = (side * d - width) / 2, top = Math.max(0, (side - 9) * d - height);
      this.background = new drawing.RoundRect({ left, top, right: left + width, bottom: top + height }, 9 * d, 9 * d);
      this.labelX = (side * d - label.widthPx) / 2; this.labelY = top + (height - label.heightPx) / 2;
    }
    this.side = side; this.density = d; this.label = label; this.playing = playing; this.progress = percent;
    if (dirty) { this.invalidate(); } return this;
  }
  drawBehind(context: DrawContext): void {
    const c = context.canvas;
    if (!this.playing || this.progress > 0) {
      c.save(); c.translate((this.side - 56) * this.density / 2, (this.side - 56) * this.density / 2);
      this.control.drawBehind(context); c.restore();
    }
    if (this.background !== null) { c.attachBrush(this.brush); c.drawRoundRect(this.background); c.detachBrush(); }
    this.label?.paragraph.paint(c, this.labelX, this.labelY);
  }
}
