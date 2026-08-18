// 翻译瞬时状态的旁路通道。
//
// 译文本身仍然写进 MessageEntry（内容真的变了，那一行重建一次是应该的）。
// 但「翻译中」和「翻译失败」是瞬时态：它们每秒可能变好几次，尤其并发提到
// 6 之后。让它们进行 key 等于把每次状态跳动都变成一次整行重建，正是今天
// 一整天在消除的东西。所以它们不进 key，走这里直达气泡。
//
// 与 mediaThumbChannel / sendStateChannel 同构，键用 messageId：翻译请求
// 本来就是按 (chatId, messageId, editDate, lang) 定位的。

export type TranslationPhase = 'loading' | 'failed';

export interface TranslationStatus {
  phase: TranslationPhase;
  // 失败时的 TDLib 原始报错，成功/进行中为 ''。
  error: string;
}

const states: Map<number, TranslationStatus> = new Map();
const subs: Map<number, Set<(s: TranslationStatus | null) => void>> = new Map();

function emit(messageId: number, next: TranslationStatus | null): void {
  const listeners = subs.get(messageId);
  if (listeners !== undefined) {
    listeners.forEach((cb: (s: TranslationStatus | null) => void): void => cb(next));
  }
}

export function publishTranslating(messageId: number): void {
  const current = states.get(messageId);
  if (current !== undefined && current.phase === 'loading') {
    return;
  }
  const next: TranslationStatus = { phase: 'loading', error: '' };
  states.set(messageId, next);
  emit(messageId, next);
}

export function publishTranslationFailed(messageId: number, error: string): void {
  const current = states.get(messageId);
  if (current !== undefined && current.phase === 'failed' && current.error === error) {
    return;
  }
  const next: TranslationStatus = { phase: 'failed', error };
  states.set(messageId, next);
  emit(messageId, next);
}

// 成功之后瞬时态就该消失——译文自己会从 MessageEntry 渲染出来。
export function clearTranslationStatus(messageId: number): void {
  if (!states.has(messageId)) {
    return;
  }
  states.delete(messageId);
  emit(messageId, null);
}

export function translationStatusFor(messageId: number): TranslationStatus | null {
  return states.get(messageId) ?? null;
}

export function subscribeTranslationStatus(
  messageId: number, cb: (s: TranslationStatus | null) => void): () => void {
  let listeners = subs.get(messageId);
  if (listeners === undefined) {
    listeners = new Set<(s: TranslationStatus | null) => void>();
    subs.set(messageId, listeners);
  }
  listeners.add(cb);
  return (): void => {
    const current = subs.get(messageId);
    if (current !== undefined) {
      current.delete(cb);
      if (current.size === 0) {
        subs.delete(messageId);
      }
    }
  };
}
