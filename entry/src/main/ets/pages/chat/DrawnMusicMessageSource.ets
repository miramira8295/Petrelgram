import { UIContext } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnRichSource, DrawnRichBlock } from '../../util/drawnRichTextPolicy';
import { DrawnMusicCardLayouts, DrawnMusicCardLayout, rememberMusicCard } from './DrawnMusicCardLayout';

export class DrawnMusicMessageSource {
  private layouts: DrawnMusicCardLayouts = new DrawnMusicCardLayouts();
  private layout: DrawnMusicCardLayout | null = null;
  private body: DrawnRichSource | null = null;
  private cached: DrawnRichSource | null = null;
  prepare(ui: UIContext, body: DrawnRichSource | null, msg: MessageEntry, width: number, environment: string): DrawnRichSource {
    const layout = this.layouts.prepare(ui, msg.audioTitle ?? '', msg.audioPerformer ?? '', msg.videoFileName ?? '', msg.videoMimeType ?? '', msg.videoFileSize ?? 0, width, environment);
    if (this.cached !== null && this.body === body && this.layout === layout) { return this.cached; }
    const widget: DrawnDocumentWidget = { key: 'message-audio', kind: 'message-audio', name: '', mimeType: '', size: 0,
      latitude: 0, longitude: 0, zoom: 0, width, height: layout.height };
    rememberMusicCard(widget, layout);
    const empty: DrawnRichSource = { content: '', runs: [], links: [], targets: new Set<string>() };
    const blocks: DrawnRichBlock[] = [{ source: empty, widget, kind: 'text', offset: -100000, expandable: false, language: '' }];
    if (body?.blocks !== undefined) { for (const block of body.blocks) { blocks.push(block); } }
    else if (body !== null && body.content !== '') { blocks.push({ source: body, kind: 'text', offset: 0, expandable: false, language: '' }); }
    this.layout = layout; this.body = body;
    this.cached = { content: body?.content ?? '', runs: [], links: body?.links ?? [], targets: body?.targets ?? empty.targets, blocks, hasMath: body?.hasMath };
    return this.cached;
  }
}
