import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { placeDrawnFooter } from '../../util/drawnFooterPlacement';
import { DrawnSenderHeader } from './DrawnSenderHeader';
import { DrawnReplyQuote } from './DrawnReplyQuote';
import { i18n } from '@kit.LocalizationKit';
import { systemDateTime } from '@kit.BasicServicesKit';
import { ColorMetrics, UIContext } from '@kit.ArkUI';
import { common2D, drawing, text } from '@kit.ArkGraphics2D';
import { glassBubbleCommands } from '../../util/bubbleGlassPath';
import { drawnTextMetrics } from '../../util/drawnTextMetrics';
import {
  DrawnPlainLayoutCache, DrawnPlainTextSpec, drawnTailGutter, sameDrawnPlainTextSpec,
  sameDrawnPlainParagraphSpec, snapshotDrawnPlainTextSpec
} from '../../util/drawnPlainTextPolicy';

let drawnLocaleEpoch: string = '';
let drawnLocaleRtl: boolean = false;
export function drawnTextUsesRtlLayout(epoch: string): boolean {
  if (drawnLocaleEpoch !== epoch) {
    try {
      drawnLocaleRtl = i18n.isRTL(i18n.System.getAppPreferredLanguage());
      drawnLocaleEpoch = epoch;
    } catch (_error) { return true; }
  }
  return drawnLocaleRtl;
}

function drawColor(color: ResourceColor): common2D.Color {
  const resolved = ColorMetrics.resourceColor(color);
  return { alpha: resolved.alpha, red: resolved.red, green: resolved.green, blue: resolved.blue };
}

function sameColor(a: common2D.Color, b: common2D.Color): boolean {
  return a.alpha === b.alpha && a.red === b.red && a.green === b.green && a.blue === b.blue;
}

function layoutClockMs(): number {
  try { return systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, true) / 1000000; }
  catch (_error) { return Number.NaN; }
}

// Owned by one row's bounded cache, never shared across active row instances.
// Colors are mutable; geometry and paragraphs stay intact during decoration edits.
class DrawnPlainParagraphs {
  body: text.Paragraph;
  footer: text.Paragraph;
  widthPx: number;
  heightPx: number;
  footerWidth: number;
  footerHeight: number;
  lastLineRight: number;
  lastLineTop: number;
  iconPx: number;
  private foreground: common2D.Color;
  private secondary: common2D.Color;

  constructor(body: text.Paragraph, footer: text.Paragraph, widthPx: number, heightPx: number,
    footerWidth: number, footerHeight: number, lastLineRight: number, lastLineTop: number, iconPx: number,
    foreground: common2D.Color, secondary: common2D.Color) {
    this.body = body; this.footer = footer;
    this.widthPx = widthPx; this.heightPx = heightPx;
    this.footerWidth = footerWidth; this.footerHeight = footerHeight;
    this.lastLineRight = lastLineRight; this.lastLineTop = lastLineTop; this.iconPx = iconPx;
    this.foreground = foreground; this.secondary = secondary;
  }

  recolor(foreground: common2D.Color, secondary: common2D.Color): void {
    if (!sameColor(this.foreground, foreground)) {
      this.body.updateColor(foreground);
      this.foreground = foreground;
      drawnTextMetrics.colorUpdated();
    }
    if (!sameColor(this.secondary, secondary)) {
      this.footer.updateColor(secondary);
      this.secondary = secondary;
      drawnTextMetrics.colorUpdated();
    }
  }
}

export class DrawnPlainTextLayout {
  widthVp: number = 0;
  heightVp: number = 0;
  density: number = 1;
  bodyX: number = 0;
  bodyY: number = 0;
  footerX: number = 0;
  footerY: number = 0;
  statusX: number = 0;
  statusY: number = 0;
  iconPx: number = 12;
  outgoing: boolean = false;
  body: text.Paragraph;
  footer: text.Paragraph;
  outline: drawing.Path;
  fill: common2D.Color;
  foreground: common2D.Color;
  secondary: common2D.Color;
  accent: common2D.Color;
  header: DrawnSenderHeader | null = null;
  quote: DrawnReplyQuote | null = null;
  contentWidthPx: number = 0;
  headerY: number = 0;
  replyY: number = 0;
  replyBackground: drawing.RoundRect | null = null;
  replyStripe: common2D.Rect | null = null;
  replyClip: common2D.Rect | null = null;
  private paragraphs: DrawnPlainParagraphs;

  constructor(paragraphs: DrawnPlainParagraphs, outline: drawing.Path, fill: common2D.Color,
    foreground: common2D.Color, secondary: common2D.Color, accent: common2D.Color) {
    this.paragraphs = paragraphs;
    this.body = paragraphs.body; this.footer = paragraphs.footer;
    this.outline = outline; this.fill = fill;
    this.foreground = foreground; this.secondary = secondary; this.accent = accent;
  }

  ensureColors(): void { this.paragraphs.recolor(this.foreground, this.secondary); }
}

// One last paint plan per cached paragraph pair preserves A -> B -> A reuse
// without a second independent cache retaining extra native paragraphs.
class DrawnPlainParagraphEntry {
  paragraphs: DrawnPlainParagraphs;
  planSpec: DrawnPlainTextSpec | null = null;
  plan: DrawnPlainTextLayout | null = null;
  outlineKey: string = '';
  outline: drawing.Path | null = null;
  constructor(paragraphs: DrawnPlainParagraphs) { this.paragraphs = paragraphs; }
}

export class DrawnPlainTextLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private paragraphs: DrawnPlainLayoutCache<DrawnPlainTextSpec, DrawnPlainParagraphEntry> =
    new DrawnPlainLayoutCache<DrawnPlainTextSpec, DrawnPlainParagraphEntry>(sameDrawnPlainParagraphSpec);
  private currentSpec: DrawnPlainTextSpec | null = null;
  private currentLayout: DrawnPlainTextLayout | null = null;
  private currentEnvironment: string = '';

  prepare(ui: UIContext, spec: DrawnPlainTextSpec, header: DrawnSenderHeader | null = null,
    quote: DrawnReplyQuote | null = null): DrawnPlainTextLayout {
    drawnTextMetrics.request();
    try { return this.prepareCurrent(ui, spec, header, quote); }
    catch (error) { drawnTextMetrics.failure(); throw error as Error; }
  }

  private prepareCurrent(ui: UIContext, spec: DrawnPlainTextSpec, header: DrawnSenderHeader | null,
    quote: DrawnReplyQuote | null): DrawnPlainTextLayout {
    this.units.prepare(ui, spec.textEnvironment);
    const density: number = this.units.density;
    const fontPx: number = this.units.fp2px(spec.fontSize);
    const smallPx: number = this.units.fp2px(11);
    const environment: string = `${spec.textEnvironment}:${density}:${fontPx}:${smallPx}`;
    if (this.currentLayout !== null && this.currentSpec !== null &&
      this.currentEnvironment === environment && this.currentLayout.header === header &&
      this.currentLayout.quote === quote && sameDrawnPlainTextSpec(this.currentSpec, spec)) {
      // Restore colors even after a failed attempt to assemble another plan.
      this.currentLayout.ensureColors();
      drawnTextMetrics.planHit();
      return this.currentLayout;
    }
    this.paragraphs.prepare(environment);
    const fill = drawColor(spec.fill);
    const foreground = drawColor(spec.foreground);
    const secondary = drawColor(spec.secondary);
    const accent = drawColor(spec.accent);
    let entry = this.paragraphs.get(spec);
    if (entry === undefined) {
      const timed: boolean = drawnTextMetrics.paragraphMiss();
      const start: number = timed ? layoutClockMs() : Number.NaN;
      const paragraphs = this.buildParagraphs(ui, spec, density, fontPx, smallPx, foreground, secondary);
      if (timed) { drawnTextMetrics.sampleBuild(layoutClockMs() - start); }
      drawnTextMetrics.paragraphBuilt();
      entry = new DrawnPlainParagraphEntry(paragraphs);
      this.paragraphs.put(snapshotDrawnPlainTextSpec(spec), entry);
    } else if (entry.plan !== null && entry.planSpec !== null && entry.plan.header === header &&
      entry.plan.quote === quote && sameDrawnPlainTextSpec(entry.planSpec, spec)) {
      entry.plan.ensureColors();
      this.currentSpec = entry.planSpec;
      this.currentLayout = entry.plan;
      this.currentEnvironment = environment;
      drawnTextMetrics.planHit();
      return entry.plan;
    } else {
      drawnTextMetrics.paragraphHit();
    }
    const paragraphs = entry.paragraphs;
    const gutter: number = drawnTailGutter(spec.tail);
    const footerPlacement = placeDrawnFooter({
      maxWidthPx: Math.floor((spec.maxWidthVp - 16) * density),
      bodyWidthPx: paragraphs.widthPx, bodyHeightPx: paragraphs.heightPx,
      lastLineRightPx: paragraphs.lastLineRight, lastLineTopPx: paragraphs.lastLineTop,
      chromeWidthPx: Math.max(header?.widthPx ?? 0, quote?.widthPx ?? 0),
      footerWidthPx: paragraphs.footerWidth, footerHeightPx: paragraphs.footerHeight,
      gapPx: 4 * density, bottomGapPx: 2 * density
    });
    const contentWidth: number = footerPlacement.widthPx;
    const headerSpace: number = header !== null ? header.heightPx + 2 * density : 0;
    const replySpace: number = quote !== null ? quote.heightPx + 4 * density : 0;
    const widthVp: number = contentWidth / density + 16 + gutter;
    const heightVp: number = (footerPlacement.heightPx + headerSpace + replySpace) / density + 16;
    const outline = this.prepareOutline(entry, spec, widthVp, heightVp, density, gutter);
    const result = new DrawnPlainTextLayout(paragraphs, outline, fill, foreground, secondary, accent);
    result.widthVp = widthVp; result.heightVp = heightVp; result.density = density;
    result.bodyX = (8 + (spec.outgoing ? 0 : gutter)) * density;
    result.header = header; result.quote = quote; result.contentWidthPx = contentWidth;
    result.headerY = 8 * density;
    result.replyY = result.headerY + headerSpace;
    result.bodyY = result.replyY + replySpace;
    if (quote !== null) {
      result.replyBackground = new drawing.RoundRect({ left: 0, top: 0,
        right: contentWidth, bottom: quote.heightPx }, 4 * density, 4 * density);
      result.replyStripe = { left: 0, top: 0, right: 4 * density, bottom: quote.heightPx };
      result.replyClip = { left: 10 * density, top: 3 * density,
        right: contentWidth - 6 * density, bottom: quote.heightPx - 3 * density };
    }
    result.footerX = result.bodyX + contentWidth - paragraphs.footerWidth;
    result.footerY = result.bodyY + footerPlacement.footerYPx;
    result.statusX = result.bodyX + contentWidth - paragraphs.iconPx * 4 / 3;
    result.statusY = result.footerY + (paragraphs.footerHeight - paragraphs.iconPx) / 2;
    result.iconPx = paragraphs.iconPx; result.outgoing = spec.outgoing;
    result.ensureColors();
    entry.planSpec = snapshotDrawnPlainTextSpec(spec);
    entry.plan = result;
    this.currentSpec = entry.planSpec;
    this.currentLayout = result;
    this.currentEnvironment = environment;
    return result;
  }

  private prepareOutline(entry: DrawnPlainParagraphEntry, spec: DrawnPlainTextSpec, widthVp: number, heightVp: number,
    density: number, gutter: number): drawing.Path {
    // Fixed-size geometry key; no text or message identity is serialized.
    const key: string = `${widthVp}:${heightVp}:${density}:${spec.outgoing}:${spec.tail}:` +
      `${spec.topLeft}:${spec.topRight}:${spec.bottomRight}:${spec.bottomLeft}`;
    if (entry.outline !== null && entry.outlineKey === key) { return entry.outline; }
    const outline = new drawing.Path();
    if (!outline.buildFromSvgString(glassBubbleCommands(widthVp, heightVp, spec.outgoing, spec.tail,
      spec.topLeft, spec.topRight, spec.bottomRight, spec.bottomLeft, 8, 12, density, 0, gutter))) {
      throw new Error('invalid drawn bubble outline');
    }
    entry.outline = outline; entry.outlineKey = key;
    drawnTextMetrics.outlineBuilt();
    return outline;
  }

  private buildParagraphs(ui: UIContext, spec: DrawnPlainTextSpec, density: number,
    fontPx: number, smallPx: number, foreground: common2D.Color, secondary: common2D.Color): DrawnPlainParagraphs {
    const fonts = text.FontCollection.getGlobalInstance();
    const maxPx: number = Math.floor((spec.maxWidthVp - 16) * density);
    if (maxPx <= 0) { throw new Error('invalid drawn content width'); }
    const bodyBuilder = new text.ParagraphBuilder({
      textStyle: { fontSize: fontPx, color: foreground, heightOnly: true, heightScale: 1.34, halfLeading: true },
      wordBreak: text.WordBreak.BREAK_WORD, textDirection: text.TextDirection.LTR, align: text.TextAlign.LEFT
    }, fonts);
    bodyBuilder.addText(spec.content);
    const body = bodyBuilder.build();
    drawnTextMetrics.layoutCall();
    body.layoutSync(maxPx);
    // Wrap once using the full available width. Shrink only the outer shell;
    // the left-aligned paragraph keeps its original glyph and line positions.
    const widthPx: number = Math.ceil(body.getLongestLine());
    const bodyHeight: number = Math.ceil(body.getHeight());
    if (!Number.isFinite(widthPx) || widthPx < 0 || widthPx > maxPx + 1 || !Number.isFinite(bodyHeight) || bodyHeight <= 0) {
      throw new Error('invalid drawn paragraph size');
    }
    const last = body.getLineMetrics(body.getLineCount() - 1);
    // Unknown metrics force a separate footer row rather than guessing an overlap.
    const lastRight: number = last !== undefined ? last.left + last.width : Number.NaN;
    const lastTop: number = last !== undefined ? Math.max(0, last.baseline - last.ascent) : Number.NaN;
    const footerBuilder = new text.ParagraphBuilder({ textStyle: { fontSize: smallPx, color: secondary } }, fonts);
    if (spec.edited !== '') {
      footerBuilder.pushStyle({ fontSize: this.units.fp2px(10.5), color: secondary });
      footerBuilder.addText(spec.edited);
      footerBuilder.popStyle();
      footerBuilder.addPlaceholder({ width: 4 * density, height: 0,
        align: text.PlaceholderAlignment.BOTTOM_OF_ROW_BOX,
        baseline: text.TextBaseline.ALPHABETIC, baselineOffset: 0 });
    }
    footerBuilder.addText(spec.time);
    const footer = footerBuilder.build();
    drawnTextMetrics.layoutCall();
    footer.layoutSync(maxPx);
    const iconPx: number = this.units.fp2px(12);
    const statusWidth: number = spec.outgoing ? iconPx * 4 / 3 + 4 * density : 0;
    const footerWidth: number = Math.ceil(footer.getMaxIntrinsicWidth()) + statusWidth;
    const footerHeight: number = Math.max(footer.getHeight(), spec.outgoing ? iconPx : 0);
    if (footerWidth > maxPx) { throw new Error('drawn footer exceeds content width'); }
    return new DrawnPlainParagraphs(body, footer, widthPx, bodyHeight, footerWidth,
      footerHeight, lastRight, lastTop, iconPx, foreground, secondary);
  }
}
