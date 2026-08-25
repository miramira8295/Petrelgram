import router from '@ohos.router';
import { logE } from './log';
import { chatKey, decideChatPush, ChatPushDecision, PushOrigin, StackFrame } from './splitRouting';
import { NavStackLike, snapshotOf, stackOf } from './navStacks';
import { isSplitLayout } from './splitMetrics';
import { setChatListRenderActive } from './chatListRenderGate';

// 聊天详情页的路由地址。此前十个调用点各自写了一遍这个字符串，也各自
// 直接 pushUrl——谁也不检查栈里是否已经有一个同会话的详情页，于是通知、
// 消息里的群组链接、搜索结果三条路都能把同一个群叠出好几层。
export const CHAT_PAGE_URL: string = 'pages/chat/ChatPage';
const CHAT_PAGE_NAME: string = 'ChatPage';

// 路由表（router_map.json）里注册的名字。与 CHAT_PAGE_NAME 同值不是巧合：
// router 时代的页面名和 NavDestination 名都取自同一个文件名，但两者的用途
// 不同（一个是 router 栈里的 name，一个是路由表条目），分开写以免哪天改一个
// 就把另一个也带歪。
export const CHAT_DEST_NAME: string = 'ChatPage';

// MainScreen 的当前页签下标，@StorageLink('mainTabIndex') 双向绑定，外部写入由
// 它的 @Watch('onTabExternallyChanged') 落到 TabsController 上。Index.ets:175
// 也是这么写的。
export const KEY_MAIN_TAB: string = 'mainTabIndex';
// MainScreen.build() 里 TabContent 的顺序：ChatListPage / ContactsPage /
// SettingsPage / MyProfilePage。
export const CHAT_TAB_INDEX: number = 0;

// 不关心跳转结果的调用点用它收尾。navigateToChat 现在**会 reject**（回退的
// 整页路由真失败时），而 ArkTS 里被丢弃的 rejection 会冒到全局去，所以每个
// 即发即忘的调用点都必须显式收掉——收法只有这一种，抽出来省得抄二十几遍。
export function logChatNavFailure(e: Error): void {
  logE(`navigateToChat failed: ${e.message}`);
}

// 路由栈的一层，抽成纯数据是为了让去重规则可以脱离 router 单测。
export interface RouteSnapshot {
  index: number;
  name: string;
  path: string;
  chatId: number;
  topicId: number;
}

// 栈里承载该会话的详情页下标，0 表示没有——router 的下标从 1 开始，所以
// 0 是个安全的"无"。有多层匹配时返回最靠上的一层：回退到更深的一层会把
// 中间那些页面一起弹掉。
export function findChatRouteIndex(stack: RouteSnapshot[], chatId: number, topicId: number): number {
  let found: number = 0;
  for (const r of stack) {
    if (r.name !== CHAT_PAGE_NAME || r.chatId !== chatId || r.topicId !== topicId) {
      continue;
    }
    if (r.index > found) {
      found = r.index;
    }
  }
  return found;
}

function numberField(params: Object | undefined, key: string): number {
  if (params === undefined || params === null) {
    return 0;
  }
  const bag = params as Record<string, Object>;
  const raw = bag[key] as number | undefined;
  return raw === undefined ? 0 : raw;
}

// 当前路由栈的快照。getLength 返回的是字符串（不是笔误，SDK 就这么定义的），
// 且 getStateByIndex 对越界返回 undefined，两处都得防。
function snapshotRoutes(): RouteSnapshot[] {
  const out: RouteSnapshot[] = [];
  const depth = Number(router.getLength());
  if (!Number.isFinite(depth) || depth <= 0) {
    return out;
  }
  for (let i = 1; i <= depth; i++) {
    const st = router.getStateByIndex(i);
    if (st === undefined) {
      continue;
    }
    out.push({
      index: st.index,
      name: st.name,
      path: st.path,
      chatId: numberField(st.params, 'chatId'),
      topicId: numberField(st.params, 'forumTopicId')
    });
  }
  return out;
}

// 会话的实例键：param 里塞的是 chatId / forumTopicId 两个数字。注意话题字段
// 叫 forumTopicId 而不是 topicId——十来个调用点塞的都是这个名字，别改。
function chatFrameKey(name: string, param: Object | undefined): string {
  if (name !== CHAT_DEST_NAME || param === undefined) {
    return '';
  }
  return chatKey(numberField(param, 'chatId'), numberField(param, 'forumTopicId'));
}

// 迁移前的整页路由回退。栈还没注册时（冷启动早期，ChatListPage 尚未挂树）
// 走这条，行为与迁移前完全一致——含 findChatRouteIndex 的同会话去重。
function navigateToChatViaRouter(params: Record<string, Object>): Promise<void> {
  const chatId = numberField(params, 'chatId');
  const topicId = numberField(params, 'forumTopicId');
  if (chatId !== 0) {
    let existing: number = 0;
    try {
      existing = findChatRouteIndex(snapshotRoutes(), chatId, topicId);
    } catch (e) {
      // 路由栈读不到不该连累跳转本身——退化成老行为（新开一页）即可。
      const err = e as Error;
      logE(`chatNav.snapshot failed: ${err.message}`);
    }
    if (existing > 0) {
      // back 带上新参数，已经在栈里的那一页可以据此跳到指定消息。
      router.back(existing, params);
      return Promise.resolve();
    }
  }
  // 这里**不再**吞掉失败：整页路由跳不动是真正的"会话打不开"，调用方
  // （比如 NewGroupPage 建完群要据此决定是弹掉自己还是报错）需要知道。
  // 即发即忘的调用点用 logChatNavFailure 自行收尾。
  return router.pushUrl({ url: CHAT_PAGE_URL, params: params });
}

// 打开会话详情页。这是**所有**会话入口的唯一漏斗（通知、深链、搜索结果、
// 群链接、转发来源、联系人页），改这一个函数等于改全部入口。
//
// **会 reject**，但只在一条窄路径上：栈还没注册（冷启动早期，ChatListPage 尚未
// 挂树）时会回退到整页 router，此时 pushUrl 的失败会原样透出来。栈已注册的主
// 路径全程 resolve。
//
// **origin 决定推栈方式，这是本函数最要紧的一个参数**：
//
//   'navbar'  —— 用户从**左栏/列表**选了一个会话（会话列表、通知、深链、搜索
//                结果）。语义是"换一个会话看"，所以先清空右栏再推：不清的话
//                在列表里点十个会话就叠十层，返回要按十次。
//   'content' —— 用户从**当前右栏内部**跳去另一个会话（消息里的群链接、@提及、
//                转发来源、资料页的「发消息」、话题列表选话题）。语义是"再往
//                里走一层"，必须保留当前这层，否则返回就跳过了它。
//
// **1.4.0 的回归就是这里**：此前 origin 恒为 'navbar'，于是
//   文件夹A → 聊天B →（从 B 里点进）聊天C → 返回
// 会直接落回文件夹A 的列表——推 C 的时候把 B 那一层清掉了。用户期望回到 B。
// 同一根因还有两个表现：「话题列表 → 话题 → 返回」不回话题列表；
// 「资料页 → 发消息 → 返回」不回资料页。三个一起修。
//
// **判据不是"调用点写在哪个文件"，而是"用户此刻在哪一栏"。** ChatRow 代码只有
// 一处，却有两个运行时上下文——左栏会话列表和归档列表。从归档里点话题群曾按
// 'navbar' 清栈，返回后落回会话列表而不是归档（issue #117）；现在 ChatRow 按
// listKey 传 origin，navigateToForumTopics 不再写死。
//
// 之所以不把失败吞在这里：NewGroupPage 建完群要靠这个 rejection 才能把
// "打不开会话" 反馈给用户（复位 spinner + 显示错误），吞掉它那段就是死代码。
// 代价是每个调用点都得接住——除 ChatListPage（return 进了自己的链）和
// NewGroupPage（自己处理）外，其余 26 处统一 .catch(logChatNavFailure)。
// 新增调用点时别忘了跟上，否则是未捕获的 Promise rejection。
// origin 参数保留但**已不参与决策**——去重规则现在只看"这个会话是不是已经
// 开着"，与从哪一栏点的无关。留着签名是为了不动 10 个调用点，也为了将来若要
// 恢复"从列表选会话就替换"的行为时有现成的入口。
export function navigateToChat(
  params: Record<string, Object>,
  origin: PushOrigin = 'navbar'
): Promise<void> {
  const stack: NavStackLike | undefined = stackOf('chat');
  if (stack === undefined) {
    // 回退走的是整页 router，不依赖页签，所以下面那句切页签不能提到这上面来。
    return navigateToChatViaRouter(params);
  }
  // 推进去的是**聊天页签的栈**，所以必须先确保聊天页签是当前页签——否则会话
  // 推进去了却在屏幕外。从联系人页签建群（ContactsPage → NewGroupPage）、停在
  // 设置页签时点通知或深链，都会撞上这个。
  //
  // 放在 decidePush 之前是有意的：skip 分支（会话已经在栈顶）同样需要切页签，
  // 那种情况下用户看不见它的原因恰恰就是页签不对，此时什么都不做等于点击失灵。
  AppStorage.setOrCreate<number>(KEY_MAIN_TAB, CHAT_TAB_INDEX);
  const target: StackFrame = {
    name: CHAT_DEST_NAME,
    key: chatKey(numberField(params, 'chatId'), numberField(params, 'forumTopicId'))
  };
  // 允许同时开多个会话窗口，但同一个会话只能有一个——规则在 splitRouting 的
  // decideChatPush（7 条测）。已经开着的会话不再新开一层，而是出栈回到它，
  // 这正是迁移前 findChatRouteIndex() 做的事（那时是 router.back(index)）。
  const snap: StackFrame[] = snapshotOf(stack, chatFrameKey);
  const decision: ChatPushDecision = decideChatPush(snap, target);
  if (decision.action === 'skip') {
    return Promise.resolve();
  }
  if (decision.action === 'popTo') {
    // 逐层出栈到目标那一层。NavStackLike 没有 popToIndex，只能一层层来；
    // 层数就是压在目标之上的那些，由 decideChatPush 算好。
    for (let i = 0; i < decision.popCount; i++) {
      stack.pop(false);
    }
    return Promise.resolve();
  }
  // onNavBarStateChange(false) arrives after HdsNavigation has started the
  // push. Close the render gate synchronously first so read/revision updates
  // caused by opening the chat cannot publish into the covered LazyForEach in
  // that gap. Split layouts keep the list visible and therefore stay active.
  const screenW: number = AppStorage.get<number>('screenWidthVp') ?? 0;
  const screenH: number = AppStorage.get<number>('screenHeightVp') ?? 0;
  if (!isSplitLayout(screenW, screenH)) {
    setChatListRenderActive(false);
  }
  stack.pushPath({ name: CHAT_DEST_NAME, param: params });
  return Promise.resolve();
}
