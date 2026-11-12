import { UIContext } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export class DrawnReplyQuote {
  sender: DrawnTextLine;
  excerpt: DrawnTextLine;
  widthPx: number;
  heightPx: number;
  density: number;
  mediaWidthPx: number;
  accent: common2D.Color;
  fill: common2D.Color;

  constructor(sender: DrawnTextLine, excerpt: DrawnTextLine, density: number,
    accent: common2D.Color, fill: common2D.Color, mediaWidthPx: number = 0) {
    this.sender = sender; this.excerpt = excerpt; this.density = density;
    this.mediaWidthPx = mediaWidthPx;
    this.widthPx = Math.max(sender.widthPx, excerpt.widthPx) + 16 * density + mediaWidthPx;
    this.heightPx = 38 * density; // two 16vp lines + 3vp top/bottom padding
    this.accent = accent; this.fill = fill;
  }

  paint(canvas: drawing.Canvas, brush: drawing.Brush, background: drawing.RoundRect,
    stripe: common2D.Rect, clip: common2D.Rect): void {
    brush.setColor(this.fill);
    canvas.attachBrush(brush); canvas.drawRoundRect(background); canvas.detachBrush();
    canvas.save();
    canvas.clipRoundRect(background);
    brush.setColor(this.accent);
    canvas.attachBrush(brush); canvas.drawRect(stripe); canvas.detachBrush();
    canvas.restore();
    // Fixed native quote rows clip large-font glyphs to the same two-line box.
    canvas.save(); canvas.clipRect(clip);
    this.sender.paragraph.paint(canvas, 10 * this.density + this.mediaWidthPx, 3 * this.density);
    this.excerpt.paragraph.paint(canvas, 10 * this.density + this.mediaWidthPx, 19 * this.density);
    canvas.restore();
  }
}

export class DrawnReplyQuoteCache {
  private sender: DrawnTextLineCache = new DrawnTextLineCache();
  private excerpt: DrawnTextLineCache = new DrawnTextLineCache();
  private current: DrawnReplyQuote | null = null;
  private appearance: string = '';
  private accent: ResourceColor = '';
  private foreground: ResourceColor = '';
  private fill: ResourceColor = '';

  prepare(ui: UIContext, sender: string, excerpt: string, maxPx: number, accent: ResourceColor,
    foreground: ResourceColor, fill: ResourceColor, textEnvironment: string, appearance: string, hasMedia: boolean = false): DrawnReplyQuote {
    const density: number = ui.vp2px(1);
    const mediaWidthPx = hasMedia ? 38 * density : 0;
    const limit: number = Math.max(1, Math.min(maxPx - 16 * density - mediaWidthPx, Math.round(maxPx / density * 0.76) * density));
    const senderLine = this.sender.prepare(sender, limit, ui.fp2px(12), drawnColor(accent), textEnvironment,
      false, 16 * density);
    const excerptLine = this.excerpt.prepare(excerpt, limit, ui.fp2px(12), drawnColor(foreground), textEnvironment,
      false, 16 * density);
    if (this.current !== null && this.current.sender === senderLine && this.current.excerpt === excerptLine &&
      this.current.density === density && this.current.mediaWidthPx === mediaWidthPx && this.appearance === appearance && this.accent === accent &&
      this.foreground === foreground && this.fill === fill) { return this.current; }
    this.current = new DrawnReplyQuote(senderLine, excerptLine, density, drawnColor(accent), drawnColor(fill), mediaWidthPx);
    this.appearance = appearance; this.accent = accent; this.foreground = foreground; this.fill = fill;
    return this.current;
  }
}
