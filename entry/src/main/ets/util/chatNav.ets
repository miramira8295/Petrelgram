import router from '@ohos.router';
import { logE } from './log';
import { chatKey, decidePush, StackAction, StackFrame } from './splitRouting';
import { NavStackLike, snapshotOf, stackOf } from './navStacks';

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
  return router.pushUrl({ url: CHAT_PAGE_URL, params: params }).catch((e: Error): void => {
    logE(`chatNav.pushUrl failed: ${e.message}`);
  });
}

// 打开会话详情页。这是**所有**会话入口的唯一漏斗（通知、深链、搜索结果、
// 群链接、转发来源、联系人页），改这一个函数等于改全部入口。
//
// 返回 Promise 只是为了让少数几个想串在自己流程里的调用点还能 then/catch，
// 它不会 reject——跳不动是这里自己记日志，不该把调用方的流程也带崩。
export function navigateToChat(params: Record<string, Object>): Promise<void> {
  const stack: NavStackLike | undefined = stackOf('chat');
  if (stack === undefined) {
    return navigateToChatViaRouter(params);
  }
  const target: StackFrame = {
    name: CHAT_DEST_NAME,
    key: chatKey(numberField(params, 'chatId'), numberField(params, 'forumTopicId'))
  };
  // 会话是从左栏（或通知/深链——语义同样是"选一个会话"）选的，按分栏规则
  // 先清右栏再推。这一步替代了迁移前 findChatRouteIndex() 的去重：那时是
  // 回退到栈里已有的那一层，现在是直接把右栏换成目标会话，结果一致而更简单。
  const snap: StackFrame[] = snapshotOf(stack, chatFrameKey);
  const action: StackAction = decidePush(snap, 'navbar', target);
  if (action === 'skip') {
    return Promise.resolve();
  }
  if (action === 'clearAndPush') {
    stack.clear(false);
  }
  stack.pushPath({ name: CHAT_DEST_NAME, param: params });
  return Promise.resolve();
}
