import { fullDate } from '../../util/intlFormat';
import { indexDocumentAnchors } from '../../util/drawnDocumentAnchors';
import { DrawnDocumentWidget, drawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnDocumentMedia, drawnDocumentMedia } from '../../util/drawnDocumentMedia';
import { drawnPageButtonAction, drawnPageButtonStyle } from '../../util/drawnPageButton';
import { TdObject } from '../../tdkit/TdTypes';
import { RichRun } from '../../util/richText';
import { richSpansOf, RichSpan } from '../../util/richBlocks';
import { DrawnRichBlock, DrawnRichSource, DrawnRichLink, DrawnRichTableCell, DrawnRichButton, buildDrawnRichSource } from '../../util/drawnRichTextPolicy';

// Android's RichMessageLayout keeps block boundaries; it does not feed the
// conversation-preview flattened text back into the message renderer.
// One source snapshot per physical owner. Geometry/theme/footer updates are O(1).
// Traversal is O(nodes + UTF-16 text + runs), with a bounded nesting depth.
export class DrawnStructuredSource {
  private input: TdObject[] | undefined;
  private environment: string = '';
  private cached: DrawnRichSource | null = null;
  private serial: number = 0;
  private count: number = 0;
  private units: number = 0;
  private links: DrawnRichLink[] = [];
  private targets: Set<string> = new Set<string>();
  reason: string = '';
  private media: DrawnDocumentMedia[] = [];
  private audioItems: DrawnDocumentWidget[] = [];
  private footnotes: Map<string, DrawnRichSource> = new Map<string, DrawnRichSource>();

  prepare(nodes: TdObject[] | undefined, environment: string = ''): DrawnRichSource | null {
    if (nodes === this.input && environment === this.environment) { return this.cached; }
    this.environment = environment; this.input = nodes; this.cached = null; this.serial = 0; this.count = 0; this.units = 0;
    this.links = []; this.targets = new Set<string>(); this.reason = ''; this.media = []; this.audioItems = []; this.footnotes = new Map<string, DrawnRichSource>();
    if (nodes === undefined || nodes.length === 0) { this.reason = 'empty'; return null; }
    const result = this.document(nodes, 0);
    if (result !== null) { result.links = this.links; result.targets = this.targets; result.mediaItems = this.media; result.audioItems = this.audioItems; result.footnotes = this.footnotes; result.anchorPaths = indexDocumentAnchors(result); }
    this.cached = result;
    return result;
  }

  private document(nodes: TdObject[], depth: number): DrawnRichSource | null {
    if (depth > 64) { this.reason = 'structured-depth-limit'; return null; }
    const blocks: DrawnRichBlock[] = [];
    for (const node of nodes) {
      if (++this.count > 2048) { this.reason = 'structured-block-limit'; return null; }
      const type = (node['@type'] as string | undefined) ?? '';
      const offset = this.serial++;
      if (type === 'pageBlockAnchor') {
        blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
          kind: 'anchor', anchorName: ((node['name'] as string | undefined) ?? '').toLowerCase(), offset, expandable: false, language: '' });
        continue;
      }
      if (type === 'pageBlockRelatedArticles') {
        const header = this.inline(node['header'] as TdObject | undefined, true);
        if (header === null) { return null; }
        blocks.push({ source: header, kind: 'text', fontSize: 18, offset, expandable: false, language: '' });
        const articles = (node['articles'] as TdObject[] | undefined) ?? [];
        for (let index: number = 0; index < articles.length; index++) {
          if (++this.count > 2048) { this.reason = 'structured-block-limit'; return null; }
          const article = articles[index];
          const imageNode: TdObject = { '@type': 'pageBlockEmbeddedPost' };
          imageNode['author'] = article['title'] ?? ''; imageNode['url'] = article['url'] ?? '';
          imageNode['author_photo'] = article['photo'];
          const image = drawnDocumentWidget(imageNode, `article:${this.serial}`);
          if (image === null || image.url === '') { this.reason = 'structured-article-invalid'; return null; }
          image.kind = 'article-image';
          const titleNode: TdObject = { '@type': 'richTextPlain' }; titleNode['text'] = image.name;
          const title = this.inline(titleNode, true);
          const author = (article['author'] as string | undefined) ?? '';
          const date = (article['publish_date'] as number | undefined) ?? 0;
          const dateText = Number.isFinite(date) && date > 0 && date <= 8640000000000 ? fullDate(new Date(date * 1000)) : '';
          // Android prioritizes author/date, then description, then URL.
          const description = author !== '' ? (dateText !== '' ? `${dateText} · ${author}` : author)
            : dateText || (article['description'] as string | undefined) || image.url || '';
          const descriptionNode: TdObject = { '@type': 'richTextPlain' }; descriptionNode['text'] = description;
          const source = this.inline(descriptionNode);
          this.units += (image.url ?? '').length;
          if (title === null || source === null || this.units > 131072) { this.reason = 'structured-text-limit'; return null; }
          blocks.push({ source, title, article: image, divider: index < articles.length - 1,
            kind: 'article', offset: this.serial++, expandable: false, language: '' });
        }
        continue;
      }
      if (type === 'pageBlockAuthorDate') {
        const author = node['author'] as TdObject | undefined;
        const date = (node['publish_date'] as number | undefined) ?? 0;
        const prefix = Number.isFinite(date) && date > 0 && date <= 8640000000000
          ? fullDate(new Date(date * 1000)) : '';
        // Prefix the existing rich runs once; links retain their shifted offsets.
        const source = this.inline(author, false, prefix);
        if (source === null) { return null; }
        blocks.push({ source, kind: 'text', fontSize: 12, offset, expandable: false, language: '' });
        continue;
      }
      if (type === 'pageBlockEmbeddedPost') {
        const widget = drawnDocumentWidget(node, `post:${offset}`);
        if (widget === null) { this.reason = 'structured-post-invalid'; return null; }
        this.units += widget.name.length + (widget.url?.length ?? 0) + (widget.html?.length ?? 0);
        if (this.units > 131072) { this.reason = 'structured-text-limit'; return null; }
        const child = this.document((node['page_blocks'] ?? node['blocks'] ?? []) as TdObject[], depth + 1);
        if (child === null) { return null; }
        const body: DrawnRichBlock[] = [{ source: { content: '', runs: [], links: [], targets: new Set<string>() },
          widget, kind: 'widget', offset, expandable: false, language: '' }];
        for (const item of child.blocks ?? []) { body.push(item); }
        child.blocks = body;
        blocks.push({ source: child, kind: 'quote', offset: this.serial++, expandable: false, language: '' });
        const caption = node['caption'] as TdObject | undefined;
        if (caption !== undefined) {
          const text = this.inline((caption['text'] ?? caption) as TdObject);
          const credit = this.inline(caption['credit'] as TdObject | undefined);
          if (text === null || credit === null) { return null; }
          if (text.content !== '') { blocks.push({ source: text, kind: 'text', offset: this.serial++, expandable: false, language: '' }); }
          if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
        }
        continue;
      }
      if (type === 'pageBlockCover') {
        const cover = node['cover'] as TdObject | undefined;
        const child = cover !== undefined ? this.document([cover], depth + 1) : null;
        if (child === null) { return null; }
        blocks.push({ source: child, kind: 'text', offset, expandable: false, language: '' });
        continue;
      }
      if (type === 'pageBlockEmbedded' || type === 'pageBlockChatLink' || type === 'pageBlockMap' || type === 'pageBlockDocument' || type === 'pageBlockVoiceNote' || type === 'pageBlockAudio') {
        const widget = drawnDocumentWidget(node, `widget:${offset}`);
        if (widget === null) { this.reason = 'structured-widget-invalid'; return null; }
        this.units += widget.name.length + (widget.url?.length ?? 0) + (widget.html?.length ?? 0);
        if (this.units > 131072) { this.reason = 'structured-text-limit'; return null; }
        if (widget.kind === 'audio') { this.audioItems.push(widget); }
        blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
          widget, kind: 'widget', offset, expandable: false, language: '' });
        const caption = node['caption'] as TdObject | undefined;
        if (caption !== undefined) {
          const text = this.inline((caption['text'] ?? caption) as TdObject);
          const credit = this.inline(caption['credit'] as TdObject | undefined);
          if (text === null || credit === null) { return null; }
          if (text.content !== '') { blocks.push({ source: text, kind: 'text', offset: this.serial++, expandable: false, language: '' }); }
          if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
        }
        continue;
      }
      if (type === 'pageBlockCollage' || type === 'pageBlockSlideshow') {
        const children = (node['page_blocks'] ?? node['items'] ?? []) as TdObject[];
        if (children.length === 0 || children.length > 256) { this.reason = 'structured-gallery-limit'; return null; }
        const gallery: DrawnDocumentMedia[] = [];
        for (const child of children) {
          if (++this.count > 2048) { this.reason = 'structured-block-limit'; return null; }
          const media = drawnDocumentMedia(child, `media:${this.serial++}`, this.media.length);
          // No silently omitted gallery members: preserve atomic admission.
          if (media === null) { this.reason = 'structured-gallery-member'; return null; }
          gallery.push(media); this.media.push(media);
        }
        blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
          gallery, kind: type === 'pageBlockSlideshow' ? 'slideshow' : 'collage', offset, expandable: false, language: '' });
        const caption = node['caption'] as TdObject | undefined;
        if (caption !== undefined) {
          const text = this.inline((caption['text'] ?? caption) as TdObject);
          const credit = this.inline(caption['credit'] as TdObject | undefined);
          if (text === null || credit === null) { return null; }
          if (text.content !== '') { blocks.push({ source: text, kind: 'text', offset: this.serial++, expandable: false, language: '' }); }
          if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
        }
        continue;
      }
      if (type === 'pageBlockPhoto' || type === 'pageBlockVideo' || type === 'pageBlockAnimation') {
        const media = drawnDocumentMedia(node, `media:${offset}`, this.media.length);
        if (media === null) { this.reason = 'structured-media-missing-file'; return null; }
        this.media.push(media);
        blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
          media, kind: 'media', offset, expandable: false, language: '' });
        const caption = node['caption'] as TdObject | undefined;
        if (caption !== undefined) {
          const text = this.inline((caption['text'] ?? caption) as TdObject);
          const credit = this.inline(caption['credit'] as TdObject | undefined);
          if (text === null || credit === null) { return null; }
          if (text.content !== '') { blocks.push({ source: text, kind: 'text', offset: this.serial++, expandable: false, language: '' }); }
          if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
        }
        continue;
      }
      if (type === 'pageBlockList') {
        const items = (node['items'] as TdObject[] | undefined) ?? [];
        for (const item of items) {
          const child = this.document((item['blocks'] ?? item['page_blocks'] ?? []) as TdObject[], depth + 1);
          if (child === null) { return null; }
          const marker = item['has_checkbox'] === true ? (item['is_checked'] === true ? '☑' : '☐')
            : (item['label'] as string | undefined) || '•';
          blocks.push({ source: child, kind: 'list-item', marker, offset: this.serial++, expandable: false, language: '' });
        }
        continue;
      }
      if (type === 'pageBlockDetails') {
        const title = this.inline((node['title'] ?? node['header'] ?? node['text']) as TdObject | undefined);
        const child = this.document((node['blocks'] ?? node['page_blocks'] ?? []) as TdObject[], depth + 1);
        if (title === null || child === null) { return null; }
        blocks.push({ source: child, title, initiallyOpen: node['is_open'] === true, kind: 'details', offset, expandable: false, language: '' });
        continue;
      }
      if (type === 'pageBlockBlockQuote' || type === 'pageBlockPullQuote') {
        const children = (node['blocks'] ?? node['page_blocks']) as TdObject[] | undefined;
        const child = children !== undefined ? this.document(children, depth + 1)
          : this.inline(node['text'] as TdObject | undefined);
        if (child === null) { return null; }
        blocks.push({ source: child, kind: 'quote', offset, expandable: false, language: '' });
        const credit = this.inline((node['credit'] ?? node['caption']) as TdObject | undefined);
        if (credit !== null && credit.content !== '') {
          blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' });
        }
        continue;
      }
      if (type === 'pageBlockTable') {
        const rawRows = (node['cells'] as TdObject[][] | undefined) ?? [];
        if (rawRows.length > 256) { this.reason = 'structured-table-limit'; return null; }
        const rows: DrawnRichTableCell[][] = [];
        let cells: number = 0;
        const tableLinks: DrawnRichLink[] = [];
        const tableTargets: Set<string> = new Set<string>();
        for (const rawRow of rawRows) {
          const row: DrawnRichTableCell[] = [];
          for (const cell of rawRow) {
            if (++cells > 2048) { this.reason = 'structured-table-limit'; return null; }
            const header = cell['is_header'] === true;
            const source = this.inline(cell['text'] as TdObject | undefined, header);
            if (source === null) { return null; }
            for (const link of source.links) { tableLinks.push(link); }
            for (const target of source.targets) { tableTargets.add(target); }
            const alignment = cell['align'] as TdObject | undefined;
            const vertical = cell['valign'] as TdObject | undefined;
            const valign = vertical?.['@type'] === 'pageBlockVerticalAlignmentMiddle' ? 'middle'
              : vertical?.['@type'] === 'pageBlockVerticalAlignmentBottom' ? 'bottom' : 'top';
            const align = alignment?.['@type'] === 'pageBlockHorizontalAlignmentRight' ? 'right'
              : alignment?.['@type'] === 'pageBlockHorizontalAlignmentCenter' ? 'center' : 'left';
            row.push({ source, header, align, valign, colspan: (cell['colspan'] as number | undefined) ?? 1,
              rowspan: (cell['rowspan'] as number | undefined) ?? 1 });
          }
          rows.push(row);
        }
        const caption = this.inline(node['caption'] as TdObject | undefined);
        if (caption === null) { return null; }
        blocks.push({ source: { content: '', runs: [], links: tableLinks, targets: tableTargets,
          hasMath: rows.some((row: DrawnRichTableCell[]): boolean => row.some((cell: DrawnRichTableCell): boolean => cell.source.hasMath === true)),
          table: { rows, bordered: node['is_bordered'] === true, striped: node['is_striped'] === true } },
          title: caption, kind: 'table', offset, expandable: false, language: '' });
        continue;
      }
      if (type === 'pageBlockButtonRow') {
        const rawButtons = (node['buttons'] as TdObject[] | undefined) ?? [];
        if (rawButtons.length > 128) { this.reason = 'structured-button-limit'; return null; }
        const buttons: DrawnRichButton[] = [];
        for (const button of rawButtons) {
          let label = button['text'] as TdObject | undefined;
          if (typeof button['text'] === 'string') {
            label = { '@type': 'richTextPlain' }; label['text'] = button['text'];
          }
          const source = this.inline(label, true);
          if (source === null) { return null; }
          buttons.push({ source, action: drawnPageButtonAction(button['type'] as TdObject | undefined),
            style: drawnPageButtonStyle(button['style'] as TdObject | undefined) });
        }
        const align = node['align_left'] === true ? 'left' : node['align_right'] === true ? 'right'
          : node['align_center'] === true ? 'center' : 'fill';
        blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
          kind: 'buttons', buttons, buttonAlign: align, offset, expandable: false, language: '' });
        continue;
      }
      if (type === 'pageBlockMath') {
        const expression = (node['source'] ?? node['expression'] ?? '') as string;
        const formula: TdObject = { '@type': 'richTextMathematicalExpression' }; formula['expression'] = expression;
        const source = this.inline(formula);
        if (source === null) { return null; }
        blocks.push({ source, kind: 'math', offset, expandable: false, language: '' });
        continue;
      }
      const heading = type === 'pageBlockTitle' || type === 'pageBlockHeader' ? 20
        : type === 'pageBlockSubtitle' || type === 'pageBlockSubheader' || type === 'pageBlockSectionHeading' ? 18
        : type === 'pageBlockKicker' ? 16 : 0;
      const accepted = heading > 0 || type === 'pageBlockParagraph' || type === 'pageBlockFooter' ||
        type === 'pageBlockPreformatted' || type === 'pageBlockDivider';
      // Never publish a partial document that silently swallowed a media/table
      // block. Their dedicated layout engines must be connected before admission.
      if (!accepted) { this.reason = `structured-kind:${type}`; return null; }
      const source = this.inline((node['text'] ?? node[type.substring(9).toLowerCase()]) as TdObject | undefined, heading > 0);
      if (source === null) { return null; }
      blocks.push({ source, kind: type === 'pageBlockPreformatted' ? 'pre' : type === 'pageBlockDivider' ? 'divider' : 'text',
        fontSize: heading || undefined, offset, expandable: false, language: (node['language'] as string | undefined) ?? '' });
    }
    return { content: '', runs: [], links: [], targets: new Set<string>(), blocks,
      hasEmbed: blocks.some((item: DrawnRichBlock): boolean => item.widget?.kind === 'html-embed' || item.source.hasEmbed === true),
      hasMath: blocks.some((item: DrawnRichBlock): boolean => item.source.hasMath === true || item.title?.hasMath === true || item.buttons?.some((button: DrawnRichButton): boolean => button.source.hasMath === true) === true) };
  }

  private inline(node: TdObject | undefined, bold: boolean = false, prefix: string = ''): DrawnRichSource | null {
    const spans = richSpansOf(node, '', true);
    const anchors: string[] = [];
    const parts: string[] = [], runs: RichRun[] = [];
    const leading = prefix === '' ? '' : prefix + (spans.some((span: RichSpan): boolean => span.text !== '' && span.anchor === undefined) ? ' · ' : '');
    let offset: number = leading.length;
    if (leading !== '') {
      parts.push(leading);
      runs.push({ offset: 0, text: leading, bold: false, italic: false, underline: false,
        strike: false, code: false, spoiler: false, customEmojiId: '', link: false, url: '' });
    }
    for (const span of spans) {
      if (span.anchor !== undefined) { anchors.push(span.anchor); continue; }
      // A formula must retain its image/inline metrics, not turn into plain code.
      if (span.unsupported !== undefined) { this.reason = `structured-inline:${span.unsupported ?? 'math'}`; return null; }
      parts.push(span.text);
      runs.push({ offset, icon: span.icon, text: span.text, marked: span.marked, script: span.script, math: span.math ? span.text : undefined, bold: bold || span.bold, italic: span.italic,
        underline: span.underline, strike: span.strike, code: span.code, spoiler: false,
        customEmojiId: '', link: span.url !== '', url: span.url });
      offset += span.text.length;
    }
    this.units += offset;
    if (this.units > 131072) { this.reason = 'structured-text-limit'; return null; }
    const source = buildDrawnRichSource(parts.join(''), runs);
    if (source !== null) {
      source.anchorNames = anchors;
      for (const name of anchors) { if (name !== '' && source.content !== '') { this.footnotes.set(name, source); } }
      source.hasMath = runs.some((run: RichRun): boolean => run.math !== undefined);
      for (const link of source.links) { this.links.push(link); }
      for (const target of source.targets) { this.targets.add(target); }
    }
    return source;
  }
}
