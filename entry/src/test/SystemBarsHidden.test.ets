import { describe, it, expect } from '@ohos/hypium';
import {
  SYSTEM_BARS_OWNER_LIVE, requestSystemBarsHidden, resetSystemBarsHiddenForTest,
  systemBarsApplyFailed, systemBarsOwnerCount, viewerSystemBarsOwner
} from '../main/ets/util/systemBarsHidden';

export default function systemBarsHiddenTest() {
  describe('SystemBarsHidden', () => {
    it('第一个持有者要藏时推 true，最后一个放开时推 false', 0, () => {
      resetSystemBarsHiddenForTest();
      expect(requestSystemBarsHidden('a', true)).assertEqual(true);
      expect(requestSystemBarsHidden('a', false)).assertEqual(false);
    });

    it('同一持有者重复登记不重复推', 0, () => {
      resetSystemBarsHiddenForTest();
      expect(requestSystemBarsHidden('a', true)).assertEqual(true);
      expect(requestSystemBarsHidden('a', true)).assertNull();
      expect(systemBarsOwnerCount()).assertEqual(1);
    });

    // 本模块存在的理由：直播全屏还开着时关掉一个查看器，不能把系统栏放回来。
    it('多个持有者时，放掉其中一个不恢复系统栏', 0, () => {
      resetSystemBarsHiddenForTest();
      expect(requestSystemBarsHidden(SYSTEM_BARS_OWNER_LIVE, true)).assertEqual(true);
      const viewer: string = viewerSystemBarsOwner();
      expect(requestSystemBarsHidden(viewer, true)).assertNull();
      expect(requestSystemBarsHidden(viewer, false)).assertNull();
      expect(systemBarsOwnerCount()).assertEqual(1);
      expect(requestSystemBarsHidden(SYSTEM_BARS_OWNER_LIVE, false)).assertEqual(false);
    });

    it('没登记过的持有者放开不做任何事', 0, () => {
      resetSystemBarsHiddenForTest();
      expect(requestSystemBarsHidden('ghost', false)).assertNull();
      expect(systemBarsOwnerCount()).assertEqual(0);
    });

    it('空名字一律忽略', 0, () => {
      resetSystemBarsHiddenForTest();
      expect(requestSystemBarsHidden('', true)).assertNull();
      expect(systemBarsOwnerCount()).assertEqual(0);
    });

    it('查看器持有者按实例取名，互不相同', 0, () => {
      resetSystemBarsHiddenForTest();
      expect(viewerSystemBarsOwner() === viewerSystemBarsOwner()).assertFalse();
    });

    // 窗口调用失败后要能重试，而不是被当成"已经藏了"。
    it('推送失败回滚后，同方向的请求会再推一次', 0, () => {
      resetSystemBarsHiddenForTest();
      expect(requestSystemBarsHidden('a', true)).assertEqual(true);
      systemBarsApplyFailed(true);
      expect(requestSystemBarsHidden('b', true)).assertEqual(true);
    });
  });
}
