import { fileIo as fs } from '@kit.CoreFileKit';
import {
  AUDIO_HEADER_PREFIX_BYTES, AudioSourceInfo, audioSourceKnown, probeAudioHeader
} from '../util/audioHeaderProbe';
import { MusicTrack, trackKeyOf } from '../util/musicTrackModel';
import { logE, logI } from '../util/log';

// 音源信息的探测（2026-09-18，音乐中心）。解析本身在 util/audioHeaderProbe（纯函数、有单测），
// 这里只负责"把文件开头那几十 KB 弄到手"，以及缓存与并发去重。
//
// 【只从本地文件读，不联网】原来还有第二条路：文件还在云端时用 downloadFile 的
// offset/limit 只取前 64 KB。**那条路已经删掉**——2026-09-20 真机日志：
//
//     AudioMetadataProbe downloadFile failed: Canceled by another downloadFile request
//     VoicePlayback failed message=...: "player state error"
//
// TDLib 对同一个文件**只保留一组 offset/limit**。探测开一段、边下边播的流式会话
// 开另一段，两边互相取消：探测报错，流被搅坏到解复用器嗅探不出媒体头，
// 表现就是"点了不播放"。音源信息是锦上添花，播放不是——冲突时让路的必须是它。
//
// 代价：云端没下完的曲目读不出真实采样率/位深，界面退回估算值（格式取 mime、
// 码率按大小÷时长）。等整首落地之后再进这一页就能读出来了。
//
// 【缓存】结果按曲目键缓存，**失败也缓存**：解不出来的文件再探一次还是解不出来，
// 而播放页每次切歌都会问一次。


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

// 这首歌的音源信息。同一首歌重复调只会真探一次；探不出来返回全 0 的结果，
// 界面据此退回"用文件大小估算的码率"。
export function probeMusicSource(track: MusicTrack): Promise<AudioSourceInfo> {
  const key: string = trackKeyOf(track);
  const cached: AudioSourceInfo | undefined = cache.get(key);
  if (cached !== undefined) {
    return Promise.resolve(cached);
  }
  const running: Promise<AudioSourceInfo> | undefined = inFlight.get(key);
  if (running !== undefined) {
    return running;
  }
  const hadLocal: boolean = track.localPath !== '';
  const started: Promise<AudioSourceInfo> = probeTrack(track).then((info: AudioSourceInfo): AudioSourceInfo => {
    // **只有读过本地文件的那一次才是最终答案。** 没有本地文件时这次是"还不能探"，
    // 缓存下去的话整首下完之后也不会再探一次，那一格就永远空着。
    if (hadLocal) {
      cache.set(key, info);
    }
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
  if (local.length === 0) {
    return Promise.resolve(unknown());
  }
  return Promise.resolve(probeAudioHeader(local));
}

// 换账号时清掉：曲目键是"会话 id + 消息 id"，两个账号会撞。
export function resetMusicSourceCache(): void {
  cache.clear();
  inFlight.clear();
}
