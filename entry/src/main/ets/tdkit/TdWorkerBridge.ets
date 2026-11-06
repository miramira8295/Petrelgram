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
import { OrderSnapshot } from '../store/chatListOrder';

interface TdWorkerEvent {
  kind: string;
  payload?: TdObject;
  // kind==='batch'：一个投递窗口内的多条，顺序即到达顺序。
  items?: TdObject[];
  // kind==='order'：worker 侧影子排序（第二层 B2）。
  lists?: OrderSnapshot[];
  head?: string;
}

interface TdWorkerCommand {
  kind: string;
  json?: string;
  request?: TdObject;
}

export class TdWorkerBridge implements TdBridge {
  private port: worker.ThreadWorker;
  private parsedSink: ((obj: TdObject) => void) | null = null;
  private orderSink: ((lists: OrderSnapshot[]) => void) | null = null;

  constructor() {
    this.port = new worker.ThreadWorker('entry/ets/workers/TdWorker.ets');
    this.port.onmessage = (e: MessageEvents): void => {
      const data = e.data as TdWorkerEvent;
      if (data.kind === 'recv') {
        // 响应（带 @extra）走单条通道，不吃批窗口。
        if (this.parsedSink !== null && data.payload !== undefined) {
          this.parsedSink(data.payload);
        }
      } else if (data.kind === 'batch') {
        // 批内顺序必须按原样逐条下发：@extra 配对与 handler 分发都依赖到达序。
        const items = data.items;
        if (this.parsedSink !== null && items !== undefined) {
          for (const item of items) {
            this.parsedSink(item);
          }
        }
      } else if (data.kind === 'order') {
        if (this.orderSink !== null && data.lists !== undefined) {
          this.orderSink(data.lists);
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

  // 影子排序索引的出口（第二层 B2）。没有订阅方时这些事件直接丢掉。
  onOrder(sink: (lists: OrderSnapshot[]) => void): void {
    this.orderSink = sink;
  }

  init(_onReceive: (json: string) => void): void {
    this.post({ kind: 'init' });
  }

  // 接口要求的字符串路径。TdClient 一旦发现本桥有 sendObject 就不会走这里，
  // 保留它是为了 TdBridge 的实现完整（直连语义下 send 仍是唯一入口）。
  send(json: string): void {
    this.post({ kind: 'send', json: json });
  }

  // 发送侧的序列化搬进 worker：UI 线程只做浅拷贝 + 投递，stringify 在
  // TdWorker 里、tdSend 之前完成。
  sendObject(request: TdObject): void {
    this.post({ kind: 'send', request: request });
  }

  // 销毁也走同一条队列（见 TdTypes.TdBridge.destroy 的说明）。post 失败时
  // worker 已经不在了，那边的 td* 调用同样不可能再发生。
  destroy(): void {
    this.post({ kind: 'destroy' });
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
