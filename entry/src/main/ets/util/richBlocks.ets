import { DrawnInlineIcon, drawnInlineIcon } from './drawnInlineIcon';
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
export const RB_MATH: string = 'math';

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
  spoiler?: boolean;
  customEmojiId?: string;
  anchor?: string;
  icon?: DrawnInlineIcon;
  script?: number;
  marked?: boolean;
  unsupported?: string;
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
  // RB_PRE 用：代码块的语言（pageBlockPreformatted.language），可能为空串。
  language: string;
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
    underline: base.underline || type === 'richTextUnderline',
    marked: base.marked === true || type === 'richTextMarked',
    strike: base.strike || type === 'richTextStrikethrough',
    code: base.code || type === 'richTextFixed',
    spoiler: base.spoiler === true || type === 'richTextSpoiler', customEmojiId: base.customEmojiId,
    url: url !== '' ? url : base.url,
    icon: base.icon, math: base.math, unsupported: base.unsupported,
    script: type === 'richTextSubscript' ? -1 : type === 'richTextSuperscript' ? 1 : base.script
  };
}

interface RichSpanFrame {
  node: TdObject;
  style: RichSpan;
}

// One visit per richText node. Carry inherited flags down to leaves instead of
// mapping/copying every descendant array at every wrapper (O(nodes × depth)).
// An explicit stack also handles deeply nested style wrappers without JS stack overflow.
export function richSpansOf(node: TdObject | undefined, url: string = '', internalAnchors: boolean = false): RichSpan[] {
  if (node === undefined) { return []; }
  const out: RichSpan[] = [];
  const initial = emptySpan(''); initial.url = url;
  const pending: RichSpanFrame[] = [{ node, style: initial }];
  while (pending.length > 0) {
    const frame = pending.pop()!;
    const current = frame.node;
    const type = (current['@type'] as string | undefined) ?? '';
    if (type === 'richTexts') {
      const children = (current['texts'] as TdObject[] | undefined) ?? [];
      for (let i: number = children.length - 1; i >= 0; i--) {
        pending.push({ node: children[i], style: frame.style });
      }
      continue;
    }
    if (internalAnchors && (type === 'richTextAnchor' ||
      (type === 'richTextReference' && current['name'] !== undefined && current['anchor_name'] === undefined && current['url'] === undefined))) {
      const marker = emptySpan(''); marker.anchor = ((current['name'] as string | undefined) ?? '').toLowerCase();
      out.push(marker);
      const child = current['text'] as TdObject | undefined;
      if (child !== undefined) { pending.push({ node: child, style: frame.style }); }
      continue;
    }
    if (type === 'richTextCustomEmoji') {
      const leaf = styled(frame.style, '', '');
      leaf.text = (current['alternative_text'] as string | undefined) ?? '';
      leaf.customEmojiId = `${current['custom_emoji_id'] ?? ''}`;
      if (leaf.customEmojiId === '' || leaf.customEmojiId === '0' || leaf.text === '') { leaf.unsupported = type; }
      out.push(leaf); continue;
    }
    if (type === 'richTextIcon') {
      const leaf = styled(frame.style, '', ''); leaf.text = '\uFFFC'; leaf.icon = drawnInlineIcon(current);
      if (leaf.icon === undefined) { leaf.unsupported = type; }
      out.push(leaf); continue;
    }
    if (type === 'richTextPlain' || type === 'richTextMathematicalExpression') {
      const value = (current[type === 'richTextPlain' ? 'text' : 'expression'] as string | undefined) ?? '';
      if (value !== '') {
        const leaf = styled(frame.style, type === 'richTextMathematicalExpression' ? 'richTextFixed' : '', '');
        leaf.text = value; leaf.math = type === 'richTextMathematicalExpression'; out.push(leaf);
      }
      continue;
    }
    let target: string = '';
    if (type === 'richTextUrl' || type === 'richTextReference' || type === 'richTextReferenceLink' || type === 'richTextAnchorLink') {
      const refName = (current[type === 'richTextReferenceLink' ? 'reference_name' : 'anchor_name'] as string | undefined) ?? '';
      target = internalAnchors && type !== 'richTextUrl'
        ? `#${encodeURIComponent(refName)}`
        : (current['url'] as string | undefined) ?? '';
    } else if (type === 'richTextEmailAddress') {
      const address = (current['email_address'] as string | undefined) ?? '';
      if (address !== '') { target = `mailto:${address}`; }
    } else if (type === 'richTextPhoneNumber') {
      const phone = (current['phone_number'] as string | undefined) ?? '';
      if (phone !== '') { target = `tel:${phone}`; }
    } else if (type === 'richTextMention') {
      const username = ((current['username'] as string | undefined) ?? '').replace(/^@/, '');
      if (username !== '') { target = `https://t.me/${username}`; }
    } else if (type === 'richTextMentionName') {
      const userId = (current['user_id'] as number | undefined) ?? 0;
      if (userId > 0) { target = `tg://user?id=${userId}`; }
    } else if (type === 'richTextHashtag') {
      const hashtag = ((current['hashtag'] as string | undefined) ?? '').replace(/^#/, '');
      if (hashtag !== '') { target = `tg-hashtag:#${hashtag}`; }
    } else if (type === 'richTextCashtag') {
      const cashtag = ((current['cashtag'] as string | undefined) ?? '').replace(/^\$/, '');
      if (cashtag !== '') { target = `tg-hashtag:$${cashtag}`; }
    } else if (type === 'richTextBotCommand') {
      const cmd = ((current['bot_command'] as string | undefined) ?? '').replace(/^\//, '');
      if (cmd !== '') { target = `tg-command:/${cmd}`; }
    } else if (type === 'richTextBankCardNumber') {
      const card = (current['bank_card_number'] as string | undefined) ?? '';
      if (card !== '') { target = `tg-copy:${card}`; }
    } else if (type === 'richTextTonAddress') {
      const addr = (current['address'] as string | undefined) ?? '';
      if (addr !== '') { target = `tg-copy:${addr}`; }
    } else if (type === 'richTextButton') {
      const btn = current['button'] as TdObject | undefined;
      const btnType = btn?.['type'] as TdObject | undefined;
      const btnUrl = btnType?.['@type'] === 'inlineKeyboardButtonTypeUrl'
        ? ((btnType['url'] as string | undefined) ?? '') : '';
      const rawText = btn?.['text'];
      if (typeof rawText === 'string' && rawText !== '') {
        const leaf = styled(frame.style, 'richTextBold', btnUrl);
        leaf.text = rawText;
        out.push(leaf);
        continue;
      }
      if (rawText !== undefined && typeof rawText === 'object') {
        pending.push({ node: rawText as TdObject, style: styled(frame.style, 'richTextBold', btnUrl) });
        continue;
      }
    } else if (type === 'richTextDiff') {
      const removed = current['is_removed'] === true;
      const diffStyle = styled(frame.style, removed ? 'richTextStrikethrough' : 'richTextMarked', '');
      const diffChild = current['text'] as TdObject | undefined;
      if (diffChild !== undefined) { pending.push({ node: diffChild, style: diffStyle }); }
      continue;
    }
    const child = current['text'] as TdObject | undefined;
    if (child !== undefined) { pending.push({ node: child, style: styled(frame.style, type, target) }); }
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
  striped: boolean = false, language: string = ''): RichBlock {
  return {
    kind, level, spans, children, ordered, marker, hasCheckbox, checked,
    rows, bordered, striped, language
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
    const rawSize = type === 'pageBlockSectionHeading' ? (node['size'] as number | undefined) : undefined;
    const resolvedLevel = rawSize !== undefined && Number.isFinite(rawSize)
      ? (rawSize <= 1 ? 1 : rawSize === 2 ? 2 : 3) : level;
    const spans: RichSpan[] = richSpansOf((node['text'] ?? node[type.substring(9).toLowerCase()]) as TdObject | undefined, '');
    return spans.length > 0 ? [block(RB_HEADING, resolvedLevel, spans, [], false, '')] : [];
  }

  if (type === 'pageBlockMathematicalExpression' || type === 'pageBlockMath') {
    const expr: string = ((node['expression'] ?? node['source']) as string | undefined) ?? '';
    if (expr.trim() === '') { return []; }
    const mathSpan: RichSpan = emptySpan(expr);
    mathSpan.code = true; mathSpan.math = true;
    return [block(RB_MATH, 0, [mathSpan], [], false, '')];
  }

  if (type === 'pageBlockBlockQuote' || type === 'pageBlockExpandableBlockQuote' || type === 'pageBlockPullQuote') {
    const inner = (node['blocks'] as TdObject[] | undefined) ?? [];
    const children: RichBlock[] = inner.length > 0
      ? parseBlocks(inner)
      : parseTextOnly(node);
    return children.length > 0 ? [block(RB_QUOTE, 0, [], children, false, '')] : [];
  }

  if (type === 'pageBlockUnsupported') {
    return [];
  }

  if (type === 'pageBlockPreformatted') {
    const spans: RichSpan[] = richSpansOf(node['text'] as TdObject | undefined, '');
    // language 是可选的，源里常常是空串——渲染侧据此决定表头写 "code" 还是
    // "code: python"。
    const language: string = (node['language'] as string | undefined) ?? '';
    return spans.length > 0
      ? [block(RB_PRE, 0, spans, [], false, '', false, false, [], false, false, language)]
      : [];
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
          spans: richSpansOf(cell['text'] as TdObject | undefined, ''),
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
    const caption: RichSpan[] = richSpansOf(node['caption'] as TdObject | undefined, '');
    return [block(RB_TABLE, 0, caption, [], false, '', false, false, rows,
      (node['is_bordered'] as boolean | undefined) ?? false,
      (node['is_striped'] as boolean | undefined) ?? false)];
  }

  return parseTextOnly(node);
}

// 兜底：只要这个块带 text，就当普通段落收下。认不出的块类型（图片、嵌入等）
// 没有 text，返回空数组直接跳过，而不是留个空段落撑出一行空白。
function parseTextOnly(node: TdObject): RichBlock[] {
  const spans: RichSpan[] = richSpansOf(node['text'] as TdObject | undefined, '');
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
