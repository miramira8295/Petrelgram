// 只播一次的动画（骰子/老虎机）播过没有（2026-10-10）。
//
// 【为什么要记】播放组件挂在会复用的消息行里：滑出去再滑回来、行被复用、消息数据一更新，
// 组件都会从头再来——骰子就会过几秒又重摇一遍。Telegram 的做法是只在第一次出现时摇，
// 之后一律直接显示结果。键由调用方给（会话 + 消息 id），只在进程内记。
const MAX_KEYS: number = 500;
// Set 按插入顺序迭代，第一个就是最早的。
const played: Set<string> = new Set<string>();

export function playedOnce(key: string): boolean {
  return key !== '' && played.has(key);
}

export function markPlayedOnce(key: string): void {
  if (key === '' || played.has(key)) {
    return;
  }
  if (played.size >= MAX_KEYS) {
    const oldest: string | undefined = played.values().next().value;
    if (oldest !== undefined) {
      played.delete(oldest);
    }
  }
  played.add(key);
}

export function resetPlayedOnceForTest(): void {
  played.clear();
}
