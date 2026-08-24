import { describe, it, expect } from '@ohos/hypium';
import {
  isUnformattedPlainText, parseFormattedText, RichSegment
} from '../main/ets/util/richText';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function entity(offset: number, length: number, typeName: string): TdObject {
  const type: TdObject = { '@type': typeName };
  const value: TdObject = { '@type': 'textEntity' };
  value['offset'] = offset;
  value['length'] = length;
  value['type'] = type;
  return value;
}

export default function richTextTest() {
  describe('RichText', () => {
    it('detects_only_unstyled_non_link_text_for_direct_rendering', 0, () => {
      expect(isUnformattedPlainText('ordinary message', [])).assertTrue();
      expect(isUnformattedPlainText('两行\n普通文本', [])).assertTrue();
      expect(isUnformattedPlainText('   ', [])).assertFalse();
      expect(isUnformattedPlainText('打开 https://example.com', [])).assertFalse();
      expect(isUnformattedPlainText('你好 @alice', [])).assertFalse();
      expect(isUnformattedPlainText('#话题', [])).assertFalse();
      expect(isUnformattedPlainText('styled', [{ '@type': 'textEntity' }])).assertFalse();
    });
    it('collapses_block_boundary_blank_lines', 0, () => {
      const text: string = '来源标题\n\n引用内容';
      const type: TdObject = { '@type': 'textEntityTypeBlockQuote' };
      const entity: TdObject = {
        '@type': 'textEntity',
        'offset': 6,
        'length': 4,
        'type': type
      };
      const segments: RichSegment[] = parseFormattedText(text, [entity]);
      expect(segments.length).assertEqual(2);
      expect(segments[0].runs[0].text).assertEqual('来源标题');
      expect(segments[1].text).assertEqual('引用内容');
    });

    it('preserves_internal_paragraph_breaks_without_blocks', 0, () => {
      const segments: RichSegment[] = parseFormattedText('第一段\n\n第二段', []);
      expect(segments.length).assertEqual(1);
      expect(segments[0].runs[0].text).assertEqual('第一段\n\n第二段');
    });

    it('overlapping_bold_keeps_complete_url_target', 0, () => {
      const text = 'https://example.com';
      const segments = parseFormattedText(text, [
        entity(0, text.length, 'textEntityTypeUrl'),
        entity(8, 7, 'textEntityTypeBold')
      ]);
      expect(segments[0].runs.length > 1).assertTrue();
      for (const run of segments[0].runs) {
        expect(run.url).assertEqual(text);
      }
    });

    it('parses_inline_styles_and_custom_emoji', 0, () => {
      const custom = entity(4, 2, 'textEntityTypeCustomEmoji');
      const customType = custom['type'] as TdObject;
      customType['custom_emoji_id'] = '9988';
      const segments = parseFormattedText('abc 😀', [
        entity(0, 1, 'textEntityTypeUnderline'),
        entity(1, 1, 'textEntityTypeStrikethrough'),
        entity(2, 1, 'textEntityTypeCode'),
        entity(4, 2, 'textEntityTypeSpoiler'),
        custom
      ]);
      expect(segments[0].runs[0].underline).assertTrue();
      expect(segments[0].runs[1].strike).assertTrue();
      expect(segments[0].runs[2].code).assertTrue();
      const last = segments[0].runs[segments[0].runs.length - 1];
      expect(last.spoiler).assertTrue();
      expect(last.customEmojiId).assertEqual('9988');
    });

    it('auto_detects_plain_url_and_excludes_trailing_punctuation', 0, () => {
      const segments = parseFormattedText('打开 https://example.com。', []);
      const runs = segments[0].runs;
      expect(runs.length).assertEqual(3);
      expect(runs[1].url).assertEqual('https://example.com');
      expect(runs[2].text).assertEqual('。');
    });

    it('maps_commands_phone_and_bank_card_actions', 0, () => {
      const phone = '+86 138-0013-8000';
      const card = '6222';
      const text = `/start ${phone} ${card}`;
      const segments = parseFormattedText(text, [
        entity(0, 6, 'textEntityTypeBotCommand'),
        entity(text.indexOf(phone), phone.length, 'textEntityTypePhoneNumber'),
        entity(text.indexOf(card), card.length, 'textEntityTypeBankCardNumber')
      ]);
      expect(segments[0].runs[0].url).assertEqual('tg-command:/start');
      expect(segments[0].runs[2].url).assertEqual('tel:+8613800138000');
      expect(segments[0].runs[4].url).assertEqual('tg-copy:6222');
    });

    it('keeps_expandable_quote_and_code_language_metadata', 0, () => {
      const quote = entity(0, 5, 'textEntityTypeExpandableBlockQuote');
      const pre = entity(6, 4, 'textEntityTypePreCode');
      const preType = pre['type'] as TdObject;
      preType['language'] = 'ts';
      const segments = parseFormattedText('quote\ncode', [quote, pre]);
      expect(segments[0].expandable).assertTrue();
      expect(segments[1].language).assertEqual('ts');
      expect(segments[1].isLast).assertTrue();
    });

    it('ignores_invalid_entity_ranges_without_losing_text', 0, () => {
      const segments = parseFormattedText('safe', [
        entity(99, 10, 'textEntityTypeBold'),
        entity(-8, 0, 'textEntityTypeItalic')
      ]);
      expect(segments.length).assertEqual(1);
      expect(segments[0].runs[0].text).assertEqual('safe');
    });
  });
}
