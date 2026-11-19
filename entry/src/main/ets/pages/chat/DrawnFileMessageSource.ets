import { UIContext } from '@kit.ArkUI';
import { DrawnFileCardLayout, DrawnFileCardLayouts, rememberFileCard } from './DrawnFileCardLayout';
import { DrawnRichSource, DrawnRichBlock } from '../../util/drawnRichTextPolicy';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';

// One immutable document slot per physical row. File transfer state lives in
// DrawnFileMessage, never in this source or paragraph key. O(1) warm preparation.
export class DrawnFileMessageSource {
  private fileLayouts: DrawnFileCardLayouts | null = null;
  private fileLayout: DrawnFileCardLayout | undefined = undefined;
  private body: DrawnRichSource | null | undefined = undefined;
  private cached: DrawnRichSource | null = null;
  private widget: DrawnDocumentWidget = { key: 'message-file', kind: 'message-file',
    name: '', mimeType: '', size: 0, latitude: 0, longitude: 0, zoom: 0, width: 262, height: 80 };

  prepareFile(ui: UIContext, body: DrawnRichSource | null, fileName: string, width: number, environment: string, tileSize: number = 48): DrawnRichSource {
    if (this.fileLayouts === null) { this.fileLayouts = new DrawnFileCardLayouts(); }
    return this.prepare(body, this.fileLayouts.prepare(ui, fileName, width, environment, tileSize));
  }

  prepare(body: DrawnRichSource | null, layout?: DrawnFileCardLayout): DrawnRichSource {
    if (this.cached !== null && body === this.body && this.fileLayout === layout) { return this.cached; }
    if (layout !== undefined && layout !== this.fileLayout) {
      this.widget = { key: 'message-file', kind: 'message-file', name: '', mimeType: '', size: 0,
        latitude: 0, longitude: 0, zoom: 0, width: layout.width, height: layout.height };
      rememberFileCard(this.widget, layout);
    }
    this.fileLayout = layout;
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
