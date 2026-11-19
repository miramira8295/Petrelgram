import { TdObject } from '../tdkit/TdTypes';

export interface RichMessageTask {
  id: number;
  checked: boolean;
}
interface RichTaskPath {
  owner: Object;
  key: string | number;
  parent: RichTaskPath | null;
}
interface RichInputTask {
  item: TdObject;
  path: RichTaskPath;
}
export interface RichMessageTaskIndex {
  byItem: WeakMap<TdObject, RichMessageTask>;
  tasks: Map<number, RichInputTask>;
  rawTasks: Map<number, RichInputTask>;
  inputBlocks: TdObject[] | null;
  reason: string;
  count: number;
}
const snapshots: WeakMap<TdObject[], RichMessageTaskIndex> = new WeakMap();
const richTextValidity: WeakMap<TdObject, boolean> = new WeakMap();
const RICH_TEXT_WRAPPERS: Set<string> = new Set(['richTextBold', 'richTextItalic', 'richTextUnderline',
  'richTextStrikethrough', 'richTextSpoiler', 'richTextSubscript', 'richTextSuperscript', 'richTextMarked',
  'richTextDateTime', 'richTextMention', 'richTextHashtag', 'richTextCashtag', 'richTextBankCardNumber',
  'richTextTonAddress', 'richTextBotCommand', 'richTextFixed', 'richTextMentionName', 'richTextUrl',
  'richTextEmailAddress', 'richTextPhoneNumber', 'richTextReference', 'richTextReferenceLink', 'richTextAnchorLink']);
const RICH_TEXT_LEAVES: Set<string> = new Set(['richTextPlain', 'richTextCustomEmoji', 'richTextMathematicalExpression', 'richTextAnchor']);
const USER_BUTTONS: Set<string> = new Set(['inlineKeyboardButtonTypeUrl', 'inlineKeyboardButtonTypeUser', 'inlineKeyboardButtonTypeCopyText']);

function copyRecord(source: TdObject): TdObject {
  const target: TdObject = {};
  for (const key of Object.keys(source)) { target[key] = source[key]; }
  return target;
}
interface RichTextVisit { node: TdObject; exit: boolean; }
// InputRichMessage accepts most RichText unchanged, but not Instant View icons
// or diff spans. Reject unsupported documents atomically instead of dropping
// their fields while persisting a checkbox. Native/server validation stays final.
function inputRichText(node: TdObject | undefined): boolean {
  if (node === undefined || node === null) { return true; }
  if (typeof node !== 'object') { return false; }
  const hit = richTextValidity.get(node); if (hit !== undefined) { return hit; }
  const pending: RichTextVisit[] = [{ node, exit: false }], active: Set<TdObject> = new Set();
  while (pending.length > 0) {
    const frame = pending.pop()!;
    if (frame.exit) { active.delete(frame.node); richTextValidity.set(frame.node, true); continue; }
    if (richTextValidity.get(frame.node) === true) { continue; }
    if (active.has(frame.node)) { richTextValidity.set(node, false); return false; }
    const type = frame.node['@type'] as string;
    if (RICH_TEXT_LEAVES.has(type)) { richTextValidity.set(frame.node, true); continue; }
    let children: TdObject[];
    if (type === 'richTexts') { children = (frame.node['texts'] as TdObject[] | undefined) ?? []; }
    else if (RICH_TEXT_WRAPPERS.has(type)) {
      const child = frame.node['text'] as TdObject | undefined;
      if (child === undefined || child === null) { richTextValidity.set(node, false); return false; }
      children = [child];
    } else if (type === 'richTextButton') {
      const button = frame.node['button'] as TdObject | undefined;
      if (button === undefined || !USER_BUTTONS.has(((button['type'] as TdObject | undefined)?.['@type'] as string) ?? '')) {
        richTextValidity.set(node, false); return false;
      }
      children = [button['text'] as TdObject];
    } else { richTextValidity.set(node, false); return false; }
    active.add(frame.node); pending.push({ node: frame.node, exit: true });
    for (let i = children.length - 1; i >= 0; i--) {
      if (children[i] === undefined || children[i] === null) { richTextValidity.set(node, false); return false; }
      pending.push({ node: children[i], exit: false });
    }
  }
  return true;
}
function captionValid(node: TdObject): boolean {
  const caption = node['caption'] as TdObject | undefined;
  return caption === undefined || caption === null ||
    (typeof caption === 'object' && (String(caption['@type'] ?? '').startsWith('richText') ? inputRichText(caption) :
    (inputRichText(caption['text'] as TdObject | undefined) && inputRichText(caption['credit'] as TdObject | undefined))));
}
function fileInput(file: TdObject | undefined): TdObject | null {
  const id = (file?.['id'] as number | undefined) ?? 0;
  if (!Number.isSafeInteger(id) || id <= 0) { return null; }
  const result: Record<string, Object> = {}; result['@type'] = 'inputFileId'; result['id'] = id; return result as TdObject;
}
function thumbnailInput(thumb: TdObject | undefined): TdObject | undefined {
  if (thumb === undefined || thumb === null) { return undefined; }
  const file = fileInput(thumb['file'] as TdObject | undefined);
  if (file === null) { return undefined; }
  const result: Record<string, Object> = {}; result['@type'] = 'inputThumbnail'; result['thumbnail'] = file;
  result['width'] = thumb['width'] ?? 0; result['height'] = thumb['height'] ?? 0; return result as TdObject;
}
function existingPhoto(photo: TdObject | undefined): TdObject | null {
  let selected: TdObject | undefined;
  let area: number = -1;
  for (const size of (photo?.['sizes'] as TdObject[] | undefined) ?? []) {
    const file = fileInput(size['photo'] as TdObject | undefined);
    const width = (size['width'] as number | undefined) ?? 0, height = (size['height'] as number | undefined) ?? 0;
    if (file !== null && width * height > area) { selected = size; area = width * height; }
  }
  if (selected === undefined) { return null; }
  const file = fileInput(selected['photo'] as TdObject)!;
  const result: Record<string, Object> = {}; result['@type'] = 'inputPhoto'; result['photo'] = file;
  result['added_sticker_file_ids'] = []; result['width'] = selected['width']; result['height'] = selected['height'];
  return result as TdObject;
}
function existingMedia(node: TdObject, kind: string): TdObject | null {
  const value = node[kind] as TdObject | undefined;
  if (kind === 'photo') { return existingPhoto(value); }
  const key = kind === 'voice_note' ? 'voice' : kind;
  const file = fileInput(value?.[key] as TdObject | undefined);
  if (file === null || value === undefined) { return null; }
  const input: Record<string, Object> = {};
  if (kind === 'animation') {
    input['@type'] = 'inputAnimation'; input['animation'] = file; input['added_sticker_file_ids'] = [];
    input['duration'] = value['duration'] ?? 0; input['width'] = value['width'] ?? 0; input['height'] = value['height'] ?? 0;
  } else if (kind === 'audio') {
    input['@type'] = 'inputAudio'; input['audio'] = file; input['duration'] = value['duration'] ?? 0;
    input['title'] = value['title'] ?? ''; input['performer'] = value['performer'] ?? '';
    const cover = thumbnailInput(value['album_cover_thumbnail'] as TdObject | undefined);
    if (cover !== undefined) { input['album_cover_thumbnail'] = cover; }
  } else if (kind === 'document') {
    input['@type'] = 'inputDocument'; input['document'] = file; input['disable_content_type_detection'] = true;
  } else if (kind === 'video') {
    input['@type'] = 'inputVideo'; input['video'] = file; input['duration'] = value['duration'] ?? 0;
    input['width'] = value['width'] ?? 0; input['height'] = value['height'] ?? 0;
    input['supports_streaming'] = value['supports_streaming'] === true; input['start_timestamp'] = 0; input['added_sticker_file_ids'] = [];
  } else {
    input['@type'] = 'inputVoiceNote'; input['voice_note'] = file; input['duration'] = value['duration'] ?? 0;
    input['waveform'] = value['waveform'] ?? '';
  }
  if (kind !== 'audio' && kind !== 'voice_note') {
    const thumb = thumbnailInput(value['thumbnail'] as TdObject | undefined);
    if (thumb !== undefined) { input['thumbnail'] = thumb; }
  }
  return input;
}

interface BlockJob { input: TdObject[]; output: TdObject[]; }
function convertBlocks(nodes: TdObject[], rawTasks: WeakMap<TdObject, RichMessageTask>, outputTasks: WeakMap<TdObject, number>): TdObject[] | null {
  const result: TdObject[] = [], pending: BlockJob[] = [{ input: nodes, output: result }];
  while (pending.length > 0) {
    const frame = pending.pop()!;
    for (const node of frame.input) {
      const type = node['@type'] as string;
      const out: TdObject = { '@type': `input${type.charAt(0).toUpperCase()}${type.substring(1)}` };
      const scalar: string[] = [];
      if (type === 'pageBlockSectionHeading') { scalar.push('text', 'size'); }
      else if (type === 'pageBlockParagraph') { scalar.push('text'); }
      else if (type === 'pageBlockPreformatted') { scalar.push('text', 'language'); }
      else if (type === 'pageBlockFooter') { scalar.push('footer'); }
      else if (type === 'pageBlockDivider') { /* No fields. */ }
      else if (type === 'pageBlockMathematicalExpression') { scalar.push('expression'); }
      else if (type === 'pageBlockAnchor') { scalar.push('name'); }
      else if (type === 'pageBlockList') {
        const items: TdObject[] = [];
        for (const item of (node['items'] as TdObject[] | undefined) ?? []) {
          const children: TdObject[] = [];
          const converted: Record<string, Object> = {}; converted['@type'] = 'inputPageBlockListItem'; converted['blocks'] = children;
          converted['has_checkbox'] = item['has_checkbox'] === true; converted['is_checked'] = item['is_checked'] === true;
          converted['value'] = item['value'] ?? 0; converted['type'] = item['type'] ?? '';
          const task = rawTasks.get(item); if (task !== undefined) { outputTasks.set(converted, task.id); }
          items.push(converted);
          pending.push({ input: (item['blocks'] ?? item['page_blocks'] ?? []) as TdObject[], output: children });
        }
        out['items'] = items;
      } else if (type === 'pageBlockBlockQuote' || type === 'pageBlockDetails' || type === 'pageBlockCollage' || type === 'pageBlockSlideshow') {
        scalar.push(...(type === 'pageBlockDetails' ? ['header', 'is_open'] : type === 'pageBlockBlockQuote' ? ['credit'] : ['caption']));
        const children: TdObject[] = []; out['blocks'] = children;
        pending.push({ input: (node['blocks'] ?? node['page_blocks'] ?? []) as TdObject[], output: children });
      } else if (type === 'pageBlockExpandableBlockQuote' || type === 'pageBlockPullQuote') { scalar.push('text', 'credit'); }
      else if (type === 'pageBlockAnimation' || type === 'pageBlockAudio' || type === 'pageBlockDocument' || type === 'pageBlockPhoto' || type === 'pageBlockVideo' || type === 'pageBlockVoiceNote') {
        const kind = type === 'pageBlockVoiceNote' ? 'voice_note' : type.substring(9).toLowerCase();
        const input = existingMedia(node, kind); if (input === null) { return null; }
        out[kind] = input; scalar.push('caption');
        if (kind === 'photo' || kind === 'video' || kind === 'animation') { out['has_spoiler'] = node['has_spoiler'] === true; }
      } else if (type === 'pageBlockTable') {
        scalar.push('caption', 'cells', 'is_bordered', 'is_striped', 'is_compact');
        for (const row of (node['cells'] as TdObject[][] | undefined) ?? []) {
          for (const cell of row) { if (!inputRichText(cell['text'] as TdObject | undefined)) { return null; } }
        }
      } else if (type === 'pageBlockMap') { scalar.push('location', 'zoom', 'width', 'height', 'caption'); }
      else if (type === 'pageBlockButtonRow') {
        scalar.push('buttons', 'align');
        for (const button of (node['buttons'] as TdObject[] | undefined) ?? []) {
          if (!USER_BUTTONS.has(((button['type'] as TdObject | undefined)?.['@type'] as string) ?? '') ||
            !inputRichText(button['text'] as TdObject | undefined)) { return null; }
        }
      } else { return null; }
      if (!captionValid(node)) { return null; }
      for (const key of scalar) {
        if (node[key] === undefined || node[key] === null) { continue; }
        if ((key === 'text' || key === 'footer' || key === 'header' || key === 'credit') && !inputRichText(node[key] as TdObject)) { return null; }
        out[key] = node[key];
      }
      frame.output.push(out);
    }
  }
  return result;
}
interface RawVisit { node: TdObject; exit: boolean; }
function taskNodes(nodes: TdObject[], target: RichMessageTaskIndex): boolean {
  const pending: RawVisit[] = [], active: Set<TdObject> = new Set(); let id: number = 0;
  for (let i = nodes.length - 1; i >= 0; i--) { pending.push({ node: nodes[i], exit: false }); }
  while (pending.length > 0) {
    const frame = pending.pop()!;
    if (frame.exit) { active.delete(frame.node); continue; }
    if (active.has(frame.node)) { target.reason = 'rich-task-cycle'; return false; }
    if (frame.node['has_checkbox'] === true) {
      if (target.byItem.has(frame.node)) { target.reason = 'rich-task-shared-item'; return false; }
      target.byItem.set(frame.node, { id: id++, checked: frame.node['is_checked'] === true });
    }
    active.add(frame.node); pending.push({ node: frame.node, exit: true });
    const children = (frame.node['items'] ?? frame.node['blocks'] ?? frame.node['page_blocks']) as TdObject[] | undefined;
    if (children !== undefined) {
      for (let i = children.length - 1; i >= 0; i--) { pending.push({ node: children[i], exit: false }); }
    }
    const cover = frame.node['cover'] as TdObject | undefined;
    if (cover !== undefined) { pending.push({ node: cover, exit: false }); }
  }
  target.count = id; return true;
}
interface InputVisit { nodes: TdObject[]; path: RichTaskPath | null; }
function indexInputTasks(blocks: TdObject[], taskIdOf: (node: TdObject) => number | undefined, target: Map<number, RichInputTask>): void {
  const pending: InputVisit[] = [{ nodes: blocks, path: null }];
  while (pending.length > 0) {
    const frame = pending.pop()!;
    for (let i = 0; i < frame.nodes.length; i++) {
      const node = frame.nodes[i];
      const path: RichTaskPath = { owner: frame.nodes, key: i, parent: frame.path };
      const taskId = taskIdOf(node); if (taskId !== undefined) { target.set(taskId, { item: node, path }); }
      const children = (node['items'] ?? node['blocks'] ?? node['page_blocks']) as TdObject[] | undefined;
      if (children !== undefined) {
        pending.push({ nodes: children, path: { owner: node, key: node['items'] !== undefined ? 'items' : node['blocks'] !== undefined ? 'blocks' : 'page_blocks', parent: path } });
      }
    }
  }
}

// Immutable source identity is the cache boundary. Explicit stacks and linked
// paths retain O(N) state; a deep checkbox never stores a full path per ancestor.
export function richMessageTaskIndex(nodes: TdObject[]): RichMessageTaskIndex {
  const cached = snapshots.get(nodes); if (cached !== undefined) { return cached; }
  const result: RichMessageTaskIndex = { byItem: new WeakMap(), tasks: new Map(), rawTasks: new Map(), inputBlocks: null, reason: '', count: 0 };
  snapshots.set(nodes, result);
  if (!taskNodes(nodes, result)) { return result; }
  if (result.count === 0) { result.reason = 'rich-task-none'; return result; }
  const outputTasks: WeakMap<TdObject, number> = new WeakMap();
  const blocks = convertBlocks(nodes, result.byItem, outputTasks);
  if (blocks === null) { result.reason = 'rich-task-unsupported-input'; return result; }
  result.inputBlocks = blocks;
  indexInputTasks(blocks, (node: TdObject): number | undefined => outputTasks.get(node), result.tasks);
  indexInputTasks(nodes, (node: TdObject): number | undefined => result.byItem.get(node)?.id, result.rawTasks);
  return result;
}

// A rare edit clones the changed item and its ancestor containers only. It does
// not mutate received blocks; serialization of the complete edit remains O(N),
// as required by editMessageText/inputMessageRichMessage's whole-document API.
export function createRichTaskEditContent(nodes: TdObject[], taskId: number, checked: boolean, isRtl: boolean = false): TdObject | null {
  const indexed = richMessageTaskIndex(nodes), task = indexed.tasks.get(taskId);
  if (indexed.inputBlocks === null || task === undefined) { return null; }
  const changed = changedTaskTree(task, checked);
  const source: Record<string, Object> = {}; source['@type'] = 'richMessageSourceBlocks'; source['blocks'] = changed;
  const message: Record<string, Object> = {}; message['@type'] = 'inputRichMessage'; message['source'] = source;
  message['is_rtl'] = isRtl; message['detect_automatic_blocks'] = false;
  const result: Record<string, Object> = {}; result['@type'] = 'inputMessageRichMessage'; result['message'] = message; result['clear_draft'] = false;
  return result as TdObject;
}

export function richTaskEditable(nodes: TdObject[]): boolean {
  const indexed = richMessageTaskIndex(nodes); return indexed.inputBlocks !== null && indexed.tasks.size > 0;
}

function changedTaskTree(task: RichInputTask, checked: boolean): TdObject[] {
  const item = copyRecord(task.item); item['is_checked'] = checked;
  let changed: Object = item;
  let path: RichTaskPath | null = task.path;
  while (path !== null) {
    if (typeof path.key === 'number') {
      const parent = (path.owner as Object[]).slice(); parent[path.key] = changed; changed = parent;
    } else {
      const parent = copyRecord(path.owner as TdObject); parent[path.key] = changed; changed = parent;
    }
    path = path.parent;
  }
  return changed as TdObject[];
}

// Used for an optimistic local update. The caller owns permission, in-flight
// serialization and conditional rollback; the received snapshot is untouched.
export function updateRichTaskChecked(nodes: TdObject[], taskId: number, checked: boolean): TdObject[] | null {
  const indexed = richMessageTaskIndex(nodes), task = indexed.rawTasks.get(taskId);
  if (indexed.inputBlocks === null || task === undefined) { return null; }
  return changedTaskTree(task, checked);
}
