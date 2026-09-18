import { fileIo as fs } from '@kit.CoreFileKit';
import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  AUDIO_HEADER_PREFIX_BYTES, AudioSourceInfo, audioSourceKnown, probeAudioHeader
} from '../util/audioHeaderProbe';
import { MusicTrack, musicTrackKey } from '../util/musicTrackModel';
import { logE, logI } from '../util/log';

// 音源信息的探测（2026-09-18，音乐中心）。解析本身在 util/audioHeaderProbe（纯函数、有单测），
// 这里只负责"把文件开头那几十 KB 弄到手"，以及缓存与并发去重。
//
// 【两条取字节的路】
//   · 本地已下载：直接 fileIo 读前 64 KB；
//   · 还在云端：TDLib 的 downloadFile 支持 offset/limit，只取前 64 KB 就够解头部——
//     不必为了显示"96 kHz"把一首 70 MB 的无损整个拉下来。
//     注意同一个文件 TDLib 只保留一组 offset/limit（见 [[tdlib-download-single-range]]），
//     所以这里只发一次、不分多段，也不取消真正在播放的那首的下载。
//
// 【缓存】结果按曲目键缓存，**失败也缓存**：解不出来的文件再探一次还是解不出来，
// 而播放页每次切歌都会问一次。

const PROBE_PRIORITY: number = 1;   // 比播放（MEDIA_VIEWING_PRIORITY）低，别抢下载带宽
const PROBE_TIMEOUT_MS: number = 20000;

const cache: Map<string, AudioSourceInfo> = new Map<string, AudioSourceInfo>();
const inFlight: Map<string, Promise<AudioSourceInfo>> = new Map<string, Promise<AudioSourceInfo>>();

function unknown(): AudioSourceInfo {
  return { format: '', sampleRateHz: 0, bitDepth: 0, channels: 0, bitrateKbps: 0, durationSec: 0 };
}

// 读文件开头的一段。读不到（文件还没落盘、权限、被删）一律返回空数组，由调用方当"不知道"。
function readPrefix(path: string): Uint8Array {
  if (path === '') {
    return new Uint8Array(0);
  }
  let fd: number = -1;
  try {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    fd = file.fd;
    const buffer: ArrayBuffer = new ArrayBuffer(AUDIO_HEADER_PREFIX_BYTES);
    const read: number = fs.readSync(fd, buffer, { offset: 0, length: AUDIO_HEADER_PREFIX_BYTES });
    return read > 0 ? new Uint8Array(buffer.slice(0, read)) : new Uint8Array(0);
  } catch (e) {
    logE(`AudioMetadataProbe read failed: ${e}`);
    return new Uint8Array(0);
  } finally {
    if (fd >= 0) {
      try {
        fs.closeSync(fd);
      } catch (e) {
        logE(`AudioMetadataProbe close failed: ${e}`);
      }
    }
  }
}

// 只下前 64 KB。synchronous=true 让这一发等到那段真的落盘再回来。
function downloadPrefix(fileId: number): Promise<string> {
  const req: TdRequest = { '@type': 'downloadFile' };
  req['file_id'] = fileId;
  req['priority'] = PROBE_PRIORITY;
  req['offset'] = 0;
  req['limit'] = AUDIO_HEADER_PREFIX_BYTES;
  req['synchronous'] = true;
  return getTdClient().send(req, PROBE_TIMEOUT_MS).then((file: TdObject): string => {
    const local = file['local'] as TdObject | undefined;
    if (local === undefined) {
      return '';
    }
    const downloaded: number = (local['downloaded_prefix_size'] as number | undefined) ?? 0;
    return downloaded > 0 ? ((local['path'] as string | undefined) ?? '') : '';
  }).catch((e: TdError): string => {
    logE(`AudioMetadataProbe downloadFile failed: ${e.message}`);
    return '';
  });
}

// 这首歌的音源信息。同一首歌重复调只会真探一次；探不出来返回全 0 的结果，
// 界面据此退回"用文件大小估算的码率"。
export function probeMusicSource(track: MusicTrack): Promise<AudioSourceInfo> {
  const key: string = musicTrackKey(track.chatId, track.messageId);
  const cached: AudioSourceInfo | undefined = cache.get(key);
  if (cached !== undefined) {
    return Promise.resolve(cached);
  }
  const running: Promise<AudioSourceInfo> | undefined = inFlight.get(key);
  if (running !== undefined) {
    return running;
  }
  const started: Promise<AudioSourceInfo> = probeTrack(track).then((info: AudioSourceInfo): AudioSourceInfo => {
    cache.set(key, info);
    inFlight.delete(key);
    if (audioSourceKnown(info)) {
      logI(`[Music] probed ${info.format} ${info.sampleRateHz}Hz ${info.bitDepth}bit`);
    }
    return info;
  });
  inFlight.set(key, started);
  return started;
}

function probeTrack(track: MusicTrack): Promise<AudioSourceInfo> {
  const local: Uint8Array = readPrefix(track.localPath);
  if (local.length > 0) {
    const info: AudioSourceInfo = probeAudioHeader(local);
    if (audioSourceKnown(info)) {
      return Promise.resolve(info);
    }
  }
  if (track.fileId <= 0) {
    return Promise.resolve(unknown());
  }
  return downloadPrefix(track.fileId).then((path: string): AudioSourceInfo => {
    const bytes: Uint8Array = readPrefix(path);
    return bytes.length > 0 ? probeAudioHeader(bytes) : unknown();
  });
}

// 换账号时清掉：曲目键是"会话 id + 消息 id"，两个账号会撞。
export function resetMusicSourceCache(): void {
  cache.clear();
  inFlight.clear();
}
