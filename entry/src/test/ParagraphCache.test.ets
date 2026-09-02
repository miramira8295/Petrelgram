import { describe, expect, it } from '@ohos/hypium';
import {
  paragraphCacheSize, plainParagraphFor, PlainParagraph,
  setParagraphFactoryForTest
} from '../main/ets/util/paragraphCache';

function fakeLaid(height: number): PlainParagraph {
  return { paragraph: null, widthVp: 10, heightVp: height };
}

export default function paragraphCacheTest() {
  describe('ParagraphCache', () => {
    it('caches_by_content_width_font_and_color', 0, (): void => {
      let builds: number = 0;
      setParagraphFactoryForTest((
        _c: string, _w: number, _f: number, _col: number
      ): PlainParagraph => {
        builds++;
        return fakeLaid(20);
      });
      try {
        plainParagraphFor('hello', 200, 16, 0xFF000000);
        plainParagraphFor('hello', 200, 16, 0xFF000000);
        expect(builds).assertEqual(1);
        plainParagraphFor('hello', 240, 16, 0xFF000000);
        plainParagraphFor('hello', 200, 17, 0xFF000000);
        plainParagraphFor('hello', 200, 16, 0xFF111111);
        plainParagraphFor('world', 200, 16, 0xFF000000);
        expect(builds).assertEqual(5);
      } finally {
        setParagraphFactoryForTest(null);
      }
    });

    it('evicts_oldest_beyond_limit_but_keeps_touched_entries', 0, (): void => {
      let builds: number = 0;
      setParagraphFactoryForTest((
        _c: string, _w: number, _f: number, _col: number
      ): PlainParagraph => {
        builds++;
        return fakeLaid(20);
      });
      try {
        for (let i = 0; i < 192; i++) {
          plainParagraphFor(`m${i}`, 200, 16, 0xFF000000);
        }
        expect(paragraphCacheSize()).assertEqual(192);
        // 触摸最老的一条，把它挪到队尾。
        plainParagraphFor('m0', 200, 16, 0xFF000000);
        expect(builds).assertEqual(192);
        // 再灌一条：被淘汰的应是 m1（当前最老），m0 仍在缓存。
        plainParagraphFor('fresh', 200, 16, 0xFF000000);
        expect(paragraphCacheSize()).assertEqual(192);
        plainParagraphFor('m0', 200, 16, 0xFF000000);
        expect(builds).assertEqual(193);
        plainParagraphFor('m1', 200, 16, 0xFF000000);
        expect(builds).assertEqual(194);
      } finally {
        setParagraphFactoryForTest(null);
      }
    });

    it('does_not_cache_failed_layouts', 0, (): void => {
      let builds: number = 0;
      setParagraphFactoryForTest((
        _c: string, _w: number, _f: number, _col: number
      ): PlainParagraph => {
        builds++;
        return { paragraph: null, widthVp: 200, heightVp: 0 };
      });
      try {
        plainParagraphFor('broken', 200, 16, 0xFF000000);
        plainParagraphFor('broken', 200, 16, 0xFF000000);
        // 失败结果（null paragraph 且零高）不进缓存，每次都重试。
        expect(builds).assertEqual(2);
      } finally {
        setParagraphFactoryForTest(null);
      }
    });
  });
}
