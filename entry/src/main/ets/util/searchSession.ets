// 搜索会话的临时记忆（issue #129）。
//
// 搜索页是整页 router 页、盖在页签栈上面；点开一条结果时必须把它弹掉，否则用户
// 看到的是「点了没反应」（会话被推进的是页签栈）。页一弹，关键词和分页就没了，
// 从会话返回等于从头再搜一次。
//
// 这里只记「关键词 + 当前分页」，下次打开搜索页自动填回去并重跑一次检索——结果
// 本身由 TDLib 缓存，重跑基本是瞬间的。不记结果列表：那些条目挂着实时订阅
// （已读数、在线态），存快照只会显示过期数据。
//
// 时效之外就当没记：隔了半天再点搜索，还看到上午那次的关键词是打扰。
export const SEARCH_SESSION_TTL_MS: number = 5 * 60 * 1000;

export interface SearchSession {
  query: string;
  tab: number;
  savedAt: number;
}

let session: SearchSession | null = null;

// 只在「点开结果导致搜索页关闭」时记。点「取消」是明确要离开，见 forgetSearchSession。
export function rememberSearchSession(query: string, tab: number, nowMs: number): void {
  const trimmed: string = query.trim();
  if (trimmed === '') {
    session = null;
    return;
  }
  session = { query: query, tab: tab, savedAt: nowMs };
}

export function takeSearchSession(nowMs: number): SearchSession | null {
  if (session === null) {
    return null;
  }
  if (nowMs - session.savedAt > SEARCH_SESSION_TTL_MS) {
    session = null;
    return null;
  }
  return session;
}

export function forgetSearchSession(): void {
  session = null;
}

