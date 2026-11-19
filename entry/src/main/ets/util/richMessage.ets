import { TdObject } from '../tdkit/TdTypes';

// Preview/search/copy text for immutable messageRichMessage snapshots. Block
// layout remains with DrawnStructuredSource; this path must also tolerate the
// same deep documents before the drawn compiler is reached.
export interface FlatText { text: string; entities: TdObject[]; }
interface FlatEntity { start: number; end: number; type: string; url: string; customEmojiId: string; }
interface FlatFrame {
  kind: string;
  node?: TdObject;
  nodes?: TdObject[];
  rows?: TdObject[][];
  index?: number;
  column?: number;
  started?: boolean;
  start?: number;
  url?: string;
  entity?: FlatEntity;
  text?: string;
  bold?: boolean;
}
const STYLE_ENTITY: ReadonlyMap<string, string> = new Map<string, string>([
  ['richTextBold', 'textEntityTypeBold'], ['richTextItalic', 'textEntityTypeItalic'],
  ['richTextUnderline', 'textEntityTypeUnderline'], ['richTextStrikethrough', 'textEntityTypeStrikethrough'],
  ['richTextFixed', 'textEntityTypeCode'], ['richTextMarked', 'textEntityTypeUnderline'],
  ['richTextUrl', 'textEntityTypeTextUrl'], ['richTextEmailAddress', 'textEntityTypeEmailAddress'],
  ['richTextPhoneNumber', 'textEntityTypePhoneNumber'], ['richTextSpoiler', 'textEntityTypeSpoiler']
]);
const HEADING_BLOCKS: ReadonlySet<string> = new Set<string>([
  'pageBlockTitle', 'pageBlockSubtitle', 'pageBlockHeader', 'pageBlockSubheader', 'pageBlockSectionHeading', 'pageBlockKicker'
]);
const flatSnapshots: WeakMap<TdObject, FlatText> = new WeakMap<TdObject, FlatText>();

function entityAt(value: FlatEntity): TdObject {
  const type: TdObject = { '@type': value.type };
  if (value.url !== '') { type['url'] = value.url; }
  if (value.customEmojiId !== '') { type['custom_emoji_id'] = value.customEmojiId; }
  const entity: Record<string, Object> = {};
  entity['@type'] = 'textEntity'; entity['offset'] = value.start;
  entity['length'] = value.end - value.start; entity['type'] = type;
  return entity as TdObject;
}
function nodesOf(value: Object | undefined): TdObject[] { return Array.isArray(value) ? value as TdObject[] : []; }

// Only captions use this optional first-content probe, at most once per rich
// subtree occurrence. It prevents empty captions adding extra line breaks;
// actual text/entity traversal is still one continuation stack, never recursive.
interface RichProbeFrame { value: Object; leaving: boolean; }
function hasRichText(value: Object | undefined): boolean {
  const pending: RichProbeFrame[] = value === undefined || value === null ? [] : [{ value, leaving: false }];
  const active: Set<Object> = new Set<Object>(), finished: Set<Object> = new Set<Object>();
  while (pending.length > 0) {
    const frame = pending.pop()!, item = frame.value;
    if (frame.leaving) { active.delete(item); finished.add(item); continue; }
    if (typeof item === 'string') { if (item.length > 0) { return true; } continue; }
    if (item === null || finished.has(item)) { continue; }
    // The actual walk rejects the cycle atomically. Do not hide it by treating
    // an empty cyclic caption as an ordinary absent caption during this probe.
    if (active.has(item)) { return true; }
    active.add(item); pending.push({ value: item, leaving: true });
    const node = item as TdObject, type = node['@type'];
    if (type === 'richTextCustomEmoji') {
      const alt = node['alternative_text']; if (typeof alt === 'string' && alt.length > 0) { return true; }
    }
    if (type === 'richTexts') {
      const children = nodesOf(node['texts']);
      for (let i = children.length - 1; i >= 0; i--) { pending.push({ value: children[i], leaving: false }); }
    } else if (node['text'] !== undefined) { pending.push({ value: node['text'], leaving: false }); }
  }
  return false;
}

class RichMessageFlattener {
  private output: string[] = [];
  private offset: number = 0;
  private frames: FlatFrame[] = [];
  private active: Set<TdObject> = new Set<TdObject>();
  private entities: Map<number, FlatEntity[]> = new Map<number, FlatEntity[]>();
  private valid: boolean = true;

  flatten(blocks: TdObject[]): FlatText {
    this.frames.push({ kind: 'blocks', nodes: blocks, index: 0 });
    while (this.valid && this.frames.length > 0) {
      const frame = this.frames.pop()!;
      if (frame.kind === 'leave') { this.active.delete(frame.node!); }
      else if (frame.kind === 'end') { frame.entity!.end = this.offset; }
      else if (frame.kind === 'literal') { this.append(frame.text ?? ''); }
      else if (frame.kind === 'blocks' || frame.kind === 'rich-list' || frame.kind === 'list-items') { this.sequence(frame); }
      else if (frame.kind === 'table') { this.table(frame); }
      else if (frame.kind === 'section') {
        if (hasRichText(frame.node)) {
          if (this.offset > (frame.start ?? 0)) { this.append('\n'); }
          this.rich(frame.node, frame.url ?? '', frame.bold === true);
        }
      } else if (frame.kind === 'rich') { this.appendRich(frame.node!, frame.url ?? '', frame.bold === true); }
      else if (frame.kind === 'block') { this.appendBlock(frame.node!); }
    }
    if (!this.valid) { return { text: '', entities: [] }; }
    const result: TdObject[] = [];
    // Starts are inserted in monotonically increasing output order. Equal-start
    // intervals are nested, so ends already descend. Only equal-range groups
    // need reversing to preserve the former postorder+stable-sort tie order.
    this.entities.forEach((values: FlatEntity[]): void => {
      const visible: FlatEntity[] = [];
      for (const entity of values) { if (entity.end > entity.start) { visible.push(entity); } }
      let at = 0;
      while (at < visible.length) {
        let end = at + 1;
        while (end < visible.length && visible[end].end === visible[at].end) { end++; }
        for (let i = end - 1; i >= at; i--) { result.push(entityAt(visible[i])); }
        at = end;
      }
    });
    return { text: this.output.join(''), entities: result };
  }
  private append(text: string): void { if (text !== '') { this.output.push(text); this.offset += text.length; } }
  private enter(node: TdObject): boolean {
    if (node === null || typeof node !== 'object' || this.active.has(node)) { this.valid = false; return false; }
    this.active.add(node); this.frames.push({ kind: 'leave', node }); return true;
  }
  private begin(type: string, url: string = '', customEmojiId: string = ''): FlatEntity {
    const value: FlatEntity = { type, url, customEmojiId, start: this.offset, end: this.offset };
    let bucket = this.entities.get(this.offset);
    if (bucket === undefined) { bucket = []; this.entities.set(this.offset, bucket); }
    bucket.push(value); return value;
  }
  private rich(value: Object | undefined, url: string = '', bold: boolean = false): void {
    if (value === undefined || value === null) { return; }
    if (typeof value === 'string') { this.frames.push({ kind: 'literal', text: value }); }
    else { this.frames.push({ kind: 'rich', node: value as TdObject, url, bold }); }
  }
  private blocks(value: Object | undefined): void { this.frames.push({ kind: 'blocks', nodes: nodesOf(value), index: 0 }); }
  private section(value: Object | undefined, start: number, bold: boolean = false): void {
    if (value === undefined || value === null) { return; }
    if (typeof value === 'string') {
      if (value !== '') {
        const node: Record<string, Object> = {};
        node['@type'] = 'richTextPlain'; node['text'] = value;
        this.frames.push({ kind: 'section', node: node as TdObject, start, bold });
      }
    } else { this.frames.push({ kind: 'section', node: value as TdObject, start, bold }); }
  }
  private caption(value: Object | undefined, start: number): void {
    if (value === undefined || value === null) { return; }
    if (typeof value === 'string') { this.section(value, start); return; }
    const caption = value as TdObject, type = (caption['@type'] as string | undefined) ?? '';
    this.section(caption['credit'], start);
    this.section(type.startsWith('richText') ? caption : caption['text'] ?? caption, start);
  }
  private sequence(frame: FlatFrame): void {
    const nodes = frame.nodes ?? [], index = frame.index ?? 0;
    if (index >= nodes.length) { return; }
    const node = nodes[index]; frame.index = index + 1; this.frames.push(frame);
    if (frame.kind === 'list-items') {
      if (!this.enter(node)) { return; }
      const children = nodesOf(node['blocks'] ?? node['page_blocks']);
      if (children.length > 0) { this.blocks(children); }
      else if (node['text'] !== undefined) {
        if (this.offset > 0) { this.append('\n'); }
        this.rich(node['text']);
      }
    } else { this.frames.push({ kind: frame.kind === 'blocks' ? 'block' : 'rich', node, url: frame.url ?? '' }); }
  }
  private appendRich(node: TdObject, url: string, bold: boolean): void {
    if (!this.enter(node)) { return; }
    const type = (node['@type'] as string | undefined) ?? '';
    if (bold) { this.frames.push({ kind: 'end', entity: this.begin('textEntityTypeBold') }); }
    if (type === 'richTextPlain') {
      const text = node['text'];
      if (text !== undefined && typeof text !== 'string') { this.valid = false; return; }
      this.append((text as string | undefined) ?? '');
    } else if (type === 'richTexts') {
      this.frames.push({ kind: 'rich-list', nodes: nodesOf(node['texts']), index: 0, url });
    } else if (type === 'richTextCustomEmoji') {
      const alternative = node['alternative_text'];
      if (alternative !== undefined && typeof alternative !== 'string') { this.valid = false; return; }
      const alt = (alternative as string | undefined) ?? '';
      const rawId = node['custom_emoji_id'];
      const id = typeof rawId === 'string' || typeof rawId === 'number' ? `${rawId}` : '';
      if (alt !== '' && id !== '' && id !== '0') {
        const entity = this.begin('textEntityTypeCustomEmoji', '', id); this.append(alt); entity.end = this.offset;
      } else { this.append(alt); }
    } else {
      const mapped = STYLE_ENTITY.get(type);
      const nextUrl = type === 'richTextUrl' ? (node['url'] as string | undefined) ?? '' : url;
      if (mapped !== undefined) { this.frames.push({ kind: 'end', entity: this.begin(mapped, mapped === 'textEntityTypeTextUrl' ? nextUrl : '') }); }
      this.rich(node['text'], nextUrl);
    }
  }
  private table(frame: FlatFrame): void {
    const rows = frame.rows ?? [], row = frame.index ?? 0, column = frame.column ?? 0;
    if (row >= rows.length) { return; }
    if (!frame.started) { frame.started = true; if (this.offset > (frame.start ?? 0)) { this.append('\n'); } }
    const cells = rows[row];
    if (!Array.isArray(cells)) { this.valid = false; return; }
    if (column >= cells.length) {
      if (row + 1 < rows.length) { this.append('\n'); }
      frame.index = row + 1; frame.column = 0; this.frames.push(frame); return;
    }
    if (column > 0) { this.append('\t'); }
    const cell = cells[column]; frame.column = column + 1; this.frames.push(frame);
    if (cell === null || typeof cell !== 'object') { this.valid = false; return; }
    this.rich(cell['text'], '', cell['is_header'] === true);
  }
  private appendBlock(node: TdObject): void {
    if (!this.enter(node)) { return; }
    const type = (node['@type'] as string | undefined) ?? '';
    // Covers are transparent containers. Legacy concrete blocks still add the
    // exact same leading separator, including empty/unknown concrete blocks.
    if (!(type === 'pageBlockCover' && node['cover'] !== undefined) && this.offset > 0) { this.append('\n'); }
    const start = this.offset;
    if (type === 'pageBlockBlockQuote' || type === 'pageBlockPullQuote') {
      this.section(node['credit'] ?? node['caption'], start);
      this.frames.push({ kind: 'end', entity: this.begin('textEntityTypeBlockQuote') });
      const children = nodesOf(node['blocks'] ?? node['page_blocks']);
      if (children.length > 0) { this.blocks(children); } else { this.rich(node['text']); }
    } else if (type === 'pageBlockPreformatted') {
      this.frames.push({ kind: 'end', entity: this.begin('textEntityTypePre') }); this.rich(node['text']);
    } else if (type === 'pageBlockList') {
      this.frames.push({ kind: 'list-items', nodes: nodesOf(node['items']), index: 0 });
    } else if (type === 'pageBlockCover') {
      if (node['cover'] !== undefined) { this.frames.push({ kind: 'block', node: node['cover'] as TdObject }); }
      else { this.rich(node['text']); }
    } else if (type === 'pageBlockDetails') {
      this.blocks(node['blocks'] ?? node['page_blocks']); this.rich(node['title'] ?? node['header'] ?? node['text']);
    } else if (type === 'pageBlockEmbeddedPost') {
      this.caption(node['caption'], start); this.blocks(node['page_blocks'] ?? node['blocks']);
      this.section(node['author'], start); this.rich(node['text']);
    } else if (type === 'pageBlockTable') {
      this.caption(node['caption'], start);
      this.frames.push({ kind: 'table', rows: (node['cells'] as TdObject[][] | undefined) ?? [], index: 0, column: 0, start });
      this.rich(node['text']);
    } else if (type === 'pageBlockCollage' || type === 'pageBlockSlideshow') {
      this.caption(node['caption'], start); this.blocks(node['page_blocks'] ?? node['items']); this.rich(node['text']);
    } else if (type === 'pageBlockButtonRow') {
      const buttons = nodesOf(node['buttons']);
      for (let i = buttons.length - 1; i >= 0; i--) { this.section(buttons[i]['text'], start); }
      this.rich(node['text']);
    } else {
      this.caption(node['caption'], start);
      if (HEADING_BLOCKS.has(type)) {
        this.frames.push({ kind: 'end', entity: this.begin('textEntityTypeBold') }); this.rich(node['text'] ?? node['title']);
      } else { this.rich(node['text']); }
    }
  }
}

// Traversal, UTF-16 offsets, output joining and entity ordering are O(N+T+E).
// True cycles reject atomically; legitimate depth and task/block count do not.
export function flattenRichMessage(content: TdObject): FlatText {
  const message = content['message'] as TdObject | undefined;
  if (message === undefined || message === null || typeof message !== 'object') { return { text: '', entities: [] }; }
  const hit = flatSnapshots.get(message); if (hit !== undefined) { return hit; }
  const result = new RichMessageFlattener().flatten(nodesOf(message['blocks']));
  flatSnapshots.set(message, result); return result;
}
