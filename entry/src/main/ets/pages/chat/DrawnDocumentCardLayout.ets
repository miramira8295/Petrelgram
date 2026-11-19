import { UIContext } from '@kit.ArkUI';
import { DrawnDocumentWidget, DrawnDocumentWidgetPlacement } from '../../util/drawnDocumentWidget';
import { documentFileId } from '../../util/drawnDocumentMedia';
import { DrawnFileCardLayout, DrawnFileCardLayouts, fileCardTileSize } from './DrawnFileCardLayout';
import { DrawnMediaTexts } from './DrawnMediaText';
import { COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { formatVoiceDuration } from '../../util/voiceWaveform';
import { str } from '../../util/strings';

export interface DrawnDocumentCardLayout {
  height: number;
  labels: DrawnMediaTexts;
  environment: string;
  file?: DrawnFileCardLayout;
}
// Layout belongs to a placement, not a file ID: the same attachment can occur
// at different widths in quotes/tables. Shifted placements retain the same plan.
const documentCards: WeakMap<DrawnDocumentWidgetPlacement, DrawnDocumentCardLayout> = new WeakMap();
export function documentCardFor(item: DrawnDocumentWidgetPlacement): DrawnDocumentCardLayout | undefined { return documentCards.get(item); }
export function rememberDocumentCard(item: DrawnDocumentWidgetPlacement, card: DrawnDocumentCardLayout): void { documentCards.set(item, card); }
export function offsetDocumentWidget(item: DrawnDocumentWidgetPlacement, x: number, y: number): DrawnDocumentWidgetPlacement {
  const shifted: DrawnDocumentWidgetPlacement = { widget: item.widget, x: item.x + x, y: item.y + y, width: item.width, height: item.height };
  const card = documentCards.get(item);
  if (card !== undefined) { documentCards.set(shifted, card); }
  return shifted;
}

export class DrawnDocumentCardLayouts {
  private labels: DrawnMediaTexts = new DrawnMediaTexts();
  private retries: DrawnMediaTexts = new DrawnMediaTexts();
  private files: DrawnFileCardLayouts = new DrawnFileCardLayouts();
  prepare(ui: UIContext, widget: DrawnDocumentWidget, width: number, environment: string): DrawnDocumentCardLayout {
    if (widget.kind === 'file') {
      const file = this.files.prepare(ui, widget.name, width, environment,
        fileCardTileSize(widget.name, widget.mimeType, documentFileId(widget.thumbnailFile), widget.thumbnailMini ?? ''));
      return { height: file.height, labels: file.labels, file, environment };
    }
    if (widget.kind === 'audio') {
      const text = this.labels.prepare(ui, environment, Math.max(1, width - 48),
        widget.title || widget.name || str('preview_music'), 14, COLOR_TEXT_PRIMARY,
        `${widget.performer ?? ''} ${formatVoiceDuration(widget.duration ?? 0)}`, 11, COLOR_TEXT_SECONDARY, 1, false, 1);
      return { height: Math.max(48, text.height + 21), labels: this.labels, environment };
    }
    // Reserve both action states once. Download/retry transitions stay local.
    const ready = this.labels.prepare(ui, environment, Math.max(1, width - 32), str('preview_voice'), 16, '#FFFFFF');
    const retry = this.retries.prepare(ui, environment, Math.max(1, width - 32), str('live_media_retry_now'), 16, '#FFFFFF');
    return { height: Math.max(60, ready.height + 16, retry.height + 16), labels: this.labels, environment };
  }
}
