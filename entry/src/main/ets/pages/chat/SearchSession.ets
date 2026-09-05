// 会话内搜索（关键词 / 按发送者筛选 + 结果导航）的状态机。
// 从 ChatPage 整体搬出（B6 批）。
//
// 【为什么要搬】
// 敲一个字就要写 query/results/total/idx 四个字段（mode/senderId 相对少动），
// 搬之前它们全是 ChatPage 的 @Local，于是每次键入都要重跑一遍页面的
// chatTitleBar 闭包——键入越快，页面重算越密。搬进 @ObservedV2 之后，
// SearchHeader/SearchBottomBar 直接持有本控制器的引用、在自己的 build() 里读
// @Trace，敲一个字只刷新读到它的那个 TextInput/计数文案节点，ChatPage 一个字
// 都不读。
//
// 只把字段搬走、读点留在页面，收益就只有行数——所以 SearchHeader/
// SearchBottomBar 必须改成直读本对象，这是 B6 唯一真正缩小重渲染半径的地方。
//
// 【为什么仍有几个字段收窄不了】
// mode 仍被 bottomDock/chatTitleBar/chromeGeometryInput/ScrollFab 显隐/
// handleBackPressed 五处直接读——它们是页面级 build 的判定，几何链
// （headerChromeHeight/topBannerHeight）和返回键的"selecting > searchMode"
// 优先级链都贯穿整页。页面读它时走 this.search.mode，依赖粒度仍是该字段本身，
// 与搬之前一一对应。
//
// 【B6 更正】searchSenderId 字段上原来挂着一句"drops stale responses"，那是
// 张冠李戴——真正起丢弃迟到响应作用的是 seq（run() 里的
// `if (seq !== this.seq) return`），跟按发送者筛选是两回事。这句注释已挪到
// seq 字段上，senderId 上不再有它。
//
// 【B6 有意加固】进入即搜索的那个 setTimeout(SEARCH_ENTRY_DELAY_MS) 搬之前是
// 裸的，没有存句柄：页面若在这 400ms 延迟内退出（NavDestination 复用场景下
// 甚至可能是同一个 struct 实例又换了一个会话），回调仍会摸上 this.mode、进而
// 对一个已经不该再动的状态发出一趟不该发的 TDLib 请求。搬进控制器后给它一个
// entryTimer 句柄，dispose() 里 clear 掉。这一步**改变了行为**（改前会调、
// 改后不调）——是修复，不是纯搬迁，需要写进本批验证手册的"行为变更"一节。
//
// 【为什么是 per-ChatPage 实例，不是模块级单例】
// 平板分栏、导航栈多层时同时活着多个 ChatPage，每个都有自己的搜索关键词、
// 自己的结果列表、自己的请求 seq。做成单例会让一个会话敲的字冒到另一个会话的
// 搜索框里。页面用字段初始化器 new 一个：首帧前就已存在、引用全生命周期稳定、
// 类型非空。
//
// 【为什么 dispose() 里先 ++seq 再清定时器】
// seq 是 run() 那趟 searchChatMessages 请求的在途守卫：响应回来时先比
// `seq !== this.seq`，对不上（或 mode 已经是 false）就整个丢掉。先 ++seq 再
// clearTimeout，是为了让「已经发出、还没回来」的那趟请求在 then() 里被判成
// 过期，而不是回来往一个已经 dispose 的对象上写字段。这与 LiveTopCardController
// 的 dispose 顺序一致，也是本仓所有 @ObservedV2 控制器的通用约定。
//
// 【不在本类里声明 @Monitor】
// 官方规则：类中 @Monitor 的解注册依赖 GC，销毁时机不可靠。本簇的所有联动都用
// 显式方法调用表达。

import { promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { applyMessageTopicScope } from '../../util/messageTopicScope';
import {
  AnchorMerge, SEARCH_FETCH, SEARCH_JUMP, SearchStep, mergeAnchorHit, stepNewer, stepOlder
} from '../../util/searchPaging';
import { SEARCH_ENTRY_DELAY_MS } from '../../util/chatPageTuning';
import { logE } from '../../util/log';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读页面
// 当下的真值，动作回调把副作用交回页面执行。仿 LiveTopCardController 的
// LiveTopCardHost / util/chatPageLifecycle.ets 的 ChatPageHiddenHooks。
//
// 两条纪律：
// 1. 这里只放**取值器**，不放页面的 @Local 引用。控制器不缓存页面的值，每次
//    要用就现取——否则页面改了字段、控制器手里还是旧的。
// 2. 命中之后要做的"跳过去"这件事（压回返回栈、滚动、两拍高亮闪烁）本身留在
//    页面的 onReplyTap 里，控制器只负责把选中的消息 id 交回去，不复刻那套逻辑。
export interface SearchSessionHost {
  // 当前会话 id。
  chatId: () => number;
  threadRootId: () => number;
  forumTopicId: () => number;
  directMessagesTopicId: () => number;
  // 命中一条结果（或翻页跳到已加载的一条）时，交给页面去跳——页面侧是
  // this.onReplyTap(messageId)，与点引用块/点置顶条同一条路径（压回返回栈、
  // scroller.scrollToIndex、flashAtIndex 两拍高亮）。
  jumpToMessage: (messageId: number) => void;
  // 退出搜索/换关键词时顺手取消进行中的跳转高亮闪烁——这不是搜索簇自己的
  // 状态（属于 flash 高亮簇，B13 才搬），只是 exit()/updateQuery() 两个写口子
  // 搬之前就恰好也碰它，原样保留成 host 回调。
  cancelFlash: () => void;
}

@ObservedV2
export class SearchSession {
  // ——— 显示态：SearchHeader / SearchBottomBar 直接读这些 @Trace ———

  @Trace mode: boolean = false;
  @Trace query: string = '';
  @Trace results: number[] = []; // message ids, newest → oldest；整体替换，不原地 push
  @Trace total: number = 0;
  @Trace idx: number = 0; // 0-based index into results
  // 「查看历史」筛的那个发送者；0 = 不按发送者筛（普通关键词搜索）。
  // 按发送者筛时 query 允许为空——TDLib 支持"空 query + sender_id"列出此人
  // 全部消息。
  @Trace senderId: number = 0;

  // ——— 内部机件：一律**不加 @Trace** ———
  // 定时器句柄与序号守卫都不驱动任何 UI，加了 @Trace 只会在每次自增/清句柄时
  // 白发一轮通知。

  // 从全局搜索进入本会话时带的那条"锚点命中"消息 id；0 = 没有。一次性：被
  // run() 的第一趟成功响应消费掉之后立刻清零，此后 older()/newer()/onSubmit
  // 一律走普通的 jumpToResult 路径，不再看它。
  private anchorId: number = 0;
  // run() 那趟 searchChatMessages 请求的在途守卫，同时也是 exit()/
  // updateQuery() 的会话失效计数器。
  // 【B6 更正】这句"drops stale responses"原来错挂在 senderId 上——真正做这
  // 件事的是这个字段：响应回来时比 `seq !== this.seq`，对不上就整个丢掉；
  // exit()/updateQuery() 各自 seq++ 就能让上一次输入/上一次搜索会话的响应
  // 作废，不需要它们各自去记"自己发过什么"。
  private seq: number = 0;
  // 进入即搜索的那次 setTimeout(SEARCH_ENTRY_DELAY_MS) 的句柄。
  // 【B6 加固】搬之前是裸 setTimeout，没有句柄可清；dispose() 现在会 clear
  // 它，防止延迟期内页面已经退出、回调却仍摸上状态发出一趟不该发的请求。
  private entryTimer: number = -1;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的
  // 值，与页面同名字段的初值一致。
  private host: SearchSessionHost = {
    chatId: (): number => 0,
    threadRootId: (): number => 0,
    forumTopicId: (): number => 0,
    directMessagesTopicId: (): number => 0,
    jumpToMessage: (_messageId: number): void => {},
    cancelFlash: (): void => {}
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: SearchSessionHost): void {
    this.host = host;
  }

  // ——— 会话生命周期 ———

  // 搬之前是 ChatPage.enterSearch()。头部 ⋮ 菜单的"搜索"项调用（页面侧改调
  // this.search.enter()）。
  enter(): void {
    this.mode = true;
    this.query = '';
    this.results = [];
    this.total = 0;
    this.idx = 0;
  }

  // 搬之前是 ChatPage.exitSearch()。调用方：handleBackPressed（返回键，
  // selecting 之后第二优先）、SearchHeader.onExit——都在簇外，页面侧改调
  // this.search.exit()。
  exit(): void {
    this.mode = false;
    this.query = '';
    // 发送者过滤必须跟着一起清：留着的话下一次普通关键词搜索会被悄悄限定在
    // 那个人身上，用户完全看不出为什么搜不到。
    this.senderId = 0;
    this.results = [];
    this.total = 0;
    this.idx = 0;
    this.seq++;
    this.host.cancelFlash();
  }

  // 搬之前是 ChatPage.updateSearchQuery()。SearchHeader.onQueryChange 调用。
  updateQuery(value: string): void {
    if (value === this.query) {
      return;
    }
    this.query = value;
    this.results = [];
    this.total = 0;
    this.idx = 0;
    this.seq++;
    this.host.cancelFlash();
  }

  // Run a search page. fromMsgId 0 = fresh search; otherwise fetch the page
  // older than that message (pagination for the ∧ button past the first 50).
  // 搬之前是 ChatPage.runSearch()。调用方：scheduleEntrySearch()（本类）、
  // enterForSender()（本类）、applySearchStep()（本类）、
  // SearchHeader.onSubmit（簇外，直接调 run(0,0)，跳过 updateQuery() 那次
  // 提前清空——无害，因为 fromMsgId===0 本来就会整体替换 results）。
  run(fromMsgId: number, thenJumpTo: number): void {
    const q = this.query.trim();
    // 关键词为空时通常没什么可搜的，但**按发送者筛是例外**：空 query +
    // sender_id 正是 TDLib 列出"此人在本会话的全部消息"的用法（「查看历史」
    // 走这条）。
    if (q === '' && this.senderId === 0) {
      return;
    }
    const seq = ++this.seq;
    const req: TdRequest = { '@type': 'searchChatMessages' };
    req['chat_id'] = this.host.chatId();
    req['query'] = q;
    applyMessageTopicScope(
      req, this.host.threadRootId(), this.host.forumTopicId(), this.host.directMessagesTopicId());
    if (this.senderId > 0) {
      const sender: TdObject = { '@type': 'messageSenderUser' };
      sender['user_id'] = this.senderId;
      req['sender_id'] = sender;
    }
    req['from_message_id'] = fromMsgId;
    req['offset'] = 0;
    req['limit'] = 50;
    getTdClient().send(req).then((res: TdObject): void => {
      if (seq !== this.seq || !this.mode) {
        return;
      }
      const msgs = (res['messages'] as TdObject[] | undefined) ?? [];
      const ids: number[] = [];
      for (const m of msgs) {
        const id = (m['id'] as number | undefined) ?? 0;
        if (id > 0) {
          ids.push(id);
        }
      }
      this.total = (res['total_count'] as number | undefined) ?? ids.length;
      this.results = fromMsgId === 0 ? ids : [...this.results, ...ids];
      if (this.results.length === 0) {
        promptAction.showToast({ message: $r('app.string.cp_no_messages_found'), duration: 1500 });
        return;
      }
      // 从全局搜索点某条消息进来：那一条就是跳转目标，已经落到位了，这次
      // 搜索只是为了把 ∧/∨ 的列表填上——**任何情况下都不再跳**。
      //
      // 原来是 indexOf 找不到锚点就 jumpToResult(0)。两边匹配口径不同时这就
      // 会把用户刚落对的位置甩开（issue #80：全局搜索命中「opengram，还有
      // 最近那个」，会话内搜索用同一串词只回了另一条含 "opengram" 的消息，
      // 页面于是自己滑走）。锚点是用户的选择，按 id 序插进结果里，不推翻它。
      if (this.anchorId !== 0) {
        const merged: AnchorMerge = mergeAnchorHit(this.results, this.anchorId);
        this.anchorId = 0;
        this.results = merged.results;
        this.idx = merged.index;
        if (merged.inserted) {
          this.total = this.total + 1;
        }
        return;
      }
      this.jumpToResult(thenJumpTo);
    }).catch((e: TdError): void => {
      logE(`SearchSession.run searchChatMessages failed: ${e.message}`);
    });
  }

  // 搬之前是 ChatPage.jumpToResult()。只在本类内部调用（run() 的成功路径、
  // applySearchStep() 的 SEARCH_JUMP 分支），不对外暴露。
  private jumpToResult(idx: number): void {
    if (idx < 0 || idx >= this.results.length) {
      return;
    }
    this.idx = idx;
    this.host.jumpToMessage(this.results[idx]); // same jump + double-blink flash
  }

  // ∧ / ∨ 的决策交给纯函数（util/searchPaging，有单测）：下标越界、总数为
  // 0、已加载等于总数、空结果集——这几个边界混在异步回调之间最容易写错。
  // 搬之前是 ChatPage.applySearchStep()。
  private applySearchStep(step: SearchStep): void {
    if (step.action === SEARCH_JUMP) {
      this.jumpToResult(step.index);
    } else if (step.action === SEARCH_FETCH) {
      this.run(step.fromMessageId, step.index);
    }
  }

  // 搬之前是 ChatPage.searchOlder()。SearchBottomBar.onOlder 调用。
  older(): void {
    this.applySearchStep(stepOlder(this.results, this.idx, this.total));
  }

  // 搬之前是 ChatPage.searchNewer()。SearchBottomBar.onNewer 调用。
  newer(): void {
    this.applySearchStep(stepNewer(this.idx));
  }

  // 「查看历史」：在本会话里筛出这个人的全部消息。复用会话内搜索的整套界面
  // （结果计数、上/下一条、跳转高亮），只是把 sender_id 填上、query 留空——
  // TDLib 支持这种组合。搬之前是 ChatPage.viewSenderHistory() 的方法体（页面
  // 侧原来是"摆好三字段再调 runSearch"，现在收成一个入口）。
  enterForSender(senderId: number): void {
    if (senderId <= 0) {
      return;
    }
    this.senderId = senderId;
    this.query = '';
    this.mode = true;
    this.run(0, 0);
  }

  // 路由参数就绪后的初值。搬之前是 resolveRouteAndResetSession() 里的三行
  // 直接字段赋值（route.searchQuery !== '' 分支 / route.startSearch 分支），
  // 判据顺序原样保留，**包括"没有 else 分支复位 mode=false"这条既有语义**：
  // 今天这只在"每次路由应用都是一个全新 ChatPage 实例"（clearAndPush）的前提
  // 下安全——见本批 issues 里记的那条风险，本类不擅自补一个 else 分支。
  seedFromRoute(query: string, startSearch: boolean, anchorId: number): void {
    if (query !== '') {
      this.mode = true;
      this.query = query;
      this.anchorId = anchorId;
    } else if (startSearch) {
      // Profile-page 搜索 button: open the chat with an empty, focused search.
      this.mode = true;
    }
  }

  // Let the initial history land first — run() jumps to the newest hit, and
  // that jump would otherwise be undone by the initial scroll-to-bottom.
  // 搬之前是 ChatPage.scheduleEntrySearchIfNeeded()，applyRouteParams 阶段 A
  // 收尾时调用一次。
  scheduleEntrySearch(): void {
    if (this.mode && this.query !== '') {
      this.entryTimer = setTimeout((): void => {
        this.entryTimer = -1;
        if (this.mode) {
          this.run(0, 0);
        }
      }, SEARCH_ENTRY_DELAY_MS);
    }
  }

  // ChatPage.aboutToDisappear 调用，放在原来清 search* 字段的位置。
  // 先 ++seq 再清定时器：让已经发出的 run() 请求在响应里被判成过期，而不是
  // 清完定时器之后那一小段窗口里被漏进来——与本仓所有 @ObservedV2 控制器的
  // dispose 顺序约定一致。
  dispose(): void {
    this.seq++;
    if (this.entryTimer !== -1) {
      clearTimeout(this.entryTimer);
      this.entryTimer = -1;
    }
  }
}
