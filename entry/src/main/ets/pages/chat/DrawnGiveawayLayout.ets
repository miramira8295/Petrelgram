import { drawnWeightMedium, drawnWeightNormal } from '../../util/systemFontWeight';
import { UIContext, DrawContext } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { drawnFirstStrongRtl } from '../../util/drawnTextDirection';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnGiveawayLayout {
  width: number;
  height: number;
  density: number;
  artworkHeight: number;
  textHeight: number;
  titleY: number;
  prizeY: number;
  descriptionY: number;
  statsHeight: number;
  buttonHeight: number;
  badgeHeight: number;
  hasOriginal: boolean;
  titles: text.Paragraph[];
  prize: text.Paragraph;
  description: text.Paragraph | null;
}

const giveawayLayouts: WeakMap<DrawnDocumentWidget, DrawnGiveawayLayout> = new WeakMap<DrawnDocumentWidget, DrawnGiveawayLayout>();
export function rememberGiveawayLayout(widget: DrawnDocumentWidget, layout: DrawnGiveawayLayout): void { giveawayLayouts.set(widget, layout); }
export function giveawayLayoutFor(widget: DrawnDocumentWidget): DrawnGiveawayLayout | null { return giveawayLayouts.get(widget) ?? null; }

class DrawnGiveawayParagraphs {
  private current: text.Paragraph | null = null;
  private ui: UIContext | null = null;
  private content: string = '';
  private environment: string = '';
  private width: number = 0;
  private font: number = 0;
  // Each slot has a fixed weight; colors are set by its painter at bind time.
  prepare(ui: UIContext, content: string, width: number, font: number, environment: string,
    medium: boolean): text.Paragraph {
    if (this.current !== null && this.ui === ui && this.content === content && this.environment === environment &&
      this.width === width && this.font === font) { return this.current; }
    const builder = new text.ParagraphBuilder({ textStyle: { fontSize: font,
      color: drawnColor(medium ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY),
      fontWeight: medium ? drawnWeightMedium() : drawnWeightNormal() },
      wordBreak: text.WordBreak.BREAK_WORD,
      textDirection: drawnFirstStrongRtl(content) ? text.TextDirection.RTL : text.TextDirection.LTR,
      align: text.TextAlign.LEFT }, text.FontCollection.getGlobalInstance());
    builder.addText(content);
    const paragraph = builder.build();
    paragraph.layoutSync(width);
    if (!Number.isFinite(paragraph.getHeight()) || paragraph.getHeight() <= 0) { throw new Error('invalid giveaway text height'); }
    this.current = paragraph; this.ui = ui; this.content = content; this.environment = environment;
    this.width = width; this.font = font;
    return paragraph;
  }
}

// GiveawayMessageCell prepares all text before summing measuredHeight. Keep
// only four geometries here: stats visible/hidden × original button visible/hidden.
export class DrawnGiveawayLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private titles: DrawnGiveawayParagraphs[] = [new DrawnGiveawayParagraphs(), new DrawnGiveawayParagraphs(),
    new DrawnGiveawayParagraphs(), new DrawnGiveawayParagraphs(), new DrawnGiveawayParagraphs()];
  private prizes: DrawnGiveawayParagraphs = new DrawnGiveawayParagraphs();
  private descriptions: DrawnGiveawayParagraphs = new DrawnGiveawayParagraphs();
  private stats: DrawnTextLineCache = new DrawnTextLineCache();
  private button: DrawnTextLineCache = new DrawnTextLineCache();
  private badge: DrawnTextLineCache = new DrawnTextLineCache();
  private plans: (DrawnGiveawayLayout | null)[] = [null, null, null, null];
  private ui: UIContext | null = null;
  private environment: string = '';
  private width: number = 0;
  private prize: string = '';
  private description: string = '';
  prepare(ui: UIContext, message: MessageEntry, maxWidth: number, environment: string): DrawnGiveawayLayout {
    const width = Math.max(1, maxWidth), prizeText = message.giveawayPrize ?? '', descriptionText = message.giveawayDescription ?? '';
    const hasOriginal = message.giveawayMessageId > 0;
    const hasStats = message.giveawayWinnerCount > 0 || message.giveawayOnlyNewMembers || message.giveawayUnclaimedCount > 0;
    const index = (hasOriginal ? 2 : 0) + (hasStats ? 1 : 0);
    const same = this.ui === ui && this.environment === environment && this.width === width &&
      this.prize === prizeText && this.description === descriptionText;
    const cached = this.plans[index];
    if (same && cached !== null) { return cached; }
    const units = this.units.prepare(ui, environment), density = units.density;
    const labels: string[] = ['gw_cancelled', 'gw_channel', 'gw_you_won', 'gw_results', 'gw_ended'];
    const titles: text.Paragraph[] = [];
    let titleHeight = 0;
    // Fixed five title states, independent of channel/message/participant counts.
    for (let i = 0; i < labels.length; i++) {
      const title = this.titles[i].prepare(ui, str(labels[i]), width * density, units.fp2px(15), environment, true);
      titles.push(title); titleHeight = Math.max(titleHeight, title.getHeight() / density);
    }
    const prize = this.prizes.prepare(ui, prizeText.trim() !== '' ? prizeText : str('giveaway_prize_unavailable'),
      width * density, units.fp2px(13), environment, true);
    const description = descriptionText.trim() !== '' ? this.descriptions.prepare(ui, descriptionText,
      width * density, units.fp2px(11.5), environment, false) : null;
    const color = drawnColor(COLOR_TEXT_SECONDARY);
    const statsHeight = hasStats ? Math.max(units.fp2px(10.5) / density * 1.3,
      this.stats.prepare('0', width * density, units.fp2px(10.5), color, environment).heightPx / density) : 0;
    const buttonHeight = Math.max(34, units.fp2px(13) / density + 12,
      this.button.prepare(str('gw_view_original'), width * density, units.fp2px(12), color, environment, true).heightPx / density + 12);
    const badgeHeight = Math.max(units.fp2px(11) / density,
      this.badge.prepare('0', width * density, units.fp2px(10.5), color, environment).heightPx / density) + 8;
    const titleY = 126 + 9, prizeY = titleY + titleHeight + 9;
    const descriptionY = prizeY + prize.getHeight() / density + 9;
    const textHeight = titleHeight + 9 + prize.getHeight() / density + (description !== null ? 9 + description.getHeight() / density : 0);
    const height = 126 + textHeight + statsHeight + (hasOriginal ? buttonHeight : 0) + 9 + (hasOriginal ? 36 : 27);
    if (!Number.isFinite(height) || height <= 0) { throw new Error('invalid giveaway prelayout height'); }
    const layout: DrawnGiveawayLayout = { width, height, density, artworkHeight: 126, textHeight, titleY, prizeY,
      descriptionY, statsHeight, buttonHeight, badgeHeight, hasOriginal, titles, prize, description };
    if (!same) { this.plans.fill(null); }
    this.plans[index] = layout;
    this.ui = ui; this.environment = environment; this.width = width; this.prize = prizeText; this.description = descriptionText;
    return layout;
  }
}

export class DrawnGiveawayTextPainter extends DrawModifier {
  private layout: DrawnGiveawayLayout | null = null;
  private state: string = '';
  private refunded: boolean = false;
  bind(layout: DrawnGiveawayLayout | null, state: string, refunded: boolean): DrawnGiveawayTextPainter {
    if (this.layout === layout && this.state === state && this.refunded === refunded) { return this; }
    this.layout = layout; this.state = state; this.refunded = refunded;
    if (layout !== null) {
      this.title(layout).updateColor(drawnColor(refunded ? COLOR_TEXT_SECONDARY : COLOR_TEXT_PRIMARY));
      layout.prize.updateColor(drawnColor(refunded ? COLOR_TEXT_SECONDARY : '#7B57C7'));
    }
    this.invalidate();
    return this;
  }
  private title(layout: DrawnGiveawayLayout): text.Paragraph {
    return layout.titles[this.refunded ? 0 : this.state === 'active' ? 1 : this.state === 'prize' ? 2 : this.state === 'winners' ? 3 : 4];
  }
  drawBehind(context: DrawContext): void {
    const layout = this.layout;
    if (layout === null) { return; }
    this.title(layout).paint(context.canvas, 0, layout.titleY * layout.density);
    layout.prize.paint(context.canvas, 0, layout.prizeY * layout.density);
    layout.description?.paint(context.canvas, 0, layout.descriptionY * layout.density);
  }
}
