// 聊天内搜索的翻页决策。
//
// 结果按"新 → 旧"排列，∧ 往更旧走（下标 +1），∨ 往更新走（下标 -1）。窗口
// 一次取 50 条，翻到尽头时要不要再取一页，取决于已加载数和服务端给的总数。
//
// 抽成纯函数是因为这几个边界最容易错：下标越界、总数为 0、已加载等于总数、
// 空结果集。它们在页面里是三个 if 混在异步回调之间，单独测才看得清。

export const SEARCH_STAY: string = 'stay';       // 什么都不做
export const SEARCH_JUMP: string = 'jump';       // 跳到已加载的某一条
export const SEARCH_FETCH: string = 'fetch';     // 先取下一页，到货后跳

export interface SearchStep {
  action: string;
  // SEARCH_JUMP 时是目标下标；SEARCH_FETCH 时是到货后要跳的下标。
  index: number;
  // SEARCH_FETCH 时是"从这条消息往更旧翻"的锚点，其余为 0。
  fromMessageId: number;
}

function stay(): SearchStep {
  return { action: SEARCH_STAY, index: 0, fromMessageId: 0 };
}

// ∧：更旧的那一条。
export function stepOlder(
  loaded: number[], currentIndex: number, total: number
): SearchStep {
  const next: number = currentIndex + 1;
  if (next < loaded.length) {
    return { action: SEARCH_JUMP, index: next, fromMessageId: 0 };
  }
  // 已加载的到头了：还有没取回来的才继续翻页。loaded 为空时无锚点可用。
  if (loaded.length > 0 && loaded.length < total) {
    return { action: SEARCH_FETCH, index: next, fromMessageId: loaded[loaded.length - 1] };
  }
  return stay();
}

// ∨：更新的那一条。永远不需要翻页——更新的结果都在已加载窗口里。
export function stepNewer(currentIndex: number): SearchStep {
  return currentIndex > 0
    ? { action: SEARCH_JUMP, index: currentIndex - 1, fromMessageId: 0 }
    : stay();
}

// 计数显示："第几条 / 共几条"。结果按新→旧排，所以下标 0 是最新的那条，
// 显示成第 total 条。
export function searchCounterText(currentIndex: number, total: number): string {
  if (total <= 0) {
    return '';
  }
  return `${total - currentIndex} / ${total}`;
}
