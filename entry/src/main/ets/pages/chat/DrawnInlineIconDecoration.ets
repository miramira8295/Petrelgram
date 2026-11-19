import { DrawContext, UIContext } from '@kit.ArkUI';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { COLOR_TEXT_PRIMARY } from '../../util/theme';
import { DrawnMediaControl } from './DrawnMediaControl';

// Only the unresolved inline document uses this placeholder. Scale the retained
// picture glyph to the actual span box, including sub-24vp inline icons.
export class DrawnInlineIconDecoration extends DrawModifier {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private icon: DrawnMediaControl = new DrawnMediaControl();
  private width: number = 0;
  private height: number = 0;
  private density: number = 0;
  private scale: number = 0;
  private environment: string = '';
  bind(ui: UIContext, environment: string, width: number, height: number): DrawnInlineIconDecoration {
    const d = this.units.prepare(ui, environment).density;
    if (this.width === width && this.height === height && this.density === d && this.environment === environment) { return this; }
    this.icon.bind(ui, environment, 24, '#00000000', COLOR_TEXT_PRIMARY, 'photo');
    this.width = Math.max(0, width); this.height = Math.max(0, height);
    this.scale = Math.min(this.width, this.height) / 24;
    this.density = d; this.environment = environment; this.invalidate(); return this;
  }
  drawBehind(context: DrawContext): void {
    if (!(this.scale > 0)) { return; }
    const c = context.canvas, d = this.density;
    c.save(); c.translate((this.width - 24 * this.scale) * d / 2, (this.height - 24 * this.scale) * d / 2);
    c.scale(this.scale, this.scale); this.icon.drawBehind(context); c.restore();
  }
}
