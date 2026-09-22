// 新取到的一页历史能不能**接**在当前窗口上（issue #213）。
//
// 【为什么这件事必须判】Telegram 的消息 id 是 `序号 << 20`，所以两条消息 id 的
// 差除以 1048576 就是它们之间隔了多少条。一页历史如果和窗口之间隔着成百上千条，
// 直接合并出来的窗口看着是连续的，**中间那几百条无声无息地没了**：用户从落点
// 往下滑，滑到接缝处一步跨过去，就成了"跳过大量历史直接回到最新"。
//
// 这道检查在 onHistory 的 `kind === 'latest'` 那一支早就有了（进程被冻结期间到
// 达的消息会造成同样的断层），注释也写着 "Merging would render the two runs
// seamlessly glued with the middle silently missing"。**`around` 那一支一直漏着**
// ——而跳转正是最容易造成断层的动作：会话刚打开只有最新一页，跳到很早的媒体，
// 两段之间天然隔着整个中段。2026-09-22 真机日志：
//
//   onHistory kind=around got=30 rowsBefore=43          ← 合并，不是替换
//   gap after=around biggest=979 atIdx=30                ← 第 30 行处断了 979 条
//   live tail reached: window==chatLast, closing newer pagination
//
// 第三行是这个洞永远补不上的原因：最新页还留在窗口里，窗口最后一条就等于会话
// 最后一条，向下分页被判定"到底了"直接关掉，再没有任何人会去取中间那段。
//
// （原始日志里的消息 id 不往仓里抄：它们来自真实会话，而这里需要的只是 979
// 这个条数——`(较新 id - 较旧 id) / ID_STEP` 就是它。）
export const WINDOW_JOIN_TOLERANCE: number = 5;

// 两段之间隔了多少条消息（不相接时为正，相接/重叠为 0）。
export function messagesBetween(lowerId: number, upperId: number, idStep: number): number {
  if (lowerId <= 0 || upperId <= 0 || idStep <= 0 || upperId <= lowerId) {
    return 0;
  }
  return Math.round((upperId - lowerId) / idStep) - 1;
}

// 这一页和窗口断开了吗。新页可能落在窗口**下方**（跳去更早的历史，#213 的情形）
// 也可能落在**上方**（从很早的位置跳回接近最新处），两侧都要判。
//
// 容差：删除过的消息会在 id 上留下正常的小空档，几条之内不算断层——那正是
// logWindowGap 只报 >3 的理由。容差之内照旧合并。
export function historyPageDetached(
  pageOldest: number, pageNewest: number,
  windowOldest: number, windowNewest: number,
  idStep: number, tolerance: number = WINDOW_JOIN_TOLERANCE
): boolean {
  if (pageOldest <= 0 || pageNewest <= 0 || windowOldest <= 0 || windowNewest <= 0) {
    return false;
  }
  // 有重叠就一定接得上。
  if (pageOldest <= windowNewest && pageNewest >= windowOldest) {
    return false;
  }
  const below: number = messagesBetween(pageNewest, windowOldest, idStep);
  const above: number = messagesBetween(windowNewest, pageOldest, idStep);
  return Math.max(below, above) > tolerance;
}

// 窗口里有没有还没发出去的消息。
//
// 【为什么它能一票否决换窗口】未发送的消息只活在本地，窗口一清就没了，用户
// 会看到自己刚发的那条凭空消失。这种情形（正在发送 + 同时跳去很早的历史）
// 很少见，宁可在这个角落里保留旧行为（合并、留洞），也不能丢消息。
//
// 判据是 id：服务端消息的 id 是 `序号 << 20`，低 20 位恒为 0；未发送的本地
// 消息带着非零的低位。
export function windowHasUnsent(ids: number[], idStep: number): boolean {
  if (idStep <= 0) {
    return false;
  }
  return ids.some((id: number): boolean => id > 0 && id % idStep !== 0);
}
