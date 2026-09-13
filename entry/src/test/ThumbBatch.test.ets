import { describe, it, expect } from '@ohos/hypium';
import { ThumbBatch } from '../main/ets/util/thumbBatch';

// 壁纸页缩略图到达合批（issue #201 第 7 条）：几十张缩略图各自回调时不再
// 每张换一次 Map，攒起来一次落。
export default function thumbBatchTest(): void {
  describe('thumbBatch', (): void => {
    it('第一次 add 返回 true（该排一次落盘），随后的 add 返回 false', 0, (): void => {
      const b: ThumbBatch = new ThumbBatch();
      expect(b.add('a', '/a.jpg')).assertTrue();
      expect(b.add('b', '/b.jpg')).assertFalse();
      expect(b.add('c', '/c.jpg')).assertFalse();
    });
    it('drain 一次拿走全部，且清空；再 add 又会返回 true', 0, (): void => {
      const b: ThumbBatch = new ThumbBatch();
      b.add('a', '/a.jpg'); b.add('b', '/b.jpg');
      const got: Map<string, string> = b.drain();
      expect(got.size).assertEqual(2);
      expect(got.get('b')).assertEqual('/b.jpg');
      expect(b.drain().size).assertEqual(0);
      expect(b.add('c', '/c.jpg')).assertTrue();
    });
    it('同一键后到的覆盖先到的', 0, (): void => {
      const b: ThumbBatch = new ThumbBatch();
      b.add('a', '/old.jpg'); b.add('a', '/new.jpg');
      expect(b.drain().get('a')).assertEqual('/new.jpg');
    });
    it('clear 丢弃未落的（页面换了深浅色 / 退出）', 0, (): void => {
      const b: ThumbBatch = new ThumbBatch();
      b.add('a', '/a.jpg'); b.clear();
      expect(b.drain().size).assertEqual(0);
      expect(b.add('a', '/a.jpg')).assertTrue();
    });
  });
}
