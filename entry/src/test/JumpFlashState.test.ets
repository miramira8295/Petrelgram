import { describe, expect, it } from '@ohos/hypium';
import { JumpFlashState, JumpFlashStateHost } from '../main/ets/pages/chat/JumpFlashState';
import { AlbumGroup, collapseAlbums } from '../main/ets/util/collapseAlbums';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { UserStore } from '../main/ets/store/UserStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { KEY_POWER_EFFECT_REPLY } from '../main/ets/store/AppSettings';
import { BubbleFocusChannel } from '../main/ets/util/bubbleFocusChannel';

// Landing geometry and cancellation use a fake Scroller and real timers.
// The row channel is pure state; visual easing still requires device review.
// Tests wait through the 150ms layout settling delay, then cancel the pulse.

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

// 假的 ArkUI Scroller：只覆写 getItemRect，返回值/是否抛异常都能从测试里
// 摆布。calls 记录每次被传入的下标——用来证明"某次调用到底有没有摸到
// scroller"，比如令牌失效之后的延迟回调，是不是真的连 getItemRect 都没走到。
class FakeScroller extends Scroller {
  rect: RectResult = { x: 0, y: 0, width: 0, height: 0 };
  shouldThrow: boolean = false;
  calls: number[] = [];

  getItemRect(index: number): RectResult {
    this.calls.push(index);
    if (this.shouldThrow) {
      throw new Error('row not laid out');
    }
    return this.rect;
  }
}

// 宿主（ChatPage）暴露给控制器的那一小片接口的替身，形状照抄
// ChatOverlayState.test.ets 的 FakeHost：三个取值器全部只记账，不做真实业务逻辑。
class FakeHost implements JumpFlashStateHost {
  scrollerValue: FakeScroller = new FakeScroller();
  scrollerCalls: number = 0;
  groupsValue: AlbumGroup[] = [];
  groupsCalls: number = 0;
  effectDurationCalls: string[] = [];
  motionEnabled: boolean = true;

  scroller: () => Scroller = (): Scroller => {
    this.scrollerCalls++;
    return this.scrollerValue;
  };
  groups: () => AlbumGroup[] = (): AlbumGroup[] => {
    this.groupsCalls++;
    return this.groupsValue;
  };
  effectDuration: (key: string, ms: number) => number = (key: string, ms: number): number => {
    this.effectDurationCalls.push(key);
    return this.motionEnabled ? ms : 0;
  };
}

function controllerOn(host: FakeHost): JumpFlashState {
  const controller: JumpFlashState = new JumpFlashState();
  controller.bind(host);
  return controller;
}

// —— 下面三个仅供"syncFlashRect 早退分支"那条用例使用 ——
// 需要一份真实的 AlbumGroup，不手搭 30+ 字段的字面量，照
// CollapseAlbumsKey.test.ets 的 baseEntry() 写法用
// buildMessageEntry()+collapseAlbums() 现算，group.memberIds 才是真实的
// groupIndexOf() 认得出来的形状。

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function usersOf(): UserStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  client.start();
  return new UserStore(client);
}

function baseEntry(id: number, users: UserStore): MessageEntry {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = 'hi';
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 1;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['is_outgoing'] = false;
  message['sender_id'] = sender;
  message['date'] = 1000;
  message['content'] = content;
  return buildMessageEntry(message, users);
}

function groupsWithMessage(id: number): AlbumGroup[] {
  return collapseAlbums([baseEntry(id, usersOf())]);
}

export default function jumpFlashStateTest() {
  describe('JumpFlashState', () => {

    it('focus changes only the target row and resets the previous target', 0, () => {
      const channel: BubbleFocusChannel = new BubbleFocusChannel();
      const first: number[] = [];
      const second: number[] = [];
      const stopFirst = channel.subscribe(11, (value: number): void => { first.push(value); });
      const stopSecond = channel.subscribe(22, (value: number): void => { second.push(value); });
      channel.set(11, 1);
      expect(first).assertDeepEquals([0, 1]);
      expect(second).assertDeepEquals([0]);
      channel.set(22, 1);
      expect(first).assertDeepEquals([0, 1, 0]);
      expect(second).assertDeepEquals([0, 1]);
      channel.clear();
      expect(second).assertDeepEquals([0, 1, 0]);
      stopFirst();
      stopSecond();
    });

    it('recycled rows unsubscribe and a new page cannot inherit focus', 0, () => {
      const channel: BubbleFocusChannel = new BubbleFocusChannel();
      const otherPage: BubbleFocusChannel = new BubbleFocusChannel();
      channel.set(11, 1);
      let current: number = -1;
      const stop = channel.subscribe(11, (value: number): void => { current = value; });
      expect(current).assertEqual(1);
      expect(otherPage.value(11)).assertEqual(0);
      stop();
      channel.clear();
      expect(current).assertEqual(1);
      const rebound: number[] = [];
      const stopRebound = channel.subscribe(22, (value: number): void => { rebound.push(value); });
      channel.set(11, 1);
      expect(rebound).assertDeepEquals([0]);
      stopRebound();
    });

    it('index-only jumps retain identity when history is prepended during settling', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.groupsValue = groupsWithMessage(77);
        host.scrollerValue.rect = { x: 0, y: 10, width: 100, height: 40 };
        const controller: JumpFlashState = controllerOn(host);
        controller.flashAtIndex(0);
        host.groupsValue = groupsWithMessage(66).concat(host.groupsValue);
        await sleep(170);
        expect(host.scrollerValue.calls[0]).assertEqual(1);
        controller.cancelFlash();
      });

    it('dispose cancels a pending landing and clears active row feedback', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.groupsValue = groupsWithMessage(77);
        host.scrollerValue.rect = { x: 0, y: 10, width: 100, height: 40 };
        const controller: JumpFlashState = controllerOn(host);
        controller.focus.set(77, 1);
        controller.flashAtIndex(0);
        controller.dispose();
        await sleep(170);
        expect(controller.focus.value(77)).assertEqual(0);
        expect(controller.shown).assertFalse();
        expect(host.scrollerValue.calls.length).assertEqual(0);
      });

    it('disabled motion does not leave an enlarged target', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      host.motionEnabled = false;
      host.groupsValue = groupsWithMessage(77);
      host.scrollerValue.rect = { x: 0, y: 10, width: 100, height: 40 };
      const controller: JumpFlashState = controllerOn(host);
      controller.flashAtIndex(0, 77);
      await sleep(170);
      expect(controller.shown).assertFalse();
      expect(controller.focus.value(host.groupsValue[0].head.rowId)).assertEqual(0);
    });

    // 防的回归：flashAtIndex 的 150ms 延迟回调算 top/height 的那一段被删掉、
    // 或者算完了不写 shown。假 scroller 返回一个可控的矩形，等 150ms 过去，
    // 三个字段应该原样落到 flashAtIndex 传下来的矩形上。
    it('flashAtIndex 用假 scroller 算出 top/height，并把 shown 置真', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 42, width: 100, height: 64 };
      const controller: JumpFlashState = controllerOn(host);

      controller.flashAtIndex(4);
      await sleep(170);

      expect(controller.shown).assertTrue();
      expect(controller.top).assertEqual(42);
      expect(controller.height).assertEqual(64);
      expect(host.scrollerValue.calls.indexOf(4) >= 0).assertTrue();
      // 顺带证明 effectDuration 确实被 runPulse 用正确的 key 转发过——host
      // 转手有没有接对，这一步就是全部证据（不依赖 animateTo 回调本身是否
      // 已经跑完，见文件头环境限制 2）。
      expect(host.effectDurationCalls.indexOf(KEY_POWER_EFFECT_REPLY) >= 0).assertTrue();

      controller.cancelFlash(); // 收尾：取消后续回弹定时器
    });

    // 防的回归：flashAtIndex 拿到的矩形 height<=0（行还没排好版）时不该点
    // 亮。这道判据和"抛异常"是两条独立的早退分支，各自可能被单独削弱，分开测。
    it('flashAtIndex 遇到 height<=0 的矩形时不点亮', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 5, width: 10, height: 0 };
      const controller: JumpFlashState = controllerOn(host);

      controller.flashAtIndex(3);
      await sleep(170);

      expect(controller.shown).assertFalse();
      expect(controller.top).assertEqual(0);
      expect(controller.height).assertEqual(0);
    });

    // 防的回归：getItemRect 抛异常（行被回收/下标越界）时，catch 分支被削弱
    // 成不返回，让后面的代码拿着没赋上值的 top/height 继续往下跑。
    it('getItemRect 抛异常时不改字段', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.shouldThrow = true;
      const controller: JumpFlashState = controllerOn(host);

      controller.flashAtIndex(5);
      await sleep(170);

      expect(controller.shown).assertFalse();
      expect(controller.top).assertEqual(0);
      expect(controller.height).assertEqual(0);
      expect(controller.alpha).assertEqual(0);
      // 证明这不是"根本没调用"的巧合空过：确实摸到了 scroller，且确实是拿
      // idx=5 去问的。
      expect(host.scrollerValue.calls).assertDeepEquals([5]);
    });

    // 防的回归：flashSeq 的"比较后不执行"取消语义被削弱——cancelFlash() 之
    // 后，已经排队的 150ms 延迟回调不该再写任何字段。
    it('cancelFlash 之后，flashAtIndex 排的延迟回调不写任何字段', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 9, width: 9, height: 9 };
      const controller: JumpFlashState = controllerOn(host);

      controller.flashAtIndex(9);
      controller.cancelFlash(); // 抢在 150ms 之前把令牌作废
      await sleep(170);

      expect(controller.shown).assertFalse();
      expect(controller.top).assertEqual(0);
      expect(controller.height).assertEqual(0);
      expect(controller.alpha).assertEqual(0);
      // 令牌比较发生在 flashAtIndex 回调的第一行——如果它没能挡住，下面这行
      // 就会看到一次真实的 getItemRect(9) 调用。
      expect(host.scrollerValue.calls.length).assertEqual(0);
    });

    // 防的回归：连续两次 flashAtIndex，前一次排的延迟回调应该被后一次领到
    // 的新 seq 作废——即使前一次的矩形本身是合法的（能通过 height>0 检
    // 查），它也不该覆盖后一次的结果，更不该真的去问 scroller。
    it('连续两次 flashAtIndex：前一次的延迟回调被后一次的 seq 作废', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 20, width: 20, height: 20 };
      const controller: JumpFlashState = controllerOn(host);

      controller.flashAtIndex(1); // 第一次：马上被下面这次作废
      controller.flashAtIndex(2); // 第二次：真正落地的这一次
      await sleep(170);

      expect(controller.shown).assertTrue();
      expect(controller.top).assertEqual(20);
      expect(controller.height).assertEqual(20);
      // 关键断言：第一次的下标 1 从没被拿去问过 scroller——如果令牌检查被
      // 削弱，这里会看到 1 也出现在 calls 里。
      expect(host.scrollerValue.calls.indexOf(1)).assertEqual(-1);
      expect(host.scrollerValue.calls.indexOf(2) >= 0).assertTrue();

      controller.cancelFlash();
    });

    // 防的回归：syncFlashRect 顶部的"没在显示就直接返回"被删掉或削弱。先用
    // 一次真实落地过的 flashAtIndex(targetId>0) 把 flashTargetId 摆成非
    // 零，再用 cancelFlash() 把 shown 单独按回 false——cancelFlash 不清
    // flashTargetId/flashTargetIdx，这两个字段原样留着。这样如果早退判据
    // 被删，syncFlashRect 会往下走到
    // groupIndexOf(host.groups(), flashTargetId) 那一步，读点由 groupsCalls
    // 计数器抓出来。
    it('syncFlashRect 在 shown 为假时直接返回，不碰 groups/scroller', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      host.scrollerValue.rect = { x: 0, y: 5, width: 5, height: 15 };
      host.groupsValue = groupsWithMessage(77);
      const controller: JumpFlashState = controllerOn(host);

      controller.flashAtIndex(0, 77);
      await sleep(170);
      expect(controller.shown).assertTrue(); // 确认真的落地了，flashTargetId 才有非零值

      controller.cancelFlash();
      expect(controller.shown).assertFalse();

      host.groupsCalls = 0;
      host.scrollerValue.calls = [];

      controller.syncFlashRect();

      expect(host.groupsCalls).assertEqual(0);
      expect(host.scrollerValue.calls.length).assertEqual(0);
    });

    // ——— 以下三条是验收时补的：syncFlashRect 的四条分支原本一条没测，也没
    // 进 skippedAreas，等于用沉默代替了理由。其中两条正是 issue #80 的本体
    // （按 id 重解下标、高亮期间滚动重定位），是这一簇存在的全部意义。
    // 三条都是同步的，不用等定时器。———

    // 防的回归：`if (this.flashTargetId > 0) idx = groupIndexOf(...)` 这一步
    // 被删掉，或者 `idx < 0` 之后不 cancelFlash 而是 return。
    // 目标行整个从 groups 里消失（被滚出窗口、数据换了）时，高亮必须收掉——
    // 留着就是一条悬空的色带，钉在一个已经不是目标的行上。
    it('syncFlashRect：目标行从 groups 里消失时收掉高亮（不是留一条悬空色带）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.scrollerValue.rect = { x: 0, y: 5, width: 5, height: 15 };
        host.groupsValue = groupsWithMessage(77);
        const controller: JumpFlashState = controllerOn(host);

        controller.flashAtIndex(0, 77);
        await sleep(170);
        expect(controller.shown).assertTrue(); // 阳性对照：确实点亮过

        host.groupsValue = groupsWithMessage(88); // 77 没了
        controller.syncFlashRect();

        expect(controller.shown).assertFalse();
      });

    // 防的回归：syncFlashRect 里 getItemRect 的 catch 从 cancelFlash() 被改成
    // return。这两处的语义**是相反的**，很容易被"统一"掉：
    //   flashAtIndex 的 catch → return（还没点亮，什么都不做）
    //   syncFlashRect 的 catch → cancelFlash（已经亮着，要主动收掉）
    // 改成 return 的后果是：行一旦布局不出来，高亮就永远停在最后一次对上的
    // 位置，跟着页面滚，谁也收不掉它。
    it('syncFlashRect：getItemRect 抛异常时收掉高亮（与 flashAtIndex 的 catch 语义相反）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.scrollerValue.rect = { x: 0, y: 5, width: 5, height: 15 };
        host.groupsValue = groupsWithMessage(77);
        const controller: JumpFlashState = controllerOn(host);

        controller.flashAtIndex(0, 77);
        await sleep(170);
        expect(controller.shown).assertTrue(); // 阳性对照

        host.scrollerValue.shouldThrow = true;
        controller.syncFlashRect();

        expect(controller.shown).assertFalse();
      });

    // 防的回归：`|Δtop| > 0.5` 那道重定位判据被删（每帧都写，白白标脏）或者
    // 被反向（超过阈值反而不写，高亮就跟不上行了）。
    // 这条就是计划里"高亮期间滚动不错位（issue #80 场景）"要防的东西：行高
    // 在闪烁期间变了（链接预览到货、缩略图撑开），高亮层必须跟着重新对位。
    it('syncFlashRect：位移超过 0.5 才重定位，没超过不写（issue #80 的重定位判据）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.scrollerValue.rect = { x: 0, y: 5, width: 5, height: 15 };
        host.groupsValue = groupsWithMessage(77);
        const controller: JumpFlashState = controllerOn(host);

        controller.flashAtIndex(0, 77);
        await sleep(170);
        expect(controller.top).assertEqual(5); // 阳性对照：第一次对位

        // 位移 0.3 < 0.5：判据认为没动，不回写。
        host.scrollerValue.rect = { x: 0, y: 5.3, width: 5, height: 15 };
        controller.syncFlashRect();
        expect(controller.top).assertEqual(5);

        // 位移 40 > 0.5：必须跟上去。
        host.scrollerValue.rect = { x: 0, y: 45, width: 5, height: 15 };
        controller.syncFlashRect();
        expect(controller.top).assertEqual(45);
      });

    // 防的回归：把控制器做成模块级单例，两个 ChatPage（比如平板分栏）共用
    // 一份高亮状态。这里额外验证的不只是显示态字段互不串台，还验证了
    // flashSeq 这枚取消令牌本身没有被两个实例共享——如果共享，B 排的
    // flashAtIndex 会把 A 已经排队但还没到期的延迟回调一起作废掉（令牌比较
    // 会认为 A 的回调过期）。
    //
    // 【本条没有对应的 regressionDetector】
    // JumpFlashState 的 top/height/alpha/shown/flashSeq/flashTargetIdx/
    // flashTargetId 全部是普通实例字段（@Trace 装饰的那四个更是明确要求
    // 装在实例上），类里没有一处 static、没有模块级可变状态。要在这个类
    // 内部制造出"两个实例共享状态"的效果，唯一的办法是把某个字段声明成
    // static——但 TypeScript 对 static 成员是名义访问，`this.xxx` 引用一个
    // static 字段会直接编译不过（TS2339），必须同时把类内所有
    // `this.flashSeq` 之类的引用改成 `JumpFlashState.flashSeq`，这已经不是
    // "改一行"能做到的破坏，也不满足"破法要能在运行期体现，不能是一改就
    // 编译不过"的要求。真正的单例风险出在 ChatPage 那一侧的字段初始化器
    // 写法（`flash: JumpFlashState = new JumpFlashState();` vs 手滑写成模
    // 块级共享变量），不在 JumpFlashState.ets 内部——这条用例因此没有列进
    // 下面的 regressionDetectors，如实说明，不硬凑一条改了也不会红的假检测点。
    it('两个实例互不影响（防的回归：做成模块级单例，分栏两页共用一份状态/令牌）', 0,
      async (): Promise<void> => {
        const hostA: FakeHost = new FakeHost();
        hostA.scrollerValue.rect = { x: 0, y: 11, width: 11, height: 11 };
        const a: JumpFlashState = controllerOn(hostA);

        const hostB: FakeHost = new FakeHost();
        hostB.scrollerValue.rect = { x: 0, y: 22, width: 22, height: 22 };
        const b: JumpFlashState = controllerOn(hostB);

        a.flashAtIndex(5); // A 先排一个延迟回调
        b.flashAtIndex(6); // B 紧接着也排一个——如果令牌是共享的，这一步会作废 A 那个

        await sleep(170);

        expect(a.shown).assertTrue();
        expect(a.top).assertEqual(11);
        expect(a.height).assertEqual(11);
        expect(b.shown).assertTrue();
        expect(b.top).assertEqual(22);
        expect(b.height).assertEqual(22);
        expect(hostA.scrollerValue.calls.indexOf(5) >= 0).assertTrue();
        expect(hostB.scrollerValue.calls.indexOf(6) >= 0).assertTrue();

        a.cancelFlash();
        b.cancelFlash();
      });
  });
}

// Visual scale/brightness interpolation is checked on device, not in the host runner.
