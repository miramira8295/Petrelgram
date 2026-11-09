import { HIGH_WATER_BYTES, PREPARE_TAIL_BYTES } from '../services/VideoStreamSession';

// 视频气泡出现时**预取第一块**的判据与取块规则（纯函数，全部有单测）。
//
// 【目的】用户点开视频时，播放器起手要的那几块字节已经在本地，"点了直接播"
// 的概率大幅提高。适用于单视频、视频+文字、相册里的视频格——信号来自气泡
// 现成的 onMediaRatio / onMediaGone，相册每一格独立上报。
//
// 【取哪几块】头 VIDEO_PREFETCH_HEAD_BYTES（20MB）+ 尾 PREPARE_TAIL_BYTES（MP4 的
// moov 可能在尾部）。头块经历过 2MB → 6MB → 20MB：2MB 只是 waitForReady 的门槛，
// 6MB 是 start() 起手的 HIGH_WATER，20MB 是用户拍的（2026-09-09："下载20m"）——
// 够播上几十秒不再等网络。单测钉住它**不低于 HIGH_WATER_BYTES**：低于那个数，
// 起播那一刻播放器自己还得补，预取就白做。尾块常量仍从 VideoStreamSession import。
//
// 【流量】Wi-Fi 与蜂窝一律预取（用户 2026-09-09："蜂窝网络也下载"），VPN 同样
// 放行（底下不是 Wi-Fi 就是蜂窝）；漫游、无网、未知网络、省电模式不预取。
// 每条视频至多 21MB，一屏并发 3 条。
//
// 【归属，最要紧的一条】TDLib 的 downloadFile 若文件已在下载，新调用会**覆盖**
// 它的 priority/offset/limit。播放器正在整份下的时候我们发一个 limit=2MB 的，
// 就把它夹成 2MB。所以被认领的文件（正在播放/查看、用户点过下载、进了下载
// 管理器）**既不发预取，也不取消**。判据由 MessageStore.isVideoFileClaimed 提供。

// 一屏同时出现多条视频时的并发上限。预取优先级低，但并发连接和内存不低；
// 超出的排队，前面的划走后补位。2 → 3（用户 2026-09-09："能下载并发调大吗"）；
// TDLib 自己对并行下载也有上限，再往上基本换不来吞吐，只会互相抢。
export const MAX_CONCURRENT_VIDEO_PREFETCH: number = 3;

// 头块大小。见文件头【取哪几块】。
export const VIDEO_PREFETCH_HEAD_BYTES: number = 20 * 1024 * 1024;

// 气泡在视口里停够这么久才开下载。快速滑动时气泡进出只有几百毫秒，真机日志里
// 全是"start → 1s 后 pause"，每次都是一个 20MB 请求起了又停。
export const VIDEO_PREFETCH_DWELL_MS: number = 400;

export interface PrefetchDecisionInput {
  network: string;        // KEY_CURRENT_NETWORK_TYPE：wifi | mobile | roaming | none | other
  powerSaving: boolean;
  alreadyLocal: boolean;  // videoPath 非空
  fileClaimed: boolean;   // MessageStore.isVideoFileClaimed
  fileId: number;
}

export interface VideoPrefetchRange {
  offset: number;
  limit: number;
}

// 拒绝原因，'' = 放行。给日志用：真机上"没感觉被预取"时，第一件事就是看它
// 到底是没触发、还是被哪一条拒了（网络类型是最常见的——AppSettings 初始化把
// KEY_CURRENT_NETWORK_TYPE 置成 'other'，NetworkStateService 之后才异步改成真值）。
export function prefetchRefusalReason(input: PrefetchDecisionInput): string {
  if (input.fileId === 0) {
    return 'not-video';
  }
  if (input.alreadyLocal) {
    return 'local';
  }
  if (input.fileClaimed) {
    return 'claimed';
  }
  if (input.powerSaving) {
    return 'power-saving';
  }
  // 'vpn' = 默认网络是 VPN 且底下的物理承载没找到；VPN 之下不是 Wi-Fi 就是蜂窝，
  // 而蜂窝本来就放行，所以 VPN 也放行。'other'/'none'/'roaming' 仍拒。
  if (input.network === 'wifi' || input.network === 'mobile' || input.network === 'vpn') {
    return '';
  }
  return `network=${input.network}`;
}

export function prefetchAllowed(input: PrefetchDecisionInput): boolean {
  return prefetchRefusalReason(input) === '';
}

// 尺寸未知（0）时只要头块：TDLib 里 limit=0 是"到文件末尾"，那就不是预取了。
export function prefetchRanges(fileSize: number): VideoPrefetchRange[] {
  if (fileSize <= 0) {
    return [{ offset: 0, limit: VIDEO_PREFETCH_HEAD_BYTES }];
  }
  if (fileSize <= VIDEO_PREFETCH_HEAD_BYTES) {
    return [{ offset: 0, limit: fileSize }];
  }
  const tail: number = Math.min(PREPARE_TAIL_BYTES, fileSize);
  return [
    { offset: 0, limit: VIDEO_PREFETCH_HEAD_BYTES },
    { offset: Math.max(0, fileSize - tail), limit: tail }
  ];
}
