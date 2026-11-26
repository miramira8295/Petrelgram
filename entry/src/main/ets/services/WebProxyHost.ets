import { webview } from '@kit.ArkWeb';
import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logI, logW } from '../util/log';

// TDLib 1.8.71 原生 proxyTypeWeb 载体管理器。
//
// TDLib 负责构造 bridge URL、管理重连、obfuscated2/MTProto 封装以及 ping/test 临时载体；
// App 这边只做三件薄事：
//   1. 订阅 updateWebProxyCarrierOpened / Data / Closed，按 carrier.id 维护隐藏 WebView 列表；
//   2. 把页面通过 window[bridge_object_name].postMessage() 发来的文本/二进制转给
//      processWebProxyCarrierMessage；
//   3. 把 updateWebProxyCarrierData 按序投递给页面 onmessage，并在加载失败或渲染进程
//      退出时调用 reportWebProxyCarrierError。
//
// 安全约束（对齐 td_api.tl webProxyCarrier 说明）：
//   · 永不在日志或错误消息里输出 carrier.url；
//   · 仅在顶层文档且精确匹配 carrier.origin 时注入只读桥接对象；
//   · 收到 updateWebProxyCarrierClosed 后立即忽略页面后续消息；若页面曾发过消息，
//     先向 onmessage 投递 {"t":"close"} 并在 200ms 后销毁 WebView，否则立即销毁。

export const KEY_WEB_PROXY_CARRIERS: string = 'tdWebProxyCarriers';

export interface WebProxyCarrierSpec {
  id: number;
  proxyId: number;
  url: string;
  origin: string;
  pathPrefix: string;
  bridgeObjectName: string;
  isTemporary: boolean;
}

interface QueuedDelivery {
  kind: 'binary' | 'text';
  payload: string;
}

interface CarrierRecord {
  spec: WebProxyCarrierSpec;
  client: TdClient;
  controller: webview.WebviewController | null;
  hasSentMessage: boolean;
  closed: boolean;
  errorReported: boolean;
  queue: QueuedDelivery[];
  pumping: boolean;
  closeTimer: number;
}

const MAX_DELIVERY_QUEUE: number = 512;
const CLOSE_GRACE_MS: number = 200;

class TdWebProxyCarrierManager {
  private carriers: Map<number, CarrierRecord> = new Map();
  private unsubByClient: Map<TdClient, (() => void)[]> = new Map();

  attach(client: TdClient): void {
    if (this.unsubByClient.has(client)) {
      return;
    }
    const offs: (() => void)[] = [
      client.onUpdate('updateWebProxyCarrierOpened', (u: TdObject): void => {
        this.onCarrierOpened(client, u);
      }),
      client.onUpdate('updateWebProxyCarrierData', (u: TdObject): void => {
        this.onCarrierData(u);
      }),
      client.onUpdate('updateWebProxyCarrierClosed', (u: TdObject): void => {
        this.onCarrierClosed(u);
      })
    ];
    this.unsubByClient.set(client, offs);
  }

  detach(client: TdClient): void {
    const offs: (() => void)[] | undefined = this.unsubByClient.get(client);
    if (offs !== undefined) {
      for (const off of offs) {
        off();
      }
      this.unsubByClient.delete(client);
    }
    let removed: boolean = false;
    const toRemove: number[] = [];
    this.carriers.forEach((record: CarrierRecord, id: number): void => {
      if (record.client === client) {
        toRemove.push(id);
      }
    });
    for (const id of toRemove) {
      const record: CarrierRecord | undefined = this.carriers.get(id);
      if (record !== undefined) {
        this.disposeRecord(record);
        this.carriers.delete(id);
        removed = true;
      }
    }
    if (removed) {
      this.publishSpecs();
    }
  }

  attachController(carrierId: number, controller: webview.WebviewController): void {
    const record: CarrierRecord | undefined = this.carriers.get(carrierId);
    if (record === undefined || record.closed) {
      return;
    }
    record.controller = controller;
    this.pump(record);
  }

  detachController(carrierId: number): void {
    const record: CarrierRecord | undefined = this.carriers.get(carrierId);
    if (record === undefined) {
      return;
    }
    record.controller = null;
  }

  onPageMessage(carrierId: number, kind: string, data: string): void {
    const record: CarrierRecord | undefined = this.carriers.get(carrierId);
    if (record === undefined || record.closed) {
      return;
    }
    let message: TdObject;
    if (kind === 'text') {
      message = { '@type': 'webProxyCarrierMessageText', 'text': data };
    } else if (kind === 'binary') {
      message = { '@type': 'webProxyCarrierMessageBinary', 'data': data };
    } else {
      return;
    }
    record.hasSentMessage = true;
    const req: TdRequest = { '@type': 'processWebProxyCarrierMessage' };
    req['carrier_id'] = carrierId;
    req['message'] = message;
    record.client.send(req).catch((err: TdError): void => {
      logW(`[WebProxy] processWebProxyCarrierMessage(${carrierId}) failed: ${err.message}`);
    });
  }

  onPageError(carrierId: number, errorKind: string, message: string = ''): void {
    const record: CarrierRecord | undefined = this.carriers.get(carrierId);
    if (record === undefined || record.closed || record.errorReported) {
      return;
    }
    record.errorReported = true;
    let errorObj: TdObject;
    if (errorKind === 'terminated') {
      errorObj = { '@type': 'webProxyCarrierErrorTerminated' };
    } else if (errorKind === 'refused') {
      errorObj = { '@type': 'webProxyCarrierErrorRefused' };
    } else if (errorKind === 'unsupported') {
      errorObj = { '@type': 'webProxyCarrierErrorUnsupported' };
    } else if (errorKind === 'paused') {
      errorObj = { '@type': 'webProxyCarrierErrorPaused' };
    } else {
      errorObj = { '@type': 'webProxyCarrierErrorLoadFailed', 'message': message };
    }
    logW(`[WebProxy] carrier error id=${carrierId} kind=${errorKind}`
      + (message.length > 0 ? ` msg=${message}` : ''));
    const req: TdRequest = { '@type': 'reportWebProxyCarrierError' };
    req['carrier_id'] = carrierId;
    req['error'] = errorObj;
    record.client.send(req).catch((err: TdError): void => {
      logW(`[WebProxy] reportWebProxyCarrierError(${carrierId}) failed: ${err.message}`);
    });
  }

  private onCarrierOpened(client: TdClient, u: TdObject): void {
    const carrier = u['carrier'] as TdObject | undefined;
    if (carrier === undefined) {
      return;
    }
    const id: number = (carrier['id'] as number | undefined) ?? 0;
    const proxyId: number = (carrier['proxy_id'] as number | undefined) ?? 0;
    const url: string = (carrier['url'] as string | undefined) ?? '';
    const origin: string = (carrier['origin'] as string | undefined) ?? '';
    const pathPrefix: string = (carrier['path_prefix'] as string | undefined) ?? '';
    const bridgeObjectName: string = (carrier['bridge_object_name'] as string | undefined) ?? 'TelegramWebProxy';
    const isTemporary: boolean = carrier['is_temporary'] === true;
    if (id <= 0 || url.length === 0 || origin.length === 0) {
      logW(`[WebProxy] ignoring malformed carrier id=${id}`);
      return;
    }
    const existing: CarrierRecord | undefined = this.carriers.get(id);
    if (existing !== undefined) {
      this.disposeRecord(existing);
    }
    const spec: WebProxyCarrierSpec = {
      id: id,
      proxyId: proxyId,
      url: url,
      origin: origin,
      pathPrefix: pathPrefix,
      bridgeObjectName: bridgeObjectName.length > 0 ? bridgeObjectName : 'TelegramWebProxy',
      isTemporary: isTemporary
    };
    const record: CarrierRecord = {
      spec: spec,
      client: client,
      controller: null,
      hasSentMessage: false,
      closed: false,
      errorReported: false,
      queue: [],
      pumping: false,
      closeTimer: -1
    };
    this.carriers.set(id, record);
    logI(`[WebProxy] carrier opened id=${id} proxy=${proxyId} temp=${isTemporary} origin=${origin}`);
    this.publishSpecs();
  }

  private onCarrierData(u: TdObject): void {
    const carrierId: number = (u['carrier_id'] as number | undefined) ?? 0;
    const data: string = (u['data'] as string | undefined) ?? '';
    const record: CarrierRecord | undefined = this.carriers.get(carrierId);
    if (record === undefined || record.closed || data.length === 0) {
      return;
    }
    if (record.queue.length >= MAX_DELIVERY_QUEUE) {
      logW(`[WebProxy] carrier ${carrierId} delivery queue overflow, reporting load_failed`);
      this.onPageError(carrierId, 'load_failed', 'delivery queue overflow');
      return;
    }
    record.queue.push({ kind: 'binary', payload: data });
    this.pump(record);
  }

  private onCarrierClosed(u: TdObject): void {
    const carrierId: number = (u['carrier_id'] as number | undefined) ?? 0;
    const record: CarrierRecord | undefined = this.carriers.get(carrierId);
    if (record === undefined || record.closed) {
      return;
    }
    record.closed = true;
    record.queue = [];
    logI(`[WebProxy] carrier closed id=${carrierId} sent=${record.hasSentMessage}`);
    if (record.hasSentMessage && record.controller !== null) {
      const controller: webview.WebviewController = record.controller;
      const closeScript: string =
        'window.__petrelTdWebProxyDeliver&&window.__petrelTdWebProxyDeliver(\'text\',\'{"t":"close"}\')';
      controller.runJavaScript(closeScript).catch((): void => {});
      record.closeTimer = setTimeout((): void => {
        record.closeTimer = -1;
        this.removeCarrier(carrierId);
      }, CLOSE_GRACE_MS);
    } else {
      this.removeCarrier(carrierId);
    }
  }

  private removeCarrier(carrierId: number): void {
    const record: CarrierRecord | undefined = this.carriers.get(carrierId);
    if (record === undefined) {
      return;
    }
    this.disposeRecord(record);
    this.carriers.delete(carrierId);
    this.publishSpecs();
  }

  private disposeRecord(record: CarrierRecord): void {
    record.closed = true;
    record.queue = [];
    record.controller = null;
    if (record.closeTimer >= 0) {
      clearTimeout(record.closeTimer);
      record.closeTimer = -1;
    }
  }

  private pump(record: CarrierRecord): void {
    if (record.pumping || record.closed) {
      return;
    }
    const controller: webview.WebviewController | null = record.controller;
    if (controller === null) {
      return;
    }
    const next: QueuedDelivery | undefined = record.queue.shift();
    if (next === undefined) {
      return;
    }
    record.pumping = true;
    const script: string = 'window.__petrelTdWebProxyDeliver&&window.__petrelTdWebProxyDeliver('
      + JSON.stringify(next.kind) + ',' + JSON.stringify(next.payload) + ')';
    controller.runJavaScript(script).then((): void => {
      record.pumping = false;
      this.pump(record);
    }).catch((err: Error): void => {
      record.pumping = false;
      if (!record.closed) {
        logW(`[WebProxy] deliver to carrier ${record.spec.id} failed: ${err.message}`);
        this.onPageError(record.spec.id, 'load_failed', 'js delivery failed');
      }
    });
  }

  private publishSpecs(): void {
    const list: WebProxyCarrierSpec[] = [];
    this.carriers.forEach((record: CarrierRecord): void => {
      list.push(record.spec);
    });
    AppStorage.setOrCreate<WebProxyCarrierSpec[]>(KEY_WEB_PROXY_CARRIERS, list);
  }
}

export const webProxyCarrierManager: TdWebProxyCarrierManager = new TdWebProxyCarrierManager();

export function attachWebProxyCarrier(client: TdClient): void {
  webProxyCarrierManager.attach(client);
}

export function detachWebProxyCarrier(client: TdClient): void {
  webProxyCarrierManager.detach(client);
}
