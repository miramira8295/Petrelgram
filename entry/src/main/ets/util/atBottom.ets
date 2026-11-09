// 用户此刻算不算"停在会话底部"。
//
// 这个判定挂着两条已经上线过的 bug，所以每条规则都写明为什么。
//
// isAtEnd() 单独不可信：恢复/重取窗口时列表刚被换掉、还没排好版，它会瞬时
// 返回真，atBottom 被置成 true 卡住；随后"内容原地长高时保持贴底"那一支照常
// 开火，把用户从中间拽到最新。实测日志里同一时刻 atBottom=true 而
// endIdx=11 / rows=42，自相矛盾。
//
// 所以用可见行号交叉验证——但**只在行号确实描述当前这份数据时**才允许否决。
// 行号由 onScrollIndex 给出，它落后于数据：新消息到达时行数先加一，行号要等
// 下一次回调才更新。拿旧行号去否决，就会判成"不在底部" → 不贴底 → 不滚动 →
// 没有新的 onScrollIndex → 自锁死，现象是停在底部却不跟新消息。
//
// 先前用"距末尾 3 行"的余量绕过这个时间差，但那个数是设备相关的：
// onScrollIndex 报的区间取决于屏幕能装下多少行，pad 屏高、可见行多，同样的
// 3 行完全不是一回事——pad 和部分手机上因此失效。现在改成记录"这批行号是在
// 数据长度为多少时算出来的"，只有两者一致才敢否决：不涉及像素也不涉及行数，
// 跨设备一致。

export const AT_BOTTOM_KEEP: string = 'keep';  // 维持现状，不改判定
export const AT_BOTTOM_YES: string = 'yes';
export const AT_BOTTOM_NO: string = 'no';

export interface AtBottomInput {
  // 全屏查看器开着：底层列表的位置不该被任何东西改动。
  viewerOpen: boolean;
  // 输入法正在改变列表高度的那几帧，最后一行会被短暂裁掉。
  imeTailPinned: boolean;
  scrollerAtEnd: boolean;
  // onScrollIndex 报的可见区间末行；-1 表示还没有过回调。
  visibleEndIdx: number;
  // 上面那个行号是在数据长度为多少时算出来的。
  indexGroupsLen: number;
  groupsLen: number;
  // MessageStore 里还有没有更新的历史没拉。窗口边缘不是真正的会话末尾。
  hasMoreNewer: boolean;
}

// 行号是否描述当前这份数据。
export function tailIndexFresh(input: AtBottomInput): boolean {
  return input.visibleEndIdx >= 0 && input.indexGroupsLen === input.groupsLen;
}

export function atBottomVerdict(input: AtBottomInput): string {
  if (input.viewerOpen) {
    return AT_BOTTOM_KEEP;
  }
  if (input.imeTailPinned) {
    return AT_BOTTOM_YES;
  }
  // 行号不新鲜就不许否决——宁可漏判也不能误判，误判会自锁死。
  const indexSaysTail: boolean = !tailIndexFresh(input) ||
    input.visibleEndIdx >= input.groupsLen - 1;
  return (input.scrollerAtEnd && indexSaysTail && !input.hasMoreNewer)
    ? AT_BOTTOM_YES : AT_BOTTOM_NO;
}
