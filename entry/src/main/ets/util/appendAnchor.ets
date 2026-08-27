// 向下追加时要不要手动复位锚点。
//
// 【这道闸挡的是哪一维】
// 列表是 stackFromEnd(true)（底部锚定）。往末尾追加行，可见内容会被顶着走，
// 用户会看到视口自己跑到底——260e497 因此加了一次手动 scrollToIndex 复位。
// 但它当时的额外判据是 `!atBottom`，那**问的是另一件事**：
//
//   atBottom = "用户此刻停在会话的实时尾部吗"（util/atBottom）
//
// 而 atBottomVerdict 里带着 `!hasMoreNewer`：窗口还没取到会话实时尾部时，
// atBottom 按定义恒为假。也就是说，从未读锚点开窗、一路向下翻页的**整个过程
// 中**这道闸恒开，每一次追加发布都复位一次视口。真机后果是一条闭合回路：
//
//   发布 → scrollToIndex(锚点) 把视口按住 → 可见区间恒定 → 边界行每帧建了又
//   拆（RepeatVirtualScroll:RemoveNode 每秒 25–30 次）→ 缩略图 path/pixelMap
//   跟着每帧清空重设（闪）；滑动时位置纹丝不动；点 ↓ 要和复位抢好几个回合。
//   直到 hasMoreNewer 翻假，闸关上，位置一下到位。
//
// 【正确的维度】
// 要判的是「**这次追加是不是用户主动向下翻页的结果**」。用户手指推着列表往下
// 走、因此打出一页 newer——那一页落地时把他手底下那行按回原位，正是 260e497
// 要的。反过来，程序性/自动的追加（首屏铺满后的自动预取、短页补链、实时新
// 消息）没有"用户手底下那一行"可言，复位只是跟系统的布局较劲。
//
// 这个判据在**请求发出时**取值，然后一路带到发布点，而不是在发布时回头看
// "用户是不是恰好还在滑"——后者是时序巧合：一次轻扫打出的页往往在手指离开
// 之后才回来。
export interface AppendAnchorInput {
  // 快速回退开关（ChatPage.APPEND_ANCHOR_RESTORE_BYPASSED）。
  bypassed: boolean;
  // 首次定位还没完成时列表的位置由首屏逻辑拥有，任何复位都是抢方向盘。
  didInitialScroll: boolean;
  // 这次发布已经被向上翻页的复位接管了，一次发布只允许一个锚点。
  prependAnchorHeld: boolean;
  // 这次发布确实是"在末尾追加行、头部没变"（AlbumGroupDataSource.appendBreaksAnchor）。
  appendBreaksAnchor: boolean;
  // 这一批追加的行，是用户主动向下翻页请求回来的那一页。
  userDrivenAppend: boolean;
}

export function shouldHoldAppendAnchor(input: AppendAnchorInput): boolean {
  if (input.bypassed || !input.didInitialScroll || input.prependAnchorHeld) {
    return false;
  }
  if (!input.appendBreaksAnchor) {
    return false;
  }
  return input.userDrivenAppend;
}

// 请求这一页 newer 的是谁。
//
// 判据是**闸的膛是谁压上去的**（PageGate.armedByUser），不是发请求那一刻某个
// 滚动标志的瞬时值。
//
// ── 为什么换掉 listTouchActive || listUserScrollActive ──────────────────
//
// 真机日志（探针 [AppendAnchor]）：hold 40 次、restore 40 次、**skip 0 次**，
// 而同一时段 [NewerFire] 全程 touch=false userScroll=false。也就是说所有追加
// 都被判成用户驱动，包括首屏定位之后那一批。两条原因叠在一起：
//
//   1) listUserScrollActive 的真实语义不是"用户还在滚"。它只在
//      onDidScroll && listTouchActive 时置真，置假只靠浮动日期条的 820ms 隐藏
//      计时器（ChatPage.armFloatDateHide）和 resetScrollSession——抬手和
//      onScrollStop 都不清它。它等价于"浮动日期条还亮着"，惯性期间恒真。
//   2) 更要命的是它和闸的**上膛条件读的是同一个变量**：第一版里闸只有在
//      listUserScrollActive 为真时才重新上膛，于是凡是穿过闸的请求，回头去读
//      这个变量必然是真。skip 对分页请求在结构上不可达。
//
// armedByUser 表达的是"这一枪是谁扣的扳机"，与"扣完之后过了多久""此刻还滚不
// 滚"无关，也不再和上膛条件同源。首屏程序性定位打掉的那一发 armedByUser=false，
// 查看器换组走的 loadNewer() 默认也是假——它们现在都落在 skip 这一支。
export function newerPageIsUserDriven(gateArmedByUser: boolean): boolean {
  return gateArmedByUser;
}

// 追加标记的一次性配对。
//
// 标记由 MessageStore 在"用户驱动的那一页真的合进窗口"时置位，由 ChatPage 的
// **每一次**发布无条件取走（consumeUserDrivenAppend）；取走之后用不用得上，再
// 看这次发布有没有真的在末尾追加行。
//
// 第一版有两个漏点，合起来让标记变成一个永久闩：
//
//   · 置位在 loadNewer 的 .then() 开头，**早于合并**。走短页补链、缓存预热重
//     问、整页丢弃这些分支时一行都不会追加，标记却已经置上了。
//   · 取走只发生在 appendsRows 为真的那次发布。上面那种"置了位却没追加行"的
//     请求，标记就没人取，**永久闩在那儿**。
//
// 而 loadNewer 的过滤相当激进（页内断链只收连续前缀、与锚点步长为 0 的重复条
// 目全丢），一页拿回 0 行是常态。于是第一次用户驱动的请求之后，此后任何一次
// 追加——实时新消息、查看器换组、补链——都会读到"已置位"，全部误判成用户翻出
// 来的。hold 40 / skip 0 就是这么来的。
//
// 现在置位挪到真正合并那两处，取走无条件：一次请求最多影响一次发布，跨页残留
// 不可能再发生。
export function useUserDrivenAppendMark(markPending: boolean, appendsRows: boolean): boolean {
  return markPending && appendsRows;
}
