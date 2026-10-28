import { TdObject } from '../tdkit/TdTypes';

// A styled inline run of text (part of a normal text segment).
export interface RichRun {
  offset: number;
  text: string;
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strike: boolean;
  code: boolean;
  spoiler: boolean;
  customEmojiId: string;
  link: boolean; // link / mention / hashtag / command → colored
  url: string;   // tap target ('' = not openable); drives onClick
}

// A block of a message: inline styled text, a pre/code block, or a blockquote.
export interface RichSegment {
  kind: string;    // 'text' | 'pre' | 'quote'
  runs: RichRun[]; // for kind === 'text' | 'quote' (quotes keep their inline links)
  text: string;    // raw text for kind === 'pre' | 'quote'
  offset: number;
  expandable: boolean;
  language: string;
  isLast: boolean;
}

interface Ent {
  offset: number;
  length: number;
  type: string;
  url: string;    // for textEntityTypeTextUrl
  userId: number; // for textEntityTypeMentionName
  customEmojiId: string;
  language: string;
}

function isBlock(t: string): boolean {
  return t === 'textEntityTypePre' || t === 'textEntityTypePreCode'
    || t === 'textEntityTypeBlockQuote' || t === 'textEntityTypeExpandableBlockQuote';
}

// 导出给 linguisticText.ets：判定语种时要把链接类片段摘掉，那边不该再抄一份
// 类型清单——TDLib 加了新的链接实体时，两处会一起吃到。
export function isLinkEntityType(t: string): boolean {
  return t === 'textEntityTypeTextUrl' || t === 'textEntityTypeUrl'
    || t === 'textEntityTypeMention' || t === 'textEntityTypeMentionName'
    || t === 'textEntityTypeHashtag' || t === 'textEntityTypeCashtag'
    || t === 'textEntityTypeBotCommand' || t === 'textEntityTypeEmailAddress'
    || t === 'textEntityTypePhoneNumber' || t === 'textEntityTypeBankCardNumber'
    || t === 'textEntityTypeFallbackUrl';
}

const AUTO_LINK_RE: RegExp =
  /(https?:\/\/[^\s<>]+|(?:t\.me|telegram\.me|telegram\.dog)\/@?[A-Za-z0-9_+/?=&%-]+|www\.[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?:\/[^\s<>]*)?|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}|@[A-Za-z0-9_]{3,32}|#[A-Za-z0-9_\u4e00-\u9fff]+|\$[A-Za-z][A-Za-z0-9_]*)/gi;

// The overwhelmingly common chat row is one ordinary, unstyled text run.
// Let callers identify it without constructing RichSegment/RichRun arrays.
// Keep this check tied to AUTO_LINK_RE: entity-less links still need the rich
// renderer so they remain tappable.
export function isUnformattedPlainText(text: string, entities: TdObject[]): boolean {
  if (text.trim() === '' || entities.length !== 0) {
    return false;
  }
  AUTO_LINK_RE.lastIndex = 0;
  const hasAutoLink: boolean = AUTO_LINK_RE.test(text);
  AUTO_LINK_RE.lastIndex = 0;
  return !hasAutoLink;
}

function trimAutoLinkToken(token: string): string {
  let out = token;
  while (out.length > 0 && /[.,!?;:，。！？；：)\]}》」』]$/.test(out)) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

function autoLinkTarget(token: string): string {
  const lower = token.toLowerCase();
  if (token.startsWith('@')) {
    return `https://t.me/${token.substring(1)}`;
  }
  if (token.startsWith('#') || token.startsWith('$')) {
    return `tg-hashtag:${token}`;
  }
  if (token.indexOf('@') > 0 && token.indexOf('://') < 0) {
    return `mailto:${token}`;
  }
  if (lower.startsWith('t.me/') || lower.startsWith('telegram.me/') ||
    lower.startsWith('telegram.dog/') || lower.startsWith('www.')) {
    return `https://${token}`;
  }
  return token;
}

function autoLinkEntities(text: string): Ent[] {
  const out: Ent[] = [];
  AUTO_LINK_RE.lastIndex = 0;
  let match = AUTO_LINK_RE.exec(text);
  while (match !== null) {
    const token = trimAutoLinkToken(match[0]);
    if (token !== '') {
      out.push({
        offset: match.index,
        length: token.length,
        type: 'textEntityTypeFallbackUrl',
        url: autoLinkTarget(token),
        userId: 0,
        customEmojiId: '',
        language: ''
      });
    }
    match = AUTO_LINK_RE.exec(text);
  }
  return out;
}

function readEntities(text: string, entities: TdObject[]): Ent[] {
  const out: Ent[] = [];
  for (const e of entities) {
    const t = e['type'] as TdObject | undefined;
    const type = t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '';
    const url = t !== undefined ? ((t['url'] as string | undefined) ?? '') : '';
    const userId = t !== undefined ? ((t['user_id'] as number | undefined) ?? 0) : 0;
    const rawOffset = (e['offset'] as number | undefined) ?? 0;
    const rawLength = (e['length'] as number | undefined) ?? 0;
    const offset = Math.max(0, Math.min(text.length, rawOffset));
    const end = Math.max(offset, Math.min(text.length, rawOffset + rawLength));
    if (end <= offset || type === '') {
      continue;
    }
    out.push({
      offset,
      length: end - offset,
      type,
      url,
      userId,
      customEmojiId: t !== undefined ? `${t['custom_emoji_id'] ?? ''}` : '',
      language: t !== undefined ? ((t['language'] as string | undefined) ?? '') : ''
    });
  }
  // Messages composed locally or received from older TDLib builds can carry
  // plain text without URL entities. Detect links only when TDLib supplied no
  // entities at all, avoiding overlaps with authoritative formatting ranges.
  if (out.length === 0 && text !== '') {
    return autoLinkEntities(text);
  }
  return out;
}

// Resolve from the FULL entity, not a run split by overlapping formatting.
// Resolved at most once per entity while sweeping its active ranges.
function entityLinkTarget(e: Ent, text: string): string {
  if (e.type === 'textEntityTypeTextUrl' || e.type === 'textEntityTypeFallbackUrl') {
    return e.url;
  }
  if (e.type === 'textEntityTypeMentionName') {
    return e.userId > 0 ? `tg://user?id=${e.userId}` : '';
  }
  const entityText = text.substring(e.offset, e.offset + e.length);
  if (e.type === 'textEntityTypeUrl') {
    return entityText;
  }
  if (e.type === 'textEntityTypeMention') {
    return `https://t.me/${entityText.replace('@', '')}`;
  }
  if (e.type === 'textEntityTypeEmailAddress') {
    return `mailto:${entityText}`;
  }
  if (e.type === 'textEntityTypePhoneNumber') {
    return `tel:${entityText.replace(/[ \-()]/g, '')}`;
  }
  if (e.type === 'textEntityTypeBotCommand') {
    return `tg-command:${entityText}`;
  }
  if (e.type === 'textEntityTypeBankCardNumber') {
    return `tg-copy:${entityText}`;
  }
  if (e.type === 'textEntityTypeHashtag' || e.type === 'textEntityTypeCashtag') {
    return `tg-hashtag:${entityText}`;
  }
  return '';
}

// Collapse only adjacent non-interactive runs after block boundary trimming.
// Spoilers keep their offset/length reveal keys; each custom emoji keeps its own
// ImageSpan. Links also keep their original text ranges: linkTextHidesUrl uses
// that text when deciding whether a tap needs a confirmation.
function compactStyledRuns(runs: RichRun[]): void {
  if (runs.length < 2) {
    return;
  }
  let count = 1;
  for (let i = 1; i < runs.length; i++) {
    const previous = runs[count - 1];
    const next = runs[i];
    if (!previous.spoiler && !next.spoiler && !previous.link && !next.link &&
      previous.customEmojiId === '' && next.customEmojiId === '' &&
      previous.url === '' && next.url === '' &&
      previous.offset + previous.text.length === next.offset &&
      previous.bold === next.bold && previous.italic === next.italic &&
      previous.underline === next.underline && previous.strike === next.strike &&
      previous.code === next.code) {
      previous.text += next.text;
    } else {
      runs[count++] = next;
    }
  }
  runs.length = count;
}

// Each inline entity contributes two ordered events. Style counters handle
// arbitrary overlaps; priority heaps preserve TDLib array order for the first
// link and last custom emoji. Every event is consumed once across all blocks.
interface InlineEvent {
  position: number;
  entityIndex: number;
  flags: number;
  entering: boolean;
}

function inlineFlags(type: string): number {
  switch (type) {
    case 'textEntityTypeBold': return 1;
    case 'textEntityTypeItalic': return 2;
    case 'textEntityTypeUnderline': return 4;
    case 'textEntityTypeStrikethrough': return 8;
    case 'textEntityTypeCode': return 16;
    case 'textEntityTypeSpoiler': return 32;
    case 'textEntityTypeCustomEmoji': return 64;
    default: return isLinkEntityType(type) ? 128 : 0;
  }
}

// Min-heap of original indices (negated for last-entity priority). Expired
// entries are discarded lazily, at most once each; no array shifts or rescans.
class ActiveEntityHeap {
  private values: number[] = [];
  private lastWins: boolean;

  constructor(lastWins: boolean) { this.lastWins = lastWins; }

  add(index: number): void {
    const value = this.lastWins ? -index : index;
    const values = this.values;
    let child = values.length;
    values.push(value);
    while (child > 0) {
      const parent = (child - 1) >> 1;
      if (values[parent] <= value) { break; }
      values[child] = values[parent];
      child = parent;
    }
    values[child] = value;
  }

  current(active: boolean[]): number {
    const values = this.values;
    while (values.length > 0) {
      const index = this.lastWins ? -values[0] : values[0];
      if (active[index]) { return index; }
      const tail = values.pop()!;
      if (values.length === 0) { break; }
      let parent = 0;
      while (parent * 2 + 1 < values.length) {
        let child = parent * 2 + 1;
        if (child + 1 < values.length && values[child + 1] < values[child]) { child++; }
        if (values[child] >= tail) { break; }
        values[parent] = values[child];
        parent = child;
      }
      values[parent] = tail;
    }
    return -1;
  }
}

class InlineRunCursor {
  private text: string;
  private entities: Ent[];
  private events: InlineEvent[] = [];
  private nextEvent: number = 0;
  private active: boolean[] = [];
  private counts: number[] = [0, 0, 0, 0, 0, 0];
  private links: ActiveEntityHeap | null = null;
  private emojis: ActiveEntityHeap | null = null;
  private linkTargets: string[] = [];

  constructor(text: string, entities: Ent[]) {
    this.text = text;
    this.entities = entities;
    for (let i = 0; i < entities.length; i++) {
      const entity = entities[i];
      // NaN ranges never supplied boundaries or styles in the previous parser.
      if (isBlock(entity.type) || !Number.isFinite(entity.offset) || !Number.isFinite(entity.length)) {
        continue;
      }
      const flags = inlineFlags(entity.type);
      if (flags === 128 && this.links === null) { this.links = new ActiveEntityHeap(false); }
      if (flags === 64 && this.emojis === null) { this.emojis = new ActiveEntityHeap(true); }
      // Unknown entity types still create boundaries: interactive run keys
      // must not change just because their neighboring entity is unrecognized.
      this.events.push({ position: entity.offset, entityIndex: i, flags, entering: true });
      this.events.push({ position: entity.offset + entity.length, entityIndex: i, flags, entering: false });
    }
    this.events.sort((a: InlineEvent, b: InlineEvent): number => a.position - b.position);
  }

  private advanceTo(position: number): void {
    while (this.nextEvent < this.events.length && this.events[this.nextEvent].position <= position) {
      const event = this.events[this.nextEvent++];
      const flags = event.flags;
      const delta = event.entering ? 1 : -1;
      this.active[event.entityIndex] = event.entering;
      if ((flags & 1) !== 0) { this.counts[0] += delta; }
      if ((flags & 2) !== 0) { this.counts[1] += delta; }
      if ((flags & 4) !== 0) { this.counts[2] += delta; }
      if ((flags & 8) !== 0) { this.counts[3] += delta; }
      if ((flags & 16) !== 0) { this.counts[4] += delta; }
      if ((flags & 32) !== 0) { this.counts[5] += delta; }
      if (event.entering) {
        if (flags === 128) { this.links!.add(event.entityIndex); }
        if (flags === 64) { this.emojis!.add(event.entityIndex); }
      }
    }
  }

  private run(start: number, end: number): RichRun {
    const link = this.links !== null ? this.links.current(this.active) : -1;
    const emoji = this.emojis !== null ? this.emojis.current(this.active) : -1;
    let url = '';
    if (link >= 0) {
      const cached: string | undefined = this.linkTargets[link];
      if (cached !== undefined) {
        url = cached;
      } else {
        url = entityLinkTarget(this.entities[link], this.text);
        this.linkTargets[link] = url;
      }
    }
    return {
      offset: start, text: this.text.substring(start, end),
      bold: this.counts[0] > 0, italic: this.counts[1] > 0,
      underline: this.counts[2] > 0, strike: this.counts[3] > 0,
      code: this.counts[4] > 0, spoiler: this.counts[5] > 0,
      customEmojiId: emoji >= 0 ? this.entities[emoji].customEmojiId : '',
      link: link >= 0, url
    };
  }

  // Call ranges are in document order. A pre/code block can skip a range;
  // advanceTo consumes its events so inline styles resume correctly afterwards.
  runs(start: number, end: number): RichRun[] {
    const runs: RichRun[] = [];
    let position = start;
    this.advanceTo(position);
    while (position < end) {
      const next = this.nextEvent < this.events.length
        ? Math.min(end, this.events[this.nextEvent].position) : end;
      const run = this.run(position, next);
      if (run.text.length > 0) { runs.push(run); }
      position = next;
      this.advanceTo(position);
    }
    return runs;
  }
}

// TDLib commonly leaves the blank line(s) separating ordinary text from a
// quote/pre entity outside the entity range. Rendering those line breaks and
// adding the block card's own margin produces a conspicuous empty band. Keep
// line breaks inside normal paragraphs, but consume boundary-only separators
// because the block component already supplies visual spacing.
function trimBoundaryBreaks(runs: RichRun[]): RichRun[] {
  const out: RichRun[] = runs.map((run: RichRun): RichRun => ({
    text: run.text,
    offset: run.offset,
    bold: run.bold,
    italic: run.italic,
    underline: run.underline,
    strike: run.strike,
    code: run.code,
    spoiler: run.spoiler,
    customEmojiId: run.customEmojiId,
    link: run.link,
    url: run.url
  }));
  while (out.length > 0) {
    const first: RichRun = out[0];
    const trimmed: string = first.text.replace(/^[ \t]*[\r\n]+[ \t]*/, '');
    if (trimmed === first.text) {
      break;
    }
    if (trimmed === '') {
      out.shift();
    } else {
      first.text = trimmed;
      break;
    }
  }
  while (out.length > 0) {
    const last: RichRun = out[out.length - 1];
    const trimmed: string = last.text.replace(/[ \t]*[\r\n]+[ \t]*$/, '');
    if (trimmed === last.text) {
      break;
    }
    if (trimmed === '') {
      out.pop();
    } else {
      last.text = trimmed;
      break;
    }
  }
  return out;
}

function trimBlockText(text: string): string {
  return text
    .replace(/^[ \t]*[\r\n]+[ \t]*/, '')
    .replace(/[ \t]*[\r\n]+[ \t]*$/, '');
}

interface ParseCacheEntry {
  text: string;
  segments: RichSegment[];
}

// Parse results keyed by the entities array's identity: a TDLib formattedText
// owns its entities array, so one array only ever pairs with one text (the
// text equality check covers shared empty-array constants). The bubble build
// path re-parses on every render otherwise, which shows up as scroll jank.
// WeakMap keeps a cache entry alive exactly as long as its message does.
const parseCache: WeakMap<TdObject[], ParseCacheEntry> = new WeakMap();
// Only parser-owned, read-only segments participate. An empty value marks a
// segment whose fingerprint has not been requested yet; shape-only consumers
// do not pay for hashing. Caller-created mutable segments remain uncached.
const segmentFingerprints: WeakMap<RichSegment, string> = new WeakMap();

// Parse a TDLib formattedText (text + entities) into renderable segments.
// Results are memoized; callers must treat the returned segments as read-only.
export function parseFormattedText(text: string, entities: TdObject[]): RichSegment[] {
  const hit = parseCache.get(entities);
  if (hit !== undefined && hit.text === text) {
    return hit.segments;
  }
  const segments = parseFormattedTextUncached(text, entities);
  for (const segment of segments) {
    compactStyledRuns(segment.runs);
    segmentFingerprints.set(segment, '');
  }
  parseCache.set(entities, { text, segments });
  return segments;
}

function parseFormattedTextUncached(text: string, entities: TdObject[]): RichSegment[] {
  const ents = readEntities(text, entities);
  const blocks: Ent[] = [];
  for (const e of ents) {
    if (isBlock(e.type)) {
      blocks.push(e);
    }
  }
  blocks.sort((a: Ent, b: Ent): number => a.offset - b.offset);
  const normalizedBlocks: Ent[] = [];
  let blockEnd = 0;
  for (const block of blocks) {
    const end = block.offset + block.length;
    if (end <= blockEnd) {
      continue;
    }
    if (block.offset < blockEnd) {
      block.length = end - blockEnd;
      block.offset = blockEnd;
    }
    normalizedBlocks.push(block);
    blockEnd = block.offset + block.length;
  }
  const inline = new InlineRunCursor(text, ents);
  const segments: RichSegment[] = [];
  const n = text.length;
  let cursor = 0;
  for (const b of normalizedBlocks) {
    const bStart = Math.max(0, b.offset);
    const bEnd = Math.min(n, b.offset + b.length);
    if (bStart > cursor) {
      const runs = trimBoundaryBreaks(inline.runs(cursor, bStart));
      if (runs.length > 0) {
        segments.push({
          kind: 'text', runs, text: '', offset: cursor,
          expandable: false, language: '', isLast: false
        });
      }
    }
    const kind = (b.type === 'textEntityTypeBlockQuote' || b.type === 'textEntityTypeExpandableBlockQuote')
      ? 'quote' : 'pre';
    // Quotes keep their inline runs so links/mentions inside stay tappable.
    const quoteRuns = kind === 'quote'
      ? trimBoundaryBreaks(inline.runs(bStart, bEnd)) : [];
    const blockText = trimBlockText(text.substring(bStart, bEnd));
    if (blockText !== '') {
      segments.push({
        kind,
        runs: quoteRuns,
        text: blockText,
        offset: bStart,
        expandable: b.type === 'textEntityTypeExpandableBlockQuote',
        language: b.language,
        isLast: false
      });
    }
    cursor = bEnd;
  }
  if (cursor < n) {
    const runs = normalizedBlocks.length > 0
      ? trimBoundaryBreaks(inline.runs(cursor, n))
      : inline.runs(cursor, n);
    if (runs.length > 0) {
      segments.push({
        kind: 'text', runs, text: '', offset: cursor,
        expandable: false, language: '', isLast: false
      });
    }
  }
  if (segments.length === 0 && n > 0) {
    segments.push({
      kind: 'text',
      runs: [{
        offset: 0, text, bold: false, italic: false, underline: false,
        strike: false, code: false, spoiler: false, customEmojiId: '',
        link: false, url: ''
      }],
      text: '',
      offset: 0,
      expandable: false,
      language: '',
      isLast: false
    });
  }
  if (segments.length > 0) {
    segments[segments.length - 1].isLast = true;
  }
  return segments;
}

// 消息正文里的可复制链接（真 URL：显式 textUrl 的目标、裸 URL 的原文）。
// @提及/#话题/命令等可点击实体不算——"复制链接"复制出一个 @名字没有意义。
export function messageUrls(text: string, entities: TdObject[]): string[] {
  const out: string[] = [];
  for (const e of entities) {
    const type = e['type'] as TdObject | undefined;
    const t: string = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
    if (t === 'textEntityTypeTextUrl') {
      const url: string = (type!['url'] as string | undefined) ?? '';
      if (url !== '' && out.indexOf(url) < 0) {
        out.push(url);
      }
    } else if (t === 'textEntityTypeUrl') {
      const offset: number = (e['offset'] as number | undefined) ?? 0;
      const length: number = (e['length'] as number | undefined) ?? 0;
      // TDLib 的 offset/length 是 UTF-16 码元，和 JS 的 substring 同一口径。
      const url: string = text.substring(offset, offset + length);
      if (url !== '' && out.indexOf(url) < 0) {
        out.push(url);
      }
    }
  }
  return out;
}

// 分段在 ForEach 里的键。
//
// **不能只有序号和 kind。** 原来写的是 `seg_${i}_${seg.kind}`——而 kind 只有
// 'text' | 'pre' | 'quote' 三种取值，是**类型标签，不是内容**。一个「每条都是
// 一段带话题标签的纯文本」的频道里，每条消息都算出 `seg_0_text`，逐字相同。
//
// ForEach 的契约是「键不变就复用已有组件、**不重新执行子构建函数**」。于是分段
// 那一层的构建函数不重跑，里面 `ForEach(seg.runs, …)` 的数据源还是上一条消息的
// runs——run 级的键虽然带全文（`run_${i}_${r.offset}_${r.text}`），也**根本没有
// 机会被求值**。正文因此停在上一条消息上。
//
// 而相册的图这一层已经按身份重建了（见 util/albumCellKey），两边一错开，用户
// 看到的就是**「图是这一条的、字是上一条的」**——真机实报的「文图对不上」，
// 而且只在格式一致的频道上犯，因为那种频道里每条消息的分段结构恰好都一样。
//
// 内容从哪来：'pre' 的正文在 seg.text，'text' 的在 runs 里，'quote' 两边都有。
// 全折进去。另外几个字段决定这一段画成什么形状（可展开的引用、代码块的语言、
// 是不是最后一段——它决定要不要给时间戳留位），所以一并进键。
//
// 取指纹而不是原文：键会被 ForEach 一直留着，一条几百字的说明乘以可见行数不划算；
// 解析结果已按 entities 身份复用；同一只读分段的指纹也只算一次，避免滚动
// 重绑时 ForEach 取键反复扫描文字和样式。编辑/翻译的新解析结果独立计算。
function segmentFingerprint(seg: RichSegment): string {
  const cached: string | undefined = segmentFingerprints.get(seg);
  if (cached !== undefined && cached !== '') {
    return cached;
  }
  let h: number = 5381;
  const mix = (s: string): void => {
    for (let i = 0; i < s.length; i++) {
      h = ((h << 5) + h + s.charCodeAt(i)) & 0x7fffffff;
    }
    h = ((h << 5) + h + 1) & 0x7fffffff; // 分隔符，免得 'ab'+'c' 与 'a'+'bc' 撞
  };
  mix(seg.text);
  for (const run of seg.runs) {
    mix(run.text);
    // 只混文字**不够**：同一句话这次挂 textUrl A、下次挂 textUrl B，或者这次加粗
    // 下次不加粗、这次是剧透下次不是——文字一模一样而实体不同的话，键还是会撞，
    // 分段子树不重建，点上去打开的就是**上一条消息的链接**。样式位压成一个字符
    // 一起混进去。
    mix(run.url);
    mix(run.customEmojiId);
    mix(`${run.bold ? 'b' : ''}${run.italic ? 'i' : ''}${run.underline ? 'u' : ''}` +
      `${run.strike ? 's' : ''}${run.code ? 'c' : ''}${run.spoiler ? 'p' : ''}` +
      `${run.link ? 'l' : ''}`);
  }
  const fingerprint: string = h.toString(36);
  if (cached !== undefined) {
    segmentFingerprints.set(seg, fingerprint);
  }
  return fingerprint;
}

export function richSegmentKey(index: number, seg: RichSegment): string {
  return `seg_${index}_${seg.kind}_${seg.offset}_${seg.expandable ? 'x' : '-'}` +
    `_${seg.isLast ? 'z' : '-'}_${seg.language}_${segmentFingerprint(seg)}`;
}
