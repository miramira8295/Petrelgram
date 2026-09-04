// 下载通知的 id 段与阶段判定。
//
// 单独成文件是为了能在宿主用例里验：判定本身是纯函数，而它们所在的
// services/DownloadSaveNotification 一整套都挂在 notificationManager /
// 后台任务上，那些在主机上跑不起来。

// 下载通知专用的 id 段。**这一段是我们自己划的**：新消息、通话那些通知走各自
// 的 id，落不进这个区间，所以按段清扫不会误伤它们。
export const NOTIFICATION_ID_START: number = 1800000000;
export const NOTIFICATION_ID_END: number = 1899999999;

// 下一个 id。走到段尾绕回段首，绝不越界到别人的号段里去。
export function nextNotificationIdAfter(id: number): number {
  return id >= NOTIFICATION_ID_END ? NOTIFICATION_ID_START : id + 1;
}

// 一个 id 是不是本模块发的下载通知。启动清扫按它决定撤不撤。
export function isDownloadNotificationId(id: number): boolean {
  return Number.isFinite(id) && id >= NOTIFICATION_ID_START && id <= NOTIFICATION_ID_END;
}

// 一个阶段是不是终态。终态那一行发出去之后要定时撤掉——不撤就是常驻在通知栏
// 里等用户手动划（用户："通知栏下载不会回收"）。
//
// **'saving' 不算终态**：保存到公共目录还在进行中，撤了进度就断在半路。
export function isTerminalPhase(phase: string): boolean {
  return phase === 'saved' || phase === 'downloadFailed' || phase === 'saveFailed';
}
