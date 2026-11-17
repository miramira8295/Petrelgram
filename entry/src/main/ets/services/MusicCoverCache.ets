import { TdClient } from '../tdkit/TdClient';
import { currentNowPlaying, publishNowPlaying } from '../util/nowPlayingChannel';
import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logE } from '../util/log';

// 专辑封面（messageAudio 的 album_cover_thumbnail）的取数与缓存。
//
// 【为什么单独一层】封面缩略图是**按文件 id**取的，而同一张专辑会在播放页、
// 播放列表、合集详情、搜索结果里同时出现好几次。不缓存的话每处各发一次
// downloadFile，滚动时尤其浪费；缓存在这里，谁先要谁触发，其余直接命中。
//
// 【失败也缓存】没有内嵌封面、或者缩略图取不回来的曲目，每次进来都会再问一次，
// 而答案不会变。存一条空串当"问过了，没有"，界面据此退回渐变色块。

const cache: Map<number, string> = new Map<number, string>();
const inFlight: Map<number, Promise<string>> = new Map<number, Promise<string>>();

// 缩略图，优先级压到最低：它只是好看，不该和正在播的那首抢带宽。
const COVER_PRIORITY: number = 1;
const COVER_CACHE_LIMIT: number = 128;
const COVER_PENDING_LIMIT: number = 16;
let owner: TdClient | null = null;
let epoch: number = 0;
function syncOwner(): TdClient {
  const client = getTdClient();
  if (owner !== client) { resetMusicCoverCache(); owner = client; }
  return client;
}
function remember(fileId: number, path: string): void {
  cache.delete(fileId); cache.set(fileId, path);
  if (cache.size > COVER_CACHE_LIMIT) { cache.delete(cache.keys().next().value as number); }
  const playing = currentNowPlaying();
  if (path !== '' && playing?.documentTrack?.coverFileId === fileId && playing.coverPath !== path) {
    publishNowPlaying({ chatId: playing.chatId, messageId: playing.messageId, sourceMessageId: playing.sourceMessageId,
      documentTrack: playing.documentTrack, documentPlaylist: playing.documentPlaylist, title: playing.title,
      performer: playing.performer, coverPath: path, path: playing.path, durationSec: playing.durationSec });
  }
}

// 已经拿到的路径；'' 表示没有或还没取。界面用它同步渲染，不必等 Promise。
export function cachedMusicCover(fileId: number): string {
  if (fileId <= 0) { return ''; }
  syncOwner(); return cache.get(fileId) ?? '';
}

export function ensureMusicCover(fileId: number): Promise<string> {
  if (fileId <= 0) {
    return Promise.resolve('');
  }
  const client = syncOwner(), token = epoch;
  const hit: string | undefined = cache.get(fileId);
  if (hit !== undefined) {
    return Promise.resolve(hit);
  }
  const running: Promise<string> | undefined = inFlight.get(fileId);
  if (running !== undefined) {
    return running;
  }
  if (inFlight.size >= COVER_PENDING_LIMIT) { return Promise.resolve(''); }
  const req: TdRequest = { '@type': 'downloadFile' };
  req['file_id'] = fileId;
  req['priority'] = COVER_PRIORITY;
  req['synchronous'] = true;
  const started: Promise<string> = client.send(req).then((file: TdObject): string => {
    if (token !== epoch || owner !== client || client !== getTdClient()) { return ''; }
    const local = file['local'] as TdObject | undefined;
    const path: string = local?.['is_downloading_completed'] === true ? ((local['path'] as string | undefined) ?? '') : '';
    remember(fileId, path);
    return path;
  }).catch((e: TdError): string => {
    // 失败也记一笔，别让同一个取不到的封面每次滚过都再发一遍请求。
    if (token !== epoch || owner !== client || client !== getTdClient()) { return ''; }
    remember(fileId, '');
    logE(`MusicCoverCache.downloadFile(${fileId}) failed: ${e.message}`);
    return '';
  }).finally((): void => {
    if (token === epoch && inFlight.get(fileId) === started) { inFlight.delete(fileId); }
  });
  inFlight.set(fileId, started);
  return started;
}

// 换账号时清掉：文件 id 是按账号发的。
export function resetMusicCoverCache(): void {
  epoch++; owner = null;
  cache.clear();
  inFlight.clear();
}

// 给 Image() 用的来源串。TDLib 给的是绝对路径，要加 file:// 前缀。
export function musicCoverSource(path: string): string {
  return path.startsWith('/') ? `file://${path}` : path;
}
