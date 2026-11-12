import { ColorMetrics } from '@kit.ArkUI';
import { common2D, text } from '@kit.ArkGraphics2D';

export function drawnColor(color: ResourceColor): common2D.Color {
  const resolved = ColorMetrics.resourceColor(color);
  return { alpha: resolved.alpha, red: resolved.red, green: resolved.green, blue: resolved.blue };
}

function colorsEqual(a: common2D.Color, b: common2D.Color): boolean {
  return a.alpha === b.alpha && a.red === b.red && a.green === b.green && a.blue === b.blue;
}

export class DrawnTextLine {
  paragraph: text.Paragraph;
  widthPx: number;
  heightPx: number;
  private color: common2D.Color;

  constructor(paragraph: text.Paragraph, widthPx: number, color: common2D.Color) {
    this.paragraph = paragraph;
    this.widthPx = widthPx;
    this.heightPx = paragraph.getHeight();
    this.color = color;
  }

  recolor(color: common2D.Color): void {
    if (!colorsEqual(this.color, color)) {
      this.paragraph.updateColor(color);
      this.color = color;
    }
  }
}

// One native paragraph per label slot, owned by one bubble. Paint-only changes
// update its color; asynchronous role/reply edits never invalidate body text.
export class DrawnTextLineCache {
  private current: DrawnTextLine | null = null;
  private content: string = '';
  private environment: string = '';
  private maxPx: number = 0;
  private fontPx: number = 0;
  private linePx: number = 0;
  private medium: boolean = false;

  prepare(content: string, maxPx: number, fontPx: number, color: common2D.Color,
    environment: string, medium: boolean = false, linePx: number = 0): DrawnTextLine {
    if (this.current !== null && this.content === content && this.environment === environment &&
      this.maxPx === maxPx && this.fontPx === fontPx && this.medium === medium && this.linePx === linePx) {
      this.current.recolor(color);
      return this.current;
    }
    if (!(maxPx > 0) || !(fontPx > 0)) { throw new Error('invalid drawn label width/font'); }
    const style: text.TextStyle = {
      fontSize: fontPx, color: color, fontWeight: medium ? text.FontWeight.W500 : text.FontWeight.W400,
      ellipsis: '\u2026'
    };
    if (linePx > 0) {
      style.heightOnly = true;
      style.heightScale = linePx / fontPx;
      style.halfLeading = true;
    }
    const paragraphBuilder = new text.ParagraphBuilder({ textStyle: style, maxLines: 1,
      textDirection: text.TextDirection.LTR, align: text.TextAlign.LEFT }, text.FontCollection.getGlobalInstance());
    paragraphBuilder.addText(content);
    const paragraph = paragraphBuilder.build();
    paragraph.layoutSync(maxPx);
    // Only visible laid-out glyphs determine width; hidden lines after a newline
    // must not widen a one-line reply/name.
    const width: number = Math.min(maxPx, Math.ceil(paragraph.getLongestLine()));
    if (!Number.isFinite(width) || !Number.isFinite(paragraph.getHeight())) {
      throw new Error('invalid drawn label metrics');
    }
    const result = new DrawnTextLine(paragraph, width, color);
    this.current = result;
    this.content = content; this.environment = environment; this.maxPx = maxPx;
    this.fontPx = fontPx; this.medium = medium; this.linePx = linePx;
    return result;
  }
}
