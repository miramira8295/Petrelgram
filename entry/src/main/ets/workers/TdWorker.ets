// TDLib 收包线程（A 批 1，见 docs/superpowers/specs/2026-09-02-tdlib-worker-survey.md）。
//
// 职责刻意最小：持有 libentry.so 的收发口，收到的 JSON 在**本线程**解析，
// 把解析结果经 postMessage（结构化克隆）投回 UI 线程。过滤/合并（A 批 2 的
// updateFile 节流等）将来加在 parse 之后、post 之前——顺序语义必须保持：
// 本文件内单队列顺发，不重排。
//
// ⚠️ spike 未验证项（开关默认关的原因）：libentry.so 在 worker 线程的可加载
// 性与 tdInit 回调的线程投递假设。真机验证清单见勘探文档问题 1/4。

import { worker, ThreadWorkerGlobalScope, MessageEvents } from '@kit.ArkTS';
import testNapi from 'libentry.so';
import { coalesceKeyOf } from '../tdkit/tdUpdateFilter';
import { TdIngestBatch, BatchTimerFns } from '../tdkit/tdIngestBatch';
import { ChatListOrder, OrderSnapshot } from '../store/chatListOrder';
import { listKeyOf } from '../store/ListKey';
import { TdObject } from '../tdkit/TdTypes';
import { ChatEntry } from '../store/ChatEntry';
import { buildChatEntry } from '../store/chatEntryFactory';

const scope: ThreadWorkerGlobalScope = worker.workerPort;

// postMessage 可抛（宿主已销毁/序列化失败）。worker 里没有日志管线，失败
// 只能吞——丢一条 update 的后果由 UI 侧的请求超时和 TDLib 的状态重放兜底。
function postSafe(event: object): void {
  try {
    scope.postMessage(event);
  } catch (_e) {
    // 见上：无处可记。
  }
}

interface TdWorkerCommand {
  kind: string;
  json?: string;
  request?: object;
  // init 时带上来的本地化文案（预览里的"照片""语音"等）。
  labels?: Record<string, string>;
}

interface TdWorkerEvent {
  kind: string;
  payload?: object;
  // kind==='batch' 时的整批（批内顺序 = 到达顺序）。
  items?: object[];
  // kind==='order' 时的排序快照（第二层 B2，影子索引对账用）。
  lists?: OrderSnapshot[];
  // kind==='chatEntry' 时由本线程构建的会话实体（第二层 B4b 影子）。
  entries?: ChatEntry[];
  head?: string;
}

// 可交换更新的合并缓冲（A 批 2，见 tdkit/tdUpdateFilter）。Map 迭代按插入序，
// flush 时的相对顺序即到达顺序（同 key 后写覆盖先写、占原位）。
const pendingCoalesced: Map<string, object> = new Map<string, object>();
let flushTimer: number = -1;
const COALESCE_FLUSH_MS: number = 48;

// 批投递（A 批 3，见 tdkit/tdIngestBatch）：窗口内的多条合一个 postMessage。
const batchTimer: BatchTimerFns = {
  setTimeout: (cb: () => void, ms: number): number => setTimeout(cb, ms),
  clearTimeout: (id: number): void => { clearTimeout(id); }
};
const batch: TdIngestBatch = new TdIngestBatch((items: object[]): void => {
  const event: TdWorkerEvent = { kind: 'batch', items: items };
  postSafe(event);
}, batchTimer);

function flushCoalesced(): void {
  if (flushTimer !== -1) {
    clearTimeout(flushTimer);
    flushTimer = -1;
  }
  if (pendingCoalesced.size === 0) {
    return;
  }
  // Map 迭代按插入序：并入批次的相对顺序仍是到达顺序。
  pendingCoalesced.forEach((payload: object): void => {
    batch.push(payload);
  });
  pendingCoalesced.clear();
}

function deliver(obj: object): void {
  const record = obj as Record<string, Object>;
  // 影子索引：先按到达顺序喂一遍，再走投递（投递可能被合并/批处理推迟，
  // 而位置语义必须按到达顺序落地）。
  trackOrder(record);
  trackChatEntry(record);
  const key: string = coalesceKeyOf(record);
  if (key === '') {
    // 直通事件发出前先冲积压：与不可交换事件的相对顺序必须保持。
    flushCoalesced();
    // 响应（带 @extra）不吃批窗口：先冲掉已排队的一批，再单独投递，
    // 既保序又不给请求-响应加最多一个窗口的延迟。
    if ((obj as Record<string, Object>)['@extra'] !== undefined) {
      batch.flush();
      const event: TdWorkerEvent = { kind: 'recv', payload: obj };
      postSafe(event);
      return;
    }
    batch.push(obj);
    return;
  }
  pendingCoalesced.set(key, obj);
  if (flushTimer === -1) {
    flushTimer = setTimeout((): void => {
      flushTimer = -1;
      flushCoalesced();
    }, COALESCE_FLUSH_MS);
  }
}

// ── 第二层 B2：影子排序索引 ────────────────────────────────────────────────
//
// 用同一份更新流在 worker 里再排一遍。**它现在只用于对账**：UI 侧拿自己的
// 序列和它对，逐项不一致就打日志、切权威的事留到下一批。这样即使影子错了，
// 用户看到的仍是 UI 的排序。
//
// 三个入口与 ChatStore 完全对齐：updateNewChat（chat.positions）、
// updateChatLastMessage（positions）、updateChatPosition（position）。
// 顺序 = 更新到达顺序；去重与置顶分段规则由 ChatListOrder 保证（同一份代码）。
const knownChats: Set<number> = new Set<number>();
const orderIndex: ChatListOrder = new ChatListOrder((id: number): boolean => knownChats.has(id));
const orderDirty: Set<string> = new Set<string>();
let orderTimer: number = -1;
// 每 200ms 把脏列表发一次。**快照不要求"恰好一致"**：UI 侧的位置更新会被
// 行级配对事务压到 320ms 之后才落，任何时刻比对都天然会看到"worker 新、
// UI 旧"。真正的判据在 UI 侧：只在它自己安静下来之后才比对（见
// ChatStore.compareWorkerOrder）。
const ORDER_POST_MS: number = 200;

function applyPositionOf(chatId: number, position: Record<string, Object>): void {
  const list = position['list'] as Record<string, Object> | undefined;
  if (list === undefined) {
    return;
  }
  const key: string = listKeyOf(list as TdObject);
  if (key === '') {
    return;
  }
  const order: string = (position['order'] as string | undefined) ?? '0';
  const isPinned: boolean = (position['is_pinned'] as boolean | undefined) ?? false;
  orderIndex.apply(key, chatId, order, isPinned);
  orderDirty.add(key);
  if (orderTimer === -1) {
    orderTimer = setTimeout((): void => {
      orderTimer = -1;
      flushOrder();
    }, ORDER_POST_MS);
  }
}

function flushOrder(): void {
  if (orderDirty.size === 0) {
    return;
  }
  const lists: OrderSnapshot[] = [];
  orderDirty.forEach((key: string): void => {
    const ids: number[] = orderIndex.orderedIds(key).slice();
    const pinned: number[] = [];
    for (const id of ids) {
      if (orderIndex.isPinned(key, id)) {
        pinned.push(id);
      }
    }
    lists.push({ key, ids, pinned });
  });
  orderDirty.clear();
  const event: TdWorkerEvent = { kind: 'order', lists: lists };
  postSafe(event);
}

function trackOrder(obj: Record<string, Object>): void {
  const type: string | undefined = obj['@type'] as string | undefined;
  if (type === 'updateNewChat') {
    const chat = obj['chat'] as Record<string, Object> | undefined;
    if (chat === undefined) {
      return;
    }
    const id = chat['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    knownChats.add(id);
    const positions = chat['positions'] as object[] | undefined;
    if (positions !== undefined) {
      for (const p of positions) {
        applyPositionOf(id, p as Record<string, Object>);
      }
    }
    return;
  }
  if (type === 'updateChatLastMessage') {
    const id = obj['chat_id'] as number | undefined;
    const positions = obj['positions'] as object[] | undefined;
    if (id === undefined || positions === undefined) {
      return;
    }
    for (const p of positions) {
      applyPositionOf(id, p as Record<string, Object>);
    }
    return;
  }
  if (type === 'updateChatPosition') {
    const id = obj['chat_id'] as number | undefined;
    const position = obj['position'] as Record<string, Object> | undefined;
    if (id === undefined || position === undefined) {
      return;
    }
    applyPositionOf(id, position);
  }
}

// ── 第二层 B4b：影子实体 ────────────────────────────────────────────────────
//
// 用 updateNewChat 的完整 chat 对象在本线程构建 ChatEntry（同一份
// chatEntryFactory），发回 UI 逐字段对账。**不切权威**：UI 仍按自己的路径建库，
// 这里只证明「工厂能在 worker 里跑，且算出来的字段与 UI 一致」。
//
// 已知的对不上的字段（本批不比）：lastSenderName（要 UserStore）、avatarPath
// （UI 侧异步解析）、typingText（UI 侧暂存事务）、isLive/isRtmpLive（来自通话
// 状态）、revision（各自口径）。
const shadowEntries: Map<number, ChatEntry> = new Map<number, ChatEntry>();
// worker 侧保留每个会话的**原始 chat 对象**，增量更新先打补丁再重建实体。
// 这样字段规则只有 chatEntryFactory 一份，没有第二套"逐字段赋值"要维护。
const shadowChats: Map<number, TdObject> = new Map<number, TdObject>();
const entryDirty: Set<number> = new Set<number>();
let entryTimer: number = -1;
const ENTRY_POST_MS: number = 200;
let shadowSelfId: number = 0;
// 预览文案的译文表：UI 在 init 时同步过来。没同步到就退回 key 本身——
// 宁可显示一个 key，也不要显示空白。
const previewLabels: Map<string, string> = new Map<string, string>();

// 资源里的占位符是 %1$s / %1$d（不是 %s）：worker 得自己替换，见
// base/element/string.json 的 preview_* 条目。
function fillLabel(pattern: string, arg: string | number): string {
  return pattern.replace('%1$s', `${arg}`).replace('%1$d', `${arg}`)
    .replace('%s', `${arg}`).replace('%d', `${arg}`);
}

function labelOf(key: string, arg?: string | number): string {
  const base: string | undefined = previewLabels.get(key);
  if (base === undefined) {
    return key;
  }
  return arg === undefined ? base : fillLabel(base, arg);
}

function flushEntries(): void {
  if (entryDirty.size === 0) {
    return;
  }
  const entries: ChatEntry[] = [];
  entryDirty.forEach((id: number): void => {
    const entry = shadowEntries.get(id);
    if (entry !== undefined) {
      entries.push(entry);
    }
  });
  entryDirty.clear();
  const event: TdWorkerEvent = { kind: 'chatEntry', entries: entries };
  postSafe(event);
}

// 增量 update → chat 对象上的补丁。返回补丁后的新对象；null = 这条 update
// 不在这条链上。
//
// 【为什么每次拷一份】ArkTS 不允许 delete，而 TdObject 装不下 null——"最后一条
// 消息没了"只能靠**去掉这个键**表达。拷贝只在有更新的那次发生，代价可接受。
function patchChat(obj: Record<string, Object>, base: TdObject): TdObject | null {
  const type: string | undefined = obj['@type'] as string | undefined;
  // "最后一条消息没了"（删除/清空会话）在 TDLib 里是 last_message 缺省。
  // ArkTS 不允许 delete，所以拷贝时直接跳过这个键——保留旧值会让 worker 的
  // 预览停在删掉的那条上（真机上正是这批 diff 的来源）。
  const dropLastMessage: boolean = type === 'updateChatLastMessage' && obj['last_message'] === undefined;
  const chat: TdObject = {};
  for (const key of Object.keys(base)) {
    if (dropLastMessage && key === 'last_message') {
      continue;
    }
    chat[key] = base[key];
  }
  if (type === 'updateChatLastMessage') {
    const lastMessage: Object | undefined = obj['last_message'];
    // TDLib 用空值表示"这条消息没了"：拷贝时就不带这个键，工厂按缺省当 null。
    if (lastMessage !== undefined) {
      chat['last_message'] = lastMessage;
    }
    const positions = obj['positions'];
    if (positions !== undefined) {
      chat['positions'] = positions;
    }
    return chat;
  }
  if (type === 'updateChatReadInbox') {
    chat['last_read_inbox_message_id'] = obj['last_read_inbox_message_id'];
    chat['unread_count'] = obj['unread_count'];
    return chat;
  }
  if (type === 'updateChatReadOutbox') {
    chat['last_read_outbox_message_id'] = obj['last_read_outbox_message_id'];
    return chat;
  }
  if (type === 'updateChatTitle') {
    chat['title'] = obj['title'];
    return chat;
  }
  if (type === 'updateChatPhoto') {
    chat['photo'] = obj['photo'];
    return chat;
  }
  if (type === 'updateChatNotificationSettings') {
    chat['notification_settings'] = obj['notification_settings'];
    return chat;
  }
  if (type === 'updateChatMessageAutoDeleteTime') {
    chat['message_auto_delete_time'] = obj['message_auto_delete_time'];
    return chat;
  }
  if (type === 'updateChatIsMarkedAsUnread') {
    chat['is_marked_as_unread'] = obj['is_marked_as_unread'];
    return chat;
  }
  if (type === 'updateChatUnreadMentionCount' || type === 'updateMessageMentionRead') {
    // 两个 update 都只带 unread_mention_count，语义都是"这个会话的提及数变了"。
    chat['unread_mention_count'] = obj['unread_mention_count'];
    return chat;
  }
  if (type === 'updateChatActionBar') {
    chat['action_bar'] = obj['action_bar'];
    return chat;
  }
  if (type === 'updateChatTheme') {
    chat['theme_name'] = obj['theme_name'];
    return chat;
  }
  if (type === 'updateChatVideoChat') {
    chat['video_chat'] = obj['video_chat'];
    return chat;
  }
  if (type === 'updateChatBackground') {
    chat['background'] = obj['background'];
    return chat;
  }
  return null;
}

function rebuildShadowEntry(id: number): void {
  const chat = shadowChats.get(id);
  if (chat === undefined) {
    return;
  }
  const entry: ChatEntry = buildChatEntry({
    chat,
    previous: shadowEntries.get(id),
    selfId: shadowSelfId,
    // 本批还没有 worker 侧用户表：这一列不参与对账。
    senderName: (_message: TdObject | undefined): string => '',
    label: labelOf
  });
  shadowEntries.set(id, entry);
  entryDirty.add(id);
  if (entryTimer === -1) {
    entryTimer = setTimeout((): void => {
      entryTimer = -1;
      flushEntries();
    }, ENTRY_POST_MS);
  }
}

function trackChatEntry(obj: Record<string, Object>): void {
  const type: string | undefined = obj['@type'] as string | undefined;
  if (type === 'updateOption') {
    if (((obj['name'] as string | undefined) ?? '') === 'my_id') {
      const value = obj['value'] as Record<string, Object> | undefined;
      const raw = value !== undefined ? value['value'] : undefined;
      const id: number = typeof raw === 'number' ? raw as number : Number(`${raw ?? 0}`);
      if (Number.isFinite(id) && id > 0) {
        shadowSelfId = id;
      }
    }
    return;
  }
  if (type === 'updateNewChat') {
    const chat = obj['chat'] as TdObject | undefined;
    if (chat === undefined) {
      return;
    }
    const id = chat['id'] as number | undefined;
    if (id === undefined) {
      return;
    }
    shadowChats.set(id, chat);
    rebuildShadowEntry(id);
    return;
  }
  // 其余类型是增量：先给保存的 chat 打补丁，再用同一份工厂重建实体。
  const chatId = obj['chat_id'] as number | undefined;
  if (chatId === undefined) {
    return;
  }
  const chat = shadowChats.get(chatId);
  if (chat === undefined) {
    // 没见过完整对象：UI 侧同样不会凭空建出会话，等 updateNewChat。
    return;
  }
  const patched: TdObject | null = patchChat(obj, chat);
  if (patched !== null) {
    shadowChats.set(chatId, patched);
    rebuildShadowEntry(chatId);
  }
}

scope.onmessage = (e: MessageEvents): void => {
  const msg = e.data as TdWorkerCommand;
  // td* 的 native 实现在 g_created 翻转窗口会抛 JS 异常（"tdSend before
  // tdInit"/"tdInit called twice"——账号切换时 UI 线程 tdDestroy 与本线程
  // 的消息处理存在竞争，napi_init.cpp 实测确认）。未捕获异常会杀死 worker
  // 的消息循环，等于整条收包线路无声死亡——必须包住并回报。
  try {
    handleCommand(msg);
  } catch (err) {
    const failure: TdWorkerEvent = { kind: 'parse-error', head: `${msg.kind} failed: ${err}` };
    postSafe(failure);
  }
};

function handleCommand(msg: TdWorkerCommand): void {
  if (msg.kind === 'init') {
    // 账号切换会重发 init：清掉上一个运行时的积压（合并缓冲与待发批次）。
    previewLabels.clear();
    const labels = msg.labels;
    if (labels !== undefined) {
      for (const key of Object.keys(labels)) {
        previewLabels.set(key, labels[key]);
      }
    }
    pendingCoalesced.clear();
    batch.reset();
    // 新运行时：影子索引整体作废，等新一轮 updateNewChat 重建。
    knownChats.clear();
    orderIndex.clear();
    orderDirty.clear();
    shadowEntries.clear();
    entryDirty.clear();
    shadowSelfId = 0;
    testNapi.tdInit((json: string): void => {
      let obj: object | null = null;
      try {
        obj = JSON.parse(json) as object;
      } catch (err) {
        // 与 TdClient.onReceive 的容错一致：无法解析的载荷丢弃。worker 里
        // 没有日志管线，回投一条 parse-error 事件由 UI 侧记日志。
        const parseError: TdWorkerEvent = { kind: 'parse-error', head: json.substring(0, 120) };
        postSafe(parseError);
        return;
      }
      deliver(obj);
    });
  } else if (msg.kind === 'send') {
    // 请求以对象跨线程（A 批 1 的发送侧）：序列化在**本线程**、tdSend 之前。
    // json 分支留给 TdBridge.send 的直通形态，两条路互斥。
    const payload: string = msg.request !== undefined
      ? JSON.stringify(msg.request)
      : (msg.json ?? '');
    testNapi.tdSend(payload);
  } else if (msg.kind === 'destroy') {
    // 账号切换：tdDestroy 也必须排在本队列里，和 tdSend/tdInit 串行。
    //
    // UI 线程直接调的那版会 join 接收线程、清 g_clientId，而本线程可能正有
    // 一条 tdSend 已越过 g_created 检查——napi_init.cpp 里这两步之间没有同步。
    // 上一个运行时的积压一并清掉：它们属于旧账号，不该在新运行时里落地
    // （init 分支同样会清，这里清是为了不依赖下一条 init 到达的时机）。
    pendingCoalesced.clear();
    if (flushTimer !== -1) {
      clearTimeout(flushTimer);
      flushTimer = -1;
    }
    batch.reset();
    testNapi.tdDestroy();
  }
}
