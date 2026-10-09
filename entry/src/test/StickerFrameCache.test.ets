import { describe, it, expect } from '@ohos/hypium';
import {
  frameCacheFileName, planFrameCachePrune, FrameCacheEntry, FRAME_CACHE_VERSION,
  uidFrameCacheFileName, parseUidFrameCacheFileName, pickUidFrameCache, UidFrameCacheVariant
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
    // 大表情放宽预算后解出来的帧（抽帧步长不同）必须和普通档分开存，否则会命中
    // 之前按普通档（隔帧）写下的缓存。
    it('预算档位进文件名，默认档文件名不变', 0, (): void => {
      const normal: string = frameCacheFileName('/d/abc.webm', 1234, 256);
      const explicitNormal: string = frameCacheFileName('/d/abc.webm', 1234, 256, false);
      const high: string = frameCacheFileName('/d/abc.webm', 1234, 256, true);
      expect(explicitNormal).assertEqual(normal);
      expect(high === normal).assertFalse();
      expect(high.endsWith(`_v${FRAME_CACHE_VERSION}.pgsf`)).assertTrue();
    });

    // 第二步（2026-10-09）：按 Telegram 文件的全局唯一 ID 存，下载之前就能查。
    it('按唯一 ID 命名，能原样解析回来', 0, (): void => {
      const name: string = uidFrameCacheFileName('AgADBQADwDGrLQ', 128, true);
      expect(name).assertEqual(`u_AgADBQADwDGrLQ_128h_v${FRAME_CACHE_VERSION}.pgsf`);
      const parsed = parseUidFrameCacheFileName(name);
      expect(parsed?.uid).assertEqual('AgADBQADwDGrLQ');
      expect(parsed?.bucket).assertEqual(128);
      expect(parsed?.high).assertTrue();
      expect(parseUidFrameCacheFileName(uidFrameCacheFileName('a-b_c', 256, false))?.high).assertFalse();
    });

    it('旧版本、按路径命名的、乱七八糟的文件名都不认', 0, (): void => {
      expect(parseUidFrameCacheFileName('abc123_4096_128_v1.pgsf') === null).assertTrue();
      expect(parseUidFrameCacheFileName('u_abc_128_v0.pgsf') === null).assertTrue();
      expect(parseUidFrameCacheFileName('u_abc_xx_v1.pgsf') === null).assertTrue();
      expect(parseUidFrameCacheFileName('u_abc_128_v1.pgsf.tmp') === null).assertTrue();
    });

    it('挑缓存：尺寸桶不小于要的，优先最接近的', 0, (): void => {
      const have: UidFrameCacheVariant[] = [
        { bucket: 96, high: false }, { bucket: 256, high: false }, { bucket: 160, high: false }
      ];
      expect(pickUidFrameCache(have, 128, false)?.bucket).assertEqual(160);
      expect(pickUidFrameCache(have, 96, false)?.bucket).assertEqual(96);
      // 只有更小的：放大会糊，宁可重新下载解码
      expect(pickUidFrameCache([{ bucket: 96, high: false }], 256, false) === null).assertTrue();
    });

    it('挑缓存：大表情要高帧率那一档，普通贴纸两档都行、同尺寸先挑普通档', 0, (): void => {
      const have: UidFrameCacheVariant[] = [{ bucket: 256, high: false }, { bucket: 256, high: true }];
      expect(pickUidFrameCache(have, 256, true)?.high).assertTrue();
      expect(pickUidFrameCache([{ bucket: 256, high: false }], 256, true) === null).assertTrue();
      expect(pickUidFrameCache(have, 256, false)?.high).assertFalse();
      expect(pickUidFrameCache([{ bucket: 256, high: true }], 128, false)?.high).assertTrue();
    });
  });
}
