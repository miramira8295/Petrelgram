import { filePreviewKind } from '../../util/filePreview';
import { UIContext } from '@kit.ArkUI';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { displayFileName, fileStatusText } from '../../util/fileMessage';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { DrawnMediaTexts } from './DrawnMediaText';

export const FILE_TILE_SIZE: number = 48;
export const FILE_CARD_TOP: number = 1;
export const FILE_CARD_BOTTOM: number = 4;
export function fileCardTileSize(name: string, mime: string, thumbnailId: number, mini: string): number {
  return filePreviewKind(name, mime) !== '' || thumbnailId > 0 || mini !== '' ? 86 : FILE_TILE_SIZE;
}
export function fileCardTextWidth(width: number, tileSize: number = FILE_TILE_SIZE): number {
  // Reserve the action slot in every transfer state: progress cannot reflow the filename.
  return Math.max(1, width - 4 - tileSize - 10 - 38);
}
export interface DrawnFileCardLayout {
  width: number;
  height: number;
  tileSize: number;
  // Immutable safe corner for the row footer. Transfer updates must not move it.
  footerLeft: number;
  footerTop: number;
  labels: DrawnMediaTexts;
  environment: string;
}
const fileCardLayoutsByWidget: WeakMap<DrawnDocumentWidget, DrawnFileCardLayout> = new WeakMap();
export function rememberFileCard(widget: DrawnDocumentWidget, layout: DrawnFileCardLayout): void { fileCardLayoutsByWidget.set(widget, layout); }
export function fileCardFor(widget: DrawnDocumentWidget | undefined): DrawnFileCardLayout | undefined {
  return widget === undefined ? undefined : fileCardLayoutsByWidget.get(widget);
}

// First layout and the local file controls share the filename Paragraph cache.
// Only name, width and font environment affect geometry; downloads/covers do not.
export class DrawnFileCardLayouts {
  private labels: DrawnMediaTexts = new DrawnMediaTexts();
  private current: DrawnFileCardLayout | null = null;
  private ui: UIContext | null = null;
  private name: string = '';
  private environment: string = '';
  prepare(ui: UIContext, fileName: string, maxWidth: number, environment: string, tileSize: number = FILE_TILE_SIZE): DrawnFileCardLayout {
    const width = Math.max(1, maxWidth);
    if (this.current !== null && this.ui === ui && this.name === fileName &&
      this.current.width === width && this.current.tileSize === tileSize && this.environment === environment) { return this.current; }
    const labels = this.labels.prepare(ui, environment, fileCardTextWidth(width, tileSize), displayFileName(fileName),
      14.5, COLOR_TEXT_PRIMARY, fileStatusText(1, '', 0, false, 0, false), 11, COLOR_TEXT_SECONDARY, 2, true, 4, tileSize);
    this.ui = ui; this.name = fileName; this.environment = environment;
    const textBottom = labels.top + labels.primary.height / labels.density + labels.gap +
      (labels.secondary?.height ?? 0) / labels.density;
    const actionBottom = (labels.height + 28) / 2;
    this.current = { width, tileSize, height: labels.height + FILE_CARD_TOP + FILE_CARD_BOTTOM,
      footerLeft: tileSize + 10, footerTop: FILE_CARD_TOP + Math.max(textBottom, actionBottom) + 2,
      labels: this.labels, environment };
    return this.current;
  }
}
