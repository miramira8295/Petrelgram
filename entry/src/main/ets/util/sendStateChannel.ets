// 发送状态的旁路通道。
//
// sendState 原本进行 key，于是"时钟 → 对号"这一步会把整行当成新 item 销毁
// 重建。而发送成功时 TDLib 同时把临时 id 换成真实 id（见 MessageEntry.rowId），
// 两者叠在一起，界面上就是发完消息"闪一下"。
//
// 与 mediaThumbChannel / mediaProgressChannel 同构，键用 rowId：它跨过
// "临时 id → 真实 id"那次替换保持不变，正是这个通道要的稳定身份。
const states: Map<number, string> = new Map();
const subs: Map<number, Set<(state: string) => void>> = new Map();

// 状态没变就不通知——否则每次 store 更新都会把订阅者叫醒一遍。
export function publishSendState(rowId: number, state: string): void {
  if (rowId === 0 || state === '' || states.get(rowId) === state) {
    return;
  }
  states.set(rowId, state);
  const listeners = subs.get(rowId);
  if (listeners !== undefined) {
    listeners.forEach((cb: (state: string) => void): void => cb(state));
  }
}

export function sendStateFor(rowId: number): string {
  return states.get(rowId) ?? '';
}

export function subscribeSendState(rowId: number, cb: (state: string) => void): () => void {
  let listeners = subs.get(rowId);
  if (listeners === undefined) {
    listeners = new Set<(state: string) => void>();
    subs.set(rowId, listeners);
  }
  listeners.add(cb);
  return (): void => {
    const current = subs.get(rowId);
    if (current !== undefined) {
      current.delete(cb);
      if (current.size === 0) {
        subs.delete(rowId);
      }
    }
  };
}
