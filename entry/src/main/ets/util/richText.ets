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

function isLink(t: string): boolean {
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

function styleAt(pos: number, ents: Ent[]): RichRun {
  let bold = false;
  let italic = false;
  let underline = false;
  let strike = false;
  let code = false;
  let spoiler = false;
  let customEmojiId = '';
  let link = false;
  for (const e of ents) {
    if (isBlock(e.type)) {
      continue;
    }
    if (pos >= e.offset && pos < e.offset + e.length) {
      if (e.type === 'textEntityTypeBold') {
        bold = true;
      } else if (e.type === 'textEntityTypeItalic') {
        italic = true;
      } else if (e.type === 'textEntityTypeUnderline') {
        underline = true;
      } else if (e.type === 'textEntityTypeStrikethrough') {
        strike = true;
      } else if (e.type === 'textEntityTypeCode') {
        code = true;
      } else if (e.type === 'textEntityTypeSpoiler') {
        spoiler = true;
      } else if (e.type === 'textEntityTypeCustomEmoji') {
        customEmojiId = e.customEmojiId;
      } else if (isLink(e.type)) {
        link = true;
      }
    }
  }
  return {
    offset: pos,
    text: '',
    bold,
    italic,
    underline,
    strike,
    code,
    spoiler,
    customEmojiId,
    link,
    url: ''
  };
}

// Resolve the tap target for a run at `pos`. Use the FULL entity range rather
// than the current run: overlapping bold/italic boundaries can split one URL
// into several visual runs, but every piece must still open the complete URL.
// '' means the run is styled as a link but has no openable target.
function linkTargetFor(pos: number, text: string, ents: Ent[]): string {
  for (const e of ents) {
    if (isBlock(e.type) || !isLink(e.type)) {
      continue;
    }
    if (pos >= e.offset && pos < e.offset + e.length) {
      const entityText = text.substring(e.offset, e.offset + e.length);
      if (e.type === 'textEntityTypeTextUrl') {
        return e.url;
      }
      if (e.type === 'textEntityTypeUrl') {
        return entityText;
      }
      if (e.type === 'textEntityTypeMention') {
        return `https://t.me/${entityText.replace('@', '')}`;
      }
      if (e.type === 'textEntityTypeMentionName') {
        return e.userId > 0 ? `tg://user?id=${e.userId}` : '';
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
      // Pseudo-scheme: the chat page turns hashtag taps into an in-chat search.
      if (e.type === 'textEntityTypeHashtag' || e.type === 'textEntityTypeCashtag') {
        return `tg-hashtag:${entityText}`;
      }
      if (e.type === 'textEntityTypeFallbackUrl') {
        return e.url;
      }
      return '';
    }
  }
  return '';
}

// Split [start,end) into runs at inline-entity boundaries; style is constant
// within each run.
function buildRuns(text: string, start: number, end: number, ents: Ent[]): RichRun[] {
  const bounds: number[] = [start, end];
  for (const e of ents) {
    if (isBlock(e.type)) {
      continue;
    }
    const s = e.offset;
    const en = e.offset + e.length;
    if (s > start && s < end) {
      bounds.push(s);
    }
    if (en > start && en < end) {
      bounds.push(en);
    }
  }
  bounds.sort((a: number, b: number): number => a - b);
  const uniq: number[] = [];
  for (let k = 0; k < bounds.length; k++) {
    if (k === 0 || bounds[k] !== bounds[k - 1]) {
      uniq.push(bounds[k]);
    }
  }
  const runs: RichRun[] = [];
  for (let k = 0; k < uniq.length - 1; k++) {
    const s = uniq[k];
    const en = uniq[k + 1];
    if (en <= s) {
      continue;
    }
    const run = styleAt(s, ents);
    run.text = text.substring(s, en);
    if (run.link) {
      run.url = linkTargetFor(s, text, ents);
    }
    if (run.text.length > 0) {
      runs.push(run);
    }
  }
  return runs;
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

// Parse a TDLib formattedText (text + entities) into renderable segments.
// Results are memoized; callers must treat the returned segments as read-only.
export function parseFormattedText(text: string, entities: TdObject[]): RichSegment[] {
  const hit = parseCache.get(entities);
  if (hit !== undefined && hit.text === text) {
    return hit.segments;
  }
  const segments = parseFormattedTextUncached(text, entities);
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
  const segments: RichSegment[] = [];
  const n = text.length;
  let cursor = 0;
  for (const b of normalizedBlocks) {
    const bStart = Math.max(0, b.offset);
    const bEnd = Math.min(n, b.offset + b.length);
    if (bStart > cursor) {
      const runs = trimBoundaryBreaks(buildRuns(text, cursor, bStart, ents));
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
      ? trimBoundaryBreaks(buildRuns(text, bStart, bEnd, ents)) : [];
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
      ? trimBoundaryBreaks(buildRuns(text, cursor, n, ents))
      : buildRuns(text, cursor, n, ents);
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
