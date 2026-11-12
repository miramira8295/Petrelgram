import { DrawContext, UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnRichHit } from '../../util/drawnRichTextPolicy';
import { DrawnRichTextLayout } from './DrawnRichTextLayout';
import { drawnColor } from './DrawnTextLine';

export class DrawnRichTextPainter extends DrawModifier {
  private plan: DrawnRichTextLayout | null = null;
  private pressRect: common2D.Rect | null = null;
  private pressBrush: drawing.Brush | null = null;

  bind(plan: DrawnRichTextLayout | null): DrawnRichTextPainter {
    if (this.plan !== plan) {
      this.plan = plan; this.pressRect = null; this.invalidate();
    }
    return this;
  }

  press(hit: DrawnRichHit, ui: UIContext): void {
    if (this.pressBrush === null) { this.pressBrush = new drawing.Brush(); }
    this.pressBrush.setColor(drawnColor($r('app.color.select_highlight')));
    const density: number = ui.vp2px(1);
    this.pressRect = { left: hit.x * density, top: hit.y * density,
      right: (hit.x + hit.widthVp) * density, bottom: (hit.y + hit.heightVp) * density };
    this.invalidate();
  }

  clearPress(): void {
    if (this.pressRect !== null) { this.pressRect = null; this.invalidate(); }
  }

  drawBehind(context: DrawContext): void {
    // No parsing, layout, rectangle queries or new native objects per frame.
    if (this.pressRect !== null && this.pressBrush !== null) {
      context.canvas.attachBrush(this.pressBrush);
      context.canvas.drawRect(this.pressRect);
      context.canvas.detachBrush();
    }
    this.plan?.paragraph.paint(context.canvas, 0, 0);
  }
}
