import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { TdClient } from '../tdkit/TdClient';

// Only explicit composer sends/editing use these helpers. Bot commands, reply
// keyboard text and received plain messages keep their original byte content.
export type ComposeMarkdownClient = TdClient;

export function composeFormattedText(text: string, entities: TdObject[] = []): TdObject {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = text; formatted['entities'] = entities;
  return formatted;
}

// A single scan, no substring-per-character or repeated delimiter searches.
// This is admission only: TDLib owns matching, nesting, escaping and UTF-16
// offset remapping (including existing name mentions/custom emoji entities).
export function hasComposeMarkdown(text: string): boolean {
  for (let i: number = 0; i < text.length; i++) {
    const c = text.charAt(i);
    if (c === '`' || c === '[') { return true; }
    if ((c === '*' || c === '_' || c === '~' || c === '|') && text.charAt(i + 1) === c) { return true; }
  }
  return false;
}

function isSplitSurrogate(text: string, offset: number): boolean {
  if (offset <= 0 || offset >= text.length) { return false; }
  const a = text.charCodeAt(offset - 1), b = text.charCodeAt(offset);
  return a >= 0xD800 && a <= 0xDBFF && b >= 0xDC00 && b <= 0xDFFF;
}

// Reject an invalid native result instead of silently publishing partial text
// or stripping entities. The caller's existing send-error path retains draft.
export function checkedComposeFormattedText(value: TdObject): TdObject {
  if (value['@type'] !== 'formattedText' || typeof value['text'] !== 'string' || !Array.isArray(value['entities'])) {
    throw new Error('Invalid formatted text returned by TDLib');
  }
  const text = value['text'] as string, entities = value['entities'] as TdObject[];
  for (const entity of entities) {
    const offset = entity['offset'] as number, length = entity['length'] as number;
    const type = entity['type'] as TdObject | undefined;
    if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) || offset < 0 || length <= 0 ||
      offset > text.length - length || type === undefined || typeof type['@type'] !== 'string' ||
      isSplitSurrogate(text, offset) || isSplitSurrogate(text, offset + length)) {
      throw new Error('Invalid formatted text entity returned by TDLib');
    }
  }
  return value;
}

export async function parseComposeMarkdown(client: ComposeMarkdownClient, text: string,
  entities: TdObject[] = []): Promise<TdObject> {
  const formatted = composeFormattedText(text, entities);
  checkedComposeFormattedText(formatted);
  if (!hasComposeMarkdown(text)) { return formatted; }
  const request: TdRequest = { '@type': 'parseMarkdown' };
  request['text'] = formatted;
  return checkedComposeFormattedText(await client.send(request));
}

export async function markdownForEditing(client: ComposeMarkdownClient, text: string,
  entities: TdObject[] = []): Promise<TdObject> {
  const formatted = composeFormattedText(text, entities);
  checkedComposeFormattedText(formatted);
  if (entities.length === 0) { return formatted; }
  const request: TdRequest = { '@type': 'getMarkdownText' };
  request['text'] = formatted;
  // getMarkdownText keeps entities which have no unambiguous Markdown form.
  // Return the whole formattedText, not only .text, so mention identity survives.
  return checkedComposeFormattedText(await client.send(request));
}

function isEditableStyle(entity: TdObject): boolean {
  const type = entity['type'] as TdObject;
  const kind = type['@type'] as string;
  return kind === 'textEntityTypeBold' || kind === 'textEntityTypeItalic' || kind === 'textEntityTypeUnderline' ||
    kind === 'textEntityTypeStrikethrough' || kind === 'textEntityTypeSpoiler' || kind === 'textEntityTypeCode' ||
    kind === 'textEntityTypePre' || kind === 'textEntityTypePreCode' || kind === 'textEntityTypeBlockQuote' ||
    kind === 'textEntityTypeExpandableBlockQuote';
}

// Incremental editor changes are one replaced UTF-16 interval. Compare common
// prefix/suffix once, then move each preserved entity once: O(T + E), O(E).
// Name mentions/custom emoji/semantic links lose identity if their own label is
// edited; styling can expand/shrink with the changed text. Call per onChange.
export function remapComposeEntities(before: string, after: string, entities: TdObject[]): TdObject[] {
  if (before === after || entities.length === 0) { return entities; }
  let prefix: number = 0;
  const shortest = Math.min(before.length, after.length);
  while (prefix < shortest && before.charCodeAt(prefix) === after.charCodeAt(prefix)) { prefix++; }
  if (isSplitSurrogate(before, prefix) || isSplitSurrogate(after, prefix)) { prefix--; }
  let suffix: number = 0;
  while (suffix < before.length - prefix && suffix < after.length - prefix &&
    before.charCodeAt(before.length - suffix - 1) === after.charCodeAt(after.length - suffix - 1)) { suffix++; }
  if (isSplitSurrogate(before, before.length - suffix) || isSplitSurrogate(after, after.length - suffix)) { suffix--; }
  const oldEnd = before.length - suffix, newEnd = after.length - suffix, delta = newEnd - oldEnd;
  const result: TdObject[] = [];
  for (const entity of entities) {
    const offset = entity['offset'] as number, length = entity['length'] as number, end = offset + length;
    if (end <= prefix) { result.push(entity); continue; }
    if (offset >= oldEnd) {
      const moved: TdObject = {};
      moved['offset'] = offset + delta; moved['length'] = length; moved['type'] = entity['type'];
      result.push(moved); continue;
    }
    if (!isEditableStyle(entity)) { continue; }
    const start = Math.min(offset, prefix), finish = end >= oldEnd ? end + delta : newEnd;
    if (finish > start) {
      const updated: TdObject = {};
      updated['offset'] = start; updated['length'] = finish - start; updated['type'] = entity['type'];
      result.push(updated);
    }
  }
  return result;
}
