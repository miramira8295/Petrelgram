import { common } from '@kit.AbilityKit';
import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { CacheRecord } from '../util/cacheRegistryModel';
import {
  cachedMediaRecords, cacheRecordFor, currentCacheSlot, ensureCacheRegistry, isBackgroundCaching, noteCachedMedia,
  setBackgroundCaching, setCacheAllowCellular, setCachePaused
} from '../store/CacheRegistry';
import { KEY_BG_CACHE_WIFI_ONLY, KEY_CURRENT_NETWORK_TYPE } from '../store/AppSettings';
import { subscribeNetworkType } from './NetworkStateService';
import { acquireTransferKeepAlive, releaseTransferKeepAlive } from './DownloadSaveNotification';
import { backgroundCacheNotifier } from './BackgroundCacheNotifier';
import { publishProgress } from '../util/mediaProgressChannel';
import { displayNameOf, progressPercent } from '../util/downloadCenterModel';
import { dcKindLabel } from '../util/downloadCenterLabels';
import {
  BG_WAIT_NONE, BG_WAIT_WIFI, cacheWaitReason, MAX_IDLE_REARMS, messageHasFile, resumableCacheRecords
} from '../util/backgroundCacheModel';
import { logE, logI, logW } from '../util/log';

// 「后台缓存」（2026-09-15，媒体查看器右上角菜单 / 消息长按 / 多选顶栏 / 下载中心「继续」）。
//
// 走 downloadFile：不进 TDLib 的下载管理器、不导出到相册或下载目录，文件只留在 TDLib 的缓存里（缓存上限照常清理，
// 用户明确说过这是对的）；同时登记到缓存记录（store/CacheRegistry），下载中心据此显示进度。
//
// 【通知栏 + 退出不停】每条后台缓存持有数据传输长时任务的一份引用（与显式保存共用一个），进度汇总成通知栏的一行
// （services/BackgroundCacheNotifier）。没有长时任务时，应用一退到后台几秒就被系统冻结，TDLib 的下载跟着停。
//
// 【网络门控】「只在 Wi‑Fi 下后台缓存」（默认开）：蜂窝下真的让 TDLib 停下，显示「等待 Wi‑Fi」，回到 Wi‑Fi 自动继续；
// 单条可以「用流量继续」（落盘）。断网时照样发起，TDLib 自己会等网络回来，界面显示「等待网络」。
//
// 【会被别人改掉下载范围】TDLib 同一个文件只留一组 offset/limit（见 memory：tdlib-download-single-range）。
// 用户正看着这个视频时，流式播放按位置发的分段请求会把整份下载夹成一段；那段下完、播放器关了，下载就停在半路。
// 所以盯着 updateFile：不再下载、又没下完，就重发整份。重发有 2 秒节流——节流期内到的「停了」不能丢，
// 排定时器补发（以前直接丢：点完「后台缓存」马上关查看器，停止的那次更新正好落在 2 秒内，之后再没有更新来触发）。
//
// 【重启续上 / 切账号】登录就绪时（pages/Index）续上当前账号没被暂停的后台缓存，续之前拿来源消息核对 fileId；
// 其它账号的缓存任务作废（它们挂在已经换掉的 TDLib 实例上）。
//
// 进度同时发到 mediaProgressChannel：聊天里这条视频的气泡跟着显示进度环和百分比。

// 最低档：不和正在看的内容抢带宽。
const BACKGROUND_CACHE_PRIORITY: number = 1;
const REARM_MIN_INTERVAL_MS: number = 2000;

interface CacheTask {
  slot: string;
  title: string;
  chatId: number;
  messageId: number;
  keepAliveToken: number;
  rearmTimer: number;
  idleRearms: number;
  lastBytes: number;
  downloaded: number;
  size: number;
  waiting: string;
  armed: boolean;
}

let unsubFile: (() => void) | null = null;
let unsubNetwork: (() => void) | null = null;
const resumedSlots: Set<string> = new Set<string>();
const lastArmedAt: Map<number, number> = new Map<number, number>();
const tasks: Map<number, CacheTask> = new Map<number, CacheTask>();
const listeners: Set<() => void> = new Set<() => void>();

// 下载中心订阅：等待原因、任务增减一变就刷新。
export function subscribeBackgroundCache(listener: () => void): () => void {
  listeners.add(listener);
  return (): void => {
    listeners.delete(listener);
  };
}

// 这一条此刻为什么没在下：'' / 'wifi' / 'network'（util/backgroundCacheModel 的 BG_WAIT_*）。
export function backgroundCacheWaitReason(fileId: number): string {
  const task: CacheTask | undefined = tasks.get(fileId);
  return task !== undefined ? task.waiting : BG_WAIT_NONE;
}

export async function startBackgroundCache(context: common.UIAbilityContext, rec: CacheRecord): Promise<void> {
  logI(`[DC] background cache start file=${rec.fileId}`);
  await ensureCacheRegistry(context);
  noteCachedMedia(rec);
  setCachePaused(rec.fileId, false);
  setBackgroundCaching(rec.fileId, true);
  backgroundCacheNotifier.bind(context, (): void => { pauseAllBackgroundCaches(); });
  ensureTask(context, rec);
  watchFiles();
  watchNetwork();
  await applyGate(rec.fileId);
}

// 下载中心「用流量继续」：这一条不再受「只在 Wi‑Fi 下后台缓存」限制（落盘，重启后仍有效）。
export async function allowCellularForBackgroundCache(context: common.UIAbilityContext, rec: CacheRecord): Promise<void> {
  await ensureCacheRegistry(context);
  setCacheAllowCellular(rec.fileId, true);
  if (tasks.has(rec.fileId)) {
    await applyGate(rec.fileId);
  } else {
    await startBackgroundCache(context, rec);
  }
}

// 下载中心切了「只在 Wi‑Fi 下后台缓存」开关。
export function onBackgroundCachePolicyChanged(): void {
  regateAll();
}

// 通知栏「全部暂停」：每一条都按用户暂停处理（重启后不自动续上）。
export function pauseAllBackgroundCaches(): void {
  for (const id of Array.from(tasks.keys())) {
    stopBackgroundCache(id, true).catch((e: Object): void => {
      logW(`BackgroundCache pauseAll(${id}) failed: ${JSON.stringify(e)}`);
    });
  }
}

// 停掉后台缓存（下载中心「暂停」「取消」、通知栏「全部暂停」）：先摘标记，免得 updateFile 回来又被重新发起；
// 再让 TDLib 停下。paused = 用户暂停（重启后不自动续上）；取消时调用方随后会删掉整条记录，传 false。
export async function stopBackgroundCache(fileId: number, paused: boolean = true): Promise<void> {
  if (paused) {
    setCachePaused(fileId, true);
  }
  endBackgroundCache(fileId, true);
  await cancelDownload(fileId);
}

// 登录就绪后调（pages/Index，切账号之后也会再来）：其它账号的任务作废；当前账号每个进程续一次。
export function resumeBackgroundCachesOnce(context: common.UIAbilityContext): void {
  const slot: string = currentCacheSlot();
  dropTasksOfOtherAccounts(slot);
  if (resumedSlots.has(slot)) {
    return;
  }
  resumedSlots.add(slot);
  resumeBackgroundCaches(context).catch((e: Object): void => {
    logE(`BackgroundCache resume failed: ${JSON.stringify(e)}`);
  });
}

function dropTasksOfOtherAccounts(slot: string): void {
  const stale: number[] = [];
  tasks.forEach((task: CacheTask, id: number): void => {
    if (task.slot !== slot) {
      stale.push(id);
    }
  });
  if (stale.length === 0) {
    return;
  }
  for (const id of stale) {
    endBackgroundCache(id, true);
  }
  // 文件更新的订阅挂在旧的 TDLib 实例上，下一次发起时重挂。
  if (unsubFile !== null) {
    unsubFile();
    unsubFile = null;
  }
}

async function resumeBackgroundCaches(context: common.UIAbilityContext): Promise<void> {
  await ensureCacheRegistry(context);
  const candidates: CacheRecord[] = resumableCacheRecords(cachedMediaRecords());
  let resumed: number = 0;
  for (const rec of candidates) {
    if (isBackgroundCaching(rec.fileId) || !(await stillPending(rec))) {
      continue;
    }
    try {
      await startBackgroundCache(context, rec);
      resumed++;
    } catch (e) {
      logW(`BackgroundCache resume(${rec.fileId}) failed: ${JSON.stringify(e)}`);
    }
  }
  logI(`[DC] background cache resumed ${resumed}/${candidates.length}`);
}

// 来源消息里还是这个文件，而且还没下完。
async function stillPending(rec: CacheRecord): Promise<boolean> {
  try {
    const msgReq: TdRequest = { '@type': 'getMessage' };
    msgReq['chat_id'] = rec.chatId;
    msgReq['message_id'] = rec.messageId;
    const msg: TdObject = await getTdClient().send(msgReq);
    if (!messageHasFile(msg['content'] as Object | undefined, rec.fileId)) {
      return false;
    }
    const fileReq: TdRequest = { '@type': 'getFile' };
    fileReq['file_id'] = rec.fileId;
    const file: TdObject = await getTdClient().send(fileReq);
    const local = file['local'] as TdObject | undefined;
    return !(local !== undefined && ((local['is_downloading_completed'] as boolean | undefined) ?? false));
  } catch (e) {
    return false;
  }
}

function ensureTask(context: common.UIAbilityContext, rec: CacheRecord): void {
  if (tasks.has(rec.fileId)) {
    return;
  }
  const title: string = displayNameOf(rec.name) !== '' ? rec.name : dcKindLabel(rec.kind);
  tasks.set(rec.fileId, {
    slot: currentCacheSlot(), title: title, chatId: rec.chatId, messageId: rec.messageId,
    keepAliveToken: acquireTransferKeepAlive(context), rearmTimer: -1, idleRearms: 0, lastBytes: -1,
    downloaded: 0, size: rec.size, waiting: BG_WAIT_NONE, armed: false
  });
  reportTask(rec.fileId);
}

// 按当前网络决定这一条是发起下载还是等着。蜂窝下被挡住的真的让 TDLib 停下；断网照样发起——TDLib 自己会等网络回来。
async function applyGate(fileId: number): Promise<void> {
  const task: CacheTask | undefined = tasks.get(fileId);
  if (task === undefined) {
    return;
  }
  const rec: CacheRecord | undefined = cacheRecordFor(fileId);
  const reason: string = cacheWaitReason(AppStorage.get<string>(KEY_CURRENT_NETWORK_TYPE) ?? 'other',
    AppStorage.get<boolean>(KEY_BG_CACHE_WIFI_ONLY) ?? true, rec !== undefined && rec.allowCellular === true);
  task.waiting = reason;
  reportTask(fileId);
  notifyListeners();
  if (reason === BG_WAIT_WIFI) {
    if (task.armed) {
      task.armed = false;
      clearRearm(task);
      lastArmedAt.delete(fileId);
      await cancelDownload(fileId);
    }
    return;
  }
  if (!task.armed) {
    task.armed = true;
    task.idleRearms = 0;
    try {
      await armDownload(fileId);
    } catch (e) {
      endBackgroundCache(fileId, false);
      throw e as Error;
    }
  }
}

function regateAll(): void {
  for (const id of Array.from(tasks.keys())) {
    applyGate(id).catch((e: Object): void => {
      logW(`BackgroundCache regate(${id}) failed: ${JSON.stringify(e)}`);
    });
  }
}

// 结束一条后台缓存。stopped = 用户叫停（通知栏里去掉它）；否则是失败（发一行「后台缓存失败」）。
function endBackgroundCache(fileId: number, stopped: boolean): void {
  setBackgroundCaching(fileId, false);
  lastArmedAt.delete(fileId);
  const task: CacheTask | undefined = tasks.get(fileId);
  if (task !== undefined) {
    tasks.delete(fileId);
    clearRearm(task);
    releaseTransferKeepAlive(task.keepAliveToken);
    if (stopped) {
      backgroundCacheNotifier.remove(fileId);
    } else {
      backgroundCacheNotifier.failed(fileId, task.title);
    }
  }
  stopWatchingIfIdle();
  notifyListeners();
}

function armDownload(fileId: number): Promise<void> {
  lastArmedAt.set(fileId, Date.now());
  const req: TdRequest = { '@type': 'downloadFile' };
  req['file_id'] = fileId;
  req['priority'] = BACKGROUND_CACHE_PRIORITY;
  req['offset'] = 0;
  req['limit'] = 0;
  req['synchronous'] = false;
  return getTdClient().send(req).then((f: TdObject): void => { onFile(f); });
}

function cancelDownload(fileId: number): Promise<void> {
  const req: TdRequest = { '@type': 'cancelDownloadFile' };
  req['file_id'] = fileId;
  req['only_if_pending'] = false;
  return getTdClient().send(req).then((_r: TdObject): void => {});
}

function watchFiles(): void {
  if (unsubFile !== null) {
    return;
  }
  unsubFile = getTdClient().onUpdate('updateFile', (u: TdObject): void => {
    const f = u['file'] as TdObject | undefined;
    if (f !== undefined) {
      onFile(f);
    }
  });
}

function watchNetwork(): void {
  if (unsubNetwork !== null) {
    return;
  }
  unsubNetwork = subscribeNetworkType((_network: string): void => { regateAll(); });
}

function onFile(file: TdObject): void {
  const id: number = (file['id'] as number | undefined) ?? 0;
  const task: CacheTask | undefined = id !== 0 ? tasks.get(id) : undefined;
  if (task === undefined || !isBackgroundCaching(id)) {
    return;
  }
  const local = file['local'] as TdObject | undefined;
  const done: boolean = local !== undefined && ((local['is_downloading_completed'] as boolean | undefined) ?? false);
  const active: boolean = local !== undefined && ((local['is_downloading_active'] as boolean | undefined) ?? false);
  const size: number = Math.max((file['size'] as number | undefined) ?? 0, (file['expected_size'] as number | undefined) ?? 0);
  const got: number = local !== undefined
    ? Math.max((local['downloaded_size'] as number | undefined) ?? 0, (local['downloaded_prefix_size'] as number | undefined) ?? 0)
    : 0;
  publishProgress(id, done ? 100 : progressPercent(got, size, false));
  task.downloaded = done ? Math.max(size, got) : got;
  if (size > 0) {
    task.size = size;
  }
  if (done) {
    setBackgroundCaching(id, false);
    lastArmedAt.delete(id);
    tasks.delete(id);
    clearRearm(task);
    releaseTransferKeepAlive(task.keepAliveToken);
    backgroundCacheNotifier.completed(id, task.title, task.chatId, task.messageId);
    stopWatchingIfIdle();
    notifyListeners();
    return;
  }
  if (got > task.lastBytes) {
    task.idleRearms = 0;
    task.lastBytes = got;
  }
  reportTask(id);
  if (!active && task.armed && task.waiting === BG_WAIT_NONE) {
    scheduleRearm(id);
  }
}

// 不在下又没下完：重发整份。离上次发不到 2 秒就排定时器补发，不丢。
function scheduleRearm(fileId: number): void {
  const found: CacheTask | undefined = tasks.get(fileId);
  if (found === undefined || found.rearmTimer !== -1) {
    return;
  }
  const task: CacheTask = found;
  const wait: number = Math.max(0, REARM_MIN_INTERVAL_MS - (Date.now() - (lastArmedAt.get(fileId) ?? 0)));
  task.rearmTimer = setTimeout((): void => {
    task.rearmTimer = -1;
    if (!isBackgroundCaching(fileId) || tasks.get(fileId) !== task || task.waiting !== BG_WAIT_NONE) {
      return;
    }
    task.idleRearms++;
    if (task.idleRearms > MAX_IDLE_REARMS) {
      logW(`BackgroundCache(${fileId}) gave up after ${MAX_IDLE_REARMS} idle rearms`);
      endBackgroundCache(fileId, false);
      return;
    }
    armDownload(fileId).catch((e: Object): void => {
      logE(`BackgroundCache rearm(${fileId}) failed: ${JSON.stringify(e)}`);
    });
  }, wait);
}

function reportTask(fileId: number): void {
  const task: CacheTask | undefined = tasks.get(fileId);
  if (task === undefined) {
    return;
  }
  backgroundCacheNotifier.update(fileId, {
    title: task.title, downloaded: task.downloaded, size: task.size, waiting: task.waiting
  });
}

function notifyListeners(): void {
  listeners.forEach((listener: () => void): void => {
    try {
      listener();
    } catch (e) {
      logE(`BackgroundCache listener failed: ${e}`);
    }
  });
}

function clearRearm(task: CacheTask): void {
  if (task.rearmTimer !== -1) {
    clearTimeout(task.rearmTimer);
    task.rearmTimer = -1;
  }
}

function stopWatchingIfIdle(): void {
  if (tasks.size > 0) {
    return;
  }
  if (unsubFile !== null) {
    unsubFile();
    unsubFile = null;
  }
  if (unsubNetwork !== null) {
    unsubNetwork();
    unsubNetwork = null;
  }
}
