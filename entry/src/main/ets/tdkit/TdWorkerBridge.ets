// TdBridge 的 worker 实现（A 批 1，勘探见 docs/superpowers/specs/
// 2026-09-02-tdlib-worker-survey.md）。
//
// 直连路径：libentry 回调 JSON 字符串进 UI 线程 → TdClient.onReceive 在
// UI 线程 JSON.parse（重滚动实测 ~85ms）。本实现把收包与解析搬进
// workers/TdWorker.ets，跨线程投递解析好的对象，UI 侧经
// TdClient.deliverParsed 直接分发——@extra 配对、超时、handler 分发全部
// 原样留在 TdClient。
//
// 回退 = Globals.TD_WORKER_BRIDGE_ENABLED 置回 false（构造抛错时也会自动
// 落回直连）。

import { worker, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import { TdObject, TdBridge } from './TdTypes';
import { logE } from '../util/log';

interface TdWorkerEvent {
  kind: string;
  payload?: TdObject;
  head?: string;
}

interface TdWorkerCommand {
  kind: string;
  json?: string;
}

export class TdWorkerBridge implements TdBridge {
  private port: worker.ThreadWorker;
  private parsedSink: ((obj: TdObject) => void) | null = null;

  constructor() {
    this.port = new worker.ThreadWorker('entry/ets/workers/TdWorker.ets');
    this.port.onmessage = (e: MessageEvents): void => {
      const data = e.data as TdWorkerEvent;
      if (data.kind === 'recv') {
        if (this.parsedSink !== null && data.payload !== undefined) {
          this.parsedSink(data.payload);
        }
      } else if (data.kind === 'parse-error') {
        logE(`TdWorkerBridge: unparseable payload, skipped: ${data.head ?? ''}`);
      }
    };
    this.port.onerror = (err: ErrorEvent): void => {
      // worker 挂掉 = 收包线路断了。不静默：这属于 spike 要暴露的故障面。
      logE(`TdWorkerBridge worker error: ${err.message}`);
    };
  }

  // 解析对象的出口。TdBridge.init 的字符串回调在 worker 路径下不再使用，
  // Globals 装配时把这里接到 TdClient.deliverParsed。
  onParsed(sink: (obj: TdObject) => void): void {
    this.parsedSink = sink;
  }

  init(_onReceive: (json: string) => void): void {
    this.post({ kind: 'init' });
  }

  send(json: string): void {
    this.post({ kind: 'send', json: json });
  }

  // postMessage 会抛（worker 已终止 10200004 / 序列化失败 10200006）。请求发
  // 不出去时 TdClient 的超时会把对应 Promise 拒绝掉，这里只负责把原因留痕。
  private post(command: TdWorkerCommand): void {
    try {
      this.port.postMessage(command);
    } catch (e) {
      logE(`TdWorkerBridge post(${command.kind}) failed: ${e}`);
    }
  }
}
