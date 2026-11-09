// 边下边播的下载提前量（2026-10-10）。纯函数，可单测。
//
// 原来固定 6MB：普通 1080p（约 4Mbps）够 12 秒，4K HDR（约 12Mbps）只够 4 秒，网络一抖、
// TDLib 一换 DC 就卡。改成按「秒」算：Wi-Fi 提前 60 秒、封顶 64MB；计流量的提前 20 秒、
// 封顶 24MB（多下的部分用户中途退出就白花了）。最少保持原来的 6MB。

const MB: number = 1024 * 1024;
export const READ_AHEAD_MIN_BYTES: number = 6 * MB;
const READ_AHEAD_SECONDS_UNMETERED: number = 60;
const READ_AHEAD_SECONDS_METERED: number = 20;
const READ_AHEAD_MAX_UNMETERED: number = 64 * MB;
const READ_AHEAD_MAX_METERED: number = 24 * MB;

// fileSize / durationMs 任一未知（<= 0）按最小值。
export function streamReadAheadBytes(fileSize: number, durationMs: number, metered: boolean): number {
  if (!(fileSize > 0) || !(durationMs > 0)) {
    return READ_AHEAD_MIN_BYTES;
  }
  const bytesPerSec: number = fileSize / (durationMs / 1000);
  const seconds: number = metered ? READ_AHEAD_SECONDS_METERED : READ_AHEAD_SECONDS_UNMETERED;
  const cap: number = metered ? READ_AHEAD_MAX_METERED : READ_AHEAD_MAX_UNMETERED;
  return Math.round(Math.max(READ_AHEAD_MIN_BYTES, Math.min(cap, bytesPerSec * seconds)));
}
