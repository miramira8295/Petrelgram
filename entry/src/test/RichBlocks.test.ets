import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import {
  RB_DIVIDER, RB_HEADING, RB_LIST_ITEM, RB_PARAGRAPH, RB_PRE, RB_QUOTE,
  RichBlock, RichSpan, parseRichMessage
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

    it('列表项按有无 label 决定序号还是圆点', 0, () => {
      const list: TdObject = { '@type': 'pageBlockList' };
      const item1: TdObject = { '@type': 'pageBlockListItem' };
      item1['label'] = '1.';
      item1['page_blocks'] = [blk('pageBlockParagraph', plain('甲'))];
      const item2: TdObject = { '@type': 'pageBlockListItem' };
      item2['page_blocks'] = [blk('pageBlockParagraph', plain('乙'))];
      list['items'] = [item1, item2];
      const bs: RichBlock[] = parseRichMessage(message([list]));
      expect(bs.length).assertEqual(2);
      expect(bs[0].kind).assertEqual(RB_LIST_ITEM);
      expect(bs[0].ordered).assertTrue();
      expect(bs[0].marker).assertEqual('1.');
      expect(bs[1].ordered).assertFalse();
      expect(bs[1].marker).assertEqual('•');
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
  });
}
