import { describe, expect, it } from '@ohos/hypium';
import { JumpFlashState, JumpFlashStateHost } from '../main/ets/pages/chat/JumpFlashState';
import { AlbumGroup, collapseAlbums } from '../main/ets/util/collapseAlbums';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { UserStore } from '../main/ets/store/UserStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { KEY_POWER_EFFECT_REPLY } from '../main/ets/store/AppSettings';

// 跳转目标高亮控制器（flash 簇，B13 从 ChatPage 整体搬出）的测试。写法照抄
// ChatOverlayState.test.ets：FakeHost + sleep() 真实等待 + 文件头先讲环境限制。
//
// 【环境限制 1：假 scroller 是子类化，不是对象字面量】
// JumpFlashStateHost.scroller() 的返回类型是 ArkUI 的 `Scroller`——
// component/scroll.d.ts 里的 `declare class Scroller`，是 class 不是
// interface。ArkTS 对 class 类型走名义类型（nominal typing），一个只实现了
// `getItemRect` 的对象字面量不能直接当 `Scroller` 用；本仓其余控制器测试
// 遇到的都是自定义的小 Host 接口（interface，结构类型可以直接用对象字面量
// 顶），这是本仓第一次需要假冒一个 ArkUI 内置控制器类，没有先例可抄。这里
// 用 `class FakeScroller extends Scroller`，只覆写 `getItemRect`，不调用
// `super.getItemRect()`——真正的原生绑定实现完全不会被触达。构造函数走
// `Scroller` 自带的无参构造：本仓所有页面都是在字段初始化器里
// `new Scroller()`、从不传参，且 SDK 文档原文写的是 "Scroller APIs cannot
// be called effectively" before binding（暗示对象本身能造出来，只是未绑定
// 组件时调用方法会报错）——这正是 flashAtIndex/syncFlashRect 那两处
// try/catch 要接住的异常，也是下面"抛异常"那条用例的依据。
//
// 【环境限制 2：animateTo 的回调是否同步执行，借用 SelectionSession 的既有证据】
// runBlink 用 `animateTo({...}, () => { this.alpha = ... })` 包住 alpha 翻转。
// 本仓没有在真机上专门验证过 animateTo 在没有渲染树的本地单元测试环境下是否
// 同步执行回调，但 SelectionSession.test.ets 已经有等价证据：
// `session.enter([301, 302, 303])`（内部 animateSelection 用 animateTo 包住
// active/ids 翻转）后面紧跟不等待的同步断言
// `expect(session.ids.length).assertEqual(3)`，而那个文件是绿的——说明
// animateTo 的回调在这套本地单元测试运行时里就是同步执行的。为了不让下面
// 的用例绑死在这条环境结论上，凡是经由 animateTo 才会翻转的字段（alpha 变
// 成 1/0 那两步），本文件一律不断言具体数值，只断言不经过 animateTo 的
// shown/top/height 三个字段；effectDuration 的转发验证也只看"有没有被调用
// 到"，不依赖 animateTo 回调本身是否已经跑完。
//
// 【真实定时器，等的是真时间】
// flashAtIndex 的 150ms、runBlink 内部的两个 340ms 都是写死在源码里的常量，
// 不经过 host 转发，测试没法把它们调快。下面的用例只等第一拍落地需要的
// 150ms（留一点余量等到 170ms），不追等后续的 340ms 两拍闭环——追等一次要
// 多等约 1.5 秒，用例数一多会显著拖慢整个套件，而两拍本身唯一的分支判据
// （flashSeq 比较）已经被"连续两次调用"和"cancelFlash 之后"那两条用例覆盖
// 到了，详见文件末尾 skippedAreas 的说明。

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
    return ms;
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
      // 顺带证明 effectDuration 确实被 runBlink 用正确的 key 转发过——host
      // 转手有没有接对，这一步就是全部证据（不依赖 animateTo 回调本身是否
      // 已经跑完，见文件头环境限制 2）。
      expect(host.effectDurationCalls.indexOf(KEY_POWER_EFFECT_REPLY) >= 0).assertTrue();

      controller.cancelFlash(); // 收尾：别让后续两拍的 340ms 定时器悬到后面的用例里
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

// 【skippedAreas —— 没写测试的方法/分支，各自的原因】
//
// 【验收时的更正】这份清单最初漏了 syncFlashRect 的四条分支：按 id 重解下标、
// idx<0 收掉高亮、getItemRect 抛异常收掉高亮、|Δtop|>0.5 才重定位。它们既没有
// 用例、也没有出现在下面的清单里——等于用沉默代替了理由，而其中两条正是
// issue #80 的本体（下标漂移、滚动中错位），是这一簇存在的全部意义。四条全都
// 是同步的、用现成的 FakeHost/FakeScroller 就能测，不受下面任何一条环境限制
// 影响。验收时补了三条用例覆盖它们（见上方"以下三条是验收时补的"那一段）。
// 教训：清单只列"我想到的"，等于没列；写清单时应当把被测方法的每条分支过一遍。
//
// - runBlink()：private，没有公开访问点，只能通过 flashAtIndex 间接触发。
//   它内部的令牌失效判据（seq !== this.flashSeq）已经被"连续两次调用"和
//   "cancelFlash 之后"两条用例间接覆盖到；但两拍 340ms 的完整闭环——第二拍
//   的 syncFlashRect/animateTo、recursion 到 remaining=0 时把
//   shown/alpha 收尾复位——没有端到端跑满。原因：每条用例要多等约 1.5 秒
//   才能看到 remaining<=0 的收尾，而这段代码唯一的分支判据（同一处
//   flashSeq 比较）已经被更短的用例覆盖，追加收益有限、拖慢套件。
// - dispose()：源码注释明确写"有意留空"（对照 aboutToDisappear 全链路核实
//   过原代码在这一簇上没有任何清理）。当前没有任何字段变化或副作用可断
//   言，写一条"调用后什么都没变"的用例价值有限，故未写；如后续这里改成真
//   的做清理（加固），再补对应用例钉住新行为。
// - bind()：只有一行 `this.host = host;` 赋值，没有分支逻辑，已经在
//   controllerOn() 辅助函数里被本文件所有其它用例间接跑到，不必单独立一条。
// - logW 的具体日志文案格式：全局工具函数，不依赖任何页面/控制器状态，超
//   出本控制器职责范围（与其它控制器测试对 logE/logW 的处理一致，见
//   ChatOverlayState.test.ets）。
// - animateTo 的视觉过渡效果本身（是否真的渐显/渐隐、曲线是否正确）：本地
//   单元测试没有真实渲染树，只能验证回调触发后的字段翻转，过渡效果的视觉
//   正确性需要真机验收（与 SelectionSession.test.ets 文件头记录的环境限制
//   一致）。
