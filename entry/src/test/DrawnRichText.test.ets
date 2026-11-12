import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { parseFormattedText, RichSegment } from '../main/ets/util/richText';
import { drawnRichSegmentSource, appendDrawnRichHits, DrawnRichHit, DrawnRichLink, DrawnRichRect, DrawnRichSourceCache } from '../main/ets/util/drawnRichTextPolicy';

function richEntity(kind: string, offset: number, length: number, url: string = ''): TdObject {
  const type: TdObject = { '@type': `textEntityType${kind}` };
  if (kind === 'TextUrl') { type['url'] = url; }
  if (kind === 'CustomEmoji') { type['custom_emoji_id'] = '123'; }
  const result: TdObject = { '@type': 'textEntity' };
  result['offset'] = offset; result['length'] = length; result['type'] = type;
  return result;
}

function richTestLink(): DrawnRichLink {
  return { start: 0, end: 4, label: 'link', url: 'https://a.example', hidesUrl: true,
    accessibilityLabel: 'link', accessibilityFirst: true };
}

export default function drawnRichTextTest(): void {
  describe('DrawnRichText', (): void => {
    it('fallback_reason_is_cached_without_reparsing_or_changing_eligibility', 0, (): void => {
      let calls: number = 0;
      const cache = new DrawnRichSourceCache((content: string, entities: TdObject[]): RichSegment[] => {
        calls++; return parseFormattedText(content, entities);
      });
      const emoji: TdObject[] = [richEntity('Spoiler', 0, 2)];
      const plain: TdObject[] = [];
      expect(cache.prepare('😀 body', emoji) === null).assertTrue();
      expect(cache.reason).assertEqual('spoiler');
      for (let i: number = 0; i < 1000; i++) { cache.prepare('😀 body', emoji); }
      expect(calls).assertEqual(1);
      expect(cache.prepare('body', plain) !== null).assertTrue();
      expect(cache.reason).assertEqual('');
      expect(cache.prepare('😀 body', emoji) === null).assertTrue();
      expect(cache.reason).assertEqual('spoiler');
      expect(calls).assertEqual(2);
      expect(cache.prepare('a\tb', plain) === null).assertTrue();
      expect(cache.reason).assertEqual('direction-or-control:U+9');
      expect(calls).assertEqual(2);
      expect(cache.prepare('code', [richEntity('Code', 0, 4)]) === null).assertTrue();
      expect(cache.reason).assertEqual('inline-code');
    });
    it('ordinary_blocks_draw_independently_of_neighboring_quotes', 0, (): void => {
      const text: string = 'first\nquote\nlast';
      const segments = parseFormattedText(text, [richEntity('BlockQuote', 6, 5),
        richEntity('TextUrl', 12, 4, 'https://example.org/last')]);
      expect(segments.length).assertEqual(3);
      expect(drawnRichSegmentSource(segments[0])?.content).assertEqual('first');
      expect(drawnRichSegmentSource(segments[1]) === null).assertTrue();
      const last = drawnRichSegmentSource(segments[2]);
      expect(last?.content).assertEqual('last');
      expect(last?.links[0].start).assertEqual(0);
      expect(last?.links[0].end).assertEqual(4);
      expect(last?.links[0].url).assertEqual('https://example.org/last');
      expect(segments[2].runs[0].offset).assertEqual(12);
      for (let i: number = 0; i < 1000; i++) {
        expect(drawnRichSegmentSource(segments[2]) === last).assertTrue();
      }
    });
    it('segment_source_preserves_unicode_styling_and_spoken_link_grouping', 0, (): void => {
      const segments = parseFormattedText('😀abc', [richEntity('TextUrl', 0, 5, 'https://example.org'),
        richEntity('Bold', 2, 1)]);
      const source = drawnRichSegmentSource(segments[0]);
      expect(source?.runs[1].offset).assertEqual(2);
      expect(source?.runs[1].bold).assertTrue();
      expect(source?.links[0].accessibilityLabel).assertEqual('😀abc');
      expect(source?.links[1].accessibilityFirst).assertFalse();
    });
    it('custom_emoji_preserves_original_offsets_and_link_semantics', 0, (): void => {
      const source = new DrawnRichSourceCache().prepare('😀 link 🎬', [richEntity('CustomEmoji', 0, 2),
        richEntity('CustomEmoji', 8, 2), richEntity('TextUrl', 3, 4, 'https://example.org')]);
      expect(source !== null).assertTrue();
      expect(source?.content).assertEqual('😀 link 🎬');
      expect(source?.runs[0].customEmojiId).assertEqual('123');
      expect(source?.links[0].start).assertEqual(3);
      expect(source?.links[0].end).assertEqual(7);
      const segment = parseFormattedText('😀', [richEntity('CustomEmoji', 0, 2)])[0];
      expect(drawnRichSegmentSource(segment)?.runs[0].customEmojiId).assertEqual('123');
    });
    it('segment_source_keeps_unsupported_inline_content_on_native_path', 0, (): void => {
      for (const kind of ['Spoiler', 'Code']) {
        const segment = parseFormattedText('word', [richEntity(kind, 0, 4)])[0];
        expect(drawnRichSegmentSource(segment) === null).assertTrue();
        expect(drawnRichSegmentSource(segment) === null).assertTrue();
      }
      expect(drawnRichSegmentSource(parseFormattedText('مرحبا', [])[0]) === null).assertTrue();
    });
    it('segment_edits_do_not_reuse_previous_link_target_or_style', 0, (): void => {
      const first = drawnRichSegmentSource(parseFormattedText('link', [
        richEntity('TextUrl', 0, 4, 'https://a.example')])[0]);
      const second = drawnRichSegmentSource(parseFormattedText('link', [
        richEntity('TextUrl', 0, 4, 'https://b.example'), richEntity('Bold', 0, 4)])[0]);
      expect(first === second).assertFalse();
      expect(first?.links[0].url).assertEqual('https://a.example');
      expect(second?.links[0].url).assertEqual('https://b.example');
      expect(second?.runs[0].bold).assertTrue();
    });
    it('repeated unchanged input prepares once and reuses source identity', 0, (): void => {
      let calls: number = 0;
      const cache = new DrawnRichSourceCache((s: string, e: TdObject[]): RichSegment[] => {
        calls++; return parseFormattedText(s, e);
      });
      const entities: TdObject[] = [richEntity('Bold', 0, 4)];
      const first = cache.prepare('bold text', entities);
      for (let i: number = 0; i < 1000; i++) { expect(cache.prepare('bold text', entities) === first).assertTrue(); }
      expect(calls).assertEqual(1);
      expect(first?.runs[0].bold).assertTrue();
    });
    it('unsupported results are cached instead of repeatedly parsed', 0, (): void => {
      let calls: number = 0;
      const cache = new DrawnRichSourceCache((s: string, e: TdObject[]): RichSegment[] => {
        calls++; return parseFormattedText(s, e);
      });
      const entities: TdObject[] = [richEntity('Spoiler', 0, 4)];
      for (let i: number = 0; i < 100; i++) { expect(cache.prepare('hide', entities) === null).assertTrue(); }
      expect(calls).assertEqual(1);
    });
    it('bounded source cache reuses A B A and evicts the least recently used entry', 0, (): void => {
      let calls: number = 0;
      const cache = new DrawnRichSourceCache((s: string, e: TdObject[]): RichSegment[] => {
        calls++; return parseFormattedText(s, e);
      });
      const entities: TdObject[] = [];
      const first = cache.prepare('a', entities);
      cache.prepare('b', entities); cache.prepare('c', entities); cache.prepare('d', entities);
      expect(cache.prepare('a', entities) === first).assertTrue(); expect(calls).assertEqual(4);
      cache.prepare('e', entities); cache.prepare('b', entities);
      expect(calls).assertEqual(6);
    });
    it('same text with swapped link targets cannot retain old tap metadata', 0, (): void => {
      const cache = new DrawnRichSourceCache();
      const first = cache.prepare('one two', [richEntity('TextUrl', 0, 3, 'a'), richEntity('TextUrl', 4, 3, 'b')]);
      const next = cache.prepare('one two', [richEntity('TextUrl', 0, 3, 'b'), richEntity('TextUrl', 4, 3, 'a')]);
      expect(first !== next).assertTrue();
      expect(first?.links[0].url).assertEqual('a');
      expect(next?.links[0].url).assertEqual('b');
      expect(next?.links[1].url).assertEqual('a');
    });
    it('styles change with entity identity even when body stays unchanged', 0, (): void => {
      const cache = new DrawnRichSourceCache();
      const bold = cache.prepare('same', [richEntity('Bold', 0, 4)]);
      const italic = cache.prepare('same', [richEntity('Italic', 0, 4)]);
      expect(bold?.runs[0].bold).assertTrue();
      expect(italic?.runs[0].bold).assertFalse(); expect(italic?.runs[0].italic).assertTrue();
    });
    it('edited text invalidates even with the same entity array', 0, (): void => {
      const cache = new DrawnRichSourceCache(); const entities: TdObject[] = [];
      const first = cache.prepare('https://a.example', entities);
      const next = cache.prepare('https://b.example', entities);
      expect(first?.links[0].url).assertEqual('https://a.example');
      expect(next?.links[0].url).assertEqual('https://b.example');
    });
    it('CJK and surrogate pairs preserve UTF16 link offsets', 0, (): void => {
      const body: string = '中文😀 link';
      const prepared = new DrawnRichSourceCache().prepare(body, [richEntity('TextUrl', 5, 4, 'target')]);
      expect(prepared?.links[0].start).assertEqual(5); expect(prepared?.links[0].end).assertEqual(9);
      expect(prepared?.links[0].label).assertEqual('link');
    });
    it('styled parts of a continuous link have one spoken entry and original click semantics', 0, (): void => {
      const entities: TdObject[] = [richEntity('TextUrl', 0, 9, 'https://a.example'), richEntity('Bold', 3, 3)];
      const before = JSON.stringify(parseFormattedText('abcDEFghi', entities));
      const prepared = new DrawnRichSourceCache().prepare('abcDEFghi', entities);
      expect(prepared?.links.length).assertEqual(3);
      expect(prepared?.links[0].accessibilityLabel).assertEqual('abcDEFghi');
      expect(prepared?.links[0].accessibilityFirst).assertTrue();
      expect(prepared?.links[1].accessibilityFirst).assertFalse();
      expect(prepared?.links[2].accessibilityFirst).assertFalse();
      expect(JSON.stringify(parseFormattedText('abcDEFghi', entities))).assertEqual(before);
    });
    it('separate occurrences of the same URL remain independently accessible', 0, (): void => {
      const prepared = new DrawnRichSourceCache().prepare('one two',
        [richEntity('TextUrl', 0, 3, 'target'), richEntity('TextUrl', 4, 3, 'target')]);
      expect(prepared?.links[0].accessibilityFirst).assertTrue();
      expect(prepared?.links[1].accessibilityFirst).assertTrue();
      expect(prepared?.targets.size).assertEqual(1);
    });
    it('hidden targets retain confirmation while ordinary URL does not', 0, (): void => {
      const cache = new DrawnRichSourceCache();
      expect(cache.prepare('https://a.example', [])?.links[0].hidesUrl).assertFalse();
      expect(cache.prepare('click', [richEntity('TextUrl', 0, 5, 'https://a.example')])?.links[0].hidesUrl).assertTrue();
    });
    it('code spoiler and block formatting preserve native rendering', 0, (): void => {
      const cache = new DrawnRichSourceCache();
      for (const kind of ['Code', 'Spoiler', 'Pre', 'PreCode', 'BlockQuote', 'ExpandableBlockQuote']) {
        expect(cache.prepare('text', [richEntity(kind, 0, 4)]) === null).assertTrue();
      }
    });
    it('caps input and keeps bidi tabs and empty text on the native path', 0, (): void => {
      const cache = new DrawnRichSourceCache();
      for (const s of ['', 'a\tb', 'hello\u202eworld', 'مرحبا', 'x'.repeat(16385)]) {
        expect(cache.prepare(s, []) === null).assertTrue();
      }
    });
    it('121 runs are supported without changing parser boundaries', 0, (): void => {
      const body = 'x '.repeat(121); const entities: TdObject[] = [];
      for (let i: number = 0; i < 121; i++) { entities.push(richEntity('TextUrl', i * 2, 1, `https://x/${i}`)); }
      const prepared = new DrawnRichSourceCache().prepare(body, entities);
      expect(prepared?.links.length).assertEqual(121);
      expect(prepared?.runs.map((r): string => r.text).join('')).assertEqual(body);
      expect(prepared?.links[120].url).assertEqual('https://x/120');
    });
    it('multiline link rectangles retain exact gaps and convert px to vp', 0, (): void => {
      const hits: DrawnRichHit[] = [];
      expect(appendDrawnRichHits(hits, [
        { left: 20, top: 0, right: 100, bottom: 20 }, { left: 0, top: 24, right: 30, bottom: 44 }
      ], richTestLink(), 2, 120, 60, 1)).assertTrue();
      expect(hits.length).assertEqual(2); expect(hits[0].x).assertEqual(10);
      expect(hits[0].widthVp).assertEqual(40); expect(hits[1].widthVp).assertEqual(15);
      expect(hits[0].accessible).assertTrue(); expect(hits[1].accessible).assertFalse();
    });
    it('missing or invalid link geometry requires native fallback', 0, (): void => {
      expect(appendDrawnRichHits([], [], richTestLink(), 2, 100, 100, 1)).assertFalse();
      expect(appendDrawnRichHits([], [{ left: 0, top: 0, right: 0, bottom: 10 }], richTestLink(), 2, 100, 100, 1)).assertFalse();
      expect(appendDrawnRichHits([], [{ left: 0, top: 0, right: Number.NaN, bottom: 10 }], richTestLink(), 2, 100, 100, 1)).assertFalse();
    });
    it('new layout generations replace captured link handlers', 0, (): void => {
      const a: DrawnRichHit[] = []; const b: DrawnRichHit[] = [];
      const boxes: DrawnRichRect[] = [{ left: 0, top: 0, right: 20, bottom: 20 }];
      appendDrawnRichHits(a, boxes, richTestLink(), 2, 100, 100, 1);
      appendDrawnRichHits(b, boxes, richTestLink(), 2, 100, 100, 2);
      expect(a[0].key === b[0].key).assertFalse();
    });
  });
}
