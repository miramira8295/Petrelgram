import { describe, it, expect } from '@ohos/hypium';
import {
  anchorYAfterUserScroll, canApplyAnchorRestore, planAnchorRestore, INVALID_ANCHOR_RECT,
  ANCHOR_RESTORE_DELTA, ANCHOR_RESTORE_FALLBACK, AnchorRectSnapshot,
  ANCHOR_RESTORE_ATTEMPTS, PrependAnchorCaptureInput, shouldCapturePrependAnchor,
  shouldPrimePrependAnchor, shouldRetryAnchorRestore
} from '../main/ets/util/anchorRestore';

function prependInput(): PrependAnchorCaptureInput {
  return {
    didInitialScroll: true,
    anchorIndexFresh: true,
    olderPageGrowth: true
  };
}

export default function anchorRestoreTest() {
  describe('shouldCapturePrependAnchor', () => {
    it('older 媒体页增长时保留可见锚点', 0, (): void => {
      expect(shouldCapturePrependAnchor(prependInput())).assertTrue();
    });

    it('非 older 增长的发布不抢滚动位置', 0, (): void => {
      const value: PrependAnchorCaptureInput = prependInput();
      value.olderPageGrowth = false;
      expect(shouldCapturePrependAnchor(value)).assertFalse();
    });

    it('首屏定位前和过期行号都不采样', 0, (): void => {
      const beforeLanding: PrependAnchorCaptureInput = prependInput();
      beforeLanding.didInitialScroll = false;
      expect(shouldCapturePrependAnchor(beforeLanding)).assertFalse();
      const staleIndex: PrependAnchorCaptureInput = prependInput();
      staleIndex.anchorIndexFresh = false;
      expect(shouldCapturePrependAnchor(staleIndex)).assertFalse();
    });
  });

  describe('anchorYAfterUserScroll', () => {
    it('数据发布期间用户继续向末尾滑动，锚点目标跟着上移', 0, (): void => {
      expect(anchorYAfterUserScroll(-20, 100, 136)).assertEqual(-56);
    });

    it('用户反向滑动也保留，不被异步复位抵消', 0, (): void => {
      expect(anchorYAfterUserScroll(-20, 100, 84)).assertEqual(-4);
    });

    it('没有新的用户位移时保持原锚点', 0, (): void => {
      expect(anchorYAfterUserScroll(-20, 100, 100)).assertEqual(-20);
    });
  });

  describe('shouldPrimePrependAnchor', () => {
    it('静止在绝对顶部时发布前预定位', 0, (): void => {
      expect(shouldPrimePrependAnchor(0, 152.857, 153, false)).assertTrue();
    });

    it('松手后的顶部回弹仍然预定位', 0, (): void => {
      expect(shouldPrimePrependAnchor(0, 159.342, 153, false)).assertTrue();
    });

    it('普通可见位置不走预定位', 0, (): void => {
      expect(shouldPrimePrependAnchor(1, 153, 153, false)).assertFalse();
      expect(shouldPrimePrependAnchor(0, 140, 153, false)).assertFalse();
      expect(shouldPrimePrependAnchor(0, 166, 153, false)).assertFalse();
    });

    it('手指仍按着时不抢滚动位置', 0, (): void => {
      expect(shouldPrimePrependAnchor(0, 153, 153, true)).assertFalse();
    });
  });

  describe('canApplyAnchorRestore', () => {
    it('静止列表允许修正布局残差', 0, (): void => {
      expect(canApplyAnchorRestore(false, 0)).assertTrue();
      expect(canApplyAnchorRestore(false, 0.49)).assertTrue();
    });

    it('拖动或惯性期间不让程序滚动抢位置', 0, (): void => {
      expect(canApplyAnchorRestore(true, 0)).assertFalse();
      expect(canApplyAnchorRestore(false, 1)).assertFalse();
      expect(canApplyAnchorRestore(false, 2467)).assertFalse();
    });
  });

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

  describe('shouldRetryAnchorRestore', () => {
    // 量到了就落地，别再多跑一帧。
    it('量到就不重试', 0, (): void => {
      expect(shouldRetryAnchorRestore(ANCHOR_RESTORE_DELTA, 0)).assertFalse();
      expect(shouldRetryAnchorRestore(ANCHOR_RESTORE_DELTA, 1)).assertFalse();
    });

    // 真机上 setTimeout(0) 那一刻新快照常常还没排版，首次必然量不到。
    // 只量一次 = 71% 的前插零补偿（2026-08-29 日志 B 区 22/31）。
    it('量不到且还有次数就再量一帧', 0, (): void => {
      expect(shouldRetryAnchorRestore(ANCHOR_RESTORE_FALLBACK, 0)).assertTrue();
      expect(shouldRetryAnchorRestore(ANCHOR_RESTORE_FALLBACK, 1)).assertTrue();
    });

    // 用尽了就放弃——不恢复 scrollToIndex 兜底，它会把视口整体往下推。
    it('次数用尽就放弃', 0, (): void => {
      expect(shouldRetryAnchorRestore(ANCHOR_RESTORE_FALLBACK, ANCHOR_RESTORE_ATTEMPTS - 1)).assertFalse();
      expect(shouldRetryAnchorRestore(ANCHOR_RESTORE_FALLBACK, ANCHOR_RESTORE_ATTEMPTS)).assertFalse();
    });

    // 总次数含首次，所以最多只多跑 ATTEMPTS-1 帧。
    it('总尝试次数是三次', 0, (): void => {
      expect(ANCHOR_RESTORE_ATTEMPTS).assertEqual(3);
      let attempt: number = 0;
      while (shouldRetryAnchorRestore(ANCHOR_RESTORE_FALLBACK, attempt)) {
        attempt++;
      }
      expect(attempt).assertEqual(ANCHOR_RESTORE_ATTEMPTS - 1);
    });
  });
}
