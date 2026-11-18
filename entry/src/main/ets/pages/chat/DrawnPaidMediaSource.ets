import { UIContext } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnPaidMediaLayout, DrawnPaidMediaLayouts, rememberPaidMediaLayout } from './DrawnPaidMediaLayout';
import { DrawnRichSource, DrawnRichBlock } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';

// One immutable document slot per physical row. Paid-media cover state lives in
// DrawnPaidMediaMessage, never in this source or paragraph key. O(1) warm preparation.
export class DrawnPaidMediaSource {
  private layouts: DrawnPaidMediaLayouts = new DrawnPaidMediaLayouts();
  private layout: DrawnPaidMediaLayout | null = null;
  private chatId: number = 0;
  private rowId: number = -1;
  private body: DrawnRichSource | null | undefined = undefined;
  private cached: DrawnRichSource | null = null;
  private widget: DrawnDocumentWidget = { key: 'message-paid-media', kind: 'message-paid-media',
    name: '', mimeType: '', size: 0, latitude: 0, longitude: 0, zoom: 0, width: 262, height: 240 };

  prepare(ui: UIContext, body: DrawnRichSource | null, message: MessageEntry, width: number,
    environment: string, chatId: number): DrawnRichSource {
    const layout = this.layouts.prepare(ui, message, width, environment), rowId = message.rowId;
    if (this.cached !== null && body === this.body && this.rowId === rowId && this.chatId === chatId &&
      this.layout === layout) { return this.cached; }
    if (this.rowId !== rowId || this.chatId !== chatId || this.layout !== layout) {
      this.widget = { key: 'message-paid-media', kind: 'message-paid-media', name: '', mimeType: '', size: 0,
        latitude: 0, longitude: 0, zoom: 0, width: layout.width, height: layout.height };
      rememberPaidMediaLayout(this.widget, layout);
    }
    this.rowId = rowId; this.chatId = chatId; this.layout = layout;
    const empty: DrawnRichSource = { content: '', runs: [], links: [], targets: new Set<string>() };
    const blocks: DrawnRichBlock[] = [{ source: empty, widget: this.widget,
      kind: 'text', offset: -100000, expandable: false, language: '' }];
    if (body?.blocks !== undefined) { for (const block of body.blocks) { blocks.push(block); } }
    else if (body !== null) { blocks.push({ source: body, kind: 'text', offset: 0, expandable: false, language: '' }); }
    this.body = body;
    this.cached = { content: body?.content ?? '', runs: [], links: body?.links ?? [],
      targets: body?.targets ?? empty.targets, blocks, hasMath: body?.hasMath, hasEmbed: body?.hasEmbed };
    return this.cached;
  }
}
