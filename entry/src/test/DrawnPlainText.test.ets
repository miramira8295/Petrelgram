import { describe, expect, it } from '@ohos/hypium';
import {
  drawnPlainTextEligible, drawnChromeTextSupported, drawnReplyHit, drawnTailGutter, DrawnPlainLayoutCache, DrawnPlainTextSpec,
  sameDrawnPlainTextSpec, sameDrawnPlainParagraphSpec, snapshotDrawnPlainTextSpec
} from '../main/ets/util/drawnPlainTextPolicy';
import { linkifyRuns, hasPlainTextLink, PlainTextLinkPresenceCache } from '../main/ets/util/linkify';
import { RichRun } from '../main/ets/util/richText';

function eligible(content: string): boolean {
  return drawnPlainTextEligible(content, false, false, 0, false, '',
    hasPlainTextLink(content));
}

function layoutSpec(): DrawnPlainTextSpec {
  return {
    content: 'ordinary text', time: '12:34', edited: '', maxWidthVp: 280, fontSize: 16,
    outgoing: true, tail: true, topLeft: 16, topRight: 16, bottomRight: 16, bottomLeft: 16,
    fill: '#ffffff', foreground: '#000000', secondary: '#888888', accent: '#3390ec', environment: '0', textEnvironment: 'font0:locale0'
  };
}

export default function drawnPlainTextTest() {
  describe('DrawnPlainText', () => {
    it('draws CJK multiline Latin and emoji without stripping content', 0, () => {
      expect(eligible('你好\nHello 👨‍👩‍👧‍👦👍🏽')).assertTrue();
      expect(eligible('一行\n')).assertTrue();
    });
    it('keeps detected web links on the interactive renderer', 0, () => {
      expect(eligible('打开 https://t.me/example')).assertFalse();
    });
    it('keeps glass bubbles on the material renderer', 0, () => {
      expect(drawnPlainTextEligible('hello', true, false, 0, false, '', false)).assertFalse();
    });
    it('allows sender headers with their dedicated role subscription', 0, () => {
      expect(drawnPlainTextEligible('hello', false, true, 0, false, '', false)).assertTrue();
    });
    it('allows replies with their dedicated hit target', 0, () => {
      expect(drawnPlainTextEligible('hello', false, false, 99, false, '', false)).assertTrue();
    });
    it('supports empty and multiline quote summaries without changing stored text', 0, () => {
      expect(drawnChromeTextSupported('')).assertTrue();
      expect(drawnChromeTextSupported('管理员 👨‍👩‍👧‍👦')).assertTrue();
      expect(drawnChromeTextSupported('first\nsecond')).assertTrue();
    });
    it('bounds chrome text and preserves unsupported direction and tab behavior', 0, () => {
      expect(drawnChromeTextSupported('x'.repeat(4096))).assertTrue();
      expect(drawnChromeTextSupported('x'.repeat(4097))).assertFalse();
      expect(drawnChromeTextSupported('مرحبا')).assertFalse();
      expect(drawnChromeTextSupported('x\u202ey')).assertFalse();
      expect(drawnChromeTextSupported('x\ty')).assertFalse();
    });
    it('quote hit testing converts vp to pixels and excludes adjacent body text', 0, () => {
      expect(drawnReplyHit(14, 30, 28, 60, 200, 76, 2)).assertTrue();
      expect(drawnReplyHit(113, 67, 28, 60, 200, 76, 2)).assertTrue();
      expect(drawnReplyHit(114, 30, 28, 60, 200, 76, 2)).assertFalse();
      expect(drawnReplyHit(14, 68, 28, 60, 200, 76, 2)).assertFalse();
      expect(drawnReplyHit(13, 30, 28, 60, 200, 76, 2)).assertFalse();
      expect(drawnReplyHit(14, 29, 28, 60, 200, 76, 2)).assertFalse();
    });
    it('unmeasured quote rectangles do not swallow a bubble click', 0, () => {
      expect(drawnReplyHit(0, 0, 0, 0, 0, 76, 2)).assertFalse();
      expect(drawnReplyHit(0, 0, 0, 0, 100, 0, 2)).assertFalse();
      expect(drawnReplyHit(0, 0, 0, 0, 100, 76, 0)).assertFalse();
    });
    it('falls back for translating and channel view labels', 0, () => {
      expect(drawnPlainTextEligible('hello', false, false, 0, true, '', false)).assertFalse();
      expect(drawnPlainTextEligible('hello', false, false, 0, false, '1K', false)).assertFalse();
    });
    it('preserves bidi controls RTL content and RTL application layout', 0, () => {
      expect(eligible('مرحبا')).assertFalse();
      expect(eligible('hello\u202eworld')).assertFalse();
      expect(eligible('hello\u2067world\u2069')).assertFalse();
      expect(drawnPlainTextEligible('hello', false, false, 0, false, '', false, true)).assertFalse();
    });
    it('bounds paragraph caching and preserves native tab layout', 0, () => {
      expect(eligible('')).assertFalse();
      expect(eligible('x'.repeat(4096))).assertTrue();
      expect(eligible('x'.repeat(4097))).assertFalse();
      expect(eligible('a\tb')).assertFalse();
    });
    it('matches the existing solid tail overlap and tail-less spacer', 0, () => {
      expect(drawnTailGutter(true)).assertEqual(8 - 2);
      expect(drawnTailGutter(false)).assertEqual(7);
    });
    it('keeps cached layouts on status and scroll-only updates', 0, () => {
      const cache = new DrawnPlainLayoutCache<string, number>((a: string, b: string): boolean => a === b);
      cache.prepare('theme0:language0:config0:3:48:33');
      cache.put('message:width', 7);
      cache.prepare('theme0:language0:config0:3:48:33');
      expect(cache.get('message:width')).assertEqual(7);
    });
    it('invalidates native paragraphs after configuration or theme changes', 0, () => {
      const cache = new DrawnPlainLayoutCache<string, number>((a: string, b: string): boolean => a === b);
      cache.prepare('config0');
      cache.put('message', 1);
      cache.prepare('config1');
      expect(cache.get('message') === undefined).assertTrue();
    });
    it('evicts the least recently used layout and separates edited content', 0, () => {
      const cache = new DrawnPlainLayoutCache<string, number>((a: string, b: string): boolean => a === b, 2);
      cache.put('before-edit', 1);
      cache.put('after-edit', 2);
      expect(cache.get('before-edit')).assertEqual(1);
      cache.put('narrow-width', 3);
      expect(cache.get('after-edit') === undefined).assertTrue();
      expect(cache.get('before-edit')).assertEqual(1);
      expect(cache.get('narrow-width')).assertEqual(3);
    });
    it('link presence agrees with full parsing at URL and mention boundaries', 0, () => {
      const samples: string[] = ['', 'hello', '@ab', '@abc', '@' + 'x'.repeat(33),
        'https://', 'https://example.com/a?q=b#c', 'HTTP://example.com', 'http://a\nb',
        't.me/a', 'telegram.me/@example', 'telegram.dog/+a-b', 'www.example.com',
        '你好 https://a.example 好', 'test@example.com', '前缀t.me/x',
        'https://a.example http://b.example @name', 'x'.repeat(4096)];
      for (const content of samples) {
        expect(hasPlainTextLink(content)).assertEqual(
          linkifyRuns(content, []).some((run: RichRun): boolean => run.link));
      }
    });
    it('early detection preserves all links and their original URLs', 0, () => {
      const content: string = 'https://one.example t.me/two @three';
      expect(hasPlainTextLink(content)).assertTrue();
      const links: RichRun[] = linkifyRuns(content, []).filter((run: RichRun): boolean => run.link);
      expect(links.length).assertEqual(3);
      expect(links[0].url).assertEqual('https://one.example');
      expect(links[1].url).assertEqual('https://t.me/two');
      expect(links[2].url).assertEqual('@three');
    });
    it('boolean tests do not share a global regex cursor with full rendering', 0, () => {
      for (let i: number = 0; i < 20; i++) {
        expect(hasPlainTextLink('@alice')).assertTrue();
        expect(hasPlainTextLink('no links')).assertFalse();
        expect(linkifyRuns('https://one https://two', []).filter((r: RichRun): boolean => r.link).length)
          .assertEqual(2);
      }
    });
    it('presence cache follows text edits including same-length replacements', 0, () => {
      const cache = new PlainTextLinkPresenceCache();
      expect(cache.hasLink('')).assertFalse();
      expect(cache.hasLink('@alice')).assertTrue();
      expect(cache.hasLink('@alice')).assertTrue();
      expect(cache.hasLink('xxxxxx')).assertFalse();
      expect(cache.hasLink('xxxxxx')).assertFalse();
      expect(cache.hasLink('@alice')).assertTrue();
      expect(cache.hasLink('')).assertFalse();
    });
    it('field cache hits for freshly constructed equivalent specs without serialization', 0, () => {
      const cache = new DrawnPlainLayoutCache<DrawnPlainTextSpec, number>(sameDrawnPlainTextSpec);
      cache.put(snapshotDrawnPlainTextSpec(layoutSpec()), 7);
      expect(cache.get(layoutSpec())).assertEqual(7);
    });
    it('every layout-affecting field invalidates independently', 0, () => {
      const changes: Array<(spec: DrawnPlainTextSpec) => void> = [
        (spec: DrawnPlainTextSpec): void => { spec.content = 'edited text'; },
        (spec: DrawnPlainTextSpec): void => { spec.time = '12:35'; },
        (spec: DrawnPlainTextSpec): void => { spec.edited = 'edited'; },
        (spec: DrawnPlainTextSpec): void => { spec.maxWidthVp = 240; },
        (spec: DrawnPlainTextSpec): void => { spec.fontSize = 18; },
        (spec: DrawnPlainTextSpec): void => { spec.outgoing = false; },
        (spec: DrawnPlainTextSpec): void => { spec.tail = false; },
        (spec: DrawnPlainTextSpec): void => { spec.topLeft = 7; },
        (spec: DrawnPlainTextSpec): void => { spec.topRight = 7; },
        (spec: DrawnPlainTextSpec): void => { spec.bottomRight = 7; },
        (spec: DrawnPlainTextSpec): void => { spec.bottomLeft = 7; },
        (spec: DrawnPlainTextSpec): void => { spec.fill = '#eeeeee'; },
        (spec: DrawnPlainTextSpec): void => { spec.foreground = '#333333'; },
        (spec: DrawnPlainTextSpec): void => { spec.secondary = '#777777'; },
        (spec: DrawnPlainTextSpec): void => { spec.accent = '#ff0000'; },
        (spec: DrawnPlainTextSpec): void => { spec.environment = '1'; },
        (spec: DrawnPlainTextSpec): void => { spec.textEnvironment = 'font1:locale0'; }
      ];
      const cache = new DrawnPlainLayoutCache<DrawnPlainTextSpec, number>(sameDrawnPlainTextSpec);
      cache.put(snapshotDrawnPlainTextSpec(layoutSpec()), 7);
      for (const change of changes) {
        const next = layoutSpec();
        change(next);
        expect(cache.get(next) === undefined).assertTrue();
      }
    });
    it('snapshot prevents mutated input from making a stale layout look current', 0, () => {
      const spec = layoutSpec();
      const cache = new DrawnPlainLayoutCache<DrawnPlainTextSpec, number>(sameDrawnPlainTextSpec);
      cache.put(snapshotDrawnPlainTextSpec(spec), 7);
      spec.content = 'different text';
      spec.maxWidthVp = 180;
      expect(cache.get(spec) === undefined).assertTrue();
      expect(cache.get(layoutSpec())).assertEqual(7);
    });
    it('compares full string values without lossy hashes or delimiter collisions', 0, () => {
      const first = layoutSpec();
      first.content = 'a:"b"\n👩‍💻';
      const other = snapshotDrawnPlainTextSpec(first);
      expect(sameDrawnPlainTextSpec(first, other)).assertTrue();
      other.content = 'a:"c"\n👩‍💻';
      expect(sameDrawnPlainTextSpec(first, other)).assertFalse();
    });
    it('replacement does not consume extra cache slots', 0, () => {
      const cache = new DrawnPlainLayoutCache<DrawnPlainTextSpec, number>(sameDrawnPlainTextSpec, 2);
      const second = layoutSpec();
      second.content = 'second';
      cache.put(snapshotDrawnPlainTextSpec(layoutSpec()), 1);
      cache.put(snapshotDrawnPlainTextSpec(second), 2);
      cache.put(snapshotDrawnPlainTextSpec(layoutSpec()), 3);
      expect(cache.get(layoutSpec())).assertEqual(3);
      expect(cache.get(second)).assertEqual(2);
    });
    it('shell and paint changes reuse the same paragraph geometry', 0, () => {
      const original = layoutSpec();
      const decorated = snapshotDrawnPlainTextSpec(original);
      decorated.tail = false;
      decorated.topLeft = 3; decorated.topRight = 4;
      decorated.bottomLeft = 5; decorated.bottomRight = 6;
      decorated.fill = '#112233'; decorated.foreground = '#ffffff';
      decorated.secondary = '#cccccc'; decorated.accent = '#33ff00';
      decorated.environment = 'appearance1';
      expect(sameDrawnPlainParagraphSpec(original, decorated)).assertTrue();
      expect(sameDrawnPlainTextSpec(original, decorated)).assertFalse();
    });
    it('text layout inputs still invalidate the paragraph cache', 0, () => {
      const changes: Array<(spec: DrawnPlainTextSpec) => void> = [
        (spec: DrawnPlainTextSpec): void => { spec.content = 'edited'; },
        (spec: DrawnPlainTextSpec): void => { spec.time = '23:59'; },
        (spec: DrawnPlainTextSpec): void => { spec.edited = 'edited'; },
        (spec: DrawnPlainTextSpec): void => { spec.maxWidthVp = 180; },
        (spec: DrawnPlainTextSpec): void => { spec.fontSize = 20; },
        (spec: DrawnPlainTextSpec): void => { spec.outgoing = false; },
        (spec: DrawnPlainTextSpec): void => { spec.textEnvironment = 'font1:locale0'; }
      ];
      for (const change of changes) {
        const next = layoutSpec();
        change(next);
        expect(sameDrawnPlainParagraphSpec(layoutSpec(), next)).assertFalse();
      }
    });
    it('font environment snapshots stay isolated from mutable input', 0, () => {
      const original = layoutSpec();
      const saved = snapshotDrawnPlainTextSpec(original);
      original.textEnvironment = 'font1:locale1';
      expect(saved.textEnvironment).assertEqual('font0:locale0');
      expect(sameDrawnPlainParagraphSpec(original, saved)).assertFalse();
    });
  });
}
