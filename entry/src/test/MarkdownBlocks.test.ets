import { describe, expect, it } from '@ohos/hypium';
import { MdBlock, MdSpan, parseInline, parseMarkdownBlocks } from '../main/ets/util/markdownBlocks';

function plain(blocks: MdBlock[], index: number): string {
  return blocks[index].spans.map((s: MdSpan): string => s.text).join('');
}

export default function markdownBlocksTest() {
  describe('MarkdownBlocks', (): void => {
    it('parses_headings_bullets_and_paragraphs', 0, (): void => {
      const blocks = parseMarkdownBlocks('## 新增\n\n- 实时位置\n- 顶部穿透\n\n普通说明。');
      expect(blocks.length).assertEqual(4);
      expect(blocks[0].kind).assertEqual('heading');
      expect(blocks[0].level).assertEqual(2);
      expect(plain(blocks, 0)).assertEqual('新增');
      expect(blocks[1].kind).assertEqual('bullet');
      expect(plain(blocks, 1)).assertEqual('实时位置');
      expect(blocks[3].kind).assertEqual('paragraph');
      expect(plain(blocks, 3)).assertEqual('普通说明。');
    });

    it('merges_soft_wrapped_lines_into_one_paragraph', 0, (): void => {
      const blocks = parseMarkdownBlocks('第一行\n第二行\n\n另一段');
      expect(blocks.length).assertEqual(2);
      expect(plain(blocks, 0)).assertEqual('第一行 第二行');
      expect(plain(blocks, 1)).assertEqual('另一段');
    });

    it('marks_bold_and_code_spans', 0, (): void => {
      const spans = parseInline('修正 **三处** 结构，见 `liveLocation`。');
      expect(spans.length).assertEqual(5);
      expect(spans[1].text).assertEqual('三处');
      expect(spans[1].bold).assertTrue();
      expect(spans[3].text).assertEqual('liveLocation');
      expect(spans[3].code).assertTrue();
    });

    it('keeps_unclosed_markers_as_literal_text', 0, (): void => {
      // 未闭合的标记按普通字符处理，否则正文会被吞掉一截。
      const spans = parseInline('a ** b ` c');
      expect(spans.length).assertEqual(1);
      expect(spans[0].text).assertEqual('a ** b ` c');
      expect(spans[0].bold).assertFalse();
    });

    it('returns_empty_block_list_for_blank_input', 0, (): void => {
      expect(parseMarkdownBlocks('').length).assertEqual(0);
      expect(parseMarkdownBlocks('\n\n  \n').length).assertEqual(0);
    });
  });
}
