import { describe, expect, it } from '@ohos/hypium';
import {
  SearchSession, SearchSessionHost
} from '../main/ets/pages/chat/SearchSession';
import { SEARCH_ENTRY_DELAY_MS } from '../main/ets/util/chatPageTuning';

// 会话内搜索（关键词 / 按发送者筛选 + 结果导航）的状态机，B6 把它从 ChatPage
// 整体搬进 pages/chat/SearchSession.ets 之后补的第一组断言。
//
// 【两条环境限制，读用例前先看——与 LiveTopCardController.test.ets 一致】
// 1. 本地测试跑不起 TDLib：Globals 里的 client 从没初始化过，getTdClient() 返回
//    的是 undefined，`searchChatMessages` 那一句会同步抛。凡是会走到 run() 内部
//    真正发请求那一步的用例都用 untilTdlibSend() 包一层——被断言的是"发请求
//    之前"那段同步字段变更，吞掉的是环境缺失而不是被测逻辑。
// 2. seq 是私有字段，测试读不到；响应回调本身也进不来（见第 1 条），所以
//    "exit()/updateQuery() 让上一次搜索的迟到响应被 seq 判成过期"这条没法直接
//    断言——不像 LiveTopCardController 那边还有 liveChatRefreshInFlight 这类
//    公开可观测的去重副作用可以顶替验证，run() 本身不设"在途"去重标志（同一个
//    controller 允许连续发多趟请求，靠 seq 挑最后一个），所以这里连替代验证都
//    没有。没有对应用例，不写摆设断言。
//
// 【entryTimer/dispose 一条的额外风险说明，读那条用例前先看】
// "dispose 在延迟期内清掉 entryTimer" 这条必须让 scheduleEntrySearch() 真的排下
// 一个 400ms 的 setTimeout，再验证 dispose() 之后它不再触发。当前实现下这条
// 100% 安全：dispose() 确实调用了 clearTimeout，回调永远不会被执行，下面的
// sleep() 只是空等。
// 但如果验收方按纪律"照着真的去改坏"——删掉 dispose() 里清 entryTimer 那几行
// 再跑一遍——回调就会在 sleep() 期间真的触发，调用 run(0,0)。query 在那一刻仍
// 非空、senderId 仍是 0，越不过 run() 内部的早退判据，于是会一路发到
// getTdClient().send()，在本地环境同步抛错。这次抛错发生在测试代码的调用栈之外
// （一个够不着、catch 不住的 setTimeout 回调里），untilTdlibSend 包不住它。
// 期望的结果是：host 的四个取值器在回调抛错前已经被调用过一轮，下面的
// `hostGetterCalls() === 0` 断言会先于抛错被观测到变化而判红；但如果测试运行时
// 对"定时器回调里的未捕获异常"处理得比较激进（终止整个测试进程），这条用例
// 暴露回归的方式会是让本文件的其余用例一起不正常结束，而不是一条干净的红。
// 这是当前这套本地单测环境下能做到的最接近"真实断言"的验证方式，残余风险照实
// 写在这里，不假装它不存在。

// 宿主（ChatPage）那一小片接口的替身：4 个取值器读下面的 …Value 字段并计数，
// 2 个动作回调只记账。控制器不许缓存宿主的值，所以改 …Value 就等于"页面那边
// 变了"；调用计数用来证明 run() 是否真的跑到了"读 host"这一步。
class FakeHost implements SearchSessionHost {
  chatIdValue: number = 0;
  threadRootIdValue: number = 0;
  forumTopicIdValue: number = 0;
  directMessagesTopicIdValue: number = 0;
  chatIdCalls: number = 0;
  threadRootIdCalls: number = 0;
  forumTopicIdCalls: number = 0;
  directMessagesTopicIdCalls: number = 0;
  jumpToMessageArgs: number[] = [];
  cancelFlashCount: number = 0;

  chatId: () => number = (): number => {
    this.chatIdCalls++;
    return this.chatIdValue;
  };
  threadRootId: () => number = (): number => {
    this.threadRootIdCalls++;
    return this.threadRootIdValue;
  };
  forumTopicId: () => number = (): number => {
    this.forumTopicIdCalls++;
    return this.forumTopicIdValue;
  };
  directMessagesTopicId: () => number = (): number => {
    this.directMessagesTopicIdCalls++;
    return this.directMessagesTopicIdValue;
  };
  jumpToMessage: (messageId: number) => void = (messageId: number): void => {
    this.jumpToMessageArgs.push(messageId);
  };
  cancelFlash: () => void = (): void => {
    this.cancelFlashCount++;
  };

  // 四个取值器一共被调了多少次——entryTimer 那条用例靠它证明"回调真的跑到了
  // run() 里读 host 那一步"，而不是干等一段时间就号称验证过了。
  hostGetterCalls(): number {
    return this.chatIdCalls + this.threadRootIdCalls +
      this.forumTopicIdCalls + this.directMessagesTopicIdCalls;
  }
}

function controllerOn(host: FakeHost): SearchSession {
  const controller: SearchSession = new SearchSession();
  controller.bind(host);
  return controller;
}

// 见文件头限制 1。若哪天 Globals 真被初始化了，send 是异步的，本函数照样什么都
// 不改——用例断言的都是同步段。
function untilTdlibSend(action: () => void): void {
  try {
    action();
  } catch (e) {
    // getTdClient() 未初始化，吞掉。
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, ms); });
}

export default function searchSessionTest() {
  describe('SearchSession', () => {

    // 防的回归：exit() 漏清某一个字段。senderId 尤其容易漏——B6 之前那句
    // "drops stale responses" 就错挂在它头上，容易让人以为它跟 seq 一样只是个
    // 内部记账、清不清都无所谓；漏清的真实后果是下一次普通关键词搜索会被悄悄
    // 限定在上一次筛过的那个人身上，用户完全看不出为什么搜不到。
    it('exit() 清空 results/total/idx/senderId/query 并把 mode 复位为 false', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: SearchSession = controllerOn(host);
      controller.mode = true;
      controller.query = 'opengram';
      controller.senderId = 9;
      controller.results = [3, 2, 1];
      controller.total = 5;
      controller.idx = 2;

      controller.exit();

      expect(controller.mode).assertFalse();
      expect(controller.query).assertEqual('');
      expect(controller.senderId).assertEqual(0);
      expect(controller.results.length).assertEqual(0);
      expect(controller.total).assertEqual(0);
      expect(controller.idx).assertEqual(0);
      // exit() 顺手取消跳转高亮闪烁——与 updateQuery() 共用同一个 host 回调。
      expect(host.cancelFlashCount).assertEqual(1);
      controller.dispose();
    });

    // 防的回归：updateQuery 换了关键词却没清旧的结果列表——用户敲下一个字，
    // 屏幕上短暂地用新关键词标题显示着上一个关键词的命中结果。
    it('updateQuery 换关键词时清空旧的结果列表', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: SearchSession = controllerOn(host);
      controller.query = 'old';
      controller.results = [1, 2, 3];
      controller.total = 3;
      controller.idx = 2;

      controller.updateQuery('new');

      expect(controller.query).assertEqual('new');
      expect(controller.results.length).assertEqual(0);
      expect(controller.total).assertEqual(0);
      expect(controller.idx).assertEqual(0);
      expect(host.cancelFlashCount).assertEqual(1);
      controller.dispose();
    });

    // 防的回归：删掉"值没变就提前返回"这道去重守卫——TextInput 的 onChange 在
    // 某些输入法组合下会用同一个字符串回调两次，没有这道守卫，第二次回调会
    // 平白无故地把已经到手的结果列表清空一遍。
    it('updateQuery 值未变时提前返回，不清结果、不取消闪烁', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: SearchSession = controllerOn(host);
      controller.query = 'same';
      controller.results = [9];
      controller.total = 1;
      controller.idx = 0;

      controller.updateQuery('same');

      expect(controller.query).assertEqual('same');
      // 没变化就是没变化：结果列表原样留着。
      expect(controller.results.length).assertEqual(1);
      expect(controller.total).assertEqual(1);
      expect(host.cancelFlashCount).assertEqual(0);
      controller.dispose();
    });

    // 防的回归：∧/∨ 的方向接反，或者越界之后还继续往前挪一格。结果按新→旧
    // 排，∧（older）下标 +1 走向更旧，∨（newer）下标 -1 走向更新，两端都要
    // 在越界时停住不动、也不发出多余的跳转。
    it('older()/newer() 按下标步进，越界时停住不动', 0, (): void => {
      const host: FakeHost = new FakeHost();
      const controller: SearchSession = controllerOn(host);
      controller.results = [500, 400, 300]; // newest → oldest
      controller.total = 3;
      controller.idx = 0;

      controller.older();
      expect(controller.idx).assertEqual(1);
      expect(host.jumpToMessageArgs[host.jumpToMessageArgs.length - 1]).assertEqual(400);

      controller.older();
      expect(controller.idx).assertEqual(2);
      expect(host.jumpToMessageArgs[host.jumpToMessageArgs.length - 1]).assertEqual(300);

      // 已经在最旧一条（下标 2，已加载 3 条等于总数 3，没有更多可翻）：
      // 再点 ∧ 必须原地不动，也不该再多发一次跳转。
      const callsBeforeOverrun: number = host.jumpToMessageArgs.length;
      controller.older();
      expect(controller.idx).assertEqual(2);
      expect(host.jumpToMessageArgs.length).assertEqual(callsBeforeOverrun);

      controller.newer();
      expect(controller.idx).assertEqual(1);
      expect(host.jumpToMessageArgs[host.jumpToMessageArgs.length - 1]).assertEqual(400);

      controller.newer();
      expect(controller.idx).assertEqual(0);
      expect(host.jumpToMessageArgs[host.jumpToMessageArgs.length - 1]).assertEqual(500);

      // 已经在最新一条（下标 0）：再点 ∨ 必须原地不动。
      const callsBeforeUnderrun: number = host.jumpToMessageArgs.length;
      controller.newer();
      expect(controller.idx).assertEqual(0);
      expect(host.jumpToMessageArgs.length).assertEqual(callsBeforeUnderrun);
      controller.dispose();
    });

    // 防的回归：enterForSender 把三个字段的写入顺序或内容搞错——尤其是忘记清
    // query（残留的关键词会把"查看历史"变成"查看历史里含这几个字的消息"）。
    it('enterForSender 设置 senderId + mode 并触发一次 run()', 0, (): void => {
      const host: FakeHost = new FakeHost();
      host.chatIdValue = 42;
      const controller: SearchSession = controllerOn(host);
      controller.query = '上一次搜的词';

      untilTdlibSend((): void => { controller.enterForSender(7); });

      expect(controller.senderId).assertEqual(7);
      expect(controller.query).assertEqual('');
      expect(controller.mode).assertTrue();
      // senderId > 0 越过了 run() 里"query 为空且未按发送者筛"的早退判据，
      // 一路读到了 host 的取值器（紧接着才会在 getTdClient() 那一行同步抛错，
      // 被 untilTdlibSend 吞掉）——这就是"触发了一次 run()"的证据。
      expect(host.chatIdCalls).assertEqual(1);
      controller.dispose();
    });

    // 防的回归：把 senderId<=0 的防御性早退删掉。「查看历史」的调用方本该只
    // 传合法的 sender id，但一旦这道短路被删，传 0/负数进来会强行把 mode 掀成
    // true、把用户正在打的关键词冲掉——静默地把普通搜索框变成一个空的
    // "查看历史"框。
    it('enterForSender(0 或负数) 什么都不做', 0, (): void => {
      const controller: SearchSession = controllerOn(new FakeHost());
      controller.query = '正在打的字';
      controller.mode = false;

      controller.enterForSender(0);
      expect(controller.senderId).assertEqual(0);
      expect(controller.query).assertEqual('正在打的字');
      expect(controller.mode).assertFalse();

      controller.enterForSender(-3);
      expect(controller.senderId).assertEqual(0);
      expect(controller.query).assertEqual('正在打的字');
      expect(controller.mode).assertFalse();
      controller.dispose();
    });

    // 防的回归：seedFromRoute 被"顺手"补一个 else 分支去复位 mode。这条既有
    // 语义（没有 else）是有意保留的——见 SearchSession.ets 顶部注释与本批
    // issues：今天只在"每次路由应用都是全新实例"的前提下安全，本类不擅自补
    // 这个分支，测试钉住"现在就是这样"，而不是"这样是完美的"。
    it('seedFromRoute 三条分支：query 优先，startSearch 只摆 mode，都没有则原样不动', 0, (): void => {
      const withQuery: SearchSession = controllerOn(new FakeHost());
      withQuery.seedFromRoute('opengram', false, 501);
      expect(withQuery.mode).assertTrue();
      expect(withQuery.query).assertEqual('opengram');

      const startOnly: SearchSession = controllerOn(new FakeHost());
      startOnly.query = '上一轮剩下的';
      startOnly.seedFromRoute('', true, 0);
      expect(startOnly.mode).assertTrue();
      // startSearch 分支只摆 mode，不碰 query —— 对应"从个人资料页的搜索按钮
      // 进来，带一个空的、已聚焦的搜索框"这个原始语义。
      expect(startOnly.query).assertEqual('上一轮剩下的');

      const neither: SearchSession = controllerOn(new FakeHost());
      neither.mode = true; // 模拟上一次路由应用遗留下来的 mode
      neither.seedFromRoute('', false, 0);
      // 没有 else 分支：这一支什么都不做，mode 原样保留，不会被复位成 false。
      expect(neither.mode).assertTrue();

      withQuery.dispose();
      startOnly.dispose();
      neither.dispose();
    });

    // 防的回归：dispose() 漏清 entryTimer。这是 B6 相对搬迁前新加的一处行为
    // 加固——搬之前这个 setTimeout 是裸的，页面在 400ms 延迟期内退出（或
    // NavDestination 复用场景下换到了另一个会话）时回调仍会摸上状态、发出一趟
    // 不该发的请求。残余风险见文件头说明。
    it('dispose 在延迟期内清掉 entryTimer，进入即搜索的回调不再触发', 0,
      async (): Promise<void> => {
        const host: FakeHost = new FakeHost();
        host.chatIdValue = 42;
        const controller: SearchSession = controllerOn(host);
        controller.mode = true;
        controller.query = '进入即搜索';

        controller.scheduleEntrySearch(); // 排下 SEARCH_ENTRY_DELAY_MS 后的回调
        controller.dispose(); // 延迟期内销毁：entryTimer 应该被清掉

        await sleep(SEARCH_ENTRY_DELAY_MS + 260);

        // dispose 工作正常：entryTimer 从未触发，run() 从未被调用，host 的四个
        // 取值器一次都没被摸到。若 dispose() 漏清了 entryTimer，回调会在这段
        // sleep 期间真的执行，越过 run() 的早退判据（query 仍非空）一路读到
        // host——这个计数会从 0 变成 4。
        expect(host.hostGetterCalls()).assertEqual(0);
        expect(controller.query).assertEqual('进入即搜索');
      });

    // 防的回归：有人把控制器做成模块级单例，或者 dispose 波及了别的实例。
    // 平板分栏、导航栈多层时同时活着多个 ChatPage，各自的搜索关键词、结果列表
    // 不该串到一起。
    it('两个实例互不影响（防的回归：做成模块级单例，分栏两页共用一份搜索状态）', 0, (): void => {
      const a: SearchSession = controllerOn(new FakeHost());
      const b: SearchSession = controllerOn(new FakeHost());

      a.mode = true;
      a.query = '会话 A 在搜的词';
      a.results = [1, 2];
      a.senderId = 5;

      expect(b.mode).assertFalse();
      expect(b.query).assertEqual('');
      expect(b.results.length).assertEqual(0);
      expect(b.senderId).assertEqual(0);

      // 一页销毁不能把另一页的状态一起清掉。
      b.mode = true;
      b.query = '会话 B 在搜的词';
      a.exit();
      expect(b.mode).assertTrue();
      expect(b.query).assertEqual('会话 B 在搜的词');
      expect(a.mode).assertFalse();
      b.dispose();
    });
  });
}
