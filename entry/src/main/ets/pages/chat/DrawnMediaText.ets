import { DrawContext, UIContext } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { drawnFirstStrongRtl } from '../../util/drawnTextDirection';
import { drawnColor } from './DrawnTextLine';

class DrawnMediaParagraph {
  paragraph: text.Paragraph;
  height: number;
  width: number;
  private color: ResourceColor;
  constructor(paragraph: text.Paragraph, color: ResourceColor, maxWidth: number) {
    this.paragraph = paragraph; this.height = paragraph.getHeight(); this.color = color;
    this.width = Math.max(1, Math.min(maxWidth, Math.ceil(paragraph.getLongestLine())));
  }
  recolor(color: ResourceColor): boolean {
    if (this.color === color) { return false; }
    this.color = color; this.paragraph.updateColor(drawnColor(color)); return true;
  }
}

class DrawnMediaParagraphCache {
  private current: DrawnMediaParagraph | null = null;
  private content: string = '';
  private width: number = 0;
  private font: number = 0;
  private lines: number = 0;
  private bold: boolean = false;
  private environment: string = '';
  private centered: boolean = false;
  prepare(content: string, width: number, font: number, lines: number, bold: boolean,
    color: ResourceColor, environment: string, centered: boolean = false): DrawnMediaParagraph {
    if (this.current !== null && this.content === content && this.width === width && this.font === font &&
      this.lines === lines && this.bold === bold && this.environment === environment && this.centered === centered) { return this.current; }
    const style: text.ParagraphStyle = { textStyle: { fontSize: font, color: drawnColor(color),
      fontWeight: bold ? text.FontWeight.W500 : text.FontWeight.W400, ellipsis: '\u2026' },
      textDirection: drawnFirstStrongRtl(content) ? text.TextDirection.RTL : text.TextDirection.LTR,
      align: centered ? text.TextAlign.CENTER : text.TextAlign.LEFT, wordBreak: text.WordBreak.BREAK_WORD };
    if (lines > 0) { style.maxLines = lines; }
    const builder = new text.ParagraphBuilder(style, text.FontCollection.getGlobalInstance());
    builder.addText(content);
    const paragraph = builder.build(); paragraph.layoutSync(width);
    if (!Number.isFinite(paragraph.getHeight()) || paragraph.getHeight() < 0) { throw new Error('invalid media label height'); }
    this.content = content; this.width = width; this.font = font; this.lines = lines;
    this.bold = bold; this.environment = environment; this.centered = centered;
    this.current = new DrawnMediaParagraph(paragraph, color, width); return this.current;
  }
}

export interface DrawnMediaTextPlan {
  width: number;
  height: number;
  density: number;
  top: number;
  gap: number;
  primary: DrawnMediaParagraph;
  secondary: DrawnMediaParagraph | null;
  revision: number;
}

// Cache each label independently: byte/status updates cannot reshape a filename
// or song title. Only real font/width/content changes perform paragraph layout.
export class DrawnMediaTexts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private titles: DrawnMediaParagraphCache = new DrawnMediaParagraphCache();
  private subtitles: DrawnMediaParagraphCache = new DrawnMediaParagraphCache();
  private current: DrawnMediaTextPlan | null = null;
  private revision: number = 0;
  prepare(ui: UIContext, environment: string, widthVp: number, primary: string, primarySize: number,
    primaryColor: ResourceColor, secondary: string = '', secondarySize: number = 11,
    secondaryColor: ResourceColor = '#888888', primaryLines: number = 1, bold: boolean = false,
    gap: number = 0, minHeight: number = 0, shrink: boolean = false, centered: boolean = false, secondaryLines: number = 1): DrawnMediaTextPlan {
    const units = this.units.prepare(ui, environment), density = units.density;
    const width = Math.max(1, widthVp), maxPx = width * density;
    const title = this.titles.prepare(primary, maxPx, units.fp2px(primarySize), primaryLines, bold, primaryColor, environment, centered);
    const subtitle = secondary === '' ? null : this.subtitles.prepare(secondary, maxPx,
      units.fp2px(secondarySize), secondaryLines, false, secondaryColor, environment, centered);
    let recolored = title.recolor(primaryColor);
    if (subtitle?.recolor(secondaryColor)) { recolored = true; }
    const contentHeight = title.height / density + (subtitle === null ? 0 : gap + subtitle.height / density);
    const height = Math.max(minHeight, contentHeight);
    const resultWidth = shrink && !centered ? Math.max(title.width, subtitle?.width ?? 0) / density : width;
    const old = this.current;
    if (old !== null && old.primary === title && old.secondary === subtitle && old.width === resultWidth &&
      old.height === height && old.density === density && old.gap === gap && !recolored) { return old; }
    this.current = { width: resultWidth, height, density, top: (height - contentHeight) / 2, gap,
      primary: title, secondary: subtitle, revision: ++this.revision };
    return this.current;
  }
}

export class DrawnMediaTextPainter extends DrawModifier {
  private plan: DrawnMediaTextPlan | null = null;
  private fitHeight: number = 0;
  bind(plan: DrawnMediaTextPlan, fitHeight: number = 0): DrawnMediaTextPainter {
    if (this.plan !== plan || this.fitHeight !== fitHeight) { this.plan = plan; this.fitHeight = fitHeight; this.invalidate(); }
    return this;
  }
  drawBehind(context: DrawContext): void {
    const p = this.plan;
    if (p === null) { return; }
    const canvas = context.canvas;
    const fit = this.fitHeight > 0 && p.height > this.fitHeight ? this.fitHeight / p.height : 1;
    if (fit < 1) { canvas.save(); canvas.translate(p.width * p.density * (1 - fit) / 2, 0); canvas.scale(fit, fit); }
    const y = p.top * p.density;
    p.primary.paragraph.paint(context.canvas, 0, y);
    p.secondary?.paragraph.paint(context.canvas, 0, y + p.primary.height + p.gap * p.density);
    if (fit < 1) { canvas.restore(); }
  }
}
