import { DrawContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { glassBubbleCommands } from '../../util/bubbleGlassPath';
import { cornerPx } from '../../util/bubbleCornerInset';
import { drawnColor } from './DrawnTextLine';

// Intrinsic/native islands determine their size in the normal layout pass.
// Read the final draw size directly, avoiding size -> @Local -> layout feedback.
// Only a size/style change creates a path. Steady-state paint is O(1).
export class DrawnContentOutline extends DrawModifier {
  private path: drawing.Path | null = null;
  private brush: drawing.Brush = new drawing.Brush();
  private shadow: drawing.Brush = new drawing.Brush();
  private fill: common2D.Color = { alpha: 0, red: 0, green: 0, blue: 0 };
  private width: number = -1;
  private height: number = -1;
  private density: number = 0;
  private targetDensity: number = 1;
  private geometry: string = '';
  private appearance: string = '';
  private sourceFill: ResourceColor | undefined = undefined;
  private outgoing: boolean = false;
  private tail: boolean = false;
  private corners: BorderRadiuses = {};
  private shadowOn: boolean = false;

  bind(outgoing: boolean, tail: boolean, corners: BorderRadiuses, fill: ResourceColor,
    environment: string, shadowOn: boolean, density: number): DrawnContentOutline {
    const geometry = `${outgoing}:${tail}:${cornerPx(corners.topLeft)}:${cornerPx(corners.topRight)}:` +
      `${cornerPx(corners.bottomRight)}:${cornerPx(corners.bottomLeft)}`;
    let dirty = false;
    if (density > 0 && this.targetDensity !== density) { this.targetDensity = density; dirty = true; }
    if (geometry !== this.geometry) {
      this.geometry = geometry; this.outgoing = outgoing; this.tail = tail; this.corners = corners;
      this.path = null; dirty = true;
    }
    if (environment !== this.appearance || fill !== this.sourceFill) {
      this.fill = drawnColor(fill); this.appearance = environment; this.sourceFill = fill; dirty = true;
    }
    if (this.shadowOn !== shadowOn) { this.shadowOn = shadowOn; dirty = true; }
    if (dirty) { this.invalidate(); }
    return this;
  }

  drawBehind(context: DrawContext): void {
    const pixels = context.sizeInPixel, d = this.targetDensity;
    const width = pixels.width / d, height = pixels.height / d;
    if (!(width > 7) || !(height > 0)) { return; }
    if (this.path === null || this.width !== width || this.height !== height || this.density !== d) {
      const path = new drawing.Path(), c = this.corners;
      if (!path.buildFromSvgString(glassBubbleCommands(width, height, this.outgoing, this.tail,
        cornerPx(c.topLeft), cornerPx(c.topRight), cornerPx(c.bottomRight), cornerPx(c.bottomLeft), 8, 12, d, 0, 7))) {
        return;
      }
      this.path = path; this.width = width; this.height = height;
      if (this.density !== d) {
        this.shadow.setAntiAlias(true); this.shadow.setColor({ alpha: 20, red: 0, green: 0, blue: 0 });
        this.shadow.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL, (2 * .57735 + .5) * d));
      }
      this.density = d;
    }
    const canvas = context.canvas;
    if (this.shadowOn) {
      canvas.save(); canvas.translate(0, d); canvas.attachBrush(this.shadow);
      canvas.drawPath(this.path); canvas.detachBrush(); canvas.restore();
    }
    this.brush.setAntiAlias(true); this.brush.setColor(this.fill);
    canvas.attachBrush(this.brush); canvas.drawPath(this.path); canvas.detachBrush();
  }
}
