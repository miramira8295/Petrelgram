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
export const RB_TABLE: string = 'table';

// 表格的一格。**空格子也要留着**——列是靠位置对齐的，丢掉一个空单元格
// 后面整行就错位了。
export interface RichCell {
  spans: RichSpan[];
  header: boolean;
  // 'left' | 'center' | 'right'，来自 pageBlockHorizontalAlignment*。
  align: string;
}

// 一段行内文字及其样式。url 非空表示可点。
export interface RichSpan {
  text: string;
  bold: boolean;
  italic: boolean;
  underline: boolean;
  strike: boolean;
  code: boolean;
  url: string;
  // 这一段是数学公式（text 是 LaTeX 原文）。**和 code 分开记**：块渲染那条路
  // 把公式当代码体显示，而序列化成 Markdown 时它要写成 `$...$` 才能被公式
  // 引擎接住——两种去处需要区分，光靠 code 标记分不出来。
  math: boolean;
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
  // RB_LIST_ITEM 用：任务列表。源里 pageBlockListItem 自带 has_checkbox /
  // is_checked，**不需要**去解析 `- [x]` 这种文本前缀。
  hasCheckbox: boolean;
  checked: boolean;
  // RB_TABLE 用。spans 在表格块上另作它用：装 caption（表格下方的说明）。
  rows: RichCell[][];
  bordered: boolean;
  striped: boolean;
}

function emptySpan(text: string): RichSpan {
  return {
    text, bold: false, italic: false, underline: false, strike: false,
    code: false, url: '', math: false
  };
}

function styled(base: RichSpan, type: string, url: string): RichSpan {
  return {
    text: base.text,
    bold: base.bold || type === 'richTextBold',
    italic: base.italic || type === 'richTextItalic',
    underline: base.underline || type === 'richTextUnderline' || type === 'richTextMarked',
    strike: base.strike || type === 'richTextStrikethrough',
    code: base.code || type === 'richTextFixed',
    url: url !== '' ? url : base.url,
    math: base.math
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
  // 数学公式。真机字段：`keys=[@type,expression]`，expression 是 LaTeX 原文。
  //
  // 【为什么按代码体显示原文，而不是渲染成公式】真渲染要一个 LaTeX 排版引擎，
  // 和"在聊天气泡里显示一条公式"完全不成比例。而这个节点**没有 text 字段**，
  // 下面那条"认不出就递归 node['text']"的兜底对它返回空——于是公式整段凭空
  // 消失，用户只看到"行内公式:"后面什么都没有（2026-09-22 实报）。
  // 显示原文至少让内容不丢，也看得出这里本来是个公式。
  if (type === 'richTextMathematicalExpression') {
    const expr: string = (node['expression'] as string | undefined) ?? '';
    if (expr === '') {
      return [];
    }
    const span: RichSpan = styled(emptySpan(expr), 'richTextFixed', url);
    return [{
      text: span.text, bold: span.bold, italic: span.italic, underline: span.underline,
      strike: span.strike, code: span.code, url: span.url, math: true
    }];
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
  children: RichBlock[], ordered: boolean, marker: string,
  hasCheckbox: boolean = false, checked: boolean = false,
  rows: RichCell[][] = [], bordered: boolean = false,
  striped: boolean = false): RichBlock {
  return {
    kind, level, spans, children, ordered, marker, hasCheckbox, checked,
    rows, bordered, striped
  };
}

// pageBlockHorizontalAlignment* → 渲染只认的三档。
function cellAlign(node: TdObject | undefined): string {
  const type: string = node !== undefined
    ? ((node['@type'] as string | undefined) ?? '') : '';
  if (type === 'pageBlockHorizontalAlignmentCenter') {
    return 'center';
  }
  if (type === 'pageBlockHorizontalAlignmentRight') {
    return 'right';
  }
  return 'left';
}

// pageBlockListItem 的子块字段。
//
// **实测叫 `blocks`，不是 td_api 文档上的 `page_blocks`**（2026-09-22 真机探针：
// `firstKeys=[@type,label,blocks,has_checkbox,is_checked,value,type]`）。读错名字
// 的后果是整份列表静默消失——子块取到空数组，上面那个 `children.length === 0`
// 就把每一项都 continue 掉了。用户报的「表格/列表整块不见」，列表那一半就是它。
//
// 这个 bug 能活下来是因为**单测抄了同一份错假设**：RichBlocks.test 里的桩数据
// 也写的 `page_blocks`，于是代码和用例互相印证，谁都没碰过真实数据。两个名字
// 都认下来，别再为这种事翻一次车。
function listItemBlocks(item: TdObject): TdObject[] {
  const real = item['blocks'] as TdObject[] | undefined;
  if (real !== undefined) {
    return real;
  }
  return (item['page_blocks'] as TdObject[] | undefined) ?? [];
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
      const children: RichBlock[] = parseBlocks(listItemBlocks(item));
      if (children.length === 0) {
        continue;
      }
      // label 由源提供（有序列表是 "1."，无序是空）。空就自己画圆点。
      const label: string = (item['label'] as string | undefined) ?? '';
      const hasCheckbox: boolean = (item['has_checkbox'] as boolean | undefined) ?? false;
      const checked: boolean = (item['is_checked'] as boolean | undefined) ?? false;
      out.push(block(RB_LIST_ITEM, 0, [], children, label !== '',
        label !== '' ? label : '•', hasCheckbox, checked));
    }
    return out;
  }

  if (type === 'pageBlockTable') {
    // 真机字段：keys=[@type,cells,is_bordered,is_striped]，
    // cellKeys=[@type,text,is_header,colspan,rowspan,align,valign]。
    //
    // **colspan / rowspan 按 1 处理，不做跨格合并**：Markdown 生成的表格里这两个
    // 恒为 1（GFM 不支持合并单元格），而真要支持就得在气泡里写一个网格布局引擎，
    // 和「在聊天气泡里放一张表」不成比例。遇到 >1 的表只是列对不齐，不会崩。
    const cells = (node['cells'] as TdObject[][] | undefined) ?? [];
    const rows: RichCell[][] = [];
    for (const row of cells) {
      const out: RichCell[] = [];
      for (const cell of row) {
        // 空格子照样 push：列靠位置对齐，丢一个后面整行就错位。
        out.push({
          spans: spansOf(cell['text'] as TdObject | undefined, ''),
          header: (cell['is_header'] as boolean | undefined) ?? false,
          align: cellAlign(cell['align'] as TdObject | undefined)
        });
      }
      if (out.length > 0) {
        rows.push(out);
      }
    }
    if (rows.length === 0) {
      return [];
    }
    const caption: RichSpan[] = spansOf(node['caption'] as TdObject | undefined, '');
    return [block(RB_TABLE, 0, caption, [], false, '', false, false, rows,
      (node['is_bordered'] as boolean | undefined) ?? false,
      (node['is_striped'] as boolean | undefined) ?? false)];
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
