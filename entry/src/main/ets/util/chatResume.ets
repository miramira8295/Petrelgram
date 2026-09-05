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

// 这次进会话该从哪儿开：有跳转目标 → 目标；有未读 → 交给未读锚点（返回 0）；
// 否则用记住的位置。未读优先是官方行为，也是用户预期。
export function openAtMessageId(jumpTo: number, hasUnread: boolean, remembered: number): number {
  if (jumpTo > 0) {
    return jumpTo;
  }
  if (hasUnread) {
    return 0;
  }
  return remembered > 0 ? remembered : 0;
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
