// 内容不足一屏时要不要主动向上补一页。
//
// 【原始需求，必须保住】
// 向上分页全靠滚动事件驱动（onReachStart / onScrollIndex 里 start <= 4），可内容
// 铺不满一屏时列表根本滚不动，这两个事件永远不来，于是卡在初始那点内容上——
// 用户看到的就是"999+ 却滑不动"。平板尤其容易中招：屏幕更高，要更多行才铺得满。
//
// 【第一版判据错在哪】
// 第一版只问"最后一行可见吗"（curEndIdx >= rows - 1）。写代码时的意图（注释原话）
// 是「整份数据都在屏幕上、列表滚不动」，但列表是 stackFromEnd(true)：**底部锚定，
// 最后一行几乎恒可见**。于是这条判据在"用户正停在底部"时恒成立，和"内容铺不满
// 一屏"完全分不开。
//
// 真机后果（2026-08-27，带未读进会话立刻下滑）：
//
//   [InitialPage] route=around-unread anchor=11488198656
//   [InitialPage] around got=14 rows=14 windowAtTail=true hasMoreNewer=false
//                 hasMoreOlder=true
//
// rows=14、一屏 8–9 行、未读锚点还在中间 —— 最后一行可见，判据成立。于是每发布
// 一次就 loadOlder 一次，**往上追加**行；配合 maintainVisibleContentPosition(true)
// 视口相对内容被钉住，而用户正想往下滑。一路拉到 FILL_VIEWPORT_MAX_ROWS = 80 才
// 停，手感就是"刚进去那几秒滑不动，过一会列表稳定就好使了"——时间尺度和用户描述
// 对得上。这不是"可优化"，是主诉的直接成因之一。
//
// 【正确的判据】
// 回到注释里写的那个意思：**整份数据都在屏幕上**，也就是列表根本滚不动。
// 第一行和最后一行同时可见才成立：
//
//   startIdx === 0 && endIdx >= rows - 1
//
// 加上 startIdx === 0 这一半之后：
//   · 消息太少铺不满一屏 → 首行末行都可见 → 照常补页，原始需求分毫不动；
//   · 用户停在长列表底部 → startIdx > 0 → 不再误触发，往上追加的连锁没了。
//
// 行号新鲜度也要看：onScrollIndex 报的行号属于**那一刻**的数据长度，而 applyMessages
// 里数据已经换了新快照。对不上就不判，等下一次 onScrollIndex——宁可晚一帧，也不
// 拿错位的行号做决定。
export interface ViewportFillInput {
  // 还有更旧的历史可取。没有就无事可做。
  hasMoreOlder: boolean;
  // 当前快照的行数。
  rows: number;
  // 补页封顶，防呆用（ChatPage.FILL_VIEWPORT_MAX_ROWS）。
  maxRows: number;
  // 可见区间的首行 / 末行下标（ChatPage.curStartIdx / curEndIdx）。
  startIdx: number;
  endIdx: number;
  // 报出上面那对行号时的数据长度（ChatPage.indexGroupsLen）。
  indexRows: number;
}

export function shouldFillViewport(input: ViewportFillInput): boolean {
  if (!input.hasMoreOlder) {
    return false;
  }
  if (input.rows <= 0 || input.rows >= input.maxRows) {
    return false;
  }
  // 首帧之前行号是 -1，那时还不知道能看见多少，交给后续的滚动/数据变化再判。
  if (input.startIdx < 0 || input.endIdx < 0) {
    return false;
  }
  // 行号和当前快照对不上：这对下标是上一份数据的，不能拿来判。
  if (input.indexRows !== input.rows) {
    return false;
  }
  // 整份数据都在屏幕上 ⇒ 列表滚不动 ⇒ 滚动事件永远不来 ⇒ 得自己敲门。
  return input.startIdx === 0 && input.endIdx >= input.rows - 1;
}
