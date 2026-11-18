import { UIContext, DrawContext } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { drawnFirstStrongRtl } from '../../util/drawnTextDirection';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnPaidMediaLayout {
  width: number;
  height: number;
  density: number;
  artworkHeight: number;
  textHeight: number;
  headingY: number;
  noteY: number;
  buttonHeight: number;
  badgeHeight: number;
  lockedTitle: text.Paragraph;
  unlockedTitle: text.Paragraph;
  note: text.Paragraph | null;
}

const paidLayouts: WeakMap<DrawnDocumentWidget, DrawnPaidMediaLayout> = new WeakMap<DrawnDocumentWidget, DrawnPaidMediaLayout>();
export function rememberPaidMediaLayout(widget: DrawnDocumentWidget, layout: DrawnPaidMediaLayout): void { paidLayouts.set(widget, layout); }
export function paidMediaLayoutFor(widget: DrawnDocumentWidget): DrawnPaidMediaLayout | null { return paidLayouts.get(widget) ?? null; }

// The current multi-item model exposes only its first item; keep its existing
// preview size until all items are modeled. Single-item previews have real sizes.
export function drawnPaidArtworkHeight(width: number, sourceWidth: number, sourceHeight: number, count: number): number {
  if (count !== 1 || !Number.isFinite(sourceWidth) || !Number.isFinite(sourceHeight) ||
    sourceWidth <= 0 || sourceHeight <= 0) { return 156; }
  const maximum = Math.min(360, width * 1.2), minimum = Math.min(96, maximum);
  return Math.max(minimum, Math.min(maximum, width * (sourceHeight / sourceWidth)));
}

class DrawnPaidTextLayouts {
  private current: text.Paragraph | null = null;
  private ui: UIContext | null = null;
  private environment: string = '';
  private content: string = '';
  private width: number = 0;
  private font: number = 0;
  prepare(ui: UIContext, content: string, width: number, font: number, environment: string,
    medium: boolean, maxLines?: number): text.Paragraph {
    if (this.current !== null && this.ui === ui && this.environment === environment &&
      this.content === content && this.width === width && this.font === font) { return this.current; }
    // Each slot has a fixed weight/line policy; only its text/size/environment vary.
    const builder = new text.ParagraphBuilder({ textStyle: { fontSize: font,
      color: drawnColor(medium ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY),
      fontWeight: medium ? text.FontWeight.W500 : text.FontWeight.W400, ellipsis: '\u2026' },
      maxLines, wordBreak: text.WordBreak.BREAK_WORD,
      textDirection: drawnFirstStrongRtl(content) ? text.TextDirection.RTL : text.TextDirection.LTR,
      align: text.TextAlign.LEFT }, text.FontCollection.getGlobalInstance());
    builder.addText(content);
    const paragraph = builder.build();
    paragraph.layoutSync(width);
    if (!Number.isFinite(paragraph.getHeight()) || paragraph.getHeight() <= 0) { throw new Error('invalid paid text height'); }
    this.current = paragraph; this.ui = ui; this.environment = environment;
    this.content = content; this.width = width; this.font = font;
    return paragraph;
  }
}

// Retain both with-note and without-note geometries. Unlock state does not
// reshape static labels, and a single-item unlock keeps the same layout object.
export class DrawnPaidMediaLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private locked: DrawnPaidTextLayouts = new DrawnPaidTextLayouts();
  private unlocked: DrawnPaidTextLayouts = new DrawnPaidTextLayouts();
  private note: DrawnPaidTextLayouts = new DrawnPaidTextLayouts();
  private button: DrawnTextLineCache = new DrawnTextLineCache();
  private badge: DrawnTextLineCache = new DrawnTextLineCache();
  private withoutNote: DrawnPaidMediaLayout | null = null;
  private withNote: DrawnPaidMediaLayout | null = null;
  private ui: UIContext | null = null;
  private environment: string = '';
  private width: number = 0;
  private artworkHeight: number = 0;
  prepare(ui: UIContext, message: MessageEntry, maxWidth: number, environment: string): DrawnPaidMediaLayout {
    const width = Math.max(1, maxWidth);
    const artworkHeight = drawnPaidArtworkHeight(width, message.photoWidth, message.photoHeight, message.paidMediaCount);
    const showNote = !message.paidMediaLocked && message.paidMediaCount > 1 && message.paidMediaSet?.complete !== true;
    const same = this.ui === ui && this.environment === environment && this.width === width && this.artworkHeight === artworkHeight;
    const cached = showNote ? this.withNote : this.withoutNote;
    if (same && cached !== null) { return cached; }
    const units = this.units.prepare(ui, environment), density = units.density;
    const lockedTitle = this.locked.prepare(ui, str('paid_media'), width * density, units.fp2px(14), environment, true);
    const unlockedTitle = this.unlocked.prepare(ui, str('paid_media_unlocked'), width * density, units.fp2px(14), environment, true);
    // Warm both branches once so an unlock only switches retained geometry.
    const noteParagraph = this.note.prepare(ui, str('paid_viewer_note'), width * density, units.fp2px(10.5), environment, false, 2);
    const color = drawnColor(COLOR_TEXT_SECONDARY);
    const buttonHeight = Math.max(36, 16 + 12, this.button.prepare(`${str('paid_checking')} ⭐`, width * density,
      units.fp2px(12.5), color, environment, true).heightPx / density + 12);
    const badgeHeight = Math.max(units.fp2px(11) / density,
      this.badge.prepare('0', width * density, units.fp2px(10.5), color, environment).heightPx / density) + 8;
    const headingY = artworkHeight + 9;
    const headingHeight = Math.max(lockedTitle.getHeight(), unlockedTitle.getHeight()) / density;
    const noteY = headingY + headingHeight + 2;
    const textHeight = headingHeight + (showNote ? 2 + noteParagraph.getHeight() / density : 0);
    const height = artworkHeight + textHeight + buttonHeight + 36;
    if (!Number.isFinite(height) || height <= 0) { throw new Error('invalid paid prelayout height'); }
    const layout: DrawnPaidMediaLayout = { width, height, density, artworkHeight, textHeight,
      headingY, noteY, buttonHeight, badgeHeight, lockedTitle, unlockedTitle, note: showNote ? noteParagraph : null };
    if (!same) { this.withNote = null; this.withoutNote = null; }
    if (showNote) { this.withNote = layout; } else { this.withoutNote = layout; }
    this.ui = ui; this.environment = environment; this.width = width; this.artworkHeight = artworkHeight;
    return layout;
  }
}

export class DrawnPaidMediaTextPainter extends DrawModifier {
  private layout: DrawnPaidMediaLayout | null = null;
  private locked: boolean = true;
  bind(layout: DrawnPaidMediaLayout | null, locked: boolean): DrawnPaidMediaTextPainter {
    if (this.layout !== layout || this.locked !== locked) { this.layout = layout; this.locked = locked; this.invalidate(); }
    return this;
  }
  drawBehind(context: DrawContext): void {
    const layout = this.layout;
    if (layout === null) { return; }
    (this.locked ? layout.lockedTitle : layout.unlockedTitle).paint(context.canvas, 0, layout.headingY * layout.density);
    layout.note?.paint(context.canvas, 0, layout.noteY * layout.density);
  }
}
