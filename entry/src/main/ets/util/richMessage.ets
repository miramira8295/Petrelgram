import { TdObject } from '../tdkit/TdTypes';

// messageRichMessage（Telegram 的富文本长帖）走的是 Instant View 那套页面块
// 模型：blocks[] 里是 pageBlockParagraph / pageBlockSectionHeading /
// pageBlockBlockQuote…，每块的文字又是一棵 richText* 的树。
//
// 这里把整棵树摊平成 TDLib 常规的 formattedText（纯文本 + 实体偏移）。这样
// 下游一行都不用改：气泡、会话预览、搜索命中全都已经会渲染 formattedText，
// 加粗、等宽、链接也一并保住。代价是丢掉块级排版（标题层级、图片、嵌入），
// 那些要真做得另起一个 Instant View 渲染器。
//
// 不这么做的话，这类消息在界面上只有一行"暂不支持的消息"。

export interface FlatText {
  text: string;
  entities: TdObject[];
}

interface Range {
  start: number;
  end: number;
}

function entityAt(type: string, r: Range, url: string): TdObject {
  const kind: TdObject = { '@type': type };
  if (url !== '') {
    kind['url'] = url;
  }
  const e: TdObject = { '@type': 'textEntity' };
  e['offset'] = r.start;
  e['length'] = r.end - r.start;
  e['type'] = kind;
  return e;
}

// richText 树 → 追加到 out，同时记下样式实体。
// 未知的包装节点一律递归它的 text 字段：Telegram 时不时加新样式，认不出的
// 那层也不该把里面的文字整段吞掉。
function appendRich(node: TdObject | undefined, out: string[], at: number,
  entities: TdObject[], url: string): number {
  if (node === undefined) {
    return at;
  }
  const type: string = (node['@type'] as string | undefined) ?? '';
  if (type === 'richTextPlain') {
    const t: string = (node['text'] as string | undefined) ?? '';
    if (t !== '') {
      out.push(t);
    }
    return at + t.length;
  }
  if (type === 'richTexts') {
    const parts = (node['texts'] as TdObject[] | undefined) ?? [];
    let cursor: number = at;
    for (const part of parts) {
      cursor = appendRich(part, out, cursor, entities, url);
    }
    return cursor;
  }
  const styles: Map<string, string> = STYLE_ENTITY;
  const mapped: string | undefined = styles.get(type);
  const nextUrl: string = type === 'richTextUrl'
    ? ((node['url'] as string | undefined) ?? '') : url;
  const start: number = at;
  const end: number = appendRich(node['text'] as TdObject | undefined, out, at, entities, nextUrl);
  if (end > start) {
    if (mapped !== undefined) {
      entities.push(entityAt(mapped, { start, end }, mapped === 'textEntityTypeTextUrl' ? nextUrl : ''));
    } else if (type === 'richTextUrl' && nextUrl !== '') {
      entities.push(entityAt('textEntityTypeTextUrl', { start, end }, nextUrl));
    }
  }
  return end;
}

const STYLE_ENTITY: Map<string, string> = new Map<string, string>([
  ['richTextBold', 'textEntityTypeBold'],
  ['richTextItalic', 'textEntityTypeItalic'],
  ['richTextUnderline', 'textEntityTypeUnderline'],
  ['richTextStrikethrough', 'textEntityTypeStrikethrough'],
  ['richTextFixed', 'textEntityTypeCode'],
  ['richTextMarked', 'textEntityTypeUnderline'],
  ['richTextUrl', 'textEntityTypeTextUrl'],
  ['richTextEmailAddress', 'textEntityTypeEmailAddress'],
  ['richTextPhoneNumber', 'textEntityTypePhoneNumber']
]);

// 这些块的文字整段加粗，当作标题。
const HEADING_BLOCKS: string[] = [
  'pageBlockTitle', 'pageBlockSubtitle', 'pageBlockHeader',
  'pageBlockSubheader', 'pageBlockSectionHeading', 'pageBlockKicker'
];

function appendBlocks(blocks: TdObject[], out: string[], at: number,
  entities: TdObject[], quoted: boolean): number {
  let cursor: number = at;
  for (const block of blocks) {
    cursor = appendBlock(block, out, cursor, entities, quoted);
  }
  return cursor;
}

function appendBlock(block: TdObject, out: string[], at: number,
  entities: TdObject[], quoted: boolean): number {
  const type: string = (block['@type'] as string | undefined) ?? '';
  let cursor: number = at;

  // 段间空行。第一块之前不加，否则整条消息从空行开始。
  if (cursor > 0) {
    out.push('\n');
    cursor += 1;
  }

  if (type === 'pageBlockBlockQuote' || type === 'pageBlockPullQuote') {
    const inner = (block['blocks'] as TdObject[] | undefined) ?? [];
    const start: number = cursor;
    let end: number = cursor;
    if (inner.length > 0) {
      end = appendBlocks(inner, out, cursor, entities, true);
    } else {
      end = appendRich(block['text'] as TdObject | undefined, out, cursor, entities, '');
    }
    if (end > start) {
      entities.push(entityAt('textEntityTypeBlockQuote', { start, end }, ''));
    }
    return end;
  }

  if (type === 'pageBlockPreformatted') {
    const start: number = cursor;
    const end: number = appendRich(block['text'] as TdObject | undefined, out, cursor, entities, '');
    if (end > start) {
      entities.push(entityAt('textEntityTypePre', { start, end }, ''));
    }
    return end;
  }

  if (type === 'pageBlockList') {
    const items = (block['items'] as TdObject[] | undefined) ?? [];
    for (const item of items) {
      const inner = (item['page_blocks'] as TdObject[] | undefined) ?? [];
      cursor = appendBlocks(inner, out, cursor, entities, quoted);
    }
    return cursor;
  }

  const start: number = cursor;
  const end: number = appendRich(block['text'] as TdObject | undefined, out, cursor, entities, '');
  if (end > start && HEADING_BLOCKS.indexOf(type) >= 0) {
    entities.push(entityAt('textEntityTypeBold', { start, end }, ''));
  }
  return end;
}

// messageRichMessage 的 content → formattedText 等价物。
// 拿不到任何文字时返回空串，调用方照旧退回"暂不支持"的兜底。
export function flattenRichMessage(content: TdObject): FlatText {
  const message = content['message'] as TdObject | undefined;
  const blocks = message !== undefined
    ? ((message['blocks'] as TdObject[] | undefined) ?? []) : [];
  const out: string[] = [];
  const entities: TdObject[] = [];
  appendBlocks(blocks, out, 0, entities, false);
  // 必须按偏移排序。实体是按遍历顺序 push 的，嵌套时内层会排在外层前面
  // （引用块最明显）；下游 parseFormattedText 按有序实体处理，乱序会让部分
  // 样式整段失效——真机上表现为标题该加粗却没有。
  // 同偏移时长的在前，外层包内层，这也是 TDLib 自己的约定。
  entities.sort((a: TdObject, b: TdObject): number => {
    const ao: number = (a['offset'] as number | undefined) ?? 0;
    const bo: number = (b['offset'] as number | undefined) ?? 0;
    if (ao !== bo) {
      return ao - bo;
    }
    const al: number = (a['length'] as number | undefined) ?? 0;
    const bl: number = (b['length'] as number | undefined) ?? 0;
    return bl - al;
  });
  return { text: out.join(''), entities };
}
