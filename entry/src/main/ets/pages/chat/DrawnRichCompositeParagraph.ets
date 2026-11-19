import { common2D, drawing, text } from '@kit.ArkGraphics2D';

export interface DrawnRichLineMetrics {
  left: number;
  width: number;
  baseline: number;
  ascent: number;
}

// Native paragraphs and block documents expose the same small paint/metrics
// contract. No layout, source parsing or native allocation occurs in paint().
export interface DrawnRichParagraph {
  paint(canvas: drawing.Canvas, x: number, y: number): void;
  getLineCount(): number;
  getLineMetrics(index: number): DrawnRichLineMetrics | undefined;
  getHeight(): number;
}

// Explicit adapter: ArkTS deliberately rejects structural assignment of SDK classes.
export class DrawnRichNativeParagraph implements DrawnRichParagraph {
  private native: text.Paragraph;
  private shiftX: number;
  constructor(paragraph: text.Paragraph, shiftX: number = 0) { this.native = paragraph; this.shiftX = shiftX; }
  paint(canvas: drawing.Canvas, x: number, y: number): void { this.native.paint(canvas, x + this.shiftX, y); }
  getHeight(): number { return this.native.getHeight(); }
  getLineCount(): number { return this.native.getLineCount(); }
  getLineMetrics(index: number): DrawnRichLineMetrics | undefined {
    const line = this.native.getLineMetrics(index);
    return line === undefined ? undefined : { left: line.left + this.shiftX, width: line.width,
      baseline: line.baseline, ascent: line.ascent };
  }
}

export interface DrawnRichPaintPart {
  paragraph: DrawnRichParagraph;
  x: number;
  y: number;
}

export class DrawnRichBlockBackground {
  readonly shape: drawing.RoundRect;
  readonly brush: drawing.Brush = new drawing.Brush();
  readonly stripe: common2D.Rect | null;
  readonly stripeBrush: drawing.Brush | null;
  constructor(rect: common2D.Rect, radius: number, color: common2D.Color,
    accent: common2D.Color, stripeWidth: number) {
    this.shape = new drawing.RoundRect(rect, radius, radius);
    this.brush.setAntiAlias(true); this.brush.setColor(color);
    this.stripeBrush = stripeWidth > 0 ? new drawing.Brush() : null;
    this.stripeBrush?.setAntiAlias(true); this.stripeBrush?.setColor(accent);
    this.stripe = stripeWidth > 0 ? { left: rect.left, top: rect.top,
      right: Math.min(rect.right, rect.left + stripeWidth), bottom: rect.bottom } : null;
  }
  paint(canvas: drawing.Canvas): void {
    canvas.attachBrush(this.brush); canvas.drawRoundRect(this.shape); canvas.detachBrush();
    if (this.stripe !== null && this.stripeBrush !== null) {
      canvas.attachBrush(this.stripeBrush); canvas.drawRect(this.stripe); canvas.detachBrush();
    }
  }
}

export class DrawnRichCompositeParagraph implements DrawnRichParagraph {
  readonly parts: DrawnRichPaintPart[] = [];
  readonly backgrounds: DrawnRichBlockBackground[] = [];
  readonly borders: common2D.Rect[] = [];
  borderPen: drawing.Pen | null = null;
  height: number = 0;
  // Footer placement only needs the last visual line. A block ending in a
  // control/background reserves its full width so status cannot overlap it.
  lastLine: DrawnRichLineMetrics | undefined = undefined;
  getHeight(): number { return this.height; }
  getLineCount(): number { return this.lastLine === undefined ? 0 : 1; }
  getLineMetrics(index: number): DrawnRichLineMetrics | undefined { return index === 0 ? this.lastLine : undefined; }
  paint(canvas: drawing.Canvas, x: number, y: number): void {
    canvas.save(); canvas.translate(x, y);
    for (const background of this.backgrounds) { background.paint(canvas); }
    if (this.borderPen !== null) {
      canvas.attachPen(this.borderPen);
      for (const rect of this.borders) { canvas.drawRect(rect); }
      canvas.detachPen();
    }
    for (const part of this.parts) { part.paragraph.paint(canvas, part.x, part.y); }
    canvas.restore();
  }
}
