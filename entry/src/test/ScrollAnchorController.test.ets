import { describe, expect, it } from '@ohos/hypium';
import { LengthMetrics } from '@kit.ArkUI';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import { ScrollAnchorController, ScrollAnchorHost } from '../main/ets/pages/chat/ScrollAnchorController';

// 锚点复位簇（第二轮 R2-B）的**执行层**测试。
//
// 【为什么这份测试是那一批的正当性来源】
// util/anchorRestore.ets 的单测钉的是纯判据——planAnchorRestore 该给出什么
// plan、shouldRetryAnchorRestore 该不该再来一次。它们钉不到"页面拿到 plan
// 之后有没有照做、照做时参数对不对"。而这一簇恰恰是全文件回归史最烂的一段：
// 556c5fa → 351dab9 → 720a485(revert) → 0b62293 → ca5bde9 → ecce2fd →
// 32064be → 63ccaf0 → da6f52f → 90f75ad，十个 commit、一次 revert、一次
// "删了再加回来"，十次里**没有一次是本地手段发现的**，全靠真机日志和用户报障。
// 搬进 ScrollAnchorController 换来的就是下面这几条：代次作废、三种早退、
// 重试阶梯到 reposition，第一次有了本地防线。
//
// 【断言的是"对 scroller 发了什么指令"，不是"某个纯函数被调用过"】
// 断言 planAnchorRestore 被调用过是没有意义的——把被防的代码删掉，那种断言
// 也不变。所以每条用例看的都是 FakeScroller 上记下来的调用与参数。
//
// 【假 Scroller 是子类化，不是对象字面量】
// 环境结论照抄 JumpFlashState.test.ets 的文件头：`Scroller` 是 class 不是
// interface，ArkTS 对 class 走名义类型，对象字面量顶不上，必须
// `class FakeScroller extends Scroller`。本文件在它之上多覆写了 scrollBy /
// scrollToIndex / currentOffset 三个——这三个此前没有先例，落地前专门用一份
// 临时探针测试证过：覆写成立，且经基类引用调用走的是覆写体（多态生效）。
//
// 【等的是真时间】
// ANCHOR_RESTORE_RETRY_MS = 16、ANCHOR_RESTORE_ATTEMPTS = 3 都写死在
// util/anchorRestore.ets 里，不经 host 转发，测试没法把它们调快。重试阶梯那条
// 要等 0 + 16 + 16 = 32ms 才走到 reposition，这里等 80ms 留足余量。

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

class ScrollByCall {
  dy: number = 0;
}

class ScrollToIndexCall {
  index: number = 0;
  smooth: boolean = false;
  align: number = -1;
  extraOffset: number = Number.NaN;
}

// 假的 ArkUI Scroller：四个方法全部只记账，一律不调 super——真正的原生绑定
// 实现完全不会被触达。
class FakeScroller extends Scroller {
  rect: RectResult = { x: 0, y: 0, width: 0, height: 0 };
  offsetY: number = 0;
  rectCalls: number[] = [];
  byCalls: ScrollByCall[] = [];
  indexCalls: ScrollToIndexCall[] = [];

  getItemRect(index: number): RectResult {
    this.rectCalls.push(index);
    return this.rect;
  }

  scrollBy(dx: Length, dy: Length) {
    const call: ScrollByCall = new ScrollByCall();
    call.dy = typeof dy === 'number' ? dy as number : Number.NaN;
    this.byCalls.push(call);
  }

  scrollToIndex(value: number, smooth?: boolean, align?: ScrollAlign, options?: ScrollToIndexOptions) {
    const call: ScrollToIndexCall = new ScrollToIndexCall();
    call.index = value;
    call.smooth = smooth === true;
    call.align = align === undefined ? -1 : align as number;
    call.extraOffset = options === undefined
      ? Number.NaN : (options.extraOffset as LengthMetrics).value;
    this.indexCalls.push(call);
  }

  currentOffset(): OffsetResult {
    return { xOffset: 0, yOffset: this.offsetY };
  }

  // 这一簇有没有"完全没碰过 scroller"，是代次作废与三处早退的共同判据。
  untouched(): boolean {
    return this.rectCalls.length === 0 && this.byCalls.length === 0 && this.indexCalls.length === 0;
  }
}

// 宿主替身：七个取值器的返回值都能在用例中间随时改——这正是"取值器是触发那
// 一刻现取、不是 bind 时快照"这条要证的东西。
class FakeHost implements ScrollAnchorHost {
  scrollerValue: FakeScroller = new FakeScroller();
  userOffset: number = 0;
  scrollActive: boolean = false;
  jumpId: number = 0;
  bottomPending: boolean = false;
  chromeH: number = 153;
  gateProbeCalls: number = 0;

  scroller: () => Scroller = (): Scroller => this.scrollerValue;
  userScrollOffsetTotal: () => number = (): number => this.userOffset;
  timelineScrollActive: () => boolean = (): boolean => this.scrollActive;
  pendingJumpId: () => number = (): number => this.jumpId;
  pendingScrollBottom: () => boolean = (): boolean => this.bottomPending;
  headerChromeHeight: () => number = (): number => this.chromeH;
  appendGateProbe: (groups: AlbumGroup[]) => string = (_groups: AlbumGroup[]): string => {
    this.gateProbeCalls++;
    return 'probe';
  };
}

function controllerOn(host: FakeHost): ScrollAnchorController {
  const controller: ScrollAnchorController = new ScrollAnchorController();
  controller.bind(host);
  return controller;
}

export default function scrollAnchorControllerTest() {
  describe('ScrollAnchorController', () => {

    // 【1】代次作废：跳转/贴底这类更强的定位意图会作废本轮复位。
    // 现行实现故意不持定时器句柄——已排队的回调仍会触发，靠 attemptAnchorRestore
    // 开头那句代次比对空转返回。所以这里断言的是"连 getItemRect 都没摸到"，
    // 而不是"定时器被清了"。
    it('invalidate 之后那一轮复位连 scroller 都不碰', 0, async () => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 40, width: 300, height: 60 };
      const c: ScrollAnchorController = controllerOn(host);

      c.restoreScrollAnchor(7, 10);
      c.invalidate();
      await sleep(40);

      expect(host.scrollerValue.untouched()).assertTrue();
    });

    // 【2】pendingJumpId 早退。**同时证明取值器是触发那一刻现取**：
    // restoreScrollAnchor 调用时 jumpId 还是 0，是在排队之后才置的非 0。
    // 如果控制器在 bind 时把值快照下来，这条就会红。
    it('复位排队之后才出现的 pendingJumpId 也能拦住它', 0, async () => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 40, width: 300, height: 60 };
      const c: ScrollAnchorController = controllerOn(host);

      c.restoreScrollAnchor(7, 10);
      host.jumpId = 555;
      await sleep(40);

      expect(host.scrollerValue.untouched()).assertTrue();
    });

    it('复位排队之后才出现的 pendingScrollBottom 也能拦住它', 0, async () => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 40, width: 300, height: 60 };
      const c: ScrollAnchorController = controllerOn(host);

      c.restoreScrollAnchor(7, 10);
      host.bottomPending = true;
      await sleep(40);

      expect(host.scrollerValue.untouched()).assertTrue();
    });

    // 【3】用户正在滑就让路——不把手势或惯性滚动拉回去。
    it('用户正在拖动时不发任何滚动指令', 0, async () => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 40, width: 300, height: 60 };
      const c: ScrollAnchorController = controllerOn(host);

      host.scrollActive = true;
      c.restoreScrollAnchor(7, 10);
      await sleep(40);

      expect(host.scrollerValue.untouched()).assertTrue();
    });

    // 【4】量得到就只补差值：scrollBy(0, dy)，**不碰 scrollToIndex**。
    // 后者会让 List 从给定下标起全量重测，真机 Frame trace 里最大的几个尖峰
    // 就是它。
    it('量得到锚点行时只 scrollBy 差值，不调 scrollToIndex', 0, async () => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 40, width: 300, height: 60 };
      const c: ScrollAnchorController = controllerOn(host);

      c.restoreScrollAnchor(7, 10);
      await sleep(40);

      expect(host.scrollerValue.byCalls.length).assertEqual(1);
      expect(host.scrollerValue.byCalls[0].dy).assertEqual(30);
      expect(host.scrollerValue.indexCalls.length).assertEqual(0);
    });

    // 【5】本批测试的主要目标：重试阶梯用尽之后的 reposition 分支。
    // 这是全簇唯一带 revert 史又零覆盖的分支——ecce2fd 删掉、32064be 依据
    // 2026-08-29 那份天然 A/B（只量一次的那半 31 次里放弃 22 次，71%）加回来、
    // da6f52f 又按真机 residual 153/153/153/770 给算式补上 + headerChromeHeight()。
    //
    // 断言 extraOffset = -targetY + headerChromeHeight()：targetY 这里等于
    // itemY（用户没滑，userDelta = 0），所以是 -10 + 153 = 143。
    // 同时断言 scrollBy 一次都没被调用——旧兜底是 scrollToIndex 再 scrollBy
    // 分两步走，那一步之间是看得见的，现在必须一次调用完成。
    it('量不到时重试三次，用尽后一步式 scrollToIndex 定位', 0, async () => {
      const host: FakeHost = new FakeHost();
      // 全 0 矩形 = 非法下标/未排版（faqs-arkui-572），planAnchorRestore 走 fallback 支。
      host.scrollerValue.rect = { x: 0, y: 0, width: 0, height: 0 };
      const c: ScrollAnchorController = controllerOn(host);

      c.restoreScrollAnchor(7, 10);
      await sleep(80);

      expect(host.scrollerValue.rectCalls.length).assertEqual(3);
      expect(host.scrollerValue.byCalls.length).assertEqual(0);
      expect(host.scrollerValue.indexCalls.length).assertEqual(1);
      const call: ScrollToIndexCall = host.scrollerValue.indexCalls[0];
      expect(call.index).assertEqual(7);
      expect(call.smooth).assertFalse();
      expect(call.align).assertEqual(ScrollAlign.START as number);
      expect(call.extraOffset).assertEqual(143);
    });

    // 【6】捕获之后用户自己滑动过，就整轮让路。
    //
    // 判据是 canApplyAnchorRestore = `!scrollActive && Math.abs(userDelta) < 0.5`
    // ——**闸门比修正项更严**。所以"用户滑了一段"的正常结局不是"把 targetY 调整
    // 一下再补"，而是**一个指令都不发**：在一个布局帧里补一次跨屏的 scrollBy，
    // 会把顺滑的惯性变成看得见的跳页。这条和【3】是同一道闸的两个入口
    // （那条走 scrollActive，这条走 userDelta）。
    it('捕获之后用户滑过一段距离时整轮让路', 0, async () => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 40, width: 300, height: 60 };
      const c: ScrollAnchorController = controllerOn(host);

      c.restoreScrollAnchor(7, 10, 0);
      host.userOffset = 12;
      await sleep(40);

      expect(host.scrollerValue.byCalls.length).assertEqual(0);
      expect(host.scrollerValue.indexCalls.length).assertEqual(0);
    });

    // 【6b】亚像素位移（< 0.5）不触发让路，此时 targetY 才真的会被扣减。
    // anchorYAfterUserScroll(capturedY=10, atCapture=0, now=0.4) = 10 - 0.4 = 9.6，
    // 量到的 y 是 40 → dy = 40 - 9.6 = 30.4（不是 30）。
    // 这 0.4 的差值就是 util 里那个修正项唯一能被执行到的场合——把它钉住，
    // 免得有人看它"永远约等于 capturedY"就顺手删掉。
    it('亚像素位移下 targetY 仍按用户滚动量扣减', 0, async () => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 40, width: 300, height: 60 };
      const c: ScrollAnchorController = controllerOn(host);

      c.restoreScrollAnchor(7, 10, 0);
      host.userOffset = 0.4;
      await sleep(40);

      expect(host.scrollerValue.byCalls.length).assertEqual(1);
      expect(host.scrollerValue.byCalls[0].dy).assertEqual(30.4);
    });

    // 【7】primeBeforeLayout：排版前先按 START + extraOffset 落一次位，
    // 与 reposition 用的是同一个算式（-itemY + headerChromeHeight()）。
    it('primeBeforeLayout 会在排队前先定位一次', 0, async () => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 10, width: 300, height: 60 };
      const c: ScrollAnchorController = controllerOn(host);

      c.restoreScrollAnchor(7, 10, Number.NaN, true);

      // prime 是同步发生的，不等定时器。
      expect(host.scrollerValue.indexCalls.length).assertEqual(1);
      expect(host.scrollerValue.indexCalls[0].extraOffset).assertEqual(143);
      await sleep(40);
    });

    // 【8】找不到锚点行时不发指令。groups 传空数组 → groupIndexOf 回 -1 → 早退。
    // 两侧的差别也一并钉住：append 的 lost 分支要打 appendAnchorGateProbe，
    // prepend 的早退分支不打。
    it('锚点消息不在当前 groups 里时直接放弃，append 侧仍打探针', 0, async () => {
      const host: FakeHost = new FakeHost();
      const c: ScrollAnchorController = controllerOn(host);

      c.restorePrependAnchor([], 123, 10);
      c.restoreAppendAnchor([], 123, 10);
      await sleep(40);

      expect(host.scrollerValue.untouched()).assertTrue();
      expect(host.gateProbeCalls).assertEqual(1);
    });
  });
}
