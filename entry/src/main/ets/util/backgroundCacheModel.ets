import { CacheRecord } from './cacheRegistryModel';

// 后台缓存的纯逻辑（2026-09-15）：重启后该续上哪几条、来源消息里还是不是那个文件、空转重发多少次该放弃、
// 此刻该不该下（网络门控）、通知栏的汇总进度。

// 重发整份下载却一个字节都没多：多半是文件已经不可下（消息删了、没有权限）。连续这么多次就放弃，
// 免得每 2 秒空转下去。
export const MAX_IDLE_REARMS: number = 15;

// 重启应用后自动续上的：点过「后台缓存」、没被用户暂停、知道来源消息（续上之前要拿它核对文件）。
export function resumableCacheRecords(records: CacheRecord[]): CacheRecord[] {
  return records.filter((r: CacheRecord): boolean =>
    r.background && r.paused !== true && r.chatId !== 0 && r.messageId !== 0);
}

const MAX_WALK_DEPTH: number = 8;

// 消息内容里有没有这个 fileId 的文件对象。fileId 只在当前 TDLib 实例里有效：切过账号，同一个数字可能指向
// 另一个账号里的别的文件，续上之前先拿来源消息核对。
export function messageHasFile(node: Object | undefined, fileId: number, depth: number = 0): boolean {
  if (node === undefined || (node as Object | null) === null || typeof node !== 'object' || depth > MAX_WALK_DEPTH) {
    return false;
  }
  if (Array.isArray(node)) {
    for (const child of (node as Object[])) {
      if (messageHasFile(child, fileId, depth + 1)) {
        return true;
      }
    }
    return false;
  }
  const obj = node as Record<string, Object>;
  if ((obj['@type'] as string | undefined) === 'file' && (obj['id'] as number | undefined) === fileId) {
    return true;
  }
  for (const key of Object.keys(obj)) {
    if (messageHasFile(obj[key], fileId, depth + 1)) {
      return true;
    }
  }
  return false;
}

// 此刻为什么不下：'' = 该下；'wifi' = 等 Wi‑Fi；'network' = 等网络。
export const BG_WAIT_NONE: string = '';
export const BG_WAIT_WIFI: string = 'wifi';
export const BG_WAIT_NETWORK: string = 'network';

// 断网 → 等网络；蜂窝（含漫游）且「只在 Wi‑Fi 下后台缓存」、这一条没点过「用流量继续」→ 等 Wi‑Fi。
// VPN（底下承载不明）和其它网络放行，同视频预取的判法（见 services/NetworkStateService 里 'vpn' 的说明）。
export function cacheWaitReason(network: string, wifiOnly: boolean, allowCellular: boolean): string {
  if (network === 'none') {
    return BG_WAIT_NETWORK;
  }
  if ((network === 'mobile' || network === 'roaming') && wifiOnly && !allowCellular) {
    return BG_WAIT_WIFI;
  }
  return BG_WAIT_NONE;
}

export interface CacheProgressSample {
  downloaded: number;
  size: number;
}

// 通知栏汇总进度：已缓存字节之和 / 总字节之和；总大小未知的不计入。没全部下完就封顶 99。
export function aggregateCachePercent(samples: CacheProgressSample[]): number {
  let got: number = 0;
  let total: number = 0;
  for (const s of samples) {
    if (s.size > 0) {
      total += s.size;
      got += Math.min(s.size, Math.max(0, s.downloaded));
    }
  }
  return total > 0 ? Math.min(99, Math.floor(got * 100 / total)) : 0;
}
