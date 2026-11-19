import { UIContext } from '@kit.ArkUI';
import { DrawnMediaTexts, DrawnMediaTextPlan } from './DrawnMediaText';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { musicFormatLabel } from '../../util/musicTrackModel';
import { formatFileSize } from '../../util/formatFileSize';
import { str } from '../../util/strings';

export function musicCardTitle(title: string, fileName: string): string {
  const named = title.trim();
  if (named !== '') { return named; }
  const file = fileName.trim();
  if (file === '') { return str('music_audio'); }
  const dot = file.lastIndexOf('.');
  return dot > 0 ? file.substring(0, dot) : file;
}
export function musicCardSubtitle(performer: string, mime: string, name: string, size: number): string {
  const parts: string[] = [performer.trim() || str('music_unknown_artist')];
  const format = musicFormatLabel(mime, name);
  if (format !== '') { parts.push(format); }
  if (size > 0) { parts.push(formatFileSize(size)); }
  return parts.join(' · ');
}
export interface DrawnMusicCardLayout {
  width: number; height: number; waveHeight: number; chipHeight: number;
  title: string; subtitle: string; label: DrawnMediaTextPlan; environment: string;
}
const musicCards: WeakMap<DrawnDocumentWidget, DrawnMusicCardLayout> = new WeakMap();
export function musicCardFor(widget: DrawnDocumentWidget | undefined): DrawnMusicCardLayout | undefined {
  return widget === undefined ? undefined : musicCards.get(widget);
}
export function rememberMusicCard(widget: DrawnDocumentWidget, layout: DrawnMusicCardLayout): void { musicCards.set(widget, layout); }

// Raw metadata is compared before trimming/formatting. Stable player/progress
// updates are O(1), cold title layout O(text length); no transfer state in key.
export class DrawnMusicCardLayouts {
  private labels: DrawnMediaTexts = new DrawnMediaTexts();
  private measures: DrawnMediaTexts = new DrawnMediaTexts();
  private current: DrawnMusicCardLayout | null = null;
  private title: string = ''; private performer: string = ''; private name: string = ''; private mime: string = ''; private size: number = 0;
  private ui: UIContext | null = null;
  prepare(ui: UIContext, title: string, performer: string, name: string, mime: string, size: number,
    width: number, environment: string): DrawnMusicCardLayout {
    if (this.current !== null && this.ui === ui && this.title === title && this.performer === performer && this.name === name &&
      this.mime === mime && this.size === size && this.current.width === width && this.current.environment === environment) { return this.current; }
    const heading = musicCardTitle(title, name), subtitle = musicCardSubtitle(performer, mime, name, size);
    const label = this.labels.prepare(ui, environment, Math.max(1, width - 126), heading, 15, COLOR_TEXT_PRIMARY,
      subtitle, 11.5, COLOR_TEXT_SECONDARY, 1, true, 2, 44);
    const metrics = this.measures.prepare(ui, environment, Math.max(1, width), '00:00', 11, COLOR_TEXT_SECONDARY);
    const waveHeight = Math.max(24, metrics.height), chipHeight = Math.max(20, metrics.height);
    this.ui = ui; this.title = title; this.performer = performer; this.name = name; this.mime = mime; this.size = size;
    this.current = { width, height: 18 + Math.max(44, label.height) + 8 + waveHeight + 9 + 0.8 + 8 + chipHeight,
      waveHeight, chipHeight, title: heading, subtitle, label, environment };
    return this.current;
  }
}
