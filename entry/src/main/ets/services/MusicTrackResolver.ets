import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  MusicTrack, musicTrackFromMessage, musicTrackKey, MusicTrackRef, parseMusicTrackKey
} from '../util/musicTrackModel';
import { logE } from '../util/log';

// 按曲目键把歌取回来（2026-09-18，音乐中心的合集）。
//
// 【为什么需要它】合集里只存曲目键（会话 id + 消息 id，理由见 musicCollectionModel）。
// 曲库那边只加载了搜索结果的前几页，合集里的歌未必在其中——冷启动之后更是一首都不在。
// 键里有会话和消息 id，所以直接按 getMessage 取回原消息再解析成曲目即可，
// 不需要把曲目快照也落一份盘（那份快照必然和真实消息对不上：文件 id、本地路径都会变）。
//
// 【缓存】进程内按键缓存。取不到的（消息被删、退了群）也记一笔空，
// 否则每次打开合集详情都会为同一条已删消息再发一次请求。

const cache: Map<string, MusicTrack> = new Map<string, MusicTrack>();
const missing: Set<string> = new Set<string>();
const inFlight: Map<string, Promise<MusicTrack | null>> = new Map<string, Promise<MusicTrack | null>>();

// 曲库/搜索结果里见过的歌先存起来，合集详情就不必再请求一遍。
export function rememberMusicTracks(tracks: MusicTrack[]): void {
  tracks.forEach((track: MusicTrack): void => {
    const key: string = musicTrackKey(track.chatId, track.messageId);
    cache.set(key, track);
    missing.delete(key);
  });
}

export function cachedMusicTrack(key: string): MusicTrack | null {
  return cache.get(key) ?? null;
}

function fetchTrack(key: string): Promise<MusicTrack | null> {
  const ref: MusicTrackRef | null = parseMusicTrackKey(key);
  if (ref === null) {
    missing.add(key);
    return Promise.resolve(null);
  }
  const req: TdRequest = { '@type': 'getMessage' };
  req['chat_id'] = ref.chatId;
  req['message_id'] = ref.messageId;
  return getTdClient().send(req).then((message: TdObject): MusicTrack | null => {
    const track: MusicTrack | null = musicTrackFromMessage(message);
    if (track === null) {
      missing.add(key);
      return null;
    }
    cache.set(key, track);
    return track;
  }).catch((e: TdError): MusicTrack | null => {
    missing.add(key);
    logE(`MusicTrackResolver.getMessage(${key}) failed: ${e.message}`);
    return null;
  }).finally((): void => {
    inFlight.delete(key);
  });
}

// 一组键 → 一组歌，顺序按传入的键，取不到的直接不出现在结果里。
export function resolveMusicTracks(keys: string[]): Promise<MusicTrack[]> {
  const jobs: Promise<MusicTrack | null>[] = keys.map((key: string): Promise<MusicTrack | null> => {
    const hit: MusicTrack | undefined = cache.get(key);
    if (hit !== undefined) {
      return Promise.resolve(hit);
    }
    if (missing.has(key)) {
      return Promise.resolve(null);
    }
    const running: Promise<MusicTrack | null> | undefined = inFlight.get(key);
    if (running !== undefined) {
      return running;
    }
    const started: Promise<MusicTrack | null> = fetchTrack(key);
    inFlight.set(key, started);
    return started;
  });
  return Promise.all(jobs).then((tracks: (MusicTrack | null)[]): MusicTrack[] => {
    const out: MusicTrack[] = [];
    tracks.forEach((track: MusicTrack | null): void => {
      if (track !== null) {
        out.push(track);
      }
    });
    return out;
  });
}

// 换账号时清掉：曲目键是「会话 id + 消息 id」，两个账号会撞。
export function resetMusicTrackCache(): void {
  cache.clear();
  missing.clear();
  inFlight.clear();
}
