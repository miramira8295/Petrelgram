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
}

interface TdWorkerEvent {
  kind: string;
  payload?: object;
  head?: string;
}

// 可交换更新的合并缓冲（A 批 2，见 tdkit/tdUpdateFilter）。Map 迭代按插入序，
// flush 时的相对顺序即到达顺序（同 key 后写覆盖先写、占原位）。
const pendingCoalesced: Map<string, object> = new Map<string, object>();
let flushTimer: number = -1;
const COALESCE_FLUSH_MS: number = 48;

function flushCoalesced(): void {
  if (flushTimer !== -1) {
    clearTimeout(flushTimer);
    flushTimer = -1;
  }
  if (pendingCoalesced.size === 0) {
    return;
  }
  pendingCoalesced.forEach((payload: object): void => {
    const event: TdWorkerEvent = { kind: 'recv', payload: payload };
    postSafe(event);
  });
  pendingCoalesced.clear();
}

function deliver(obj: object): void {
  const key: string = coalesceKeyOf(obj as Record<string, Object>);
  if (key === '') {
    // 直通事件发出前先冲积压：与不可交换事件的相对顺序必须保持。
    flushCoalesced();
    const event: TdWorkerEvent = { kind: 'recv', payload: obj };
    postSafe(event);
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
    // 账号切换会重发 init：清掉上一个运行时的积压。
    pendingCoalesced.clear();
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
    testNapi.tdSend(msg.json ?? '');
  }
}
