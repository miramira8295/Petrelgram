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
}

interface TdWorkerEvent {
  kind: string;
  payload?: object;
  // kind==='batch' 时的整批（批内顺序 = 到达顺序）。
  items?: object[];
  // kind==='order' 时的排序快照（第二层 B2，影子索引对账用）。
  lists?: OrderSnapshot[];
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
    lists.push({ key, ids: orderIndex.orderedIds(key).slice() });
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
    pendingCoalesced.clear();
    batch.reset();
    // 新运行时：影子索引整体作废，等新一轮 updateNewChat 重建。
    knownChats.clear();
    orderIndex.clear();
    orderDirty.clear();
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
