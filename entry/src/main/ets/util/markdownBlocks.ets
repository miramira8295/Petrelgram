// GitHub release 正文的轻量 markdown 解析。
//
// 只覆盖发布说明里真正会用到的语法：标题、无序列表、粗体、行内代码。刻意不做
// 完整的 markdown —— 表格、图片、嵌套引用在发布说明里几乎不出现，为它们引入
// 一个解析库不划算，而且渲染失败比不渲染更难看。
//
// 解析结果是纯数据，渲染在 AboutPage 里做，方便单测。

export interface MdSpan {
  text: string;
  bold: boolean;
  code: boolean;
}

export interface MdBlock {
  kind: string;   // 'heading' | 'bullet' | 'paragraph'
  level: number;  // heading 才有意义：1/2/3
  spans: MdSpan[];
}

function span(text: string, bold: boolean, code: boolean): MdSpan {
  return { text: text, bold: bold, code: code };
}

// 行内解析：**粗体** 与 `代码`。两者不嵌套 —— 发布说明里没有这种写法，
// 硬撑嵌套只会让状态机变复杂。
export function parseInline(raw: string): MdSpan[] {
  const spans: MdSpan[] = [];
  let buffer: string = '';
  let index: number = 0;
  const flush = (): void => {
    if (buffer !== '') {
      spans.push(span(buffer, false, false));
      buffer = '';
    }
  };
  while (index < raw.length) {
    const rest: string = raw.substring(index);
    if (rest.startsWith('**')) {
      const end: number = rest.indexOf('**', 2);
      if (end > 2) {
        flush();
        spans.push(span(rest.substring(2, end), true, false));
        index += end + 2;
        continue;
      }
    }
    if (rest.startsWith('`')) {
      const end: number = rest.indexOf('`', 1);
      if (end > 1) {
        flush();
        spans.push(span(rest.substring(1, end), false, true));
        index += end + 1;
        continue;
      }
    }
    buffer += raw.charAt(index);
    index++;
  }
  flush();
  return spans.length > 0 ? spans : [span('', false, false)];
}

// 块级解析。连续的普通行合并成一段（markdown 的软换行语义），空行分段。
export function parseMarkdownBlocks(raw: string): MdBlock[] {
  const blocks: MdBlock[] = [];
  let paragraph: string[] = [];
  const flushParagraph = (): void => {
    if (paragraph.length > 0) {
      blocks.push({ kind: 'paragraph', level: 0, spans: parseInline(paragraph.join(' ')) });
      paragraph = [];
    }
  };
  for (const rawLine of raw.split('\n')) {
    const line: string = rawLine.trim();
    if (line === '') {
      flushParagraph();
      continue;
    }
    const heading = line.match(/^(#{1,3})\s+(.*)$/);
    if (heading !== null) {
      flushParagraph();
      blocks.push({
        kind: 'heading',
        level: heading[1].length,
        spans: parseInline(heading[2])
      });
      continue;
    }
    const bullet = line.match(/^[-*·]\s+(.*)$/);
    if (bullet !== null) {
      flushParagraph();
      blocks.push({ kind: 'bullet', level: 0, spans: parseInline(bullet[1]) });
      continue;
    }
    paragraph.push(line);
  }
  flushParagraph();
  return blocks;
}
