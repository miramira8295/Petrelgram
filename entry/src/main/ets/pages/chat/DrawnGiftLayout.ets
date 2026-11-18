import { UIContext, DrawContext } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { drawnFirstStrongRtl } from '../../util/drawnTextDirection';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnGiftLayout {
  width: number;
  height: number;
  density: number;
  artworkHeight: number;
  textHeight: number;
  titleY: number;
  valueY: number;
  footerHeight: number;
  statusHeight: number;
  copyHeight: number;
  copyWidth: number;
  hasCode: boolean;
  titleText: string;
  title: text.Paragraph;
  value: text.Paragraph | null;
}

const giftLayouts: WeakMap<DrawnDocumentWidget, DrawnGiftLayout> = new WeakMap<DrawnDocumentWidget, DrawnGiftLayout>();
export function rememberGiftLayout(widget: DrawnDocumentWidget, layout: DrawnGiftLayout): void { giftLayouts.set(widget, layout); }
export function giftLayoutFor(widget: DrawnDocumentWidget): DrawnGiftLayout | null { return giftLayouts.get(widget) ?? null; }

// Colors belong to the local painter. Refund/kind changes must not reshape
// these plain paragraphs or alter the enclosing row's geometry.
class DrawnGiftParagraphs {
  private current: text.Paragraph | null = null;
  private content: string = '';
  private width: number = 0;
  private font: number = 0;
  private environment: string = '';
  private ui: UIContext | null = null;
  prepare(ui: UIContext, content: string, width: number, font: number, environment: string): text.Paragraph {
    if (this.current !== null && this.ui === ui && this.content === content && this.width === width &&
      this.font === font && this.environment === environment) { return this.current; }
    const builder = new text.ParagraphBuilder({ textStyle: { fontSize: font,
      color: drawnColor(COLOR_TEXT_PRIMARY), fontWeight: text.FontWeight.W500 },
      wordBreak: text.WordBreak.BREAK_WORD,
      textDirection: drawnFirstStrongRtl(content) ? text.TextDirection.RTL : text.TextDirection.LTR,
      align: text.TextAlign.LEFT }, text.FontCollection.getGlobalInstance());
    builder.addText(content);
    const paragraph = builder.build();
    paragraph.layoutSync(width);
    if (!Number.isFinite(paragraph.getHeight()) || paragraph.getHeight() <= 0) { throw new Error('invalid gift paragraph height'); }
    this.current = paragraph; this.ui = ui; this.content = content; this.width = width;
    this.font = font; this.environment = environment;
    return paragraph;
  }
}

// Like ChatActionCell's gift layouts, compute text and button metrics before
// publishing the full card height. A fixed one-line status slot isolates updates.
export class DrawnGiftLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private titles: DrawnGiftParagraphs = new DrawnGiftParagraphs();
  private values: DrawnGiftParagraphs = new DrawnGiftParagraphs();
  private statuses: DrawnTextLineCache = new DrawnTextLineCache();
  private copies: DrawnTextLineCache = new DrawnTextLineCache();
  private current: DrawnGiftLayout | null = null;
  private ui: UIContext | null = null;
  private title: string = '';
  private value: string = '';
  private environment: string = '';
  prepare(ui: UIContext, message: MessageEntry, maxWidth: number, environment: string): DrawnGiftLayout {
    const width = Math.max(1, maxWidth), titleText = message.giftTitle ?? '', valueText = message.giftValue ?? '';
    const hasCode = (message.giftCode ?? '') !== '';
    if (this.current !== null && this.ui === ui && this.current.width === width && this.title === titleText &&
      this.value === valueText && this.environment === environment && this.current.hasCode === hasCode) { return this.current; }
    const units = this.units.prepare(ui, environment), density = units.density;
    const displayTitle = titleText.trim() !== '' ? titleText : str('gift_regular_title');
    const title = this.titles.prepare(ui, displayTitle,
      width * density, units.fp2px(15), environment);
    const value = valueText.trim() !== '' ? this.values.prepare(ui, valueText, width * density,
      units.fp2px(13), environment) : null;
    const secondary = drawnColor(COLOR_TEXT_SECONDARY);
    const statusHeight = Math.max(units.fp2px(11) / density * 1.3,
      this.statuses.prepare(str('gift_status_unknown'), width * density,
        units.fp2px(11), secondary, environment).heightPx / density);
    const copy = this.copies.prepare(str('gift_copy_code'), width * density,
      units.fp2px(11), secondary, environment);
    const iconSize = units.fp2px(12) / density;
    const copyHeight = Math.max(iconSize, copy.heightPx / density) + 10;
    const copyWidth = Math.min(width * 0.55, copy.widthPx / density + iconSize + 20);
    const footerHeight = Math.max(6, statusHeight, hasCode ? copyHeight : 0) + 9;
    const titleY = 124 + 8, valueY = titleY + title.getHeight() / density + 8;
    const textHeight = title.getHeight() / density + (value !== null ? 8 + value.getHeight() / density : 0);
    const height = 124 + textHeight + footerHeight + 16;
    if (!Number.isFinite(height) || height <= 0) { throw new Error('invalid gift prelayout height'); }
    this.current = { width, height, density, artworkHeight: 124, textHeight, titleY, valueY,
      footerHeight, statusHeight, copyHeight, copyWidth, hasCode, titleText: displayTitle, title, value };
    this.ui = ui; this.title = titleText; this.value = valueText; this.environment = environment;
    return this.current;
  }
}

export class DrawnGiftTextPainter extends DrawModifier {
  private layout: DrawnGiftLayout | null = null;
  private refunded: boolean = false;
  private accent: string = '';
  bind(layout: DrawnGiftLayout | null, refunded: boolean, accent: string): DrawnGiftTextPainter {
    if (this.layout === layout && this.refunded === refunded && this.accent === accent) { return this; }
    this.layout = layout; this.refunded = refunded; this.accent = accent;
    if (layout !== null) {
      layout.title.updateColor(drawnColor(refunded ? COLOR_TEXT_SECONDARY : COLOR_TEXT_PRIMARY));
      layout.value?.updateColor(drawnColor(accent));
    }
    this.invalidate();
    return this;
  }
  drawBehind(context: DrawContext): void {
    const layout = this.layout;
    if (layout === null) { return; }
    layout.title.paint(context.canvas, 0, layout.titleY * layout.density);
    layout.value?.paint(context.canvas, 0, layout.valueY * layout.density);
  }
}
