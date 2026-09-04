// 媒体下载的优先级分档。
//
// TDLib 的 downloadFile 用 1..32 排队，数字大的先拿带宽。分档必须一眼能对上
// 「谁在等」：
//   32  正在播的视频分片（VideoStreamSession，不在本文件里）
//   24  用户此刻正盯着的东西：点开的全屏图、点开要看的视频、存进下载管理器
//   16  可见窗口里的缩略图
//    8  静默预取：邻图、可见窗口里的自动播放视频
//
// 【为什么抽出来】优先级过去是在 MessageStore 里就地三元表达式挑的，挑错了
// 从代码上完全看不出来：startVideoDownload 按 manage（为存而下）挑，于是
// 「点开就看」发的是 8——比后台缩略图还低，24 那档只服务「保存」。
// 判据是 exempt（为看而下），不是 manage（为存而下）。

export const MEDIA_PREFETCH_PRIORITY: number = 8;
export const THUMBNAIL_PRIORITY: number = 16;
export const MEDIA_USER_PRIORITY: number = 24;

// manage：进 TDLib 下载管理器，用户要「留下」这个文件。
// exempt：豁免可见窗口的自动取消，用户此刻正在「看」这个文件。
// 两者任一为真都说明有人在等，给 24；都为假才是背景预取。
export function mediaDownloadPriority(manage: boolean, exempt: boolean): number {
  return (manage || exempt) ? MEDIA_USER_PRIORITY : MEDIA_PREFETCH_PRIORITY;
}
