import { describe, expect, it } from '@ohos/hypium';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { customEmojiNeedsRepainting, inlineEmojiUpdate, InlineCustomEmojiPaint } from '../main/ets/util/inlineCustomEmojiPaint';

export default function inlineCustomEmojiPaintTest(): void {
  describe('InlineCustomEmojiPaint', (): void => {
    it('only authoritative custom emoji repaint flags enable tint', 0, (): void => {
      const full: TdObject = { '@type': 'stickerFullTypeCustomEmoji' };
      full['needs_repainting'] = true;
      const sticker: TdObject = { '@type': 'sticker' };
      sticker['full_type'] = full;
      expect(customEmojiNeedsRepainting(sticker)).assertTrue();
      const empty: TdObject = { '@type': 'sticker' };
      expect(customEmojiNeedsRepainting(empty)).assertFalse();
      full['needs_repainting'] = false;
      expect(customEmojiNeedsRepainting(sticker)).assertFalse();
      full['needs_repainting'] = true; full['@type'] = 'stickerFullTypeRegular';
      expect(customEmojiNeedsRepainting(sticker)).assertFalse();
    });
    it('paths and repaint flags hydrate together with missing assets', 0, (): void => {
      const paths = new Map<string, string>([['video', '/v.webp']]);
      const result = inlineEmojiUpdate(['video', 'picture'], [], [], paths, new Set<string>(['video']));
      expect(result?.paths.join('|')).assertEqual('/v.webp|');
      expect(result?.repaint.join('|')).assertEqual('true|false');
    });
    it('unchanged hydration returns null but metadata alone causes an update', 0, (): void => {
      const paths = new Map<string, string>([['video', '/v.webp']]);
      expect(inlineEmojiUpdate(['video'], ['/v.webp'], [true], paths, new Set<string>(['video'])) === null).assertTrue();
      expect(inlineEmojiUpdate(['video'], ['/v.webp'], [false], paths, new Set<string>(['video']))?.repaint[0]).assertTrue();
      expect(inlineEmojiUpdate([], [], [], paths, new Set<string>()) === null).assertTrue();
    });
    it('late changed slot preserves prefix and leaves old arrays untouched', 0, (): void => {
      const paths: string[] = ['/a', '/b']; const repaint: boolean[] = [false, false];
      const result = inlineEmojiUpdate(['a', 'b'], paths, repaint,
        new Map<string, string>([['a', '/a'], ['b', '/new']]), new Set<string>(['b']));
      expect(result?.paths.join('|')).assertEqual('/a|/new');
      expect(result?.repaint.join('|')).assertEqual('false|true');
      expect(paths[1]).assertEqual('/b'); expect(repaint[1]).assertFalse();
    });
    it('lookup resets on reused messages and maps file paths once', 0, (): void => {
      const cache = new InlineCustomEmojiPaint();
      cache.prepare(['video', 'picture'], ['/v.webp', 'file:///p.webp'], [true, false]);
      expect(cache.source('video')).assertEqual('file:///v.webp');
      expect(cache.source('picture')).assertEqual('file:///p.webp');
      expect(cache.needsRepainting('video')).assertTrue();
      expect(cache.needsRepainting('picture')).assertFalse();
      cache.prepare(['new'], [''], [true]);
      expect(cache.source('video')).assertEqual(''); expect(cache.needsRepainting('video')).assertFalse();
      expect(cache.source('new')).assertEqual('');
    });
    it('same ID picks up downloaded assets and changed repaint metadata', 0, (): void => {
      const cache = new InlineCustomEmojiPaint(); const ids: string[] = ['video'];
      cache.prepare(ids, [], []); expect(cache.source('video')).assertEqual('');
      const paths: string[] = ['/video'];
      cache.prepare(ids, paths, [false]); expect(cache.needsRepainting('video')).assertFalse();
      cache.prepare(ids, paths, [true]); expect(cache.needsRepainting('video')).assertTrue();
      cache.prepare(ids, ['/next'], [true]); expect(cache.source('video')).assertEqual('file:///next');
    });
  });
}
