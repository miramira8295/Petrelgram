// 下载中心的纯逻辑（2026-09-15；第三版照 Claude Design「下载中心」稿）：条目模型、类型判定、三路来源合并去重、
// 按页签与关键词过滤、「进行中 / 已完成」两段与段内排序、存储条比例、速度平滑与剩余时间。
// 不碰 TDLib、不碰 UI，可单测。数据怎么取见 store/DownloadCenterStore。

export const DC_TAB_ALL: string = 'all';
export const DC_KIND_VIDEO: string = 'video';
export const DC_KIND_PHOTO: string = 'photo';
export const DC_KIND_AUDIO: string = 'audio';
export const DC_KIND_FILE: string = 'file';
export const DC_KIND_VOICE: string = 'voice';
export const DC_KIND_APK: string = 'apk';
// 页签顺序即显示顺序（设计稿：全部 / 视频 / 图片 / 音乐 / 文件 / 语音 / APK）。
export const DC_TABS: string[] = [
  DC_TAB_ALL, DC_KIND_VIDEO, DC_KIND_PHOTO, DC_KIND_AUDIO, DC_KIND_FILE, DC_KIND_VOICE, DC_KIND_APK
];

// 条目状态。
export const DC_STATE_DOWNLOADING: string = 'downloading'; // 正在传
export const DC_STATE_PAUSED: string = 'paused';           // 下载管理器里被暂停
export const DC_STATE_QUEUED: string = 'queued';           // 下载管理器里没暂停、也没在传
export const DC_STATE_FAILED: string = 'failed';           // 本页发起的继续 / 重试报了错
export const DC_STATE_WAITING_WIFI: string = 'waitingWifi';       // 后台缓存：蜂窝下被「只在 Wi‑Fi 下后台缓存」挡住
export const DC_STATE_WAITING_NETWORK: string = 'waitingNetwork'; // 断网，本该在下的
export const DC_STATE_PARTIAL: string = 'partial';         // 缓存记录里没下完、眼下没在传（界面按「已暂停」画）
export const DC_STATE_COMPLETE: string = 'complete';

// 条目来源：TDLib 下载管理器 / 本应用的缓存记录（后台缓存、播放时边看边缓存）/ 磁盘扫描。
export const DC_SOURCE_MANAGER: string = 'manager';
export const DC_SOURCE_CACHE: string = 'cache';
export const DC_SOURCE_DISK: string = 'disk';

export const DC_SECTION_ACTIVE: string = 'active';
export const DC_SECTION_DONE: string = 'done';

export interface DownloadCenterItem {
  fileId: number;      // 0 = 只知道磁盘路径（扫描出来的历史文件）
  path: string;        // 下完才有
  name: string;
  kind: string;        // DC_KIND_*
  size: number;        // 总字节，0 = 未知
  downloaded: number;  // 已缓存字节
  state: string;       // DC_STATE_*
  source: string;      // DC_SOURCE_*
  mtime: number;       // 毫秒
  preview: string;     // 来源消息摘要
  chatId: number;
  messageId: number;
  mimeType: string;
  session: string;     // 来源会话名，查不到为空串
  savedLocal: boolean; // 存到过相册 / 下载目录（store/SavedLocalRegistry）
  speed: number;       // 字节/秒，只有正在传的才有
}

export interface DownloadCenterSection {
  section: string;
  items: DownloadCenterItem[];
}

export function copyDownloadCenterItem(it: DownloadCenterItem): DownloadCenterItem {
  return {
    fileId: it.fileId, path: it.path, name: it.name, kind: it.kind, size: it.size, downloaded: it.downloaded,
    state: it.state, source: it.source, mtime: it.mtime, preview: it.preview, chatId: it.chatId,
    messageId: it.messageId, mimeType: it.mimeType, session: it.session, savedLocal: it.savedLocal, speed: it.speed
  };
}

// 列表身份：有 fileId 按 fileId 认，没有的按路径认（前缀不同，两类不会撞）。
export function downloadCenterItemId(it: DownloadCenterItem): string {
  return it.fileId !== 0 ? `f${it.fileId}` : `p${it.path}`;
}

// 内容签名：会改变这一行画法的字段都进来。速度按 KB/s 取整，免得每个字节都重建。
export function downloadCenterItemKey(it: DownloadCenterItem): string {
  return `${downloadCenterItemId(it)}_${it.state}_${it.downloaded}_${it.size}_${it.path}_${it.name}_${it.session}` +
    `_${it.savedLocal}_${Math.round(it.speed / 1024)}`;
}

export function progressPercent(downloaded: number, size: number, complete: boolean): number {
  if (complete) {
    return 100;
  }
  if (size <= 0 || downloaded <= 0) {
    return 0;
  }
  // 没下完就封顶 99：100 只留给 TDLib 确认完成的。
  return Math.max(0, Math.min(99, Math.floor(downloaded * 100 / size)));
}

// 按消息内容类型判定（MessageEntry.contentType）。
export function kindOfContentType(contentType: string): string {
  if (contentType === 'video' || contentType === 'videoNote' || contentType === 'animation') {
    return DC_KIND_VIDEO;
  }
  if (contentType === 'photo') {
    return DC_KIND_PHOTO;
  }
  if (contentType === 'audio') {
    return DC_KIND_AUDIO;
  }
  if (contentType === 'voice') {
    return DC_KIND_VOICE;
  }
  return DC_KIND_FILE;
}

// 按 TDLib 的 message.content['@type'] 判定（下载管理器条目带的是原始消息）。
export function kindOfTdContentType(tdType: string): string {
  if (tdType === 'messageVideo' || tdType === 'messageVideoNote' || tdType === 'messageAnimation') {
    return DC_KIND_VIDEO;
  }
  if (tdType === 'messagePhoto') {
    return DC_KIND_PHOTO;
  }
  if (tdType === 'messageAudio') {
    return DC_KIND_AUDIO;
  }
  if (tdType === 'messageVoiceNote') {
    return DC_KIND_VOICE;
  }
  return DC_KIND_FILE;
}

// 按 TDLib 落盘目录名判定（见 util/tdCacheScan）。
export function kindOfDiskDir(dir: string): string {
  if (dir === 'videos' || dir === 'animations' || dir === 'video_notes') {
    return DC_KIND_VIDEO;
  }
  if (dir === 'photos') {
    return DC_KIND_PHOTO;
  }
  if (dir === 'music') {
    return DC_KIND_AUDIO;
  }
  if (dir === 'voice') {
    return DC_KIND_VOICE;
  }
  return DC_KIND_FILE;
}

const PACKAGE_FILE_NAME: RegExp = new RegExp('\\.(apk|apks|xapk|hap)$', 'i');

export function isPackageFileName(name: string): boolean {
  return PACKAGE_FILE_NAME.test(name.trim());
}

// 文件类里的安装包单独归到 APK 页签（设计稿），其它类型不动。
export function refineKindByName(kind: string, name: string): string {
  return kind === DC_KIND_FILE && isPackageFileName(name) ? DC_KIND_APK : kind;
}

// 三路合并：同一 fileId 下载管理器优先于缓存记录；磁盘扫描出来的文件若路径已被带 fileId 的条目占着就丢掉。
export function mergeDownloadCenterItems(manager: DownloadCenterItem[], cached: DownloadCenterItem[],
  disk: DownloadCenterItem[]): DownloadCenterItem[] {
  const seenFiles: Set<number> = new Set();
  const out: DownloadCenterItem[] = [];
  for (const it of [...manager, ...cached]) {
    if (it.fileId === 0 || seenFiles.has(it.fileId)) {
      continue;
    }
    seenFiles.add(it.fileId);
    out.push(it);
  }
  const seenPaths: Set<string> = new Set();
  for (const it of out) {
    if (it.path !== '') {
      seenPaths.add(it.path);
    }
  }
  for (const it of disk) {
    if (it.path === '' || seenPaths.has(it.path)) {
      continue;
    }
    seenPaths.add(it.path);
    out.push(it);
  }
  return out;
}

// 关键词匹配文件名、来源会话名和消息摘要，不分大小写。
export function matchesDownloadCenterQuery(it: DownloadCenterItem, query: string): boolean {
  const q: string = query.trim().toLowerCase();
  if (q === '') {
    return true;
  }
  return it.name.toLowerCase().includes(q) || it.session.toLowerCase().includes(q) ||
    it.preview.toLowerCase().includes(q);
}

export function filterDownloadCenterItems(items: DownloadCenterItem[], tab: string, query: string): DownloadCenterItem[] {
  return items.filter((it: DownloadCenterItem): boolean =>
    (tab === DC_TAB_ALL || it.kind === tab) && matchesDownloadCenterQuery(it, query));
}

// 来源不明的缓存：磁盘扫描出来、没有 fileId 的文件（名字多半是一串数字）。「全部」页签把它们折成一行。
export function isUnsourcedCache(it: DownloadCenterItem): boolean {
  return it.source === DC_SOURCE_DISK;
}

export function sectionOf(it: DownloadCenterItem): string {
  return it.state === DC_STATE_COMPLETE ? DC_SECTION_DONE : DC_SECTION_ACTIVE;
}

// 进行中段内：正在传 → 等 Wi‑Fi / 等网络 → 暂停（含没下完的缓存）→ 排队 → 失败，同档新到旧。
export function activeRank(state: string): number {
  if (state === DC_STATE_DOWNLOADING) {
    return 0;
  }
  if (state === DC_STATE_WAITING_WIFI || state === DC_STATE_WAITING_NETWORK) {
    return 1;
  }
  if (state === DC_STATE_PAUSED || state === DC_STATE_PARTIAL) {
    return 2;
  }
  return state === DC_STATE_QUEUED ? 3 : 4;
}

// 「已完成」段的排序：按时间（新到旧）/ 按大小（大到小，一样大的新到旧）。
export const DC_SORT_TIME: string = 'time';
export const DC_SORT_SIZE: string = 'size';

// 分成「进行中」「已完成」两段；空段不出现。
export function groupDownloadCenterItems(items: DownloadCenterItem[], sort: string = DC_SORT_TIME): DownloadCenterSection[] {
  const active: DownloadCenterItem[] = items
    .filter((it: DownloadCenterItem): boolean => sectionOf(it) === DC_SECTION_ACTIVE)
    .sort((a: DownloadCenterItem, b: DownloadCenterItem): number => {
      const byRank: number = activeRank(a.state) - activeRank(b.state);
      return byRank !== 0 ? byRank : b.mtime - a.mtime;
    });
  const done: DownloadCenterItem[] = items
    .filter((it: DownloadCenterItem): boolean => sectionOf(it) === DC_SECTION_DONE)
    .sort((a: DownloadCenterItem, b: DownloadCenterItem): number => {
      const bySize: number = sort === DC_SORT_SIZE ? b.size - a.size : 0;
      return bySize !== 0 ? bySize : b.mtime - a.mtime;
    });
  const out: DownloadCenterSection[] = [];
  if (active.length > 0) {
    out.push({ section: DC_SECTION_ACTIVE, items: active });
  }
  if (done.length > 0) {
    out.push({ section: DC_SECTION_DONE, items: done });
  }
  return out;
}

export interface StorageBarWidths {
  cache: number; // 百分比
  local: number; // 百分比
}

// 存储条两段的宽度（设计稿的算法）：缓存占「缓存 + 已存本地」的比例；已存本地那段再乘 0.9，右端留一截底色。
// 两者都为 0 时各半。
export function storageBarWidths(cacheBytes: number, localBytes: number): StorageBarWidths {
  const cache: number = Math.max(0, cacheBytes);
  const local: number = Math.max(0, localBytes);
  const pc: number = cache + local > 0 ? cache / (cache + local) * 100 : 50;
  return { cache: pc, local: (100 - pc) * 0.9 };
}

// 速度采样的最小间隔：updateFile 可能一帧来好几条，间隔太短算出来的瞬时速度全是噪声。
export const SPEED_MIN_INTERVAL_MS: number = 200;
const SPEED_SMOOTHING: number = 0.4;

// 速度（字节/秒）：指数平滑，免得数字每跳一次就乱晃。间隔不够时沿用上一次。
export function nextSpeed(prev: number, deltaBytes: number, deltaMs: number): number {
  if (deltaMs < SPEED_MIN_INTERVAL_MS) {
    return prev;
  }
  const instant: number = Math.max(0, deltaBytes) * 1000 / deltaMs;
  return prev <= 0 ? instant : prev * (1 - SPEED_SMOOTHING) + instant * SPEED_SMOOTHING;
}

// 剩余秒数；速度未知、大小未知或已下完返回 -1。
export function etaSeconds(size: number, downloaded: number, speed: number): number {
  if (speed <= 0 || size <= 0 || downloaded >= size) {
    return -1;
  }
  return Math.ceil((size - downloaded) / speed);
}

// TDLib 缓存目录里自动生成的文件名（一串数字，可能带 _序号）：没有给人看的意义，界面上不当标题用。
const GENERATED_CACHE_NAME: RegExp = new RegExp('^\\d+(_\\d+)?\\.[a-zA-Z0-9]{2,5}$');

export function isGeneratedCacheName(name: string): boolean {
  return GENERATED_CACHE_NAME.test(name);
}

export function displayNameOf(name: string): string {
  return isGeneratedCacheName(name) ? '' : name;
}
