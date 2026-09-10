// List.stackFromEnd 同时做两件事：短内容底部对齐，以及插入 ListItem 时保持
// "离末尾的距离"。第二件事不能用于可滚动的消息历史。官方 List API 明确写着，
// stackFromEnd=true 时插入 ListItem 会把其上方的可见项整体往上移动；这正是用户
// 停在末尾附近、底部收到新消息时整屏气泡闪动/移位的来源。
//
// 因此它只服务于第一件事：上一份有效布局里所有行都同时可见，说明内容尚未铺满
// 一屏，可以继续底部对齐。长列表即使正贴着实时末尾也关闭它；真正的实时跟随由
// ChatPage 在 atBottom=true 时显式、延后到布局完成后 scrollEdge(Bottom)。
//
// 这里故意读取 indexGroupsLen 描述的上一份布局，而不要求它等于刚发布的新长度：
// 尾部追加的同一帧里 onScrollIndex 还没上报新长度，旧布局恰好才是判断“追加之前
// 是否已经可滚动”的可靠证据。
export function stackFromEndWanted(
  hasMoreNewer: boolean,
  visibleStartIdx: number,
  visibleEndIdx: number,
  indexGroupsLen: number
): boolean {
  if (hasMoreNewer) {
    return false;
  }
  if (visibleStartIdx < 0 || visibleEndIdx < 0 || indexGroupsLen <= 0) {
    // 首次布局仍从末尾开始；首屏落点逻辑随后会覆盖需要停在中段的场景。
    return true;
  }
  return visibleStartIdx === 0 && visibleEndIdx >= indexGroupsLen - 1;
}
