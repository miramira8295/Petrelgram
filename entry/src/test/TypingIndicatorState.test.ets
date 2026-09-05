import { beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  TypingIndicatorState, TypingIndicatorHost
} from '../main/ets/pages/chat/TypingIndicatorState';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { resetStrings } from '../main/ets/util/strings';
import { TYPING_ACTION_TTL_MS } from '../main/ets/util/typingIndicator';

// 对方"正在输入…"提示的状态机，B10 把它从 ChatPage 整体搬进
// pages/chat/TypingIndicatorState.ets 之后补的第一组断言。写法照抄
// HeaderIdentitySession.test.ets / SearchSession.test.ets（FakeHost、
// untilXxx 吞异常的包装函数、文件头先说环境限制）。
//
// 【两条环境限制，读用例前先看】
//
// 1. 本地测试跑不起全局 UserStore 单例：Globals 里的 users 从没初始化过，
//    getUserStore() 返回的是 undefined（`users!` 只是编译期断言，运行时值仍是
//    undefined），任何一次 `.ensure(...)`/`.displayName(...)` 调用都会在那一行
//    同步抛出 TypeError。onChatAction 对**非取消**动作（typing/uploading/…）
//    在 `senders.has(uid)` 命中时无条件调用 `getUserStore().ensure(uid)`——这一句
//    排在 rebuildTypingLabel() **之前**，所以本地环境下任何一次"记下一条新的
//    正在输入"都会在写完 senders 表之后、重建文案之前同步抛错。凡是要往 senders
//    里塞数据但不关心这次调用本身重建没重建文案的用例，都用 untilUnavailableGlobal()
//    包一层——被断言的是 applyTypingUpdate 已经把 senders 表改好这件事（抛错发生
//    在纯函数返回之后），吞掉的是环境缺失，不是被测逻辑。
//
// 2. 因为上一条，本地环境下**唯一**能安全跑到 rebuildTypingLabel() 的入口是
//    "对一个当前不在 senders 表里的 uid 发 chatActionCancel"——它落进
//    applyTypingUpdate 的 cancel 分支，delete 一个不存在的 key 是无操作，返回的
//    uid 因为从未被 set 过所以 `senders.has(uid)` 恒为 false，从而跳过那句会抛错
//    的 ensure()，一路跑到 rebuildTypingLabel()。下面的用例管这个叫"cancel 触发
//    器"：拿一个从没出现过的 uid（比如 999901）发 cancel，只为了让重建文案这一步
//    跑起来，不代表真实产品里会发生这种 cancel。
//    这条限制还带来一个副作用：group/channel 档且 senders 里恰好剩 1 个人时，
//    typingLabelOf 会去问 `displayName(ids[0])`，那同样是 getUserStore()，同样会
//    抛错——所以下面凡是要在非 private/secret 档上重建文案的用例，都保证 senders
//    里同时有 **2 个**人（走 plural 分支，不碰 displayName）。
//
// 【6000ms 到期与轮询的用例为什么真的 sleep】
// TYPING_ACTION_TTL_MS/setInterval 轮询间隔都钉在 Date.now() 上，这套本地
// harness 没有可替换的时钟（senders 表与 timer 都是控制器私有字段，不为测试
// 开后门），唯一能验证到期行为的办法是真的等——TTL(6000) + 一个轮询周期(1500)
// + 400ms 缓冲 = 7900ms 一轮。这让下面三条用例各跑 7~8 秒，比其余用例慢得多，
// 但没有更便宜的验证方式。
//
// 【"timer 复位"为什么被拆成前后相邻的两条用例】
// 要钉住"轮询把 senders 裁空后 this.timer 真的复位回 -1"，只等一轮到期是不够
// 的：label 清空这件事跟复位与否无关。必须在同一个实例上再喂一批输入、看第二轮
// 到期是否也能自动清空——没复位的话 `this.timer === -1 && senders.size > 0`
// 恒为假，第二轮永远排不上轮询。两轮加起来 15.8s，超过 hypium 每条用例
// 15000ms 的硬上限（service.js getFuncWithArgsZero 里 config.timeout，本地
// harness 注入 15000，没有对外的调节口），所以拆成 TestC1/TestC2 两条，共用
// 下面这个 describe 作用域里的实例。hypium 按声明顺序串行跑 describe 里的 it，
// **两条的先后不能调换、中间不能插入新用例**：TestC2 依赖 TestC1 留下的
// "轮询刚刚自行停过一次"这个状态，单独跑 TestC2 是钉不住复位的。

// 一条 updateChatAction。sender 默认是用户，action 由参数给——与
// TypingIndicator.test.ets 里的同名 helper 逐字一致（每个测试文件各自维护一份，
// 与 HeaderIdentitySession.test.ets 的 cachedPrivateEntry() 是同一惯例）。
function chatAction(chatId: number, uid: number, actionType: string): TdObject {
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = uid;
  const action: TdObject = { '@type': actionType };
  const update: TdObject = { '@type': 'updateChatAction' };
  update['chat_id'] = chatId;
  update['sender_id'] = sender;
  update['action'] = action;
  return update;
}

// 宿主（ChatPage）那一小片接口的替身：4 个会话/话题作用域取值器 + currentKind，
// 全部读下面的 …Value 字段。控制器不许缓存宿主的值，所以改 …Value 就等于"页面
// 那边的现值变了"，下一次调用就该看到新值——TestD 就是在钉这一点。
class FakeHost implements TypingIndicatorHost {
  chatIdValue: number = 0;
  threadRootIdValue: number = 0;
  forumTopicIdValue: number = 0;
  directMessagesTopicIdValue: number = 0;
  currentKindValue: string = '';

  chatId: () => number = (): number => this.chatIdValue;
  threadRootId: () => number = (): number => this.threadRootIdValue;
  forumTopicId: () => number = (): number => this.forumTopicIdValue;
  directMessagesTopicId: () => number = (): number => this.directMessagesTopicIdValue;
  currentKind: () => string = (): string => this.currentKindValue;
}

function controllerOn(host: FakeHost): TypingIndicatorState {
  const controller: TypingIndicatorState = new TypingIndicatorState();
  controller.bind(host);
  return controller;
}

// 见文件头限制 1。本地环境下 getUserStore() 是未初始化的模块单例，摸到它就会
// 同步抛出 TypeError——这个函数把"环境缺失导致的抛错"和"被测逻辑本身的错误"
// 分开，只吞前者。
function untilUnavailableGlobal(action: () => void): void {
  try {
    action();
  } catch (e) {
    // getUserStore() 未初始化，吞掉。
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

export default function typingIndicatorStateTest() {
  describe('TypingIndicatorState', () => {
    beforeEach((): void => { resetStrings(); });

    // 防的回归：rebuildTypingLabel 没有真的把 typingLabelOf 的结果写进 label，
    // 或者 onChatAction 里两条 typing 动作没能各自落进 senders 表。
    // 两次 typing 用 untilUnavailableGlobal 包住（见文件头限制 1），第三条
    // 对陌生 uid 的 cancel 是"cancel 触发器"（见文件头限制 2），不包裹——如果
    // 它自己也抛了，说明重建路径本身出了问题，测试要如实红。
    it('两人同时输入 → label 走复数文案', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 7;
      host.currentKindValue = 'group';
      const controller: TypingIndicatorState = controllerOn(host);

      untilUnavailableGlobal((): void => {
        controller.onChatAction(chatAction(7, 1, 'chatActionTyping'));
      });
      untilUnavailableGlobal((): void => {
        controller.onChatAction(chatAction(7, 2, 'chatActionTyping'));
      });
      // 阳性对照：两次 typing 因为 ensure() 抛错，都没跑到 rebuildTypingLabel，
      // label 这时候应该还是初始的空串。
      expect(controller.label).assertEqual('');

      controller.onChatAction(chatAction(7, 999901, 'chatActionCancel'));
      expect(controller.label).assertEqual('cp_n_typing(2,2)');
      controller.dispose();
    });

    // 防的回归：rebuildTypingLabel 把 host.currentKind() 的结果缓存了下来（或者
    // 用 isGroup 之类的字段猜），而不是每次现取——B8 迁移时在 HeaderIdentitySession
    // 里踩过同一个坑（isGroup ? 'group' : 'private' 在身份解析前把默认档翻错），
    // TypingIndicatorState 文件头明确写了"不得重犯"。同一批 senders（2 人）不变，
    // 只把 host 的档位从 private 换成 group，文案必须跟着换档，换不了就是把
    // currentKind() 缓存住了。
    it('rebuildTypingLabel 的 kind 现取自 host.currentKind()，不缓存', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 7;
      host.currentKindValue = 'private';
      const controller: TypingIndicatorState = controllerOn(host);

      untilUnavailableGlobal((): void => {
        controller.onChatAction(chatAction(7, 1, 'chatActionTyping'));
      });
      untilUnavailableGlobal((): void => {
        controller.onChatAction(chatAction(7, 2, 'chatActionTyping'));
      });
      controller.onChatAction(chatAction(7, 999904, 'chatActionCancel'));
      // private 档：不管 senders 里有几个人，只说"正在输入…"。
      expect(controller.label).assertEqual('cp_typing');

      host.currentKindValue = 'group';
      controller.onChatAction(chatAction(7, 999905, 'chatActionCancel'));
      expect(controller.label).assertEqual('cp_n_typing(2,2)');
      controller.dispose();
    });

    // TestC1/TestC2 共用的那一个实例。声明在 describe 作用域里，因为
    // "timer 复位"这条断言必须跨两轮、跨两条用例（拆分理由见文件头）。
    const twoRoundHost: FakeHost = new FakeHost();
    twoRoundHost.chatIdValue = 7;
    twoRoundHost.currentKindValue = 'group';
    const twoRound: TypingIndicatorState = controllerOn(twoRoundHost);

    // TestC1（防的回归：6000ms 到期后 senders 没被裁空 / label 没清）。
    // 它同时是 TestC2 的前置：跑完这一条，twoRound 里的轮询已经自行停过一次。
    it('第一轮：6000ms 到期后 label 清空', 0,
      async (): Promise<void> => {
        // 两个人在输入，cancel 触发器重建文案的同时排下 1500ms 轮询。
        untilUnavailableGlobal((): void => {
          twoRound.onChatAction(chatAction(7, 1, 'chatActionTyping'));
        });
        untilUnavailableGlobal((): void => {
          twoRound.onChatAction(chatAction(7, 2, 'chatActionTyping'));
        });
        twoRound.onChatAction(chatAction(7, 999906, 'chatActionCancel'));
        expect(twoRound.label).assertEqual('cp_n_typing(2,2)'); // 阳性对照

        await sleep(TYPING_ACTION_TTL_MS + 1500 + 400);
        expect(twoRound.label).assertEqual('');
      });

    // TestC2（防的回归：轮询回调清完 senders 之后没把 this.timer 复位成 -1）。
    // **必须紧跟 TestC1**：用的是同一个已经跑完一轮的实例。如果没复位，下面这次
    // cancel 触发器里的 `this.timer === -1 && senders.size > 0` 判据恒为假，
    // 永远不会排下新一轮轮询——第二批发送方一直挂着，等不到自己的 6s 到期，
    // 最后一条断言就会红。
    it('第二轮：timer 已复位，同一实例能再开一轮轮询并再次到期清空', 0,
      async (): Promise<void> => {
        expect(twoRound.label).assertEqual(''); // 前置校验：TestC1 确实跑过且清空了

        untilUnavailableGlobal((): void => {
          twoRound.onChatAction(chatAction(7, 3, 'chatActionTyping'));
        });
        untilUnavailableGlobal((): void => {
          twoRound.onChatAction(chatAction(7, 4, 'chatActionTyping'));
        });
        twoRound.onChatAction(chatAction(7, 999907, 'chatActionCancel'));
        expect(twoRound.label).assertEqual('cp_n_typing(2,2)'); // 阳性对照：第二轮也亮起过

        await sleep(TYPING_ACTION_TTL_MS + 1500 + 400);
        expect(twoRound.label).assertEqual(''); // 只有 timer 真的复位过才能等到这一步
        twoRound.dispose();
      });

    // 防的回归：dispose() 漏清轮询定时器。页面销毁后如果这个 1500ms 轮询还活着，
    // 到期回调会继续往一个已经离场的 ChatPage 的 @Trace 上写 label——真机表现是
    // "刚退出这个会话页，输入提示还在背后悄悄清空"。
    it('dispose() 之后到期回调不再改 label（防的回归：轮询定时器漏清）', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.chatIdValue = 7;
        host.currentKindValue = 'group';
        const controller: TypingIndicatorState = controllerOn(host);

        untilUnavailableGlobal((): void => {
          controller.onChatAction(chatAction(7, 1, 'chatActionTyping'));
        });
        untilUnavailableGlobal((): void => {
          controller.onChatAction(chatAction(7, 2, 'chatActionTyping'));
        });
        controller.onChatAction(chatAction(7, 999908, 'chatActionCancel'));
        expect(controller.label).assertEqual('cp_n_typing(2,2)'); // 阳性对照：轮询确实排下了

        controller.dispose();
        // 哨兵：到期回调若还活着，会在下面这段等待期间把 senders 裁空后把
        // label 写回 ''，从而覆盖掉这个哨兵值。
        controller.label = '哨兵';
        await sleep(TYPING_ACTION_TTL_MS + 1500 + 400);
        expect(controller.label).assertEqual('哨兵');
      });

    // 防的回归：把这簇状态做成模块级单例，或者一个实例的 dispose 波及了另一个。
    // 平板分栏、导航栈多层时同时活着多个 ChatPage，各自会话的输入提示互不相干。
    it('两个实例互不影响（防的回归：typing 状态被拼成模块级单例）', 0, (): void => {
      const hostA: FakeHost = new FakeHost();
      hostA.chatIdValue = 7;
      hostA.currentKindValue = 'group';
      const hostB: FakeHost = new FakeHost();
      hostB.chatIdValue = 8;
      hostB.currentKindValue = 'private';
      const a: TypingIndicatorState = controllerOn(hostA);
      const b: TypingIndicatorState = controllerOn(hostB);

      untilUnavailableGlobal((): void => { a.onChatAction(chatAction(7, 11, 'chatActionTyping')); });
      untilUnavailableGlobal((): void => { a.onChatAction(chatAction(7, 12, 'chatActionTyping')); });
      a.onChatAction(chatAction(7, 999909, 'chatActionCancel'));
      expect(a.label).assertEqual('cp_n_typing(2,2)');
      expect(b.label).assertEqual(''); // b 完全没被 a 的输入影响

      untilUnavailableGlobal((): void => { b.onChatAction(chatAction(8, 21, 'chatActionTyping')); });
      b.onChatAction(chatAction(8, 999910, 'chatActionCancel'));
      expect(b.label).assertEqual('cp_typing'); // private 档，且只受自己那条 chatId=8 的影响
      expect(a.label).assertEqual('cp_n_typing(2,2)'); // a 没被 b 的写入连累

      a.dispose();
      expect(b.label).assertEqual('cp_typing'); // 一个实例 dispose 不清另一个的状态
      b.dispose();
    });
  });
}
