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
  deadlineMs: number;
}

export class TdClient {
  private bridge: TdBridge;
  private timer: TimerFns;
  private extraSeq: number = 0;
  private pending: Map<string, Pending> = new Map();
  private handlers: Map<string, Array<(update: TdObject) => void>> = new Map();
  // One timer services every pending request. The old per-request timers made
  // clearTimeout a measurable NAPI hotspot during TDLib response bursts.
  private timeoutTimerId: number = -1;
  private timeoutDeadlineMs: number = 0;

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
    // TD requests are flat at the top level; nested values are never modified.
    // A shallow copy protects the caller's object without the former
    // stringify -> parse -> mutate -> stringify round-trip on the UI thread.
    const requestObj: TdObject = {};
    for (const key of Object.keys(request)) {
      requestObj[key] = request[key];
    }
    requestObj['@extra'] = extra;
    return new Promise<TdObject>((resolve, reject) => {
      const deadlineMs: number = Date.now() + Math.max(0, timeoutMs);
      this.pending.set(extra, { resolve, reject, deadlineMs });
      this.scheduleTimeoutTimer();
      this.bridge.send(JSON.stringify(requestObj));
    });
  }

  private clearTimeoutTimer(): void {
    if (this.timeoutTimerId !== -1) {
      this.timer.clearTimeout(this.timeoutTimerId);
      this.timeoutTimerId = -1;
      this.timeoutDeadlineMs = 0;
    }
  }

  private scheduleTimeoutTimer(): void {
    let nearest: number = 0;
    for (const entry of this.pending.values()) {
      if (nearest === 0 || entry.deadlineMs < nearest) {
        nearest = entry.deadlineMs;
      }
    }
    if (nearest === 0) {
      this.clearTimeoutTimer();
      return;
    }
    if (this.timeoutTimerId !== -1 && this.timeoutDeadlineMs <= nearest) {
      return;
    }
    this.clearTimeoutTimer();
    this.timeoutDeadlineMs = nearest;
    this.timeoutTimerId = this.timer.setTimeout((): void => {
      // A timer callback represents reaching the deadline it was scheduled
      // for. This also keeps deterministic/manual timers useful in unit tests.
      const expiredThrough: number = this.timeoutDeadlineMs;
      this.timeoutTimerId = -1;
      this.timeoutDeadlineMs = 0;
      const expired: Pending[] = [];
      const expiredExtras: string[] = [];
      this.pending.forEach((entry: Pending, extra: string): void => {
        if (entry.deadlineMs <= expiredThrough) {
          expiredExtras.push(extra);
        }
      });
      for (const extra of expiredExtras) {
        const entry = this.pending.get(extra);
        if (entry !== undefined) {
          this.pending.delete(extra);
          expired.push(entry);
        }
      }
      for (const entry of expired) {
        entry.reject(new TdError(-1, 'request timeout'));
      }
      this.scheduleTimeoutTimer();
    }, Math.max(0, nearest - Date.now()));
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
    this.clearTimeoutTimer();
    for (const entry of this.pending.values()) {
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
      let scheduledDeadlineStillNeeded: boolean = false;
      if (entry.deadlineMs <= this.timeoutDeadlineMs) {
        for (const pending of this.pending.values()) {
          if (pending.deadlineMs <= this.timeoutDeadlineMs) {
            scheduledDeadlineStillNeeded = true;
            break;
          }
        }
      }
      if (this.pending.size === 0 ||
        (entry.deadlineMs <= this.timeoutDeadlineMs && !scheduledDeadlineStillNeeded)) {
        this.clearTimeoutTimer();
        this.scheduleTimeoutTimer();
      }
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
