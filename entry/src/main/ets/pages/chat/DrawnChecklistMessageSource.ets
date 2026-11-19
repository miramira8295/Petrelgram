import { UIContext } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnRichSource, DrawnRichBlock } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnChecklistLayout, DrawnChecklistLayouts, rememberChecklistLayout } from './DrawnChecklistLayout';

// The checklist is the entire body. MessageEntry.text remains the complete
// textual preview/search/copy form and must not be appended a second time.
export class DrawnChecklistMessageSource {
  private layouts: DrawnChecklistLayouts = new DrawnChecklistLayouts();
  private layout: DrawnChecklistLayout | null = null;
  private chatId: number = 0;
  private rowId: number = -1;
  private cached: DrawnRichSource | null = null;
  prepare(ui: UIContext, _body: DrawnRichSource | null, message: MessageEntry,
    width: number, environment: string, chatId: number): DrawnRichSource | null {
    const model = message.checklist;
    if (model === undefined) { return null; }
    const layout = this.layouts.prepare(ui, model, width, environment);
    if (this.cached !== null && layout === this.layout && this.chatId === chatId && this.rowId === message.rowId) { return this.cached; }
    const widget: DrawnDocumentWidget = { key: 'message-checklist', kind: 'message-checklist', name: '', mimeType: '', size: 0,
      latitude: 0, longitude: 0, zoom: 0, width: layout.width, height: layout.height };
    rememberChecklistLayout(widget, layout);
    const empty: DrawnRichSource = { content: '', runs: [], links: [], targets: new Set<string>() };
    const blocks: DrawnRichBlock[] = [{ source: empty, widget, kind: 'text', offset: -100000, expandable: false, language: '' }];
    this.layout = layout; this.chatId = chatId; this.rowId = message.rowId;
    this.cached = { content: '', runs: [], links: [], targets: empty.targets, blocks }; return this.cached;
  }
}
