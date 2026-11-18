import { DrawnRichSource, DrawnRichBlock } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';

// One immutable document slot per physical row. Map and countdown state lives in
// DrawnLocationMessage, never in this source or paragraph key. O(1) warm preparation.
export class DrawnLocationMessageSource {
  private sharing: boolean = false;
  private body: DrawnRichSource | null | undefined = undefined;
  private cached: DrawnRichSource | null = null;
  private widget: DrawnDocumentWidget = { key: 'message-location', kind: 'message-location',
    name: '', mimeType: '', size: 0, latitude: 0, longitude: 0, zoom: 0, width: 262, height: 180 };

  prepare(body: DrawnRichSource | null, sharing: boolean): DrawnRichSource {
    if (this.cached !== null && body === this.body && sharing === this.sharing) { return this.cached; }
    this.widget = { key: 'message-location', kind: 'message-location', name: '', mimeType: '', size: 0,
      latitude: 0, longitude: 0, zoom: 0, width: 262, height: sharing ? 245 : 180 };
    this.sharing = sharing;
    const empty: DrawnRichSource = { content: '', runs: [], links: [], targets: new Set<string>() };
    const blocks: DrawnRichBlock[] = [{ source: empty, widget: this.widget,
      kind: 'text', offset: -100000, expandable: false, language: '' }];
    if (body?.blocks !== undefined) { for (const block of body.blocks) { blocks.push(block); } }
    else if (body !== null) { blocks.push({ source: body, kind: 'text', offset: 0, expandable: false, language: '' }); }
    this.body = body;
    this.cached = { content: body?.content ?? '', runs: [], links: body?.links ?? [],
      targets: body?.targets ?? empty.targets, blocks, hasMath: body?.hasMath };
    return this.cached;
  }
}
