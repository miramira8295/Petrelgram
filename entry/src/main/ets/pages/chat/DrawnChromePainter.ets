import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnBubbleChrome } from './DrawnBubbleChrome';
import { DrawnReactionChip } from './DrawnReactionLayout';

// No shaping, geometry construction, image IO or native allocation in paint.
export class DrawnChromePainter {
  private brush: drawing.Brush = new drawing.Brush();
  private pen: drawing.Pen = new drawing.Pen();
  private placeholder: common2D.Rect = { left: 0, top: 0, right: 0, bottom: 0 };
  private pressedFill: common2D.Color = { alpha: 30, red: 0, green: 0, blue: 0 };
  private missingFill: common2D.Color = { alpha: 30, red: 128, green: 128, blue: 128 };
  private divider: common2D.Color = { alpha: 20, red: 0, green: 0, blue: 0 };

  paint(c: drawing.Canvas, p: DrawnBubbleChrome, d: number, accent: common2D.Color,
    secondary: common2D.Color, pressed: DrawnReactionChip | null): void {
    this.brush.setAntiAlias(true); this.pen.setAntiAlias(true); this.pen.setStrokeWidth(d);
    if (p.content.forward !== null) {
      p.content.forward.paragraph.paint(c, p.forwardRect.x * d, p.forwardRect.y * d);
    }
    if (p.reactions !== null) {
      c.save(); c.translate(p.reactionsX * d, p.reactionsY * d);
      for (const chip of p.reactions.chips) {
        c.save(); c.translate(chip.x * d, chip.y * d);
        if (chip.reaction !== null) {
          this.brush.setColor(chip.fill); c.attachBrush(this.brush);
          c.drawRoundRect(chip.background); c.detachBrush();
          if (chip.emoji !== null) {
            chip.emoji.paragraph.paint(c, 9 * d, (chip.height * d - chip.emoji.heightPx) / 2);
          } else if (chip.reaction.customEmojiPath === '') {
            this.placeholder.left = 9 * d; this.placeholder.top = (chip.height - 15) * d / 2;
            this.placeholder.right = 24 * d; this.placeholder.bottom = this.placeholder.top + 15 * d;
            this.brush.setColor(this.missingFill); c.attachBrush(this.brush);
            c.drawRect(this.placeholder); c.detachBrush();
          }
          if (chip.count !== null) {
            chip.count.paragraph.paint(c, (13 + chip.iconWidth) * d, (chip.height * d - chip.count.heightPx) / 2);
          }
          if (chip === pressed) {
            this.brush.setColor(this.pressedFill); c.attachBrush(this.brush);
            c.drawRoundRect(chip.background); c.detachBrush();
          }
        } else { this.chevron(c, 11 * d, chip.height * d / 2, d, secondary); }
        c.restore();
      }
      c.restore();
    }
    const text = p.content.comments;
    if (text !== null) {
      const r = p.commentsRect;
      this.pen.setColor(this.divider); c.attachPen(this.pen);
      c.drawLine(r.x * d, r.y * d, (r.x + r.width) * d, r.y * d); c.detachPen();
      text.paragraph.paint(c, p.commentsTextX * d, (r.y + 10) * d + ((r.height - 14) * d - text.heightPx) / 2);
      this.chevron(c, (r.x + r.width - 8) * d, (r.y + 10 + (r.height - 14) / 2) * d, d, accent);
    }
  }

  private chevron(c: drawing.Canvas, x: number, y: number, d: number, color: common2D.Color): void {
    this.pen.setColor(color); c.attachPen(this.pen);
    c.drawLine(x - 2 * d, y - 4 * d, x + 2 * d, y);
    c.drawLine(x + 2 * d, y, x - 2 * d, y + 4 * d); c.detachPen();
  }
}
