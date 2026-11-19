import { UIContext } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnLocationCardLayout, DrawnLocationCardLayouts, rememberLocationCard } from './DrawnLocationCardLayout';
import { DrawnRichSource, DrawnRichBlock } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';

// One immutable document slot per physical row. Map and countdown state lives in
// DrawnLocationMessage, never in this source or paragraph key. O(1) warm preparation.
export class DrawnLocationMessageSource {
  private layouts: DrawnLocationCardLayouts = new DrawnLocationCardLayouts();
  private layout: DrawnLocationCardLayout | null = null;
  private body: DrawnRichSource | null | undefined = undefined;
  private cached: DrawnRichSource | null = null;
  private widget: DrawnDocumentWidget = { key: 'message-location', kind: 'message-location',
    name: '', mimeType: '', size: 0, latitude: 0, longitude: 0, zoom: 0, width: 262, height: 180 };

  prepare(ui: UIContext, body: DrawnRichSource | null, msg: MessageEntry, width: number, environment: string, sharing: boolean): DrawnRichSource {
    const layout = this.layouts.prepare(ui, { title: msg.venueTitle ?? '', address: msg.venueAddress ?? '',
      live: msg.locationLivePeriod > 0, valid: msg.locationValid, sharing, width, environment });
    if (this.cached !== null && body === this.body && this.layout === layout) { return this.cached; }
    this.widget = { key: 'message-location', kind: 'message-location', name: '', mimeType: '', size: 0,
      latitude: 0, longitude: 0, zoom: 0, width: layout.width, height: layout.height };
    rememberLocationCard(this.widget, layout); this.layout = layout;
    const empty: DrawnRichSource = { content: '', runs: [], links: [], targets: new Set<string>() };
    const blocks: DrawnRichBlock[] = [{ source: empty, widget: this.widget,
      kind: 'text', offset: -100000, expandable: false, language: '' }];
    if (body?.blocks !== undefined) { for (const block of body.blocks) { blocks.push(block); } }
    else if (body !== null && body.content !== '') { blocks.push({ source: body, kind: 'text', offset: 0, expandable: false, language: '' }); }
    this.body = body;
    this.cached = { content: body?.content ?? '', runs: [], links: body?.links ?? [],
      targets: body?.targets ?? empty.targets, blocks, hasMath: body?.hasMath };
    return this.cached;
  }
}
