import { describe, expect, it } from '@ohos/hypium';
import {
  ChatOverlaySheetKind, ChatOverlayState, ChatOverlayStateHost
} from '../main/ets/pages/chat/ChatOverlayState';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { MessageStore } from '../main/ets/store/MessageStore';
import { UserStore } from '../main/ets/store/UserStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';

// 反应弹层/转发弹层/其余四个 sheet 开关/贴纸残影动画的控制器，B11 把它从
// ChatPage 整体搬进 pages/chat/ChatOverlayState.ets 之后补的第一组断言。
// 写法照抄 ComposerSession.test.ets / HeaderIdentitySession.test.ets
// （FakeHost、sleep 包装函数、文件头先说环境限制）。
//
// 【环境限制，读用例前先看——本文件独有的一条，比 ComposerSession/
// HeaderIdentitySession 两个前例都更彻底】
//
// ensureAllowedReactions() 的"在途请求去重"（allowedReactionsTask 命中时
// 直接把同一个 Promise 还给第二个调用方，不重复发请求）**在本地环境下完全
// 无法验证，一条用例都写不出来**——不是"写得到但覆盖不全"，是这个方法唯一
// 能建立起"已有在途任务"这个前置状态的路径，本身会在到达那一行赋值之前
// 就同步抛错：
//
//   const task: Promise<string[]> = getTdClient().send(req).then(...)...;
//   this.allowedReactionsTask = task;   // ← 去重要靠这一行留下的痕迹
//
// getTdClient() 读的是 tdkit/Globals 里的模块级单例，本地测试从没跑过
// initTdKit()，`client` 字段永远是 undefined；`getTdClient()` 把它原样
// `!` 断言吐出去（这个操作符在编译产物里不留任何运行时检查），换来的是
// `undefined.send(req)`——这一步已经同步抛出 TypeError，抛错发生在
// `const task = ...` 这一整条语句的求值过程里，`task` 从未被构造出来，
// `this.allowedReactionsTask = task` 这一行永远执行不到。也就是说：
//   - 第一次调用：allowedReactions.length===0 且 allowedReactionsTask===null，
//     两道短路都不命中，必然走到 getTdClient() 那一行，必然同步抛错。
//   - 第二次调用：因为第一次抛错发生在赋值之前，allowedReactionsTask 还是
//     null，allowedReactions 还是空数组——状态和"从没调用过"完全一样，
//     还是必然抛错。
// 换句话说，"已经有一个在途 Promise，第二次调用应该原样拿到它"这个要验证
// 的前置状态，在本地测试里永远搭建不起来——不存在任何调用序列能让
// allowedReactionsTask 变成非 null。这与 HeaderIdentitySession.test.ets
// 文件头限制 2 描述的"isSavedMessages()/refresh() 第一条语句就抛错、完全
// 没有写测试"是同一类环境限制，这里同样选择如实记录、不写一条"包一层
// try/catch、什么都断言不到"的凑数用例，也不会为了凑出断言点去访问
// allowedReactions/allowedReactionsTask 这两个私有字段（本类没有为它们开
// 任何读写口子，私有就是私有）。
//
// toggleReaction() 内部对同一份 allowedReactions/ensureAllowedReactions
// 的依赖，本文件全部改用 'ce:' 前缀的自定义 emoji key 绕开——自定义分支走
// `Promise.resolve(this.allowedReactions)`，完全不碰 getTdClient()，这才是
// 下面互斥锁那几条用例能在本地环境跑起来的原因，不是偶然挑的测试数据。
//
// showReactors() 同样每条分支都会摸到 getTdClient()/getUserStore()/
// getChatStore() 之一，本地必然同步抛错且没有"抛错之前"的可断言前缀（第一
// 条语句就在拼 req，第二条就是 getTdClient().send(...)），因此也不在下面的
// 用例名单里——不是任务要求的必测项，如实同理跳过。

// 宿主（ChatPage）那一小片接口的替身：5 个取值器/回调全部只记账，不做任何
// 真实业务逻辑，形状照抄 ComposerSession.test.ets 的 FakeHost。
class FakeHost implements ChatOverlayStateHost {
  storeValue: MessageStore | null = null;
  storeCalls: number = 0;
  chatIdValue: number = 0;
  chatIdCalls: number = 0;
  findMsgResult: MessageEntry | null = null;
  findMsgCalls: number[] = [];
  setEmojiPanelCalls: boolean[] = [];
  // effectDuration 的返回值队列：按调用顺序逐个吐出；队列空了就原样回传 ms
  // （和 ChatOverlayState 自带的"未 bind"空宿主默认行为一致）。
  effectDurationQueue: number[] = [];
  effectDurationCalls: string[] = [];

  store: () => MessageStore | null = (): MessageStore | null => {
    this.storeCalls++;
    return this.storeValue;
  };
  chatId: () => number = (): number => {
    this.chatIdCalls++;
    return this.chatIdValue;
  };
  findMsg: (messageId: number) => MessageEntry | null = (messageId: number): MessageEntry | null => {
    this.findMsgCalls.push(messageId);
    return this.findMsgResult;
  };
  setEmojiPanel: (show: boolean) => void = (show: boolean): void => {
    this.setEmojiPanelCalls.push(show);
  };
  effectDuration: (key: string, ms: number) => number = (key: string, ms: number): number => {
    this.effectDurationCalls.push(key);
    if (this.effectDurationQueue.length > 0) {
      return this.effectDurationQueue.shift() as number;
    }
    return ms;
  };
}

function controllerOn(host: FakeHost): ChatOverlayState {
  const controller: ChatOverlayState = new ChatOverlayState();
  controller.bind(host);
  return controller;
}

// 六个 sheet 开关的当下快照，顺序与 setSheet 用例里的 kinds 数组一一对应。
// 写在模块顶层而不是 it() 回调内部：本仓 2000+ 个 .ets 里没有一处在函数体内
// 做 function 声明，ArkTS 对这种写法的诊断在不同 SDK 档位上并不一致，不值得
// 让一条测试成为全仓孤例。
function flagsOf(c: ChatOverlayState): boolean[] {
  return [
    c.showReactionSheet, c.showForwardSheet, c.showScheduledSheet,
    c.showPollSheet, c.showContactSheet, c.showVideoNoteRecorder
  ];
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

// toggleReaction 互斥锁那几条用例专用：一套真的能收发的 TdClient，不经过
// tdkit/Globals 的模块级单例（那个在本地是坏的，见文件头），而是像
// TdClient.test.ets / ComposerSession.test.ets 那样直接 new 一个，自己的
// FakeBridge 自己接收、自己回。
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

function newWiredStore(chatId: number): WiredStore {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  client.start();
  const users: UserStore = new UserStore(client);
  const store: MessageStore = new MessageStore(client, users, chatId);
  return { store, bridge };
}

// 把 bridge.sent[index] 那一条请求原样应答成功（@type 非 'error' 就会走
// resolve 分支，见 TdClient.deliverParsed）——MessageStore.setReaction 的
// `.then((): void => {})` 不看应答内容，只要不是 error 就算成功。
function respondOk(bridge: FakeBridge, index: number): void {
  const sent: TdObject = JSON.parse(bridge.sent[index]) as TdObject;
  const resp: TdObject = { '@type': 'ok' };
  resp['@extra'] = sent['@extra'] as Object;
  bridge.onReceive(JSON.stringify(resp));
}

// respondOk 的失败版：TdClient.deliverParsed 看到 '@type':'error' 就把在途
// 请求 reject 成 TdError（TdClient.ets:160-161），于是 toggleReaction 的
// .catch 分支才跑得起来。两处 `=== key` 守卫里的第二处只在这条路径上，
// 不造出真实的失败应答就永远覆盖不到它。
function respondError(bridge: FakeBridge, index: number): void {
  const sent: TdObject = JSON.parse(bridge.sent[index]) as TdObject;
  const resp: TdObject = { '@type': 'error' };
  resp['@extra'] = sent['@extra'] as Object;
  resp['code'] = 400;
  resp['message'] = 'REACTION_INVALID';
  bridge.onReceive(JSON.stringify(resp));
}

// openReactionSheet/openForwardPicker 的 findMsg 命中场景要喂一个真实
// MessageEntry——不手搭 130+ 字段的字面量，用真实的 buildMessageEntry()
// 独立算出来，形状照抄 ComposerSession.test.ets 的 textMessageEntry()。
// 本文件不关心消息内容本身，只要"非 null"这一件事。
function anyMessageEntry(): MessageEntry {
  const bridge: FakeBridge = new FakeBridge();
  const client: TdClient = new TdClient(bridge);
  client.start();
  const users: UserStore = new UserStore(client);
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = 'hi';
  const content: TdObject = { '@type': 'messageText' };
  content['text'] = formatted;
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = 1;
  const message: TdObject = { '@type': 'message' };
  message['id'] = 1;
  message['is_outgoing'] = false;
  message['sender_id'] = sender;
  message['date'] = 1000;
  message['content'] = content;
  return buildMessageEntry(message, users);
}

export default function chatOverlayStateTest() {
  describe('ChatOverlayState', () => {

    // 防的回归：setSheet 的 switch 漏掉某个 case、或者两个 case 的分支体
    // 被写串了（比如 'poll' 分支手滑改成了写 showContactSheet）。六个开关
    // 逐个开、逐个关，每次都顺带确认其余五个纹丝不动——只测"打开自己"测不出
    // "顺带打开了别人"这种串台。
    it('setSheet 六个开关各自独立，互不串台', 0, (): void => {
      const controller: ChatOverlayState = controllerOn(new FakeHost());
      const kinds: ChatOverlaySheetKind[] =
        ['reaction', 'forward', 'scheduled', 'poll', 'contact', 'videoNote'];

      for (let i = 0; i < kinds.length; i++) {
        controller.setSheet(kinds[i], true);
        const flags: boolean[] = flagsOf(controller);
        for (let j = 0; j < flags.length; j++) {
          if (j === i) {
            expect(flags[j]).assertTrue();
          } else {
            expect(flags[j]).assertFalse();
          }
        }
        controller.setSheet(kinds[i], false);
        expect(flagsOf(controller)).assertDeepEquals([false, false, false, false, false, false]);
      }
    });

    // 防的回归：openReactionSheet 漏掉"消息还在不在"这道判据，变成无脑打开。
    // findMsg 未命中（比如消息已经被删除/还没同步到）时必须保持关闭；命中时
    // 才写 reactionTargetId 并打开。
    it('openReactionSheet 只在 host.findMsg 命中时才打开，未命中时保持关闭', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: ChatOverlayState = controllerOn(host);

      host.findMsgResult = null;
      controller.openReactionSheet(5);
      expect(controller.showReactionSheet).assertFalse();
      expect(controller.reactionTargetId).assertEqual(0);
      expect(host.findMsgCalls).assertDeepEquals([5]);

      host.findMsgResult = anyMessageEntry();
      controller.openReactionSheet(5);
      expect(controller.showReactionSheet).assertTrue();
      expect(controller.reactionTargetId).assertEqual(5);
    });

    // 防的回归：closeReactionSheet 只清了其中一个字段（比如漏清
    // reactionTargetId，弹层关了但下次快捷反应行还认得上一条消息的 id）。
    it('closeReactionSheet 把 showReactionSheet/reactionTargetId 两个字段一起清空', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.findMsgResult = anyMessageEntry();
      const controller: ChatOverlayState = controllerOn(host);
      controller.openReactionSheet(8);
      expect(controller.showReactionSheet).assertTrue();
      expect(controller.reactionTargetId).assertEqual(8);

      controller.closeReactionSheet();

      expect(controller.showReactionSheet).assertFalse();
      expect(controller.reactionTargetId).assertEqual(0);
    });

    // 防的回归：openForwardPicker 漏调 closeReactionSheet()/host.setEmojiPanel
    // (false) 这两行联动——原方法尾部这四行是逐字保留的，任何一行被漏掉都是
    // "顶替成看起来等价的近似值"这条铁律要防的那种 bug。
    it('openForwardPicker 写入 forwardMessageIds/showForwardSheet，并联动 closeReactionSheet()+host.setEmojiPanel(false)', 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        host.findMsgResult = anyMessageEntry();
        const controller: ChatOverlayState = controllerOn(host);
        controller.openReactionSheet(9); // 制造"联动 closeReactionSheet()"能被观察到的前置状态
        expect(controller.showReactionSheet).assertTrue();

        controller.openForwardPicker([11, 22]);

        expect(controller.forwardMessageIds).assertDeepEquals([11, 22]);
        expect(controller.showForwardSheet).assertTrue();
        expect(controller.showReactionSheet).assertFalse(); // closeReactionSheet() 联动生效
        expect(controller.reactionTargetId).assertEqual(0);
        expect(host.setEmojiPanelCalls).assertDeepEquals([false]);
      });

    // 防的回归：closeForwardSheet 只清了 showForwardSheet，忘了把
    // forwardMessageIds 也清空——转发列表消息 id 残留到下一次打开。
    it('closeForwardSheet 把 showForwardSheet/forwardMessageIds 两个字段一起清空', 0, (): void => {
      const controller: ChatOverlayState = controllerOn(new FakeHost());
      controller.openForwardPicker([1, 2, 3]);
      expect(controller.showForwardSheet).assertTrue();

      controller.closeForwardSheet();

      expect(controller.showForwardSheet).assertFalse();
      expect(controller.forwardMessageIds).assertDeepEquals([]);
    });

    // 防的回归：toggleReaction 的入口判据被削弱成"只挡同一条消息/同一个
    // key"，而不是"只要有任何一枚在途 key 就全部挡住"。第二次调用换了完全
    // 不同的 messageId/reactionKey，也必须被挡：锁不改、也不该再发一次
    // 请求（用 'ce:' 前缀绕开 ensureAllowedReactions/getTdClient，见文件头）。
    it('toggleReaction 互斥锁：第一次请求在途时，第二次调用被直接挡掉', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      const wired: WiredStore = newWiredStore(42);
      host.storeValue = wired.store;
      const controller: ChatOverlayState = controllerOn(host);

      controller.toggleReaction(1, 'ce:1', false);
      expect(controller.reactionPendingKey).assertEqual('1_ce:1');

      controller.toggleReaction(2, 'ce:2', false); // 应该被挡：锁非空
      expect(controller.reactionPendingKey).assertEqual('1_ce:1'); // 没被第二次调用顶替

      await sleep(0); // 放行第一次调用排的微任务，让它真正发出网络请求
      expect(wired.bridge.sent.length).assertEqual(1); // 只有第一次那一条，第二次压根没走到发请求
    });

    // 防的回归：**.then 里**那处 `if (this.reactionPendingKey === key)` 守卫被
    // 删掉、或者改成无条件清空。响应回来的时候锁可能已经被后来的调用（或者
    // resetSession()/dispose()）重新设置成了别的 key——这时候必须原样放着，
    // 不能把不是自己发的那把锁提前放行掉。
    // （.catch 里那处对称的守卫由下面走 respondError 的那一对用例覆盖——这条
    // 用例走的是成功应答，进不了 catch，钉不住那一处。）
    it('toggleReaction 成功应答回来时如果锁的 key 已经变了，不清空当前的锁（不是无条件清空）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        const wired: WiredStore = newWiredStore(42);
        host.storeValue = wired.store;
        const controller: ChatOverlayState = controllerOn(host);

        controller.toggleReaction(1, 'ce:1', false);
        expect(controller.reactionPendingKey).assertEqual('1_ce:1');
        await sleep(0);
        expect(wired.bridge.sent.length).assertEqual(1);

        // 模拟：响应回来之前，锁已经被别处重新设置成了另一枚 key。
        controller.reactionPendingKey = '999_ce:9';

        respondOk(wired.bridge, 0);
        await sleep(0);

        expect(controller.reactionPendingKey).assertEqual('999_ce:9'); // 没被过期回调清空
      });

    // 阳性对照：证明上面两条用例挡住的不是"锁永远打不开"——自己发的那把
    // key 响应回来时确实会被清空，清空之后新的一次调用能正常拿到锁。
    it('toggleReaction 正常完成后清空自己的锁（阳性对照：===key 比较确实认得出自己）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        const wired: WiredStore = newWiredStore(7);
        host.storeValue = wired.store;
        const controller: ChatOverlayState = controllerOn(host);

        controller.toggleReaction(3, 'ce:3', true);
        expect(controller.reactionPendingKey).assertEqual('3_ce:3');
        await sleep(0);
        expect(wired.bridge.sent.length).assertEqual(1);

        respondOk(wired.bridge, 0);
        await sleep(0);

        expect(controller.reactionPendingKey).assertEqual('');
        controller.toggleReaction(4, 'ce:4', false);
        expect(controller.reactionPendingKey).assertEqual('4_ce:4');
      });

    // 上面三条走的全是成功应答，只覆盖得到 .then 里那处 `=== key`；.catch 里
    // 那处（ChatOverlayState.toggleReaction 的失败分支）一次都没进去过。
    // 把它整段删掉，那三条依然全绿——所以补这一对失败路径的用例，否则用例名
    // 声称的"两处守卫"实际只钉住一处。
    //
    // 这一条是阳性对照：证明失败应答确实能把 .catch 跑起来、并且它认得出
    // 自己那把锁。没有这一条，下面那条"key 变了就不清"的断言在 .catch 根本
    // 没执行的情况下也会通过——那就成了表演。
    it('toggleReaction 失败应答也清空自己的锁（阳性对照：.catch 分支确实跑到了）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        const wired: WiredStore = newWiredStore(7);
        host.storeValue = wired.store;
        const controller: ChatOverlayState = controllerOn(host);

        controller.toggleReaction(5, 'ce:5', true);
        expect(controller.reactionPendingKey).assertEqual('5_ce:5');
        await sleep(0);
        expect(wired.bridge.sent.length).assertEqual(1);

        respondError(wired.bridge, 0);
        await sleep(0);

        // 失败也要放锁——否则一次网络错误就把这个会话的反应按钮永久锁死。
        expect(controller.reactionPendingKey).assertEqual('');
      });

    // 防的回归：**.catch 里**那处 `if (this.reactionPendingKey === key)` 被删掉
    // 或改成无条件清空。与成功路径那条对称：失败应答回来的时候，锁可能已经被
    // 后来的调用重新设置成了别的 key，这时候同样不能把不是自己发的那把锁放行。
    it('toggleReaction 失败应答回来时如果锁的 key 已经变了，不清空当前的锁', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        const wired: WiredStore = newWiredStore(42);
        host.storeValue = wired.store;
        const controller: ChatOverlayState = controllerOn(host);

        controller.toggleReaction(6, 'ce:6', false);
        expect(controller.reactionPendingKey).assertEqual('6_ce:6');
        await sleep(0);
        expect(wired.bridge.sent.length).assertEqual(1);

        // 模拟：失败应答回来之前，锁已经被别处重新设置成了另一枚 key。
        controller.reactionPendingKey = '999_ce:9';

        respondError(wired.bridge, 0);
        await sleep(0);

        expect(controller.reactionPendingKey).assertEqual('999_ce:9'); // 没被过期回调清空
      });

    // 防的回归：flyStickerGhost 的"连发保护"（stickerGhostTimer !== -1 就
    // clearTimeout）被删掉或被弱化。连续两次快速发贴纸，前一次的收尾定时器
    // 到期时不能把第二次还在飞的残影误清掉——用两个差距很大的 duration，在
    // "第一个定时器本该到期、第二个还早"的窗口期检查状态，能精确抓到"前一个
    // 没被真的清掉"这种回归。
    it('flyStickerGhost 连续两次只留最后一个 timer，前一个到期不会误清后一个的残影', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        const controller: ChatOverlayState = controllerOn(host);

        host.effectDurationQueue = [20]; // 第一次：收尾定时器 20+40=60ms 后到期
        controller.flyStickerGhost('/a.png', 1, 2);
        expect(controller.stickerGhostPath).assertEqual('/a.png');

        host.effectDurationQueue = [300]; // 第二次：收尾定时器 300+40=340ms 后到期
        controller.flyStickerGhost('/b.png', 3, 4);
        expect(controller.stickerGhostPath).assertEqual('/b.png');
        expect(host.setEmojiPanelCalls).assertDeepEquals([false, false]);

        // 150ms：早过第一个定时器的 60ms（如果没被清掉，这里已经把残影清成
        // ''），又远没到第二个定时器的 340ms。
        await sleep(150);
        expect(controller.stickerGhostPath).assertEqual('/b.png');
        expect(controller.stickerGhostX).assertEqual(3);
        expect(controller.stickerGhostY).assertEqual(4);
      });

    // 防的回归：dispose() 里清 stickerGhostTimer 的那段 clearTimeout 被删掉
    // 或被弱化——页面已经销毁，之前那个收尾定时器到期时不该再写控制器的字段
    // （B11 新增的加固，原 aboutToDisappear 全链路对这个定时器没有任何清理，
    // 这里就是要验证"新增的加固"确实生效）。
    it('dispose() 之后，之前挂起的收尾定时器到期不再写字段', 0, async (): Promise<void> => {
      const host: FakeHost = new FakeHost();
      const controller: ChatOverlayState = controllerOn(host);

      host.effectDurationQueue = [20]; // 收尾定时器 20+40=60ms 后到期
      controller.flyStickerGhost('/x.png', 5, 6);
      expect(controller.stickerGhostPath).assertEqual('/x.png');

      controller.dispose(); // 应该把这颗还没到期的收尾定时器 clearTimeout 掉

      await sleep(150); // 早过原本 60ms 的到期时刻
      expect(controller.stickerGhostPath).assertEqual('/x.png'); // 没被那颗本该被清掉的定时器改写
    });

    // 防的回归：resetSession() 漏清 3 个字段中的任意一个，或者越界碰了不属于
    // 它的字段（转发弹层、贴纸残影）。逐一摆好前置状态（先开转发，再开反应，
    // 避免 openForwardPicker 内部联动的 closeReactionSheet() 把顺序搅乱），
    // 调用一次 resetSession()，逐字段核对。
    //
    // 【为什么转发弹层**不**在这个集合里，且必须断言它没被清掉】
    // 原 resetMessageActionSession 里本簇有四行，但第四行 closeForwardSheet()
    // 排在别簇的 `paidMediaPendingIds = []` 之后，不与前三行相连。把四行一并
    // 收进 resetSession() 就等于改了语句顺序，所以只收前三行，closeForwardSheet()
    // 由页面在原位单独调（理由写在 ChatOverlayState.resetSession 上方）。
    // 这条断言就是那个决定的钉子：哪天有人图省事把 closeForwardSheet() 挪进
    // resetSession()，这里会红。
    it('resetSession() 只清 3 个字段：showReactionSheet/reactionTargetId/reactionPendingKey，不碰转发与贴纸残影', 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        const wired: WiredStore = newWiredStore(1);
        host.storeValue = wired.store;
        host.findMsgResult = anyMessageEntry();
        const controller: ChatOverlayState = controllerOn(host);

        controller.openForwardPicker([10, 20]);
        controller.openReactionSheet(5);
        controller.toggleReaction(5, 'ce:9', false); // 同步设锁，不需要等响应回来
        host.effectDurationQueue = [1000]; // 收尾定时器留在很远的将来，测试期间不会到期
        controller.flyStickerGhost('/z.png', 7, 8);

        expect(controller.showForwardSheet).assertTrue();
        expect(controller.showReactionSheet).assertTrue();
        expect(controller.reactionPendingKey).assertEqual('5_ce:9');
        expect(controller.stickerGhostPath).assertEqual('/z.png');

        controller.resetSession();

        expect(controller.showReactionSheet).assertFalse();
        expect(controller.reactionTargetId).assertEqual(0);
        expect(controller.reactionPendingKey).assertEqual('');
        // 边界核对一：转发弹层由页面在原位单独关（见上方说明），resetSession()
        // 自己不许碰——碰了就是把语句顺序改回去了。
        expect(controller.showForwardSheet).assertTrue();
        expect(controller.forwardMessageIds).assertDeepEquals([10, 20]);
        // 边界核对二：贴纸残影不属于 resetSession() 的字段集合，不该被顺带清空。
        expect(controller.stickerGhostPath).assertEqual('/z.png');
      });

    // 防的回归：这条是本批侦察报告特别标注的"顶替风险"——dispose() 和
    // resetSession() 的字段集合本来就不对称（原 disposeTimersAndSeqGuards
    // 那条路径从来没清过 reactionPendingKey），如果有人图省事把 dispose()
    // "顺手修好"成也清 reactionPendingKey，就是把一个原有的、有意保留的
    // 不对称行为悄悄改掉了。
    it('dispose() 清 3 个字段但保留 reactionPendingKey——与 resetSession() 不对称，如实保留', 0,
      (): void => {
        const host: FakeHost = new FakeHost();
        const wired: WiredStore = newWiredStore(1);
        host.storeValue = wired.store;
        host.findMsgResult = anyMessageEntry();
        const controller: ChatOverlayState = controllerOn(host);

        controller.openForwardPicker([1]);
        controller.openReactionSheet(2);
        controller.toggleReaction(2, 'ce:1', false);
        expect(controller.reactionPendingKey).assertEqual('2_ce:1');

        controller.dispose();

        expect(controller.showReactionSheet).assertFalse();
        expect(controller.reactionTargetId).assertEqual(0);
        expect(controller.showForwardSheet).assertFalse();
        expect(controller.forwardMessageIds).assertDeepEquals([]);
        // 关键一条：reactionPendingKey 原样保留，不被 dispose() 清空。
        expect(controller.reactionPendingKey).assertEqual('2_ce:1');
      });

    // 防的回归：有人把控制器做成模块级单例，或者 dispose 波及了别的实例。
    // 平板分栏、导航栈多层时同时活着多个 ChatPage，各自的弹层状态互不相干。
    it('两个实例互不影响（防的回归：做成模块级单例，分栏两页共用一份弹层状态）', 0,
      (): void => {
        const a: ChatOverlayState = controllerOn(new FakeHost());
        const b: ChatOverlayState = controllerOn(new FakeHost());

        a.setSheet('poll', true);
        a.openForwardPicker([1, 2]);

        expect(b.showPollSheet).assertFalse();
        expect(b.showForwardSheet).assertFalse();
        expect(b.forwardMessageIds).assertDeepEquals([]);

        b.setSheet('contact', true);
        a.dispose();

        expect(b.showContactSheet).assertTrue(); // a.dispose() 没有波及 b
        expect(a.showForwardSheet).assertFalse(); // a 自己确实被清了
      });
  });
}
