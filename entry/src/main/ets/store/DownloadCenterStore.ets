import { common } from '@kit.AbilityKit';
import { fileIo as fs, storageStatistics } from '@kit.CoreFileKit';
import { getChatStore, getTdClient, getTdFilesDirectory } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { ChatEntry } from './ChatEntry';
import {
  DownloadEntry, DownloadPage, DownloadQuery, defaultDownloadQuery, removeDownload, searchDownloads,
  setAllDownloadsPaused, setDownloadPaused
} from './DownloadApi';
import { CacheClearResult, clearCache, DetailedStorageUsage, getDetailedStorageUsage } from './StorageApi';
import { cachedMediaRecords, ensureCacheRegistry, forgetCachedMedia, isBackgroundCaching } from './CacheRegistry';
import {
  ensureSavedLocalRegistry, isSavedLocal, savedLocalTotalBytes, subscribeSavedLocal
} from './SavedLocalRegistry';
import { CacheRecord } from '../util/cacheRegistryModel';
import {
  allowCellularForBackgroundCache, backgroundCacheWaitReason, startBackgroundCache, stopBackgroundCache,
  subscribeBackgroundCache
} from '../services/BackgroundCache';
import { subscribeNetworkType } from '../services/NetworkStateService';
import { KEY_CURRENT_NETWORK_TYPE } from './AppSettings';
import { BG_WAIT_NETWORK, BG_WAIT_WIFI } from '../util/backgroundCacheModel';
import { scanTdCacheFiles, TdCacheFile } from '../util/tdCacheScan';
import { FileSaveProgress, saveFileToDownloads, saveMediaToGallery } from '../util/mediaSaver';
import { GallerySaveEntry, saveMediaBatchToGallery } from '../util/batchGallerySave';
import {
  copyDownloadCenterItem, DC_KIND_PHOTO, DC_KIND_VIDEO, DC_SOURCE_CACHE, DC_SOURCE_DISK, DC_SOURCE_MANAGER,
  DC_STATE_COMPLETE, DC_STATE_DOWNLOADING, DC_STATE_FAILED, DC_STATE_PARTIAL, DC_STATE_PAUSED, DC_STATE_QUEUED,
  DownloadCenterItem, kindOfDiskDir, kindOfTdContentType, mergeDownloadCenterItems, nextSpeed, refineKindByName,
  SPEED_MIN_INTERVAL_MS, DC_STATE_WAITING_NETWORK, DC_STATE_WAITING_WIFI
} from '../util/downloadCenterModel';
import { applyDoneWatermark, DcSourceWindow, doneWatermark, oldestMtime } from '../util/downloadCenterPaging';
import { logE, logI } from '../util/log';

// 下载中心的数据（2026-09-15；第三版照设计稿加了速度、排队 / 失败、已存本地、存储占用；第四版分页）。三路来源：
//   · TDLib 下载管理器（searchFileDownloads）——进行中的（含暂停）一次拉全，已完成的每页 100 条续拉；
//   · 缓存记录（store/CacheRegistry）——边看边缓存、点过「后台缓存」的；每页只向 getFile 查 100 条的进度，
//     点过「后台缓存」的第一页就全部带上（它们是用户在意的「进行中」）；
//   · 磁盘扫描（util/tdCacheScan）——后台线程排好序，每页交给界面 100 条。
// 「已完成」三路按时间合并，用水位线挡住还没翻到的那一截（util/downloadCenterPaging），续拉只会接在末尾。
// 另外两块：「已存本地」（store/SavedLocalRegistry），缓存总占用与设备可用空间（存储卡片）。
// 进度靠 updateFile 实时推，页面刷新有节流。

const PAGE_SIZE: number = 100;
const MANAGER_ACTIVE_MAX_PAGES: number = 5;
const LOAD_ALL_MAX_ROUNDS: number = 60;
const GETFILE_BATCH: number = 16;
const MIN_PHOTO_BYTES: number = 100 * 1024;
const DISK_SCAN_CAP: number = 5000;
const NOTIFY_THROTTLE_MS: number = 250;

interface SpeedSample {
  bytes: number;
  at: number;
}

function withFileState(it: DownloadCenterItem, path: string, size: number, downloaded: number,
  state: string): DownloadCenterItem {
  const out: DownloadCenterItem = copyDownloadCenterItem(it);
  out.path = path;
  out.size = size;
  out.downloaded = downloaded;
  out.state = state;
  return out;
}

// 下载管理器条目的状态：完成 > 被暂停 > 正在传 > 排队（没暂停也没在传）。
function managerState(done: boolean, active: boolean, paused: boolean): string {
  if (done) {
    return DC_STATE_COMPLETE;
  }
  if (paused) {
    return DC_STATE_PAUSED;
  }
  return active ? DC_STATE_DOWNLOADING : DC_STATE_QUEUED;
}

// saveFileToDownloads 只给回调，这里转成一次性的结果。
class SaveOutcome implements FileSaveProgress {
  private readonly settle: (ok: boolean) => void;

  constructor(settle: (ok: boolean) => void) {
    this.settle = settle;
  }

  onSaving(_percent: number): void {
  }

  onSaved(_destination: string): void {
    this.settle(true);
  }

  onCancelled(): void {
    this.settle(false);
  }

  onFailed(): void {
    this.settle(false);
  }
}

export class DownloadCenterStore {
  loading: boolean = false;
  loadingMore: boolean = false;
  // TDLib 缓存总占用（getStorageStatistics 的 size），0 = 还没算出来。
  totalCacheBytes: number = 0;
  // 设备可用空间，-1 = 取不到。
  freeBytes: number = -1;
  // 「已存本地」累计字节。
  savedBytes: number = 0;
  private managerActive: DownloadCenterItem[] = [];
  private managerDone: DownloadCenterItem[] = [];
  private managerDoneOffset: string = '';
  private managerDoneMore: boolean = true;
  private records: CacheRecord[] = [];
  private cachedLoaded: number = 0;
  private cached: DownloadCenterItem[] = [];
  private diskFiles: TdCacheFile[] = [];
  private diskLoaded: number = 0;
  private diskScanned: boolean = false;
  private disk: DownloadCenterItem[] = [];
  private initialLoad: Promise<void> = Promise.resolve();
  private moreInFlight: Promise<void> | null = null;
  private loadAllRunning: boolean = false;
  private pausedIds: Set<number> = new Set<number>();
  private backgroundIds: Set<number> = new Set<number>();
  private failedIds: Set<number> = new Set<number>();
  private speeds: Map<number, number> = new Map<number, number>();
  private samples: Map<number, SpeedSample> = new Map<number, SpeedSample>();
  private unsubFile: (() => void) | null = null;
  private unsubSaved: (() => void) | null = null;
  private unsubCache: (() => void) | null = null;
  private unsubNetwork: (() => void) | null = null;
  private notifyTimer: number = -1;
  private disposed: boolean = false;
  private readonly onChange: () => void;

  constructor(onChange: () => void) {
    this.onChange = onChange;
  }

  items(): DownloadCenterItem[] {
    const merged: DownloadCenterItem[] = mergeDownloadCenterItems(this.managerItems(), this.cached, this.disk)
      .map((it: DownloadCenterItem): DownloadCenterItem => this.decorate(it));
    return applyDoneWatermark(merged, doneWatermark(this.windows()));
  }

  hasMore(): boolean {
    return this.managerDoneMore || this.cachedLoaded < this.records.length || !this.diskScanned ||
      this.diskLoaded < this.diskFiles.length;
  }

  load(context: common.Context): void {
    this.loading = true;
    this.watchFiles();
    this.watchSaved(context);
    this.watchCacheState();
    this.notifyNow();
    this.initialLoad = this.reload(context).then((): void => {
      this.loading = false;
      this.notifyNow();
    });
  }

  // 续拉下一页（滑到底、条目太少时自动补）。同一时刻只跑一轮，重复调用拿到的是同一个 Promise。
  // 先登记在途再通知页面：页面在通知里可能马上又来要下一页。
  loadMore(context: common.Context): Promise<void> {
    if (this.moreInFlight !== null) {
      return this.moreInFlight;
    }
    if (this.disposed || this.loading || !this.hasMore()) {
      return Promise.resolve();
    }
    this.loadingMore = true;
    const run: Promise<void> = this.loadNextPages(context).catch((e: Object): void => {
      logE(`DownloadCenterStore.loadMore failed: ${JSON.stringify(e)}`);
    }).finally((): void => {
      this.moreInFlight = null;
      this.loadingMore = false;
      this.notifyNow();
    });
    this.moreInFlight = run;
    this.notifyNow();
    return run;
  }

  // 搜索要覆盖全部：把各路翻到底（轮数有上限）。
  async loadAll(context: common.Context): Promise<void> {
    if (this.loadAllRunning) {
      return;
    }
    this.loadAllRunning = true;
    try {
      await this.initialLoad;
      for (let round = 0; round < LOAD_ALL_MAX_ROUNDS && !this.disposed && this.hasMore(); round++) {
        await this.loadMore(context);
      }
    } finally {
      this.loadAllRunning = false;
    }
  }

  dispose(): void {
    this.disposed = true;
    if (this.unsubFile !== null) {
      this.unsubFile();
      this.unsubFile = null;
    }
    if (this.unsubSaved !== null) {
      this.unsubSaved();
      this.unsubSaved = null;
    }
    if (this.unsubCache !== null) {
      this.unsubCache();
      this.unsubCache = null;
    }
    if (this.unsubNetwork !== null) {
      this.unsubNetwork();
      this.unsubNetwork = null;
    }
    if (this.notifyTimer !== -1) {
      clearTimeout(this.notifyTimer);
      this.notifyTimer = -1;
    }
  }

  // —— 单条操作 ——

  // 暂停：下载管理器里的走 toggleDownloadIsPaused；缓存记录里的停掉后台缓存（记成暂停，重启后不自动续上）。
  async pause(item: DownloadCenterItem): Promise<void> {
    if (item.fileId === 0 || item.state === DC_STATE_COMPLETE) {
      return;
    }
    if (item.source === DC_SOURCE_MANAGER) {
      await setDownloadPaused(getTdClient(), item.fileId, true);
      this.pausedIds.add(item.fileId);
      this.setManagerState(item.fileId, DC_STATE_PAUSED);
    } else {
      await stopBackgroundCache(item.fileId, true);
      this.setCachedState(item.fileId, DC_STATE_PARTIAL);
    }
    this.clearSpeed(item.fileId);
    this.notifyNow();
  }

  // 继续 / 重试。报错的记成失败，界面给「重试」。
  async resume(context: common.UIAbilityContext, item: DownloadCenterItem): Promise<void> {
    if (item.fileId === 0 || item.state === DC_STATE_COMPLETE) {
      return;
    }
    this.failedIds.delete(item.fileId);
    try {
      if (item.source === DC_SOURCE_MANAGER) {
        await setDownloadPaused(getTdClient(), item.fileId, false);
        this.pausedIds.delete(item.fileId);
        this.setManagerState(item.fileId, DC_STATE_QUEUED);
      } else {
        this.backgroundIds.add(item.fileId);
        await startBackgroundCache(context, this.cacheRecordOf(item));
      }
    } catch (e) {
      this.failedIds.add(item.fileId);
      throw e as Error;
    } finally {
      this.notifyNow();
    }
  }

  // 取消：停下并丢掉已缓存的部分，条目随之消失。
  async cancel(item: DownloadCenterItem): Promise<void> {
    if (item.fileId === 0) {
      return;
    }
    if (item.source === DC_SOURCE_MANAGER) {
      await removeDownload(getTdClient(), item.fileId, true);
    } else {
      await stopBackgroundCache(item.fileId, false);
      await this.deleteTdFile(item.fileId);
    }
    this.dropFile(item.fileId);
  }

  // 删缓存：有 fileId 的交给 TDLib（下载管理器里的顺带摘掉）；只有路径的直接删文件。存到本地的副本不受影响。
  async deleteCache(item: DownloadCenterItem): Promise<void> {
    if (item.fileId !== 0) {
      if (item.source === DC_SOURCE_MANAGER) {
        await removeDownload(getTdClient(), item.fileId, true);
      } else {
        await this.deleteTdFile(item.fileId);
      }
      this.dropFile(item.fileId);
    } else if (item.path !== '') {
      await fs.unlink(item.path);
    }
    if (item.path !== '') {
      this.removeDiskPath(item.path);
    }
    this.notifyNow();
  }

  // 存本地：图片视频进相册（系统确认框），其余进下载目录。「已存本地」由 util/mediaSaver 在成功后统一记。
  saveToLocal(context: common.UIAbilityContext, item: DownloadCenterItem): Promise<boolean> {
    if (item.state !== DC_STATE_COMPLETE || item.path === '') {
      return Promise.resolve(false);
    }
    const path: string = item.path;
    if (item.kind === DC_KIND_PHOTO || item.kind === DC_KIND_VIDEO) {
      return saveMediaToGallery(context, path, item.kind === DC_KIND_VIDEO).then((): boolean => isSavedLocal(path));
    }
    return new Promise<boolean>((resolve: (value: boolean) => void): void => {
      saveFileToDownloads(context, path, item.name, new SaveOutcome(resolve));
    });
  }

  // 「用流量继续」：这一条不再受「只在 Wi‑Fi 下后台缓存」限制。
  async allowCellular(context: common.UIAbilityContext, item: DownloadCenterItem): Promise<void> {
    if (item.fileId === 0 || item.state === DC_STATE_COMPLETE || item.source === DC_SOURCE_MANAGER) {
      return;
    }
    await allowCellularForBackgroundCache(context, this.cacheRecordOf(item));
    this.notifyNow();
  }

  // —— 批量 ——

  // 「全部暂停 / 全部开始」。全部开始只拉起下载管理器里的、失败的、和点过「后台缓存」的；
  // 看视频时顺带缓存了一半的不在其列——几百条记录一起开下，流量和存储都扛不住。
  async toggleAll(context: common.UIAbilityContext, pauseAll: boolean): Promise<void> {
    await setAllDownloadsPaused(getTdClient(), pauseAll);
    for (const it of this.items()) {
      if (it.source === DC_SOURCE_MANAGER || it.fileId === 0) {
        continue;
      }
      if (pauseAll && (it.state === DC_STATE_DOWNLOADING || it.state === DC_STATE_WAITING_WIFI ||
        it.state === DC_STATE_WAITING_NETWORK)) {
        await this.pause(it);
      } else if (!pauseAll && (it.state === DC_STATE_PARTIAL || it.state === DC_STATE_FAILED) &&
        (this.backgroundIds.has(it.fileId) || this.failedIds.has(it.fileId))) {
        try {
          await this.resume(context, it);
        } catch (e) {
          logE(`DownloadCenterStore.toggleAll resume(${it.fileId}) failed: ${JSON.stringify(e)}`);
        }
      }
    }
    await this.loadManagerActive();
  }

  // 批量存本地：没下完的、已经存过的跳过。返回存成功的条数。
  async saveBatchToLocal(context: common.UIAbilityContext, items: DownloadCenterItem[]): Promise<number> {
    const media: GallerySaveEntry[] = [];
    const files: DownloadCenterItem[] = [];
    for (const it of items) {
      if (it.state !== DC_STATE_COMPLETE || it.path === '' || it.savedLocal) {
        continue;
      }
      if (it.kind === DC_KIND_PHOTO || it.kind === DC_KIND_VIDEO) {
        media.push({ path: it.path, isVideo: it.kind === DC_KIND_VIDEO });
      } else {
        files.push(it);
      }
    }
    let saved: number = 0;
    if (media.length > 0) {
      saved += (await saveMediaBatchToGallery(context, media)).length;
    }
    for (const it of files) {
      if (await this.saveToLocal(context, it)) {
        saved++;
      }
    }
    return saved;
  }

  // 批量删除：已完成的删缓存，进行中的取消。返回处理成功的条数。
  async deleteBatch(items: DownloadCenterItem[]): Promise<number> {
    let removed: number = 0;
    for (const it of items) {
      try {
        if (it.state === DC_STATE_COMPLETE) {
          await this.deleteCache(it);
        } else {
          await this.cancel(it);
        }
        removed++;
      } catch (e) {
        logE(`DownloadCenterStore.deleteBatch(${downloadIdOf(it)}) failed: ${JSON.stringify(e)}`);
      }
    }
    return removed;
  }

  // 清理缓存（存储卡片右上角）：TDLib optimizeStorage 删干净，然后从第一页重新加载。返回释放的字节数。
  async clearAllCache(context: common.Context): Promise<number> {
    let before: number = this.totalCacheBytes;
    if (before <= 0) {
      before = (await getDetailedStorageUsage(0)).size;
    }
    const res: CacheClearResult = await clearCache();
    this.totalCacheBytes = res.remainingSize;
    this.notifyNow();
    this.initialLoad = this.reload(context);
    await this.initialLoad;
    this.notifyNow();
    return Math.max(0, before - res.remainingSize);
  }

  // —— 加载 ——

  private reload(context: common.Context): Promise<void> {
    this.loadStats();
    return Promise.all([
      this.loadManagerActive(), this.loadManagerDonePage(true), this.loadCachedPage(context, true), this.loadDiskPage(true)
    ]).then((): void => {});
  }

  private async loadNextPages(context: common.Context): Promise<void> {
    const jobs: Promise<void>[] = [];
    if (this.managerDoneMore) {
      jobs.push(this.loadManagerDonePage(false));
    }
    if (this.cachedLoaded < this.records.length) {
      jobs.push(this.loadCachedPage(context, false));
    }
    if (!this.diskScanned || this.diskLoaded < this.diskFiles.length) {
      jobs.push(this.loadDiskPage(false));
    }
    await Promise.all(jobs);
  }

  // 每一路「已加载到哪儿、还有没有下一页」，算「已完成」的水位线用。
  private windows(): DcSourceWindow[] {
    return [
      { hasMore: this.managerDoneMore, loadedCount: this.managerDone.length, oldestLoadedMtime: oldestMtime(this.managerDone) },
      {
        hasMore: this.cachedLoaded < this.records.length, loadedCount: this.cachedLoaded,
        oldestLoadedMtime: this.cachedLoaded > 0 ? this.records[this.cachedLoaded - 1].addedAt : 0
      },
      {
        hasMore: !this.diskScanned || this.diskLoaded < this.diskFiles.length, loadedCount: this.diskLoaded,
        oldestLoadedMtime: this.diskLoaded > 0 ? this.diskFiles[this.diskLoaded - 1].mtimeSec * 1000 : 0
      }
    ];
  }

  private decorate(it: DownloadCenterItem): DownloadCenterItem {
    const out: DownloadCenterItem = copyDownloadCenterItem(it);
    out.session = this.sessionOf(it.chatId);
    out.savedLocal = isSavedLocal(it.path);
    out.speed = it.state === DC_STATE_DOWNLOADING ? (this.speeds.get(it.fileId) ?? 0) : 0;
    const stalled: boolean = it.state !== DC_STATE_COMPLETE && it.state !== DC_STATE_DOWNLOADING;
    if (stalled && it.fileId !== 0 && this.failedIds.has(it.fileId)) {
      out.state = DC_STATE_FAILED;
    }
    out.state = this.waitingState(it, out.state);
    return out;
  }

  // 等 Wi‑Fi（后台缓存被「只在 Wi‑Fi 下后台缓存」挡住）/ 等网络（断网时本该在下的）。
  private waitingState(it: DownloadCenterItem, state: string): string {
    if (state === DC_STATE_COMPLETE || it.fileId === 0) {
      return state;
    }
    if (it.source !== DC_SOURCE_MANAGER) {
      const reason: string = backgroundCacheWaitReason(it.fileId);
      if (reason === BG_WAIT_WIFI) {
        return DC_STATE_WAITING_WIFI;
      }
      if (reason === BG_WAIT_NETWORK) {
        return DC_STATE_WAITING_NETWORK;
      }
    }
    const offline: boolean = (AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE) ?? '') === 'none';
    if (offline && (state === DC_STATE_DOWNLOADING || state === DC_STATE_QUEUED)) {
      return DC_STATE_WAITING_NETWORK;
    }
    return state;
  }

  private sessionOf(chatId: number): string {
    if (chatId === 0) {
      return '';
    }
    const entry: ChatEntry | undefined = getChatStore().entryOf(chatId);
    return entry !== undefined ? entry.title : '';
  }

  // 后台缓存的等待原因、网络类型一变，「等 Wi‑Fi / 等网络」的显示跟着变。
  private watchCacheState(): void {
    if (this.unsubCache === null) {
      this.unsubCache = subscribeBackgroundCache((): void => { this.scheduleNotify(); });
    }
    if (this.unsubNetwork === null) {
      this.unsubNetwork = subscribeNetworkType((_network: string): void => { this.scheduleNotify(); });
    }
  }

  private watchSaved(context: common.Context): void {
    if (this.unsubSaved !== null) {
      return;
    }
    this.unsubSaved = subscribeSavedLocal((): void => {
      this.savedBytes = savedLocalTotalBytes();
      this.scheduleNotify();
    });
    ensureSavedLocalRegistry(context).then((): void => {
      this.savedBytes = savedLocalTotalBytes();
      this.notifyNow();
    });
  }

  private managerItems(): DownloadCenterItem[] {
    return this.managerActive.concat(this.managerDone);
  }

  private findManager(fileId: number): DownloadCenterItem | undefined {
    return this.managerActive.find((m: DownloadCenterItem): boolean => m.fileId === fileId) ??
      this.managerDone.find((m: DownloadCenterItem): boolean => m.fileId === fileId);
  }

  // 进度 / 路径沿用已知的，免得重新拉列表时进度条闪回 0。
  private withKnownProgress(it: DownloadCenterItem, paused: Set<number>): DownloadCenterItem {
    const prev: DownloadCenterItem | undefined = this.findManager(it.fileId);
    if (prev === undefined) {
      return it;
    }
    const done: boolean = it.state === DC_STATE_COMPLETE || prev.state === DC_STATE_COMPLETE;
    return withFileState(it, prev.path, prev.size, prev.downloaded,
      managerState(done, prev.state === DC_STATE_DOWNLOADING, paused.has(it.fileId)));
  }

  // 进行中的（含暂停）数量不大，一次拉全：它们永远该在最上面，不能埋进后几页。
  private async loadManagerActive(): Promise<void> {
    try {
      const entries: DownloadEntry[] = [];
      let offset: string = '';
      for (let page = 0; page < MANAGER_ACTIVE_MAX_PAGES; page++) {
        const query: DownloadQuery = defaultDownloadQuery();
        query.onlyActive = true;
        query.offset = offset;
        query.limit = PAGE_SIZE;
        const res: DownloadPage = await searchDownloads(getTdClient(), query);
        for (const entry of res.entries) {
          entries.push(entry);
        }
        if (res.nextOffset === '') {
          break;
        }
        offset = res.nextOffset;
      }
      if (this.disposed) {
        return;
      }
      const paused: Set<number> = new Set<number>();
      for (const entry of entries) {
        if (entry.isPaused) {
          paused.add(entry.fileId);
        }
      }
      this.pausedIds = paused;
      this.managerActive = entries.map((entry: DownloadEntry): DownloadCenterItem =>
        this.withKnownProgress(this.managerItem(entry), paused));
      logI(`[DC] manager active ${entries.length}`);
      this.notifyNow();
      await this.refreshFiles(entries.map((e: DownloadEntry): number => e.fileId), (_id: number): void => {});
    } catch (e) {
      logE(`DownloadCenterStore.loadManagerActive failed: ${JSON.stringify(e)}`);
    }
  }

  private async loadManagerDonePage(reset: boolean): Promise<void> {
    if (reset) {
      this.managerDoneOffset = '';
      this.managerDoneMore = true;
    }
    if (!this.managerDoneMore) {
      return;
    }
    try {
      const query: DownloadQuery = defaultDownloadQuery();
      query.onlyCompleted = true;
      query.offset = this.managerDoneOffset;
      query.limit = PAGE_SIZE;
      const res: DownloadPage = await searchDownloads(getTdClient(), query);
      if (this.disposed) {
        return;
      }
      const base: DownloadCenterItem[] = reset ? [] : this.managerDone;
      const seen: Set<number> = new Set<number>(base.map((m: DownloadCenterItem): number => m.fileId));
      const next: DownloadCenterItem[] = base.slice();
      const fresh: number[] = [];
      for (const entry of res.entries) {
        if (seen.has(entry.fileId)) {
          continue;
        }
        seen.add(entry.fileId);
        next.push(this.withKnownProgress(this.managerItem(entry), this.pausedIds));
        fresh.push(entry.fileId);
      }
      this.managerDone = next;
      this.managerDoneOffset = res.nextOffset;
      this.managerDoneMore = res.nextOffset !== '';
      logI(`[DC] manager done +${fresh.length} more=${this.managerDoneMore}`);
      this.notifyNow();
      await this.refreshFiles(fresh, (_id: number): void => {});
    } catch (e) {
      // 翻不动就当到底了：留着「还有下一页」会让水位线一直压着整段「已完成」。
      this.managerDoneMore = false;
      logE(`DownloadCenterStore.loadManagerDonePage failed: ${JSON.stringify(e)}`);
    }
  }

  private managerItem(entry: DownloadEntry): DownloadCenterItem {
    const completed: boolean = entry.completeDate > 0;
    return {
      fileId: entry.fileId, path: '', name: entry.fileName !== '' ? entry.fileName : entry.preview,
      kind: refineKindByName(kindOfTdContentType(entry.contentType ?? ''), entry.fileName), size: 0, downloaded: 0,
      state: completed ? DC_STATE_COMPLETE : (entry.isPaused ? DC_STATE_PAUSED : DC_STATE_QUEUED),
      source: DC_SOURCE_MANAGER, mtime: (completed ? entry.completeDate : entry.addDate) * 1000,
      preview: entry.preview, chatId: entry.chatId, messageId: entry.messageId, mimeType: '',
      session: '', savedLocal: false, speed: 0
    };
  }

  private async loadCachedPage(context: common.Context, reset: boolean): Promise<void> {
    try {
      if (reset) {
        await ensureCacheRegistry(context);
        this.records = cachedMediaRecords();
        this.cachedLoaded = 0;
        this.backgroundIds = new Set<number>(this.records
          .filter((r: CacheRecord): boolean => r.background).map((r: CacheRecord): number => r.fileId));
      }
      const start: number = this.cachedLoaded;
      const end: number = Math.min(this.records.length, start + PAGE_SIZE);
      const batch: CacheRecord[] = this.records.slice(start, end)
        .concat(reset ? this.records.slice(end).filter((r: CacheRecord): boolean => r.background) : []);
      const prev: Map<number, DownloadCenterItem> = new Map<number, DownloadCenterItem>();
      for (const m of this.cached) {
        prev.set(m.fileId, m);
      }
      const base: DownloadCenterItem[] = reset ? [] : this.cached;
      const seen: Set<number> = new Set<number>(base.map((m: DownloadCenterItem): number => m.fileId));
      const next: DownloadCenterItem[] = base.slice();
      const fresh: number[] = [];
      for (const r of batch) {
        if (seen.has(r.fileId)) {
          continue;
        }
        seen.add(r.fileId);
        next.push(this.cachedItem(r, prev.get(r.fileId)));
        fresh.push(r.fileId);
      }
      this.cached = next;
      this.cachedLoaded = end;
      this.notifyNow();
      const stale: number[] = [];
      await this.refreshFiles(fresh, (id: number): void => { stale.push(id); });
      if (this.disposed) {
        return;
      }
      // 一个字节都没有、也不在下载的：缓存已经被清掉了，记录跟着剔除。records 不动——cachedLoaded 按它的下标算窗口。
      logI(`[DC] cached +${fresh.length} of ${this.records.length} stale ${stale.length}`);
      if (stale.length > 0) {
        const staleIds: Set<number> = new Set<number>(stale);
        for (const id of stale) {
          forgetCachedMedia(id);
        }
        this.cached = this.cached.filter((it: DownloadCenterItem): boolean => !staleIds.has(it.fileId));
        this.notifyNow();
      }
    } catch (e) {
      logE(`DownloadCenterStore.loadCachedPage failed: ${JSON.stringify(e)}`);
    }
  }

  private cachedItem(r: CacheRecord, prev: DownloadCenterItem | undefined): DownloadCenterItem {
    const it: DownloadCenterItem = {
      fileId: r.fileId, path: '', name: r.name !== '' ? r.name : r.preview, kind: refineKindByName(r.kind, r.name),
      size: r.size, downloaded: 0, state: DC_STATE_PARTIAL, source: DC_SOURCE_CACHE, mtime: r.addedAt,
      preview: r.preview, chatId: r.chatId, messageId: r.messageId, mimeType: r.mimeType,
      session: '', savedLocal: false, speed: 0
    };
    return prev === undefined ? it
      : withFileState(it, prev.path, prev.size > 0 ? prev.size : it.size, prev.downloaded, prev.state);
  }

  private async loadDiskPage(reset: boolean): Promise<void> {
    try {
      if (reset || !this.diskScanned) {
        const files: TdCacheFile[] = await scanTdCacheFiles(getTdFilesDirectory(), MIN_PHOTO_BYTES, DISK_SCAN_CAP);
        if (this.disposed) {
          return;
        }
        this.diskFiles = files;
        this.diskScanned = true;
        this.diskLoaded = 0;
        this.disk = [];
        logI(`[DC] disk scanned ${files.length}`);
      }
      const from: number = this.diskLoaded;
      this.diskLoaded = Math.min(this.diskFiles.length, from + PAGE_SIZE);
      this.disk = this.disk.concat(this.diskFiles.slice(from, this.diskLoaded)
        .map((f: TdCacheFile): DownloadCenterItem => this.diskItem(f)));
      this.notifyNow();
    } catch (e) {
      this.diskScanned = true;
      logE(`DownloadCenterStore.loadDiskPage failed: ${JSON.stringify(e)}`);
    }
  }

  private diskItem(f: TdCacheFile): DownloadCenterItem {
    return {
      fileId: 0, path: f.path, name: f.name, kind: refineKindByName(kindOfDiskDir(f.dir), f.name), size: f.size,
      downloaded: f.size, state: DC_STATE_COMPLETE, source: DC_SOURCE_DISK, mtime: f.mtimeSec * 1000, preview: '',
      chatId: 0, messageId: 0, mimeType: '', session: '', savedLocal: false, speed: 0
    };
  }

  private removeDiskPath(path: string): void {
    const index: number = this.diskFiles.findIndex((f: TdCacheFile): boolean => f.path === path);
    if (index >= 0) {
      this.diskFiles = this.diskFiles.filter((_f: TdCacheFile, i: number): boolean => i !== index);
      if (index < this.diskLoaded) {
        this.diskLoaded--;
      }
    }
    this.disk = this.disk.filter((m: DownloadCenterItem): boolean => m.path !== path);
  }

  // 存储卡片的两个数：缓存总占用（getStorageStatistics 可能要几秒）和设备可用空间，各跑各的，回来再刷。
  private loadStats(): void {
    getDetailedStorageUsage(0).then((usage: DetailedStorageUsage): void => {
      this.totalCacheBytes = usage.size;
      this.notifyNow();
    }).catch((e: Object): void => {
      logE(`DownloadCenterStore.loadStats failed: ${JSON.stringify(e)}`);
    });
    storageStatistics.getFreeSize().then((free: number): void => {
      this.freeBytes = free;
      this.notifyNow();
    }).catch((e: Object): void => {
      logE(`DownloadCenterStore.freeSize failed: ${JSON.stringify(e)}`);
    });
  }

  // 分批向 getFile 要当前状态。查不到的 fileId（文件记录已失效）也算作陈旧。
  private async refreshFiles(ids: number[], onStale: (id: number) => void): Promise<void> {
    for (let i = 0; i < ids.length && !this.disposed; i += GETFILE_BATCH) {
      const batch: number[] = ids.slice(i, i + GETFILE_BATCH);
      await Promise.all(batch.map((id: number): Promise<void> => {
        const req: TdRequest = { '@type': 'getFile' };
        req['file_id'] = id;
        return getTdClient().send(req).then((f: TdObject): void => {
          if (this.applyFile(f)) {
            onStale(id);
          }
        }).catch((_e: Object): void => { onStale(id); });
      }));
      this.scheduleNotify();
    }
  }

  private watchFiles(): void {
    if (this.unsubFile !== null) {
      return;
    }
    this.unsubFile = getTdClient().onUpdate('updateFile', (u: TdObject): void => {
      const f = u['file'] as TdObject | undefined;
      if (f !== undefined && this.tracks(f)) {
        this.applyFile(f);
        this.scheduleNotify();
      }
    });
  }

  // 只关心下载中心列出来的文件：应用里别处的缩略图、头像更新不必让页面重算。
  private tracks(file: TdObject): boolean {
    const id: number = (file['id'] as number | undefined) ?? 0;
    return id !== 0 && (this.findManager(id) !== undefined ||
      this.cached.some((m: DownloadCenterItem): boolean => m.fileId === id));
  }

  // 把一份 TDLib file 状态写进对应条目。返回 true = 这是一条缓存记录，而它一个字节都没有、也没在下载。
  private applyFile(file: TdObject): boolean {
    const id: number = (file['id'] as number | undefined) ?? 0;
    if (id === 0) {
      return false;
    }
    const inManager: boolean = this.findManager(id) !== undefined;
    const inCache: boolean = this.cached.some((m: DownloadCenterItem): boolean => m.fileId === id);
    if (!inManager && !inCache) {
      return false;
    }
    const local = file['local'] as TdObject | undefined;
    const done: boolean = local !== undefined && ((local['is_downloading_completed'] as boolean | undefined) ?? false);
    const active: boolean = local !== undefined && ((local['is_downloading_active'] as boolean | undefined) ?? false);
    const size: number = Math.max((file['size'] as number | undefined) ?? 0, (file['expected_size'] as number | undefined) ?? 0);
    const got: number = local !== undefined
      ? Math.max((local['downloaded_size'] as number | undefined) ?? 0, (local['downloaded_prefix_size'] as number | undefined) ?? 0)
      : 0;
    const path: string = done && local !== undefined ? ((local['path'] as string | undefined) ?? '') : '';
    this.trackSpeed(id, got, active && !done);
    if (active) {
      this.failedIds.delete(id);
    }
    if (inManager) {
      const paused: boolean = this.pausedIds.has(id);
      const update = (m: DownloadCenterItem): DownloadCenterItem => m.fileId !== id ? m
        : withFileState(m, path, size, done ? size : got, managerState(done, active, paused));
      this.managerActive = this.managerActive.map(update);
      this.managerDone = this.managerDone.map(update);
    }
    let staleCache: boolean = false;
    if (inCache) {
      this.cached = this.cached.map((m: DownloadCenterItem): DownloadCenterItem => m.fileId !== id ? m
        : withFileState(m, path, size > 0 ? size : m.size, done ? size : got,
          done ? DC_STATE_COMPLETE : (active ? DC_STATE_DOWNLOADING : DC_STATE_PARTIAL)));
      staleCache = !done && !active && got <= 0 && !isBackgroundCaching(id);
    }
    return staleCache;
  }

  private trackSpeed(id: number, bytes: number, active: boolean): void {
    if (!active) {
      this.clearSpeed(id);
      return;
    }
    const now: number = Date.now();
    const prev: SpeedSample | undefined = this.samples.get(id);
    if (prev === undefined) {
      this.samples.set(id, { bytes: bytes, at: now });
      return;
    }
    const elapsed: number = now - prev.at;
    if (elapsed < SPEED_MIN_INTERVAL_MS) {
      return;
    }
    this.speeds.set(id, nextSpeed(this.speeds.get(id) ?? 0, bytes - prev.bytes, elapsed));
    this.samples.set(id, { bytes: bytes, at: now });
  }

  private clearSpeed(id: number): void {
    this.speeds.delete(id);
    this.samples.delete(id);
  }

  private setManagerState(fileId: number, state: string): void {
    const update = (m: DownloadCenterItem): DownloadCenterItem => m.fileId !== fileId ? m
      : withFileState(m, m.path, m.size, m.downloaded, state);
    this.managerActive = this.managerActive.map(update);
    this.managerDone = this.managerDone.map(update);
  }

  private setCachedState(fileId: number, state: string): void {
    this.cached = this.cached.map((m: DownloadCenterItem): DownloadCenterItem => m.fileId !== fileId ? m
      : withFileState(m, m.path, m.size, m.downloaded, state));
  }

  private cacheRecordOf(it: DownloadCenterItem): CacheRecord {
    return {
      fileId: it.fileId, chatId: it.chatId, messageId: it.messageId, kind: it.kind, name: it.name, size: it.size,
      mimeType: it.mimeType, preview: it.preview, background: true, addedAt: Date.now()
    };
  }

  private async deleteTdFile(fileId: number): Promise<void> {
    const req: TdRequest = { '@type': 'deleteFile' };
    req['file_id'] = fileId;
    await getTdClient().send(req);
  }

  private dropFile(fileId: number): void {
    forgetCachedMedia(fileId);
    this.failedIds.delete(fileId);
    this.pausedIds.delete(fileId);
    this.backgroundIds.delete(fileId);
    this.clearSpeed(fileId);
    this.managerActive = this.managerActive.filter((m: DownloadCenterItem): boolean => m.fileId !== fileId);
    this.managerDone = this.managerDone.filter((m: DownloadCenterItem): boolean => m.fileId !== fileId);
    this.cached = this.cached.filter((m: DownloadCenterItem): boolean => m.fileId !== fileId);
    this.notifyNow();
  }

  private scheduleNotify(): void {
    if (this.disposed || this.notifyTimer !== -1) {
      return;
    }
    this.notifyTimer = setTimeout((): void => {
      this.notifyTimer = -1;
      if (!this.disposed) {
        this.onChange();
      }
    }, NOTIFY_THROTTLE_MS);
  }

  private notifyNow(): void {
    if (this.disposed) {
      return;
    }
    if (this.notifyTimer !== -1) {
      clearTimeout(this.notifyTimer);
      this.notifyTimer = -1;
    }
    this.onChange();
  }
}

function downloadIdOf(it: DownloadCenterItem): string {
  return it.fileId !== 0 ? `${it.fileId}` : it.path;
}
