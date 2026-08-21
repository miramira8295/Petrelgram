import { TdObject, TdRequest, TdError, TdBridge } from './TdTypes';
import { logE } from '../util/log';

export const DEFAULT_TIMEOUT_MS: number = 15000;

export interface TimerFns {
  setTimeout: (cb: () => void, ms: number) => number;
  clearTimeout: (id: number) => void;
}

interface Pending {
  resolve: (value: TdObject) => void;
  reject: (reason: TdError) => void;
  timerId: number;
}

export class TdClient {
  private bridge: TdBridge;
  private timer: TimerFns;
  private extraSeq: number = 0;
  private pending: Map<string, Pending> = new Map();
  private handlers: Map<string, Array<(update: TdObject) => void>> = new Map();

  constructor(bridge: TdBridge, timer?: TimerFns) {
    this.bridge = bridge;
    this.timer = timer ?? {
      setTimeout: (cb: () => void, ms: number): number => setTimeout(cb, ms),
      clearTimeout: (id: number): void => clearTimeout(id)
    };
  }

  start(): void {
    this.bridge.init((json: string) => this.onReceive(json));
  }

  send(request: TdRequest, timeoutMs: number = DEFAULT_TIMEOUT_MS): Promise<TdObject> {
    this.extraSeq += 1;
    const extra = `req_${this.extraSeq}`;
    const requestJson = JSON.stringify(request);
    const requestObj = JSON.parse(requestJson) as TdObject;
    requestObj['@extra'] = extra;
    return new Promise<TdObject>((resolve, reject) => {
      const timerId = this.timer.setTimeout(() => {
        if (this.pending.has(extra)) {
          this.pending.delete(extra);
          reject(new TdError(-1, 'request timeout'));
        }
      }, timeoutMs);
      this.pending.set(extra, { resolve, reject, timerId });
      this.bridge.send(JSON.stringify(requestObj));
    });
  }

  onUpdate(type: string, handler: (update: TdObject) => void): () => void {
    const list = this.handlers.get(type) ?? [];
    this.handlers.set(type, [...list, handler]);
    return (): void => {
      const cur = this.handlers.get(type) ?? [];
      this.handlers.set(type, cur.filter((h: (u: TdObject) => void) => h !== handler));
    };
  }

  dispose(): void {
    for (const entry of this.pending.values()) {
      this.timer.clearTimeout(entry.timerId);
      entry.reject(new TdError(-1, 'TDLib account session changed'));
    }
    this.pending.clear();
    this.handlers.clear();
  }

  private onReceive(json: string): void {
    let obj: TdObject;
    try {
      obj = JSON.parse(json) as TdObject;
    } catch (e) {
      logE(`TdClient: unparseable payload, skipped: ${json.substring(0, 120)}`);
      return;
    }
    const extra = obj['@extra'] as string | undefined;
    if (extra !== undefined && this.pending.has(extra)) {
      const entry = this.pending.get(extra)!;
      this.pending.delete(extra);
      this.timer.clearTimeout(entry.timerId);
      if (obj['@type'] === 'error') {
        entry.reject(new TdError(obj['code'] as number, obj['message'] as string));
      } else {
        entry.resolve(obj);
      }
      return;
    }
    const type = obj['@type'] as string;
    const list = this.handlers.get(type);
    if (list) {
      for (const handler of list) {
        try {
          handler(obj);
        } catch (e) {
          logE(`TdClient: handler for ${type} threw, skipped: ${e}`);
        }
      }
    }
  }
}
