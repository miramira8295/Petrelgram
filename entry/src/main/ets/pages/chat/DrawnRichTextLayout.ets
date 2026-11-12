import { ColorMetrics, UIContext } from '@kit.ArkUI';
import { common2D, text } from '@kit.ArkGraphics2D';
import { DrawnPlainLayoutCache } from '../../util/drawnPlainTextPolicy';
import { DrawnRichHitIndex } from '../../util/drawnRichHitIndex';
import { appendDrawnRichHits, DrawnRichHit, DrawnRichRect, DrawnRichSource } from '../../util/drawnRichTextPolicy';

export interface DrawnRichTextSpec {
  source: DrawnRichSource;
  maxWidthVp: number;
  minWidthVp: number;
  fontSize: number;
  reserve: string;
  foreground: ResourceColor;
  accent: ResourceColor;
  environment: string;
}

function sameRichSpec(a: DrawnRichTextSpec, b: DrawnRichTextSpec): boolean {
  return a.source === b.source && a.maxWidthVp === b.maxWidthVp && a.minWidthVp === b.minWidthVp &&
    a.fontSize === b.fontSize && a.reserve === b.reserve && a.foreground === b.foreground &&
    a.accent === b.accent && a.environment === b.environment;
}

function richSpecSnapshot(spec: DrawnRichTextSpec): DrawnRichTextSpec {
  return { source: spec.source, maxWidthVp: spec.maxWidthVp, minWidthVp: spec.minWidthVp,
    fontSize: spec.fontSize, reserve: spec.reserve, foreground: spec.foreground,
    accent: spec.accent, environment: spec.environment };
}

function richColor(color: ResourceColor): common2D.Color {
  const c = ColorMetrics.resourceColor(color);
  return { alpha: c.alpha, red: c.red, green: c.green, blue: c.blue };
}

export interface DrawnInlineEmojiPlacement {
  id: string;
  rect: common2D.Rect;
  fallback: text.Paragraph;
  fallbackY: number;
  color: common2D.Color;
}

export class DrawnRichTextLayout {
  readonly emojis: DrawnInlineEmojiPlacement[] = [];
  emojiSizeVp: number = 0;
  density: number = 1;
  paragraph: text.Paragraph;
  widthVp: number;
  heightVp: number;
  source: DrawnRichSource;
  hits: DrawnRichHit[];
  hitIndex: DrawnRichHitIndex;
  // Built once per paragraph: O(H) space/time; a busy URL lookup is O(1).
  readonly hitsByUrl: Map<string, DrawnRichHit[]> = new Map();
  constructor(paragraph: text.Paragraph, widthVp: number, heightVp: number,
    source: DrawnRichSource, hits: DrawnRichHit[]) {
    this.paragraph = paragraph; this.widthVp = widthVp; this.heightVp = heightVp;
    this.source = source; this.hits = hits;
    this.hitIndex = new DrawnRichHitIndex(hits);
    for (const hit of hits) {
      let group = this.hitsByUrl.get(hit.link.url);
      if (group === undefined) { group = []; this.hitsByUrl.set(hit.link.url, group); }
      group.push(hit);
    }
  }
}

export class DrawnRichTextLayouts {
  private cache: DrawnPlainLayoutCache<DrawnRichTextSpec, DrawnRichTextLayout> =
    new DrawnPlainLayoutCache<DrawnRichTextSpec, DrawnRichTextLayout>(sameRichSpec);
  private generation: number = 0;
  private environment: string = '';
  private failedSpec: DrawnRichTextSpec | null = null;

  prepare(ui: UIContext, spec: DrawnRichTextSpec): DrawnRichTextLayout {
    const density: number = ui.vp2px(1);
    const fontPx: number = ui.fp2px(spec.fontSize);
    const reservePx: number = ui.fp2px(14);
    const linePx: number = ui.fp2px(spec.fontSize * 1.34);
    const environment: string = `${spec.environment}:${density}:${fontPx}:${reservePx}:${linePx}`;
    if (this.environment !== environment) { this.failedSpec = null; this.environment = environment; }
    this.cache.prepare(environment);
    const hit = this.cache.get(spec);
    if (hit !== undefined) { return hit; }
    if (this.failedSpec !== null && sameRichSpec(this.failedSpec, spec)) {
      throw new Error('rich paragraph remains unavailable');
    }
    try {
      const result = this.build(spec, density, fontPx, reservePx, linePx);
      this.cache.put(richSpecSnapshot(spec), result);
      return result;
    } catch (error) {
      this.failedSpec = richSpecSnapshot(spec);
      throw error as Error;
    }
  }

  private build(spec: DrawnRichTextSpec, density: number, fontPx: number, reservePx: number,
    linePx: number): DrawnRichTextLayout {
    const maxPx: number = Math.floor(spec.maxWidthVp * density);
    if (!(maxPx > 0) || !(fontPx > 0)) { throw new Error('invalid rich paragraph geometry'); }
    const foreground = richColor(spec.foreground);
    const accent = richColor(spec.accent);
    const paragraphBuilder = new text.ParagraphBuilder({
      textStyle: { fontSize: fontPx, color: foreground, heightOnly: true, heightScale: linePx / fontPx,
        halfLeading: true },
      wordBreak: text.WordBreak.BREAK_WORD, textDirection: text.TextDirection.LTR, align: text.TextAlign.LEFT
    }, text.FontCollection.getGlobalInstance());
    // A placeholder occupies ONE UTF-16 position. Keep original source offsets
    // for copy/accessibility; project each run/link once, never scan all icons per link.
    let paragraphOffset: number = 0;
    const linkRanges: text.Range[] = [];
    const emojiFallbacks: text.Paragraph[] = [];
    const emojiIds: string[] = [];
    const emojiColors: common2D.Color[] = [];
    const fallbacks: Map<string, text.Paragraph> = new Map();
    const emojiPx: number = (spec.fontSize + 3) * density;
    for (const run of spec.source.runs) {
      const color = run.link || run.url !== '' ? accent : foreground;
      paragraphBuilder.pushStyle({ fontSize: fontPx, color,
        heightOnly: true, heightScale: linePx / fontPx, halfLeading: true,
        fontWeight: run.bold ? text.FontWeight.W700 : text.FontWeight.W400,
        fontStyle: run.italic ? text.FontStyle.ITALIC : text.FontStyle.NORMAL,
        decoration: { textDecoration: run.strike ? text.TextDecorationType.LINE_THROUGH :
          (run.underline ? text.TextDecorationType.UNDERLINE : text.TextDecorationType.NONE), color }
      });
      const length: number = run.customEmojiId === '' ? run.text.length : 1;
      if (run.url !== '') { linkRanges.push({ start: paragraphOffset, end: paragraphOffset + length }); }
      paragraphOffset += length;
      if (run.customEmojiId === '') { paragraphBuilder.addText(run.text); }
      else {
        paragraphBuilder.addPlaceholder({ width: emojiPx, height: emojiPx,
          align: text.PlaceholderAlignment.CENTER_OF_ROW_BOX, baseline: text.TextBaseline.ALPHABETIC,
          baselineOffset: 0 });
        const fallbackKey: string = `${run.text}:${run.link || run.url !== ''}`;
        let fallback = fallbacks.get(fallbackKey);
        if (fallback === undefined) {
          const builder = new text.ParagraphBuilder({ textStyle: { fontSize: fontPx, color },
            maxLines: 1, align: text.TextAlign.CENTER, textDirection: text.TextDirection.LTR },
            text.FontCollection.getGlobalInstance());
          builder.addText(run.text); fallback = builder.build(); fallback.layoutSync(emojiPx);
          fallbacks.set(fallbackKey, fallback);
        }
        emojiIds.push(run.customEmojiId); emojiColors.push(color); emojiFallbacks.push(fallback);
      }
      paragraphBuilder.popStyle();
    }
    if (spec.reserve !== '') {
      // Keep the existing rich shell's transparent time reservation, including
      // its 14fp wrapped-line height. Footer painting still belongs to the shell.
      paragraphBuilder.pushStyle({ fontSize: reservePx, color: { alpha: 0, red: 0, green: 0, blue: 0 },
        heightOnly: true, heightScale: linePx / reservePx, halfLeading: true });
      paragraphBuilder.addText(spec.reserve);
      paragraphBuilder.popStyle();
    }
    const paragraph = paragraphBuilder.build();
    paragraph.layoutSync(maxPx);
    // getLongestLine may exclude trailing whitespace. Outgoing timeReserve
    // ends with spaces for the status icon; include their actual laid-out
    // boxes instead of losing the slot or doing a second paragraph layout.
    let reservedRight: number = 0;
    if (spec.reserve !== '') {
      const reserveBoxes = paragraph.getRectsForRange({ start: paragraphOffset,
        end: paragraphOffset + spec.reserve.length }, text.RectWidthStyle.TIGHT, text.RectHeightStyle.TIGHT);
      if (reserveBoxes.length === 0) { throw new Error('missing rich footer reservation'); }
      for (const box of reserveBoxes) { reservedRight = Math.max(reservedRight, box.rect.right); }
    }
    const widthPx: number = Math.min(maxPx, Math.max(Math.ceil(paragraph.getLongestLine()), Math.ceil(reservedRight),
      Math.min(maxPx, spec.minWidthVp * density)));
    const heightPx: number = Math.ceil(paragraph.getHeight());
    if (!Number.isFinite(widthPx) || !Number.isFinite(heightPx) || widthPx <= 0 || heightPx <= 0) {
      throw new Error('invalid rich paragraph metrics');
    }
    const hits: DrawnRichHit[] = [];
    const generation: number = ++this.generation;
    for (let index: number = 0; index < spec.source.links.length; index++) {
      const link = spec.source.links[index];
      const boxes: DrawnRichRect[] = paragraph.getRectsForRange(linkRanges[index],
        text.RectWidthStyle.TIGHT, text.RectHeightStyle.TIGHT)
        .map((box: text.TextBox): DrawnRichRect => box.rect);
      if (!appendDrawnRichHits(hits, boxes, link, density, widthPx, heightPx, generation)) {
        throw new Error('rich link has no valid hit rectangles');
      }
    }
    const result = new DrawnRichTextLayout(paragraph, widthPx / density, heightPx / density, spec.source, hits);
    result.emojiSizeVp = spec.fontSize + 3; result.density = density;
    if (emojiIds.length > 0) {
      const boxes = paragraph.getRectsForPlaceholders();
      if (boxes.length !== emojiIds.length) { throw new Error('missing inline emoji rectangles'); }
      for (let index: number = 0; index < boxes.length; index++) {
        result.emojis.push({ id: emojiIds[index], rect: boxes[index].rect,
          fallback: emojiFallbacks[index], color: emojiColors[index],
          fallbackY: boxes[index].rect.top + (boxes[index].rect.bottom - boxes[index].rect.top -
            emojiFallbacks[index].getHeight()) / 2 });
      }
    }
    // Fixed four-entry LRU. Theme/config changes drop mixed-color paragraphs;
    // updateColor on a whole paragraph would erase its per-run colors.
    return result;
  }
}
