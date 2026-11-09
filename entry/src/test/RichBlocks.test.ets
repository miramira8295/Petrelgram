import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  RB_DIVIDER, RB_HEADING, RB_LIST_ITEM, RB_PARAGRAPH, RB_PRE, RB_QUOTE, RB_TABLE,
  RichBlock, RichCell, RichSpan, parseRichMessage
} from '../main/ets/util/richBlocks';

function plain(text: string): TdObject {
  const o: TdObject = { '@type': 'richTextPlain' };
  o['text'] = text;
  return o;
}

function wrap(type: string, inner: TdObject): TdObject {
  const o: TdObject = { '@type': type };
  o['text'] = inner;
  return o;
}

function blk(type: string, inner: TdObject): TdObject {
  const o: TdObject = { '@type': type };
  o['text'] = inner;
  return o;
}

function message(blocks: TdObject[]): TdObject {
  const m: TdObject = { '@type': 'richMessage' };
  m['blocks'] = blocks;
  const c: TdObject = { '@type': 'messageRichMessage' };
  c['message'] = m;
  return c;
}

// 解析层的职责：把页面块变成渲染能直接吃的形状，且不丢文字。
export default function richBlocksTest() {
  describe('richBlocks', () => {
    it('标题折成档位，正文是普通段落', 0, () => {
      const bs: RichBlock[] = parseRichMessage(message([
        blk('pageBlockSectionHeading', plain('问题')),
        blk('pageBlockParagraph', plain('正文'))
      ]));
      expect(bs.length).assertEqual(2);
      expect(bs[0].kind).assertEqual(RB_HEADING);
      expect(bs[0].level).assertEqual(2);
      expect(bs[1].kind).assertEqual(RB_PARAGRAPH);
    });

    it('行内样式落到各自的 span 上', 0, () => {
      const runs: TdObject = { '@type': 'richTexts' };
      runs['texts'] = [plain('前 '), wrap('richTextBold', plain('粗')), plain(' 后')];
      const bs: RichBlock[] = parseRichMessage(message([blk('pageBlockParagraph', runs)]));
      const spans: RichSpan[] = bs[0].spans;
      expect(spans.length).assertEqual(3);
      expect(spans[0].bold).assertFalse();
      expect(spans[1].bold).assertTrue();
      expect(spans[1].text).assertEqual('粗');
    });

    it('链接把 url 带到 span 上', 0, () => {
      const link: TdObject = { '@type': 'richTextUrl' };
      link['text'] = plain('站点');
      link['url'] = 'https://example.com';
      const bs: RichBlock[] = parseRichMessage(message([blk('pageBlockParagraph', link)]));
      expect(bs[0].spans[0].url).assertEqual('https://example.com');
    });

    it('嵌套样式叠加，不互相覆盖', 0, () => {
      const nested: TdObject = wrap('richTextBold', wrap('richTextItalic', plain('粗斜')));
      const bs: RichBlock[] = parseRichMessage(message([blk('pageBlockParagraph', nested)]));
      expect(bs[0].spans[0].bold).assertTrue();
      expect(bs[0].spans[0].italic).assertTrue();
    });

    it('引用块保留内部块结构', 0, () => {
      const q: TdObject = { '@type': 'pageBlockBlockQuote' };
      q['blocks'] = [blk('pageBlockParagraph', plain('被引用'))];
      const bs: RichBlock[] = parseRichMessage(message([q]));
      expect(bs[0].kind).assertEqual(RB_QUOTE);
      expect(bs[0].children.length).assertEqual(1);
      expect(bs[0].children[0].spans[0].text).assertEqual('被引用');
    });

    // ⚠️ 这条用例 2026-09-22 之前只喂 `page_blocks`，而**真机上的字段叫
    // `blocks`**。代码读 page_blocks、用例也喂 page_blocks，互相印证，于是线上
    // 五个列表整块静默消失了很久（用户报「列表/表格不见」）。现在两个名字
    // 都喂一遍。
    it('列表项按有无 label 决定序号还是圆点（真机字段名是 blocks）', 0, () => {
      const list: TdObject = { '@type': 'pageBlockList' };
      const item1: TdObject = { '@type': 'pageBlockListItem' };
      item1['label'] = '1.';
      item1['blocks'] = [blk('pageBlockParagraph', plain('甲'))];
      const item2: TdObject = { '@type': 'pageBlockListItem' };
      item2['blocks'] = [blk('pageBlockParagraph', plain('乙'))];
      list['items'] = [item1, item2];
      const bs: RichBlock[] = parseRichMessage(message([list]));
      expect(bs.length).assertEqual(2);
      expect(bs[0].kind).assertEqual(RB_LIST_ITEM);
      expect(bs[0].ordered).assertTrue();
      expect(bs[0].marker).assertEqual('1.');
      expect(bs[1].ordered).assertFalse();
      expect(bs[1].marker).assertEqual('•');
    });

    // td_api 文档上写的是 page_blocks，留作兜底——万一换一版 td 又改回去。
    it('page_blocks 这个旧字段名仍然认', 0, () => {
      const list: TdObject = { '@type': 'pageBlockList' };
      const item: TdObject = { '@type': 'pageBlockListItem' };
      item['page_blocks'] = [blk('pageBlockParagraph', plain('丙'))];
      list['items'] = [item];
      const bs: RichBlock[] = parseRichMessage(message([list]));
      expect(bs.length).assertEqual(1);
      expect(bs[0].children[0].spans[0].text).assertEqual('丙');
    });

    // 任务列表：源里自带 has_checkbox / is_checked，不去解析 `- [x]` 文本前缀。
    it('带勾选框的列表项把状态带出来', 0, () => {
      const list: TdObject = { '@type': 'pageBlockList' };
      const done: TdObject = { '@type': 'pageBlockListItem' };
      done['blocks'] = [blk('pageBlockParagraph', plain('已完成'))];
      done['has_checkbox'] = true;
      done['is_checked'] = true;
      const todo: TdObject = { '@type': 'pageBlockListItem' };
      todo['blocks'] = [blk('pageBlockParagraph', plain('未完成'))];
      todo['has_checkbox'] = true;
      todo['is_checked'] = false;
      list['items'] = [done, todo];
      const bs: RichBlock[] = parseRichMessage(message([list]));
      expect(bs.length).assertEqual(2);
      expect(bs[0].hasCheckbox).assertTrue();
      expect(bs[0].checked).assertTrue();
      expect(bs[1].hasCheckbox).assertTrue();
      expect(bs[1].checked).assertFalse();
    });

    it('普通列表项不带勾选框', 0, () => {
      const list: TdObject = { '@type': 'pageBlockList' };
      const item: TdObject = { '@type': 'pageBlockListItem' };
      item['blocks'] = [blk('pageBlockParagraph', plain('甲'))];
      list['items'] = [item];
      const bs: RichBlock[] = parseRichMessage(message([list]));
      expect(bs[0].hasCheckbox).assertFalse();
      expect(bs[0].checked).assertFalse();
    });

    it('等宽块和分隔线各自成块', 0, () => {
      const div: TdObject = { '@type': 'pageBlockDivider' };
      const bs: RichBlock[] = parseRichMessage(message([
        blk('pageBlockPreformatted', plain('code')), div
      ]));
      expect(bs[0].kind).assertEqual(RB_PRE);
      expect(bs[1].kind).assertEqual(RB_DIVIDER);
    });

    it('认不出的块只要带 text 就当段落收下', 0, () => {
      const bs: RichBlock[] = parseRichMessage(message([blk('pageBlockSomethingNew', plain('照样显示'))]));
      expect(bs.length).assertEqual(1);
      expect(bs[0].kind).assertEqual(RB_PARAGRAPH);
    });

    it('没有 text 的块（图片、嵌入）跳过，不留空段落', 0, () => {
      const img: TdObject = { '@type': 'pageBlockPhoto' };
      const bs: RichBlock[] = parseRichMessage(message([img]));
      expect(bs.length).assertEqual(0);
    });

    // 真机字段（2026-09-22 探针）：keys=[@type,expression]。这个节点**没有 text
    // 字段**，兜底的"递归 node['text']"对它返回空，公式于是整段消失。
    it('数学公式取 expression，按代码体显示原文', 0, () => {
      const math: TdObject = { '@type': 'richTextMathematicalExpression' };
      math['expression'] = 'E = mc^2';
      const texts: TdObject = { '@type': 'richTexts' };
      texts['texts'] = [plain('行内公式: '), math];
      const para: TdObject = { '@type': 'pageBlockParagraph' };
      para['text'] = texts;
      const bs: RichBlock[] = parseRichMessage(message([para]));
      expect(bs.length).assertEqual(1);
      expect(bs[0].spans.length).assertEqual(2);
      expect(bs[0].spans[1].text).assertEqual('E = mc^2');
      expect(bs[0].spans[1].code).assertTrue();
    });

    it('空公式不留空 span', 0, () => {
      const math: TdObject = { '@type': 'richTextMathematicalExpression' };
      math['expression'] = '';
      const para: TdObject = { '@type': 'pageBlockParagraph' };
      para['text'] = math;
      expect(parseRichMessage(message([para])).length).assertEqual(0);
    });

    // 真机字段（2026-09-22 探针）：keys=[@type,cells,is_bordered,is_striped]，
    // cellKeys=[@type,text,is_header,colspan,rowspan,align,valign]。
    // 表格原来整块被丢：parseTextOnly 对没有 text 字段的块返回空数组。
    it('表格按行列解析，表头与对齐带出来', 0, () => {
      const cell = (text: string, header: boolean, align: string): TdObject => {
        const c: TdObject = { '@type': 'pageBlockTableCell' };
        c['text'] = plain(text);
        c['is_header'] = header;
        if (align !== '') {
          c['align'] = { '@type': align } as TdObject;
        }
        return c;
      };
      const table: TdObject = { '@type': 'pageBlockTable' };
      table['is_bordered'] = true;
      table['is_striped'] = true;
      table['cells'] = [
        [cell('列 1', true, ''), cell('列 2', true, 'pageBlockHorizontalAlignmentCenter')],
        [cell('左对齐', false, 'pageBlockHorizontalAlignmentLeft'),
          cell('右对齐', false, 'pageBlockHorizontalAlignmentRight')]
      ];
      const bs: RichBlock[] = parseRichMessage(message([table]));
      expect(bs.length).assertEqual(1);
      expect(bs[0].kind).assertEqual(RB_TABLE);
      expect(bs[0].bordered).assertTrue();
      expect(bs[0].striped).assertTrue();
      expect(bs[0].rows.length).assertEqual(2);
      expect(bs[0].rows[0].length).assertEqual(2);
      expect(bs[0].rows[0][0].header).assertTrue();
      expect(bs[0].rows[0][0].align).assertEqual('left');   // 缺 align 默认左
      expect(bs[0].rows[0][1].align).assertEqual('center');
      expect(bs[0].rows[1][1].align).assertEqual('right');
      expect(bs[0].rows[1][0].spans[0].text).assertEqual('左对齐');
    });

    // 列是靠位置对齐的，空格子丢掉后面整行就错位。
    it('空单元格保留，不塌缩', 0, () => {
      const empty: TdObject = { '@type': 'pageBlockTableCell' };
      const filled: TdObject = { '@type': 'pageBlockTableCell' };
      filled['text'] = plain('甲');
      const table: TdObject = { '@type': 'pageBlockTable' };
      table['cells'] = [[empty, filled, empty]];
      const bs: RichBlock[] = parseRichMessage(message([table]));
      expect(bs[0].rows[0].length).assertEqual(3);
      expect(bs[0].rows[0][0].spans.length).assertEqual(0);
      expect(bs[0].rows[0][1].spans[0].text).assertEqual('甲');
    });

    it('没有任何行的表格整块丢掉，不留空壳', 0, () => {
      const table: TdObject = { '@type': 'pageBlockTable' };
      table['cells'] = [];
      expect(parseRichMessage(message([table])).length).assertEqual(0);
    });

    it('表格的 caption 放在 spans 上', 0, () => {
      const c: TdObject = { '@type': 'pageBlockTableCell' };
      c['text'] = plain('甲');
      const table: TdObject = { '@type': 'pageBlockTable' };
      table['cells'] = [[c]];
      table['caption'] = plain('表一');
      const bs: RichBlock[] = parseRichMessage(message([table]));
      expect(bs[0].spans[0].text).assertEqual('表一');
    });
  });
}
