import { describe, expect, it } from '@ohos/hypium';
import {
  CommandSuggestionHost, CommandSuggestionState,
  InlineQueryHost, InlineQueryState,
  MentionSuggestionHost, MentionSuggestionState,
  StickerSuggestionHost, StickerSuggestionState
} from '../main/ets/pages/chat/ComposerSuggestionState';
import { CommandItem, MentionItem } from '../main/ets/store/InputSuggestions';
import { InlineResultRow } from '../main/ets/store/BotApi';
import { StickerSuggestion } from '../main/ets/pages/chat/ComposerStrips';
import { MessageStore } from '../main/ets/store/MessageStore';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';

// 输入条上方四块建议面板控制器（B14 从 ChatPage 整体搬出）的第一组断言。
// 写法照抄 ChatOverlayState.test.ets / SearchSession.test.ets（FakeHost、
// untilTdlibSend 吞异常的包装函数、文件头先说环境限制）。
//
// ★★★ 【验收时的重大更新：下面那一大段"核心环境限制"已经**基本作废**】★★★
//
// 这个文件最初写成的时候，四个类的方法体里直接调模块级 `getTdClient()`，本地
// 从不 initTdKit()、拿到的是 undefined，`.send(...)` 那一行同步抛错——四簇的
// seq 守卫（丢弃陈旧响应）全部活在 .then()/.catch() 里，一条用例都写不出来，
// 包括方案原文点名的"本批最重要的一条钉子"（inlineSeq 一个字段同时守两条链）。
// 下面那段限制说明就是在那个前提下写的，论证本身没错。
//
// 验收时补了一条注入缝：四个 Host 各加一个 `client: () => TdClient` 取值器，
// 方法体改经 `this.host.client()`，页面侧实现恒为 `() => getTdClient()`
// （见 ComposerSuggestionState.ets 里 client 取值器上方那段）。这正是方案 §3
// 早就写好的约定——"异步用注入的 fake"——只是这四个类原来没留缝。
//
// 缝开之后：
//   - 测试注入一个 FakeBridge 撑起来的**真** TdClient，异步回调全部走得通；
//   - inlineSeq 那条钉子已经有真用例了（"新查询作废掉在途的缩略图回填"），
//     并且真去把 inlineSeq 拆成两个字段验证过：只有它一条红；
//   - mentionSeq 的陈旧响应丢弃也有真用例了；
//   - 那个"320ms 定时炸弹"随之消失——回调不再抛错，用例自己把它结算掉。
//
// 仍然到不了的，只剩两处，已分别记在 skippedAreas 里：
//   1. 查询成功链的**第二跳**：BotApi.getInlineResults 内部用的仍是模块级
//      getTdClient()，那在 store/BotApi.ets、不属于 B14 范围。因此
//      inlineQueryId 在本地设不上非空值。
//   2. StickerSuggestionState.refreshStickerSuggestions 调的 getStickersForEmoji
//      同样自己不收 client 参数（store/StickerApi.ets），同上。
//
// 下面这段保留，是为了记住"为什么当初写不出来"以及那条缝到底换回了什么。
//
// 【核心环境限制，读用例前必看——本文件四个类全部撞上，比以往任何一个前例
// 撞得都全】
//
// 四簇的"seq 守卫丢弃陈旧响应"逻辑，全部活在网络请求的**成功/失败回调**里：
//   - MentionSuggestionState.refreshMentions  → searchMentions(getTdClient(),…)
//   - CommandSuggestionState.ensureCommandsLoaded → loadBotCommands(getTdClient(),…)
//   - InlineQueryState.refreshInlineQuery/downloadInlineThumb → 直接
//     getTdClient().send(…)
//   - StickerSuggestionState.refreshStickerSuggestions/downloadSuggestionThumb
//     → getStickersForEmoji(…) / 直接 getTdClient().send(…)
// 本地测试从没跑过 initTdKit()，tdkit/Globals 里的模块级 `client` 永远是
// undefined，`getTdClient()` 把它原样 `!` 断言吐出去（编译产物里不留运行时
// 检查）。这与 ChatOverlayState.test.ets 的 ensureAllowedReactions()、
// SearchSession.test.ets 的 run() 是同一个环境限制，这里再说一遍是因为它这次
// 挡住了全部四簇，不是某一个方法的个别情况：
//
//   1. searchMentions / loadBotCommands 是**普通函数**（非 async），内部直接
//      `client.send(req)`——client 是 undefined，`.send` 属性访问同步抛
//      TypeError，抛错发生在 refreshMentions()/ensureCommandsLoaded() 的调用
//      栈里，**同步**冒泡出来，从未产出一个 Promise 供 `.then()` 挂载。
//      InlineQueryState 里两处直接 `getTdClient().send(...)` 同理。
//   2. StickerSuggestionState.refreshStickerSuggestions 调的
//      getStickersForEmoji 是 **async function**——`await
//      getTdClient().send(...)` 里那次同步抛错会被 async 函数机制自动接住、
//      转成返回的 Promise 被 reject，而不是同步抛给调用方。这是它与前三簇
//      唯一的行为差异：调用 refreshStickerSuggestions 本身不抛，`.catch(()=>
//      {})` 悄悄吞掉那次 reject。但落地到"能不能测"上结果一样——`.then()`
//      里那段真正的 items 构建 + seq 比对代码，永远够不着。
//
// 结论：**四簇 seq 守卫"丢弃陈旧响应"这条核心行为，在本地环境下都验证不了**
// ——不是覆盖力度的取舍，是这条路径在本地根本跑不通，同 ChatOverlayState.
// test.ets 处理 ensureAllowedReactions() 的方式一致：如实记录、不写一条
// "包一层 try/catch、什么都断言不到"的凑数用例。下面对这四个方法只测**抛错/
// reject 之前**那一小段真实可观察的同步效果（guard 是否短路、host 的哪些
// 取值器被摸过），用 untilTdlibSend() 包一层。
//
// 【inlineTimer 单独的、更严重的一条限制——本文件从头到尾都不触发
// refreshInlineQuery 的"@bot query"匹配分支】
//
// 该分支的第一步是纯同步的（seq 自增、可能 clearTimeout 一个旧定时器、
// setTimeout 排一个新的 320ms 定时器），本身不碰 getTdClient()，看似安全。
// 但 320ms 后一旦真的到点，定时器回调体的第一行就是
// `getTdClient().send(...)`——这次抛错发生在一个**外部够不着、catch 不住**的
// setTimeout 回调里，不是同步抛给测试代码，untilTdlibSend 包不住它。
// 更关键的是：据 B14 侦察报告 2，`aboutToDisappear`/本类的 dispose() 现状
// **从不清理 inlineTimer**（这是要如实保留的行为，不是本文件要修的 bug）——
// 也就是说不存在任何公开 API 能在测试结束前把这个定时器安全收掉。本文件的
// 全部用例跑在同一个 hypium 进程里（List.test.ets 把几百个 describe 注册在
// 一起顺序跑），只要这里排下一个定时器，它迟早会在**某条完全不相关的用例**
// 执行期间到点、抛出一个没人接得住的异常——这不是"回归时才会红"的残余风险
// （对照 SearchSession.test.ets 对 entryTimer 的处理：那边定时器在正确代码下
// 会被 dispose() 提前清掉，只有故意改坏 dispose() 才会真的到点），这里是
// **在正确代码下也一样会到点**，属于会拖累整个测试进程的真实定时炸弹。
// 因此本文件的决定是：全程不构造任何一次匹配 `/^@([A-Za-z0-9_]{3,32})\s+(.*)$/`
// 的 refreshInlineQuery 调用，inlineSeq/inlineTimer 的真实行为（含方案原文
// 点名的"一个字段同时守两件事"）在本地环境下**无法安全验证**，如实记录在
// 这里，不用一条会威胁全仓测试稳定性的用例去凑数。
// downloadInlineThumb 不经过定时器（直接方法调用，抛错同步冒泡到调用方），
// 因此可以安全地直接调用并用 try/catch 接住，下面测的就是这一条。


// 用一个假桥撑起一个**真** TdClient。这是 B14 验收时补的注入缝带来的能力：
// 四簇的 seq 守卫（丢弃陈旧响应）全部活在 .then()/.catch() 回调里，搬迁前那些
// 方法体直接调模块级 getTdClient()，本地从不 initTdKit()、拿到的是 undefined，
// send() 那一行同步抛错、回调永远进不去——守卫一条用例都写不出来。
// 现在 client 经宿主取值器注入，回调走得通，下面几条才成立。
// 形状照抄 ChatOverlayState.test.ets 的 FakeBridge/newWiredStore。
class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

class WiredClient {
  bridge: FakeBridge = new FakeBridge();
  client: TdClient;

  constructor() {
    this.client = new TdClient(this.bridge);
    this.client.start();
  }

  // 按 @extra 把第 index 条在途请求应答掉。payload 是响应体（不含 @extra）。
  respond(index: number, payload: TdObject): void {
    const sent: TdObject = JSON.parse(this.bridge.sent[index]) as TdObject;
    payload['@extra'] = sent['@extra'] as Object;
    this.bridge.onReceive(JSON.stringify(payload));
  }

  // 第 index 条在途请求发的是什么方法。
  methodOf(index: number): string {
    const sent: TdObject = JSON.parse(this.bridge.sent[index]) as TdObject;
    return sent['@type'] as string;
  }
}

class MentionFakeHost implements MentionSuggestionHost {
  chatIdValue: number = 0;
  chatIdCalls: number = 0;
  draftValue: string = '';
  draftCalls: number = 0;
  applyDraftCalls: string[] = [];

  chatId: () => number = (): number => {
    this.chatIdCalls++;
    return this.chatIdValue;
  };
  draft: () => string = (): string => {
    this.draftCalls++;
    return this.draftValue;
  };
  wired: WiredClient = new WiredClient();
  clientCalls: number = 0;
  client: () => TdClient = (): TdClient => {
    this.clientCalls++;
    return this.wired.client;
  };
  applyDraft: (next: string) => void = (next: string): void => {
    this.applyDraftCalls.push(next);
  };
}

class CommandFakeHost implements CommandSuggestionHost {
  chatIdValue: number = 0;
  chatIdCalls: number = 0;
  storeValue: MessageStore | null = null;
  storeCalls: number = 0;
  draftValue: string = '';
  draftCalls: number = 0;

  chatId: () => number = (): number => {
    this.chatIdCalls++;
    return this.chatIdValue;
  };
  store: () => MessageStore | null = (): MessageStore | null => {
    this.storeCalls++;
    return this.storeValue;
  };
  draft: () => string = (): string => {
    this.draftCalls++;
    return this.draftValue;
  };
  wired: WiredClient = new WiredClient();
  clientCalls: number = 0;
  client: () => TdClient = (): TdClient => {
    this.clientCalls++;
    return this.wired.client;
  };
}

class InlineFakeHost implements InlineQueryHost {
  chatIdValue: number = 0;
  chatIdCalls: number = 0;

  chatId: () => number = (): number => {
    this.chatIdCalls++;
    return this.chatIdValue;
  };
  wired: WiredClient = new WiredClient();
  clientCalls: number = 0;
  client: () => TdClient = (): TdClient => {
    this.clientCalls++;
    return this.wired.client;
  };
}

class StickerFakeHost implements StickerSuggestionHost {
  wired: WiredClient = new WiredClient();
  clientCalls: number = 0;
  client: () => TdClient = (): TdClient => {
    this.clientCalls++;
    return this.wired.client;
  };
}


// 一条"成员表为空"的 searchChatMembers 应答。空表让 searchMentions 里的
// Promise.all([]) 立刻兑现，控制器的 .then() 因此不必等第二跳 getUser 就能跑到。
function emptyChatMembers(): TdObject {
  const res: TdObject = { '@type': 'chatMembers' };
  res['total_count'] = 0;
  res['members'] = [];
  return res;
}

function mentionControllerOn(host: MentionFakeHost): MentionSuggestionState {
  const controller: MentionSuggestionState = new MentionSuggestionState();
  controller.bind(host);
  return controller;
}

function commandControllerOn(host: CommandFakeHost): CommandSuggestionState {
  const controller: CommandSuggestionState = new CommandSuggestionState();
  controller.bind(host);
  return controller;
}

function inlineControllerOn(host: InlineFakeHost): InlineQueryState {
  const controller: InlineQueryState = new InlineQueryState();
  controller.bind(host);
  return controller;
}

function stickerControllerOn(host: StickerFakeHost): StickerSuggestionState {
  const controller: StickerSuggestionState = new StickerSuggestionState();
  controller.bind(host);
  return controller;
}

// 见文件头：mention/command/inline 三簇一碰 getTdClient() 就同步抛错——这里
// 把"环境缺失导致的抛错"和"被测逻辑本身的错误"分开，只吞前者，被断言的都是
// 抛错之前那一小段真实同步效果。
function untilTdlibSend(action: () => void): boolean {
  try {
    action();
    return false; // 没抛：说明这次调用命中了某个短路 guard，属于阳性分支
  } catch (e) {
    return true; // 抛了：走到了 getTdClient() 那一步，环境限制生效
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

const aliceWithUsername: MentionItem = { userId: 5, name: 'Alice', username: 'alice' };
const bobNoUsername: MentionItem = { userId: 7, name: 'Bob', username: '' };
const noNameNoUsername: MentionItem = { userId: 9, name: '', username: '' };
const zeroIdNoUsername: MentionItem = { userId: 0, name: 'Ghost', username: '' };

function sentinelCommandItems(): CommandItem[] {
  return [{ command: 'sentinel', description: '', botUserId: 0, botUsername: '' }];
}

function inlineRow(resultId: string, thumbFileId: number = 0): InlineResultRow {
  return {
    resultId, title: '', description: '', thumbFileId, thumbPath: '',
    kind: 'article', animationFileId: 0
  };
}

function stickerSuggestion(fileId: number, thumbId: number = 0): StickerSuggestion {
  return { fileId, thumbId, thumbPath: '' };
}

export default function composerSuggestionStateTest() {
  describe('ComposerSuggestionState', () => {

    // ========================================================================
    // MentionSuggestionState
    // ========================================================================

    // 防的回归：pickMention 的 idx>=0 分支截错草稿头部，或者 mentionToken
    // 的用户名分支被削弱。'@' 在草稿中间，只截到那个位置之前。
    it('pickMention：光标前有用户名的候选，替换尾部 @token，不记 pendingNameMentions', 0, (): void => {
      const host: MentionFakeHost = new MentionFakeHost();
      host.draftValue = 'hello @al';
      const controller: MentionSuggestionState = mentionControllerOn(host);
      controller.mentionItems = [aliceWithUsername];

      const next: string = controller.pickMention(aliceWithUsername);

      expect(next).assertEqual('hello @alice ');
      expect(controller.mentionItems).assertDeepEquals([]);
      expect(controller.readPendingNameMentions()).assertDeepEquals([]); // 有用户名，不必记
    });

    // 防的回归：pickMention 里 idx<0（草稿里根本没有 '@'）分支被错误地当成
    // idx>=0 处理，截掉了不该截的文本。
    it('pickMention：草稿里没有 @ 时，idx<0 分支保留整段草稿作为 head', 0, (): void => {
      const host: MentionFakeHost = new MentionFakeHost();
      host.draftValue = 'hello';
      const controller: MentionSuggestionState = mentionControllerOn(host);

      const next: string = controller.pickMention(aliceWithUsername);

      expect(next).assertEqual('hello@alice ');
    });

    // 防的回归：rememberNameMention 的"无用户名才记"判据被删掉/削弱——没有
    // username 的候选，选中后必须落进 pendingNameMentions，供 doSend 补
    // textEntityTypeMentionName 实体。
    it('pickMention：无用户名的候选记入 pendingNameMentions（供 doSend 建实体）', 0, (): void => {
      const host: MentionFakeHost = new MentionFakeHost();
      host.draftValue = '@';
      const controller: MentionSuggestionState = mentionControllerOn(host);

      const next: string = controller.pickMention(bobNoUsername);

      expect(next).assertEqual('Bob ');
      expect(controller.readPendingNameMentions()).assertDeepEquals([{ name: 'Bob', userId: 7 }]);
    });

    // 防的回归：rememberNameMention 的另外两道短路判据（name===''、
    // userId<=0）被删掉——不该记的垃圾数据混进 pendingNameMentions，doSend
    // 建实体时会拿着一个空名字或非法 id 去拼 textEntityTypeMentionName。
    it('pickMention：name 为空或 userId<=0 时不记 pendingNameMentions', 0, (): void => {
      const host: MentionFakeHost = new MentionFakeHost();
      host.draftValue = '@';
      const controller: MentionSuggestionState = mentionControllerOn(host);

      controller.pickMention(noNameNoUsername);
      controller.pickMention(zeroIdNoUsername);

      expect(controller.readPendingNameMentions()).assertDeepEquals([]);
    });

    // 防的回归：rememberNameMention 的去重判据（userId+name 都相同才算
    // "已记过"）被删掉——同一个人被连续按名字提及两次，实体列表里出现重复项。
    it('pickMention：同一 userId+name 的候选连续选中两次，只记一条（去重）', 0, (): void => {
      const host: MentionFakeHost = new MentionFakeHost();
      host.draftValue = '@';
      const controller: MentionSuggestionState = mentionControllerOn(host);

      controller.pickMention(bobNoUsername);
      host.draftValue = '@'; // 模拟页面在两次选中之间把草稿重新摆回 '@' 状态
      controller.pickMention(bobNoUsername);

      expect(controller.readPendingNameMentions()).assertDeepEquals([{ name: 'Bob', userId: 7 }]);
    });

    it('readPendingNameMentions/clearPendingNameMentions/restorePendingNameMentions：三个读写口子各自生效', 0,
      (): void => {
        const host: MentionFakeHost = new MentionFakeHost();
        host.draftValue = '@';
        const controller: MentionSuggestionState = mentionControllerOn(host);
        controller.pickMention(bobNoUsername);
        expect(controller.readPendingNameMentions()).assertDeepEquals([{ name: 'Bob', userId: 7 }]);

        controller.clearPendingNameMentions();
        expect(controller.readPendingNameMentions()).assertDeepEquals([]);

        controller.restorePendingNameMentions([{ name: 'Snapshot', userId: 99 }]);
        expect(controller.readPendingNameMentions()).assertDeepEquals([{ name: 'Snapshot', userId: 99 }]);
      });

    // 防的回归：clear() 顺手清了 pendingNameMentions——全仓现状 7+ 处调用点
    // 只清 mentionItems 这一个字段，pendingNameMentions 要活到 doSend 才清。
    it('MentionSuggestionState.clear() 只清 mentionItems，不碰 pendingNameMentions', 0, (): void => {
      const host: MentionFakeHost = new MentionFakeHost();
      host.draftValue = '@';
      const controller: MentionSuggestionState = mentionControllerOn(host);
      controller.pickMention(bobNoUsername);
      controller.mentionItems = [aliceWithUsername];

      controller.clear();

      expect(controller.mentionItems).assertDeepEquals([]);
      expect(controller.readPendingNameMentions()).assertDeepEquals([{ name: 'Bob', userId: 7 }]);
    });

    // 防的回归：dispose() 新增了原本没有的清理动作（见文件头/主文件注释：原
    // aboutToDisappear 全链路对这簇字段一处清理都没有，dispose() 必须原样
    // 空实现，不许"顺手加固"）。
    it('MentionSuggestionState.dispose() 是空实现，不清 mentionItems/pendingNameMentions', 0, (): void => {
      const host: MentionFakeHost = new MentionFakeHost();
      host.draftValue = '@';
      const controller: MentionSuggestionState = mentionControllerOn(host);
      controller.pickMention(bobNoUsername);
      controller.mentionItems = [aliceWithUsername];

      controller.dispose();

      expect(controller.mentionItems).assertDeepEquals([aliceWithUsername]);
      expect(controller.readPendingNameMentions()).assertDeepEquals([{ name: 'Bob', userId: 7 }]);
    });

    // 验收时补的注入缝（host.client()）让这条路径的 .then() 回调终于走得通。
    // 原来这里是一条"断言它必然抛错"的用例——它断言的是**环境限制本身**，
    // 不是被测逻辑；缝一开限制就没了，那条用例也就失去了意义，改写成下面两条。
    //
    // searchMentions 拿到成员 id 之后还要逐个 getUser 二次往返；这两条用例都
    // 用"成员表为空"的应答，让 Promise.all([]) 立刻兑现、直接跑进 .then()，
    // 不必构造第二跳。要断言的是守卫本身，不是 searchMentions 的解析。

    // 防的回归：拿到响应后不写 mentionItems（.then() 整段被跳过）。
    it('refreshMentions：响应回来且 @ 触发仍在时，结果写进 mentionItems', 0,
      async (): Promise<void> => {
        const host: MentionFakeHost = new MentionFakeHost();
        host.chatIdValue = 42;
        host.draftValue = '@al'; // 响应回来时 '@' 触发还在，那道判据放行
        const controller: MentionSuggestionState = mentionControllerOn(host);
        controller.mentionItems = [aliceWithUsername]; // 哨兵：被真实响应覆盖才算写入

        controller.refreshMentions('al');
        await sleep(0);
        expect(host.wired.bridge.sent.length).assertEqual(1);
        expect(host.chatIdCalls).assertEqual(1);

        host.wired.respond(0, emptyChatMembers());
        await sleep(0);

        expect(controller.mentionItems).assertDeepEquals([]); // 哨兵被覆盖 = .then() 真的跑了
      });

    // 防的回归（mentionSeq 守卫）：陈旧响应被写回面板。连发两次查询，只应答
    // **先**发的那条——它的 seq 已经过期，结果必须被丢掉。守卫一删，这份陈旧
    // 结果就会盖掉面板当前的内容。
    //
    // 这条是 B14 验收时补的：搬迁前它属于"本地根本跑不通"的那一类，注入缝
    // 开了之后才写得出来。四簇 seq 守卫里这是能覆盖到的第一个。
    it('refreshMentions：陈旧响应被 mentionSeq 丢弃，不覆盖当前面板', 0,
      async (): Promise<void> => {
        const host: MentionFakeHost = new MentionFakeHost();
        host.chatIdValue = 42;
        host.draftValue = '@al';
        const controller: MentionSuggestionState = mentionControllerOn(host);

        controller.refreshMentions('a');   // 第 1 次，seq=1（这条将成为陈旧的那个）
        controller.refreshMentions('al');  // 第 2 次，seq=2（当前有效）
        await sleep(0);
        expect(host.wired.bridge.sent.length).assertEqual(2);

        controller.mentionItems = [aliceWithUsername]; // 哨兵 = 面板当前的内容

        host.wired.respond(0, emptyChatMembers()); // 只应答第 1 次（已过期）
        await sleep(0);

        // 守卫在：哨兵原样留着。守卫没了：会被写成 []。
        expect(controller.mentionItems).assertDeepEquals([aliceWithUsername]);
      });

    // 防的回归：把控制器做成模块级单例，或者两个实例共用了 mentionItems/
    // pendingNameMentions。平板分栏、导航栈多层时同时活着多个 ChatPage。
    it('两个 MentionSuggestionState 实例互不影响', 0, (): void => {
      const a: MentionSuggestionState = mentionControllerOn(new MentionFakeHost());
      const b: MentionSuggestionState = mentionControllerOn(new MentionFakeHost());

      a.mentionItems = [aliceWithUsername];

      expect(b.mentionItems).assertDeepEquals([]);

      a.clear();
      expect(b.mentionItems).assertDeepEquals([]); // a.clear() 没有波及 b
    });

    // ========================================================================
    // CommandSuggestionState
    // ========================================================================

    // 防的回归：commandPanelActive 的正则判据（'/'、'/xxx' 都算触发，纯文字
    // 不算）被削弱或反过来。四种输入各自的期望值逐一钉死。
    it('commandPanelActive：commandMenuOpen 为真时无视草稿内容，恒为真', 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      host.draftValue = 'random text';
      const controller: CommandSuggestionState = commandControllerOn(host);
      controller.commandMenuOpen = true;

      expect(controller.commandPanelActive()).assertTrue();
    });

    it("commandPanelActive：菜单未开时，草稿 '/' 判定为真（空命令也算触发）", 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      host.draftValue = '/';
      const controller: CommandSuggestionState = commandControllerOn(host);

      expect(controller.commandPanelActive()).assertTrue();
    });

    it("commandPanelActive：菜单未开时，草稿 '/a' 判定为真", 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      host.draftValue = '/a';
      const controller: CommandSuggestionState = commandControllerOn(host);

      expect(controller.commandPanelActive()).assertTrue();
    });

    it("commandPanelActive：菜单未开时，纯文字草稿 'a' 判定为假", 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      host.draftValue = 'a';
      const controller: CommandSuggestionState = commandControllerOn(host);

      expect(controller.commandPanelActive()).assertFalse();
    });

    it("commandPanelActive：菜单未开时，空草稿 '' 判定为假", 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      host.draftValue = '';
      const controller: CommandSuggestionState = commandControllerOn(host);

      expect(controller.commandPanelActive()).assertFalse();
    });

    // 防的回归：applyCommandFilter 的 commandMenuOpen 分支忘了重新赋值
    // commandItems（哪怕目录是空的也要覆盖掉旧值，不能让上一轮的残留项
    // 挂在面板上）。用 sentinel 证明"确实被重新赋值"而不是"本来就是空"。
    it('applyCommandFilter：菜单打开+目录 ready 时，commandItems 被重新赋值（本地环境下目录恒为空）', 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      const controller: CommandSuggestionState = commandControllerOn(host);
      controller.commandMenuOpen = true;
      controller.commandLoadState = 'ready';
      controller.commandItems = sentinelCommandItems();

      controller.applyCommandFilter();

      expect(controller.commandItems).assertDeepEquals([]);
    });

    it('applyCommandFilter：菜单打开+目录未 ready 时，commandItems 清空', 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      const controller: CommandSuggestionState = commandControllerOn(host);
      controller.commandMenuOpen = true;
      controller.commandLoadState = 'idle';
      controller.commandItems = sentinelCommandItems();

      controller.applyCommandFilter();

      expect(controller.commandItems).assertDeepEquals([]);
    });

    it('applyCommandFilter：菜单关闭+草稿不匹配 / 命令正则时，commandItems 清空', 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      host.draftValue = 'not a command';
      const controller: CommandSuggestionState = commandControllerOn(host);
      controller.commandItems = sentinelCommandItems();

      controller.applyCommandFilter();

      expect(controller.commandItems).assertDeepEquals([]);
    });

    it('applyCommandFilter：菜单关闭+草稿匹配但目录未 ready 时，commandItems 清空', 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      host.draftValue = '/foo';
      const controller: CommandSuggestionState = commandControllerOn(host);
      controller.commandLoadState = 'idle';
      controller.commandItems = sentinelCommandItems();

      controller.applyCommandFilter();

      expect(controller.commandItems).assertDeepEquals([]);
    });

    // 目录在本地环境下恒为空（allCommands 私有，只能靠 loadBotCommands 成功
    // 回调填充，那一步够不着——见文件头），因此 q/botQuery 的实际前缀过滤
    // 逻辑（328 行 filter 本身）在本地测不到，如实记入 skippedAreas。这里只
    // 证明"菜单关闭+匹配+ready"分支确实走到了过滤那几行、没有半途漏掉赋值。
    it('applyCommandFilter：菜单关闭+草稿匹配+目录 ready 时，对空目录过滤结果仍是 []（分支执行到底）', 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      host.draftValue = '/foo@bar';
      const controller: CommandSuggestionState = commandControllerOn(host);
      controller.commandLoadState = 'ready';
      controller.commandItems = sentinelCommandItems();

      controller.applyCommandFilter();

      expect(controller.commandItems).assertDeepEquals([]);
    });

    // 防的回归：ensureCommandsLoaded 的短路 guard（loading/ready 且非强制）
    // 被削弱或删掉——面板打开时草稿每敲一个字符都会重新发一次目录请求。
    it('ensureCommandsLoaded：commandLoadState=loading 且非强制时短路，不摸 host、不抛错', 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      const controller: CommandSuggestionState = commandControllerOn(host);
      controller.commandLoadState = 'loading';

      const threw: boolean = untilTdlibSend((): void => {
        controller.ensureCommandsLoaded();
      });

      expect(threw).assertFalse();
      expect(host.chatIdCalls).assertEqual(0);
      expect(host.storeCalls).assertEqual(0);
      expect(controller.commandLoadState).assertEqual('loading'); // 原样未动
    });

    it('ensureCommandsLoaded：commandLoadState=ready 且非强制时同样短路', 0, (): void => {
      const host: CommandFakeHost = new CommandFakeHost();
      const controller: CommandSuggestionState = commandControllerOn(host);
      controller.commandLoadState = 'ready';

      const threw: boolean = untilTdlibSend((): void => {
        controller.ensureCommandsLoaded();
      });

      expect(threw).assertFalse();
      expect(host.chatIdCalls).assertEqual(0);
    });

    // 防的回归：force=true 却仍然被短路 guard 挡住——toggleBotMenu 的
    // onRetryCommands 场景永远重试不了。
    it('ensureCommandsLoaded：force=true 时绕过短路，即使 commandLoadState=ready 也继续（进而在 getTdClient() 处同步抛错，环境限制）', 0,
      (): void => {
        const host: CommandFakeHost = new CommandFakeHost();
        const controller: CommandSuggestionState = commandControllerOn(host);
        controller.commandLoadState = 'ready';
        controller.commandLoadError = '之前的错误';

        controller.ensureCommandsLoaded(true);

        // 缝开之后这条路径不再抛错，请求真的发得出去了。
        expect(host.wired.bridge.sent.length).assertEqual(1);
        expect(host.chatIdCalls).assertEqual(1);
        expect(host.storeCalls).assertEqual(1);
        expect(controller.commandLoadState).assertEqual('loading'); // 抛错前已切换
        expect(controller.commandLoadError).assertEqual(''); // 抛错前已清空旧错误
      });

    // 见文件头环境限制：默认 idle 状态下 ensureCommandsLoaded 一定会走到
    // getTdClient() 那一步同步抛错，与 force=true 的分支同构，单独钉一条
    // 覆盖"从未强制过、第一次自然触发"的最常见路径。
    it('ensureCommandsLoaded：默认 idle 状态下不短路，抛错前已读 host.chatId()/host.store() 并置为 loading', 0,
      (): void => {
        const host: CommandFakeHost = new CommandFakeHost();
        host.chatIdValue = 7;
        const controller: CommandSuggestionState = commandControllerOn(host);

        controller.ensureCommandsLoaded();

        expect(host.wired.bridge.sent.length).assertEqual(1);
        expect(host.chatIdCalls).assertEqual(1);
        expect(host.storeCalls).assertEqual(1);
        expect(controller.commandLoadState).assertEqual('loading');
      });

    // 防的回归：refreshCommands 漏调 applyCommandFilter，或者调用顺序反过来
    // （先 filter 后 load，导致过滤用的是上一轮的草稿判据）。用短路 guard
    // 挡住 ensureCommandsLoaded 那一半，让整条调用链在本地环境下完整跑通、
    // 不需要 try/catch——这是本文件对 refreshCommands 唯一一条不吞异常的
    // 正向用例。
    it('refreshCommands：guard 短路 ensureCommandsLoaded 时，applyCommandFilter 仍然执行并重置 commandItems', 0,
      (): void => {
        const host: CommandFakeHost = new CommandFakeHost();
        host.draftValue = '/foo';
        const controller: CommandSuggestionState = commandControllerOn(host);
        controller.commandLoadState = 'loading'; // 短路 ensureCommandsLoaded
        controller.commandItems = sentinelCommandItems();

        controller.refreshCommands(); // 不包 try/catch：这条路径本身不该抛错

        expect(host.chatIdCalls).assertEqual(0); // ensureCommandsLoaded 被短路，没碰 host
        expect(host.draftCalls).assertEqual(1); // applyCommandFilter 确实读了草稿
        expect(controller.commandItems).assertDeepEquals([]); // 目录未 ready，过滤清空
      });

    // catalogSize() 只读取值器：本地环境下 allCommands 恒为空（只能靠够不着
    // 的网络成功回调填充），这里只能钉住初始值，非零的情形记入 skippedAreas。
    it('catalogSize()：初始值为 0', 0, (): void => {
      const controller: CommandSuggestionState = commandControllerOn(new CommandFakeHost());
      expect(controller.catalogSize()).assertEqual(0);
    });

    // 防的回归：clear() 漏清 7 个字段中的任意一个，或者顺手清了不该清的。
    it('CommandSuggestionState.clear()：7 个字段全部复位', 0, (): void => {
      const controller: CommandSuggestionState = commandControllerOn(new CommandFakeHost());
      controller.commandItems = sentinelCommandItems();
      controller.commandLoadState = 'error';
      controller.commandLoadError = '之前的错误';
      controller.commandMenuOpen = true;
      controller.botMenuAvailable = true;

      controller.clear();

      expect(controller.commandItems).assertDeepEquals([]);
      expect(controller.catalogSize()).assertEqual(0);
      expect(controller.commandLoadState).assertEqual('idle');
      expect(controller.commandLoadError).assertEqual('');
      expect(controller.commandMenuOpen).assertFalse();
      expect(controller.botMenuAvailable).assertFalse();
    });

    // 防的回归：closePanel() 越界碰了 commandLoadState/commandLoadError/
    // botMenuAvailable——那几个字段现状只有 resetComposerSession 的全量
    // clear() 才动，closePanel() 只该动 commandMenuOpen+commandItems 两个。
    it('CommandSuggestionState.closePanel()：只清 commandMenuOpen+commandItems，不碰其余字段', 0, (): void => {
      const controller: CommandSuggestionState = commandControllerOn(new CommandFakeHost());
      controller.commandItems = sentinelCommandItems();
      controller.commandMenuOpen = true;
      controller.commandLoadState = 'ready';
      controller.botMenuAvailable = true;

      controller.closePanel();

      expect(controller.commandMenuOpen).assertFalse();
      expect(controller.commandItems).assertDeepEquals([]);
      expect(controller.commandLoadState).assertEqual('ready'); // 未被碰
      expect(controller.botMenuAvailable).assertTrue(); // 未被碰
    });

    // 防的回归：closeMenu() 顺手清了 commandItems——sendPendingMedia/
    // onEditorFocus/doSend 那三处现状只动 commandMenuOpen 一个字段。
    it('CommandSuggestionState.closeMenu()：只清 commandMenuOpen，不碰 commandItems', 0, (): void => {
      const controller: CommandSuggestionState = commandControllerOn(new CommandFakeHost());
      controller.commandItems = sentinelCommandItems();
      controller.commandMenuOpen = true;

      controller.closeMenu();

      expect(controller.commandMenuOpen).assertFalse();
      expect(controller.commandItems).assertDeepEquals(sentinelCommandItems());
    });

    // 防的回归：clearItems() 顺手清了 commandMenuOpen——doSend 里这两处清空
    // 现状不相邻，是分别调用的两件事。
    it('CommandSuggestionState.clearItems()：只清 commandItems，不碰 commandMenuOpen', 0, (): void => {
      const controller: CommandSuggestionState = commandControllerOn(new CommandFakeHost());
      controller.commandItems = sentinelCommandItems();
      controller.commandMenuOpen = true;

      controller.clearItems();

      expect(controller.commandItems).assertDeepEquals([]);
      expect(controller.commandMenuOpen).assertTrue();
    });

    it('CommandSuggestionState.dispose() 是空实现，不清任何字段', 0, (): void => {
      const controller: CommandSuggestionState = commandControllerOn(new CommandFakeHost());
      controller.commandItems = sentinelCommandItems();
      controller.commandMenuOpen = true;
      controller.commandLoadState = 'ready';

      controller.dispose();

      expect(controller.commandItems).assertDeepEquals(sentinelCommandItems());
      expect(controller.commandMenuOpen).assertTrue();
      expect(controller.commandLoadState).assertEqual('ready');
    });

    it('两个 CommandSuggestionState 实例互不影响', 0, (): void => {
      const a: CommandSuggestionState = commandControllerOn(new CommandFakeHost());
      const b: CommandSuggestionState = commandControllerOn(new CommandFakeHost());

      a.commandMenuOpen = true;
      a.commandItems = sentinelCommandItems();

      expect(b.commandMenuOpen).assertFalse();
      expect(b.commandItems).assertDeepEquals([]);

      a.clear();
      expect(b.commandMenuOpen).assertFalse(); // a.clear() 没有波及 b
    });

    // ========================================================================
    // InlineQueryState —— 见文件头：本文件全程不触发 '@bot query' 匹配分支
    // ========================================================================

    // 防的回归：refreshInlineQuery 未匹配分支里"已有结果才清"的判据被削弱
    // 成无条件清空，或者反过来漏清。
    it("refreshInlineQuery：不匹配 '@bot query' 格式且已有结果时，清空 inlineResults", 0, (): void => {
      const controller: InlineQueryState = inlineControllerOn(new InlineFakeHost());
      controller.inlineResults = [inlineRow('r1')];

      controller.refreshInlineQuery('plain text, no bot query');

      expect(controller.inlineResults).assertDeepEquals([]);
      expect(controller.queryId()).assertEqual('');
    });

    it("refreshInlineQuery：不匹配格式且本来就没有结果时，安全无操作（不抛错）", 0, (): void => {
      const controller: InlineQueryState = inlineControllerOn(new InlineFakeHost());

      controller.refreshInlineQuery('plain text');

      expect(controller.inlineResults).assertDeepEquals([]);
    });

    // downloadInlineThumb 不经过定时器，直接方法调用——thumbFileId===0 分支
    // 完全同步安全，不碰 getTdClient()。
    // 【验收时改过断言对象】原来这条只断言 inlineResults 没变——但删掉早退之后
    // 也只是多发一个请求、没有响应回来，inlineResults 照样不变，用例是绿的。
    // 真正该断言的是"一个请求都没发出去"。注入缝把这件事变得可观察了。
    it('downloadInlineThumb：thumbFileId===0 时提前返回，一个请求都不发', 0, (): void => {
      const host: InlineFakeHost = new InlineFakeHost();
      const controller: InlineQueryState = inlineControllerOn(host);
      controller.inlineResults = [inlineRow('r1', 0)];

      controller.downloadInlineThumb(inlineRow('r1', 0), 1);

      expect(host.wired.bridge.sent.length).assertEqual(0); // 早退在发请求之前
      expect(controller.inlineResults).assertDeepEquals([inlineRow('r1', 0)]);
    });

    // 见文件头环境限制：thumbFileId!==0 时会同步走到 getTdClient().send(...)
    // 抛错——这是一次直接方法调用（不经过定时器），可以安全 try/catch。真正
    // 的 seq 比对与 inlineResults 原地替换缩略图（464-469 行）够不着，如实
    // 记入 skippedAreas。
    it('downloadInlineThumb：thumbFileId!==0 时发出 downloadFile 请求', 0, (): void => {
      const host: InlineFakeHost = new InlineFakeHost();
      const controller: InlineQueryState = inlineControllerOn(host);

      controller.downloadInlineThumb(inlineRow('r1', 123), 1);

      expect(host.wired.bridge.sent.length).assertEqual(1);
      expect(host.wired.methodOf(0)).assertEqual('downloadFile');
    });

    // ★ 本批方案点名的"最重要的一条钉子"：inlineSeq 是**一个**字段，同时守着
    // 内联查询与缩略图回填两条链；不许拆成 inlineQuerySeq/inlineThumbSeq 两个。
    //
    // 这条用例在 B14 验收补出注入缝之前写不出来（缩略图链的 .then() 在本地
    // 根本进不去），是这条缝换来的最主要的东西。
    //
    // 反事实推演——如果有人把它拆成两个字段：refreshInlineQuery 只会 bump
    // 查询那一个，缩略图那一个仍停在旧值，于是下面第 5 步那条**已经作废**的
    // 缩略图响应会被判成"新的"，把陈旧缩略图写进当前正在显示的结果行。
    // 这条用例就会红在最后一行断言上。
    //
    // 时序刻意排成这样，是为了全程只留一个待决定时器（T2），并在结尾把它
    // 结算掉——文件头讲过，这个进程跑着全仓几百个 describe，不能留悬空定时器。
    it('inlineSeq 一个字段同时守查询与缩略图两条链：新查询作废掉在途的缩略图回填', 0,
      async (): Promise<void> => {
        const host: InlineFakeHost = new InlineFakeHost();
        host.chatIdValue = 42;
        const controller: InlineQueryState = inlineControllerOn(host);

        // 1. 第一次查询：inlineSeq 0→1，排下 320ms 定时器 T1。
        controller.refreshInlineQuery('@somebot hello');

        // 2. 趁 T1 还没到点，直接用当前 seq=1 发一次缩略图下载。这一步等价于
        //    "查询已经回来、正在逐行回填缩略图"的那个瞬间，只是跳过了中间那两跳。
        controller.downloadInlineThumb(inlineRow('r1', 123), 1);
        expect(host.wired.bridge.sent.length).assertEqual(1);
        expect(host.wired.methodOf(0)).assertEqual('downloadFile');

        // 3. 用户又改了查询词：inlineSeq 1→2，同时 clearTimeout(T1)、排下 T2。
        //    共用一个计数器的意义就在这一步——它把**缩略图那条在途链**也一并作废了。
        controller.refreshInlineQuery('@somebot world');

        // 4. 摆一个哨兵：这是"当前正在显示的结果行"。
        const sentinel: InlineResultRow = inlineRow('r1', 123);
        controller.inlineResults = [sentinel];

        // 5. 第 2 步那条缩略图请求现在才回来——它属于已经作废的那一轮。
        const file: TdObject = { '@type': 'file' };
        const local: TdObject = { '@type': 'localFile' };
        local['path'] = '/should/not/be/written.jpg';
        file['local'] = local;
        host.wired.respond(0, file);
        await sleep(0);

        // 守卫在：哨兵的 thumbPath 原样是空串。
        // 拆成两个 seq：这里会变成 '/should/not/be/written.jpg'。
        expect(controller.inlineResults[0].thumbPath).assertEqual('');

        // 收尾：把 T2 放出来并结算掉它发出的请求，不给后面的用例留悬空定时器。
        await sleep(350);
        expect(host.wired.methodOf(1)).assertEqual('searchPublicChat');
        const err: TdObject = { '@type': 'error' };
        err['code'] = 404;
        err['message'] = 'no such bot';
        host.wired.respond(1, err);
        await sleep(0);
      });

    // 【验收时降级了这条用例的声称范围——原来它是假的】
    // 原名是"inlineResults 与 inlineQueryId 一起清空"，但 inlineQueryId 的初值
    // 本来就是空串，用例从没把它设成非空就断言它是空串——恒绿。把 clear() 里那句
    // `this.inlineQueryId = '';` 整行删掉，这条用例照样全绿（验收时真破验证过）。
    //
    // 为什么修不了：inlineQueryId 是私有字段，唯一的写入点在查询成功链的第二跳
    // （BotApi.getInlineResults 的 .then）里。第一跳（searchPublicChat）现在经
    // host.client() 注入、跑得通了，但第二跳 getInlineResults **内部**用的仍是
    // 模块级 getTdClient()——那在 store/BotApi.ets 里，不属于本批范围。
    // 所以这条路径在本地依然到不了，inlineQueryId 设不上非空值。
    //
    // 于是这里只保留它真正验证得了的那一半（inlineResults 被清空），并把
    // "inlineQueryId 也要一起清"这条记进下面的 skippedAreas。宁可用例名小一点，
    // 也不要一条名字很大、实际什么都没钉住的用例。
    it('InlineQueryState.clear()：清空 inlineResults', 0, (): void => {
      const controller: InlineQueryState = inlineControllerOn(new InlineFakeHost());
      controller.inlineResults = [inlineRow('r1')];

      controller.clear();

      expect(controller.inlineResults).assertDeepEquals([]);
    });

    it('queryId()：初始值为空串', 0, (): void => {
      const controller: InlineQueryState = inlineControllerOn(new InlineFakeHost());
      expect(controller.queryId()).assertEqual('');
    });

    it('InlineQueryState.dispose() 是空实现，不清 inlineResults', 0, (): void => {
      const controller: InlineQueryState = inlineControllerOn(new InlineFakeHost());
      controller.inlineResults = [inlineRow('r1')];

      controller.dispose();

      expect(controller.inlineResults).assertDeepEquals([inlineRow('r1')]);
    });

    it('两个 InlineQueryState 实例互不影响', 0, (): void => {
      const a: InlineQueryState = inlineControllerOn(new InlineFakeHost());
      const b: InlineQueryState = inlineControllerOn(new InlineFakeHost());

      a.inlineResults = [inlineRow('r1')];

      expect(b.inlineResults).assertDeepEquals([]);

      a.clear();
      expect(b.inlineResults).assertDeepEquals([]); // a.clear() 没有波及 b
    });

    // ========================================================================
    // StickerSuggestionState
    // ========================================================================

    // 防的回归：非纯 emoji 早退分支"已有建议才清"的判据被削弱成无条件清空，
    // 或者反过来漏清。
    it('refreshStickerSuggestions：非纯 emoji 草稿且已有建议时，清空 stickerSuggestions', 0, (): void => {
      const controller: StickerSuggestionState = stickerControllerOn(new StickerFakeHost());
      controller.stickerSuggestions = [stickerSuggestion(1)];

      controller.refreshStickerSuggestions('hello123');

      expect(controller.stickerSuggestions).assertDeepEquals([]);
    });

    it('refreshStickerSuggestions：非纯 emoji 草稿且本来就没有建议时，安全无操作', 0, (): void => {
      const controller: StickerSuggestionState = stickerControllerOn(new StickerFakeHost());

      controller.refreshStickerSuggestions('hello123');

      expect(controller.stickerSuggestions).assertDeepEquals([]);
    });

    // 见文件头：getStickersForEmoji 是 async function，同步抛错会被自动转成
    // reject，refreshStickerSuggestions 本身**不抛**、由 `.catch(()=>{})`
    // 悄悄吞掉——这与 mention/command/inline 三簇"同步抛错"不同，因此这里
    // 不需要 untilTdlibSend，但同样够不着 `.then()` 里真正的 items 构建 +
    // seq 比对（items 是否已加载出来，需要等一次真实的 TDLib 响应）。
    it('refreshStickerSuggestions：纯 emoji 草稿在本地环境下安全地静默失败（getStickersForEmoji reject 被 catch 吞掉，不抛错、不崩溃）', 0,
      async (): Promise<void> => {
        const controller: StickerSuggestionState = stickerControllerOn(new StickerFakeHost());

        controller.refreshStickerSuggestions('😀'); // 不 try/catch：这一行本身不该抛错

        await sleep(30); // 放行 getStickersForEmoji 内部那次 reject 的微任务
        expect(controller.stickerSuggestions).assertDeepEquals([]); // .then() 从未执行
      });

    // downloadSuggestionThumb 不经过定时器，直接方法调用。
    // 同上：原来只断言 stickerSuggestions 没变，删掉早退也照样绿。改断言"一个
    // 请求都没发"。
    it('downloadSuggestionThumb：thumbId===0 时提前返回，一个请求都不发', 0, (): void => {
      const host: StickerFakeHost = new StickerFakeHost();
      const controller: StickerSuggestionState = stickerControllerOn(host);
      controller.stickerSuggestions = [stickerSuggestion(1, 0)];

      controller.downloadSuggestionThumb(stickerSuggestion(1, 0), 1);

      expect(host.wired.bridge.sent.length).assertEqual(0); // 早退在发请求之前
      expect(controller.stickerSuggestions).assertDeepEquals([stickerSuggestion(1, 0)]);
    });

    it('downloadSuggestionThumb：thumbId!==0 时发出 downloadFile 请求', 0, (): void => {
      const host: StickerFakeHost = new StickerFakeHost();
      const controller: StickerSuggestionState = stickerControllerOn(host);

      controller.downloadSuggestionThumb(stickerSuggestion(1, 5), 1);

      expect(host.wired.bridge.sent.length).assertEqual(1);
      expect(host.wired.methodOf(0)).assertEqual('downloadFile');
    });

    it('StickerSuggestionState.clear()：清空 stickerSuggestions', 0, (): void => {
      const controller: StickerSuggestionState = stickerControllerOn(new StickerFakeHost());
      controller.stickerSuggestions = [stickerSuggestion(1)];

      controller.clear();

      expect(controller.stickerSuggestions).assertDeepEquals([]);
    });

    // clearAfterSend() 对外可观察的效果与 clear() 一致（stickerSuggestions
    // 清空）；两者唯一的差异是私有的 stickerSuggestSeq 是否 ++，那个字段没有
    // 读口子，本地测不到区别，如实记入 skippedAreas。
    it('StickerSuggestionState.clearAfterSend()：清空 stickerSuggestions（发送后的主动失效）', 0, (): void => {
      const controller: StickerSuggestionState = stickerControllerOn(new StickerFakeHost());
      controller.stickerSuggestions = [stickerSuggestion(1)];

      controller.clearAfterSend();

      expect(controller.stickerSuggestions).assertDeepEquals([]);
    });

    it('StickerSuggestionState.dispose() 是空实现，不清 stickerSuggestions', 0, (): void => {
      const controller: StickerSuggestionState = stickerControllerOn(new StickerFakeHost());
      controller.stickerSuggestions = [stickerSuggestion(1)];

      controller.dispose();

      expect(controller.stickerSuggestions).assertDeepEquals([stickerSuggestion(1)]);
    });

    it('两个 StickerSuggestionState 实例互不影响', 0, (): void => {
      const a: StickerSuggestionState = stickerControllerOn(new StickerFakeHost());
      const b: StickerSuggestionState = stickerControllerOn(new StickerFakeHost());

      a.stickerSuggestions = [stickerSuggestion(1)];

      expect(b.stickerSuggestions).assertDeepEquals([]);

      a.clear();
      expect(b.stickerSuggestions).assertDeepEquals([]); // a.clear() 没有波及 b
    });
  });
}
