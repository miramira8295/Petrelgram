import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { mediaPlaybackKeepAlive } from './MediaPlaybackKeepAlive';
import { getUiAbilityContext } from '../tdkit/Globals';
import { KEY_BG_PLAY_MUSIC, KEY_BG_PLAY_VOICE } from '../store/AppSettings';

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

// Shared singleton for voice notes and music messages. The generation token
// prevents an older createAVPlayer promise from stealing playback after the
// user quickly taps a different item.
class VoicePlayback {
  private player: media.AVPlayer | null = null;
  private file: fs.File | null = null;
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
    this.toggleSource(messageId, path, fallbackDurationSec, 'voice');
  }

  toggleMusic(messageId: number, path: string, fallbackDurationSec: number): void {
    this.toggleSource(messageId, path, fallbackDurationSec, 'music');
  }

  startMusic(messageId: number, path: string, fallbackDurationSec: number): void {
    if (messageId > 0 && path.trim() !== '') {
      this.play(messageId, path, Math.max(0, fallbackDurationSec), 'music');
    }
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
    messageId: number, path: string, fallbackDurationSec: number, mode: string
  ): void {
    if (messageId <= 0 || path.trim() === '') {
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
    this.play(messageId, path, Math.max(0, fallbackDurationSec), mode);
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
        console.error(`VoicePlayback.setSpeed failed: ${caught}`);
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

  private play(messageId: number, path: string, fallbackDurationSec: number, mode: string): void {
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
          console.error(`VoicePlayback stale release failed: ${JSON.stringify(caught)}`);
        });
        return;
      }
      this.player = player;
      try {
        this.file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      } catch (caught) {
        this.fail(token, messageId, caught, mode);
        return;
      }
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
      player.url = `fd://${this.file.fd}`;
    }).catch((caught: Object): void => {
      this.fail(token, messageId, caught, mode);
    });
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
    console.error(`VoicePlayback failed message=${messageId}: ${JSON.stringify(reason)}`);
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
        console.error(`VoicePlayback release failed: ${JSON.stringify(caught)}`);
      });
    }
    if (this.file !== null) {
      try {
        fs.closeSync(this.file);
      } catch (caught) {
        console.error(`VoicePlayback close failed: ${caught}`);
      }
      this.file = null;
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
