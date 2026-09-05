import { describe, expect, it } from '@ohos/hypium';
import { VoiceRecordingState, VoiceRecordingStateHost } from '../main/ets/pages/chat/VoiceRecordingState';
import { MessageStore } from '../main/ets/store/MessageStore';
import { UserStore } from '../main/ets/store/UserStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge } from '../main/ets/tdkit/TdTypes';
import { common } from '@kit.AbilityKit';
import { VoiceRecorder } from '../main/ets/services/VoiceRecorder';

// 麦克风录音状态机（B15 从 ChatPage 整体搬出）的第一组断言。写法照抄
// ChatOverlayState.test.ets / AttachActions.test.ets（FakeHost + callOrder
// 合并时间线、文件头先说环境限制）。
//
// 【核心环境限制，读用例前必看】
//
// start() 守卫放行之后紧接着的五件事（beforeStart/setComposerFocused/
// recordingStarting=true/recordingSeq++/`new VoiceRecorder()`）里，最后一步
// `rec.start(this.host.context())` 会摸真实系统能力
// `abilityAccessCtrl.createAtManager().requestPermissionsFromUser(...)`
// （services/VoiceRecorder.ets）——这是一枚会弹出真实系统权限对话框、结果
// 完全由用户交互决定的调用，与 AttachActions.test.ets 文件头点名的
// photoAccessHelper/picker 是同一类风险（"是否会真的拉起一个系统 UI，未经
// 验证"）。`VoiceRecordingStateHost` 没有为 `VoiceRecorder` 本身留注入缝
// （`new VoiceRecorder()` 是控制器内部硬编码的，不经过 host），所以无法像
// ChatOverlayState 的 toggleReaction 那样换一个真的可控的替身进去。
//
// 因此本文件只覆盖 start() 三道早退判据（判据放行之后的一切，包括方案本批
// 点名的"start→cancel→start，第一次的 Promise 迟到不改状态"这枚 recordingSeq
// 令牌钉子，都在 skippedAreas 里如实记录，并写清楚补哪个缝就能测）。
// finish()/cancel()/dispose()/secondsLabel() 不依赖 VoiceRecorder 是否真的
// 启动过——voiceRec 字段初值就是 null，finish()/cancel() 在 voiceRec 为空时
// 完全不碰 VoiceRecorder，可以安全验证它们对 isRecording/recordingStarting
// 这两个公开 @Trace 字段的复位效果。

// 宿主（ChatPage）那一小片接口的替身。callOrder 合并时间线做法照抄
// AttachActions.test.ets 的 FakeHost：本控制器的核心风险是"三个判据的 ||
// 短路顺序被打乱"（比如改成先无条件取 host.store() 再判断），单独给每个
// 取值器开计数器测不出短路，callOrder 才能钉住这件事。

// 假录音器。B15 验收时给 VoiceRecordingStateHost 补了 newRecorder 取值器，
// 才有了这个东西——方案点名的那枚钉子（start→cancel→start，第一段迟到的
// Promise 不改状态）全部活在 rec.start(...) 的 .then() 里，录音器原来是
// 类内 new 出来的，测试没有任何手段让那个 Promise 按自己的节奏兑现。
//
// 继承真 VoiceRecorder 而不是另起一个接口：宿主取值器的类型就是它，且这样
// 能保证假的和真的字段/方法签名不会悄悄漂移。start() 覆写成手动兑现，
// cancel()/stop() 只记账、绝不碰真实的 AVRecorder / 文件系统。
class FakeRecorder extends VoiceRecorder {
  cancelCalls: number = 0;
  stopCalls: number = 0;
  private settle: ((ok: boolean) => void) | null = null;

  start(_context: common.UIAbilityContext): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void): void => {
      this.settle = resolve;
    });
  }

  // 测试手动把这一段录音的 start() 兑现掉。
  resolveStart(ok: boolean): void {
    const settle = this.settle;
    this.settle = null;
    if (settle !== null) { settle(ok); }
  }

  // 真 VoiceRecorder 的 cancel()/stop() 都是 async，返回类型必须对齐，
  // 否则 ArkTS 报 "Property 'cancel' ... is not assignable to the same
  // property in base type 'VoiceRecorder'"。
  cancel(): Promise<void> {
    this.cancelCalls++;
    return Promise.resolve();
  }

  stop(): Promise<number> {
    this.stopCalls++;
    return Promise.resolve(0);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

class FakeHost implements VoiceRecordingStateHost {
  callOrder: string[] = [];
  storeValue: MessageStore | null = null;
  contextValue: common.UIAbilityContext = {} as common.UIAbilityContext;

  store: () => MessageStore | null = (): MessageStore | null => {
    this.callOrder.push('store');
    return this.storeValue;
  };
  context: () => common.UIAbilityContext = (): common.UIAbilityContext => {
    this.callOrder.push('context');
    return this.contextValue;
  };
  beforeStart: () => void = (): void => { this.callOrder.push('beforeStart'); };
  setComposerFocused: (value: boolean) => void = (value: boolean): void => {
    this.callOrder.push(`setComposerFocused:${value}`);
  };
  afterSent: () => void = (): void => { this.callOrder.push('afterSent'); };

  // 每次 start() 都从这里取一个新录音器；测试按顺序留着引用，用来分别
  // 兑现第一段和第二段的 start() Promise。
  handedOut: FakeRecorder[] = [];
  newRecorder: () => VoiceRecorder = (): VoiceRecorder => {
    this.callOrder.push('newRecorder');
    const rec: FakeRecorder = new FakeRecorder();
    this.handedOut.push(rec);
    return rec;
  };
}

function controllerOn(host: FakeHost): VoiceRecordingState {
  const controller: VoiceRecordingState = new VoiceRecordingState();
  controller.bind(host);
  return controller;
}

// 短路验证用例要喂一个"看起来像正常场景"的非空 store，形状照抄
// ChatOverlayState.test.ets / AttachActions.test.ets 的 newWiredStore：一套
// 真的能收发的 TdClient，不经过 tdkit/Globals 的模块级单例（本地是坏的）。
class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function newWiredStore(chatId: number): MessageStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  client.start();
  const users: UserStore = new UserStore(client);
  return new MessageStore(client, users, chatId);
}

export default function voiceRecordingStateTest() {
  describe('VoiceRecordingState', () => {

    // 防的回归：start() 的 `if (this.recordingStarting || ...) { return; }`
    // 这道早退判据被削弱或漏掉——录音"正在启动中"时再点一次麦克风按钮，
    // 不应该重新走 beforeStart()/新建 VoiceRecorder 那一整套。
    it('start(): recordingStarting 为 true 时直接返回，不碰任何 host 方法', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.storeValue = newWiredStore(1);
      const controller: VoiceRecordingState = controllerOn(host);
      controller.recordingStarting = true;

      controller.start();

      expect(host.callOrder).assertDeepEquals([]);
    });

    // 同上，isRecording 那一档。
    it('start(): isRecording 为 true 时直接返回，不碰任何 host 方法', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.storeValue = newWiredStore(1);
      const controller: VoiceRecordingState = controllerOn(host);
      controller.isRecording = true;

      controller.start();

      expect(host.callOrder).assertDeepEquals([]);
    });

    // 防的回归：store()===null 这道判据被删掉——路由切换途中 store 还没
    // 就绪时点麦克风，不应该继续往下建立录音。这一档判据本身要调一次
    // host.store()（前两档是短路，根本不会走到这里），下面单独验证这一点。
    it('start(): host.store() 为 null 时经过一次 store() 调用后返回，不继续往下', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.storeValue = null;
      const controller: VoiceRecordingState = controllerOn(host);

      controller.start();

      expect(host.callOrder).assertDeepEquals(['store']);
    });

    // 防的回归：三个判据的 `||` 短路顺序被打乱——比如改成先无条件
    // `const s = this.host.store();` 再判断 recordingStarting/isRecording。
    // recordingStarting/isRecording 为真时，host.store() 应该一次都不会被调
    // （短路），哪怕这次 store 是一个看起来完全正常的非空 store。
    it('start(): 三个判据用 || 短路——recordingStarting/isRecording 为真时 host.store() 完全不会被调', 0, (): void => {
      const hostA: FakeHost = new FakeHost();
      hostA.storeValue = newWiredStore(1);
      const a: VoiceRecordingState = controllerOn(hostA);
      a.recordingStarting = true;
      a.start();
      expect(hostA.callOrder.includes('store')).assertFalse();

      const hostB: FakeHost = new FakeHost();
      hostB.storeValue = newWiredStore(1);
      const b: VoiceRecordingState = controllerOn(hostB);
      b.isRecording = true;
      b.start();
      expect(hostB.callOrder.includes('store')).assertFalse();
    });

    // secondsLabel()：纯函数，覆盖零头补零、整分钟进位、超过一小时（分钟数
    // 继续累加，不进位成"小时:分:秒"三段式——原方法体只有两段，逐字保留）。
    it('secondsLabel(): 零头补零、整分钟进位、超过一小时仍是"分:秒"两段', 0, (): void => {
      const controller: VoiceRecordingState = controllerOn(new FakeHost());

      controller.recordSeconds = 0;
      expect(controller.secondsLabel()).assertEqual('0:00');

      controller.recordSeconds = 5;
      expect(controller.secondsLabel()).assertEqual('0:05');

      controller.recordSeconds = 65;
      expect(controller.secondsLabel()).assertEqual('1:05');

      controller.recordSeconds = 60;
      expect(controller.secondsLabel()).assertEqual('1:00');

      controller.recordSeconds = 3661; // 61 分 1 秒——不进位成"1:01:01"
      expect(controller.secondsLabel()).assertEqual('61:01');
    });

    // 防的回归：finish() 里复位 isRecording/recordingStarting 的那两行被删
    // 或被削弱。voiceRec 为空（从未真正开始过录音，比如守卫失败后误调
    // finish()）时，这两个显示态字段仍然必须被复位——先显式设成 true 再调用，
    // 不是"字段初值就是 false，从没设成 true 就断言它是 false"那种表演。
    it('finish(): voiceRec 为空时仍然把 isRecording/recordingStarting 复位为 false', 0, (): void => {
      const controller: VoiceRecordingState = controllerOn(new FakeHost());
      controller.isRecording = true;
      controller.recordingStarting = true;

      controller.finish();

      expect(controller.isRecording).assertFalse();
      expect(controller.recordingStarting).assertFalse();
    });

    // 同上，cancel() 那一份。
    it('cancel(): voiceRec 为空时同样把 isRecording/recordingStarting 复位为 false', 0, (): void => {
      const controller: VoiceRecordingState = controllerOn(new FakeHost());
      controller.isRecording = true;
      controller.recordingStarting = true;

      controller.cancel();

      expect(controller.isRecording).assertFalse();
      expect(controller.recordingStarting).assertFalse();
    });

    // 防的回归：dispose() 被"顺手"改成空函数体，或者改成不经过 cancel() 的
    // 另一套逻辑——方案裁决 dispose() 就是 cancel()，这条钉住这件事的外部
    // 可观察效果。
    it('dispose() 等价于 cancel()：把 isRecording/recordingStarting 复位为 false', 0, (): void => {
      const controller: VoiceRecordingState = controllerOn(new FakeHost());
      controller.isRecording = true;
      controller.recordingStarting = true;

      controller.dispose();

      expect(controller.isRecording).assertFalse();
      expect(controller.recordingStarting).assertFalse();
    });

    // ★ 本批方案点名要钉的那枚钉子：**cancel() 必须 ++recordingSeq**，
    // 否则"快速开始-取消-开始"会把第一段当有效发送。
    //
    // 这条在验收之前钉不住——录音器原来是 start() 里 `new VoiceRecorder()`
    // 硬编码的，而整条语义都活在 rec.start(...) 的 .then() 里，测试没有任何
    // 手段让那个 Promise 按自己的节奏兑现。验收时给宿主补了 newRecorder 取值器
    // （本类其余每一处跨簇依赖本来就都走宿主，唯独它漏了），才有了这条用例。
    //
    // 反事实：cancel() 里那句 ++recordingSeq 一删，第一段迟到的 ok=true 就会
    // 通过 `seq !== this.recordingSeq` 那道守卫，把 isRecording 翻成 true、
    // 并排下 1 秒一跳的计时器——用户明明已经上滑取消了，界面却又自己开始录。
    //
    // 【时序为什么是"取消之后**不再**开始"】
    // 直觉上会写成 start→cancel→start，但那个时序钉不住这枚钉子：第二次
    // start() 自己也 ++recordingSeq，第一段照样被作废，等于替 cancel() 顶了包，
    // 删掉 cancel() 里那句照样全绿（验收时先写成那样，真破了一次才发现）。
    // 只有"取消之后没有第二段"时，cancel() 的自增才是唯一挡住迟到回调的东西。
    it('start→cancel：第一段迟到的 Promise 不把界面翻回录音中（cancel 必须 ++recordingSeq）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.storeValue = newWiredStore(1);
        const controller: VoiceRecordingState = controllerOn(host);

        // 第一段：拿到录音器，但 start() 的 Promise 先挂着不兑现。
        controller.start();
        expect(host.handedOut.length).assertEqual(1);
        expect(controller.recordingStarting).assertTrue();

        // 用户上滑取消。cancel() 在这里 ++recordingSeq，把第一段作废。
        controller.cancel();
        expect(controller.recordingStarting).assertFalse();
        expect(controller.isRecording).assertFalse();
        expect(host.handedOut[0].cancelCalls).assertEqual(1); // 第一段的录音器被收了

        // 第一段的 start() 现在才兑现，而且是成功的——最危险的那一下。
        host.handedOut[0].resolveStart(true);
        await sleep(0);

        // 守卫在：迟到回调整个被丢掉，什么都没改。
        // 守卫没了：isRecording 翻成 true、recordSeconds 归零后开始一秒一跳。
        expect(controller.isRecording).assertFalse();
        expect(controller.recordingStarting).assertFalse();
        expect(controller.recordSeconds).assertEqual(0);
        // 迟到的那一段自己把自己的录音器又收了一次（.then 里 seq 不符那条分支）。
        expect(host.handedOut[0].cancelCalls).assertEqual(2);
      });

    // 与上一条配套：这条钉的是 start() 自己的 ++recordingSeq。快速连按两次，
    // 第一段迟到兑现时必须被第二段的自增作废掉——否则两段录音的回调会互相
    // 覆盖 isRecording/recordTimer，留下一个没人清的计时器。
    it('start→start：第一段迟到的 Promise 被第二段的 seq 作废', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.storeValue = newWiredStore(1);
        const controller: VoiceRecordingState = controllerOn(host);

        controller.start();
        expect(host.handedOut.length).assertEqual(1);
        // 第一段还在 starting，第二段进不来（start() 开头的守卫），所以先取消
        // 掉 starting 标志之外的路：这里直接让第一段失败落地，再开第二段。
        host.handedOut[0].resolveStart(false);
        await sleep(0);
        expect(controller.recordingStarting).assertFalse();

        controller.start();
        expect(host.handedOut.length).assertEqual(2);

        // 第二段成功落地。
        host.handedOut[1].resolveStart(true);
        await sleep(0);
        expect(controller.isRecording).assertTrue();

        controller.cancel(); // 收掉计时器
        expect(controller.isRecording).assertFalse();
      });

    // 阳性对照：证明上面那条挡住的不是"永远进不了录音态"——同一段自己的
    // start() 兑现回来时，确实会翻成录音中。没有这一条，把 start() 的 .then()
    // 整个删掉，上面那条照样绿。
    it('start() 自己的 Promise 兑现成功时进入录音态（阳性对照）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.storeValue = newWiredStore(1);
        const controller: VoiceRecordingState = controllerOn(host);

        controller.start();
        host.handedOut[0].resolveStart(true);
        await sleep(0);

        expect(controller.recordingStarting).assertFalse();
        expect(controller.isRecording).assertTrue();
        expect(controller.recordSeconds).assertEqual(0);

        controller.cancel(); // 收掉 1 秒一跳的计时器
        expect(controller.isRecording).assertFalse();
      });

    // 防的回归：把控制器做成模块级单例，或者字段被误改成 static——两个
    // ChatPage 实例（平板分栏、导航栈多层）各自的录音状态必须互不相干。
    it('两个实例互不影响（防的回归：做成模块级单例）', 0, (): void => {
      const a: VoiceRecordingState = controllerOn(new FakeHost());
      const b: VoiceRecordingState = controllerOn(new FakeHost());

      a.isRecording = true;
      expect(b.isRecording).assertFalse();

      b.recordSeconds = 42;
      expect(a.recordSeconds).assertEqual(0);
    });
  });
}
