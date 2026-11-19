import { drawnWeightNormal } from '../../util/systemFontWeight';
import { UIContext, DrawContext } from '@kit.ArkUI';
import { text } from '@kit.ArkGraphics2D';
import { MessageEntry } from '../../store/MessageEntry';
import { ContactVcardSummary, contactVcardSummary } from '../../util/contactVcardSummary';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { drawnFirstStrongRtl } from '../../util/drawnTextDirection';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnTextLine, DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnContactLayout {
  width: number;
  height: number;
  density: number;
  avatarSize: number;
  avatarY: number;
  actionSize: number;
  actionX: number;
  actionY: number;
  textX: number;
  titleY: number;
  detailsY: number;
  title: DrawnTextLine;
  details: text.Paragraph;
  name: string;
  initials: string;
  phone: string;
  available: boolean;
  accessibilityLabel: string;
}

const contactLayouts: WeakMap<DrawnDocumentWidget, DrawnContactLayout> = new WeakMap<DrawnDocumentWidget, DrawnContactLayout>();
export function rememberContactLayout(widget: DrawnDocumentWidget, layout: DrawnContactLayout): void { contactLayouts.set(widget, layout); }
export function contactLayoutFor(widget: DrawnDocumentWidget): DrawnContactLayout | null { return contactLayouts.get(widget) ?? null; }

// One engine per retained row. Stable media/status updates compare a fixed set
// of scalar fields. Width/font changes reuse the parsed vCard summary.
export class DrawnContactLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private titles: DrawnTextLineCache = new DrawnTextLineCache();
  private current: DrawnContactLayout | null = null;
  private firstName: string = '';
  private lastName: string = '';
  private phone: string = '';
  private vcard: string = '';
  private userId: number = 0;
  private environment: string = '';
  private ui: UIContext | null = null;
  private summary: ContactVcardSummary = { phones: [], lines: [] };
  private summaryPhone: string = '';
  private summaryVcard: string = '';
  private summaryReady: boolean = false;

  prepare(ui: UIContext, message: MessageEntry, maxWidth: number, environment: string): DrawnContactLayout {
    const width = Math.max(1, Math.min(264, maxWidth));
    if (this.current !== null && this.ui === ui && this.environment === environment && this.current.width === width &&
      this.firstName === message.contactFirstName && this.lastName === message.contactLastName &&
      this.phone === message.contactPhone && this.vcard === message.contactVcard && this.userId === message.contactUserId) {
      return this.current;
    }
    if (!this.summaryReady || this.summaryPhone !== message.contactPhone || this.summaryVcard !== message.contactVcard) {
      this.summary = contactVcardSummary(message.contactVcard, message.contactPhone);
      this.summaryPhone = message.contactPhone; this.summaryVcard = message.contactVcard;
      this.summaryReady = true;
    }
    const units = this.units.prepare(ui, environment), density = units.density;
    const fullName = `${message.contactFirstName} ${message.contactLastName}`.replace(/[\r\n]/g, ' ').trim();
    const name = fullName || (message.contactUserId > 0 ? str('cb_telegram_user') : str('cb_unnamed'));
    const phone = this.summary.phones[0] ?? '';
    let subtitle = str('cb_unavailable');
    if (this.summary.lines.length > 0) {
      subtitle = this.summary.lines.join('\n');
    } else if (message.contactUserId > 0) {
      subtitle = str('cb_tap_profile');
    } else if (message.contactVcard.trim() !== '') {
      subtitle = str('cb_contact_card');
    }
    const available = message.contactUserId > 0 || fullName !== '' || phone !== '' || message.contactVcard.trim() !== '';
    const avatarSize = Math.min(48, width / 4);
    const actionSize = phone !== '' ? Math.min(34, width / 5) : Math.min(14, width / 8);
    const gap = Math.min(10, width / 25);
    const textX = avatarSize + gap;
    const textWidth = Math.max(1, width - textX - actionSize - gap);
    const title = this.titles.prepare(name, textWidth * density, units.fp2px(14.5),
      drawnColor(COLOR_TEXT_PRIMARY), environment, true);
    const builder = new text.ParagraphBuilder({
      textStyle: { fontSize: units.fp2px(11.5), color: drawnColor(available ? COLOR_TEXT_SECONDARY : '#D95B57'),
        fontWeight: drawnWeightNormal() },
      wordBreak: text.WordBreak.BREAK_WORD,
      textDirection: drawnFirstStrongRtl(subtitle) ? text.TextDirection.RTL : text.TextDirection.LTR,
      align: text.TextAlign.LEFT
    }, text.FontCollection.getGlobalInstance());
    builder.addText(subtitle);
    const details = builder.build();
    details.layoutSync(textWidth * density);
    const textHeight = title.heightPx / density + 4 + details.getHeight() / density;
    const contentHeight = Math.max(avatarSize, actionSize, textHeight);
    const height = Math.ceil(contentHeight + 13);
    if (!Number.isFinite(height) || height <= 0) { throw new Error('invalid contact layout height'); }
    const titleY = 2 + (contentHeight - textHeight) / 2;
    const initials = `${message.contactFirstName.trim().substring(0, 1)}${message.contactLastName.trim().substring(0, 1)}`.toUpperCase() || '?';
    const layout: DrawnContactLayout = { width, height, density, avatarSize,
      avatarY: 2 + (contentHeight - avatarSize) / 2, actionSize, actionX: width - actionSize,
      actionY: 2 + (contentHeight - actionSize) / 2, textX, titleY,
      detailsY: titleY + title.heightPx / density + 4, title, details, name, initials, phone, available,
      accessibilityLabel: available ? `${str('cb_contact_named', name)}，${subtitle}` : str('cb_unavailable') };
    this.firstName = message.contactFirstName; this.lastName = message.contactLastName;
    this.phone = message.contactPhone; this.vcard = message.contactVcard; this.userId = message.contactUserId;
    this.environment = environment; this.ui = ui; this.current = layout;
    return layout;
  }
}

export class DrawnContactTextPainter extends DrawModifier {
  private layout: DrawnContactLayout | null = null;
  bind(layout: DrawnContactLayout | null): DrawnContactTextPainter {
    if (layout !== this.layout) { this.layout = layout; this.invalidate(); }
    return this;
  }
  drawBehind(context: DrawContext): void {
    const layout = this.layout;
    if (layout === null) { return; }
    const density = layout.density;
    layout.title.paragraph.paint(context.canvas, layout.textX * density, layout.titleY * density);
    layout.details.paint(context.canvas, layout.textX * density, layout.detailsY * density);
  }
}
