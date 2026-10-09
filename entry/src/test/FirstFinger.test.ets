import { describe, expect, it } from '@ohos/hypium';
import { firstFinger } from '../main/ets/util/firstFinger';

class Point {
  localX: number = 0;
  constructor(x: number) {
    this.localX = x;
  }
}

export default function firstFingerTest() {
  describe('firstFinger', () => {
    it('正常取第一根手指', 0, (): void => {
      expect(firstFinger([new Point(3), new Point(9)])?.localX).assertEqual(3);
    });

    it('空列表返回 undefined', 0, (): void => {
      expect(firstFinger<Point>([]) === undefined).assertTrue();
    });

    // #228 崩溃榜：线上见过 length > 0 但 [0] 是 undefined 的 fingerList
    // （MessageBubble 长按读 localX 崩了 4 次）。只判 length 挡不住。
    it('长度非零但首项为空也返回 undefined', 0, (): void => {
      const holey: Point[] = new Array<Point>(1);
      expect(holey.length).assertEqual(1);
      expect(firstFinger(holey) === undefined).assertTrue();
    });

    it('列表本身为空值返回 undefined', 0, (): void => {
      expect(firstFinger<Point>(undefined) === undefined).assertTrue();
    });
  });
}
