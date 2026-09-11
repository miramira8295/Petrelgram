import { TdObject, TdRequest, TdError, TdBridge } from './TdTypes';
import { logE } from '../util/log';

export const DEFAULT_TIMEOUT_MS: number = 15000;

// 回调比它「计划的触发时刻」晚了多少，才算这段时间进程根本没在跑。
//
// 【为什么需要这个】deadlineMs 是墙钟（Date.now() + timeoutMs）。应用切到后台
// 后系统会冻住进程：setTimeout 停摆，墙钟照走。解冻那一刻定时器补火，看到
// 所有 deadline 都过了，就把**全部**在途请求一次判成 'request timeout'——
// TDLib 其实好好的，应答也在路上。紧接着真应答到达 deliverParsed，@extra 已经
// 不在 pending 里了，于是被静默丢弃。
//
// 真机日志（20260910，SGT-AL10）3/3 命中：每一条 request timeout 都紧跟在
// `windowStatus 3`（切后台）之后，其中一条是 getChat——对非 bot 那是离线请求，
// 读本地库，跑满 15s 运行时间不可能，只能是被这个定时器打死的。
//
// 门槛取 2s：正常 setTimeout 抖动是毫秒到几十毫秒量级（真机实测标称 16ms 的
// 跳实际 ~74ms），冻结是秒级，两者不会混。主线程被长卡顿堵住超过 2s 也会走
// 这条路——那同样是对的，那段时间我们照样没法处理应答。
export const FROZEN_SLACK_MS: number = 2000;

// 超时是**我们自己**判的，不是 TDLib 的答复码（TDLib 的错误码是正数）。调用方
// 靠它把「没答复」和「答复说不行」分开——前者请求多半已经生效了。
export const TIMEOUT_ERROR_CODE: number = -1;

export interface TimerFns {
  setTimeout: (cb: () => void, ms: number) => number;
  clearTimeout: (id: number) => void;
  // 可选，缺省走 Date.now。单测靠它把「冻结」演出来：手动定时器能决定回调何时
  // 跑，但决定不了跑的时候墙钟是几点，而冻结判据问的正是后者。
  now?: () => number;
}

interface Pending {
  resolve: (value: TdObject) => void;
  reject: (reason: TdError) => void;
  deadlineMs: number;
  // 冻结之后要按**这个请求自己的**窗口重新起算，所以得记着它。
  timeoutMs: number;
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

  private nowMs(): number {
    const clock: (() => number) | undefined = this.timer.now;
    return clock !== undefined ? clock() : Date.now();
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
      const window: number = Math.max(0, timeoutMs);
      const deadlineMs: number = this.nowMs() + window;
      this.pending.set(extra, { resolve, reject, deadlineMs, timeoutMs: window });
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
      // 冻结检测必须排在清账之前：这段墙钟时间进程没在跑，谁都不该因此超时。
      //
      // 【为什么是「重新起算一整个窗口」而不是「按超射量平移」】能量到的超射
      // 是 now - expiredThrough，它比真实的冻结时长**少了整整一个 timeoutMs**
      // （定时器是在 deadline 才计划触发的，冻结从哪一刻开始我们看不见）。按它
      // 平移，那种「刚发出去就被冻住」的请求平移完 deadline 恰好还是现在，原地
      // 判死——那正是要修的那一类。宁可宽：真挂死的请求在解冻后照样跑满一个
      // 窗口再超时。
      if (this.pending.size > 0 && this.nowMs() - expiredThrough > FROZEN_SLACK_MS) {
        const resumedAt: number = this.nowMs();
        this.pending.forEach((entry: Pending): void => {
          entry.deadlineMs = resumedAt + entry.timeoutMs;
        });
        this.scheduleTimeoutTimer();
        return;
      }
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
        entry.reject(new TdError(TIMEOUT_ERROR_CODE, 'request timeout'));
      }
      this.scheduleTimeoutTimer();
    }, Math.max(0, nearest - this.nowMs()));
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
    this.deliverParsed(obj);
  }

  // Worker 桥的投递口（A 批 1）：对象已在 worker 线程解析完，跳过本线程的
  // JSON.parse；@extra 配对、超时清账、handler 分发与字符串路径完全一致。
  deliverParsed(obj: TdObject): void {
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
