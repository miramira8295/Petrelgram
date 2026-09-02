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

scope.onmessage = (e: MessageEvents): void => {
  const msg = e.data as TdWorkerCommand;
  if (msg.kind === 'init') {
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
      const event: TdWorkerEvent = { kind: 'recv', payload: obj };
      postSafe(event);
    });
  } else if (msg.kind === 'send') {
    testNapi.tdSend(msg.json ?? '');
  }
};
