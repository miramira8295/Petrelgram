import { media } from '@kit.MediaKit';
import { VideoStreamSession } from './VideoStreamSession';
import { VideoRangeServer } from './VideoRangeServer';
import { getTdClient } from '../tdkit/Globals';
import { audio } from '@kit.AudioKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { mediaPlaybackKeepAlive } from './MediaPlaybackKeepAlive';
import { getUiAbilityContext } from '../tdkit/Globals';
import { KEY_BG_PLAY_MUSIC, KEY_BG_PLAY_VOICE } from '../store/AppSettings';
import { logE, logW } from '../util/log';

export interface VoiceState {
  playingId: number;  // current/preparing/completed message; 0 = idle/error
  paused: boolean;
  positionMs: number;
  durationMs: number;
  completedId: number;
  status: string;     // idle | loading | playing | paused | completed | error
  mode: string;       // idle | voice | music
  speed: number;      // 1 | 1.5 | 2
  errorId: number;    // message whose local file failed to open/decode
}

type VoiceListener = (s: VoiceState) => void;
type MusicCompletionListener = (messageId: number) => void;

const VOICE_SPEEDS: number[] = [1, 1.5, 2];

function playbackSpeedOf(speed: number): media.PlaybackSpeed {
  if (speed === 1.5) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
  }
  if (speed === 2) {
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
  }
  return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
}

// 一段音频从哪儿来。
//
// 【为什么要这一层】原来 play() 只认本地路径（`fd://`），于是音乐必须**整首下完**
// 才出声——几十 MB 的无损要等半天，而视频早就是边下边放的（2026-09-18 用户报的
// 就是这条）。边下边放要的东西视频那边现成：VideoStreamSession 按需向 TDLib 要
// 字节段，VideoRangeServer 把它包成本地回环上的一个支持 Range 的 HTTP 源，
// AVPlayer 直接吃 http:// 。两者和"视频"无关，只是名字带 Video。
//
// 语音条不用流：几百 KB，整下比建一条回环连接还快，继续走 path。
export interface AudioSource {
  // 已经下完的本地文件；非空就直接播它，下面三个字段不看。
  path: string;
  // 走流时要的：TDLib 文件 id 与**总字节数**。size 为 0 时流没法定位，只能退回下载。
  fileId: number;
  sizeBytes: number;
  mimeType: string;
}

// 起播前等头尾就位的上限。到点还没齐也照样开播，不把用户卡死在这里。
const STREAM_READY_TIMEOUT_MS: number = 15000;

export function localAudioSource(path: string): AudioSource {
  return { path: path, fileId: 0, sizeBytes: 0, mimeType: '' };
}

export function streamAudioSource(
  fileId: number, sizeBytes: number, mimeType: string
): AudioSource {
  return { path: '', fileId: fileId, sizeBytes: sizeBytes, mimeType: mimeType };
}

// 这个来源能不能播：本地有文件，或者流的两个必要条件都齐。
export function audioSourcePlayable(source: AudioSource): boolean {
  return source.path.trim() !== '' || (source.fileId > 0 && source.sizeBytes > 0);
}

// Shared singleton for voice notes and music messages. The generation token
// prevents an older createAVPlayer promise from stealing playback after the
// user quickly taps a different item.
class VoicePlayback {
  private player: media.AVPlayer | null = null;
  private file: fs.File | null = null;
  // 边下边放那一路的两件东西，和 player 同生共死（见 releaseResources）。
  private stream: VideoStreamSession | null = null;
  private rangeServer: VideoRangeServer | null = null;
  private generation: number = 0;
  private preferredSpeed: number = 1;
  private musicCompletionListener: MusicCompletionListener | null = null;
  private state: VoiceState = {
    playingId: 0, paused: false, positionMs: 0, durationMs: 0,
    completedId: 0, status: 'idle', mode: 'idle', speed: 1, errorId: 0
  };
  private listeners: VoiceListener[] = [];

  subscribe(listener: VoiceListener): () => void {
    this.listeners = [...this.listeners, listener];
    listener(this.state);
    return (): void => {
      this.listeners = this.listeners.filter((item: VoiceListener): boolean => item !== listener);
    };
  }

  current(): VoiceState {
    return this.state;
  }

  toggle(messageId: number, path: string, fallbackDurationSec: number): void {
    // 用户自己动过手就不再算"被系统打断"：打断结束时不该覆盖他的选择。
    this.pausedByFocusLoss = false;
    this.toggleSource(messageId, localAudioSource(path), fallbackDurationSec, 'voice');
  }

  toggleMusic(messageId: number, path: string, fallbackDurationSec: number): void {
    this.toggleSource(messageId, localAudioSource(path), fallbackDurationSec, 'music');
  }

  startMusic(messageId: number, path: string, fallbackDurationSec: number): void {
    this.startMusicSource(messageId, localAudioSource(path), fallbackDurationSec);
  }

  // 边下边放版。来源不成形（既没有本地文件、又没有 fileId/size）时什么都不做，
  // 由调用方退回"先下完再播"。
  startMusicSource(messageId: number, source: AudioSource, fallbackDurationSec: number): void {
    if (messageId > 0 && audioSourcePlayable(source)) {
      this.play(messageId, source, Math.max(0, fallbackDurationSec), 'music');
    }
  }

  toggleMusicSource(messageId: number, source: AudioSource, fallbackDurationSec: number): void {
    this.toggleSource(messageId, source, Math.max(0, fallbackDurationSec), 'music');
  }

  setMusicCompletionListener(listener: MusicCompletionListener | null): void {
    this.musicCompletionListener = listener;
  }

  seek(messageId: number, fraction: number): void {
    if (this.player === null || this.state.playingId !== messageId ||
      this.state.durationMs <= 0 || this.state.status === 'loading') {
      return;
    }
    const positionMs: number =
      Math.round(Math.max(0, Math.min(1, fraction)) * this.state.durationMs);
    try {
      this.player.seek(positionMs, media.SeekMode.SEEK_CLOSEST);
      this.setState({
        playingId: messageId, paused: this.state.paused, positionMs,
        durationMs: this.state.durationMs, completedId: 0,
        status: this.state.status === 'completed' ? 'paused' : this.state.status,
        mode: this.state.mode, speed: this.state.speed, errorId: 0
      });
    } catch (caught) {
      this.fail(this.generation, messageId, caught, this.state.mode);
    }
  }

  private toggleSource(
    messageId: number, source: AudioSource, fallbackDurationSec: number, mode: string
  ): void {
    if (messageId <= 0 || !audioSourcePlayable(source)) {
      return;
    }
    if (this.state.playingId === messageId && this.state.mode === mode && this.player !== null) {
      if (this.state.status === 'loading') {
        return;
      }
      if (this.state.status === 'playing') {
        this.pauseCurrent();
        return;
      }
      if (this.state.status === 'paused') {
        this.resumeCurrent(messageId);
        return;
      }
      if (this.state.status === 'completed') {
        try {
          this.player.seek(0, media.SeekMode.SEEK_PREV_SYNC);
          this.player.play();
          this.setState({
            playingId: messageId, paused: false, positionMs: 0,
            durationMs: this.state.durationMs, completedId: 0,
            status: 'playing', mode,
            speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
          });
        } catch (caught) {
          this.fail(this.generation, messageId, caught, mode);
        }
        return;
      }
    }
    this.play(messageId, source, Math.max(0, fallbackDurationSec), mode);
  }

  cycleSpeed(messageId: number): number {
    const currentIndex: number = Math.max(0, VOICE_SPEEDS.indexOf(this.preferredSpeed));
    const next: number = VOICE_SPEEDS[(currentIndex + 1) % VOICE_SPEEDS.length];
    this.preferredSpeed = next;
    if (this.player !== null && this.state.mode === 'voice' &&
      this.state.playingId === messageId &&
      this.state.status !== 'loading' && this.state.status !== 'error') {
      try {
        this.player.setSpeed(playbackSpeedOf(next));
      } catch (caught) {
        logE(`VoicePlayback.setSpeed failed: ${caught}`);
      }
    }
    this.setState({
      playingId: this.state.playingId,
      paused: this.state.paused,
      positionMs: this.state.positionMs,
      durationMs: this.state.durationMs,
      completedId: this.state.completedId,
      status: this.state.status,
      mode: this.state.mode,
      speed: next,
      errorId: this.state.errorId
    });
    return next;
  }

  // 是被系统打断才暂停的。打断结束时只恢复这一种暂停——用户自己按的暂停
  // 不能因为别人打完电话就自己响起来。
  private pausedByFocusLoss: boolean = false;

  pauseForBackground(): void {
    if (this.state.status !== 'playing') {
      return;
    }
    // 对应类别开了"后台播放"就不暂停——保活任务已在 syncKeepAlive 挂上。
    const settingKey: string = this.state.mode === 'music'
      ? KEY_BG_PLAY_MUSIC : KEY_BG_PLAY_VOICE;
    if (AppStorage.get<boolean>(settingKey) ?? false) {
      return;
    }
    this.pauseCurrent();
  }

  // 强制打断（INTERRUPT_FORCE）时系统已经把流停了，我们只需要把状态改成
  // 暂停、让界面对得上；共享打断（INTERRUPT_SHARE）的 RESUME 才是我们该主动
  // 调 play() 的时机——这两半的分工是官方《基于AVPlayer播放长视频实践》写明的。
  //
  // DUCK/UNDUCK 不处理：那是"压低音量让别人说话"，语音该继续放。
  private onAudioInterrupt(event: audio.InterruptEvent): void {
    if (event.forceType === audio.InterruptForceType.INTERRUPT_FORCE) {
      const hint = event.hintType;
      if (hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
        hint === audio.InterruptHint.INTERRUPT_HINT_STOP) {
        if (this.state.status === 'playing') {
          this.pausedByFocusLoss = hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE;
          this.pauseCurrent();
        }
      }
      return;
    }
    if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME &&
      this.pausedByFocusLoss && this.state.playingId !== 0) {
      this.pausedByFocusLoss = false;
      this.resumeCurrent(this.state.playingId);
    }
  }

  private pauseCurrent(): void {
    if (this.player === null || this.state.playingId === 0) {
      return;
    }
    try {
      this.player.pause();
      this.setState({
        playingId: this.state.playingId, paused: true,
        positionMs: this.state.positionMs, durationMs: this.state.durationMs,
        completedId: 0, status: 'paused', mode: this.state.mode,
        speed: this.state.mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
      });
    } catch (caught) {
      this.fail(this.generation, this.state.playingId, caught, this.state.mode);
    }
  }

  private resumeCurrent(messageId: number): void {
    if (this.player === null) {
      return;
    }
    try {
      this.player.play();
      this.setState({
        playingId: messageId, paused: false,
        positionMs: this.state.positionMs, durationMs: this.state.durationMs,
        completedId: 0, status: 'playing', mode: this.state.mode,
        speed: this.state.mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
      });
    } catch (caught) {
      this.fail(this.generation, messageId, caught, this.state.mode);
    }
  }

  private play(messageId: number, source: AudioSource, fallbackDurationSec: number, mode: string): void {
    const token: number = ++this.generation;
    this.releaseResources();
    this.setState({
      playingId: messageId, paused: false, positionMs: 0,
      durationMs: fallbackDurationSec * 1000, completedId: 0,
      status: 'loading', mode,
      speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
    });
    media.createAVPlayer().then((player: media.AVPlayer): void => {
      if (token !== this.generation) {
        player.release().catch((caught: Object): void => {
          logE(`VoicePlayback stale release failed: ${JSON.stringify(caught)}`);
        });
        return;
      }
      this.player = player;
      // 别的应用或来电开始发声时自动暂停。语音走的是官方 media.AVPlayer，
      // 直接有 on('audioInterrupt')；视频走 ijkplayer 拿不到这个回调，那边
      // 绕的是 AudioSessionManager（见 services/audioFocus）。
      player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
        if (token !== this.generation || this.player !== player) {
          return;
        }
        this.onAudioInterrupt(event);
      });
      player.on('stateChange', (state: string): void => {
        if (token !== this.generation || this.player !== player) {
          return;
        }
        try {
          if (state === 'initialized') {
            player.prepare();
          } else if (state === 'prepared') {
            const duration: number = player.duration > 0
              ? player.duration : fallbackDurationSec * 1000;
            player.setSpeed(playbackSpeedOf(mode === 'voice' ? this.preferredSpeed : 1));
            this.setState({
              playingId: messageId, paused: false, positionMs: 0,
              durationMs: duration, completedId: 0,
              status: 'loading', mode,
              speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
            });
            player.play();
          } else if (state === 'playing' && this.state.playingId === messageId) {
            this.setState({
              playingId: messageId, paused: false,
              positionMs: this.state.positionMs, durationMs: this.state.durationMs,
              completedId: 0, status: 'playing', mode,
              speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
            });
          } else if (state === 'paused' && this.state.playingId === messageId) {
            this.setState({
              playingId: messageId, paused: true,
              positionMs: this.state.positionMs, durationMs: this.state.durationMs,
              completedId: 0, status: 'paused', mode,
              speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
            });
          } else if (state === 'completed') {
            const duration: number = this.state.durationMs;
            this.setState({
              playingId: messageId, paused: false,
              positionMs: duration, durationMs: duration,
              completedId: messageId, status: 'completed', mode,
              speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
            });
            if (mode === 'music' && this.musicCompletionListener !== null) {
              const completionListener: MusicCompletionListener = this.musicCompletionListener;
              setTimeout((): void => {
                if (this.state.playingId === messageId && this.state.mode === 'music' &&
                  this.state.status === 'completed') {
                  completionListener(messageId);
                }
              }, 180);
            }
          } else if (state === 'error') {
            this.fail(token, messageId, 'player state error', mode);
          }
        } catch (caught) {
          this.fail(token, messageId, caught, mode);
        }
      });
      player.on('timeUpdate', (timeMs: number): void => {
        if (token === this.generation && this.state.playingId === messageId &&
          (this.state.status === 'playing' || this.state.status === 'paused')) {
          this.setState({
            playingId: messageId, paused: this.state.status === 'paused',
            positionMs: Math.max(0, timeMs), durationMs: this.state.durationMs,
            completedId: 0, status: this.state.status,
            mode, speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
          });
        }
      });
      player.on('durationUpdate', (durationMs: number): void => {
        if (token === this.generation && this.state.playingId === messageId && durationMs > 0) {
          this.setState({
            playingId: messageId, paused: this.state.paused,
            positionMs: this.state.positionMs, durationMs,
            completedId: this.state.completedId, status: this.state.status,
            mode, speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: 0
          });
        }
      });
      player.on('error', (error: BusinessError): void => {
        this.fail(token, messageId, error, mode);
      });
      // url 最后设：AVPlayer 一拿到源就开始走状态机，回调必须已经挂好。
      // 流那一路要先把回环服务器听起来，所以这里是异步的。
      this.sourceUrl(source).then((url: string): void => {
        if (token !== this.generation || this.player !== player) {
          return;
        }
        player.url = url;
      }).catch((caught: Object): void => {
        this.fail(token, messageId, caught, mode);
      });
    }).catch((caught: Object): void => {
      this.fail(token, messageId, caught, mode);
    });
  }

  // 本地文件给 fd://，流给回环上的 http://。两路都由 releaseResources 收尾。
  private async sourceUrl(source: AudioSource): Promise<string> {
    if (source.path.trim() !== '') {
      this.file = fs.openSync(source.path, fs.OpenMode.READ_ONLY);
      return `fd://${this.file.fd}`;
    }
    const session: VideoStreamSession =
      new VideoStreamSession(getTdClient(), source.fileId, source.sizeBytes);
    this.stream = session;
    const server: VideoRangeServer =
      new VideoRangeServer(session, source.fileId, source.sizeBytes, source.mimeType);
    this.rangeServer = server;
    session.start();
    const url: string = await server.start();
    // **开播前必须等头尾就位。** session.start() 只是把头块和尾块的下载请求发出去，
    // 不等它们回来。一个字节都还没落盘就把 url 交给播放器，它立刻读头部、对 m4a
    // 还要去尾部找 moov（见 util/videoPrefetchPolicy 那句「moov 可能在尾部」），
    // 于是 SnifferMediaType 失败 → player state error。
    //
    // 2026-09-20 真机：机器人搜来的歌是第一次遇到**全冷**的音频文件（会话里的歌
    // 多半已经预取过一段），必现"第一次点不播、再点一下就好"——第二次能成正是
    // 因为第一次已经把字节拉下来了。waitForReady 本来就是为这件事写的，
    // 只是一直没人调用。
    //
    // 超时了仍然把 url 交出去：让播放器自己试一把，比这里直接判死好。
    if (!await session.waitForReady(STREAM_READY_TIMEOUT_MS)) {
      logW(`VoicePlayback: stream head/tail not ready in time, starting anyway`);
    }
    return url;
  }

  stop(completedId: number = 0): void {
    this.generation++;
    this.releaseResources();
    this.setState({
      playingId: 0, paused: false, positionMs: 0, durationMs: 0,
      completedId, status: 'idle', mode: 'idle', speed: this.preferredSpeed, errorId: 0
    });
  }

  private fail(
    token: number, messageId: number, reason: Object | string, mode: string = 'idle'
  ): void {
    if (token !== this.generation) {
      return;
    }
    logE(`VoicePlayback failed message=${messageId}: ${JSON.stringify(reason)}`);
    // Invalidate state/error callbacks emitted while release() tears down the
    // failed player, otherwise they can overwrite the same error repeatedly.
    this.generation++;
    this.releaseResources();
    this.setState({
      playingId: 0, paused: false, positionMs: 0, durationMs: 0,
      completedId: 0, status: 'error', mode,
      speed: mode === 'voice' ? this.preferredSpeed : 1, errorId: messageId
    });
  }

  private releaseResources(): void {
    if (this.player !== null) {
      const player: media.AVPlayer = this.player;
      this.player = null;
      player.release().catch((caught: Object): void => {
        logE(`VoicePlayback release failed: ${JSON.stringify(caught)}`);
      });
    }
    if (this.file !== null) {
      try {
        fs.closeSync(this.file);
      } catch (caught) {
        logE(`VoicePlayback close failed: ${caught}`);
      }
      this.file = null;
    }
    // 服务器先收再收会话：反过来的话服务器还可能向一个已经关掉的会话要字节。
    if (this.rangeServer !== null) {
      this.rangeServer.close();
      this.rangeServer = null;
    }
    if (this.stream !== null) {
      this.stream.close();
      this.stream = null;
    }
  }

  private setState(state: VoiceState): void {
    this.state = state;
    this.syncKeepAlive(state);
    for (const listener of this.listeners) {
      listener(state);
    }
  }

  // 播放期后台保活：状态机唯一出口处同步，保证 acquire/release 成对。
  // 对应类别的"后台播放"开关关闭时不挂任务（切后台由系统正常暂停）。
  private heldKind: string | null = null;

  private syncKeepAlive(state: VoiceState): void {
    let desired: string | null = null;
    if (state.status === 'playing') {
      const kind: string = state.mode === 'music' ? 'music' : 'voice';
      const settingKey: string = kind === 'music' ? KEY_BG_PLAY_MUSIC : KEY_BG_PLAY_VOICE;
      if (AppStorage.get<boolean>(settingKey) ?? false) {
        desired = kind;
      }
    }
    if (desired === this.heldKind) {
      return;
    }
    if (this.heldKind !== null) {
      mediaPlaybackKeepAlive.release(this.heldKind);
      this.heldKind = null;
    }
    if (desired !== null) {
      const context = getUiAbilityContext();
      if (context !== null) {
        mediaPlaybackKeepAlive.acquire(context, desired);
        this.heldKind = desired;
      }
    }
  }
}

let instance: VoicePlayback | null = null;

export function getVoicePlayback(): VoicePlayback {
  if (instance === null) {
    instance = new VoicePlayback();
  }
  return instance;
}
