import { describe, it, expect } from '@ohos/hypium';
import { FavoriteStickerCache } from '../main/ets/util/favoriteStickerCache';

export default function favoriteStickerCacheTest() {
  describe('favoriteStickerCache', () => {
    it('未加载时一律当作"未收藏"，不谎报', 0, (): void => {
      const c: FavoriteStickerCache = new FavoriteStickerCache();
      expect(c.loaded()).assertFalse();
      expect(c.has(7)).assertFalse();
    });

    it('整表替换：服务端那份就是真相', 0, (): void => {
      const c: FavoriteStickerCache = new FavoriteStickerCache();
      c.replaceAll([1, 2, 3]);
      expect(c.loaded()).assertTrue();
      expect(c.has(2)).assertTrue();
      c.replaceAll([9]);
      expect(c.has(2)).assertFalse();
      expect(c.has(9)).assertTrue();
    });

    it('本地先行：切换立刻反映，失败可以原样退回', 0, (): void => {
      const c: FavoriteStickerCache = new FavoriteStickerCache();
      c.replaceAll([1]);
      c.set(5, true);
      expect(c.has(5)).assertTrue();
      c.set(5, false);
      expect(c.has(5)).assertFalse();
      // 重复置同一个值不应该出岔子
      c.set(1, true);
      expect(c.has(1)).assertTrue();
    });

    it('0 号文件不是贴纸，永远不收藏', 0, (): void => {
      const c: FavoriteStickerCache = new FavoriteStickerCache();
      c.replaceAll([0, 4]);
      expect(c.has(0)).assertFalse();
      c.set(0, true);
      expect(c.has(0)).assertFalse();
      expect(c.has(4)).assertTrue();
    });
  });
}
