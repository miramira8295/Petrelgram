import { describe, expect, it } from '@ohos/hypium';
import {
  TranslationDriver, TranslationDriverHost
} from '../main/ets/pages/chat/TranslationDriver';
import { MessageStore } from '../main/ets/store/MessageStore';
import { AlbumGroup } from '../main/ets/util/collapseAlbums';
import {
  setTranslateOptedIn, setTranslateOptedOut, translateOptedIn, translateOptedOut
} from '../main/ets/store/AppSettings';

// 会话翻译（总开关/排除名单/加入名单三态判定 + 会话级开关切换）的状态机，B10
// 把它从 ChatPage 整体搬进 pages/chat/TranslationDriver.ets 之后补的第一组断言。
// 写法照抄 HeaderIdentitySession.test.ets / SearchSession.test.ets（FakeHost、
// untilXxx 吞异常的包装函数、文件头先说环境限制）。
//
// 【三条环境限制，读用例前先看】
//
// 1. 本地测试跑不起 TDLib：Globals 里的 client 从没初始化过，getTdClient()
//    返回的其实是 undefined（`return client!;` 只是类型断言，运行时该是什么
//    还是什么），toggleTranslatable() 总开关关闭那一支末尾的
//    `getTdClient().send(req)` 会在这一行同步抛出 TypeError。这支必然走到那
//    一行（没有任何提前 return），下面涉及这一支的用例全部用
//    untilEnvSideEffect() 包一层——断言的是"发请求之前"那段同步字段写入/
//    host 记账，吞掉的是环境缺失而不是被测逻辑。这条和 SearchSession/
//    LiveTopCardController/HeaderIdentitySession 三个文件头的限制 1 同源。
//    发请求失败后的 `.catch(...)` 回滚分支（把 isTranslatable 改回
//    previous）因此也测不到：send() 同步抛出，Promise 链根本没建立起来，
//    `.catch` 永远不会被注册、更不会被调用。
//
// 2. promptAction.showToast 在本地这套 hypium 环境下会不会抛，没有先例可查——
//    仓库里另外三个已经落地的控制器测试文件都刻意绕开了会走到 showToast 的
//    调用路径，没有一次真的调用过它。为了不对着一个没验证过的环境行为写断言，
//    下面凡是会经过 afterToggled()（因而会经过 showToast）的用例，同样用
//    untilEnvSideEffect() 兜底：断言只钉在 showToast 之前必然已经执行完的那些
//    字段写入/落盘调用/host 记账，不对 showToast 本身有没有抛、抛的是什么做
//    任何假设。
//
// 3. AppStorage 是进程级单例，`setTranslateOptedOut`/`setTranslateOptedIn`
//    写的就是它（chatIdList/setChatIdInList 经 AppStorage.get/setOrCreate，
//    ScopeMuteStore.test.ets 已经证明这条路径本地可达、不抛）。下面每条会碰
//    这两个函数的用例都用一个当前文件内独占的 chatId，并在用例开头/结尾把
//    对应的 opt-out/opt-in 名单复位，避免同一进程里跑的其它用例、其它文件
//    互相串台。

// 宿主（ChatPage）那一小片接口的替身：5 个取值器读下面的 …Value 字段，
// setIsTranslatable 额外记一份调用历史，driveVisibleWork 只计数。控制器不许
// 缓存宿主的值，所以改 …Value 就等于"页面那边变了"。
class FakeHost implements TranslationDriverHost {
  chatIdValue: number = 0;
  storeValue: MessageStore | null = null;
  groupsValue: AlbumGroup[] = [];
  isTranslatableValue: boolean = false;
  setIsTranslatableCalls: boolean[] = [];
  driveVisibleWorkCount: number = 0;

  chatId: () => number = (): number => this.chatIdValue;
  store: () => MessageStore | null = (): MessageStore | null => this.storeValue;
  groups: () => AlbumGroup[] = (): AlbumGroup[] => this.groupsValue;
  isTranslatable: () => boolean = (): boolean => this.isTranslatableValue;
  setIsTranslatable: (value: boolean) => void = (value: boolean): void => {
    this.isTranslatableValue = value;
    this.setIsTranslatableCalls.push(value);
  };
  driveVisibleWork: () => void = (): void => { this.driveVisibleWorkCount++; };
}

function controllerOn(host: FakeHost): TranslationDriver {
  const controller: TranslationDriver = new TranslationDriver();
  controller.bind(host);
  return controller;
}

// 见文件头限制 1/2。本地环境下 getTdClient() 是未初始化的模块单例，
// .send(...) 那一行会同步抛错；promptAction.showToast 是否会抛没有先例可查。
// 两者都用这一个包装函数吞掉——断言的是抛错之前那段同步执行，不是抛错本身。
function untilEnvSideEffect(action: () => void): void {
  try {
    action();
  } catch (e) {
    // 见文件头限制 1/2，吞掉。
  }
}

export default function translationDriverTest() {
  describe('TranslationDriver', () => {

    // 防的回归：active() 里把 this.optOut / this.optIn 两个参数位置传反
    // （两个字段类型相同，编译器抓不出这种手滑）。四条用例里 optOut 和 optIn
    // 故意取不同的值，参数一旦传反，下面每一条的期望值都会跟着变。
    // 顺带钉住"总开关关→false"（用例 3）、"optOut 生效→false"（用例 2）、
    // "optIn 生效→true"（用例 4）这三个判据点。
    it('active() 三态真值表：总开关决定读排除名单还是加入名单', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: TranslationDriver = controllerOn(host);

      // 总开关开：读排除名单（optOut），加入名单（optIn）此刻应当被忽略。
      controller.optOut = false;
      controller.optIn = true;
      expect(controller.active(true)).assertTrue();

      controller.optOut = true;
      controller.optIn = false;
      expect(controller.active(true)).assertFalse();

      // 总开关关：读加入名单（optIn），排除名单（optOut）此刻应当被忽略。
      controller.optOut = true;
      controller.optIn = false;
      expect(controller.active(false)).assertFalse();

      controller.optOut = false;
      controller.optIn = true;
      expect(controller.active(false)).assertTrue();
      controller.dispose();
    });

    // 防的回归：把 host.isTranslatable() 悄悄接进判定公式——文件头注释明说
    // "服务端的 chat.is_translatable 故意不参与判定"（跟官方端各翻各的，
    // 总开关关掉才是"全局关闭"）。同一组 optOut/optIn 组合下，isTranslatable
    // 从 false 翻到 true，active() 的结果必须原地不动。
    it('active() 不参考 isTranslatable（服务端位故意不参与判定）', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: TranslationDriver = controllerOn(host);

      controller.optOut = false; // 总开关开，未排除 → active
      host.isTranslatableValue = false;
      expect(controller.active(true)).assertTrue();
      host.isTranslatableValue = true;
      expect(controller.active(true)).assertTrue();

      controller.optOut = false;
      controller.optIn = false; // 总开关关，未加入 → 不 active
      host.isTranslatableValue = false;
      expect(controller.active(false)).assertFalse();
      host.isTranslatableValue = true;
      expect(controller.active(false)).assertFalse();
      controller.dispose();
    });

    // 防的回归：onSettingChanged 把传入的 enabled 缓存成实例状态，而不是每次
    // 现用现传——连续两次传不同的值，行为必须跟着变，而不是钉死在第一次的值。
    it('onSettingChanged 不缓存 enabled：连续两次传不同值，分支跟着变', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: TranslationDriver = controllerOn(host);
      controller.optOut = true; // 总开关开时排除本会话
      controller.optIn = true;  // 总开关关时加入本会话

      // enabled=true：active(true) = !optOut = false → 走"收走译文"分支，
      // 不应调用 driveVisibleWork。
      controller.onSettingChanged(true);
      expect(host.driveVisibleWorkCount).assertEqual(0);

      // 紧接着 enabled=false：active(false) = optIn = true → 走"补翻可见范围"
      // 分支。如果 onSettingChanged 把第一次传入的 true 缓存下来当真值用，
      // 这里会仍然判成不 active，driveVisibleWorkCount 保持 0，用例判红。
      controller.onSettingChanged(false);
      expect(host.driveVisibleWorkCount).assertEqual(1);

      // 再传回 true：必须立刻跟着变回不 active 的那一支。
      controller.onSettingChanged(true);
      expect(host.driveVisibleWorkCount).assertEqual(1);
      controller.dispose();
    });

    // 防的回归：load() 把 optOut/optIn 从本地存储回填时把两个字段读反——两个
    // 存储位都是"chatId 在不在某张名单里"的同一种查法，类型上分不出误传，
    // 用不同真值才能把这类手滑照出来。
    it('load() 从本地存储回填 optOut/optIn，不读反', 0, (): void => {
      const chatId: number = 910001;
      setTranslateOptedOut(chatId, false);
      setTranslateOptedIn(chatId, false);
      setTranslateOptedOut(chatId, true);
      setTranslateOptedIn(chatId, false);

      const controller: TranslationDriver = controllerOn(new FakeHost());
      controller.load(chatId);
      expect(controller.optOut).assertTrue();
      expect(controller.optIn).assertFalse();

      setTranslateOptedOut(chatId, false);
      setTranslateOptedIn(chatId, false);
      controller.dispose();
    });

    // 防的回归：toggleTranslatable 在总开关开着时（写排除名单那一支）漏掉
    // setTranslateOptedOut 落盘，或者算错该写的布尔值——用户关掉这个会话的
    // 翻译，下次进来又是默认状态。这一支没有 TDLib 调用（见 TranslateToggle.
    // writesOptOut 分支，末尾直接 return），afterToggled 是否会经过
    // promptAction.showToast 不确定（见文件头限制 2），仍然包一层兜底。
    it('toggleTranslatable：总开关开着时翻转/落盘本地排除名单', 0, (): void => {
      const chatId: number = 910002;
      setTranslateOptedOut(chatId, false);
      setTranslateOptedIn(chatId, false);
      const host: FakeHost = new FakeHost();
      host.chatIdValue = chatId;
      const controller: TranslationDriver = controllerOn(host);
      controller.optOut = false; // 当前：总开关开、未排除 → 正在翻译

      untilEnvSideEffect((): void => { controller.toggleTranslatable(true); });

      // 正在翻译 → 关掉：写入排除名单为 true，不应补翻可见范围。
      expect(controller.optOut).assertTrue();
      expect(translateOptedOut(chatId)).assertTrue();
      expect(host.driveVisibleWorkCount).assertEqual(0);
      // 这一支不碰服务端位，setIsTranslatable 不应被调用。
      expect(host.setIsTranslatableCalls.length).assertEqual(0);

      untilEnvSideEffect((): void => { controller.toggleTranslatable(true); });

      // 再点一次：翻回"正在翻译"，排除名单落盘为 false，且要补翻可见范围。
      expect(controller.optOut).assertFalse();
      expect(translateOptedOut(chatId)).assertFalse();
      expect(host.driveVisibleWorkCount).assertEqual(1);

      setTranslateOptedOut(chatId, false);
      controller.dispose();
    });

    // 防的回归：toggleTranslatable 在总开关关着时（写加入名单+服务端位那一支）
    // 漏掉 setTranslateOptedIn 本地落盘，或者忘了先把新值经 host.
    // setIsTranslatable 写回页面字段——服务端请求本身在本地环境必然同步抛错
    // （见文件头限制 1），落到 send() 之前的那一段才是这条用例真正钉住的东西。
    it('toggleTranslatable：总开关关着时翻转本地加入名单 + 服务端位（发请求前那段）', 0, (): void => {
      const chatId: number = 910003;
      setTranslateOptedOut(chatId, false);
      setTranslateOptedIn(chatId, false);
      const host: FakeHost = new FakeHost();
      host.chatIdValue = chatId;
      host.isTranslatableValue = false;
      const controller: TranslationDriver = controllerOn(host);
      controller.optIn = false; // 当前：总开关关、未加入 → 没在翻译

      untilEnvSideEffect((): void => { controller.toggleTranslatable(false); });

      // 没在翻译 → 打开：本地加入名单落盘为 true，服务端位经 host 写成 true，
      // 且要补翻可见范围。
      expect(controller.optIn).assertTrue();
      expect(translateOptedIn(chatId)).assertTrue();
      expect(host.setIsTranslatableCalls.length).assertEqual(1);
      expect(host.setIsTranslatableCalls[0]).assertTrue();
      expect(host.driveVisibleWorkCount).assertEqual(1);

      setTranslateOptedIn(chatId, false);
      controller.dispose();
    });

    // 防的回归：把控制器做成模块级单例，或者 dispose 波及了别的实例。平板
    // 分栏、导航栈多层时同时活着多个 ChatPage，各自的会话级翻译开关不该串到
    // 一起。
    it('两个实例互不影响（防的回归：做成模块级单例，分栏两页共用一份翻译状态）', 0, (): void => {
      const a: TranslationDriver = controllerOn(new FakeHost());
      const b: TranslationDriver = controllerOn(new FakeHost());

      a.optOut = true;
      a.optIn = true;

      expect(b.optOut).assertFalse();
      expect(b.optIn).assertFalse();

      b.optOut = true;
      a.dispose();
      expect(b.optOut).assertTrue();
      expect(a.optOut).assertTrue();
      b.dispose();
    });
  });
}
