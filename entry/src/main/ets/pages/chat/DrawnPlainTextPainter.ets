import { DrawContext } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';
import { DrawnPlainTextLayout } from './DrawnPlainTextLayout';

// One instance per row, bound to one empty Row. Layout is already complete when
// drawBehind runs: no ParagraphBuilder, native text measurement or SVG parsing
// happens on the draw path.
export class DrawnPlainTextPainter extends DrawModifier {
  private layout: DrawnPlainTextLayout | null = null;
  private sendState: string = '';
  private shadowOn: boolean = false;
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private shadow: drawing.Brush = new drawing.Brush();

  private statusWidth: number = 0;
  constructor() {
    super(); this.brush.setAntiAlias(true); this.pen.setAntiAlias(true); this.shadow.setAntiAlias(true);
    this.pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
  }

  bind(layout: DrawnPlainTextLayout | null, sendState: string, shadowOn: boolean): DrawnPlainTextPainter {
    if (this.layout === layout && this.sendState === sendState && this.shadowOn === shadowOn) { return this; }
    if (layout !== null && this.layout?.density !== layout.density) {
      this.shadow.setColor({ alpha: 20, red: 0, green: 0, blue: 0 });
      this.shadow.setMaskFilter(drawing.MaskFilter.createBlurMaskFilter(drawing.BlurType.NORMAL,
        (2 * 0.57735 + 0.5) * layout.density));
    }
    if (layout !== null) {
      const width = Math.max(layout.density, layout.iconPx / 10);
      if (width !== this.statusWidth) { this.pen.setStrokeWidth(width); this.statusWidth = width; }
    }
    this.layout = layout;
    this.sendState = sendState;
    this.shadowOn = shadowOn;
    this.invalidate();
    return this;
  }

  drawBehind(context: DrawContext): void {
    const layout = this.layout;
    if (layout === null) { return; }
    const canvas = context.canvas;
    if (this.shadowOn) {
      canvas.save();
      canvas.translate(0, layout.density);
      canvas.attachBrush(this.shadow);
      canvas.drawPath(layout.outline);
      canvas.detachBrush();
      canvas.restore();
    }
    this.brush.setColor(layout.fill);
    canvas.attachBrush(this.brush);
    canvas.drawPath(layout.outline);
    canvas.detachBrush();
    if (layout.header !== null) {
      canvas.save(); canvas.translate(layout.bodyX, layout.headerY);
      layout.header.paint(canvas, this.brush);
      canvas.restore();
    }
    if (layout.quote !== null && layout.replyBackground !== null && layout.replyStripe !== null &&
      layout.replyClip !== null) {
      canvas.save(); canvas.translate(layout.bodyX, layout.replyY);
      layout.quote.paint(canvas, this.brush, layout.replyBackground, layout.replyStripe, layout.replyClip);
      canvas.restore();
    }
    layout.body.paint(canvas, layout.bodyX, layout.bodyY);
    layout.footer.paint(canvas, layout.footerX, layout.footerY);
    if (layout.outgoing && this.sendState !== '' && this.sendState !== 'none') {
      this.drawStatus(canvas, layout);
    }
  }

  private drawStatus(canvas: drawing.Canvas, layout: DrawnPlainTextLayout): void {
    const size: number = layout.iconPx;
    const x: number = layout.statusX;
    const y: number = layout.statusY;
    this.pen.setColor(this.sendState === 'failed' ? { alpha: 255, red: 255, green: 0, blue: 0 }
      : (this.sendState === 'read' ? layout.accent : layout.secondary));
    canvas.attachPen(this.pen);
    if (this.sendState === 'sending' || this.sendState === 'failed') {
      canvas.drawCircle(x + size / 2, y + size / 2, size * 0.4);
      canvas.drawLine(x + size / 2, y + size * 0.24, x + size / 2, y + size * 0.52);
      if (this.sendState === 'sending') {
        canvas.drawLine(x + size / 2, y + size * 0.52, x + size * 0.72, y + size * 0.62);
      } else {
        canvas.drawLine(x + size / 2, y + size * 0.73, x + size / 2, y + size * 0.74);
      }
    } else {
      canvas.drawLine(x + size * 0.12, y + size * 0.53, x + size * 0.4, y + size * 0.78);
      canvas.drawLine(x + size * 0.4, y + size * 0.78, x + size * 0.9, y + size * 0.22);
      if (this.sendState === 'read') {
        canvas.drawLine(x + size * 0.52, y + size * 0.68, x + size * 0.73, y + size * 0.78);
        canvas.drawLine(x + size * 0.73, y + size * 0.78, x + size * 1.23, y + size * 0.22);
      }
    }
    canvas.detachPen();
  }
}
