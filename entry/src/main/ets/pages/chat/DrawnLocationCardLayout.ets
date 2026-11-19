import { UIContext } from '@kit.ArkUI';
import { DrawnMediaTexts } from './DrawnMediaText';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

export interface DrawnLocationCardSpec {
  title: string; address: string; live: boolean; valid: boolean; sharing: boolean; width: number; environment: string;
}
export interface DrawnLocationCardLayout {
  labels: DrawnMediaTexts; environment: string;
  width: number; height: number; mapHeight: number; textHeight: number; stopHeight: number; showText: boolean;
}
const locationCards: WeakMap<DrawnDocumentWidget, DrawnLocationCardLayout> = new WeakMap();
export function locationCardFor(widget: DrawnDocumentWidget | undefined): DrawnLocationCardLayout | undefined {
  return widget === undefined ? undefined : locationCards.get(widget);
}
export function rememberLocationCard(widget: DrawnDocumentWidget, layout: DrawnLocationCardLayout): void { locationCards.set(widget, layout); }

// Android uses a 195dp map and measured one-line venue title/address. Live
// countdowns reuse reserved line geometry; the clock is deliberately absent.
export class DrawnLocationCardLayouts {
  private labels: DrawnMediaTexts = new DrawnMediaTexts();
  private ended: DrawnMediaTexts = new DrawnMediaTexts();
  private actions: DrawnMediaTexts = new DrawnMediaTexts();
  private spec: DrawnLocationCardSpec | null = null;
  private current: DrawnLocationCardLayout | null = null;
  private ui: UIContext | null = null;
  prepare(ui: UIContext, spec: DrawnLocationCardSpec): DrawnLocationCardLayout {
    const old = this.spec;
    if (this.current !== null && this.ui === ui && old !== null && old.title === spec.title && old.address === spec.address &&
      old.live === spec.live && old.valid === spec.valid && old.sharing === spec.sharing && old.width === spec.width && old.environment === spec.environment) { return this.current; }
    const width = Math.max(1, Math.min(270, spec.width)), title = spec.title.trim(), address = spec.address.trim();
    const showText = title !== '' || spec.live || !spec.valid;
    let textHeight = 0;
    if (showText) {
      const label = this.labels.prepare(ui, spec.environment, Math.max(1, width - 53), title || str(spec.live ? 'loc_live' : 'loc_unavailable'),
        14.5, COLOR_TEXT_PRIMARY, address || str(spec.live ? 'loc_live_sharing' : 'loc_no_coords'), 11.5, COLOR_TEXT_SECONDARY, 1, true, 3);
      textHeight = label.height + 10;
      if (spec.live) {
        const ended = this.ended.prepare(ui, spec.environment, Math.max(1, width - 53), str('loc_live_ended'), 14.5, COLOR_TEXT_PRIMARY,
          str('loc_live_ended'), 11.5, COLOR_TEXT_SECONDARY, 1, true, 3);
        textHeight = Math.max(textHeight, ended.height + 10);
      }
    }
    const stopHeight = spec.sharing ? Math.max(34, this.actions.prepare(ui, spec.environment, Math.max(1, width - 16),
      str('loc_stop_sharing'), 14, COLOR_TEXT_PRIMARY).height + 12) : 0;
    this.ui = ui; this.spec = spec;
    this.current = { labels: this.labels, environment: spec.environment, width, mapHeight: 195, showText, textHeight, stopHeight,
      height: 195 + (showText ? 9 + textHeight : 0) + (spec.sharing ? 9 + stopHeight : 0) };
    return this.current;
  }
}
