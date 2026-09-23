// 跳转落点（#219-6：「点击艾特信息跳转后，消息定位在最顶部模糊区域」）。
//
// 消息列表铺到毛玻璃顶栏底下，靠 contentStartOffset 留出顶栏；而
// scrollToIndex(ScrollAlign.START) **不算 contentStartOffset**——目标行被顶到列表
// 最上沿，正压在顶栏下面（08-30 真机日志：偏差恒等于顶栏高 153）。
// 跳到某条消息一律改成居中，和官方 Android 客户端一致，上下文两头都看得到。
//
// 例外是「回到上次阅读位置」：那是按记下的行内偏移原样恢复视口，不能居中。
// 它和普通跳转共用 landPendingJump 这一条落地路，所以要分得出来。

// targetRow：这次落地目标所在的行；resumeRow：记下的阅读位置所在的行（没有则 < 0）。
export function isResumeLanding(targetRow: number, resumeRow: number): boolean {
  return resumeRow >= 0 && targetRow === resumeRow;
}
