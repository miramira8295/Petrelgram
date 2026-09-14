// 翻译瞬时状态的旁路通道。
//
// 译文本身仍然写进 MessageEntry（内容真的变了，那一行重建一次是应该的）。
// 但「翻译中」和「翻译失败」是瞬时态：它们每秒可能变好几次，尤其并发提到
// 6 之后。让它们进行 key 等于把每次状态跳动都变成一次整行重建，正是今天
// 一整天在消除的东西。所以它们不进 key，走这里直达气泡。
//
// 与 mediaThumbChannel / sendStateChannel 同构，键用 messageId：翻译请求
// 本来就是按 (chatId, messageId, editDate, lang) 定位的。
//
// ── 滑动闸（2026-09-14）─────────────────────────────────────────────────
// 旁路通道挡住了"整行重建"，但**挡不住行高变化**：「翻译中」是气泡底部多出
// 来的一行，清掉又少一行。行高一变，List 就得重排整个可视窗口。真机上滑动
// 时网络请求陆续回来，气泡"长高又缩回"（用户原话：「滑动期间气泡还是会动，
// 底下的 loading 状态会改变气泡高度」）。同一时段的 Frame trace 里，卡顿帧
// 的 Measure[List] 有 38 次，而 Repeat 的数据更新只有 9 次——整屏重测大多
// 不是数据引起的。
//
// 所以滑动期间**不通知已挂着的气泡**：每条消息只攒最终态，停稳后一次放出。
// 真实状态照常记账——新挂上来的行经 translationStatusFor 直接读到它，
// 那是"新行按最终高度出现"，不是"旧行改高度"，不触发重排。
// 闸由页面（TranslationDriver.bind）挂上、dispose 时摘下；可以叠多层
// （会话页叠会话页），只看最上面那层。

export type TranslationPhase = 'loading' | 'failed';

export interface TranslationStatus {
  phase: TranslationPhase;
  // 失败时的 TDLib 原始报错，成功/进行中为 ''。
  error: string;
}

type StatusListener = (s: TranslationStatus | null) => void;

interface StatusHold {
  id: number;
  // 此刻该不该攒着（通常就是"列表在不在动"）。每次状态变化时现问。
  isHeld: () => boolean;
}

export class TranslationStatusHub {
  private states: Map<number, TranslationStatus> = new Map();
  private subs: Map<number, Set<StatusListener>> = new Map();
  private holds: StatusHold[] = [];
  private nextHoldId: number = 1;
  // 闸住期间状态变过的消息。只记 id，放出时按**当下**的真实状态通知——
  // 于是"长高又缩回"在放出时只剩一次通知，给的是最终态。
  private held: Set<number> = new Set();

  publishTranslating(messageId: number): void {
    const current = this.states.get(messageId);
    if (current !== undefined && current.phase === 'loading') {
      return;
    }
    const next: TranslationStatus = { phase: 'loading', error: '' };
    this.states.set(messageId, next);
    this.emit(messageId);
  }

  publishFailed(messageId: number, error: string): void {
    const current = this.states.get(messageId);
    if (current !== undefined && current.phase === 'failed' && current.error === error) {
      return;
    }
    const next: TranslationStatus = { phase: 'failed', error };
    this.states.set(messageId, next);
    this.emit(messageId);
  }

  // 成功之后瞬时态就该消失——译文自己会从 MessageEntry 渲染出来。
  clear(messageId: number): void {
    if (!this.states.has(messageId)) {
      return;
    }
    this.states.delete(messageId);
    this.emit(messageId);
  }

  // 真实状态，不受闸影响。
  statusFor(messageId: number): TranslationStatus | null {
    return this.states.get(messageId) ?? null;
  }

  subscribe(messageId: number, cb: StatusListener): () => void {
    const existing: Set<StatusListener> | undefined = this.subs.get(messageId);
    const listeners: Set<StatusListener> = existing ?? new Set<StatusListener>();
    if (existing === undefined) {
      this.subs.set(messageId, listeners);
    }
    listeners.add(cb);
    return (): void => {
      const current = this.subs.get(messageId);
      if (current !== undefined) {
        current.delete(cb);
        if (current.size === 0) {
          this.subs.delete(messageId);
        }
      }
    };
  }

  // 挂一层闸。返回摘除函数：摘下时立刻放出攒着的变化，免得状态卡住不显示。
  pushHold(isHeld: () => boolean): () => void {
    const id: number = this.nextHoldId++;
    this.holds = [...this.holds, { id: id, isHeld: isHeld }];
    return (): void => {
      this.holds = this.holds.filter((h: StatusHold): boolean => h.id !== id);
      this.flushHeld();
    };
  }

  // 放出闸住期间攒下的变化。**无条件**放：调用方（停稳时的页面）自己决定时机。
  flushHeld(): void {
    if (this.held.size === 0) {
      return;
    }
    const ids: number[] = Array.from(this.held);
    this.held = new Set<number>();
    for (const id of ids) {
      this.deliver(id, this.states.get(id) ?? null);
    }
  }

  // 攒着没放的消息条数（诊断 / 单测）。
  heldCount(): number {
    return this.held.size;
  }

  private emit(messageId: number): void {
    const top: StatusHold | undefined =
      this.holds.length > 0 ? this.holds[this.holds.length - 1] : undefined;
    if (top !== undefined && top.isHeld()) {
      const next: Set<number> = new Set<number>(this.held);
      next.add(messageId);
      this.held = next;
      return;
    }
    this.deliver(messageId, this.states.get(messageId) ?? null);
  }

  private deliver(messageId: number, next: TranslationStatus | null): void {
    const listeners = this.subs.get(messageId);
    if (listeners !== undefined) {
      listeners.forEach((cb: StatusListener): void => cb(next));
    }
  }
}

// 全进程一份。下面这组函数的签名与加闸之前完全一致，调用方不用改。
const hub: TranslationStatusHub = new TranslationStatusHub();

export function publishTranslating(messageId: number): void {
  hub.publishTranslating(messageId);
}

export function publishTranslationFailed(messageId: number, error: string): void {
  hub.publishFailed(messageId, error);
}

export function clearTranslationStatus(messageId: number): void {
  hub.clear(messageId);
}

export function translationStatusFor(messageId: number): TranslationStatus | null {
  return hub.statusFor(messageId);
}

export function subscribeTranslationStatus(
  messageId: number, cb: (s: TranslationStatus | null) => void): () => void {
  return hub.subscribe(messageId, cb);
}

export function pushTranslationStatusHold(isHeld: () => boolean): () => void {
  return hub.pushHold(isHeld);
}

export function flushHeldTranslationStatus(): void {
  hub.flushHeld();
}
