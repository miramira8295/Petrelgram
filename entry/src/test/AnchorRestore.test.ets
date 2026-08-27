import { describe, it, expect } from '@ohos/hypium';
import {
  planAnchorRestore, INVALID_ANCHOR_RECT,
  ANCHOR_RESTORE_DELTA, ANCHOR_RESTORE_FALLBACK, AnchorRectSnapshot
} from '../main/ets/util/anchorRestore';

export default function anchorRestoreTest() {
  describe('planAnchorRestore', () => {
    it('行还在显示区：只走一次 scrollBy，不回退', 0, (): void => {
      // 发布前行的顶边在视口顶上方 30vp；发布后框架把它放到了 -18vp。
      // 要把它推回 -30 ⇒ 内容还要再上移 12 ⇒ dy 为正 12。
      const rect: AnchorRectSnapshot = { width: 360, height: 64, y: -18 };
      const plan = planAnchorRestore(rect, -30);
      expect(plan.mode).assertEqual(ANCHOR_RESTORE_DELTA);
      expect(plan.dy).assertEqual(12);
    });

    it('反向也要能修：行被顶低了就往回滚', 0, (): void => {
      // 发布后行跑到了 -48（比记的 -30 更靠上）⇒ 内容要下移 18 ⇒ dy 为负。
      const rect: AnchorRectSnapshot = { width: 360, height: 64, y: -48 };
      const plan = planAnchorRestore(rect, -30);
      expect(plan.mode).assertEqual(ANCHOR_RESTORE_DELTA);
      expect(plan.dy).assertEqual(-18);
    });

    it('残差小于半个 vp 就整个省掉这次滚动', 0, (): void => {
      const rect: AnchorRectSnapshot = { width: 360, height: 64, y: -30.2 };
      const plan = planAnchorRestore(rect, -30);
      expect(plan.mode).assertEqual(ANCHOR_RESTORE_DELTA);
      expect(plan.dy).assertEqual(0);
      // 恰好没动的常见情形：maintainVisibleContentPosition 已经守住了。
      const exact: AnchorRectSnapshot = { width: 360, height: 64, y: -30 };
      expect(planAnchorRestore(exact, -30).dy).assertEqual(0);
    });

    it('y = 0 的可见首行也算有效——不能照抄"四个都不为 0"', 0, (): void => {
      // 停在视口顶端的那一行 y 恰好是 0，单列列表里 x 恒为 0。按 FAQ 里
      // "x/y/width/height 均不为 0"去判会把它误判成不可见，白白回退。
      const rect: AnchorRectSnapshot = { width: 360, height: 64, y: 0 };
      const plan = planAnchorRestore(rect, -24);
      expect(plan.mode).assertEqual(ANCHOR_RESTORE_DELTA);
      expect(plan.dy).assertEqual(24);
    });

    it('全 0 矩形 = 行不在显示区：回退到 scrollToIndex', 0, (): void => {
      // 框架对非法下标返回的就是全 0（faqs-arkui-572）；调用点抓到异常时也
      // 传这一份。
      const plan = planAnchorRestore(INVALID_ANCHOR_RECT, -30);
      expect(plan.mode).assertEqual(ANCHOR_RESTORE_FALLBACK);
      // scrollToIndex(START) 之后行的 y 是 0，补一次 -itemY 就回到原位。
      expect(plan.dy).assertEqual(30);
    });

    it('回退路径逐字保留旧行为：itemY 非负时不补滚', 0, (): void => {
      // 旧代码是 `if (itemY < -0.5) scrollBy(0, -itemY)`——单边。
      expect(planAnchorRestore(INVALID_ANCHOR_RECT, 0).dy).assertEqual(0);
      expect(planAnchorRestore(INVALID_ANCHOR_RECT, 12).dy).assertEqual(0);
      expect(planAnchorRestore(INVALID_ANCHOR_RECT, -0.4).dy).assertEqual(0);
      expect(planAnchorRestore(INVALID_ANCHOR_RECT, -0.6).dy).assertEqual(0.6);
    });

    it('只有宽或只有高为 0 也算非法', 0, (): void => {
      const noHeight: AnchorRectSnapshot = { width: 360, height: 0, y: -18 };
      expect(planAnchorRestore(noHeight, -30).mode).assertEqual(ANCHOR_RESTORE_FALLBACK);
      const noWidth: AnchorRectSnapshot = { width: 0, height: 64, y: -18 };
      expect(planAnchorRestore(noWidth, -30).mode).assertEqual(ANCHOR_RESTORE_FALLBACK);
    });
  });
}
