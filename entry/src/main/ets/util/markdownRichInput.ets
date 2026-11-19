import CommonMarkParser, { CommonMarkNode, inlineMarkdown } from '../vendor/commonmark/commonmark';
import { TdObject } from '../tdkit/TdTypes';
import { drawnFirstStrongRtl } from './drawnTextDirection';

export interface MarkdownResolvedImage { file: TdObject; width: number; height: number; animation?: boolean; duration?: number; }
export interface MarkdownImageResolver { resolve(url: string): Promise<MarkdownResolvedImage>; }
export interface MarkdownRichMedia { url: string; block: TdObject; }
export interface MarkdownRichDraft { content: TdObject; media: MarkdownRichMedia[]; }
interface BlockWork { node: CommonMarkNode; target: TdObject[]; trimTask: number; ordinal: number; }
interface InlineWork { node: CommonMarkNode; exit: boolean; link: string; }
interface InlinePiece { rich?: TdObject; image?: CommonMarkNode; alt?: string; link?: string; }

function td(kind: string): TdObject { const value: TdObject = {}; value['@type'] = kind; return value; }
function plain(value: string): TdObject { const rich = td('richTextPlain'); rich['text'] = value; return rich; }
function richMany(parts: TdObject[]): TdObject {
  if (parts.length === 0) { return plain(''); }
  if (parts.length === 1) { return parts[0]; }
  const rich = td('richTexts'); rich['texts'] = parts; return rich;
}
function wrapped(kind: string, child: TdObject): TdObject { const rich = td(kind); rich['text'] = child; return rich; }
function linked(child: TdObject, url: string): TdObject {
  const rich = wrapped('richTextUrl', child); rich['url'] = url; rich['is_cached'] = false; return rich;
}
function textBlock(kind: string, text: TdObject): TdObject { const block = td(kind); block['text'] = text; return block; }
function safeLink(url: string): boolean { return /^(?:https?:|mailto:|tel:|tg:)/i.test(url); }
function imageLink(url: string): boolean { return /^https?:\/\//i.test(url); }

// The commonmark parser and this adapter both use explicit stacks. Repeated
// nested style nodes are counts, not copied ancestor trees: wrappers per leaf
// stay bounded by the supported style kinds, even at extreme Markdown depth.
function inlinePieces(node: CommonMarkNode): InlinePiece[] {
  const result: InlinePiece[] = [], work: InlineWork[] = [];
  let current = node.firstChild, bold = 0, italic = 0, strike = 0, spoiler = 0, link = '';
  while (current !== null || work.length > 0) {
    if (current === null) {
      const item = work.pop()!;
      if (item.exit) {
        if (item.node.type === 'strong') { bold--; }
        else if (item.node.type === 'emph') { italic--; }
        else if (item.node.type === 'strikethrough') { strike--; }
        else if (item.node.type === 'spoiler') { spoiler--; }
        else if (item.node.type === 'link') { link = item.link; }
      } else { current = item.node; }
      continue;
    }
    const n: CommonMarkNode = current;
    if (n.next !== null) { work.push({ node: n.next, exit: false, link: '' }); }
    current = null;
    if (n.type === 'strong' || n.type === 'emph' || n.type === 'strikethrough' || n.type === 'spoiler' || n.type === 'link') {
      work.push({ node: n, exit: true, link });
      if (n.type === 'strong') { bold++; }
      else if (n.type === 'emph') { italic++; }
      else if (n.type === 'strikethrough') { strike++; }
      else if (n.type === 'spoiler') { spoiler++; }
      else { link = n.destination ?? ''; }
      current = n.firstChild; continue;
    }
    if (n.type === 'image') {
      const words: string[] = [], imageNodes: CommonMarkNode[] = [];
      if (n.firstChild !== null) { imageNodes.push(n.firstChild); }
      while (imageNodes.length > 0) {
        const child = imageNodes.pop()!;
        if (child.next !== null) { imageNodes.push(child.next); }
        if (child.firstChild !== null) { imageNodes.push(child.firstChild); }
        else { words.push(child.type === 'linebreak' || child.type === 'softbreak' ? ' ' : child.literal ?? ''); }
      }
      result.push({ image: n, alt: words.join(''), link }); continue;
    }
    let value = n.type === 'linebreak' ? '\n' : n.type === 'softbreak' ? ' ' : n.literal ?? '';
    if (n.type !== 'text' && n.type !== 'code' && n.type !== 'linebreak' && n.type !== 'softbreak' && n.type !== 'html_inline') {
      if (n.firstChild !== null) { current = n.firstChild; }
      continue;
    }
    let rich = n.type === 'code' ? wrapped('richTextFixed', plain(value)) : plain(value);
    if (italic > 0) { rich = wrapped('richTextItalic', rich); }
    if (bold > 0) { rich = wrapped('richTextBold', rich); }
    if (strike > 0) { rich = wrapped('richTextStrikethrough', rich); }
    if (spoiler > 0) { rich = wrapped('richTextSpoiler', rich); }
    if (link !== '') {
      if (safeLink(link)) { rich = linked(rich, link); }
      else { rich = richMany([rich, plain(` (${link})`)]); }
    }
    result.push({ rich });
  }
  return result;
}

function appendPhoto(piece: InlinePiece, target: TdObject[], media: MarkdownRichMedia[]): void {
  const image = piece.image!, url = image.destination ?? '';
  let caption = plain(piece.alt ?? '');
  if (piece.link !== undefined && safeLink(piece.link)) { caption = linked(caption, piece.link); }
  const block = td('inputPageBlockPhoto'), blockCaption = textBlock('pageBlockCaption', caption);
  blockCaption['credit'] = plain(image.title ?? '');
  block['has_spoiler'] = false; block['caption'] = blockCaption;
  target.push(block); media.push({ url, block });
}

function appendInlineBlocks(node: CommonMarkNode, target: TdObject[], media: MarkdownRichMedia[], heading: number = 0): void {
  let parts: TdObject[] = [];
  const flush = (): void => {
    if (parts.length === 0) { return; }
    const block = textBlock(heading > 0 ? 'inputPageBlockSectionHeading' : 'inputPageBlockParagraph', richMany(parts));
    if (heading > 0) { block['size'] = heading; }
    target.push(block); parts = [];
  };
  for (const piece of inlinePieces(node)) {
    if (piece.rich !== undefined) { parts.push(piece.rich); continue; }
    const image = piece.image!, url = image.destination ?? '';
    if (!imageLink(url)) {
      parts.push(plain(`![${piece.alt ?? ''}](${url}${image.title ? ` "${image.title}"` : ''})`)); continue;
    }
    flush(); appendPhoto(piece, target, media);
  }
  flush();
}

// Linear table splitter: pre-index matching code-span runs, then inspect each
// character once. Escaped pipes and pipes inside matching backticks stay cells.
export function splitMarkdownTableRow(raw: string): string[] {
  const nextTicks: Map<number, number> = new Map(), lastByLength: Map<number, number> = new Map();
  const starts: number[] = [], lengths: number[] = [];
  for (let i: number = 0; i < raw.length; i++) {
    if (raw.charAt(i) === '\\') { i++; continue; }
    if (raw.charAt(i) !== '`') { continue; }
    const start = i; while (raw.charAt(i + 1) === '`') { i++; }
    starts.push(start); lengths.push(i - start + 1);
  }
  for (let i: number = starts.length - 1; i >= 0; i--) {
    const next = lastByLength.get(lengths[i]); if (next !== undefined) { nextTicks.set(starts[i], next); }
    lastByLength.set(lengths[i], starts[i]);
  }
  const result: string[] = [];
  let start = 0, codeEnd = -1;
  for (let i: number = 0; i < raw.length; i++) {
    const char = raw.charAt(i);
    if (char === '\\') { i++; continue; }
    if (char === '`') {
      if (i === codeEnd) { codeEnd = -1; }
      else if (codeEnd < 0) { codeEnd = nextTicks.get(i) ?? -1; }
      while (raw.charAt(i + 1) === '`') { i++; }
    } else if (char === '|' && codeEnd < 0) { result.push(raw.substring(start, i).trim()); start = i + 1; }
  }
  result.push(raw.substring(start).trim());
  if (result.length > 1 && result[0] === '') { result.shift(); }
  if (result.length > 1 && result[result.length - 1] === '') { result.pop(); }
  return result;
}

function tableOf(parser: CommonMarkParser, raw: string, media: MarkdownRichMedia[], images: TdObject[]): TdObject | null {
  const lines = raw.trimEnd().split('\n');
  if (lines.length < 2 || lines[0].indexOf('|') < 0) { return null; }
  const header = splitMarkdownTableRow(lines[0]), divider = splitMarkdownTableRow(lines[1]);
  if (header.length !== divider.length || divider.length === 0) { return null; }
  for (const cell of divider) { if (!/^:?-{3,}:?$/.test(cell)) { return null; } }
  const cells: TdObject[][] = [];
  for (let r: number = 0; r < lines.length; r++) {
    if (r === 1 || lines[r].trim() === '') { continue; }
    const source = r === 0 ? header : splitMarkdownTableRow(lines[r]), row: TdObject[] = [];
    // Keep extra source cells rather than silently discarding text in malformed
    // GFM rows. TD's table geometry handles sparse/uneven rows independently.
    for (let c: number = 0; c < Math.max(source.length, header.length); c++) {
      const pieces = inlinePieces(inlineMarkdown(parser, source[c] ?? ''));
      const text: TdObject[] = [];
      for (const piece of pieces) {
        if (piece.rich !== undefined) { text.push(piece.rich); }
        else {
          const url = piece.image?.destination ?? '';
          if (imageLink(url)) {
            // Input richTextIcon is forbidden by TDLib. Keep a link in the cell
            // and the actual uploaded photo immediately after the native table.
            text.push(linked(plain(piece.alt || url), url));
            appendPhoto(piece, images, media);
          } else { text.push(plain(`![${piece.alt ?? ''}](${url})`)); }
        }
      }
      const alignment = divider[c] ?? '';
      const cell = textBlock('pageBlockTableCell', richMany(text));
      cell['is_header'] = r === 0; cell['colspan'] = 1; cell['rowspan'] = 1;
      cell['align'] = td(alignment.startsWith(':') && alignment.endsWith(':') ? 'pageBlockHorizontalAlignmentCenter' : alignment.endsWith(':') ?
        'pageBlockHorizontalAlignmentRight' : 'pageBlockHorizontalAlignmentLeft');
      cell['valign'] = td('pageBlockVerticalAlignmentTop'); row.push(cell);
    }
    cells.push(row);
  }
  const table = td('inputPageBlockTable');
  table['caption'] = plain(''); table['cells'] = cells; table['is_bordered'] = true;
  table['is_striped'] = false; table['is_compact'] = false; return table;
}

function childrenWork(node: CommonMarkNode, target: TdObject[], work: BlockWork[], trimTask: number = 0): void {
  let count = 0, cursor = node.firstChild;
  while (cursor !== null) { count++; cursor = cursor.next; }
  cursor = node.lastChild;
  let ordinal = (Number.isSafeInteger(node.listStart) ? node.listStart : 1) + count - 1;
  while (cursor !== null) {
    work.push({ node: cursor, target, trimTask: cursor === node.firstChild ? trimTask : 0, ordinal });
    ordinal--; cursor = cursor.prev;
  }
}

// Called only by explicit "Markdown long post", never while scrolling/building
// a bubble. CommonMark handles escaped/nested inline syntax; containers and TD
// construction are iterative. Leaf source retained by our parser patch enables
// GFM tables/tasks without rescanning an ancestor's entire descendant document.
export function parseMarkdownRichDraft(raw: string): MarkdownRichDraft {
  const parser = new CommonMarkParser({ smart: false }), document = parser.parse(raw);
  const blocks: TdObject[] = [], media: MarkdownRichMedia[] = [], work: BlockWork[] = [];
  childrenWork(document, blocks, work);
  while (work.length > 0) {
    const current = work.pop()!, node = current.node, target = current.target;
    if (node.type === 'paragraph' || node.type === 'heading') {
      const source = node.markdownSource ?? '';
      const images: TdObject[] = [];
      const table = current.trimTask === 0 && node.type === 'paragraph' ? tableOf(parser, source, media, images) : null;
      if (table !== null) { target.push(table); for (const image of images) { target.push(image); } }
      else { appendInlineBlocks(current.trimTask > 0 ? inlineMarkdown(parser, source.substring(current.trimTask)) : node,
        target, media, node.type === 'heading' ? Math.max(1, Math.min(6, node.level)) : 0); }
    } else if (node.type === 'list') {
      const items: TdObject[] = [];
      const list = td('inputPageBlockList'); list['items'] = items; target.push(list); childrenWork(node, items, work);
    } else if (node.type === 'item') {
      const body: TdObject[] = [], source = node.firstChild?.type === 'paragraph' ? node.firstChild.markdownSource ?? '' : '';
      const task = source.match(/^\[([ xX])\][ \t]+/), ordered = node.parent?.listType === 'ordered';
      const item = td('inputPageBlockListItem'); item['blocks'] = body; item['has_checkbox'] = task !== null;
      item['is_checked'] = task !== null && task[1].toLowerCase() === 'x';
      item['value'] = ordered ? current.ordinal : 0; item['type'] = ordered ? '1' : ''; target.push(item);
      childrenWork(node, body, work, task?.[0].length ?? 0);
    } else if (node.type === 'block_quote') {
      const body: TdObject[] = [];
      const quote = td('inputPageBlockBlockQuote'); quote['blocks'] = body; target.push(quote); childrenWork(node, body, work);
    } else if (node.type === 'code_block') {
      const code = textBlock('inputPageBlockPreformatted', plain(node.literal ?? ''));
      code['language'] = (node.info ?? '').split(/[ \t]+/, 1)[0]; target.push(code);
    } else if (node.type === 'thematic_break') { target.push(td('inputPageBlockDivider')); }
    else if (node.type === 'html_block') { target.push(textBlock('inputPageBlockParagraph', plain(node.literal ?? ''))); }
    else if (node.firstChild !== null) { childrenWork(node, target, work); }
    else if (node.literal !== null) { target.push(textBlock('inputPageBlockParagraph', plain(node.literal))); }
  }
  const source = td('richMessageSourceBlocks'); source['blocks'] = blocks;
  const message = td('inputRichMessage'); message['source'] = source;
  message['is_rtl'] = drawnFirstStrongRtl(raw); message['detect_automatic_blocks'] = true;
  const content = td('inputMessageRichMessage'); content['message'] = message; content['clear_draft'] = true;
  const draft: MarkdownRichDraft = { content, media }; return draft;
}

function bindMediaSlots(draft: MarkdownRichDraft): void {
  // TaskPool/JSON boundaries need not preserve duplicate object references
  // between content and the media sidecar. Rebind once in document order,
  // without storing a depth-long path for every image or rescanning per image.
  const slots: TdObject[] = [], work: Object[] = [draft.content];
  while (work.length > 0) {
    const value = work.pop();
    if (value === null || value === undefined || typeof value !== 'object') { continue; }
    if (Array.isArray(value)) {
      const items = value as Object[];
      for (let i: number = items.length - 1; i >= 0; i--) { work.push(items[i]); }
      continue;
    }
    const node = value as TdObject;
    if (node['@type'] === 'inputPageBlockPhoto' || node['@type'] === 'inputPageBlockAnimation') { slots.push(node); continue; }
    const keys = Object.keys(node);
    for (let i: number = keys.length - 1; i >= 0; i--) { work.push(node[keys[i]]); }
  }
  if (slots.length !== draft.media.length) { throw new Error('Markdown media ownership mismatch'); }
  for (let i: number = 0; i < slots.length; i++) { draft.media[i].block = slots[i]; }
}

// One request per distinct URL; four workers by default, no Promise per queued
// image and no sequential body walks per result. Nothing is published until all
// images resolve. Failure propagates so the existing composer retains draft.
export async function resolveMarkdownRichMedia(draft: MarkdownRichDraft, resolver: MarkdownImageResolver,
  concurrency: number = 4): Promise<TdObject> {
  bindMediaSlots(draft);
  const byUrl: Map<string, MarkdownRichMedia[]> = new Map();
  for (const item of draft.media) {
    const group = byUrl.get(item.url);
    if (group !== undefined) { group.push(item); } else { byUrl.set(item.url, [item]); }
  }
  const groups: MarkdownRichMedia[][] = [];
  for (const group of byUrl.values()) { groups.push(group); }
  let cursor = 0, failed = false;
  const failures: Error[] = [];
  const worker = async (): Promise<void> => {
    while (!failed && cursor < groups.length) {
      const items = groups[cursor++];
      try {
      const result = await resolver.resolve(items[0].url);
      if (!Number.isSafeInteger(result.width) || !Number.isSafeInteger(result.height) || result.width <= 0 || result.height <= 0 || result.width > 2147483647 || result.height > 2147483647 ||
        (result.file['@type'] !== 'inputFileLocal' && result.file['@type'] !== 'inputFileId' && result.file['@type'] !== 'inputFileRemote')) {
        throw new Error('Invalid Markdown image');
      }
      if (result.animation === true && result.duration !== undefined && (!Number.isFinite(result.duration) || result.duration < 0 || result.duration > 2147483647)) {
        throw new Error('Invalid Markdown animation duration');
      }
      if ((result.file['@type'] === 'inputFileLocal' && (typeof result.file['path'] !== 'string' || result.file['path'] === '')) ||
        (result.file['@type'] === 'inputFileId' && (!Number.isSafeInteger(result.file['id'] as number) || (result.file['id'] as number) <= 0)) ||
        (result.file['@type'] === 'inputFileRemote' && (typeof result.file['id'] !== 'string' || result.file['id'] === '' || imageLink(result.file['id'] as string)))) {
        throw new Error('Invalid Markdown image file');
      }
      const photo = td('inputPhoto'); photo['photo'] = result.file; photo['width'] = Math.round(result.width);
      photo['height'] = Math.round(result.height); photo['added_sticker_file_ids'] = [];
      for (const item of items) {
        if (result.animation === true) {
          item.block['@type'] = 'inputPageBlockAnimation';
          const animation = td('inputAnimation'); animation['animation'] = result.file;
          animation['width'] = result.width; animation['height'] = result.height;
          animation['duration'] = Math.max(0, Math.floor(result.duration ?? 0)); animation['added_sticker_file_ids'] = [];
          item.block['animation'] = animation;
        } else { item.block['photo'] = photo; }
      }
      } catch (error) { failed = true; if (failures.length === 0) { failures.push(error as Error); } }
    }
  };
  const workers: Promise<void>[] = [];
  const limit = Number.isFinite(concurrency) ? Math.min(8, Math.max(1, Math.floor(concurrency))) : 4;
  for (let i: number = 0; i < Math.min(groups.length, limit); i++) { workers.push(worker()); }
  // All active downloads settle before the caller disposes their local files.
  await Promise.all(workers);
  if (failures.length > 0) { throw new Error(failures[0].message); }
  return markdownRichInput(draft);
}

export function markdownRichInput(draft: MarkdownRichDraft): TdObject {
  for (const item of draft.media) {
    if (item.block['@type'] === 'inputPageBlockAnimation' ? item.block['animation'] === undefined : item.block['photo'] === undefined) {
      throw new Error('Markdown images are not resolved');
    }
  }
  return draft.content;
}
