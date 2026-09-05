import { describe, it, expect } from '@ohos/hypium';
import {
  rowFadeAnimationActive, rowFadeTransition, initialRowRevealDelay,
  INITIAL_ROW_FADE_WINDOW_MS, RowFadeTransition
} from '../main/ets/util/rowFadeGate';
import {
  INITIAL_TIMELINE_REVEAL_ROW_LIMIT, INITIAL_TIMELINE_ROW_STAGGER_MS,
  INITIAL_TIMELINE_ROW_FADE_MS
} from '../main/ets/util/chatPageTuning';

export default function rowFadeGateTest() {
  describe('rowFadeAnimationActive', () => {
    it('遮罩期间恒放行——首屏那一波淡入靠它', 0, (): void => {
      expect(rowFadeAnimationActive(true, 10000, 0)).assertTrue();
      expect(rowFadeAnimationActive(true, 10000, 1)).assertTrue();
    });

    it('揭示之后的窗口内仍然放行：逐条淡入要跑完', 0, (): void => {
      // 这一条就是「首屏逐条淡入必须保住」的钉子：masked 翻假的那一帧，
      // armedAt 还是上一帧（masked 期间续的）的时间戳，闩必须是开的。
      expect(rowFadeAnimationActive(false, 10000, 10000)).assertTrue();
      expect(rowFadeAnimationActive(false, 10016, 10000)).assertTrue();
      // 一波 stagger（7 × 14ms）加一段淡入（90ms）都还在窗口里。
      expect(rowFadeAnimationActive(false, 10000 + 98 + 90, 10000)).assertTrue();
      expect(rowFadeAnimationActive(
        false, 10000 + INITIAL_ROW_FADE_WINDOW_MS, 10000)).assertTrue();
    });

    it('窗口之外不放行：常驻动画上下文失效', 0, (): void => {
      expect(rowFadeAnimationActive(
        false, 10000 + INITIAL_ROW_FADE_WINDOW_MS + 1, 10000)).assertFalse();
      // 用户看到的那种「过一会图都加载完了就恢复正常」的场景：进页很久之后
      // 一张缩略图落地引起的 rerender，不该再开动画上下文。
      expect(rowFadeAnimationActive(false, 40000, 10000)).assertFalse();
    });

    it('从没揭示过就不放行', 0, (): void => {
      expect(rowFadeAnimationActive(false, 10000, 0)).assertFalse();
    });
  });

  describe('rowFadeTransition', () => {
    it('闩开着就带上时长和 stagger', 0, (): void => {
      const plan: RowFadeTransition = rowFadeTransition(false, true, 90, 42);
      expect(plan.enabled).assertTrue();
      expect(plan.duration).assertEqual(90);
      expect(plan.delay).assertEqual(42);
    });

    it('闩关了就整个不挂效果——不是把 duration 给 0', 0, (): void => {
      // 这一条是这轮改动的钉子：常驻 .animation() 给 0 挡不住动画上下文，
      // 换成 transition 之后"关掉"的写法必须是 TransitionEffect.IDENTITY。
      const plan: RowFadeTransition = rowFadeTransition(false, false, 90, 42);
      expect(plan.enabled).assertFalse();
      expect(plan.duration).assertEqual(0);
      expect(plan.delay).assertEqual(0);
    });

    it('滑动中一律不做入场动画', 0, (): void => {
      // 原判据照搬：chatTgsScrollActive 为真时 duration / delay 都给 0。
      const plan: RowFadeTransition = rowFadeTransition(true, true, 90, 42);
      expect(plan.enabled).assertFalse();
      expect(plan.duration).assertEqual(0);
    });

    it('两个条件都不成立时也是关的', 0, (): void => {
      expect(rowFadeTransition(true, false, 90, 42).enabled).assertFalse();
    });
  });

  // ── 首屏逐行揭示的 stagger（原 ChatPage.initialTimelineRowRevealDelay）──
  //
  // 返回的是**未经 powerAnimationDuration 换算**的裸毫秒，「动效强度」的倍率
  // 由页面在外面套。下面一律用真实取值 rowLimit=8 / staggerMs=14（见
  // util/chatPageTuning.ets），所以一波的名次是 0、14、…、98。
  describe('initialRowRevealDelay', () => {
    it('底部落点从下往上排：贴着输入框的那一行先亮', 0, (): void => {
      // 可见窗口 [10,17]，共 20 行；anchorIndex = -1 = 这次不是锚点落点。
      expect(initialRowRevealDelay(17, 10, 17, 20, -1, false, 8, 14)).assertEqual(0);
      expect(initialRowRevealDelay(16, 10, 17, 20, -1, false, 8, 14)).assertEqual(14);
      expect(initialRowRevealDelay(10, 10, 17, 20, -1, false, 8, 14)).assertEqual(98);
    });

    it('未读/续读落点从上往下排：从锚点流进未读块', 0, (): void => {
      expect(initialRowRevealDelay(10, 10, 17, 20, 10, true, 8, 14)).assertEqual(0);
      expect(initialRowRevealDelay(11, 10, 17, 20, 10, true, 8, 14)).assertEqual(14);
      expect(initialRowRevealDelay(17, 10, 17, 20, 10, true, 8, 14)).assertEqual(98);
    });

    it('同一行在两种落点下的名次是镜像的——方向写反首屏的波就扫反了', 0, (): void => {
      // 这条是这批最值钱的哨兵：anchorFromTop 或参数顺序写反都不会编译报错，
      // 只会让首屏那一波淡入从相反方向扫过来，肉眼一看就不对但没人来抓。
      const bottomTail: number = initialRowRevealDelay(17, 10, 17, 20, -1, false, 8, 14);
      const anchorTail: number = initialRowRevealDelay(17, 10, 17, 20, 10, true, 8, 14);
      expect(bottomTail).assertEqual(0);
      expect(anchorTail).assertEqual(98);
      const bottomHead: number = initialRowRevealDelay(10, 10, 17, 20, -1, false, 8, 14);
      const anchorHead: number = initialRowRevealDelay(10, 10, 17, 20, 10, true, 8, 14);
      expect(bottomHead).assertEqual(98);
      expect(anchorHead).assertEqual(0);
    });

    it('窗口外的行不排队，直接跟上', 0, (): void => {
      // 0 在这里是"不排队"，与"窗口内的第一名"同值但含义不同：同一次窗口里
      // 窗口内的 10 号行是 98，窗口外的 9 号行才是 0。
      expect(initialRowRevealDelay(9, 10, 17, 20, -1, false, 8, 14)).assertEqual(0);
      expect(initialRowRevealDelay(18, 10, 17, 20, -1, false, 8, 14)).assertEqual(0);
      expect(initialRowRevealDelay(10, 10, 17, 20, -1, false, 8, 14)).assertEqual(98);
    });

    it('名次封顶到 rowLimit-1：整屏都可见也不会排到天上去', 0, (): void => {
      // 窗口 [0,19] 比 rowLimit 长得多。没有这道封顶，第 20 行要等 266ms
      // 才起跑，早过了 rowFadeAnimationActive 的放行窗口，它就永远不淡入了。
      expect(initialRowRevealDelay(7, 0, 19, 20, 0, true, 8, 14)).assertEqual(98);
      expect(initialRowRevealDelay(8, 0, 19, 20, 0, true, 8, 14)).assertEqual(98);
      expect(initialRowRevealDelay(19, 0, 19, 20, 0, true, 8, 14)).assertEqual(98);
    });

    it('窗口还没量出来时按落点自己推一段', 0, (): void => {
      // first/last 还是首帧前的 -1：底部落点从末行往回取 8 行 → [12,19]。
      expect(initialRowRevealDelay(19, -1, -1, 20, -1, false, 8, 14)).assertEqual(0);
      expect(initialRowRevealDelay(12, -1, -1, 20, -1, false, 8, 14)).assertEqual(98);
      expect(initialRowRevealDelay(11, -1, -1, 20, -1, false, 8, 14)).assertEqual(0);
      // 锚点落点从锚点往下取 8 行 → [3,10]。
      expect(initialRowRevealDelay(3, -1, -1, 20, 3, true, 8, 14)).assertEqual(0);
      expect(initialRowRevealDelay(10, -1, -1, 20, 3, true, 8, 14)).assertEqual(98);
      expect(initialRowRevealDelay(11, -1, -1, 20, 3, true, 8, 14)).assertEqual(0);
    });

    it('anchorIndex 的负数是"不是锚点落点"的哨兵，不是"没找到"', 0, (): void => {
      // 页面侧必须先按 (stayAtUnread && firstUnreadId > 0) || resumeDividerId > 0
      // 判分支，命中才传 Math.max(0, groupIndexOf(...))，否则传 -1。把裸的
      // groupIndexOf 结果（找不到时也是 -1）直接丢进来，锚点落点会静默退化
      // 成底部落点：窗口从 [0,7] 变成 [12,19]。
      expect(initialRowRevealDelay(7, -1, -1, 20, 0, true, 8, 14)).assertEqual(98);
      expect(initialRowRevealDelay(7, -1, -1, 20, -1, true, 8, 14)).assertEqual(0);
    });

    it('选分支的判据与定方向的判据不是同一个条件，不许合并', 0, (): void => {
      // 原方法里选分支用 (stayAtUnread && firstUnreadId > 0) || resumeDividerId > 0，
      // 定方向用 stayAtUnread || resumeDividerId > 0——少了 firstUnreadId > 0
      // 那一半。stayAtUnread 为真但 firstUnreadId 是 0 时：窗口按底部推
      // （[12,19]），方向却是自顶向下。两者原本就各管各的。
      expect(initialRowRevealDelay(12, -1, -1, 20, -1, true, 8, 14)).assertEqual(0);
      expect(initialRowRevealDelay(13, -1, -1, 20, -1, true, 8, 14)).assertEqual(14);
      expect(initialRowRevealDelay(19, -1, -1, 20, -1, true, 8, 14)).assertEqual(98);
    });

    it('真实取值下，排最后的那一行仍在放行窗口之内起跑', 0, (): void => {
      // 跨文件的不变量：这一波 stagger 加一段淡入必须塞得进
      // INITIAL_ROW_FADE_WINDOW_MS，否则闩先关、末尾几行永远不淡入。
      // 头部注释里 420ms 的算式（7 × 14 + 90）在这里被钉住。
      const worst: number = initialRowRevealDelay(
        10, 10, 17, 20, -1, false,
        INITIAL_TIMELINE_REVEAL_ROW_LIMIT, INITIAL_TIMELINE_ROW_STAGGER_MS);
      expect(worst > 0).assertTrue();
      expect(worst).assertEqual(
        (INITIAL_TIMELINE_REVEAL_ROW_LIMIT - 1) * INITIAL_TIMELINE_ROW_STAGGER_MS);
      expect(worst + INITIAL_TIMELINE_ROW_FADE_MS <= INITIAL_ROW_FADE_WINDOW_MS).assertTrue();
    });
  });
}
