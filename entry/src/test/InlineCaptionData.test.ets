import { describe, expect, it } from '@ohos/hypium';
import { InlineCaptionCache } from '../main/ets/util/inlineCaptionData';
import { parseFormattedText, RichSegment, richSegmentKey } from '../main/ets/util/richText';
import { TdObject } from '../main/ets/tdkit/TdTypes';

function entity(kind: string, offset: number, length: number, target: string = ''): TdObject {
  const type: TdObject = { '@type': `textEntityType${kind}` };
  if (kind === 'TextUrl') { type['url'] = target; }
  if (kind === 'CustomEmoji') { type['custom_emoji_id'] = target; }
  const value: TdObject = { '@type': 'textEntity' };
  value['offset'] = offset; value['length'] = length; value['type'] = type;
  return value;
}
function key(cache: InlineCaptionCache): string {
  return cache.runs().length > 0 ? cache.runs()[0].key : '';
}
export default function inlineCaptionDataTest(): void {
  describe('InlineCaptionData', (): void => {
    it('formatted_inline_caption_retains_exact_parser_runs', 0, (): void => {
      const entities: TdObject[] = [entity('Bold', 0, 4), entity('TextUrl', 5, 4, 'https://a.example')];
      const text = 'bold link'; const cache = new InlineCaptionCache();
      const expected = parseFormattedText(text, entities)[0];
      const segment = cache.prepare(text, entities);
      expect(segment === expected).assertTrue(); expect(cache.runs()[0].run === expected.runs[0]).assertTrue();
      expect(segment?.isLast).assertTrue(); expect(cache.prepare(text, entities) === segment).assertTrue();
    });
    it('automatic_links_and_newlines_keep_original_offsets_and_targets', 0, (): void => {
      const text = '第一行\nhttps://example.com'; const entities: TdObject[] = [];
      const cache = new InlineCaptionCache(); cache.prepare(text, entities);
      const runs = cache.runs().map((item) => item.run);
      expect(runs.map((r): string => r.text).join('')).assertEqual(text);
      expect(runs[runs.length - 1].url).assertEqual('https://example.com');
      expect(runs[runs.length - 1].offset).assertEqual(4);
    });
    it('code_quote_expandable_quote_and_mixed_blocks_use_full_renderer', 0, (): void => {
      const cache = new InlineCaptionCache();
      for (const kind of ['Pre', 'PreCode', 'BlockQuote', 'ExpandableBlockQuote']) {
        expect(cache.prepare('block', [entity(kind, 0, 5)]) === null).assertTrue();
        expect(cache.prepare('a block z', [entity(kind, 2, 5)]) === null).assertTrue();
      }
      expect(cache.runs().length).assertEqual(0);
    });
    it('same_text_changed_url_replaces_captured_click_handler_key', 0, (): void => {
      const cache = new InlineCaptionCache();
      cache.prepare('link', [entity('TextUrl', 0, 4, 'https://a.example')]); const first = cache.runs();
      cache.prepare('link', [entity('TextUrl', 0, 4, 'https://b.example')]); const next = cache.runs();
      expect(first[0].key === next[0].key).assertFalse();
      expect(first[0].run.url).assertEqual('https://a.example');
      expect(next[0].run.url).assertEqual('https://b.example');
    });
    it('same_text_changed_styles_spoiler_or_custom_emoji_replace_keys', 0, (): void => {
      const cache = new InlineCaptionCache(); cache.prepare('text', []); const plain = key(cache);
      for (const kind of ['Bold', 'Italic', 'Underline', 'Strikethrough', 'Code', 'Spoiler', 'CustomEmoji']) {
        cache.prepare('text', [entity(kind, 0, 4, '123')]);
        expect(key(cache) === plain).assertFalse();
      }
      cache.prepare('text', [entity('CustomEmoji', 0, 4, '123')]); const one = key(cache);
      cache.prepare('text', [entity('CustomEmoji', 0, 4, '456')]);
      expect(one === key(cache)).assertFalse();
    });
    it('new_text_and_block_to_inline_reuse_cannot_keep_previous_runs', 0, (): void => {
      const cache = new InlineCaptionCache(); const entities: TdObject[] = [];
      cache.prepare('before', entities); const old = cache.runs();
      cache.prepare('after', entities);
      expect(old[0].key === key(cache)).assertFalse(); expect(old[0].run.text).assertEqual('before');
      expect(cache.prepare('quote', [entity('BlockQuote', 0, 5)]) === null).assertTrue();
      cache.prepare('returned', entities); expect(cache.runs()[0].run.text).assertEqual('returned');
    });
    it('every_run_key_retains_segment_invalidation_and_run_position', 0, (): void => {
      const cache = new InlineCaptionCache();
      const first = cache.prepare('aa bb', [entity('Bold', 0, 2)]) as RichSegment;
      const old = cache.runs();
      for (let i = 0; i < old.length; i++) {
        expect(old[i].key).assertEqual(`${richSegmentKey(0, first)}|run_${i}_${old[i].run.offset}_${old[i].run.text}`);
      }
      cache.prepare('aa bb', [entity('Italic', 0, 2)]);
      // Even an unchanged trailing run must inherit changed segment formatting.
      expect(old[1].key === cache.runs()[1].key).assertFalse();
    });
    it('unchanged_source_reuses_prepared_items_and_keys', 0, (): void => {
      const cache = new InlineCaptionCache(); const entities = [entity('Bold', 0, 2)];
      cache.prepare('aa bb', entities); const items = cache.runs();
      for (let i = 0; i < 100; i++) {
        cache.prepare('aa bb', entities);
        expect(cache.runs() === items).assertTrue();
      }
    });
    it('block_transition_discards_previous_prepared_items', 0, (): void => {
      const cache = new InlineCaptionCache(); cache.prepare('link', [entity('TextUrl', 0, 4, 'https://a.example')]);
      const old = cache.runs(); cache.prepare('block', [entity('Pre', 0, 5)]);
      expect(cache.runs().length).assertEqual(0);
      cache.prepare('next', [entity('Bold', 0, 4)]);
      expect(cache.runs()[0].run.text).assertEqual('next');
      expect(old[0].run.url).assertEqual('https://a.example');
    });
    it('each_component_owns_only_its_latest_prepared_source', 0, (): void => {
      const one = new InlineCaptionCache(); const two = new InlineCaptionCache(); const entities: TdObject[] = [];
      one.prepare('first', entities); two.prepare('second', entities); const second = two.runs();
      for (let i = 0; i < 100; i++) { one.prepare(`caption ${i}`, entities); }
      expect(one.runs().length).assertEqual(1); expect(one.runs()[0].run.text).assertEqual('caption 99');
      expect(two.runs() === second).assertTrue(); expect(second[0].run.text).assertEqual('second');
    });
  });
}
