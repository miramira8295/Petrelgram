// 会话首屏「一行都还没有、正在加载」时的提示（#219-10）。
//
// 【为什么原来是一片空白】这一档两处都以为对方会画：
//   · 状态卡（MessageListStateCard）的条件是 loadState !== 'loading'；
//   · 顶部状态胶囊（util/timelineState）在 0 行时直接返回 TL_NONE，理由是
//     "空状态卡片已经在说同样的话了"。
// 平时从本地库取几十毫秒就出来，看不出问题。没网时若第一条未读附近的历史
// 从没下载过，预取（only_local）落空、回退到联网请求，TDLib 要等十几秒
// （真机 14.4s）——这段时间界面上什么都没有，像是坏了。

// 等这么久还没出内容才显示，本地命中的正常情况不闪。
export const INITIAL_HINT_DELAY_MS: number = 500;

export function showInitialLoadingHint(hasVisibleRows: boolean, loadState: string): boolean {
  return !hasVisibleRows && loadState === 'loading';
}

// 转圈下面那行字的文案 key；'' = 只转圈。与首页标题下（ChatListPage.syncLabel）同一套。
export function initialHintLabelKey(connectionStateType: string): string {
  if (connectionStateType === 'connectionStateWaitingForNetwork') {
    return 'cl_waiting_network';
  }
  if (connectionStateType === 'connectionStateConnecting' ||
    connectionStateType === 'connectionStateConnectingToProxy') {
    return 'cl_connecting';
  }
  return '';
}
