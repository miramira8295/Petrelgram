import { describe, it, expect } from '@ohos/hypium';
import {
  isUnformattedPlainText, parseFormattedText, richSegmentKey, RichSegment
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
    it('sweep_keeps_original_link_order_instead_of_start_offset_order', 0, () => {
      const first = entity(2, 4, 'textEntityTypeTextUrl');
      const covering = entity(0, 8, 'textEntityTypeTextUrl');
      (first['type'] as TdObject)['url'] = 'first';
      (covering['type'] as TdObject)['url'] = 'covering';
      const runs = parseFormattedText('abcdefgh', [first, covering])[0].runs;
      expect(runs.length).assertEqual(3);
      expect(runs[0].url).assertEqual('covering');
      expect(runs[1].url).assertEqual('first');
      expect(runs[2].url).assertEqual('covering');
    });
    it('sweep_nested_style_exit_does_not_clear_a_covering_style', 0, () => {
      const runs = parseFormattedText('abcdefgh', [
        entity(2, 2, 'textEntityTypeBold'), entity(0, 8, 'textEntityTypeBold'),
        entity(3, 3, 'textEntityTypeItalic')
      ])[0].runs;
      expect(runs.length).assertEqual(3);
      expect(runs[0].text).assertEqual('abc');
      expect(runs[1].text).assertEqual('def');
      expect(runs[2].text).assertEqual('gh');
      for (const run of runs) { expect(run.bold).assertTrue(); }
      expect(runs[1].italic).assertTrue();
      expect(runs[2].italic).assertFalse();
    });
    it('sweep_last_emoji_can_temporarily_override_with_an_empty_id', 0, () => {
      const outer = entity(0, 6, 'textEntityTypeCustomEmoji');
      const inner = entity(2, 2, 'textEntityTypeCustomEmoji');
      (outer['type'] as TdObject)['custom_emoji_id'] = '10';
      (inner['type'] as TdObject)['custom_emoji_id'] = '';
      const runs = parseFormattedText('😀😀😀', [outer, inner])[0].runs;
      expect(runs.length).assertEqual(3);
      expect(runs[0].customEmojiId).assertEqual('10');
      expect(runs[1].customEmojiId).assertEqual('');
      expect(runs[2].customEmojiId).assertEqual('10');
    });
    it('sweep_same_position_end_and_start_keep_distinct_link_targets', 0, () => {
      const first = entity(0, 2, 'textEntityTypeTextUrl');
      const next = entity(2, 2, 'textEntityTypeTextUrl');
      (first['type'] as TdObject)['url'] = 'before';
      (next['type'] as TdObject)['url'] = 'after';
      const runs = parseFormattedText('abcd', [next, first])[0].runs;
      expect(runs.length).assertEqual(2);
      expect(runs[0].url).assertEqual('before');
      expect(runs[1].url).assertEqual('after');
    });
    it('sweep_consumes_events_skipped_by_pre_blocks', 0, () => {
      const segments = parseFormattedText('abcdefghij', [
        entity(2, 4, 'textEntityTypePre'), entity(0, 8, 'textEntityTypeBold'),
        entity(3, 1, 'textEntityTypeItalic'), entity(4, 6, 'textEntityTypeUnderline')
      ]);
      expect(segments.length).assertEqual(3);
      expect(segments[1].kind).assertEqual('pre');
      expect(segments[2].runs.length).assertEqual(2);
      const first = segments[2].runs[0];
      expect(first.text).assertEqual('gh');
      expect(first.bold && first.underline).assertTrue();
      expect(first.italic).assertFalse();
      expect(segments[2].runs[1].text).assertEqual('ij');
      expect(segments[2].runs[1].bold).assertFalse();
    });
    it('sweep_discards_multiple_expired_priority_entries', 0, () => {
      const entities: TdObject[] = [];
      for (let i = 0; i < 5; i++) {
        const link = entity(0, i + 1, 'textEntityTypeTextUrl');
        (link['type'] as TdObject)['url'] = `target${i}`;
        entities.push(link);
      }
      const runs = parseFormattedText('abcdef', entities)[0].runs;
      expect(runs.length).assertEqual(6);
      for (let i = 0; i < 5; i++) { expect(runs[i].url).assertEqual(`target${i}`); }
      expect(runs[5].link).assertFalse();
      expect(runs[5].url).assertEqual('');
    });
    it('sweep_unknown_entities_still_split_spoiler_reveal_ranges', 0, () => {
      const runs = parseFormattedText('abcdef', [entity(0, 6, 'textEntityTypeSpoiler'),
        entity(2, 2, 'textEntityTypeFutureUnknown')])[0].runs;
      expect(runs.length).assertEqual(3);
      for (let i = 0; i < 3; i++) {
        expect(runs[i].offset).assertEqual(i * 2);
        expect(runs[i].text.length).assertEqual(2);
        expect(runs[i].spoiler).assertTrue();
      }
    });
    it('sweep_link_target_spans_quote_and_normal_text_boundaries', 0, () => {
      const link = entity(0, 8, 'textEntityTypeTextUrl');
      (link['type'] as TdObject)['url'] = 'https://example.com/full';
      const segments = parseFormattedText('abcdefgh', [link, entity(2, 4, 'textEntityTypeBlockQuote')]);
      expect(segments.length).assertEqual(3);
      for (const segment of segments) {
        for (const run of segment.runs) { expect(run.url).assertEqual('https://example.com/full'); }
      }
      expect(segments[1].kind).assertEqual('quote');
    });
    it('redundant_style_boundaries_collapse_without_losing_text', 0, () => {
      const runs = parseFormattedText('abcdef', [
        entity(0, 6, 'textEntityTypeBold'), entity(1, 2, 'textEntityTypeBold'),
        entity(3, 3, 'textEntityTypeBold')
      ])[0].runs;
      expect(runs.length).assertEqual(1);
      expect(runs[0].text).assertEqual('abcdef');
      expect(runs[0].offset).assertEqual(0);
      expect(runs[0].bold).assertTrue();
    });
    it('different_overlapping_styles_keep_their_boundaries', 0, () => {
      const runs = parseFormattedText('abcdef', [
        entity(0, 6, 'textEntityTypeBold'), entity(2, 2, 'textEntityTypeItalic')
      ])[0].runs;
      expect(runs.length).assertEqual(3);
      expect(runs[0].text).assertEqual('ab');
      expect(runs[1].text).assertEqual('cd');
      expect(runs[1].bold && runs[1].italic).assertTrue();
      expect(runs[2].text).assertEqual('ef');
      expect(runs[2].italic).assertFalse();
    });
    it('adjacent_spoilers_keep_independent_reveal_keys', 0, () => {
      const runs = parseFormattedText('abcdef', [
        entity(0, 2, 'textEntityTypeSpoiler'), entity(2, 4, 'textEntityTypeSpoiler')
      ])[0].runs;
      expect(runs.length).assertEqual(2);
      expect(`${runs[0].offset}_${runs[0].text.length}`).assertEqual('0_2');
      expect(`${runs[1].offset}_${runs[1].text.length}`).assertEqual('2_4');
    });
    it('adjacent_identical_custom_emoji_keep_two_image_spans', 0, () => {
      const first = entity(0, 2, 'textEntityTypeCustomEmoji');
      const second = entity(2, 2, 'textEntityTypeCustomEmoji');
      (first['type'] as TdObject)['custom_emoji_id'] = '123';
      (second['type'] as TdObject)['custom_emoji_id'] = '123';
      const runs = parseFormattedText('😀😀', [first, second])[0].runs;
      expect(runs.length).assertEqual(2);
      expect(runs[0].text).assertEqual('😀');
      expect(runs[1].offset).assertEqual(2);
      expect(runs[1].customEmojiId).assertEqual('123');
    });
    it('adjacent_same_target_links_keep_display_text_and_tap_regions', 0, () => {
      const first = entity(0, 3, 'textEntityTypeTextUrl');
      const second = entity(3, 3, 'textEntityTypeTextUrl');
      (first['type'] as TdObject)['url'] = 'https://example.com';
      (second['type'] as TdObject)['url'] = 'https://example.com';
      const runs = parseFormattedText('abcdef', [first, second])[0].runs;
      expect(runs.length).assertEqual(2);
      expect(runs[0].text).assertEqual('abc');
      expect(runs[1].text).assertEqual('def');
      expect(runs[0].url).assertEqual(runs[1].url);
    });
    it('empty_first_link_target_does_not_fall_through_to_later_link', 0, () => {
      const first = entity(0, 4, 'textEntityTypeMentionName');
      const second = entity(0, 4, 'textEntityTypeTextUrl');
      (second['type'] as TdObject)['url'] = 'https://example.com';
      const runs = parseFormattedText('text', [first, second, entity(1, 2, 'textEntityTypeBold')])[0].runs;
      expect(runs.length).assertEqual(3);
      for (const run of runs) {
        expect(run.link).assertTrue();
        expect(run.url).assertEqual('');
      }
    });
    it('first_link_and_last_custom_emoji_keep_original_entity_precedence', 0, () => {
      const first = entity(0, 2, 'textEntityTypeTextUrl');
      const second = entity(0, 2, 'textEntityTypeTextUrl');
      const emojiA = entity(0, 2, 'textEntityTypeCustomEmoji');
      const emojiB = entity(0, 2, 'textEntityTypeCustomEmoji');
      (first['type'] as TdObject)['url'] = 'https://example.com/a';
      (second['type'] as TdObject)['url'] = 'https://example.com/b';
      (emojiA['type'] as TdObject)['custom_emoji_id'] = '100';
      (emojiB['type'] as TdObject)['custom_emoji_id'] = '200';
      const run = parseFormattedText('😀', [first, emojiA, second, emojiB])[0].runs[0];
      expect(run.url).assertEqual('https://example.com/a');
      expect(run.customEmojiId).assertEqual('200');
    });
    it('block_separators_trim_before_equivalent_runs_are_compacted', 0, () => {
      const text = 'head\n\nbody\n\ntail';
      const segments = parseFormattedText(text, [
        entity(6, 4, 'textEntityTypeBlockQuote'),
        entity(0, text.length, 'textEntityTypeBold'),
        entity(1, 2, 'textEntityTypeBold'), entity(7, 2, 'textEntityTypeBold')
      ]);
      expect(segments.length).assertEqual(3);
      expect(segments[0].runs.length).assertEqual(1);
      expect(segments[0].runs[0].text).assertEqual('head');
      expect(segments[1].kind).assertEqual('quote');
      expect(segments[1].runs.length).assertEqual(1);
      expect(segments[1].runs[0].text).assertEqual('body');
      expect(segments[2].runs[0].text).assertEqual('tail');
      expect(segments[2].isLast).assertTrue();
    });
    it('plain_caption_detection_keeps_whitespace_and_emoji_but_rejects_all_link_kinds', 0, () => {
      expect(isUnformattedPlainText('  第一行\n😀 第二行\n', [])).assertTrue();
      for (const text of ['t.me/example', 'www.example.com', 'a@example.com', '@alice', '#话题', '$USD']) {
        expect(isUnformattedPlainText(text, [])).assertFalse();
      }
      expect(isUnformattedPlainText('spoiler', [entity(0, 7, 'textEntityTypeSpoiler')])).assertFalse();
      expect(isUnformattedPlainText('code', [entity(0, 4, 'textEntityTypePre')])).assertFalse();
    });
    it('cached_segment_key_keeps_index_and_parse_identity_semantics', 0, () => {
      const entities: TdObject[] = [entity(0, 3, 'textEntityTypeBold')];
      const first = parseFormattedText('one', entities);
      const key = richSegmentKey(0, first[0]);
      expect(parseFormattedText('one', entities) === first).assertTrue();
      expect(richSegmentKey(0, first[0])).assertEqual(key);
      expect(richSegmentKey(1, first[0]) === key).assertFalse();
      const edited = parseFormattedText('two', entities);
      expect(edited === first).assertFalse();
      expect(richSegmentKey(0, edited[0]) === key).assertFalse();
      expect(richSegmentKey(0, first[0])).assertEqual(key);
    });
    it('same_text_with_changed_link_uses_a_new_key_after_cache_hit', 0, () => {
      const a = entity(0, 4, 'textEntityTypeTextUrl');
      const b = entity(0, 4, 'textEntityTypeTextUrl');
      (a['type'] as TdObject)['url'] = 'https://example.com/a';
      (b['type'] as TdObject)['url'] = 'https://example.com/b';
      const first = parseFormattedText('link', [a])[0];
      const next = parseFormattedText('link', [b])[0];
      const key = richSegmentKey(0, first);
      expect(richSegmentKey(0, first)).assertEqual(key);
      expect(richSegmentKey(0, next) === key).assertFalse();
    });
    it('same_text_with_changed_style_or_spoiler_uses_a_new_key', 0, () => {
      const bold = parseFormattedText('text', [entity(0, 4, 'textEntityTypeBold')])[0];
      const italic = parseFormattedText('text', [entity(0, 4, 'textEntityTypeItalic')])[0];
      const spoiler = parseFormattedText('text', [entity(0, 4, 'textEntityTypeSpoiler')])[0];
      const key = richSegmentKey(0, bold);
      expect(richSegmentKey(0, bold)).assertEqual(key);
      expect(richSegmentKey(0, italic) === key).assertFalse();
      expect(richSegmentKey(0, spoiler) === key).assertFalse();
    });
    it('same_emoji_text_with_changed_custom_emoji_identity_uses_a_new_key', 0, () => {
      const a = entity(0, 2, 'textEntityTypeCustomEmoji');
      const b = entity(0, 2, 'textEntityTypeCustomEmoji');
      (a['type'] as TdObject)['custom_emoji_id'] = '100';
      (b['type'] as TdObject)['custom_emoji_id'] = '200';
      const first = parseFormattedText('😀', [a])[0];
      const next = parseFormattedText('😀', [b])[0];
      const key = richSegmentKey(0, first);
      expect(richSegmentKey(0, first)).assertEqual(key);
      expect(richSegmentKey(0, next) === key).assertFalse();
    });
    it('translated_text_creates_an_independent_segment_fingerprint', 0, () => {
      const original = parseFormattedText('hello', [entity(0, 5, 'textEntityTypeBold')])[0];
      const translated = parseFormattedText('你好', [entity(0, 2, 'textEntityTypeBold')])[0];
      const key = richSegmentKey(0, original);
      expect(richSegmentKey(0, translated) === key).assertFalse();
      expect(richSegmentKey(0, original)).assertEqual(key);
    });
    it('caller_created_mutable_segments_are_not_fingerprint_cached', 0, () => {
      const segment: RichSegment = {
        kind: 'pre', runs: [], text: 'before', offset: 0,
        expandable: false, language: 'ts', isLast: true
      };
      const first = richSegmentKey(0, segment);
      segment.text = 'after';
      expect(richSegmentKey(0, segment) === first).assertFalse();
    });
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

    // 【文图对不上】分段那一层的 ForEach 键原来是 `seg_${i}_${seg.kind}`，而 kind
    // 只有三种取值。一个「每条都是一段带话题标签的纯文本」的频道里，两条**内容
    // 完全不同**的消息算出的键逐字相同 → ForEach 判定没变化 → 不重跑分段的构建
    // 函数 → 里面那个按 run 分的 ForEach（键里带全文）连求值的机会都没有，正文
    // 停在上一条消息上。而相册的图已经按身份重建了，两边错开就是「图是这一条的、
    // 字是上一条的」。
    it('两条结构相同但内容不同的消息，分段键必须不同', 0, () => {
      const a: RichSegment[] = parseFormattedText('#北京 #十里堡 身高168体重50kg', []);
      const b: RichSegment[] = parseFormattedText('#丰台 #宋家庄 身高160体重45kg', []);
      expect(a.length).assertEqual(b.length);
      expect(a[0].kind).assertEqual(b[0].kind);
      // 老写法：`seg_0_${kind}` —— 两条一模一样，这正是那个 bug。
      expect(`seg_0_${a[0].kind}`).assertEqual(`seg_0_${b[0].kind}`);
      // 新写法必须分得开。
      expect(richSegmentKey(0, a[0]) === richSegmentKey(0, b[0])).assertFalse();
    });

    // 反向不变式：同一段内容重新解析必须得到同一个键，否则每帧都在重建正文节点。
    it('同一段内容的分段键稳定', 0, () => {
      const text: string = '#朝阳 #青年路 备注：龙哥';
      const first: RichSegment[] = parseFormattedText(text, []);
      const again: RichSegment[] = parseFormattedText(text, []);
      expect(richSegmentKey(0, first[0])).assertEqual(richSegmentKey(0, again[0]));
    });

    // 指纹要能分辨「同样的字符换个断法」——'ab'+'c' 不能和 'a'+'bc' 撞。
    it('分段键的指纹带分隔符', 0, () => {
      const one: RichSegment = {
        kind: 'text', text: '', offset: 0, expandable: false, language: '', isLast: true,
        runs: [
          { offset: 0, text: 'ab', bold: false, italic: false, underline: false, strike: false,
            code: false, spoiler: false, customEmojiId: '', link: false, url: '' },
          { offset: 2, text: 'c', bold: false, italic: false, underline: false, strike: false,
            code: false, spoiler: false, customEmojiId: '', link: false, url: '' }
        ]
      };
      const two: RichSegment = {
        kind: 'text', text: '', offset: 0, expandable: false, language: '', isLast: true,
        runs: [
          { offset: 0, text: 'a', bold: false, italic: false, underline: false, strike: false,
            code: false, spoiler: false, customEmojiId: '', link: false, url: '' },
          { offset: 1, text: 'bc', bold: false, italic: false, underline: false, strike: false,
            code: false, spoiler: false, customEmojiId: '', link: false, url: '' }
        ]
      };
      expect(richSegmentKey(0, one) === richSegmentKey(0, two)).assertFalse();
    });
  });
}
