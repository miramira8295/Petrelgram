import { DrawnRichSource, DrawnRichBlock } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';

// One immutable document slot per physical row. Sticker animation state lives in
// StickerMessageBubble, never in this source or paragraph key. O(1) warm preparation.
export class DrawnStickerSource {
  private presentation: string = '';
  private sourceWidth: number = 0;
  private sourceHeight: number = 0;
  private body: DrawnRichSource | null | undefined = undefined;
  private cached: DrawnRichSource | null = null;
  private widget: DrawnDocumentWidget = { key: 'message-sticker', kind: 'message-sticker',
    name: '', mimeType: '', size: 0, latitude: 0, longitude: 0, zoom: 0, width: 150, height: 150 };

  prepare(body: DrawnRichSource | null, width: number, height: number, presentation: string = 'sticker'): DrawnRichSource {
    if (this.cached !== null && body === this.body && width === this.sourceWidth && height === this.sourceHeight && presentation === this.presentation) { return this.cached; }
    this.presentation = presentation;
    this.sourceWidth = width; this.sourceHeight = height;
    const w = width > 0 ? width : 512, h = height > 0 ? height : 512;
    const side = presentation === 'animated-emoji' ? 72 : 160;
    this.widget = { key: 'message-sticker', kind: 'message-sticker', name: '', mimeType: '', size: 0,
      latitude: 0, longitude: 0, zoom: 0, width: presentation === 'emoji' ? 72 : w >= h ? side : Math.round(side * w / h),
      height: presentation === 'emoji' ? 68 : h >= w ? side : Math.round(side * h / w) };
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
