import { RichMessageTaskIndex, richMessageTaskIndex } from '../../util/richMessageTaskEdit';
import { fullDate } from '../../util/intlFormat';
import { indexDocumentAnchors } from '../../util/drawnDocumentAnchors';
import { DrawnDocumentWidget, drawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { DrawnDocumentMedia, drawnDocumentMedia } from '../../util/drawnDocumentMedia';
import { drawnPageButtonAction, drawnPageButtonStyle } from '../../util/drawnPageButton';
import { TdObject } from '../../tdkit/TdTypes';
import { RichRun } from '../../util/richText';
import { richSpansOf, RichSpan } from '../../util/richBlocks';
import { DrawnRichBlock, DrawnRichSource, DrawnRichLink, DrawnRichTableCell, DrawnRichButton, buildDrawnRichSource } from '../../util/drawnRichTextPolicy';

interface DrawnStructuredInline {
  node: TdObject | undefined;
  bold: boolean;
  prefix: string;
  signature: string;
  source: DrawnRichSource;
}

interface DrawnStructuredFrame {
  nodes: TdObject[];
  index: number;
  blocks: DrawnRichBlock[];
  owner?: TdObject;
  accept: (source: DrawnRichSource) => boolean;
}

// Android's RichMessageLayout keeps block boundaries; it does not feed the
// conversation-preview flattened text back into the message renderer.
// One source snapshot per physical owner. Geometry/theme/footer updates are O(1).
// Each sibling block/inline source is prepared once, O(nodes + UTF-16 text + runs).
// Paragraph flow and the existing linear gallery/button packers handle large
// documents without a document-wide block/text/count rejection. Explicit
// continuation frames keep nesting independent of the JavaScript call stack.
export class DrawnStructuredSource {
  private input: TdObject[] | undefined;
  private environment: string = '';
  private allowTaskActions: boolean = false;
  private taskIndex: RichMessageTaskIndex | null = null;
  private inlineIndex: number = 0;
  private inlineCache: DrawnStructuredInline[] = [];
  private cached: DrawnRichSource | null = null;
  private serial: number = 0;
  private links: DrawnRichLink[] = [];
  private targets: Set<string> = new Set<string>();
  reason: string = '';
  private media: DrawnDocumentMedia[] = [];
  private audioItems: DrawnDocumentWidget[] = [];
  private footnotes: Map<string, DrawnRichSource> = new Map<string, DrawnRichSource>();

  prepare(nodes: TdObject[] | undefined, environment: string = '', allowTaskActions: boolean = false): DrawnRichSource | null {
    if (nodes === this.input && environment === this.environment && this.allowTaskActions === allowTaskActions) { return this.cached; }
    this.allowTaskActions = allowTaskActions;
    this.taskIndex = allowTaskActions && nodes !== undefined ? richMessageTaskIndex(nodes) : null;
    this.environment = environment; this.input = nodes; this.cached = null; this.serial = 0;
    this.inlineIndex = 0;
    this.links = []; this.targets = new Set<string>(); this.reason = ''; this.media = []; this.audioItems = []; this.footnotes = new Map<string, DrawnRichSource>();
    if (nodes === undefined || nodes.length === 0) { this.reason = 'empty'; return null; }
    const result = this.document(nodes);
    this.inlineCache.length = this.inlineIndex;
    if (result !== null) { result.links = this.links; result.targets = this.targets; result.mediaItems = this.media; result.audioItems = this.audioItems; result.footnotes = this.footnotes; result.anchorPaths = indexDocumentAnchors(result); }
    this.cached = result;
    return result;
  }

  private document(nodes: TdObject[]): DrawnRichSource | null {
    let result: DrawnRichSource | null = null;
    const pending: DrawnStructuredFrame[] = [{ nodes, index: 0, blocks: [],
      accept: (source: DrawnRichSource): boolean => { result = source; return true; } }];
    const active = new Set<TdObject>();
    while (pending.length > 0) {
      const frame = pending[pending.length - 1];
      if (frame.index < frame.nodes.length) {
        if (!this.appendNode(frame.nodes[frame.index++], frame.blocks, pending, active)) { return null; }
        continue;
      }
      pending.pop();
      if (frame.owner !== undefined) { active.delete(frame.owner); }
      let nestingDepth: number = 1;
      for (const block of frame.blocks) { nestingDepth = Math.max(nestingDepth, 1 + (block.source.nestingDepth ?? 0)); }
      const source: DrawnRichSource = { content: '', runs: [], links: [], targets: new Set<string>(), blocks: frame.blocks, nestingDepth,
        hasEmbed: frame.blocks.some((item: DrawnRichBlock): boolean => item.widget?.kind === 'html-embed' || item.source.hasEmbed === true),
        hasMath: frame.blocks.some((item: DrawnRichBlock): boolean => item.source.hasMath === true || item.title?.hasMath === true || item.buttons?.some((button: DrawnRichButton): boolean => button.source.hasMath === true) === true) };
      if (!frame.accept(source)) { return null; }
    }
    return result;
  }

  private descend(nodes: TdObject[], owner: TdObject, pending: DrawnStructuredFrame[], active: Set<TdObject>,
    accept: (source: DrawnRichSource) => boolean): boolean {
    if (active.has(owner)) { this.reason = 'structured-cycle'; return false; }
    active.add(owner); pending.push({ nodes, index: 0, blocks: [], owner, accept }); return true;
  }

  private appendList(items: TdObject[], index: number, blocks: DrawnRichBlock[], pending: DrawnStructuredFrame[], active: Set<TdObject>): boolean {
    if (index === items.length) { return true; }
    // accept() runs from document() after popping one frame. Scheduling the
    // next item here does not recurse through the document or earlier items.
    const item = items[index];
    return this.descend((item['blocks'] ?? item['page_blocks'] ?? []) as TdObject[], item, pending, active,
      (child: DrawnRichSource): boolean => {
        const marker = item['has_checkbox'] === true ? (item['is_checked'] === true ? '☑' : '☐') : (item['label'] as string | undefined) || '•';
        const task = this.taskIndex !== null && this.taskIndex.inputBlocks !== null ? this.taskIndex.byItem.get(item) : undefined;
        blocks.push({ source: child, kind: 'list-item', marker, task, offset: this.serial++, expandable: false, language: '' });
        return this.appendList(items, index + 1, blocks, pending, active);
      });
  }

  private caption(node: TdObject, blocks: DrawnRichBlock[]): boolean {
    const caption = node['caption'] as TdObject | undefined;
    if (caption === undefined) { return true; }
    const text = this.inline((caption['text'] ?? caption) as TdObject), credit = this.inline(caption['credit'] as TdObject | undefined);
    if (text === null || credit === null) { return false; }
    if (text.content !== '') { blocks.push({ source: text, kind: 'text', offset: this.serial++, expandable: false, language: '' }); }
    if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
    return true;
  }

  private appendNode(node: TdObject, blocks: DrawnRichBlock[], pending: DrawnStructuredFrame[], active: Set<TdObject>): boolean {
    const type = (node['@type'] as string | undefined) ?? '';
    const offset = this.serial++;
    if (type === 'pageBlockAnchor') {
      blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
        kind: 'anchor', anchorName: ((node['name'] as string | undefined) ?? '').toLowerCase(), offset, expandable: false, language: '' });
      return true;
    }
    if (type === 'pageBlockRelatedArticles') {
      const header = this.inline(node['header'] as TdObject | undefined, true);
      if (header === null) { return false; }
      blocks.push({ source: header, kind: 'text', fontSize: 18, offset, expandable: false, language: '' });
      const articles = (node['articles'] as TdObject[] | undefined) ?? [];
      for (let index: number = 0; index < articles.length; index++) {
        const article = articles[index];
        const imageNode: TdObject = { '@type': 'pageBlockEmbeddedPost' };
        imageNode['author'] = article['title'] ?? ''; imageNode['url'] = article['url'] ?? '';
        imageNode['author_photo'] = article['photo'];
        const image = drawnDocumentWidget(imageNode, `article:${this.serial}`);
        if (image === null || image.url === '') { this.reason = 'structured-article-invalid'; return false; }
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
        if (title === null || source === null) { return false; }
        blocks.push({ source, title, article: image, divider: index < articles.length - 1,
          kind: 'article', offset: this.serial++, expandable: false, language: '' });
      }
      return true;
    }
    if (type === 'pageBlockAuthorDate') {
      const author = node['author'] as TdObject | undefined;
      const date = (node['publish_date'] as number | undefined) ?? 0;
      const prefix = Number.isFinite(date) && date > 0 && date <= 8640000000000
        ? fullDate(new Date(date * 1000)) : '';
      // Prefix the existing rich runs once; links retain their shifted offsets.
      const source = this.inline(author, false, prefix);
      if (source === null) { return false; }
      blocks.push({ source, kind: 'text', fontSize: 12, offset, expandable: false, language: '' });
      return true;
    }
    if (type === 'pageBlockEmbeddedPost') {
      const widget = drawnDocumentWidget(node, `post:${offset}`);
      if (widget === null) { this.reason = 'structured-post-invalid'; return false; }
      return this.descend((node['page_blocks'] ?? node['blocks'] ?? []) as TdObject[], node, pending, active,
        (child: DrawnRichSource): boolean => {
          const body: DrawnRichBlock[] = [{ source: { content: '', runs: [], links: [], targets: new Set<string>() },
            widget, kind: 'widget', offset, expandable: false, language: '' }];
          for (const item of child.blocks ?? []) { body.push(item); }
          child.blocks = body;
          blocks.push({ source: child, kind: 'quote', offset: this.serial++, expandable: false, language: '' });
          return this.caption(node, blocks);
        });
    }
    if (type === 'pageBlockCover') {
      const cover = node['cover'] as TdObject | undefined;
      if (cover === undefined) { this.reason = 'structured-cover-invalid'; return false; }
      return this.descend([cover], node, pending, active, (child: DrawnRichSource): boolean => {
        blocks.push({ source: child, kind: 'text', offset, expandable: false, language: '' }); return true;
      });
    }
    if (type === 'pageBlockEmbedded' || type === 'pageBlockChatLink' || type === 'pageBlockMap' || type === 'pageBlockDocument' || type === 'pageBlockVoiceNote' || type === 'pageBlockAudio') {
      const widget = drawnDocumentWidget(node, `widget:${offset}`);
      if (widget === null) { this.reason = 'structured-widget-invalid'; return false; }
      if (widget.kind === 'audio') { this.audioItems.push(widget); }
      blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
        widget, kind: 'widget', offset, expandable: false, language: '' });
      const caption = node['caption'] as TdObject | undefined;
      if (caption !== undefined) {
        const text = this.inline((caption['text'] ?? caption) as TdObject);
        const credit = this.inline(caption['credit'] as TdObject | undefined);
        if (text === null || credit === null) { return false; }
        if (text.content !== '') { blocks.push({ source: text, kind: 'text', offset: this.serial++, expandable: false, language: '' }); }
        if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
      }
      return true;
    }
    if (type === 'pageBlockCollage' || type === 'pageBlockSlideshow') {
      const children = (node['page_blocks'] ?? node['items'] ?? []) as TdObject[];
      if (children.length === 0) { this.reason = 'structured-gallery-limit'; return false; }
      const gallery: DrawnDocumentMedia[] = [];
      for (const child of children) {
        const media = drawnDocumentMedia(child, `media:${this.serial++}`, this.media.length);
        // No silently omitted gallery members: preserve atomic admission.
        if (media === null) { this.reason = 'structured-gallery-member'; return false; }
        gallery.push(media); this.media.push(media);
      }
      blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
        gallery, kind: type === 'pageBlockSlideshow' ? 'slideshow' : 'collage', offset, expandable: false, language: '' });
      const caption = node['caption'] as TdObject | undefined;
      if (caption !== undefined) {
        const text = this.inline((caption['text'] ?? caption) as TdObject);
        const credit = this.inline(caption['credit'] as TdObject | undefined);
        if (text === null || credit === null) { return false; }
        if (text.content !== '') { blocks.push({ source: text, kind: 'text', offset: this.serial++, expandable: false, language: '' }); }
        if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
      }
      return true;
    }
    if (type === 'pageBlockPhoto' || type === 'pageBlockVideo' || type === 'pageBlockAnimation') {
      const media = drawnDocumentMedia(node, `media:${offset}`, this.media.length);
      if (media === null) { this.reason = 'structured-media-missing-file'; return false; }
      this.media.push(media);
      blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
        media, kind: 'media', offset, expandable: false, language: '' });
      const caption = node['caption'] as TdObject | undefined;
      if (caption !== undefined) {
        const text = this.inline((caption['text'] ?? caption) as TdObject);
        const credit = this.inline(caption['credit'] as TdObject | undefined);
        if (text === null || credit === null) { return false; }
        if (text.content !== '') { blocks.push({ source: text, kind: 'text', offset: this.serial++, expandable: false, language: '' }); }
        if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
      }
      return true;
    }
    if (type === 'pageBlockList') {
      return this.appendList((node['items'] as TdObject[] | undefined) ?? [], 0, blocks, pending, active);
    }
    if (type === 'pageBlockDetails') {
      const title = this.inline((node['title'] ?? node['header'] ?? node['text']) as TdObject | undefined);
      if (title === null) { return false; }
      return this.descend((node['blocks'] ?? node['page_blocks'] ?? []) as TdObject[], node, pending, active,
        (child: DrawnRichSource): boolean => {
          blocks.push({ source: child, title, initiallyOpen: node['is_open'] === true, kind: 'details', offset, expandable: false, language: '' }); return true;
        });
    }
    if (type === 'pageBlockBlockQuote' || type === 'pageBlockPullQuote') {
      const accept = (child: DrawnRichSource): boolean => {
        blocks.push({ source: child, kind: 'quote', offset, expandable: false, language: '' });
        const credit = this.inline((node['credit'] ?? node['caption']) as TdObject | undefined);
        if (credit === null) { return false; }
        if (credit.content !== '') { blocks.push({ source: credit, kind: 'text', fontSize: 12, offset: this.serial++, expandable: false, language: '' }); }
        return true;
      };
      const children = (node['blocks'] ?? node['page_blocks']) as TdObject[] | undefined;
      if (children !== undefined) { return this.descend(children, node, pending, active, accept); }
      const child = this.inline(node['text'] as TdObject | undefined);
      return child !== null && accept(child);
    }
    if (type === 'pageBlockTable') {
      const rawRows = (node['cells'] as TdObject[][] | undefined) ?? [];
      const rows: DrawnRichTableCell[][] = [];
      const tableLinks: DrawnRichLink[] = [];
      const tableTargets: Set<string> = new Set<string>();
      for (const rawRow of rawRows) {
        const row: DrawnRichTableCell[] = [];
        for (const cell of rawRow) {
          const header = cell['is_header'] === true;
          const source = this.inline(cell['text'] as TdObject | undefined, header);
          if (source === null) { return false; }
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
      if (caption === null) { return false; }
      blocks.push({ source: { content: '', runs: [], links: tableLinks, targets: tableTargets,
        hasMath: rows.some((row: DrawnRichTableCell[]): boolean => row.some((cell: DrawnRichTableCell): boolean => cell.source.hasMath === true)),
        table: { rows, bordered: node['is_bordered'] === true, striped: node['is_striped'] === true } },
        title: caption, kind: 'table', offset, expandable: false, language: '' });
      return true;
    }
    if (type === 'pageBlockButtonRow') {
      const rawButtons = (node['buttons'] as TdObject[] | undefined) ?? [];
      const buttons: DrawnRichButton[] = [];
      for (const button of rawButtons) {
        let label = button['text'] as TdObject | undefined;
        if (typeof button['text'] === 'string') {
          label = { '@type': 'richTextPlain' }; label['text'] = button['text'];
        }
        const source = this.inline(label, true);
        if (source === null) { return false; }
        buttons.push({ source, action: drawnPageButtonAction(button['type'] as TdObject | undefined),
          style: drawnPageButtonStyle(button['style'] as TdObject | undefined) });
      }
      const align = node['align_left'] === true ? 'left' : node['align_right'] === true ? 'right'
        : node['align_center'] === true ? 'center' : 'fill';
      blocks.push({ source: { content: '', runs: [], links: [], targets: new Set<string>() },
        kind: 'buttons', buttons, buttonAlign: align, offset, expandable: false, language: '' });
      return true;
    }
    if (type === 'pageBlockMath') {
      const expression = (node['source'] ?? node['expression'] ?? '') as string;
      const formula: TdObject = { '@type': 'richTextMathematicalExpression' }; formula['expression'] = expression;
      const source = this.inline(formula);
      if (source === null) { return false; }
      blocks.push({ source, kind: 'math', offset, expandable: false, language: '' });
      return true;
    }
    const heading = type === 'pageBlockTitle' || type === 'pageBlockHeader' ? 20
      : type === 'pageBlockSubtitle' || type === 'pageBlockSubheader' || type === 'pageBlockSectionHeading' ? 18
      : type === 'pageBlockKicker' ? 16 : 0;
    const accepted = heading > 0 || type === 'pageBlockParagraph' || type === 'pageBlockFooter' ||
      type === 'pageBlockPreformatted' || type === 'pageBlockDivider';
    // Never publish a partial document that silently swallowed a media/table
    // block. Their dedicated layout engines must be connected before admission.
    if (!accepted) { this.reason = `structured-kind:${type}`; return false; }
    const source = this.inline((node['text'] ?? node[type.substring(9).toLowerCase()]) as TdObject | undefined, heading > 0);
    if (source === null) { return false; }
    blocks.push({ source, kind: type === 'pageBlockPreformatted' ? 'pre' : type === 'pageBlockDivider' ? 'divider' : 'text',
      fontSize: heading || undefined, offset, expandable: false, language: (node['language'] as string | undefined) ?? '' });
    return true;
  }

  private registerInline(source: DrawnRichSource): DrawnRichSource {
    for (const name of source.anchorNames ?? []) { if (name !== '' && source.content !== '') { this.footnotes.set(name, source); } }
    for (const link of source.links) { this.links.push(link); }
    for (const target of source.targets) { this.targets.add(target); }
    return source;
  }

  private inline(node: TdObject | undefined, bold: boolean = false, prefix: string = ''): DrawnRichSource | null {
    const index = this.inlineIndex++, previous = this.inlineCache[index];
    if (previous !== undefined && previous.node === node && previous.bold === bold && previous.prefix === prefix) {
      return this.registerInline(previous.source);
    }
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
        underline: span.underline, strike: span.strike, code: span.code, spoiler: span.spoiler === true,
        customEmojiId: span.customEmojiId ?? '', link: span.url !== '', url: span.url });
      offset += span.text.length;
    }
    const content = parts.join('');
    // The signature contains flattened leaf runs, never the nested block tree.
    // Server checkbox edits can replace equivalent richText objects; unchanged
    // paragraphs keep their source and native layouts even across those copies.
    const signature = JSON.stringify([content, runs, anchors]);
    if (previous !== undefined && previous.signature === signature) {
      previous.node = node; previous.bold = bold; previous.prefix = prefix;
      return this.registerInline(previous.source);
    }
    const source = buildDrawnRichSource(content, runs);
    if (source !== null) {
      source.anchorNames = anchors;
      source.hasMath = runs.some((run: RichRun): boolean => run.math !== undefined);
      this.inlineCache[index] = { node, bold, prefix, signature, source };
      return this.registerInline(source);
    }
    return source;
  }
}
