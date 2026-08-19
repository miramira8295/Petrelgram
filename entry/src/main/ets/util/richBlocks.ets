import { TdObject } from '../tdkit/TdTypes';

// messageRichMessage（富文本长帖）的页面块 → 有类型的块模型。
//
// 和 util/richMessage 的摊平版并存，两者服务不同的地方：
//   - 摊平版把整棵树压成一行 text，只够会话列表的预览用；
//   - 这里保留块结构，供 RichMessageView 按块渲染——标题有层级、引用画竖条、
//     列表画项目符号，不像摊平那样一律退化成加粗。
//
// 解析和渲染分开，是为了让规则能单测：偏移、嵌套、认不出的节点怎么办，这些
// 都不该埋在组件里。

export const RB_PARAGRAPH: string = 'paragraph';
export const RB_HEADING: string = 'heading';
export const RB_QUOTE: string = 'quote';
export const RB_PRE: string = 'pre';
export const RB_LIST_ITEM: string = 'item';
export const RB_DIVIDER: string = 'divider';

// 一段行内文字及其样式。url 非空表示可点。
export interface RichSpan {
  text: string;
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strike: boolean;
  code: boolean;
  url: string;
}

export interface RichBlock {
  kind: string;
  // RB_HEADING 用：1 最大。源里的 pageBlockTitle/Header/SectionHeading 各有
  // 各的语义，这里统一折成 1~3 三档，渲染只认档位。
  level: number;
  spans: RichSpan[];
  // RB_QUOTE / RB_LIST_ITEM 的内容块。
  children: RichBlock[];
  // RB_LIST_ITEM 用：有序列表显示序号，无序显示圆点。
  ordered: boolean;
  marker: string;
}

function emptySpan(text: string): RichSpan {
  return { text, bold: false, italic: false, underline: false, strike: false, code: false, url: '' };
}

function styled(base: RichSpan, type: string, url: string): RichSpan {
  return {
    text: base.text,
    bold: base.bold || type === 'richTextBold',
    italic: base.italic || type === 'richTextItalic',
    underline: base.underline || type === 'richTextUnderline' || type === 'richTextMarked',
    strike: base.strike || type === 'richTextStrikethrough',
    code: base.code || type === 'richTextFixed',
    url: url !== '' ? url : base.url
  };
}

// richText 树 → 扁平的 span 列表。认不出的包装节点递归它的 text，不吞文字。
function spansOf(node: TdObject | undefined, url: string): RichSpan[] {
  if (node === undefined) {
    return [];
  }
  const type: string = (node['@type'] as string | undefined) ?? '';
  if (type === 'richTextPlain') {
    const t: string = (node['text'] as string | undefined) ?? '';
    if (t === '') {
      return [];
    }
    const s: RichSpan = emptySpan(t);
    return [url !== '' ? styled(s, '', url) : s];
  }
  if (type === 'richTexts') {
    const parts = (node['texts'] as TdObject[] | undefined) ?? [];
    const out: RichSpan[] = [];
    for (const part of parts) {
      for (const s of spansOf(part, url)) {
        out.push(s);
      }
    }
    return out;
  }
  const nextUrl: string = type === 'richTextUrl'
    ? ((node['url'] as string | undefined) ?? url) : url;
  const inner: RichSpan[] = spansOf(node['text'] as TdObject | undefined, nextUrl);
  const out: RichSpan[] = [];
  for (const s of inner) {
    out.push(styled(s, type, nextUrl));
  }
  return out;
}

// 源里的标题块种类多，渲染只需要档位。
const HEADING_LEVEL: Map<string, number> = new Map<string, number>([
  ['pageBlockTitle', 1],
  ['pageBlockHeader', 1],
  ['pageBlockSubtitle', 2],
  ['pageBlockSubheader', 2],
  ['pageBlockSectionHeading', 2],
  ['pageBlockKicker', 3]
]);

function block(kind: string, level: number, spans: RichSpan[],
  children: RichBlock[], ordered: boolean, marker: string): RichBlock {
  return { kind, level, spans, children, ordered, marker };
}

function parseOne(node: TdObject): RichBlock[] {
  const type: string = (node['@type'] as string | undefined) ?? '';

  const level: number | undefined = HEADING_LEVEL.get(type);
  if (level !== undefined) {
    const spans: RichSpan[] = spansOf(node['text'] as TdObject | undefined, '');
    return spans.length > 0 ? [block(RB_HEADING, level, spans, [], false, '')] : [];
  }

  if (type === 'pageBlockBlockQuote' || type === 'pageBlockPullQuote') {
    const inner = (node['blocks'] as TdObject[] | undefined) ?? [];
    const children: RichBlock[] = inner.length > 0
      ? parseBlocks(inner)
      : parseTextOnly(node);
    return children.length > 0 ? [block(RB_QUOTE, 0, [], children, false, '')] : [];
  }

  if (type === 'pageBlockPreformatted') {
    const spans: RichSpan[] = spansOf(node['text'] as TdObject | undefined, '');
    return spans.length > 0 ? [block(RB_PRE, 0, spans, [], false, '')] : [];
  }

  if (type === 'pageBlockDivider') {
    return [block(RB_DIVIDER, 0, [], [], false, '')];
  }

  if (type === 'pageBlockList') {
    const items = (node['items'] as TdObject[] | undefined) ?? [];
    const out: RichBlock[] = [];
    for (let i: number = 0; i < items.length; i++) {
      const item: TdObject = items[i];
      const inner = (item['page_blocks'] as TdObject[] | undefined) ?? [];
      const children: RichBlock[] = parseBlocks(inner);
      if (children.length === 0) {
        continue;
      }
      // label 由源提供（有序列表是 "1."，无序是空）。空就自己画圆点。
      const label: string = (item['label'] as string | undefined) ?? '';
      out.push(block(RB_LIST_ITEM, 0, [], children, label !== '', label !== '' ? label : '•'));
    }
    return out;
  }

  return parseTextOnly(node);
}

// 兜底：只要这个块带 text，就当普通段落收下。认不出的块类型（图片、嵌入等）
// 没有 text，返回空数组直接跳过，而不是留个空段落撑出一行空白。
function parseTextOnly(node: TdObject): RichBlock[] {
  const spans: RichSpan[] = spansOf(node['text'] as TdObject | undefined, '');
  return spans.length > 0 ? [block(RB_PARAGRAPH, 0, spans, [], false, '')] : [];
}

export function parseBlocks(nodes: TdObject[]): RichBlock[] {
  const out: RichBlock[] = [];
  for (const node of nodes) {
    for (const b of parseOne(node)) {
      out.push(b);
    }
  }
  return out;
}

// messageRichMessage 的 content → 块列表。
export function parseRichMessage(content: TdObject): RichBlock[] {
  const message = content['message'] as TdObject | undefined;
  if (message === undefined) {
    return [];
  }
  return parseBlocks((message['blocks'] as TdObject[] | undefined) ?? []);
}
