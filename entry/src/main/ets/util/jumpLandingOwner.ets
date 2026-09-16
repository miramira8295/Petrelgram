// 跳转落地的所有权窗口（纯判据，有单测）。
//
// 【修的是什么】用户 2026-09-16 报：「消息定位有时候不准确，需要二次点击才能到达
// 正确的位置，第一次像是过去了又被抓去了别的地方。」
//
// 两条跳转路是不对称的：目标**已在窗口里**就是一次 scrollToIndex，没有异步窗口；
// 目标**不在窗口里**要先 loadAround，等快照回来才由 ChatPage.landPendingJump 落地。
// 第二次点之所以准，正是因为第一次已经把目标拉进窗口了——所以这不是偶发，是这条
// 异步落地路上有人抢位置。
//
// 【为什么会被抢】landPendingJump 在**发出滚动之前**就把 pendingJumpId 清零，而
// 「pendingJumpId !== 0」是全仓唯一一条"让路给跳转"的判据：ScrollAnchorController.
// attemptAnchorRestore 的早退、appendAnchor 的 scrollIntentPending、syncReturnState、
// withholdPartialAlbum 全看它。于是落地刚开始的那一刻，所有本该让路的人同时不让路了。
// 页面里已经有一个 900ms 的 jumpLandingUntil，但它只接了**返回栈**，没有任何定位
// 路径读它。
//
// 落地后这几百毫秒里能动列表的有四个，谁都不知道刚发生过跳转：
//   · 贴底跟随：applyInitialOrFollowLanding 跑在 landPendingJump **之前**，用的是
//     跳转前的 atBottom，满足条件就排 32ms 后 scrollEdge(Bottom)；
//   · 追加侧补位：落地后 pendingJumpId 已是 0，拿可能过期的 curStartIdx
//     （只有"行数相等"这一道守卫）去 scrollToIndex——正好是"被抓回原来的地方"；
//   · 再取一页历史：loadAround 只在目标上方放 15 行（MessageStore 的 offset=-15），
//     而 ScrollAlign.START 不算 contentStartOffset，落地后的 start 很容易落进 14 行
//     的触发区，于是立刻再取一页，几百毫秒后前插 30 行；
//   · 停稳时的窗口裁剪，按同样可能过期的 curStartIdx/curEndIdx 下刀。
//
// 【这道闸做什么】给跳转一个明确的落地所有权窗口：窗口内上面四位一律让路，窗口一到
// 就放手。它不改任何一方自己的判据，只多一句"现在轮不到你"。

export const NO_JUMP_LANDING: number = 0;

// 落地所有权窗口的长度。
//
// 【下界】必须盖住落地自己的两个动作：landPendingJump 的 80ms 补发滚动、
// JumpFlashState 的 150ms 取矩形，再加两三帧排版。盖不住就等于没修。
// 【上界】必须比返回栈那道 JUMP_LANDING_GRACE_MS(900) 短。那道管的是"用户算不算
// 自己滑回了最新"，这道管的是"谁能动列表"；把定位按住 900ms 会把新消息跟随也拖住。
export const JUMP_LANDING_SETTLE_MS: number = 400;

// 开窗：返回这次落地的截止时刻。
export function jumpLandingDeadline(
  now: number, settleMs: number = JUMP_LANDING_SETTLE_MS
): number {
  return now + Math.max(0, settleMs);
}

// 此刻位置还归这次跳转所有吗。没跳过（截止时刻是初值 0）时恒为假——否则进会话
// 首屏的落点会被自己挡掉。
export function jumpLandingHolds(deadline: number, now: number): boolean {
  return deadline > NO_JUMP_LANDING && now < deadline;
}

// 跳转落地期间允不允许「头插分批」扣着头部行（util/prependChunker）。
//
// 【2026-09-16 真机日志坐实的真因】跳一条不在窗口里的消息：loadAround 把 22 行
// 更老的消息并进窗口，对 List 而言是一次纯前插，于是分批器扣下 14 行、每 120ms
// 放 8 行，~375ms 才放完。而 landPendingJump 拿的是**完整快照**（93 行）算下标：
//
//   [Jump80]   pending land target=... idx=15 rows=93   ← 参数里的完整快照
//   [JumpLand] #2 start       target=... idx=-1 rows=71 ← 列表里真正发布的
//              t=150 idx=1  rows=79
//              t=400 idx=15 rows=93
//
// idx=-1 = 目标行**还扣在没发布的头部里**。第一次点必然滚到 71 行里的第 15 行
// （一条完全无关的消息），80ms 的补发也落在分批半途。等行放完再点第二次才准——
// 用户报的「第二次点击才会定位」。
//
// 所以落地期间整份发布，不分批：分批是为了翻历史时少重建节点（每批不超过
// cachedCount），而跳转落地本来就是整窗替换、可视区全新建，扣着头部只有坏处。
export function chunkPrependAllowed(
  base: boolean, jumpPending: boolean, landingHolds: boolean
): boolean {
  return base && !jumpPending && !landingHolds;
}
