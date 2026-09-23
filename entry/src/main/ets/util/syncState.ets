// 首页标题下那行连接状态显示哪一档（#219-7）。'' = 不显示（已连上或未知）。
//
// 【#219-7 为什么完全没网时什么都不显示】updateConnectionState 是一次性推送，
// 订阅晚了就收不到当前值（Globals.trackConnectionState 的注释）。首页原来只订阅
// 后续推送、不读缓存：没网冷启动时「等待网络」那条在首页挂载之前就推完了，
// 首页停在默认的 ''。现在订阅后先拿 getConnectionState() 过一遍这个函数。
export function chatListSyncState(connectionStateType: string): string {
  if (connectionStateType === 'connectionStateUpdating' ||
    connectionStateType === 'connectionStateConnecting' ||
    connectionStateType === 'connectionStateConnectingToProxy' ||
    connectionStateType === 'connectionStateWaitingForNetwork') {
    return connectionStateType;
  }
  return '';
}
