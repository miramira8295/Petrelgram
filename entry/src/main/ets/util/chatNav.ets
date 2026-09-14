import { KEY_FORCE_SINGLE_COLUMN } from '../store/AppSettings';
import { queuePendingNav } from './pendingNav';
import { requestChatJump } from './chatJumpChannel';
import { logE } from './log';
import { canPrefetchChat, prefetchInitialPage } from './chatPrefetch';
import { getChatStore } from '../tdkit/Globals';
import { ChatEntry } from '../store/ChatEntry';
import { chatKey, decideChatPush, ChatPushDecision, PushOrigin, StackFrame } from './splitRouting';
import { NavStackLike, snapshotOf, stackOf } from './navStacks';
import { isSplitLayout } from './splitMetrics';
import { setChatListRenderActive } from './chatListRenderGate';
import { routeTopicId } from './messageTopicScope';

// 聊天详情页目的地的名字。此前十个调用点各自写了一遍这个字符串、各自直接
// pushUrl——谁也不检查栈里是否已经有一个同会话的详情页，于是通知、消息里的
// 群组链接、搜索结果三条路都能把同一个群叠出好几层。
//
// 2026-09-14：router 时代的那一半（CHAT_PAGE_URL / snapshotRoutes /
// findChatRouteIndex / navigateToChatViaRouter）连同"栈没注册就整页路由"的
// 回退一起退役了——ChatPage 早已从 main_pages.json 摘出，那条回退必然失败。
// 现在走挂起重放，见 util/pendingNav。
export const CHAT_DEST_NAME: string = 'ChatPage';

// MainScreen 的当前页签下标，@StorageLink('mainTabIndex') 双向绑定，外部写入由
// 它的 @Watch('onTabExternallyChanged') 落到 TabsController 上。Index.ets:175
// 也是这么写的。
export const KEY_MAIN_TAB: string = 'mainTabIndex';
// MainScreen.build() 里 TabContent 的顺序：ChatListPage / ContactsPage /
// SettingsPage / MyProfilePage。
export const CHAT_TAB_INDEX: number = 0;

// 不关心跳转结果的调用点用它收尾。navigateToChat 的签名仍是 Promise（26 个
// 调用点接着它），而 ArkTS 里被丢弃的 rejection 会冒到全局去，所以每个
// 即发即忘的调用点都必须显式收掉——收法只有这一种，抽出来省得抄二十几遍。
export function logChatNavFailure(e: Error): void {
  logE(`navigateToChat failed: ${e.message}`);
}

function numberField(params: Object | undefined, key: string): number {
  if (params === undefined || params === null) {
    return 0;
  }
  const bag = params as Record<string, Object>;
  const raw = bag[key] as number | undefined;
  return raw === undefined ? 0 : raw;
}


// 会话的实例键：param 里塞的是 chatId / forumTopicId 两个数字。注意话题字段
// 叫 forumTopicId 而不是 topicId——十来个调用点塞的都是这个名字，别改。
function chatFrameKey(name: string, param: Object | undefined): string {
  if (name !== CHAT_DEST_NAME || param === undefined) {
    return '';
  }
  return chatKey(numberField(param, 'chatId'),
    routeTopicId(param as Record<string, Object> | undefined));
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
// **origin 重新参与决策**（见 splitRouting.decideChatPush 的 replaceExisting）：
//   'navbar'  —— 只保留一个详情页。用户报：Pad 左栏点多个会话，右栏叠出多个
//                页面，返回要按很多次。判据是**从哪条路进来的**而不是屏幕多宽，
//                所以手机同样只留一个——那条路的语义本来就是"换一个会话看"。
//   'content' —— 照旧叠加。"手机端允许多个会话详情叠加"说的是这一条：从会话里
//                点进另一个会话，返回必须回到上一个（1.4.0 的回归就是把这条
//                也清了）。
export function navigateToChat(
  params: Record<string, Object>,
  origin: PushOrigin = 'navbar'
): Promise<void> {
  // 首屏预取：在页面还没建之前就把第一页要出来（见 util/chatPrefetch 的说明）。
  // 这里是**十个入口唯一的漏斗**，挂一处就覆盖列表/搜索/通知/深链全部。
  startInitialPagePrefetch(params);
  const stack: NavStackLike | undefined = stackOf('chat');
  if (stack === undefined) {
    // 栈还没注册（冷启动那一瞬：Index 在 stage 刚变 Ready 的同一拍就消费通知，
    // 而 MainScreen 只画在 Ready 分支里，ChatListPage 还没挂树）。
    //
    // **不再退回整页 router**：ChatPage 已从 main_pages.json 摘出，那条路必然
    // 失败，而且是系统弹一句"无法识别的链接"——用户报的正是这个。挂起，等
    // ChatListPage 注册完栈再重放（util/pendingNav）。
    AppStorage.setOrCreate<number>(KEY_MAIN_TAB, CHAT_TAB_INDEX);
    queuePendingNav({
      tab: 'chat', kind: 'chat', dest: CHAT_DEST_NAME, params: params, origin: origin
    });
    return Promise.resolve();
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
    key: chatKey(numberField(params, 'chatId'), routeTopicId(params))
  };
  // 允许同时开多个会话窗口，但同一个会话只能有一个——规则在 splitRouting 的
  // decideChatPush。已经开着的会话不再新开一层，而是出栈回到它，
  // 这正是迁移前 findChatRouteIndex() 做的事（那时是 router.back(index)）。
  //
  // 「选一个会话来看」这条路只保留一个详情页（见上面 origin 那段）。窗口尺寸
  // 与这个判断无关，读它是给下面关渲染闸用的。
  const screenW: number = AppStorage.get<number>('screenWidthVp') ?? 0;
  const screenH: number = AppStorage.get<number>('screenHeightVp') ?? 0;
  const split: boolean = isSplitLayout(screenW, screenH,
    AppStorage.get<boolean>(KEY_FORCE_SINGLE_COLUMN) ?? false);
  const snap: StackFrame[] = snapshotOf(stack, chatFrameKey);
  const decision: ChatPushDecision =
    decideChatPush(snap, target, origin === 'navbar', origin === 'search');
  // **skip / popTo 这两条路不传参**：栈帧的 param 不会因为出栈而更新，已经挂在
  // 树上的那个 ChatPage 不会重新吃一遍 pathInfo。所以 jumpTo 得走旁路交过去，
  // 否则「资料页点媒体」「搜索到已打开会话里的消息」都只是回到那一页、停在
  // 原来的位置（issue #80、#102）。push 那条不用管，它本来就把参数带进去了。
  const jumpTo: number = numberField(params, 'jumpTo');
  if (decision.action === 'skip') {
    requestChatJump(numberField(params, 'chatId'), jumpTo);
    return Promise.resolve();
  }
  if (decision.action === 'popTo') {
    // 逐层出栈到目标那一层。NavStackLike 没有 popToIndex，只能一层层来；
    // 层数就是压在目标之上的那些，由 decideChatPush 算好。
    for (let i = 0; i < decision.popCount; i++) {
      stack.pop(false);
    }
    // 出栈之后再发：那一页这时才在眼前，滚动落点也才量得准。
    requestChatJump(numberField(params, 'chatId'), jumpTo);
    return Promise.resolve();
  }
  // onNavBarStateChange(false) arrives after HdsNavigation has started the
  // push. Close the render gate synchronously first so read/revision updates
  // caused by opening the chat cannot publish into the covered LazyForEach in
  // that gap. Split layouts keep the list visible and therefore stay active.
  if (!split) {
    setChatListRenderActive(false);
  }
  // clearAndPush：先把右栏清空再推，右栏于是恒为一层。**animated=false**——
  // 清空动画和紧接着的推入动画会在同一帧里打架，看到的是旧会话先滑走再滑入
  // 新的；替换的观感应当是直接换掉。
  if (decision.action === 'clearAndPush') {
    stack.clear(false);
  }
  stack.pushPath({ name: CHAT_DEST_NAME, param: params });
  return Promise.resolve();
}

// 预取的接线：从路由参数取会话，从会话列表取那三个决策输入。
//
// **拿不到列表条目就不预取**——那三个值是决策的全部依据，猜一个反而会开错窗。
// 通知/深链进来的会话可能不在列表里，那时就走原路，行为与改动前相同。
function startInitialPagePrefetch(params: Record<string, Object>): void {
  const chatId: number = numberField(params, 'chatId');
  const hasJump: boolean = params['jumpTo'] !== undefined;
  if (!canPrefetchChat(chatId, numberField(params, 'threadRootId'),
    numberField(params, 'forumTopicId'), numberField(params, 'directMessagesTopicId'), hasJump)) {
    return;
  }
  const entry: ChatEntry | undefined = getChatStore().entryOf(chatId);
  if (entry === undefined) {
    return;
  }
  prefetchInitialPage(chatId, entry.unreadCount, entry.lastReadInboxId);
}
