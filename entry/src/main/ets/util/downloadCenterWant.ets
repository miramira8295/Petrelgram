import { Want } from '@kit.AbilityKit';

// 「打开下载中心」的外部入口（2026-09-15）：后台缓存的通知栏点一下进来。
// 与点通知进会话同一套：EntryAbility 收到 want 就写 AppStorage（写时间戳，重复点同一条也算变化），
// pages/Index 监听、登录就绪后打开「设置 › 下载中心」。
export const DOWNLOAD_CENTER_WANT_KEY: string = 'openDownloadCenter';
export const KEY_PENDING_DOWNLOAD_CENTER: string = 'pendingOpenDownloadCenter';
export const DOWNLOAD_CENTER_DEST: string = 'DownloadCenterPage';

export function stashDownloadCenterWant(want: Want): void {
  const params = want.parameters as Record<string, Object> | undefined;
  if (params === undefined || (params[DOWNLOAD_CENTER_WANT_KEY] as boolean | undefined) !== true) {
    return;
  }
  AppStorage.setOrCreate<number>(KEY_PENDING_DOWNLOAD_CENTER, Date.now());
}
