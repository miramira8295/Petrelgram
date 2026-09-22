// One channel per ChatPage. Only the target row receives focus updates; a
// timeline-wide observable would wake every mounted message on each pulse.
export class BubbleFocusChannel {
  private rowId: number = 0;
  private strength: number = 0;
  private listeners: Map<number, Set<(strength: number) => void>> = new Map();

  value(rowId: number): number {
    return rowId === this.rowId ? this.strength : 0;
  }

  set(rowId: number, strength: number): void {
    if (this.rowId !== rowId) {
      const previous: number = this.rowId;
      this.rowId = rowId;
      this.strength = 0;
      this.emit(previous, 0);
    }
    this.strength = strength;
    this.emit(rowId, strength);
  }

  clear(): void {
    this.set(0, 0);
  }

  subscribe(rowId: number, callback: (strength: number) => void): () => void {
    let callbacks: Set<(strength: number) => void> | undefined = this.listeners.get(rowId);
    if (callbacks === undefined) {
      callbacks = new Set();
      this.listeners.set(rowId, callbacks);
    }
    callbacks.add(callback);
    callback(this.value(rowId));
    return (): void => {
      const current: Set<(strength: number) => void> | undefined = this.listeners.get(rowId);
      if (current !== undefined) {
        current.delete(callback);
        if (current.size === 0) {
          this.listeners.delete(rowId);
        }
      }
    };
  }

  private emit(rowId: number, strength: number): void {
    this.listeners.get(rowId)?.forEach((callback: (strength: number) => void): void => {
      callback(strength);
    });
  }
}

// 落点脉冲的幅度。两处气泡实现（MessageBubble / LightweightPlainTextBubble，
// 各两个分支）共用，改一处四处同步。
//
// 【为什么从 0.018 / 0.10 抬上来】原来那两个数**从未在真机上被看见过**：
// KEY_POWER_EFFECT_REPLY 默认关，整段脉冲连起步都没有（2026-09-22 探针实测
// rise=0/settle=0），所以它们是没经过实机校准的初值。开关改成默认开之后需要一个
// 真的看得见的幅度：1.8% 的缩放在一行气泡上只有一两个像素，brightness 1.10 压在
// 深色气泡（#232E3C 一档）上只把它抬到 #263341，肉眼分不出来。历史上这条线索
// 另有一个视口高亮矩形做主视觉，矩形移除之后就只剩这两个量了。
//
// 上限的约束：缩放不能大到把相邻行挤开（气泡是 transform，不占布局，但视觉上会
// 压进上下两行的留白），亮度不能大到让浅色/强调色气泡过曝。
export const JUMP_FOCUS_SCALE: number = 0.03;
export const JUMP_FOCUS_BRIGHTNESS: number = 0.35;
