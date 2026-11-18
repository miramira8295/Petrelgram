import { UIContext } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { PollRichSource } from '../../util/pollRichSource';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnRichTextLayout, DrawnRichTextLayouts } from './DrawnRichTextLayout';
import { DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnGameLayout {
  width: number;
  height: number;
  coverHeight: number;
  buttonHeight: number;
  footerHeight: number;
  available: boolean;
  titleText: string;
  detailText: string;
  footerText: string;
  title: DrawnRichTextLayout;
  description: DrawnRichTextLayout | null;
  body: DrawnRichTextLayout | null;
  fallback: DrawnRichTextLayout | null;
}

const gameLayouts: WeakMap<DrawnDocumentWidget, DrawnGameLayout> = new WeakMap<DrawnDocumentWidget, DrawnGameLayout>();
export function rememberGameLayout(widget: DrawnDocumentWidget, layout: DrawnGameLayout): void { gameLayouts.set(widget, layout); }
export function gameLayoutFor(widget: DrawnDocumentWidget): DrawnGameLayout | null { return gameLayouts.get(widget) ?? null; }
const EMPTY_GAME_LAYOUT_ENTITIES: TdObject[] = [];

class DrawnGameTextLayouts {
  private sources: PollRichSource = new PollRichSource();
  private layouts: DrawnRichTextLayouts = new DrawnRichTextLayouts();
  prepare(ui: UIContext, content: string, entities: TdObject[], width: number, font: number,
    color: ResourceColor, environment: string, bold: boolean = false): DrawnRichTextLayout {
    const source = this.sources.prepare(content, entities, bold);
    if (source === null) { throw new Error('unsupported game text layout'); }
    return this.layouts.prepare(ui, { source, maxWidthVp: Math.max(1, width), minWidthVp: 0,
      fontSize: font, foreground: color, accent: COLOR_PRIMARY, environment, reserve: '' });
  }
}

// Match ChatMessageCell's preparation order: lay out text before publishing
// total preview height. Cover paths/progress never enter these geometry keys.
export class DrawnGameLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private title: DrawnGameTextLayouts = new DrawnGameTextLayouts();
  private description: DrawnGameTextLayouts = new DrawnGameTextLayouts();
  private body: DrawnGameTextLayouts = new DrawnGameTextLayouts();
  private fallback: DrawnGameTextLayouts = new DrawnGameTextLayouts();
  private footer: DrawnTextLineCache = new DrawnTextLineCache();
  private button: DrawnTextLineCache = new DrawnTextLineCache();
  private current: DrawnGameLayout | null = null;
  private ui: UIContext | null = null;
  private environment: string = '';
  private titleText: string = '';
  private shortName: string = '';
  private descriptionText: string = '';
  private bodyText: string = '';
  private entities: TdObject[] | null = null;
  private cleanTitle: string = '';
  private cleanShortName: string = '';
  private hasDescription: boolean = false;
  private hasBody: boolean = false;

  prepare(ui: UIContext, message: MessageEntry, maxWidth: number, environment: string): DrawnGameLayout {
    const width = Math.max(1, maxWidth);
    const titleText = message.gameTitle ?? '', shortName = message.gameShortName ?? '';
    const descriptionText = message.gameDescription ?? '', bodyText = message.gameText ?? '';
    const entities = message.gameTextEntities ?? EMPTY_GAME_LAYOUT_ENTITIES;
    if (this.current !== null && this.ui === ui && this.environment === environment && this.current.width === width &&
      this.titleText === titleText && this.shortName === shortName && this.descriptionText === descriptionText &&
      this.bodyText === bodyText && this.entities === entities) { return this.current; }
    const units = this.units.prepare(ui, environment), density = units.density;
    const ready = this.current !== null;
    const cleanTitle = ready && this.titleText === titleText ? this.cleanTitle : titleText.trim();
    const cleanShortName = ready && this.shortName === shortName ? this.cleanShortName : shortName.trim();
    const hasDescriptionText = ready && this.descriptionText === descriptionText ? this.hasDescription : descriptionText.trim() !== '';
    const hasBody = ready && this.bodyText === bodyText ? this.hasBody : bodyText.trim() !== '';
    // Android omits game.description when a game message already has text.
    const hasDescription = hasDescriptionText && !hasBody;
    const available = cleanTitle !== '' || cleanShortName !== '';
    const displayTitle = cleanTitle || cleanShortName || str('game_unavailable');
    const detailText = hasDescription ? descriptionText : hasBody ? bodyText :
      str(available ? 'game_interactive' : 'game_unreadable');
    const footerText = cleanShortName !== '' ? `@${cleanShortName}` : str('game_title');
    const title = this.title.prepare(ui, displayTitle, EMPTY_GAME_LAYOUT_ENTITIES, width, 15,
      available ? COLOR_TEXT_PRIMARY : '#B05D58', environment, true);
    const description = hasDescription ? this.description.prepare(ui, descriptionText, EMPTY_GAME_LAYOUT_ENTITIES,
      width, 11.5, COLOR_TEXT_SECONDARY, environment) : null;
    const body = hasBody ? this.body.prepare(ui, bodyText, entities, width,
      11.5, COLOR_TEXT_PRIMARY, environment) : null;
    const fallback = !hasDescription && !hasBody ? this.fallback.prepare(ui, detailText, EMPTY_GAME_LAYOUT_ENTITIES,
      width, 11.5, COLOR_TEXT_SECONDARY, environment) : null;
    const color = drawnColor(COLOR_TEXT_SECONDARY);
    const footerHeight = this.footer.prepare(footerText, Math.max(1, width - 64) * density,
      units.fp2px(10.5), color, environment).heightPx / density + 9;
    const buttonHeight = Math.max(36, this.button.prepare(str(available ? 'game_play' : 'game_not_available'),
      Math.max(1, width - 21) * density, units.fp2px(13), color, environment, true).heightPx / density + 12);
    const previous = this.current;
    // Fresh equivalent entity arrays still reuse the exact paragraph and plan.
    const same = previous !== null && previous.width === width && previous.title === title &&
      previous.description === description && previous.body === body && previous.fallback === fallback &&
      previous.available === available && previous.footerText === footerText &&
      previous.footerHeight === footerHeight && previous.buttonHeight === buttonHeight;
    if (!same) {
      let height = 116 + title.heightVp + buttonHeight + footerHeight;
      let blocks = 4;
      if (description !== null) { height += description.heightVp; blocks++; }
      if (body !== null) { height += body.heightVp; blocks++; }
      if (fallback !== null) { height += fallback.heightVp; blocks++; }
      height += (blocks - 1) * 8;
      if (!Number.isFinite(height) || height <= 0) { throw new Error('invalid game prelayout height'); }
      this.current = { width, height, coverHeight: 116, buttonHeight, footerHeight, available,
        titleText: displayTitle, detailText, footerText, title, description, body, fallback };
    }
    this.ui = ui; this.environment = environment; this.titleText = titleText; this.shortName = shortName;
    this.descriptionText = descriptionText; this.bodyText = bodyText; this.entities = entities;
    this.cleanTitle = cleanTitle; this.cleanShortName = cleanShortName;
    this.hasDescription = hasDescriptionText; this.hasBody = hasBody;
    return this.current!;
  }
}
