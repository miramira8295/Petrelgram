import { describe, expect, it } from '@ohos/hypium';
import { nextTabPreloadIndex } from '../main/ets/util/tabPreload';

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
  });
}
