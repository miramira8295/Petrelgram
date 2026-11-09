// 栈还没注册时，把这次跳转**挂起**，等对应页签的栈注册好再重放。
//
// 【为什么需要它】迁到 HdsNavDestination 之后，ChatPage / GlobalSearchPage /
// 四张资料页都已从 main_pages.json 摘出。而四个 nav 漏斗里"栈没注册"那一支还
// 写着 `router.pushUrl(<那些页>)`——那条路现在**必然失败**，而且失败方式是系统
// 弹一句"无法识别的链接"，用户会以为是链接坏了。
//
// 真实事故（2026-09-14 用户报「自己的通知会显示无法识别的链接」）：
//   点通知冷启动 → EntryAbility 写下 pendingNotifyChatId
//   → Index 在 stage 变 Ready 的**那一拍**就 consumeNotifyChat()
//   → 但 MainScreen 只画在 Ready 分支里，这一拍还没挂树
//   → ChatListPage.registerStack('chat') 还没跑
//   → navigateToChat 落进回退 → pushUrl('pages/chat/ChatPage') → 必败
// 而 pendingNotifyChatId 在消费时已清零，没有第二次机会：会话永远打不开。
//
// 挂起而不是原地失败，正好补上这个时间差。纯数据，可单测。

export interface PendingNav {
  // 等哪个页签的栈（TabKind 的字符串形式；这里不引 navStacks 以免绕回依赖）。
  tab: string;
  // 去重键。同一个键只保留最后一次——用户连点两条通知，该开的是后点的那条。
  kind: string;
  dest: string;
  params: Record<string, Object>;
  origin: string;
}

// 挂起上限。正常情形最多一两条（冷启动那一瞬）；设上限是防止"栈永远没注册"
// 时无限堆积——真要是那样，堆再多也没人来取。
export const MAX_PENDING_NAVS: number = 4;

let queue: PendingNav[] = [];

export function queuePendingNav(nav: PendingNav): void {
  const kept: PendingNav[] = queue.filter((n: PendingNav): boolean => n.kind !== nav.kind);
  kept.push(nav);
  queue = kept.length > MAX_PENDING_NAVS ? kept.slice(kept.length - MAX_PENDING_NAVS) : kept;
}

// 取走某个页签上挂着的全部跳转（取走即移除，重放失败也不再重试——
// 无限重放比丢一次更糟）。
export function takePendingNavs(tab: string): PendingNav[] {
  const mine: PendingNav[] = queue.filter((n: PendingNav): boolean => n.tab === tab);
  queue = queue.filter((n: PendingNav): boolean => n.tab !== tab);
  return mine;
}

export function pendingNavCount(): number {
  return queue.length;
}

// 切账号/退登：上一个账号的 chatId 在新账号下是另一个会话，挂着的跳转必须丢掉。
export function clearPendingNavs(): void {
  queue = [];
}
