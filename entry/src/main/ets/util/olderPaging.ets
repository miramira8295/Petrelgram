// 向上翻页（older）的触发线。
//
// 【为什么从 4 抬到约一屏】历史页现在是"滑动中只预取、停稳才发布"
// （见 ChatPage.maybeLoadOlder），所以触发线只决定**请求什么时候发**，
// 不决定什么时候发布——抬高它不会把"滑动中前插"那类跳带回来。
//
// 原来 start<=4 意味着视口顶上方只剩 4 行（≈230vp）才取页。一次上滑一秒能走
// 好几屏，页还没到你已经撞到已加载窗口的顶端，列表物理上没内容可滚，只能干等
// 到停稳才出历史。2026-09-10 真机实测这段等待 835 / 1053 / 1187ms（6 次里 3 次），
// 用户报"卡在那"。抬到约一屏，页在你看到顶之前就到手。
//
// 【为什么抬它现在是安全的】olderArmed 的四个重新上膛点全部与位置无关：
// 会话重置、flush 失败重试、fillViewport、TouchType.Down。早先设计里
// "start>4 重新上膛"已被移除，所以不存在"抬高阈值导致顶边再也上不了膛"。
export const OLDER_TRIGGER_ROWS: number = 14;

export function olderTriggerHit(start: number, triggerRows: number): boolean {
  return start >= 0 && start <= triggerRows;
}
