import { describe, expect, it } from '@ohos/hypium';
import { DrawnRichHitIndex } from '../main/ets/util/drawnRichHitIndex';
import { DrawnRichHit, DrawnRichLink } from '../main/ets/util/drawnRichTextPolicy';

function indexedHit(key: string, x: number, y: number, w: number = 20, h: number = 18): DrawnRichHit {
  const link: DrawnRichLink = { start: 0, end: 1, label: key, url: key, hidesUrl: false,
    accessibilityLabel: key, accessibilityFirst: true };
  return { key, link, x, y, widthVp: w, heightVp: h, accessible: true };
}

export default function drawnRichHitIndexTest(): void {
  describe('DrawnRichHitIndex', (): void => {
    it('empty text and invalid coordinates never own a tap', 0, (): void => {
      const index = new DrawnRichHitIndex([]);
      expect(index.find(0, 0) === null).assertTrue();
      expect(index.find(NaN, 0) === null).assertTrue();
      expect(index.find(0, Infinity) === null).assertTrue();
      expect(index.regions.length).assertEqual(0);
    });
    it('links retain gaps and exclusive right bottom bounds', 0, (): void => {
      const first = indexedHit('one', 3, 5), second = indexedHit('two', 30, 5);
      const index = new DrawnRichHitIndex([first, second]);
      expect(index.find(3, 5) === first).assertTrue();
      expect(index.find(23, 5) === null).assertTrue();
      expect(index.find(4, 23) === null).assertTrue();
      expect(index.find(27, 10) === null).assertTrue();
      expect(index.find(31, 10) === second).assertTrue();
    });
    it('unsorted multiline rectangles retain semantic link and region order', 0, (): void => {
      const bottom = indexedHit('wrapped', 0, 40), top = indexedHit('first', 0, 0);
      const index = new DrawnRichHitIndex([bottom, top]);
      expect(index.find(10, 45) === bottom).assertTrue();
      expect(index.find(10, 5) === top).assertTrue();
      expect(index.find(10, 30) === null).assertTrue();
      expect(index.regions[0].y).assertEqual(40);
    });
    it('overlap respects original child order rather than sorted y order', 0, (): void => {
      const first = indexedHit('lower', 0, 10, 20, 20);
      const last = indexedHit('upper', 0, 0, 20, 20);
      const index = new DrawnRichHitIndex([first, last]);
      expect(index.find(5, 15) === last).assertTrue();
      expect(index.find(5, 25) === first).assertTrue();
    });
    it('a tall earlier rectangle is found across intervening shorter ones', 0, (): void => {
      const tall = indexedHit('tall', 30, 0, 20, 100);
      const index = new DrawnRichHitIndex([tall, indexedHit('short', 0, 10)]);
      expect(index.find(40, 90) === tall).assertTrue();
      expect(index.find(5, 90) === null).assertTrue();
    });
    it('repeated lookup reuses rectangles and never changes input order', 0, (): void => {
      const hits: DrawnRichHit[] = [];
      for (let i: number = 0; i < 1024; i++) { hits.push(indexedHit(`${i}`, 0, i * 20)); }
      const index = new DrawnRichHitIndex(hits), regions = index.regions;
      for (let i: number = 0; i < hits.length; i++) {
        expect(index.find(5, i * 20 + 5) === hits[i]).assertTrue();
      }
      expect(index.regions === regions).assertTrue();
      expect(hits[0].key).assertEqual('0');
    });
  });
}
