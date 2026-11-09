import { describe, expect, it } from '@ohos/hypium';
import { nextTabPreloadIndex, pruneBuiltKeys } from '../main/ets/util/tabPreload';

export default function tabPreloadTest() {
  describe('tabPreload', () => {
    it('右邻没建过时优先右邻', 0, (): void => {
      const built = new Set<string>(['main']);
      expect(nextTabPreloadIndex(['main', 'folder:1', 'folder:2'], 0, built)).assertEqual(1);
    });
    it('右邻建过则补左邻', 0, (): void => {
      const built = new Set<string>(['folder:1', 'folder:2']);
      expect(nextTabPreloadIndex(['main', 'folder:1', 'folder:2'], 1, built)).assertEqual(0);
    });
    it('两侧都建过返回 -1', 0, (): void => {
      const built = new Set<string>(['main', 'folder:1', 'folder:2']);
      expect(nextTabPreloadIndex(['main', 'folder:1', 'folder:2'], 1, built)).assertEqual(-1);
    });
    it('首尾页签只看存在的那一侧', 0, (): void => {
      const built = new Set<string>(['main']);
      // 末位：右侧不存在，补左侧。
      expect(nextTabPreloadIndex(['main', 'folder:1'], 1, new Set<string>(['folder:1'])))
        .assertEqual(0);
      // 首位：左侧不存在，只看右侧。
      expect(nextTabPreloadIndex(['main', 'folder:1'], 0, built)).assertEqual(1);
    });
    it('只有一个页签或下标越界返回 -1', 0, (): void => {
      expect(nextTabPreloadIndex(['main'], 0, new Set<string>())).assertEqual(-1);
      expect(nextTabPreloadIndex(['main', 'folder:1'], -1, new Set<string>())).assertEqual(-1);
      expect(nextTabPreloadIndex(['main', 'folder:1'], 2, new Set<string>())).assertEqual(-1);
      expect(nextTabPreloadIndex([], 0, new Set<string>())).assertEqual(-1);
    });
    it('当前页签自己在不在账上不影响结果', 0, (): void => {
      expect(nextTabPreloadIndex(['main', 'folder:1'], 0, new Set<string>())).assertEqual(1);
      expect(nextTabPreloadIndex(['main', 'folder:1'], 0, new Set<string>(['main'])))
        .assertEqual(1);
    });
    it('账本裁剪：只留保活范围内的记账，返回新 Set', 0, (): void => {
      const keys = ['main', 'folder:1', 'folder:2', 'folder:3', 'folder:4', 'folder:5'];
      const built = new Set<string>(keys);
      const kept = pruneBuiltKeys(keys, 4, built, 2);
      expect(kept.has('main')).assertFalse();
      expect(kept.has('folder:1')).assertFalse();
      expect(kept.has('folder:2')).assertTrue();
      expect(kept.has('folder:4')).assertTrue();
      expect(kept.has('folder:5')).assertTrue();
      // 入参不被修改（账本换新不改旧）。
      expect(built.has('main')).assertTrue();
    });
    it('账本裁剪：边界与不存在的 key', 0, (): void => {
      const keys = ['main', 'folder:1', 'folder:2'];
      // 当前在首位：范围被夹在 [0, 2]。
      const keptAtStart = pruneBuiltKeys(keys, 0, new Set<string>(keys), 2);
      expect(keptAtStart.size).assertEqual(3);
      // 账上有已删除文件夹的 key：裁掉。
      const stale = pruneBuiltKeys(keys, 0, new Set<string>(['folder:gone', 'main']), 2);
      expect(stale.size).assertEqual(1);
      expect(stale.has('main')).assertTrue();
      // 越界下标：空账本。
      expect(pruneBuiltKeys(keys, 9, new Set<string>(keys), 2).size).assertEqual(0);
    });
  });
}
