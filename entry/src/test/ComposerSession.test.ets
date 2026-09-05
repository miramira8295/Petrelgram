import { describe, expect, it } from '@ohos/hypium';
import { ComposerSession, ComposerSessionHost } from '../main/ets/pages/chat/ComposerSession';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { MessageStore } from '../main/ets/store/MessageStore';
import { PendingMediaItem } from '../main/ets/util/pendingMedia';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { UserStore } from '../main/ets/store/UserStore';
import {
  COMPOSER_EDIT, COMPOSER_IDLE, COMPOSER_REPLY, ComposerMode,
  enterEdit, enterReply, idleComposer
} from '../main/ets/util/composerMode';

// 输入框上方那一条的状态机控制器，B9 把它从 ChatPage 整体搬进
// pages/chat/ComposerSession.ets 之后补的第一组断言。写法照抄
// SearchSession.test.ets / HeaderIdentitySession.test.ets（FakeHost、
// untilXxx 吞异常的包装函数、文件头先说环境限制）。
//
// 【两条环境限制，读用例前先看】
//
// 1. startEdit 命中"有待发媒体"分支时会调 `promptAction.showToast(...)`——
//    这是从 '@kit.ArkUI' 直接 import 的命名空间函数，不经 host 中转。本地
//    单测环境下这条 API 是否真的可调用未经验证（不像 ContextMenu.close()
//    那样已经在 SelectionSession.test.ets 里被别的用例直接调用过、证明过
//    安全），下面涉及它的用例一律用 untilUnavailableGlobal() 包一层——被
//    断言的是"进入这个分支之前/之中"那几次 host 取值器调用次数，这些调用
//    严格发生在 showToast() 之前，因此断言的可靠性不受它是否抛错影响。
//
// 2. startReply 末尾排的 focusTimer（0ms setTimeout）回调体只做两件事：
//    `this.focusTimer = -1`（私有字段，测试读不到）和
//    `focusControl.requestFocus('chat_composer')`（ambient 全局，调用后没有
//    可观察的返回值或副作用挂在 host/controller 的公开状态上）。这与
//    HeaderIdentitySession 的 navigationTimer 不同——那边的回调体里还多写了
//    一个公开的 @Trace 字段 `profileOpening`，可以拿来当哨兵（对照它的
//    dispose 用例）。本控制器这颗定时器没有这样的哨兵，"dispose() 之后回调
//    真的没有执行"这件事在本地测不到，属于纪律第 5 条说的"本地测不到的东西"，
//    不凑数写一条断言不到任何东西的用例。下面的 startReply 用例只钉住它在
//    dispose() 之前那段完全同步、真实可观察的效果（9 个字段经 enterReply
//    摊开 + 3 个跨簇 host 回调各触发一次），并确认 dispose() 在定时器还挂着
//    时调用不会抛错——这是本地环境下能做到的最接近的验证，残余风险照实
//    写在这里，不假装它不存在。

class FakeHost implements ComposerSessionHost {
  headerTitleValue: string = '';
  storeValue: MessageStore | null = null;
  storeCalls: number = 0;
  findMsgResult: MessageEntry | null = null;
  findMsgCalls: number[] = [];
  pendingMediaValue: PendingMediaItem[] = [];
  pendingMediaCalls: number = 0;
  draftValue: string = '';
  setDraftCalls: string[] = [];
  closeReactionSheetCount: number = 0;
  setEmojiPanelCalls: boolean[] = [];
  closeReplyKeyboardSlotCount: number = 0;

  headerTitle: () => string = (): string => this.headerTitleValue;
  store: () => MessageStore | null = (): MessageStore | null => {
    this.storeCalls++;
    return this.storeValue;
  };
  findMsg: (messageId: number) => MessageEntry | null = (messageId: number): MessageEntry | null => {
    this.findMsgCalls.push(messageId);
    return this.findMsgResult;
  };
  pendingMedia: () => PendingMediaItem[] = (): PendingMediaItem[] => {
    this.pendingMediaCalls++;
    return this.pendingMediaValue;
  };
  draft: () => string = (): string => this.draftValue;
  setDraft: (value: string) => void = (value: string): void => {
    this.draftValue = value;
    this.setDraftCalls.push(value);
  };
  closeReactionSheet: () => void = (): void => { this.closeReactionSheetCount++; };
  setEmojiPanel: (show: boolean) => void = (show: boolean): void => { this.setEmojiPanelCalls.push(show); };
  closeReplyKeyboardSlot: () => void = (): void => { this.closeReplyKeyboardSlotCount++; };
}

function controllerOn(host: FakeHost): ComposerSession {
  const controller: ComposerSession = new ComposerSession();
  controller.bind(host);
  return controller;
}

// 见文件头限制 1：promptAction（未经证实在本地是否安全可调用的 ArkUI 命名空间
// 函数）可能同步抛错——这里把"环境缺失导致的抛错"和"被测逻辑本身的错误"
// 分开，只吞前者。
function untilUnavailableGlobal(action: () => void): void {
  try {
    action();
  } catch (e) {
    // promptAction.showToast 在本地环境下是否可用未经验证，吞掉。
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(_json: string): void {}
}

// startReply 用例专用：喂一个真实用户名进 UserStore，让 buildMessageEntry
// 算出的 senderName 非空——对照 startReply 的"senderName 非空时不回退到
// headerTitle()"分支。形状照抄 SelectionSession.test.ets 的 usersOf()。
function userStoreWithSender(userId: number, name: string): UserStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  const users: UserStore = new UserStore(client);
  client.start();
  const user: TdObject = { '@type': 'user' };
  user['id'] = userId;
  user['first_name'] = name;
  const update: TdObject = { '@type': 'updateUser' };
  update['user'] = user;
  bridge.onReceive(JSON.stringify(update));
  return users;
}

// 一个完全没喂过任何 updateUser 的 UserStore——displayName() 对未知 id 原样
// 回落到 ''（UserStore.displayName: `this.names.get(userId) ?? ''`），用来
// 让 senderName 稳定为空，对照 startReply 回退到 host.headerTitle() 那一支。
function emptyUserStore(): UserStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  const users: UserStore = new UserStore(client);
  client.start();
  return users;
}

// 一条普通文本消息，喂给真实的 buildMessageEntry()——不手搭 MessageEntry
// 字面量（130+ 个字段，手写必然漏一堆，也容易和真实格式化逻辑对不上）。
// 形状照抄 SelectionSession.test.ets 的 baseEntry()。
function textMessageEntry(
  id: number, senderId: number, text: string, users: UserStore
): MessageEntry {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = text;
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = senderId;
  const message: TdObject = { '@type': 'message' };
  message['id'] = id;
  message['is_outgoing'] = false;
  message['sender_id'] = sender;
  message['date'] = 1000;
  message['content'] = content;
  return buildMessageEntry(message, users);
}

export default function composerSessionTest() {
  describe('ComposerSession', () => {

    // 防的回归：apply() 里漏改 9 个字段中的任意一个——它是这些字段的唯一
    // 写入口，源码注释原文写过"不要再单独改那七个字段"（B9 更正为实际 9
    // 个），漏掉一行就是某个字段停在默认值，回复条与其中一部分显示对不上。
    // 这里不摆一个自己拼的 ComposerMode，而是用 util/composerMode 里真实的
    // enterReply() 独立算出期望值，逐字段比对 apply() 摊开的结果。
    it('apply(enterReply(...)) 一次写满 9 个字段，与 util/composerMode 独立算出的派生完全一致', 0,
      (): void => {
        const controller: ComposerSession = controllerOn(new FakeHost());
        const next: ComposerMode = enterReply(
          idleComposer(), 501, '张三', '之前一条消息', 'file:///thumb.jpg', true);

        controller.apply(next);

        expect(controller.mode.kind).assertEqual(next.kind);
        expect(controller.replyToId).assertEqual(next.replyToId);
        expect(controller.replyToName).assertEqual(next.replyName);
        expect(controller.replyToText).assertEqual(next.replyText);
        expect(controller.replyToThumb).assertEqual(next.replyThumb);
        expect(controller.replyToThumbSticker).assertEqual(next.replyThumbSticker);
        expect(controller.editingId).assertEqual(next.editingId);
        expect(controller.editingKind).assertEqual(next.editingKind);
        expect(controller.editingPreview).assertEqual(next.editingPreview);
        // 阳性对照：确实是"回复"形状，不是默认值凑巧对上了。
        expect(controller.mode.kind).assertEqual(COMPOSER_REPLY);
        expect(controller.replyToThumbSticker).assertTrue();
        controller.dispose();
      });

    // 防的回归：startEdit 的"有待发媒体时拒绝"这道防线被删掉或被短路。
    // 编辑改的是旧消息，发媒体是发新消息，发送键做哪件事说不清，宁可拒绝也
    // 不静默丢掉用户刚选好的图（见源码注释）。这里不构造真实 MessageStore
    // 去验证"如果没有这道防线会不会真的进入编辑态"（那需要一整套
    // TdClient/UserStore/MessageStore 才能让 msg 查找命中，跑题），而是用
    // host 取值器的调用次数三角定位：拒绝分支应该摸过 pendingMedia()
    // 恰好一次、完全不该碰 store()——这条判据不受"如果误删了拒绝分支，
    // 后续查找又因为 store 是 null 而照样早退"这种巧合影响：只要
    // pendingMedia() 没被摸到过，或者 store() 被摸到过，就说明拒绝分支没有
    // 在该生效的地方生效。
    it('startEdit 在有待发媒体时拒绝：只摸一次 host.pendingMedia()，完全不碰 host.store()', 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        host.pendingMediaValue = [{ path: '/tmp/a.jpg', isVideo: false }];
        const controller: ComposerSession = controllerOn(host);

        untilUnavailableGlobal((): void => { controller.startEdit(77); });

        expect(host.pendingMediaCalls).assertEqual(1);
        expect(host.storeCalls).assertEqual(0);
        expect(controller.mode.kind).assertEqual(COMPOSER_IDLE);
        expect(controller.editingId).assertEqual(0);
        controller.dispose();
      });

    // 防的回归：cancelEdit 忘记把 draftBeforeEdit 还给 host.setDraft，或者
    // 忘记把 mode 摆回 idle。restored 是"取消编辑时要还回去的草稿"，这条链路
    // 一旦断掉，用户取消编辑后输入框里的文字会是被编辑消息的原文，而不是
    // 他进编辑前正在打的那句话。
    it('cancelEdit 把 draftBeforeEdit 经 host.setDraft 还回去，并回到 idle', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: ComposerSession = controllerOn(host);
      controller.apply(enterEdit(idleComposer(), 12, 'text', '原文预览', '编辑前的草稿'));

      controller.cancelEdit();

      expect(host.setDraftCalls.length).assertEqual(1);
      expect(host.setDraftCalls[0]).assertEqual('编辑前的草稿');
      expect(controller.mode.kind).assertEqual(COMPOSER_IDLE);
      expect(controller.editingId).assertEqual(0);
      controller.dispose();
    });

    // 对照：不在编辑态时 cancelEdit 是空操作（editingId===0 那道早退），不该
    // 平白调用 host.setDraft 把输入框内容覆盖掉。
    it('cancelEdit 在不是编辑态时什么都不做，不调用 host.setDraft', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: ComposerSession = controllerOn(host);
      controller.apply(enterReply(idleComposer(), 9, '小明', '在吗'));

      controller.cancelEdit();

      expect(host.setDraftCalls.length).assertEqual(0);
      expect(controller.mode.kind).assertEqual(COMPOSER_REPLY);
      controller.dispose();
    });

    // 防的回归：draftToPersist 的二选一判据被改错（比如条件取反，或者两个
    // 分支的返回值被换了位置）。persistDraftAndViewport 靠它决定退出页面时
    // 该往草稿箱存哪一份——编辑中存的应该是编辑前暂存的那份，不是输入框此刻
    // 显示的被编辑消息原文；不在编辑中就该存输入框此刻真正的草稿。两个
    // 分支都要覆盖，只测一半会漏掉分支被换位置这种回归。
    it('draftToPersist 编辑中返回 draftBeforeEdit，否则原样返回当前草稿', 0, (): void => {
      const controller: ComposerSession = controllerOn(new FakeHost());
      controller.apply(enterEdit(idleComposer(), 5, 'text', '预览', '编辑前的草稿'));
      expect(controller.draftToPersist('输入框此刻的文字')).assertEqual('编辑前的草稿');

      controller.apply(idleComposer());
      expect(controller.draftToPersist('输入框此刻的文字')).assertEqual('输入框此刻的文字');
      controller.dispose();
    });

    // 防的回归：reset() 被"优化"成只调 clearReply()。resetComposerSession
    // 的落点必须整体复位成 idleComposer()——clearReply() 只处理回复态，编辑态
    // 下是空操作（ComposerMode.test.ets 已经钉过这条纯函数层面的行为：
    // "clearReply 清不掉编辑态"）。如果 reset() 误用了 clearReply()，换会话时
    // 编辑态会跨会话残留：mode 还是 'edit'，editingId 还指着上一个会话的
    // 消息，下一次提交就编辑到别的会话去了。
    it('reset() 用 idleComposer 整体复位，不是只 clearReply——编辑态也要清干净', 0, (): void => {
      const controller: ComposerSession = controllerOn(new FakeHost());
      controller.apply(enterEdit(idleComposer(), 20, 'caption', '预览文字', '编辑前的草稿'));

      controller.reset();

      expect(controller.mode.kind).assertEqual(COMPOSER_IDLE);
      expect(controller.editingId).assertEqual(0);
      expect(controller.editingPreview).assertEqual('');
      // draftBeforeEdit 确实被清空的外部证据：idle 态下 draftToPersist 必须
      // 原样吐出调用方传入的当前草稿，而不是掺进被清空前记下的那份编辑前
      // 草稿——如果 reset() 漏清了 draftBeforeEdit，这一条不会失败（因为
      // draftToPersist 在 editingId===0 时压根不看 draftBeforeEdit），所以
      // 它只用来印证"确实回到了 idle 语义"，不单独当 draftBeforeEdit 的
      // 回归探测器（那需要读私有字段，测不到）。
      expect(controller.draftToPersist('当前正在打的字')).assertEqual('当前正在打的字');
      controller.dispose();
    });

    // startReply 的同步契约：9 个字段经 enterReply 摊开，且三个跨簇 host
    // 回调（closeReactionSheet/setEmojiPanel(false)/closeReplyKeyboardSlot）
    // 各触发一次；senderName 非空时不回退到 host.headerTitle()。随后验证
    // dispose() 在 focusTimer 还挂着时调用不会抛错——见文件头限制 2，
    // "回调是否真的被 dispose 拦下了"这件事本身在本地测不到。
    it('startReply 摊开 9 个字段并触发 3 个跨簇 host 回调；dispose() 在焦点定时器挂起时可以安全调用', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        const users: UserStore = userStoreWithSender(7, '李四');
        host.findMsgResult = textMessageEntry(301, 7, '在吗', users);
        const controller: ComposerSession = controllerOn(host);

        controller.startReply(301);

        expect(controller.mode.kind).assertEqual(COMPOSER_REPLY);
        expect(controller.replyToId).assertEqual(301);
        expect(controller.replyToName).assertEqual('李四'); // senderName 非空，没回退到 headerTitle()
        expect(controller.replyToText).assertEqual('在吗');
        expect(controller.editingId).assertEqual(0); // enterReply 顺带清掉编辑态
        expect(host.closeReactionSheetCount).assertEqual(1);
        expect(host.setEmojiPanelCalls.length).assertEqual(1);
        expect(host.setEmojiPanelCalls[0]).assertFalse();
        expect(host.closeReplyKeyboardSlotCount).assertEqual(1);

        // 阳性对照：senderName 为空时确实会回退到 host.headerTitle()。
        const host2: FakeHost = new FakeHost();
        host2.headerTitleValue = '会话标题';
        host2.findMsgResult = textMessageEntry(302, 999, '嗨', emptyUserStore());
        const controller2: ComposerSession = controllerOn(host2);
        controller2.startReply(302);
        expect(controller2.replyToName).assertEqual('会话标题');
        controller2.dispose();

        // dispose 前这颗 0ms 定时器已经排下；这里只验证 dispose() 本身不
        // 因为定时器还挂着而抛错，不对回调是否被拦下做进一步断言（见文件头
        // 限制 2）。
        controller.dispose();
        await sleep(30);
      });

    // 防的回归：有人把控制器做成模块级单例，或者 dispose 波及了别的实例。
    // 平板分栏、导航栈多层时同时活着多个 ChatPage，各自的回复/编辑态互不
    // 相干——文件头「为什么是 per-ChatPage 实例」那段写的就是这条。
    it('两个实例互不影响（防的回归：做成模块级单例，分栏两页共用一份输入区状态）', 0,
      (): void => {
        const a: ComposerSession = controllerOn(new FakeHost());
        const b: ComposerSession = controllerOn(new FakeHost());

        a.apply(enterReply(idleComposer(), 1, '会话 A 的回复对象', '摘要 A'));

        expect(b.mode.kind).assertEqual(COMPOSER_IDLE);
        expect(b.replyToId).assertEqual(0);

        // 一页销毁不能把另一页的状态一起清掉。
        b.apply(enterEdit(idleComposer(), 2, 'text', '预览 B', '草稿 B'));
        a.dispose();
        expect(b.mode.kind).assertEqual(COMPOSER_EDIT);
        expect(b.editingId).assertEqual(2);
        expect(a.mode.kind).assertEqual(COMPOSER_REPLY); // dispose 不清 mode，顺带确认没被误清
        b.dispose();
      });
  });
}
