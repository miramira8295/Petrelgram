import { describe, expect, it } from '@ohos/hypium';
import { attachActions, AttachAction, ATTACH_KEYS } from '../main/ets/util/attachActions';
import { common } from '@kit.AbilityKit';
import { promptAction, UIContext, PromptAction } from '@kit.ArkUI';
import { AttachActions, AttachActionsHost } from '../main/ets/pages/chat/AttachActions';
import { ChatOverlaySheetKind } from '../main/ets/pages/chat/ChatOverlayState';
import { PENDING_MEDIA_MAX } from '../main/ets/util/pendingMedia';
import { MessageStore, MediaSendItem } from '../main/ets/store/MessageStore';
import { MessageEntry } from '../main/ets/store/MessageEntry';
import { UserStore } from '../main/ets/store/UserStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';

// 附件面板是肌肉记忆：用户记的是"左上角是图库、右下角是骰子"，不是标签文字。
// 所以这份列表的**顺序**是要钉住的东西，比内容更重要。
//
// 唯一会变的是投票——Telegram 不允许私聊发投票。它排在倒数第二正是为此：
// 缺席时只有骰子一个格子挪位。
function keysOf(items: AttachAction[]): string[] {
  return items.map((a: AttachAction): string => a.key);
}

export default function attachActionsTest() {
  describe('attachActions', () => {
    it('keeps a fixed order in a private chat', 0, () => {
      expect(keysOf(attachActions(false, false)))
        .assertDeepEquals(['media', 'file', 'audio', 'videoNote', 'location', 'contact', 'dice']);
    });

    it('adds the poll only for groups and channels', 0, () => {
      const expected: string[] =
        ['media', 'file', 'audio', 'videoNote', 'location', 'contact', 'poll', 'dice'];
      expect(keysOf(attachActions(true, false))).assertDeepEquals(expected);
      expect(keysOf(attachActions(false, true))).assertDeepEquals(expected);
      expect(keysOf(attachActions(true, true))).assertDeepEquals(expected);
    });

    // 私聊相对群聊只少 poll 一项，其余相对次序完全不变——这就是"位置不漂移"
    // 的确切含义。
    it('changes nothing but the poll between chat kinds', 0, () => {
      const group: string[] = keysOf(attachActions(true, false));
      const priv: string[] = keysOf(attachActions(false, false));
      expect(group.filter((k: string): boolean => k !== 'poll')).assertDeepEquals(priv);
    });

    it('is stable across calls', 0, () => {
      expect(keysOf(attachActions(true, false))).assertDeepEquals(keysOf(attachActions(true, false)));
    });

    // 分发靠 key，重复就会有一个格子永远点不到。
    it('has unique keys', 0, () => {
      const keys: string[] = keysOf(attachActions(true, false));
      const seen: Set<string> = new Set<string>(keys);
      expect(seen.size).assertEqual(keys.length);
    });

    // ATTACH_KEYS 是 ChatPage 分发时的全集。列表里冒出一个它不认识的 key，
    // 就是一个点了没反应的格子。
    it('never produces a key outside the dispatch table', 0, () => {
      for (const kind of [[false, false], [true, false], [false, true]]) {
        for (const a of attachActions(kind[0], kind[1])) {
          expect(ATTACH_KEYS.includes(a.key)).assertTrue();
        }
      }
    });

    it('gives every entry an icon and a label', 0, () => {
      for (const a of attachActions(true, false)) {
        expect(a.icon.startsWith('sys.symbol.')).assertTrue();
        expect(a.tint.length > 0).assertTrue();
      }
    });
  });
}

// ============================================================================
// 下面这组是 pages/chat/AttachActions.ets（B12，附件面板分发表 + 媒体/文件/
// 音频/位置/骰子/联系人/投票/录像笔记/替换媒体 18 个方法的控制器）的测试。
// 之所以挤在同一个文件里、用第二个具名导出而不是新建一个文件：
// `AttachActions.test.ets` 这个文件名已经被上面这组测试占用（它测的是
// `util/attachActions.ets` 里那张纯数据的分发键位表，和这里要测的控制器类
// 是完全不同的两个东西，只是恰好同名）。新建同名文件会覆盖掉上面这组已经在
// 跑的测试，属于静默丢失覆盖率，比"不新建文件、挤在一起"更违反纪律。写法
// 照抄本仓已有的先例——List.test.ets 第 35 行 `import formatTimeTest,
// { formatClockCacheTest } from './formatTime.test';`，同一个文件默认导出
// + 具名导出并存，这不是本文件独创的变通。
//
// 【本组测试的环境限制——先读这段，再看下面的用例】
//
// AttachActions 18 个方法里，除了本组用例覆盖的部分，其余全部第一条有意义的
// 语句就会摸到 photoAccessHelper.PhotoViewPicker / picker.DocumentViewPicker /
// geoLocationManager / abilityAccessCtrl 这几个真实系统能力——这些通过
// `host.context()`（页面在 aboutToAppear 绑定时对 getContext(this) 求值一次
// 传入的真实 UIAbilityContext）或直接 import 使用，不像 host.uiContext()
// 那样是可以整体替身的取值器，无法从测试这一侧注入假的返回值/假的 Promise。
// 具体分两类：
//
// 1. **真的会弹出系统 UI、结果完全由用户交互决定**：
//    photoAccessHelper.PhotoViewPicker().select(...)（pickMedia/replaceMedia/
//    collectPickedMedia 间接用到）、picker.DocumentViewPicker(...).select(...)
//    （pickAndSendFile/pickAndSendAudio）。构造这些对象本身是否在无头单测
//    环境下会同步抛错、静默失败、还是真的尝试拉起一个系统选择器页面，未经
//    验证——万一是第三种，测试进程会一直等一个不会有人点的对话框，直到
//    hypium 15000ms 的用例上限帮它超时失败，这不是我们想要的信号来源。
//    因此下面的用例**只覆盖到"进入这些方法、guard 判据本身是否放行"这一步
//    为止**，绝不主动触发真正的 select() 调用链；`copyUriToCache`/
//    `collectPickedMedia`/`applyPickedMedia`（mediaCopySeq 的两处自增点）
//    全部挂在 select() 的 `.then` 回调里，本地永远等不到这个回调被调用，
//    所以"两次拿到的缓存文件名不相同"这条钉子本组测试**没有**——理由就是
//    本条，不写一条"包一层 try/catch、什么都断言不到"的凑数用例。
//    （原文这里写的是"见文件末尾 skippedAreas 的说明"，但文件末尾从来没有
//    那一段，是个空指针；验收时改成指向本条。）
//
// 2. **chooseLocationKind 例外**：它用的是 `this.host.uiContext()`（对应原
//    `this.getUIContext()`），这是 host 接口上的一个取值器，可以整体替身
//    ——所以本组测试能够完整验证 runAttachAction('location') 只经这一个
//    入口弹出"当前位置/15分钟/1小时/8小时"四选一菜单，不碰任何其它 host
//    调用。但菜单选完之后走向的 `sendCurrentLocation`/`startLiveLocation`
//    仍然会摸到 `host.context()` 之后的真实 geoLocationManager/
//    abilityAccessCtrl，属于第 1 类限制，本组测试同样不深入。
//
// `mediaPickerOpen` 闸门"第二次调用被挡住"这一条能测，是因为
// `this.mediaPickerOpen = true` 这一行赋值在源码里排在
// `new photoAccessHelper.PhotoViewPicker()` **之前**——不管后面那一行是否
// 安全，赋值本身已经同步生效，用一个 try/catch 吞掉后面可能的抛错、只断言
// 赋值生效前后 host 调用轨迹的变化，就能钉住"第二次调用被短路"这件事，
// 完全不依赖 select() 是否真的走得通。

// 宿主（ChatPage）那一小片接口的替身。与 ComposerSession.test.ets /
// ChatOverlayState.test.ets 的 FakeHost 不同的一点：这里额外维护一份
// `callOrder`——每个取值器/回调被调用时都往这里追加一条带关键参数的标签。
// 原因是本控制器的核心风险不是"哪个字段被错误改写"（大多数分支就是转发一次
// host 调用），而是"分发表把 key 路错、或者一个方法内部几行 host 调用的
// 先后顺序被打乱"（任务原话点名 B11 就在这上面出过唯一一次真问题）。单独
// 给每个字段开一个调用计数器测不出"顺序"，`callOrder` 这一份合并时间线可以
// 同时钉住"有没有跨簇串台"和"顺序有没有被打乱"两件事。
class FakeHost implements AttachActionsHost {
  callOrder: string[] = [];

  contextValue: common.UIAbilityContext = {} as common.UIAbilityContext;
  uiContextShowActionMenuLog: promptAction.ActionMenuOptions[] = [];
  chatIdValue: number = 0;
  storeValue: MessageStore | null = null;
  findMsgResult: MessageEntry | null = null;
  pendingMediaCountValue: number = 0;
  appendPendingMediaDropped: number = 0;
  composerSendingValue: boolean = false;
  draftTextValue: string = '';

  context: () => common.UIAbilityContext = (): common.UIAbilityContext => {
    this.callOrder.push('context');
    return this.contextValue;
  };
  // 对应原 this.getUIContext()。真实 UIContext 类是系统提供、没有公开构造
  // 函数的，这里和 AttachActions.ets 自己给"未 bind"占位值用的同一个手法
  // （`{...} as UIContext`）造一个只填了我们用得到的那一小截方法的替身。
  uiContext: () => UIContext = (): UIContext => {
    this.callOrder.push('uiContext');
    const log: promptAction.ActionMenuOptions[] = this.uiContextShowActionMenuLog;
    const fakePromptAction: PromptAction = {
      showActionMenu: (options: promptAction.ActionMenuOptions): Promise<promptAction.ActionMenuSuccessResponse> => {
        log.push(options);
        // 永远不 resolve/reject：调用方（chooseLocationKind）挂的
        // .then/.catch 因此永远不会被执行到，测试也不需要等它——我们只关心
        // showActionMenu 被以什么参数调用了这一件同步发生的事。
        return new Promise<promptAction.ActionMenuSuccessResponse>((): void => {});
      }
    } as PromptAction;
    return { getPromptAction: (): PromptAction => fakePromptAction } as UIContext;
  };
  chatId: () => number = (): number => {
    this.callOrder.push('chatId');
    return this.chatIdValue;
  };
  store: () => MessageStore | null = (): MessageStore | null => {
    this.callOrder.push('store');
    return this.storeValue;
  };
  findMsg: (messageId: number) => MessageEntry | null = (messageId: number): MessageEntry | null => {
    this.callOrder.push(`findMsg:${messageId}`);
    return this.findMsgResult;
  };
  pendingMediaCount: () => number = (): number => {
    this.callOrder.push('pendingMediaCount');
    return this.pendingMediaCountValue;
  };
  appendPendingMedia: (items: MediaSendItem[]) => number = (items: MediaSendItem[]): number => {
    this.callOrder.push(`appendPendingMedia:${items.length}`);
    return this.appendPendingMediaDropped;
  };
  composerSending: () => boolean = (): boolean => {
    this.callOrder.push('composerSending');
    return this.composerSendingValue;
  };
  draftText: () => string = (): string => {
    this.callOrder.push('draftText');
    return this.draftTextValue;
  };
  clearDraft: () => void = (): void => { this.callOrder.push('clearDraft'); };
  setAtBottom: (value: boolean) => void = (value: boolean): void => {
    this.callOrder.push(`setAtBottom:${value}`);
  };
  closeAttachPanel: () => void = (): void => { this.callOrder.push('closeAttachPanel'); };
  stopEditing: () => void = (): void => { this.callOrder.push('stopEditing'); };
  setComposerFocused: (value: boolean) => void = (value: boolean): void => {
    this.callOrder.push(`setComposerFocused:${value}`);
  };
  cancelRecording: () => void = (): void => { this.callOrder.push('cancelRecording'); };
  setSheet: (kind: ChatOverlaySheetKind, show: boolean) => void = (kind: ChatOverlaySheetKind, show: boolean): void => {
    this.callOrder.push(`setSheet:${kind}:${show}`);
  };
  setDiceSheetOpen: (open: boolean) => void = (open: boolean): void => {
    this.callOrder.push(`setDiceSheetOpen:${open}`);
  };
}

function controllerOn(host: FakeHost): AttachActions {
  const controller: AttachActions = new AttachActions();
  controller.bind(host);
  return controller;
}

// photoAccessHelper.PhotoViewPicker() 在本地单测环境下是否可以安全构造/调用
// 未经验证（文件头限制 1）。这里把"环境缺失导致的抛错"和"被测逻辑本身的
// 错误"分开，只吞前者——用法与 ComposerSession.test.ets /
// HeaderIdentitySession.test.ets 的 untilUnavailableGlobal 同一个模式。
function untilUnavailableSystemPicker(action: () => void): void {
  try {
    action();
  } catch (e) {
    // photoAccessHelper.PhotoViewPicker 在本地是否可用未经验证，吞掉。
  }
}

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

interface WiredStore {
  store: MessageStore;
  bridge: FakeBridge;
}

// 形状照抄 ChatOverlayState.test.ets / ComposerSession.test.ets 的
// newWiredStore：一套真的能收发的 TdClient，不经过 tdkit/Globals 的模块级
// 单例（本地是坏的），自己的 FakeBridge 自己接收、自己回。
function newWiredStore(chatId: number): WiredStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  client.start();
  const users: UserStore = new UserStore(client);
  const store: MessageStore = new MessageStore(client, users, chatId);
  return { store, bridge };
}

export function attachActionsControllerTest(): void {
  describe('AttachActions (controller)', () => {

    // 防的回归：if/else if 链里的分支被删掉、判据被写反，或者两个分支的
    // 方法体被写串了。未知 key 只应该收起面板，不落到任何一个分支里。
    it('runAttachAction：未知 key 只收起面板，不触发任何一个分支', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: AttachActions = controllerOn(host);

      controller.runAttachAction('not-a-real-key');

      expect(host.callOrder).assertDeepEquals(['closeAttachPanel']);
    });

    // 防的回归：'poll' 被路到了别的分支，或者顺带碰了 setDiceSheetOpen 等
    // 不相关的 host 方法。
    it("runAttachAction('poll')：只经 host.setSheet('poll', true)，不串台", 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: AttachActions = controllerOn(host);

      controller.runAttachAction('poll');

      expect(host.callOrder).assertDeepEquals(['closeAttachPanel', 'setSheet:poll:true']);
    });

    it("runAttachAction('contact')：只经 host.setSheet('contact', true)，不串台", 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: AttachActions = controllerOn(host);

      controller.runAttachAction('contact');

      expect(host.callOrder).assertDeepEquals(['closeAttachPanel', 'setSheet:contact:true']);
    });

    it("runAttachAction('dice')：只经 host.setDiceSheetOpen(true)，不串台", 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: AttachActions = controllerOn(host);

      controller.runAttachAction('dice');

      expect(host.callOrder).assertDeepEquals(['closeAttachPanel', 'setDiceSheetOpen:true']);
    });

    // 防的回归：openVideoNoteRecorder 漏掉"store 是否为空"这道前置判据，
    // store 为 null 时也照样往下调 cancelRecording/stopEditing/setSheet。
    it("runAttachAction('videoNote')：host.store() 为 null 时只检查了一次，不往下继续", 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.storeValue = null;
      const controller: AttachActions = controllerOn(host);

      controller.runAttachAction('videoNote');

      expect(host.callOrder).assertDeepEquals(['closeAttachPanel', 'store']);
    });

    // 防的回归：cancelRecording()/stopEditing()/setComposerFocused(false)/
    // setSheet('videoNote', true) 这四行的先后顺序被打乱，或者其中一行被漏掉
    // ——原方法这四行在源码里确实连续，测试按源码顺序逐行核对。
    it("runAttachAction('videoNote')：store 非空时依次 cancelRecording→stopEditing→setComposerFocused(false)→setSheet('videoNote',true)", 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        host.storeValue = newWiredStore(1).store;
        const controller: AttachActions = controllerOn(host);

        controller.runAttachAction('videoNote');

        expect(host.callOrder).assertDeepEquals([
          'closeAttachPanel', 'store', 'cancelRecording', 'stopEditing',
          'setComposerFocused:false', 'setSheet:videoNote:true'
        ]);
      });

    // 防的回归：chooseLocationKind 改用了别的入口（比如模块级静态
    // promptAction.showActionMenu），或者顺带碰了别的 host 方法。
    // 弹出的菜单选完之后会走向 sendCurrentLocation/startLiveLocation，那两个
    // 方法一进门就摸真实 geoLocationManager/abilityAccessCtrl（文件头限制
    // 1），本用例不深入，只钉住"入口只经 host.uiContext()，且确实弹的是
    // 四选一"这一同步可验证的部分。
    it("runAttachAction('location')：只经 host.uiContext() 弹出四选一菜单，不碰其余 host 方法", 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: AttachActions = controllerOn(host);

      controller.runAttachAction('location');

      expect(host.callOrder).assertDeepEquals(['closeAttachPanel', 'uiContext']);
      expect(host.uiContextShowActionMenuLog.length).assertEqual(1);
      expect(host.uiContextShowActionMenuLog[0].buttons.length).assertEqual(4);
    });

    // 防的回归：pickMedia 入口的三道判据（mediaPickerOpen/composerSending/
    // store===null）被削弱或顺序被改——用 composerSending=true 让 guard 在
    // 摸到真实 photoAccessHelper 之前就短路返回，这一条不需要
    // untilUnavailableSystemPicker 兜底，因为它从来没有机会往下走。
    it("runAttachAction('media')：composerSending 为真时在摸到系统选择器之前就短路返回", 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.composerSendingValue = true;
      const controller: AttachActions = controllerOn(host);

      controller.runAttachAction('media');

      expect(host.callOrder).assertDeepEquals(['closeAttachPanel', 'composerSending']);
    });

    // 防的回归（mediaPickerOpen 闸门）：`this.mediaPickerOpen = true` 这一行
    // 赋值排在 `new photoAccessHelper.PhotoViewPicker()` 之前，因此不管后面
    // 那一行在本地环境下是否安全，赋值本身已经同步生效。第二次调用应该在
    // `this.mediaPickerOpen || ...` 这个 `||` 链的第一项就短路，不应该再去
    // 调 host.composerSending()/host.store()/host.pendingMediaCount() 这三个
    // 取值器——用 callOrder 在两次调用之间新增的条目数量来钉住这件事。
    it("runAttachAction('media')：mediaPickerOpen 置位后，第二次调用被短路挡住，不再重新走 composerSending/store/pendingMediaCount 三道判据", 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        host.composerSendingValue = false;
        host.storeValue = newWiredStore(1).store;
        host.pendingMediaCountValue = 0;
        const controller: AttachActions = controllerOn(host);

        untilUnavailableSystemPicker((): void => { controller.runAttachAction('media'); });
        expect(host.callOrder).assertDeepEquals(
          ['closeAttachPanel', 'composerSending', 'store', 'pendingMediaCount']);

        untilUnavailableSystemPicker((): void => { controller.runAttachAction('media'); });
        expect(host.callOrder).assertDeepEquals([
          'closeAttachPanel', 'composerSending', 'store', 'pendingMediaCount', 'closeAttachPanel'
        ]);
      });

    // 防的回归：`this.mediaPickerOpen = true` 被挪到 `room <= 0` 检查**之前**。
    // 暂存区已满九张时这条分支要 return 且**不置位闸门**——置位了就再也没人
    // 复位（复位只挂在 select() 的两个回调上，而这条分支根本不会走到 select），
    // 用户删掉几张之后选择器永久打不开。
    //
    // 这条分支是本簇里少数完全同步、完全可测的：走到它之前只碰了
    // composerSending()/store()/pendingMediaCount() 三个替身取值器，之后只有
    // str() + promptAction.showToast()，一次都不摸 photoAccessHelper。
    // （showToast 在本地测试环境可用是有现成证据的：ChatOverlayState.test.ets
    // 里那条失败应答用例跑的正是 .catch 里的 showToast。）
    // 现有那两条 'media' 用例都盖不到它：一条走 composerSending 短路，
    // 另一条 pendingMediaCountValue 是 0。
    it("runAttachAction('media')：暂存区已满时早退且不置位 mediaPickerOpen（否则选择器会被永久锁死）", 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        host.composerSendingValue = false;
        host.storeValue = newWiredStore(1).store;
        host.pendingMediaCountValue = PENDING_MEDIA_MAX; // 满仓
        const controller: AttachActions = controllerOn(host);

        controller.runAttachAction('media');
        expect(host.callOrder).assertDeepEquals(
          ['closeAttachPanel', 'composerSending', 'store', 'pendingMediaCount']);

        // 关键的第二次：闸门若被误置位，这一次会在 `this.mediaPickerOpen ||`
        // 这一项就短路，后面三个取值器一个都不会再被调到。
        controller.runAttachAction('media');
        expect(host.callOrder).assertDeepEquals([
          'closeAttachPanel', 'composerSending', 'store', 'pendingMediaCount',
          'closeAttachPanel', 'composerSending', 'store', 'pendingMediaCount'
        ]);
      });

    // sendDiceEmoji 是本簇里唯二保持对外可见的方法之一（另一个是
    // replaceMedia），唯一调用点在页面 diceSheet @Builder 的 ForEach
    // onClick 里。防的回归：setDiceSheetOpen(false)/host.store()/
    // setAtBottom(true)/store.sendDice(emoji) 四步顺序被打乱或漏掉一步。
    it('sendDiceEmoji：store 非空时依次关闭骰子面板、写 atBottom、把骰子发给 store', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const wired: WiredStore = newWiredStore(7);
      host.storeValue = wired.store;
      const controller: AttachActions = controllerOn(host);

      controller.sendDiceEmoji('🎯');

      expect(host.callOrder).assertDeepEquals(['setDiceSheetOpen:false', 'store', 'setAtBottom:true']);
      expect(wired.bridge.sent.length).assertEqual(1); // store.sendDice 真的发出了一条 TDLib 请求
      const sent: TdObject = JSON.parse(wired.bridge.sent[0]) as TdObject;
      expect(sent['@type']).assertEqual('sendMessage');
      // 光断言"发出了一条 sendMessage"够不上用例名说的"把骰子发给 store"：
      // 把 store.sendDice(emoji) 写成硬编码 sendDice('🎲')、或者干脆漏传参数，
      // 上面三行照样全绿。入参特意用 🎯 而不是 🎲，就是为了不跟任何硬编码的
      // 默认值撞上。emoji 落在 input_message_content.emoji（MessageStore.sendDice）。
      const content: TdObject = sent['input_message_content'] as TdObject;
      expect(content['emoji']).assertEqual('🎯');
    });

    // 防的回归：`if (store !== null)` 这道守卫被削弱成无条件执行，store 为
    // null 时（路由切换途中）也照样调 setAtBottom/发送，对着一个不存在的
    // store 出错。
    it('sendDiceEmoji：store 为 null 时仍然关闭骰子面板，但不写 atBottom、不发送', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: AttachActions = controllerOn(host);

      controller.sendDiceEmoji('🎲');

      expect(host.callOrder).assertDeepEquals(['setDiceSheetOpen:false', 'store']);
    });

    // 防的回归：控制器被做成模块级单例，或者 `host` 字段被错误地共享
    // ——两个 ChatPage 实例（平板分栏、导航栈多层）各自的宿主必须互不干扰。
    // 用完全不摸系统 API 的三个动作（poll/contact/dice）串联验证：A 先动作，
    // 再绑定 B 并让 B 动作，最后回到 A 再动作一次——如果 `host` 是共享的
    // （比如被误改成 `static`），B 绑定之后 A 的后续动作会实际落到 B 的
    // FakeHost 上，下面最后两条 assertDeepEquals 会不匹配。
    it('两个实例互不影响（防的回归：host 字段被误改成模块级共享，而不是逐实例绑定）', 0, (): void => {
      const hostA: FakeHost = new FakeHost();
      const hostB: FakeHost = new FakeHost();
      const a: AttachActions = controllerOn(hostA);

      a.runAttachAction('poll');
      expect(hostA.callOrder).assertDeepEquals(['closeAttachPanel', 'setSheet:poll:true']);

      const b: AttachActions = controllerOn(hostB); // B 在 A 已经动作之后才绑定
      b.runAttachAction('contact');
      expect(hostB.callOrder).assertDeepEquals(['closeAttachPanel', 'setSheet:contact:true']);
      expect(hostA.callOrder).assertDeepEquals(['closeAttachPanel', 'setSheet:poll:true']); // A 没被 B 的绑定波及

      a.runAttachAction('dice'); // B 绑定之后，A 的动作应该继续落在 hostA 上
      expect(hostA.callOrder).assertDeepEquals([
        'closeAttachPanel', 'setSheet:poll:true', 'closeAttachPanel', 'setDiceSheetOpen:true'
      ]);
      expect(hostB.callOrder).assertDeepEquals(['closeAttachPanel', 'setSheet:contact:true']); // B 没被 A 的后续动作波及
    });
  });
}
