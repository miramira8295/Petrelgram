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
// 列表所有权在用户手上——手指按在列表上，或惯性滑动仍在进行——时发出的分页
// 请求才算"用户主动向下翻页"。
//
// 为什么不能用 PageGate.armed 代替：newerGate 开会话时就是满膛的
// （armedPageGate()），首屏布局完成后的第一次 onScrollIndex 就能把它打掉，
// 那一枪没有任何用户手势参与。armed 表达的是"还能不能再打一枪"，不是"这一枪
// 是谁扣的扳机"。
export function newerPageIsUserDriven(touchActive: boolean, userScrollActive: boolean): boolean {
  return touchActive || userScrollActive;
}
