// 播放器状态卡片（「正在准备视频」「缓冲中…」「正在重连」）什么时候才画出来。
//
// 四个条件容易改错，所以抽成纯函数钉住语义：
//
//   起播前（isPrepared=false）——过延迟门。本地实况照片的 mp4 只有 1.5~3 秒，
//     ijkplayer 几十毫秒就准备好了，卡片画出来就是闪一下（issue #192）。
//     delayElapsed 由 StreamingVideoPlayer 的 armStatusDelay 定时器翻起来。
//   播放中（isPrepared=true）——立刻显示。用户正盯着，画面停住却什么都不说更糟。
//   出错时——一律不显示：错误有自己的一套 UI，两层叠着会互相盖。

export function shouldShowPlayerStatus(
  status: string, hasError: boolean, delayElapsed: boolean, isPrepared: boolean
): boolean {
  if (status === '' || hasError) {
    return false;
  }
  return delayElapsed || isPrepared;
}
