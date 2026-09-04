// 进会话首屏的**预取**：在页面还没建之前就把第一页历史要出来。
//
// 【为什么值得做】09-04 真机实测（[OpenDiag] 探针），点开一个会话：
//   +12ms  页面就绪
//   +53ms  才发出历史请求 —— 中间在等 getChat 那一程往返
//   +66ms  TDLib 交回数据（**它自己只用了 13ms**）
//   +778ms UI 才拿到 —— 被 INITIAL_MESSAGE_TRANSITION_SETTLE_MS 的围栏压着
// 慢的从来不是取数，是取数**开始得太晚**：页面建好 → 问 getChat → 才敢决定
// 首屏要哪一页。而这三个决策输入（未读数、已读水位、最后一条）**会话列表
// 手上早就有**（ChatEntry.unreadCount / lastReadInboxId / lastMessageId）。
//
// 于是把请求提到点击那一刻发，页面建好时结果已经在手里 —— 页面是"带着内容"
// 滑进来的，不需要那道围栏，也就没有"闪一下"这回事。
//
// 【为什么存 Promise 而不是存结果】页面 +12ms 就建好了，而响应 +13ms 才回来：
// 存结果的话 MessageStore 构造那一刻缓存**必然是空的**，全部落回原路，白做。
// 存在途的 Promise，store 直接接上去等，既不重发也不会错过。
//
// 【只管最普通那一种】话题/评论区/私聊话题、以及带跳转锚点的进入一律不预取
// （见 canPrefetchChat）：那些的请求形状不同，猜错了比不预取更糟。未命中时
// 行为与改动前逐字相同。

import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { getTdClient } from '../tdkit/Globals';
import { logW } from './log';

// 首屏两种落点的请求几何。**MessageStore 与预取共用这一份**——抄第二份必然漂。
//
// 【09-04 调大：14/12 → 30/20】原来取小的理由是那句实测："30 条一帧建完是首帧
// 掉帧的来源，12 条铺满一屏出头，剩下的靠短页补链补齐"。**那是逐帧分批放行还
// 没有的时候的结论**——现在行是一帧一个放出去的（实测每批 16–18ms，没有长帧），
// "一帧建 30 个"这个前提不成立了。
//
// 而取小的代价是实打实的：首页不够铺满 ⇒ 立刻启动一轮往上补页 ⇒ 分批放行拒绝
// 对着还在动的快照揭幕（锚点会被前插挪走）⇒ 实测多等 407ms，然后十几行挤成
// 一批同时落地，还伴随锚点补偿的跳动（用户："一起出来有点卡"、"页面跳了几下"）。
// 第一页就铺满，这三件事一起没有。
export const INITIAL_LATEST_LIMIT: number = 20;
export const INITIAL_AROUND_LIMIT: number = 30;

// **跳转/续播（initialAlignFromStart）那条路仍取 14，不跟着调大。**
//
// 那条路的偏移是 -(limit - 1)：目标行对齐到窗口最旧的一端，其余全是它之后的行。
// 调到 30 就等于目标之后一下多出 16 行，锚点恢复要为此补偿一大段——实测
// [AnchorRestore] 里 dy=0 而 dOff=759，画面上就是"消息乱跳"。
// 而调大的收益只属于未读/最新那两条（首页铺不满才触发补页），跳转这条根本
// 不走预取（见 canPrefetchChat），白吃副作用。
export const INITIAL_RESUME_LIMIT: number = 14;
// 未读锚点要保留上下文：目标之上 7 条、之下 6 条。
export const INITIAL_AROUND_OFFSET: number = -7;

export const ROUTE_AROUND: string = 'around';
export const ROUTE_LATEST: string = 'latest';

export interface InitialPageRoute {
  kind: string;
  fromMessageId: number;
  offset: number;
  limit: number;
}

// **首屏该发哪一发。这是唯一判据，MessageStore.requestInitialPage 也走它。**
//
// 有未读且已读水位有效 → 以水位为锚居中开窗，保证未读分界线落在窗口里；
// 否则 → 取最新一页。判据本身照抄自 requestInitialPage 的原注释：
// lastReadInboxId 只跟踪收到的消息，全已读、且最新几条是自己发的会话，
// 它会停在真实尾部之后很远，那时必须走 latest。
export function initialPageRoute(unreadCount: number, lastReadInboxId: number): InitialPageRoute {
  if (unreadCount > 0 && lastReadInboxId > 0) {
    return {
      kind: ROUTE_AROUND,
      fromMessageId: lastReadInboxId,
      offset: INITIAL_AROUND_OFFSET,
      limit: INITIAL_AROUND_LIMIT
    };
  }
  return { kind: ROUTE_LATEST, fromMessageId: 0, offset: 0, limit: INITIAL_LATEST_LIMIT };
}

// 两条路由是不是同一发。store 拿到的输入可能比列表新（期间来了消息），
// 不一致就丢掉预取走原路——**宁可不用，也不能用错的那一页开窗**。
export function sameRoute(a: InitialPageRoute, b: InitialPageRoute): boolean {
  return a.kind === b.kind && a.fromMessageId === b.fromMessageId
    && a.offset === b.offset && a.limit === b.limit;
}

// 只有"普普通通打开一个会话"才预取。
export function canPrefetchChat(
  chatId: number, threadRootId: number, forumTopicId: number,
  directMessagesTopicId: number, hasJumpTarget: boolean
): boolean {
  return chatId !== 0 && threadRootId === 0 && forumTopicId === 0
    && directMessagesTopicId === 0 && !hasJumpTarget;
}

interface PendingPrefetch {
  promise: Promise<TdObject>;
  at: number;
  route: InitialPageRoute;
}

// 过期时间。用户点了却没进去（被别的页面拦住、手滑返回）时不能一直留着，
// 否则下次真进来会用到一页陈旧的窗口。
export const PREFETCH_TTL_MS: number = 10000;

const pending: Map<number, PendingPrefetch> = new Map();

// 发起预取。已经有在途的同会话请求就不重发。
export function prefetchInitialPage(
  chatId: number, unreadCount: number, lastReadInboxId: number
): void {
  const existing: PendingPrefetch | undefined = pending.get(chatId);
  if (existing !== undefined && Date.now() - existing.at < PREFETCH_TTL_MS) {
    return;
  }
  const route: InitialPageRoute = initialPageRoute(unreadCount, lastReadInboxId);
  const req: TdRequest = { '@type': 'getChatHistory' };
  req['chat_id'] = chatId;
  req['from_message_id'] = route.fromMessageId;
  req['offset'] = route.offset;
  req['limit'] = route.limit;
  // **预取绝不等服务器。**
  //
  // 09-04 实测：首屏页从 14 调到 30 之后，本地凑不够 30 条的会话开始走网络，
  // 一等就是 ~410ms —— 那等于把"补页 407ms"换成了"网络 372ms"，白忙一场。
  // 预取的全部意义是"页面建好时结果已经在手里"，为此宁可少给几条：本地有多少
  // 给多少，不够的部分照旧由 store 的补链/分页去要（那条路本来就一直在跑）。
  req['only_local'] = true;
  // **失败也要留在表里**：store 取走时会看到一个 rejected 的 Promise，它自己
  // catch 之后照原路重发。这里不 catch 掉，否则会变成一个永远 pending 的洞。
  const promise: Promise<TdObject> = getTdClient().send(req);
  // 未被取走的 rejection 会冒到全局，这里挂一个空收尾；store 那边是另一条
  // then 链，不受影响。
  promise.catch((e: TdError): void => {
    logW(`chatPrefetch ${chatId} failed (store will retry): ${e.message}`);
  });
  pending.set(chatId, { promise: promise, at: Date.now(), route: route });
}

// 取走（一次性）。路由不一致或已过期一律返回 null。
export function takePrefetchedPage(
  chatId: number, route: InitialPageRoute
): Promise<TdObject> | null {
  const hit: PendingPrefetch | undefined = pending.get(chatId);
  if (hit === undefined) {
    return null;
  }
  pending.delete(chatId);
  if (Date.now() - hit.at >= PREFETCH_TTL_MS || !sameRoute(hit.route, route)) {
    return null;
  }
  return hit.promise;
}

// 「这次进入有没有预取在手」——ChatPage 用它决定要不要下那道发布围栏。
// **只看在不在、不看路由**：围栏是个观感兜底，路由对不上时最坏是白撤一次围栏。
export function hasPrefetchedPage(chatId: number): boolean {
  const hit: PendingPrefetch | undefined = pending.get(chatId);
  return hit !== undefined && Date.now() - hit.at < PREFETCH_TTL_MS;
}

// 仅供单测。
export function resetPrefetchForTest(): void {
  pending.clear();
}
