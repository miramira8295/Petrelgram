// 退出会话时记住最后浏览位置，下次进来落回去（issue #98）。
//
// ChatPage 里原来那套 resumeScroll* 是**实例字段**，只管「页面还活着、被资料页
// 盖住又回来」这一种情况；退出会话页面就销毁，位置也没了。这里把它抬到模块级，
// 按会话（含话题）记一份，进程活着就一直有效。
//
// 不落盘：位置这种东西过一夜就没意义了，而且写盘要在每次滚动后排队，不值。
export interface RememberedChatViewport {
  messageId: number;
  itemY: number;
}

const positions: Map<string, RememberedChatViewport> =
  new Map<string, RememberedChatViewport>();
const MAX_REMEMBERED: number = 64;

export function resumeKeyOf(chatId: number, threadId: number): string {
  return `${chatId}_${threadId}`;
}

// 在底部就不记：下次进来该跟到最新，而不是钉在当时的最后一条。
export function rememberChatPosition(chatId: number, threadId: number,
  messageId: number, atBottom: boolean, itemY: number = 0): void {
  const key = resumeKeyOf(chatId, threadId);
  if (atBottom || messageId <= 0) {
    positions.delete(key);
    return;
  }
  positions.delete(key); // 重新插到尾部，下面按插入顺序淘汰最旧的
  positions.set(key, {
    messageId: messageId,
    itemY: Number.isFinite(itemY) ? itemY : 0
  });
  while (positions.size > MAX_REMEMBERED) {
    const oldest = positions.keys().next().value as string | undefined;
    if (oldest === undefined) {
      break;
    }
    positions.delete(oldest);
  }
}

export function rememberedChatPosition(chatId: number, threadId: number): number {
  return positions.get(resumeKeyOf(chatId, threadId))?.messageId ?? 0;
}

export function rememberedChatViewport(
  chatId: number, threadId: number
): RememberedChatViewport {
  const remembered: RememberedChatViewport | undefined =
    positions.get(resumeKeyOf(chatId, threadId));
  return remembered === undefined
    ? { messageId: 0, itemY: 0 }
    : { messageId: remembered.messageId, itemY: remembered.itemY };
}

export function forgetChatPosition(chatId: number, threadId: number): void {
  positions.delete(resumeKeyOf(chatId, threadId));
}

// 换账号/退登时整表清掉：消息 id 是按账号的。
export function resetChatPositions(): void {
  positions.clear();
}

// 记住的位置**赢不赢**未读锚点（issue #216）。
//
// 【原来的规则和它坏在哪】原来是一刀切的"有未读就交给未读锚点"，注释写着
// "未读优先是官方行为"。这话只对了一半：在群里隔一会儿回来想看"新的都有啥"，
// 未读优先是对的；但**频道几乎永远有未读**，于是记住的位置在频道里等于从来
// 不生效——位置其实存下来了，每次都被顶掉。频道的典型用法恰恰是往上翻历史，
// 翻到一半退出去看一眼别的，回来就被拽到底部的未读线上，读到哪儿全丢了
// （报告原话：「打开频道退出再进入时，会自动跳转到下一个消息」——那条"下一个
// 消息"就是未读分割线，它在你上次读到那条的下面一条）。
//
// 【现在的判据带方向】记住的位置在**已读区**时才赢：`remembered <= lastReadInboxId`。
// 换句话说只有"你当时在翻已经读过的历史"这一种情形才落回原处，这正是 #216 的
// 场景；而群里有 50 条未读、你上次就停在未读区里的那种，照旧交给未读锚点，
// 行为一个字不变。
//
// 【它不会藏起任何未读】未读分割线由 firstUnreadId 单独驱动，和落点无关，照画
// 在你下方，往下滑就到。落回原处只是不再把你**弹**过去。
//
// 【为什么用 lastReadInboxId 而不是"第一条未读"】前者是 TDLib 给的权威值
// （chat.last_read_inbox_message_id），后者要在已加载的消息里扫，而首屏落点
// 判定发生时那批消息可能还没到。
//
// 边界：没记住位置 → false；完全没有未读 → true（老行为）；
// lastReadInboxId 为 0（这个会话一条都没读过）→ false，交给未读锚点。
export function resumeBeatsUnread(
  rememberedId: number, unreadCount: number, lastReadInboxId: number
): boolean {
  if (rememberedId <= 0) {
    return false;
  }
  if (unreadCount <= 0) {
    return true;
  }
  if (lastReadInboxId <= 0) {
    return false;
  }
  return rememberedId <= lastReadInboxId;
}

// 这次进会话该从哪儿开：有跳转目标 → 目标；否则按 resumeBeatsUnread 决定是用
// 记住的位置还是交给未读锚点（返回 0）。
export function openAtMessageId(jumpTo: number, unreadCount: number, remembered: number,
  lastReadInboxId: number): number {
  if (jumpTo > 0) {
    return jumpTo;
  }
  return resumeBeatsUnread(remembered, unreadCount, lastReadInboxId) ? remembered : 0;
}

// ── 缓存页 resume 时，这一份快照是不是「整条时间线的一个碎片」────────────
//
// 判的是**数量级坍缩**，不是「非空」。原始注释逐字保留：
//
//   The empty-snapshot case is not the only fragment. openChat makes TDLib
//   push the newest message immediately, and its first getChatHistory reply
//   may legally contain fewer messages than asked for — and onHistory marks
//   the store 'ready' the moment that reply lands. So a one-message,
//   already-'ready' snapshot reached this point and replaced 34 rows with
//   one, which the log shows the list then rebuilding back to thirty. That
//   collapse and rebuild is the "messages scrambled after coming back from
//   the background" report.
//
//   The test is a size collapse, not emptiness: a fragment is an order of
//   magnitude smaller than what is on screen, while messages deleted in the
//   background shrink the list by a few rows. The halving threshold draws
//   that line. It errs by holding a stale viewport for one update if more
//   than half a chat is deleted while backgrounded; the next snapshot
//   clears it.
//
// 2:1 是业务 hack，不是可调参数：改成别的比例、或者退化成 `nextRows === 0`，
// 都会改变行为（前者挪动「几行删除」与「坍缩」的分界线，后者把上面那条
// 一条消息压掉 34 行的真机案例重新放进来）。
//
// prevRows = 当前屏上的行数（this.groups.length），nextRows = 新快照的条数
// （list.length）。prevRows 为 0 时永远不是碎片：屏上没东西可保。
export function isResumeFragment(prevRows: number, nextRows: number): boolean {
  return prevRows > 0 && nextRows * 2 < prevRows;
}
