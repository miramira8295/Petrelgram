import { describe, it, expect } from '@ohos/hypium';
import {
  frameCacheFileName, planFrameCachePrune, FrameCacheEntry, FRAME_CACHE_VERSION
} from '../main/ets/util/stickerFrameCache';

function entry(name: string, bytes: number, mtimeMs: number): FrameCacheEntry {
  return { name: name, bytes: bytes, mtimeMs: mtimeMs };
}

export default function stickerFrameCacheTest() {
  describe('stickerFrameCache', () => {
    it('文件名 = 源文件名 + 字节数 + 尺寸桶 + 版本', 0, (): void => {
      const name: string = frameCacheFileName('/data/files/stickers/abc123.webm', 4096, 128);
      expect(name).assertEqual(`abc123_4096_128_v${FRAME_CACHE_VERSION}.pgsf`);
    });

    it('同一个文件不同显示尺寸是两份', 0, (): void => {
      const a: string = frameCacheFileName('/a/b.webm', 10, 128);
      const b: string = frameCacheFileName('/a/b.webm', 10, 256);
      expect(a === b).assertFalse();
    });

    it('内容换了（字节数变了）就是另一份，旧的自然失效', 0, (): void => {
      const a: string = frameCacheFileName('/a/b.webm', 10, 128);
      const b: string = frameCacheFileName('/a/b.webm', 11, 128);
      expect(a === b).assertFalse();
    });

    it('文件名里的异常字符被清理，不会跑出目录', 0, (): void => {
      const name: string = frameCacheFileName('/a/../evil name/x y.webm', 1, 96);
      expect(name.indexOf('/')).assertEqual(-1);
      expect(name.indexOf(' ')).assertEqual(-1);
      expect(name).assertEqual(`x_y_1_96_v${FRAME_CACHE_VERSION}.pgsf`);
    });

    it('没超预算不删任何东西', 0, (): void => {
      const plan: string[] = planFrameCachePrune(
        [entry('a', 10, 1), entry('b', 20, 2)], 100);
      expect(plan.length).assertEqual(0);
    });

    it('超预算按最老先删，删到预算内就停', 0, (): void => {
      const plan: string[] = planFrameCachePrune(
        [entry('new', 40, 300), entry('old', 40, 100), entry('mid', 40, 200)], 90);
      expect(plan.length).assertEqual(1);
      expect(plan[0]).assertEqual('old');
    });

    it('全都太大时会一直删下去，不会死循环', 0, (): void => {
      const plan: string[] = planFrameCachePrune(
        [entry('a', 100, 1), entry('b', 100, 2)], 10);
      expect(plan.length).assertEqual(2);
      expect(plan[0]).assertEqual('a');
    });
  });
}
