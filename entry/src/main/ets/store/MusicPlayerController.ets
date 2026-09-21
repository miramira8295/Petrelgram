import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  AudioSource, audioSourcePlayable, getVoicePlayback, localAudioSource, streamAudioSource, VoiceState
} from '../services/VoicePlayback';
import { clearNowPlaying, publishNowPlaying } from '../util/nowPlayingChannel';
import { cachedMusicCover } from '../services/MusicCoverCache';
import { MusicTrack, musicTrackKey, trackKeyOf } from '../util/musicTrackModel';
import { logE } from '../util/log';

// 音乐中心的播放控制（2026-09-18）。
//
// 【和 MusicQueue 的分工】那个是**会话内**的队列：上一首/下一首在当前会话的音频消息之间走，
// 由 ChatPage 持有。音乐中心的队列是跨会话的曲库或某个合集，所以另起一个，但**播放器是同一个**
// ——getVoicePlayback() 的全局单例。两处不会同时放：谁起播谁接管。
//
// 【为什么不是 @ObservedV2】页面是 V1（要用 @StorageProp 读安全区与省电设置），
// 控制器就做成普通类 + 快照订阅：状态变了推一份 MusicPlaybackSnapshot，页面拿去更新 @State。
//
// 【起播前要先有文件】曲库里的歌大多还在云端。play() 先看本地路径，没有就整首下下来再放；
// 下载期间 loading 为真，界面上那颗播放键转圈。

const PLAY_PRIORITY: number = 32;       // 用户点了就放，优先级高于探测（priority 1）
const DOWNLOAD_TIMEOUT_MS: number = 120000;

export interface MusicPlaybackSnapshot {
  // '' = 没有在放的曲目。
  trackKey: string;
  index: number;
  playing: boolean;
  // 正在下载或准备，播放键显示转圈。
  loading: boolean;
  positionMs: number;
  durationMs: number;
}

export type MusicPlaybackListener = (snapshot: MusicPlaybackSnapshot) => void;

export class MusicPlayerController {
  private queue: MusicTrack[] = [];
  private index: number = -1;
  private loadingKey: string = '';
  private voice: VoiceState;
  private listeners: MusicPlaybackListener[] = [];
  private unsubVoice: (() => void) | null = null;
  // 作废在途的下载：用户在等的时候又点了别的歌。
  private playSeq: number = 0;

  // 机器人搜来的歌在真正播之前要先落地成一条真消息（见 store/MusicBotSearchApi
  // 的 materializeBotTrack）。放在这里而不是页面上，是因为 playAt 是所有播放的
  // 唯一漏斗——next/prev/play 全经过它，挂在这儿上一首下一首才一起生效。
  private materializer: ((track: MusicTrack) => Promise<MusicTrack | null>) | null = null;

  setMaterializer(fn: (track: MusicTrack) => Promise<MusicTrack | null>): void {
    this.materializer = fn;
  }

  constructor() {
    this.voice = getVoicePlayback().current();
    this.unsubVoice = getVoicePlayback().subscribe((state: VoiceState): void => {
      this.voice = state;
      this.notify();
    });
    // 一首放完自动下一首（设计稿里播放列表是连续的）。
    getVoicePlayback().setMusicCompletionListener((): void => { this.next(); });
  }

  dispose(): void {
    this.playSeq++;
    this.listeners = [];
    if (this.unsubVoice !== null) {
      this.unsubVoice();
      this.unsubVoice = null;
    }
    getVoicePlayback().setMusicCompletionListener(null);
  }

  subscribe(listener: MusicPlaybackListener): () => void {
    this.listeners.push(listener);
    listener(this.snapshot());
    return (): void => {
      this.listeners = this.listeners.filter((l: MusicPlaybackListener): boolean => l !== listener);
    };
  }

  getQueue(): MusicTrack[] {
    return this.queue;
  }

  current(): MusicTrack | null {
    return this.index >= 0 && this.index < this.queue.length ? this.queue[this.index] : null;
  }

  snapshot(): MusicPlaybackSnapshot {
    const track: MusicTrack | null = this.current();
    const key: string = track !== null ? trackKeyOf(track) : '';
    const mine: boolean = track !== null && this.voice.playingId === track.messageId;
    return {
      trackKey: key,
      index: this.index,
      playing: mine && this.voice.status === 'playing',
      loading: this.loadingKey === key && key !== '' || (mine && this.voice.status === 'loading'),
      positionMs: mine ? this.voice.positionMs : 0,
      // 播放器还没报时长时用消息里的时长，进度条才不会从 0 长度开始。
      durationMs: mine && this.voice.durationMs > 0
        ? this.voice.durationMs
        : (track !== null ? track.durationSec * 1000 : 0)
    };
  }

  // 换一份队列（曲库、某个合集、搜索结果）。**不动正在放的那首**：换页签不该打断播放。
  setQueue(tracks: MusicTrack[]): void {
    const playingKey: string = this.current() !== null
      ? trackKeyOf(this.current()!) : '';
    this.queue = tracks;
    this.index = playingKey === ''
      ? -1
      : tracks.findIndex((t: MusicTrack): boolean => trackKeyOf(t) === playingKey);
    this.notify();
  }

  // 接管一首**已经在放**的歌——从会话页起播、用户随后才点开音乐中心的那种。
  // 不重新起播（那会把进度归零），只是让这一页知道当前放的是哪首。
  // 手上已经有曲目时什么都不做：那说明队列是音乐中心自己建的，别被旧的通道值盖掉。
  adopt(track: MusicTrack): void {
    if (this.current() !== null) {
      return;
    }
    this.queue = [track];
    this.index = 0;
    this.notify();
  }

  playAt(index: number): void {
    if (index < 0 || index >= this.queue.length) {
      return;
    }
    this.index = index;
    const track: MusicTrack = this.queue[index];
    const key: string = trackKeyOf(track);
    const seq: number = ++this.playSeq;
    // 还没落地的机器人结果：先发进收藏夹换回真消息，再按普通曲目走。
    // 落地要走网络（一次 send + 等真实 id），这段时间行上要转圈。
    if (track.botResultId !== '' && this.materializer !== null) {
      this.loadingKey = key;
      this.notify();
      this.materializer(track).then((real: MusicTrack | null): void => {
        if (seq !== this.playSeq) {
          return;   // 期间点了别的歌
        }
        this.loadingKey = '';
        if (real === null) {
          this.notify();
          return;
        }
        // 就地换掉队列里这一项：之后它就是一首普通的歌，加入合集、下载中心
        // 这些按 chatId/messageId 走的功能全部可用。
        this.queue = this.queue.map((t: MusicTrack): MusicTrack =>
          trackKeyOf(t) === key ? real : t);
        this.playAt(index);
      });
      return;
    }
    if (track.localPath !== '') {
      this.start(track);
      return;
    }
    // 边下边放：文件 id 和总字节数都在就直接出声，不再整首下完（2026-09-18 用户
    // 报的正是这条——视频早就是流式的）。size 为 0（TDLib 只给了 expected_size 的
    // 极少数情况）时定位不了，仍退回下载。
    if (track.fileSize > 0) {
      this.start(track);
      return;
    }
    this.loadingKey = key;
    this.notify();
    this.download(track.fileId).then((path: string): void => {
      if (seq !== this.playSeq) {
        return;   // 期间点了别的歌
      }
      this.loadingKey = '';
      if (path === '') {
        this.notify();
        return;
      }
      // 路径是刚下下来的，原来的 track 里还是空的——补一份再起播。
      const ready: MusicTrack = {
        chatId: track.chatId, messageId: track.messageId, title: track.title, artist: track.artist,
        album: track.album, durationSec: track.durationSec, fileId: track.fileId,
        fileSize: track.fileSize, mimeType: track.mimeType, fileName: track.fileName,
        localPath: path, coverFileId: track.coverFileId,
        coverMini: track.coverMini, botResultId: track.botResultId
      };
      this.queue = this.queue.map((t: MusicTrack): MusicTrack =>
        trackKeyOf(t) === key ? ready : t);
      this.start(ready);
    });
  }

  playTrack(track: MusicTrack): void {
    const key: string = trackKeyOf(track);
    const at: number = this.queue.findIndex((t: MusicTrack): boolean =>
      trackKeyOf(t) === key);
    if (at >= 0) {
      this.playAt(at);
      return;
    }
    // 不在当前队列里（例如从搜索结果点的）：接在队列尾巴上再放。
    this.queue = this.queue.concat([track]);
    this.playAt(this.queue.length - 1);
  }

  toggle(): void {
    const track: MusicTrack | null = this.current();
    if (track === null) {
      return;
    }
    const source: AudioSource = track.localPath !== ''
      ? localAudioSource(track.localPath)
      : streamAudioSource(track.fileId, track.fileSize, track.mimeType);
    if (!audioSourcePlayable(source)) {
      this.playAt(this.index);
      return;
    }
    getVoicePlayback().toggleMusicSource(track.messageId, source, track.durationSec);
  }

  // 设计稿：往回按一下先回到开头，3 秒内再按才是上一首。
  prev(): void {
    if (this.snapshot().positionMs > 3000) {
      this.seekFraction(0);
      return;
    }
    if (this.queue.length === 0) {
      return;
    }
    this.playAt((this.index - 1 + this.queue.length) % this.queue.length);
  }

  next(): void {
    if (this.queue.length === 0) {
      return;
    }
    this.playAt((this.index + 1) % this.queue.length);
  }

  seekFraction(fraction: number): void {
    const track: MusicTrack | null = this.current();
    if (track === null) {
      return;
    }
    getVoicePlayback().seek(track.messageId, Math.min(1, Math.max(0, fraction)));
  }

  stop(): void {
    const track: MusicTrack | null = this.current();
    getVoicePlayback().stop();
    if (track !== null) {
      clearNowPlaying(track.messageId);
    }
    this.index = -1;
    this.notify();
  }

  private start(track: MusicTrack): void {
    // 本地有文件就直接放，没有就走流（VoicePlayback 里那条回环 Range 源）。
    const source: AudioSource = track.localPath !== ''
      ? localAudioSource(track.localPath)
      : streamAudioSource(track.fileId, track.fileSize, track.mimeType);
    getVoicePlayback().startMusicSource(track.messageId, source, track.durationSec);
    // 底栏的迷你条靠这个通道认曲目——它对音乐中心一无所知（见 nowPlayingChannel）。
    publishNowPlaying({
      chatId: track.chatId,
      messageId: track.messageId,
      title: track.title,
      performer: track.artist,
      // 缓存里有就带上；没有也不在这儿发请求——迷你条没封面只是少张图，
      // 而起播这条路上不该插一次网络往返。
      coverPath: cachedMusicCover(track.coverFileId),
      path: track.localPath,
      durationSec: track.durationSec
    });
    this.notify();
  }

  private download(fileId: number): Promise<string> {
    if (fileId <= 0) {
      return Promise.resolve('');
    }
    const req: TdRequest = { '@type': 'downloadFile' };
    req['file_id'] = fileId;
    req['priority'] = PLAY_PRIORITY;
    req['offset'] = 0;
    req['limit'] = 0;          // 0 = 整首
    req['synchronous'] = true;
    return getTdClient().send(req, DOWNLOAD_TIMEOUT_MS).then((file: TdObject): string => {
      const local = file['local'] as TdObject | undefined;
      if (local === undefined || (local['is_downloading_completed'] as boolean | undefined) !== true) {
        return '';
      }
      return (local['path'] as string | undefined) ?? '';
    }).catch((e: TdError): string => {
      logE(`MusicPlayerController.downloadFile failed: ${e.message}`);
      return '';
    });
  }

  private notify(): void {
    const snapshot: MusicPlaybackSnapshot = this.snapshot();
    this.listeners.forEach((listener: MusicPlaybackListener): void => listener(snapshot));
  }
}
