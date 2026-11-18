import { UIContext } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnPollLayout, DrawnPollLayouts, rememberPollLayout } from './DrawnPollLayout';
import { DrawnRichSource, DrawnRichBlock } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';

// One immutable document slot per physical row. Poll voting state lives in
// DrawnPollMessage. Warm preparation compares options in one linear pass;
// count-only updates retain paragraphs and the immutable document slot.
export class DrawnPollMessageSource {
  private layouts: DrawnPollLayouts = new DrawnPollLayouts();
  private layout: DrawnPollLayout | null = null;
  private chatId: number = 0;
  private rowId: number = -1;
  private pollId: string = '';
  private body: DrawnRichSource | null | undefined = undefined;
  private cached: DrawnRichSource | null = null;
  private widget: DrawnDocumentWidget = { key: 'message-poll', kind: 'message-poll',
    name: '', mimeType: '', size: 0, latitude: 0, longitude: 0, zoom: 0, width: 262, height: 240 };

  prepare(ui: UIContext, body: DrawnRichSource | null, message: MessageEntry,
    width: number, environment: string, expired: boolean, chatId: number): DrawnRichSource {
    const layout = this.layouts.prepare(ui, message, width, environment, expired);
    const rowId = message.rowId, pollId = message.pollId;
    if (this.cached !== null && body === this.body && this.rowId === rowId && this.pollId === pollId && this.chatId === chatId && this.layout === layout) { return this.cached; }
    if (this.rowId !== rowId || this.pollId !== pollId || this.chatId !== chatId || this.layout !== layout) {
      this.widget = { key: 'message-poll', kind: 'message-poll', name: '', mimeType: '', size: 0,
        latitude: 0, longitude: 0, zoom: 0, width: layout.width, height: layout.height };
      rememberPollLayout(this.widget, layout);
    }
    this.layout = layout; this.chatId = chatId;
    this.rowId = rowId; this.pollId = pollId;
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
