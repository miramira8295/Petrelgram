import {
  IjkMediaPlayer,
  OnBufferingUpdateListener,
  OnCompletionListener,
  OnErrorListener,
  OnInfoListener,
  OnPreparedListener,
  OnVideoSizeChangedListener
} from '@ohos/ijkplayer';
import {
  MATERIAL_EPOCH, overlayBackdropBlur, overlayGlassFill
} from '../../util/overlayMaterial';
import { shouldShowPlayerStatus } from '../../util/playerStatusGate';
import {
  AUTO_RETRY_DELAYS_MS, CONTROL_ACCENT, CONTROL_BAR_BG, CONTROL_TEXT_SOFT,
  CONTROL_TRACK, CONTROL_TRACK_SOFT, CONTROL_TRACK_SOFT_FILL, DEFAULT_SPEED_IDX,
  HEADSET_DEVICE_TYPES, QUICK_SEEK_MS, SPEEDS, SPEED_LABELS, STATUS_DELAY_MS,
  formatMs, formatSpeed
} from '../../util/playerChrome';
import { materialModifier } from '../../util/materialModifier';
import {
  FOCUS_PAUSE, FOCUS_RESUME, FOCUS_STOP, acquireAudioFocus
} from '../../services/audioFocus';
import { audio } from '@kit.AudioKit';
import { getTdClient, getUiAbilityContext } from '../../tdkit/Globals';
import { mediaPlaybackKeepAlive } from '../../services/MediaPlaybackKeepAlive';
import { KEY_BG_PLAY_VIDEO } from '../../store/AppSettings';
import { VideoRangeServer } from '../../services/VideoRangeServer';
import { VideoStreamSession } from '../../services/VideoStreamSession';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE, logI } from '../../util/log';



// ijk 的 info 码：视频旋转角已知/改变，extra 就是角度。
const MEDIA_INFO_VIDEO_ROTATION_CHANGED: number = 10001;


let nextPlayerInstanceId: number = 1;



@Component
export struct StreamingVideoPlayer {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @Prop fileId: number;
  @Prop fileSize: number;
  @Prop mimeType: string = '';
  @Prop videoWidth: number = 0;
  @Prop videoHeight: number = 0;
  @Prop localPath: string = '';
  @Prop posterPath: string = '';
  @Prop showControls: boolean = true;
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @Prop landscape: boolean = false;
  // Embed mode: mounted directly in a chat bubble instead of the fullscreen
  // viewer. No control bar / gestures / speed / rotate — just poster +
  // surface + buffering hint. See build() and onPlayingChanged() below.
  @Prop embedded: boolean = false;
  @StorageProp('appIsForeground') @Watch('onAppForegroundChanged')
  private appIsForeground: boolean = true;
  // 音频焦点：拿着的时候别的应用/来电开始发声，系统会通知我们让位。
  // 释放函数在停止播放时调用（幂等）。
  private releaseAudioFocus: (() => void) | null = null;
  // 是**被系统打断**才暂停的。打断结束时只恢复这一种暂停——用户自己按的
  // 暂停不能因为别人打完电话就自己动起来。
  private pausedByFocusLoss: boolean = false;
  @Watch('onMutedChanged') @Prop muted: boolean = false;
  @Prop startPositionMs: number = 0;
  // ── 实况照片模式 ──────────────────────────────────────────────────────
  // 查看器把 PG 发的实况（见 util/livePhoto）渲染成 iOS 那样：进来自动播一遍，
  // 左下角一枚「实况」胶囊可以随时暂停/重播。标准控制栏那时是关掉的，所以需要
  // 这条外部通道。
  //
  // 用**计数**而不是布尔：「想暂停」这个意图和播放器的实际状态会因为音频焦点
  // 被抢、切后台自动暂停而不同步，布尔会两边打架（外部还写着 false，内部其实
  // 已经停了，再拨就没反应）。计数是命令语义——值一变就切换一次，不关心当前状态。
  @Prop @Watch('onLiveToggleRequested') liveToggleSeq: number = 0;
  // 实况的三处差别（不自动播、不弹中央重播胶囊、不吃双击快进）由这**一个**开关
  // 统一表达。原来它们全靠 showControls=false 间接兜着，副作用会外溢——中央那枚
  // 重播胶囊和双击 ±15s 就是这么漏出来的，见 build() 与 tapZone()。
  @Prop liveMode: boolean = false;
  // 正在「静音预热出真首帧」。
  //
  // 【为什么不能简单地不 start】不 start，ijk 就不解码，也就不会报 what===3，
  // videoVisible 永远为 false——屏幕上停着的是 TDLib 那张几百像素宽的缩略图
  // （poster），全屏下又糊又发暗，那不叫「静态照片」。所以照常起播，只是先把
  // 音量压到 0，等第一帧真的进了 Surface 再就地暂停。首帧直接来自解码器，
  // 原分辨率、零异步、不落任何临时文件。
  private primingFirstFrame: boolean = false;
  // 用户在「还没就绪 / 正在预热」期间点过播放键。那两段窗口里 togglePlay 不能
  // 直接动播放器（会和 onPrepared / finishPriming 抢），只记意图、到点补执行。
  // 不记的话点了毫无反应——旧行为下不明显（反正会自动播），新行为下会被当成 bug。
  private pendingPlayRequest: boolean = false;
  // 播放状态回报，让胶囊的图标跟真实状态一致。播完时 onCompletion 会把
  // isPlaying 置 false，因此"播完自动翻回可重播"也走这一条，不用另接。
  onPlayStateChanged: (playing: boolean) => void = (): void => {};

  private onLiveToggleRequested(): void {
    // 初值 0 不算一次请求：@Watch 不在初始赋值时触发，但组件复用/重建时可能
    // 带着非 0 的初值进来，这里挡一道。
    if (this.liveToggleSeq > 0) {
      this.togglePlay();
    }
  }
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  onBackgroundTap: () => void = (): void => {};
  onSwipeNext: () => void = (): void => {};
  onSwipePrev: () => void = (): void => {};
  onOrientationChange: (landscape: boolean) => void =
    (_landscape: boolean): void => {};
  onPositionChanged: (positionMs: number) => void =
    (_positionMs: number): void => {};
  onEnded: () => void = (): void => {};
  // 内嵌模式专用：播放失败。内嵌模式没有重试按钮（见 build()），失败的那一条
  // 必须把播放位让出去，否则它会一直占着位子谁也播不了。
  onFailed: () => void = (): void => {};
  private player: IjkMediaPlayer | null = null;
  private session: VideoStreamSession | null = null;
  private rangeServer: VideoRangeServer | null = null;
  private progressUnsub: (() => void) | null = null;
  private routingManager: audio.AudioRoutingManager | null = null;
  private deviceChangeCb: ((change: audio.DeviceChangeAction) => void) | null = null;
  private progressTimer: number = -1;
  private seekFeedbackTimer: number = -1;
  private speedFeedbackTimer: number = -1;
  private retryTimer: number = -1;
  // 出错后已自动重试的次数。进会话第一次点播放大概率失败、手动"刷新"就好
  // （issue #127）——多半是文件刚开始下载 ijk 就去开的竞态。这种一次性的失败
  // 不该让用户去点刷新：按递增退避自动重来几次，都不行再报错。
  private autoRetries: number = 0;
  private firstFrameTimer: number = -1;
  private surfaceContext: object | null = null;
  private active: boolean = true;
  private readonly playerInstanceId: number = nextPlayerInstanceId++;
  @State status: string = str('player_buffering_dots');
  // status 有内容 ≠ 立刻显示：起播前要先过 STATUS_DELAY_MS 那道门。
  @State statusVisible: boolean = false;
  private statusDelayTimer: number = -1;
  @State hasError: boolean = false;
  @State errorDetail: string = '';
  @State isPrepared: boolean = false;
  @State videoVisible: boolean = false;
  @State bufferedPercent: number = 0;
  // Live download throughput (bytes/sec) shown in the control bar; 0 hides it
  // (fully downloaded or stalled). Sampled from the buffered-byte deltas.
  @State downloadSpeed: number = 0;
  private lastBufferedBytes: number = 0;
  private lastSpeedSampleMs: number = 0;
  @State @Watch('onPlayingChanged') isPlaying: boolean = false;
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;
  @State dragging: boolean = false;
  @State dragValueMs: number = 0;
  @State speedIdx: number = DEFAULT_SPEED_IDX;
  @State isCompleted: boolean = false;
  @State decodedAspectRatio: number = 0;
  // 容器里的旋转角（0/90/180/270）。竖着拍的视频在文件里是横的 1920x1440，
  // 真正的显示方向写在 display matrix 里；ijk 通过 info 10001 把它报上来。
  // 不读它就会按 1920x1440 排版，画面横躺（用户实测「播放还是横向的」）。
  @State videoRotationDeg: number = 0;
  @State viewportWidth: number = 1;
  @State viewportHeight: number = 1;
  @State seekFeedbackSide: number = 0; // -1 = rewind, 1 = forward
  @State seekFeedbackVisible: boolean = false;
  @State speedFeedbackVisible: boolean = false;
  @State speedFeedbackText: string = '';

  aboutToAppear(): void {
    this.active = true;
    this.armStatusDelay();
    if (this.surfaceContext !== null && this.player === null) {
      this.retryTimer = setTimeout((): void => {
        this.retryTimer = -1;
        if (this.active && this.surfaceContext !== null) {
          this.initPlayer(this.surfaceContext);
        }
      }, 0);
    }
  }

  aboutToDisappear(): void {
    this.deactivate();
  }

  aboutToRecycle(): void {
    this.deactivate();
  }

  aboutToReuse(_params: Record<string, Object>): void {
    this.release();
    this.autoRetries = 0;
    this.resetReusedUi();
    this.active = true;
    if (this.surfaceContext !== null) {
      this.retryTimer = setTimeout((): void => {
        this.retryTimer = -1;
        if (this.active && this.surfaceContext !== null) {
          this.initPlayer(this.surfaceContext);
        }
      }, 0);
    }
  }

  private deactivate(): void {
    this.active = false;
    this.isPlaying = false;
    this.syncAudioFocus();
    mediaPlaybackKeepAlive.release('video');
    this.release();
  }

  // 重新上膛「延迟出现」的门：先藏起来，STATUS_DELAY_MS 之后仍未就绪才显示。
  // 每次起播/换届都要调一次——不调的话上一条视频留下的 statusVisible=true 会
  // 让下一条开局就把卡片画出来，正是这次要消掉的那一闪。
  private armStatusDelay(): void {
    this.statusVisible = false;
    if (this.statusDelayTimer !== -1) {
      clearTimeout(this.statusDelayTimer);
    }
    this.statusDelayTimer = setTimeout((): void => {
      this.statusDelayTimer = -1;
      // 这期间已经就绪 / 出错 / 状态被清掉 / 组件没了，就不必再冒出来。
      if (!this.active || this.status === '' || this.hasError || this.isPrepared) {
        return;
      }
      this.statusVisible = true;
    }, STATUS_DELAY_MS);
  }

  private resetReusedUi(): void {
    this.status = str('player_buffering_dots');
    this.armStatusDelay();
    this.hasError = false;
    this.errorDetail = '';
    this.isPrepared = false;
    this.videoVisible = false;
    this.bufferedPercent = 0;
    this.downloadSpeed = 0;
    this.lastBufferedBytes = 0;
    this.lastSpeedSampleMs = 0;
    this.currentTimeMs = 0;
    this.durationMs = 0;
    this.dragging = false;
    this.dragValueMs = 0;
    this.isCompleted = false;
    this.decodedAspectRatio = 0;
    this.videoRotationDeg = 0;
    this.seekFeedbackVisible = false;
    this.speedFeedbackVisible = false;
  }

  // 播放状态变化时同步"视频后台播放"保活。开关关闭时不挂任务，**并且**由
  // onAppForegroundChanged 主动暂停——原来这里只写了不挂任务，指望系统把进程
  // 挂起，但 backgroundGraceTask 会让进程多活几分钟，那几分钟里声音照放。
  // 内嵌模式（列表内播放位）从不申请保活——划走气泡就该正常息屏/挂起，
  // 不能被一段列表预览挡住。
  onPlayingChanged(): void {
    this.onPlayStateChanged(this.isPlaying);
    this.syncAudioFocus();
    if (this.embedded) {
      mediaPlaybackKeepAlive.release('video');
      return;
    }
    if (this.isPlaying && (AppStorage.get<boolean>(KEY_BG_PLAY_VIDEO) ?? false)) {
      const context = getUiAbilityContext();
      if (context !== null) {
        mediaPlaybackKeepAlive.acquire(context, 'video');
      }
      return;
    }
    mediaPlaybackKeepAlive.release('video');
  }

  // Pause when a headset (wired or Bluetooth) disconnects, per platform convention.
  private setupAudioDeviceListener(): void {
    try {
      const routingManager = audio.getAudioManager().getRoutingManager();
      this.routingManager = routingManager;
      this.deviceChangeCb = (change: audio.DeviceChangeAction): void => {
        if (change.type !== audio.DeviceChangeType.DISCONNECT) {
          return;
        }
        const unpluggedHeadset = change.deviceDescriptors.some(
          (d: audio.AudioDeviceDescriptor) => HEADSET_DEVICE_TYPES.includes(d.deviceType));
        if (unpluggedHeadset && this.isPlaying && this.player !== null) {
          this.player.pause();
          this.isPlaying = false;
        }
      };
      routingManager.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.deviceChangeCb);
    } catch (e) {
      logE(`StreamingVideoPlayer.setupAudioDeviceListener failed: ${e}`);
    }
  }

  private cleanupAudioDeviceListener(): void {
    if (this.routingManager !== null && this.deviceChangeCb !== null) {
      try {
        this.routingManager.off('deviceChange', this.deviceChangeCb);
      } catch (e) {
        logE(`StreamingVideoPlayer.cleanupAudioDeviceListener failed: ${e}`);
      }
    }
    this.routingManager = null;
    this.deviceChangeCb = null;
  }

  private release(): void {
    this.cleanupAudioDeviceListener();
    this.stopProgressPolling();
    // 换届/销毁时归零：留着会让下一个实例开局就以为自己在预热窗口里。
    this.primingFirstFrame = false;
    this.pendingPlayRequest = false;
    if (this.seekFeedbackTimer !== -1) {
      clearTimeout(this.seekFeedbackTimer);
      this.seekFeedbackTimer = -1;
    }
    if (this.speedFeedbackTimer !== -1) {
      clearTimeout(this.speedFeedbackTimer);
      this.speedFeedbackTimer = -1;
    }
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    if (this.firstFrameTimer !== -1) {
      clearTimeout(this.firstFrameTimer);
      this.firstFrameTimer = -1;
    }
    if (this.statusDelayTimer !== -1) {
      clearTimeout(this.statusDelayTimer);
      this.statusDelayTimer = -1;
    }
    if (this.progressUnsub !== null) {
      this.progressUnsub();
      this.progressUnsub = null;
    }
    if (this.player !== null) {
      const p = this.player;
      this.player = null;
      try {
        // Native release must finish before its HTTP source is closed.
        p.release();
      } catch (e) {
        logE(`StreamingVideoPlayer.release failed: ${e}`);
      }
    }
    if (this.rangeServer !== null) {
      this.rangeServer.close();
      this.rangeServer = null;
    }
    if (this.session !== null) {
      this.session.close();
      this.session = null;
    }
    this.isPlaying = false;
  }

  // 应用当前 muted 状态到原生播放器音量。onPrepared（起播）和 onMutedChanged
  // （@Watch，静音开关中途拨动）两处共用，避免两份重复的音量字符串字面量。
  private applyMutedVolume(): void {
    if (this.player === null || !this.isPrepared) {
      return;
    }
    const volume: string = this.muted ? '0.0' : '1.0';
    this.player.setVolume(volume, volume);
  }

  // muted 中途变化（缓存设置里的「静音播放」开关）时对已挂载的播放器实例
  // 重设音量，不等下一次换届/重新 prepare。播放器可能还没建好（isPrepared
  // 为 false）或者已经 release（this.player 为 null）——两种情况都在
  // applyMutedVolume() 里判空短路，不会在原生层触碰一个未就绪/已释放的实例。
  // 全屏查看器路径 muted 恒为字面量 false，构造后不会再变，这里不会为它
  // 产生任何额外的 setVolume 调用；@Watch 本身也不在初始赋值时触发。
  private onMutedChanged(): void {
    this.applyMutedVolume();
    // 静音的播放不该占着音频焦点（会把别人的音乐掐掉），取消静音时又该重新
    // 拿回来——判据在 syncAudioFocus 里，这里只负责在 muted 变化时过一遍。
    this.syncAudioFocus();
  }

  private async initPlayer(context: object): Promise<void> {
    if (!this.active || this.player !== null || this.session !== null) {
      return;
    }
    if (this.localPath === '' && this.fileId === 0) {
      this.showError(str('player_video_unavailable'));
      return;
    }
    if (this.localPath === '' && this.fileSize <= 0) {
      this.showError(str('player_no_size'));
      return;
    }
    this.surfaceContext = context;
    this.hasError = false;
    this.errorDetail = '';
    this.isPrepared = false;
    this.videoVisible = false;
    this.status = str('player_preparing');
    this.armStatusDelay();
    this.bufferedPercent = this.localPath !== '' ? 100 : 0;
    this.downloadSpeed = 0;
    this.lastBufferedBytes = 0;
    this.lastSpeedSampleMs = 0;
    this.setupAudioDeviceListener();
    let sourceUrl: string = this.localPath;
    let session: VideoStreamSession | null = null;
    try {
      if (sourceUrl === '') {
        session = new VideoStreamSession(getTdClient(), this.fileId, this.fileSize);
        this.session = session;
        this.progressUnsub = session.subscribeProgress((buffered: number, total: number): void => {
          this.bufferedPercent = total > 0 ? Math.min(100, Math.floor((buffered / total) * 100)) : 0;
          // Throughput from the buffered-byte delta between samples (>=400ms apart
          // to smooth out bursty TDLib updates). Fully-downloaded → 0 (hidden).
          const now = Date.now();
          if (total > 0 && buffered >= total) {
            this.downloadSpeed = 0;
          } else if (this.lastSpeedSampleMs === 0) {
            this.lastSpeedSampleMs = now;
            this.lastBufferedBytes = buffered;
          } else {
            const dtMs = now - this.lastSpeedSampleMs;
            if (dtMs >= 400) {
              const dBytes = buffered - this.lastBufferedBytes;
              this.downloadSpeed = dBytes > 0 ? (dBytes / dtMs) * 1000 : 0;
              this.lastSpeedSampleMs = now;
              this.lastBufferedBytes = buffered;
            }
          }
        });
        session.start();
        const rangeServer = new VideoRangeServer(session, this.fileId, this.fileSize, this.mimeType);
        this.rangeServer = rangeServer;
        sourceUrl = await rangeServer.start();
        if (!this.active || this.session !== session) {
          rangeServer.close();
          return;
        }
      }
      const componentId = this.componentId();
      const player = new IjkMediaPlayer(componentId);
      this.player = player;
      player.setContext(context, componentId);
      player.native_setup();
      const preparedListener: OnPreparedListener = {
        onPrepared: (): void => {
          this.autoRetries = 0;
          if (this.player !== player) {
            return;
          }
          this.status = '';
          this.hasError = false;
          this.isPrepared = true;
          this.durationMs = Math.max(0, player.getDuration());
          player.setSpeed(SPEEDS[this.speedIdx]);
          this.applyMutedVolume();
          if (this.startPositionMs > 0) {
            player.seekTo(`${Math.floor(this.startPositionMs)}`);
            this.currentTimeMs = this.startPositionMs;
          }
          this.isCompleted = false;
          // 实况：预热到首帧就停住（见 primingFirstFrame）。用户在 prepare
          // 之前就点过播放键的话不预热，直接照常播。
          if (this.liveMode && !this.pendingPlayRequest) {
            this.primingFirstFrame = true;
            player.setVolume('0.0', '0.0');
            player.start();
            // isPlaying 故意**不**置真：胶囊图标跟着它走，预热期间画面是静止的。
            this.startProgressPolling();
            return;
          }
          this.pendingPlayRequest = false;
          player.start();
          this.isPlaying = true;
          this.startProgressPolling();
        }
      };
      const completionListener: OnCompletionListener = {
        onCompletion: (): void => {
          this.isPlaying = false;
          this.currentTimeMs = this.durationMs;
          if (this.embedded) {
            // No replay affordance in embed mode — the mount point (chat
            // bubble) decides what happens next (fall back to poster, etc).
            this.onEnded();
            return;
          }
          this.isCompleted = true;
          if (this.liveMode && this.player !== null) {
            // 播完回到静态首帧（iOS 的手感）。**暂停态下 seek 会不会立刻把那一帧
            // 刷上屏，文档没写、未上机验证**——不刷的话画面停在最后一帧，与改动前
            // 一致，不是回退。isCompleted 仍然置真：胶囊那一下要走 replay()。
            this.player.seekTo('0');
            this.currentTimeMs = 0;
          }
        }
      };
      // bufferedPercent tracks the actual TDLib download (subscribeProgress
      // above), not ijk's playback buffer — ijk reports 100% long before the
      // file is local, which used to make the indicator lie and finish early.
      const bufferingListener: OnBufferingUpdateListener = {
        onBufferingUpdate: (): void => {}
      };
      const infoListener: OnInfoListener = {
        onInfo: (what: number, extra: number): void => {
          if (what === MEDIA_INFO_VIDEO_ROTATION_CHANGED) {
            const deg: number = ((extra % 360) + 360) % 360;
            logI(`[VideoRot] rotation=${deg} decoded=${this.decodedAspectRatio.toFixed(3)}` +
              ` declared=${this.videoWidth}x${this.videoHeight}`);
            if (this.videoRotationDeg !== deg) {
              this.videoRotationDeg = deg;
            }
            return;
          }
          if (what === 701) {
            this.status = str('player_buffering');
          } else if (what === 702 || what === 3) {
            this.status = '';
            if (what === 3 && this.firstFrameTimer === -1) {
              // IJK's rendering-start event can arrive one compositor frame
              // before the Surface contains the decoded image. Leave the
              // poster in place through that gap.
              this.firstFrameTimer = setTimeout((): void => {
                this.firstFrameTimer = -1;
                if (this.player !== player) {
                  return;
                }
                this.videoVisible = true;
                // 这里是唯一能确认「Surface 里已经有解码图」的时刻——那 80ms
                // 本来就是为躲开这一帧空窗加的。实况就停在这一帧上。
                this.finishPriming();
              }, 80);
            }
          }
        }
      };
      const errorListener: OnErrorListener = {
        onError: (what: number, extra: number): void => {
          this.isPlaying = false;
          logE(`StreamingVideoPlayer error: what=${what}, extra=${extra}` +
            ` autoRetries=${this.autoRetries}`);
          if (this.autoRetries < AUTO_RETRY_DELAYS_MS.length && this.active) {
            // 见 autoRetries 的说明。retry() 自己还有 100ms，这里的间隔是在那之上。
            const delay: number = AUTO_RETRY_DELAYS_MS[this.autoRetries];
            this.autoRetries++;
            this.status = str('player_reconnecting');
            if (this.retryTimer !== -1) {
              clearTimeout(this.retryTimer);
            }
            this.retryTimer = setTimeout((): void => {
              this.retryTimer = -1;
              this.retry();
            }, delay);
            return;
          }
          this.showError(str('player_play_failed'));
        }
      };
      const sizeListener: OnVideoSizeChangedListener = {
        onVideoSizeChanged: (width: number, height: number, sarNum: number, sarDen: number): void => {
          this.updateVideoAspect(width, height, sarNum, sarDen);
        }
      };
      player.setOnPreparedListener(preparedListener);
      player.setOnCompletionListener(completionListener);
      player.setOnBufferingUpdateListener(bufferingListener);
      player.setOnInfoListener(infoListener);
      player.setOnErrorListener(errorListener);
      player.setOnVideoSizeChangedListener(sizeListener);
      player.setMessageListener();
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '0');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'enable-accurate-seek', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'soundtouch', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'mediacodec-all-videos', '1');
      // 不开 mediacodec-auto-rotate：这套移植版上它**不生效**（实测 info 10001
      // 报了 rotation=90，出画仍是 1920x1440 横的），而万一哪天生效了，就会和
      // 下面 ArkTS 侧的旋转叠成两次。旋转只在一个地方做。
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'timeout', '60000000');
      player.setDataSource(sourceUrl);
      player.prepareAsync();
    } catch (e) {
      logE(`StreamingVideoPlayer.init failed: ${e}`);
      this.release();
      this.showError(str('player_load_failed'));
    }
  }

  private showError(detail: string): void {
    this.status = '';
    this.hasError = true;
    this.errorDetail = detail;
    this.isPrepared = false;
    this.videoVisible = false;
    this.isPlaying = false;
    if (this.embedded) {
      // 内嵌模式（气泡播放位）：不展示重试 UI，直接把播放位让出去，回落到
      // 封面 + 播放按钮。点开全屏才是这里的重试入口。
      this.onFailed();
    }
  }

  private retry(): void {
    if (this.surfaceContext === null || !this.active) {
      return;
    }
    const context = this.surfaceContext;
    this.release();
    this.hasError = false;
    this.errorDetail = '';
    this.status = str('player_reconnecting');
    this.isCompleted = false;
    this.currentTimeMs = 0;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      if (this.active) {
        this.initPlayer(context);
      }
    }, 100);
  }

  // 切后台时按「后台播放视频」这个设置决定停不停。语音/音乐那边早就有对应的
  // pauseForBackground（ChatPage.onAppForegroundChanged 调），视频这边只做了
  // 保活任务那一半：开关开着就挂任务，关着**什么都不做**，注释里的假设是
  // "由系统正常挂起"。
  //
  // 那个假设不成立。EntryAbility.onBackground 会 backgroundGraceTask.begin()
  // 申请 requestSuspendDelay，为了继续收消息让进程多活几分钟——这几分钟里
  // 进程没被挂起，开关关着的视频照样带着声音在放。
  //
  // 回前台不自动续播：和语音那边一致（pauseForBackground 也不自动恢复），
  // 而且用户离开时未必想让它接着放。
  private onAppForegroundChanged(): void {
    if (this.appIsForeground || !this.isPlaying || this.player === null) {
      return;
    }
    // 内嵌播放位是列表里的静音预览，切后台没有任何理由继续解码。
    if (!this.embedded && (AppStorage.get<boolean>(KEY_BG_PLAY_VIDEO) ?? false)) {
      return;
    }
    // 不标记 pausedByFocusLoss：这不是音频打断，别让打断恢复的逻辑接管它。
    this.player.pause();
    this.isPlaying = false;
  }

  // 播放期间持有音频焦点，停下就交还。
  //
  // 内嵌模式（列表里的播放位）不申请：那是静音预览，抢焦点会把用户正在听的
  // 音乐掐掉——划过一条视频气泡就静音了别人的播放器，是最难查的那种投诉。
  private syncAudioFocus(): void {
    const wants: boolean = this.isPlaying && !this.embedded && !this.muted;
    if (wants && this.releaseAudioFocus === null) {
      this.releaseAudioFocus = acquireAudioFocus((action: string): void => {
        this.onAudioFocusChanged(action);
      });
      return;
    }
    if (!wants && this.releaseAudioFocus !== null) {
      const release = this.releaseAudioFocus;
      this.releaseAudioFocus = null;
      release();
    }
  }

  private onAudioFocusChanged(action: string): void {
    if (!this.active || this.player === null) {
      return;
    }
    if (action === FOCUS_PAUSE || action === FOCUS_STOP) {
      if (this.isPlaying) {
        this.player.pause();
        this.isPlaying = false;
        // STOP 是永久失去焦点，不会再有 resume；标成"被打断"只会让它以后
        // 莫名其妙自己响起来。
        this.pausedByFocusLoss = action === FOCUS_PAUSE;
      }
      return;
    }
    if (action === FOCUS_RESUME && this.pausedByFocusLoss) {
      this.pausedByFocusLoss = false;
      if (!this.isPlaying && this.isPrepared && !this.hasError && !this.isCompleted) {
        this.player.start();
        this.isPlaying = true;
      }
    }
  }

  // 预热结束：第一帧已经在 Surface 里了，就地停住并把音量还回去。
  private finishPriming(): void {
    if (!this.primingFirstFrame || this.player === null) {
      return;
    }
    this.primingFirstFrame = false;
    if (this.pendingPlayRequest) {
      // 预热期间用户已经点过播放键：别停，接着播就是了。
      this.pendingPlayRequest = false;
      this.applyMutedVolume();
      this.isPlaying = true;
      return;
    }
    this.player.pause();
    this.isPlaying = false;
    // 音量在预热前被压到 0，这里还回去。**不 seek 回 0**：此刻位置本来就在
    // 几十毫秒内，而暂停态下 seek 会不会刷新 Surface 没有文档、也没验过，
    // 平白引入一个不确定的动作不划算。
    this.applyMutedVolume();
  }

  private togglePlay(): void {
    if (this.player === null || this.hasError) {
      return;
    }
    if (!this.isPrepared || this.primingFirstFrame) {
      // 还没就绪、或正在预热。**画面上此刻已经有图**，用户看不出播放器还没准备好，
      // 原来这里直接 return 等于点了没反应。记下意图，到点补执行。
      //
      // **是置位，不是取反。** 取反读起来更像「切换」，但这段窗口里没有任何东西
      // 会因为这一下而变化——胶囊图标跟着 isPlaying 走，而这里不碰它。于是"取消"
      // 这个动作对用户完全不可见：流式的实况 prepareAsync 可以卡上一两秒，
      // 不耐烦连点两下的人得到的是"一下都没算"，还得再点第三下。置位则最坏是
      // 多记一次同样的意图，播起来之后再按停就是了——那一下有反馈。
      this.pendingPlayRequest = true;
      return;
    }
    if (this.isCompleted) {
      this.replay();
      return;
    }
    // 用户自己动过手就不再算"被系统打断"：打断结束时不该覆盖他的选择。
    this.pausedByFocusLoss = false;
    if (this.isPlaying) {
      this.player.pause();
      this.isPlaying = false;
    } else {
      this.player.start();
      this.isPlaying = true;
    }
  }

  private replay(): void {
    if (this.player === null) {
      return;
    }
    this.isCompleted = false;
    this.currentTimeMs = 0;
    this.player.seekTo('0');
    this.player.start();
    this.isPlaying = true;
  }

  // Common media-viewer convention: double tap either half to jump exactly
  // 15 seconds. Clamp at the media boundaries and keep the existing
  // play/pause state, so an inspection seek never unexpectedly starts audio.
  private seekBy(deltaMs: number): void {
    if (this.player === null || !this.isPrepared || this.durationMs <= 0 || this.hasError) {
      return;
    }
    const base = this.dragging ? this.dragValueMs : this.currentTimeMs;
    const target = Math.max(0, Math.min(this.durationMs, base + deltaMs));
    this.dragging = false;
    this.currentTimeMs = target;
    this.player.seekTo(`${Math.floor(target)}`);
    if (target < this.durationMs) {
      this.isCompleted = false;
    }
    this.showSeekFeedback(deltaMs < 0 ? -1 : 1);
  }

  private showSeekFeedback(side: number): void {
    if (this.seekFeedbackTimer !== -1) {
      clearTimeout(this.seekFeedbackTimer);
      this.seekFeedbackTimer = -1;
    }
    this.seekFeedbackSide = side;
    this.seekFeedbackVisible = false;
    animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.seekFeedbackVisible = true;
    });
    this.seekFeedbackTimer = setTimeout((): void => {
      this.seekFeedbackTimer = -1;
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.seekFeedbackVisible = false;
      });
    }, 520);
  }

  // Drag the seek bar: track the dragged position live (without fighting the
  // player's own timeUpdate events); commit the seek only once the user
  // releases (End) or taps a new spot (Click).
  private onSeekChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.dragging = true;
      this.dragValueMs = value;
      return;
    }
    this.dragging = false;
    this.currentTimeMs = value;
    if (this.player !== null) {
      this.player.seekTo(`${Math.floor(value)}`);
    }
  }

  private cycleSpeed(): void {
    const nextIdx: number = (this.speedIdx + 1) % SPEEDS.length;
    let applied: boolean = true;
    if (this.player !== null && this.isPrepared) {
      try {
        this.player.setSpeed(SPEEDS[nextIdx]);
        const nativeSpeed: number = this.player.getSpeed();
        logI(`StreamingVideoPlayer speed requested=${SPEEDS[nextIdx]}, native=${nativeSpeed}`);
        applied = nativeSpeed <= 0 || Math.abs(nativeSpeed - Number(SPEEDS[nextIdx])) < 0.08;
      } catch (caught) {
        applied = false;
        logE(`StreamingVideoPlayer.setSpeed failed: ${caught}`);
      }
    }
    // Keep the chosen value even while preparing. onPrepared applies the
    // latest selection, so tapping during an initial buffer is never lost.
    this.speedIdx = nextIdx;
    this.showSpeedFeedback(applied
      ? str('player_speed', SPEED_LABELS[nextIdx])
      : str('player_speed_failed'));
  }

  private showSpeedFeedback(text: string): void {
    if (this.speedFeedbackTimer !== -1) {
      clearTimeout(this.speedFeedbackTimer);
      this.speedFeedbackTimer = -1;
    }
    this.speedFeedbackText = text;
    this.speedFeedbackVisible = false;
    animateTo({ duration: 120, curve: Curve.EaseOut }, () => {
      this.speedFeedbackVisible = true;
    });
    this.speedFeedbackTimer = setTimeout((): void => {
      this.speedFeedbackTimer = -1;
      animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
        this.speedFeedbackVisible = false;
      });
    }, 850);
  }

  private onSwipeSwitch(offsetX: number): void {
    if (Math.abs(offsetX) < 50) {
      return;
    }
    if (offsetX < 0) {
      this.onSwipeNext();
    } else {
      this.onSwipePrev();
    }
  }

  private componentId(): string {
    return `stream_video_${this.fileId}_${this.playerInstanceId}`;
  }

  private startProgressPolling(): void {
    this.stopProgressPolling();
    this.progressTimer = setInterval((): void => {
      if (this.player === null) {
        return;
      }
      if (!this.dragging) {
        this.currentTimeMs = Math.max(0, this.player.getCurrentPosition());
        this.onPositionChanged(this.currentTimeMs);
      }
      const duration = this.player.getDuration();
      if (duration > 0) {
        this.durationMs = duration;
      }
      this.updateVideoAspect(this.player.getVideoWidth(), this.player.getVideoHeight(),
        this.player.getVideoSarNum(), this.player.getVideoSarDen());
      // 预热窗口里原生确实在播，但那是为了解出首帧，不是「用户看到的在播」。
      // 不挡这一下，350ms 的 tick 会把 isPlaying 刷成真，经 onPlayingChanged
      // 回灌胶囊图标，还会顺手申请音频焦点、开后台播放保活。
      if (!this.primingFirstFrame) {
        this.isPlaying = this.player.isPlaying();
      }
      // No buffered-byte update for a while → the download stalled or finished;
      // drop the speed readout instead of leaving a stale value on screen.
      if (this.downloadSpeed > 0 && this.lastSpeedSampleMs > 0
        && Date.now() - this.lastSpeedSampleMs > 1200) {
        this.downloadSpeed = 0;
      }
    }, 350);
  }

  private stopProgressPolling(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private updateVideoAspect(width: number, height: number, sarNum: number, sarDen: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const pixelAspect = sarNum > 0 && sarDen > 0 ? sarNum / sarDen : 1;
    const aspect = (width * pixelAspect) / height;
    if (Number.isFinite(aspect) && aspect > 0 && Math.abs(aspect - this.decodedAspectRatio) > 0.001) {
      logI(`[VideoRot] decoded=${width}x${height} sar=${sarNum}/${sarDen}` +
        ` rot=${this.videoRotationDeg} declared=${this.videoWidth}x${this.videoHeight}`);
      this.decodedAspectRatio = aspect;
    }
  }

  // 旋转 90/270 时，解码出来的宽高是**转置**的，直接拿来排版就会横躺。
  private quarterTurned(): boolean {
    return this.videoRotationDeg === 90 || this.videoRotationDeg === 270;
  }

  private displayAspectRatio(): number {
    if (this.decodedAspectRatio > 0) {
      return this.quarterTurned() ? 1 / this.decodedAspectRatio : this.decodedAspectRatio;
    }
    // 服务端带来的 width/height 已经是**显示**尺寸（发送侧按静图的真实宽高填的，
    // 见 MessageStore.mediaInputContent），所以这一支不需要再转置。
    if (this.videoWidth > 0 && this.videoHeight > 0) {
      return this.videoWidth / this.videoHeight;
    }
    return 16 / 9;
  }

  private surfaceWidth(): number {
    const aspect = this.displayAspectRatio();
    const viewportAspect = this.viewportWidth / this.viewportHeight;
    return viewportAspect > aspect ? this.viewportHeight * aspect : this.viewportWidth;
  }

  private surfaceHeight(): number {
    const aspect = this.displayAspectRatio();
    const viewportAspect = this.viewportWidth / this.viewportHeight;
    return viewportAspect > aspect ? this.viewportHeight : this.viewportWidth / aspect;
  }

  // 渲染面**自己**的尺寸。解码器交出来的画面是未旋转的（横躺的 1920x1440），
  // 所以节点要按那个方向给尺寸，再整体转 90°——转完正好落回 surfaceWidth ×
  // surfaceHeight 那个竖着的框。只改 aspect 不转节点的话，横画面会被拉进竖框里
  // （用户实测「还是横着的，但是拉伸了」）。
  private surfaceNodeWidth(): number {
    return this.quarterTurned() ? this.surfaceHeight() : this.surfaceWidth();
  }

  private surfaceNodeHeight(): number {
    return this.quarterTurned() ? this.surfaceWidth() : this.surfaceHeight();
  }

  private posterSrc(): string {
    return this.posterPath.startsWith('/') ? `file://${this.posterPath}` : this.posterPath;
  }

  @Styles
  controlNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  controlPressedStyle() {
    .opacity(0.68)
    .scale({ x: 0.9, y: 0.9 })
  }

  @Builder
  tapZone(forward: boolean) {
    if (this.liveMode) {
      // 实况只有一两秒，双击 ±15s 只会瞬间跳到 0 或结尾（seekBy 有 clamp），
      // 是纯粹的误触。但**单击唤起 chrome 必须留着**——整个 Row 不挂的话那一下
      // 也一起丢了。改用 onClick 而不是单击 TapGesture：没有双击要区分，就不必
      // 付那段等待双击的延迟。
      Column()
        .width('50%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .onClick((): void => { this.onBackgroundTap(); });
    } else {
      Column()
        .width('50%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .accessibilityText(forward ? $r('app.string.player_double_tap_forward') : $r('app.string.player_double_tap_back'))
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2, fingers: 1 })
              .onAction((): void => { this.seekBy(forward ? QUICK_SEEK_MS : -QUICK_SEEK_MS); }),
            TapGesture({ count: 1, fingers: 1 })
              .onAction((): void => { this.onBackgroundTap(); })
          )
        );
    }
  }

  @Builder
  seekFeedback() {
    Row() {
      Column({ space: 3 }) {
        if (this.seekFeedbackSide < 0) {
          SymbolGlyph($r('sys.symbol.gobackward_15'))
            .fontSize(36).fontColor([Color.White]);
        } else {
          SymbolGlyph($r('sys.symbol.goforward_15'))
            .fontSize(36).fontColor([Color.White]);
        }
        Text(this.seekFeedbackSide < 0 ? $r('app.string.player_back_15') : $r('app.string.player_forward_15'))
          .fontSize(12)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium);
      }
      .width(96)
      .height(96)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#66000000')
      .borderRadius(48)
      .opacity(this.seekFeedbackVisible && this.seekFeedbackSide < 0 ? 1 : 0)
      .scale({
        x: this.seekFeedbackVisible && this.seekFeedbackSide < 0 ? 1 : 0.82,
        y: this.seekFeedbackVisible && this.seekFeedbackSide < 0 ? 1 : 0.82
      })
      .hitTestBehavior(HitTestMode.None);
      Blank().layoutWeight(1);
      Column({ space: 3 }) {
        if (this.seekFeedbackSide < 0) {
          SymbolGlyph($r('sys.symbol.gobackward_15'))
            .fontSize(36).fontColor([Color.White]);
        } else {
          SymbolGlyph($r('sys.symbol.goforward_15'))
            .fontSize(36).fontColor([Color.White]);
        }
        Text(this.seekFeedbackSide < 0 ? $r('app.string.player_back_15') : $r('app.string.player_forward_15'))
          .fontSize(12)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium);
      }
      .width(96)
      .height(96)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#66000000')
      .borderRadius(48)
      .opacity(this.seekFeedbackVisible && this.seekFeedbackSide > 0 ? 1 : 0)
      .scale({
        x: this.seekFeedbackVisible && this.seekFeedbackSide > 0 ? 1 : 0.82,
        y: this.seekFeedbackVisible && this.seekFeedbackSide > 0 ? 1 : 0.82
      })
      .hitTestBehavior(HitTestMode.None);
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  symbolControl(symbol: string, width: number, symbolSize: number, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol))
        .fontSize(symbolSize)
        .fontColor([CONTROL_ACCENT]);
    }
    .width(width)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(17)
    .stateStyles({
      normal: this.controlNormalStyle,
      pressed: this.controlPressedStyle
    })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onClick(onTap);
  }

  @Builder
  speedControl() {
    Row() {
      Text(SPEED_LABELS[this.speedIdx])
        .fontSize(15)
        .fontColor(CONTROL_ACCENT)
        .fontWeight(FontWeight.Bold);
    }
    .width(48)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.speedIdx === DEFAULT_SPEED_IDX ? Color.Transparent : $r('app.color.selected_pill'))
    .borderRadius(18)
    .stateStyles({
      normal: this.controlNormalStyle,
      pressed: this.controlPressedStyle
    })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .accessibilityText(str('player_speed_a11y', SPEED_LABELS[this.speedIdx]))
    .onClick((): void => { this.cycleSpeed(); });
  }

  @Builder
  playControl() {
    Stack() {
      Circle({ width: 42, height: 42 }).fill('#00000000');
      if (this.isPlaying) {
        Row({ space: 5 }) {
          Column().width(4).height(16).borderRadius(2).backgroundColor(CONTROL_ACCENT);
          Column().width(4).height(16).borderRadius(2).backgroundColor(CONTROL_ACCENT);
        }
        .width(18).height(18)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
      } else {
        SymbolGlyph($r('sys.symbol.play_fill')).fontSize(22).fontColor([CONTROL_ACCENT]).margin({ left: 2 });
      }
    }
    .width(56).height(42)
    .borderRadius(21)
    .stateStyles({
      normal: this.controlNormalStyle,
      pressed: this.controlPressedStyle
    })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onClick(() => { this.togglePlay(); });
  }

  build() {
    Stack() {
      if (this.posterPath !== '') {
        Image(this.posterSrc()).draggable(false)
          .width(this.surfaceWidth())
          .height(this.surfaceHeight())
          .objectFit(ImageFit.Contain)
          // 实况这一层是「首帧到位之前用户看到的东西」，压暗到 0.88 会让随后
          // 淡入的真首帧显得跳一下；普通视频保持原样（它本来就要被播放盖住）。
          .opacity(this.hasError ? 0.54 : (this.liveMode ? 1 : 0.88));
      }
      XComponent({ id: this.componentId(), type: XComponentType.SURFACE, libraryname: 'ijkplayer_napi' })
        .opacity(this.videoVisible ? 1 : 0)
        .animation({ duration: 180, curve: Curve.EaseOut })
        // ── 下面这三样**故意写在 .animation() 之后**，不进动画 ──────────────
        //
        // .animation() 的作用域是它**上面**的属性。旋转角是首帧解出来之后
        // （ijk 的 info 10001）才知道的，是一次 0 → 90 的跳变；写在动画上面
        // 这一跳就被动画成 180ms 的转场，而那时画面还没解出来——屏幕上就是
        // 一块黑色的面在转（用户实测「实况照片打开有个旋转的黑块」）。
        // 尺寸同理：转 90° 时宽高要互换，跟着动画就是一块黑面边转边变形。
        //
        // 绕自身中心转（ArkUI 默认轴心就是中心），父级 Stack 居中，转完与框重合。
        .width(this.surfaceNodeWidth()).height(this.surfaceNodeHeight())
        .rotate({ angle: this.videoRotationDeg })
        .onLoad((context: object) => {
          this.surfaceContext = context;
          this.initPlayer(context);
        })
        .onDestroy(() => {
          this.release();
          this.surfaceContext = null;
        });
      // 纯装饰的 seek 反馈必须位于 tapZone 之下：它用 opacity 隐藏（始终在树上），
      // 而 HitTestMode.None 只让自身不响应、子节点仍参与命中测试，叠在上面时
      // 会永久吞掉左右两块圆形区域的点击（表现为"单击唤起控制器没反应"）。
      this.seekFeedback();
      // Controls hidden → both halves remain interactive. Exclusive recognition
      // delays the single tap just enough to distinguish the double-tap seek.
      // Embedded (chat-bubble) mode never renders the gesture layer at all.
      if (!this.embedded && !this.showControls) {
        Row() {
          this.tapZone(false);
          this.tapZone(true);
        }
        .width('100%')
        .height('100%');
      }
      // Actual prepare/stall state: centered and explicit, while the poster
      // remains visible underneath instead of flashing a featureless black frame.
      if (shouldShowPlayerStatus(this.status, this.hasError, this.statusVisible, this.isPrepared)) {
        if (this.embedded) {
          // Embedded (chat-bubble) buffering indicator: a plain ring centered
          // over the video — no percentage text, no dark card behind it, just
          // the ring riding on top of the poster/surface.
          //
          // bufferedPercent stays 0 until the first real progress sample
          // arrives; a fully-empty ring there reads as "nothing is happening"
          // rather than "buffering", so it floors at a small fixed sliver
          // instead.
          Progress({
            value: this.bufferedPercent > 0 ? this.bufferedPercent : 8,
            total: 100,
            type: ProgressType.Ring
          })
            .width(32)
            .height(32)
            .color(Color.White)
            .backgroundColor('#33FFFFFF')
            .align(Alignment.Center)
            // Purely decorative — must not steal the tap that opens/toggles
            // controls on the video underneath.
            .hitTestBehavior(HitTestMode.Transparent);
        } else {
          Column({ space: 8 }) {
            if (this.bufferedPercent > 0 && this.bufferedPercent < 100) {
              Stack() {
                Progress({ value: this.bufferedPercent, total: 100, type: ProgressType.Ring })
                  .width(44).height(44).color(Color.White);
                Text(`${this.bufferedPercent}%`).fontSize(10).fontColor(Color.White);
              }
            } else {
              LoadingProgress().width(38).height(38).color(Color.White);
            }
            Text(this.status)
              .fontSize(13)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium);
          }
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 18, right: 18, top: 15, bottom: 15 })
          .backgroundColor('#70000000')
          .borderRadius(16)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
            .animation({ duration: 180, curve: Curve.EaseOut }));
        }
      }
      // 内嵌模式不画错误 UI：那颗"重试"按钮会吃掉气泡"点开全屏"的点击，而
      // 失败的这一条本来就已经通过 onFailed() 让出播放位、即将卸载回封面。
      if (this.hasError && !this.embedded) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(30)
            .fontColor([Color.White]);
          Text($r('app.string.player_playback_failed'))
            .fontSize(14)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
          Text(this.errorDetail)
            .fontSize(11)
            .fontColor(CONTROL_TEXT_SOFT)
            .maxLines(2)
            .textAlign(TextAlign.Center);
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([Color.White]);
            Text($r('app.string.settings_retry')).fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
          .height(34)
          .padding({ left: 15, right: 15 })
          .backgroundColor('#29FFFFFF')
          .borderRadius(17)
          .stateStyles({
            normal: this.controlNormalStyle,
            pressed: this.controlPressedStyle
          })
          .animation({ duration: 120, curve: Curve.EaseOut })
          .onClick((): void => { this.retry(); });
        }
        .constraintSize({ minWidth: 180, maxWidth: 248 })
        .padding({ left: 20, right: 20, top: 17, bottom: 16 })
        .backgroundColor('#78000000')
        .borderRadius(18)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.9, y: 0.9 }))
          .animation({ duration: 180, curve: Curve.EaseOut }));
      }
      if (this.speedFeedbackVisible) {
        Row() {
          Text(this.speedFeedbackText)
            .fontSize(14)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium);
        }
        .height(38)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#78000000')
        .borderRadius(19)
        .opacity(this.speedFeedbackVisible ? 1 : 0)
        .scale({
          x: this.speedFeedbackVisible ? 1 : 0.88,
          y: this.speedFeedbackVisible ? 1 : 0.88
        })
        .hitTestBehavior(HitTestMode.None);
      }
      // `!this.liveMode`：这一块既没有 !embedded 也没有 showControls 守卫（对比
      // 下面的控制栏），而实况正是靠关掉 showControls 给左下角那枚胶囊让位的。
      // 不挡的话播完那一刻中央一个「重播」、左下角一个播放键，两个入口同时在场。
      if (this.isCompleted && !this.liveMode) {
        Stack() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(25).fontColor([Color.White]);
            Text($r('app.string.player_replay')).fontSize(18).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
          .padding({ left: 20, right: 20, top: 14, bottom: 14 })
          .backgroundColor(CONTROL_BAR_BG)
          .borderRadius(20);
        }
        .constraintSize({ minWidth: 140, minHeight: 64 })
        .stateStyles({
          normal: this.controlNormalStyle,
          pressed: this.controlPressedStyle
        })
        .animation({ duration: 120, curve: Curve.EaseOut })
        .onClick(() => { this.replay(); });
      }
      if (!this.embedded && this.showControls && !this.hasError) {
        Column() {
          Row() {
            this.tapZone(false);
            this.tapZone(true);
          }
          .width('100%')
          .layoutWeight(1);
          Column({ space: 10 }) {
            Row() {
              // Live download speed on the left (mirrors the play control on the
              // right), so the centered play button stays centered.
              Row({ space: 3 }) {
                if (this.downloadSpeed > 0) {
                  SymbolGlyph($r('sys.symbol.arrow_down')).fontSize(12).fontColor([CONTROL_TEXT_SOFT]);
                  Text(formatSpeed(this.downloadSpeed))
                    .fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
                }
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Start)
              .alignItems(VerticalAlign.Center);
              this.playControl();
              Row({ space: 8 }) {
                this.speedControl();
                this.symbolControl(
                  this.landscape
                    ? 'sys.symbol.rectangle_portrait_rotate'
                    : 'sys.symbol.rectangle_rotate',
                  40,
                  25,
                  () => {
                    this.onOrientationChange(!this.landscape);
                  }
                );
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.End)
              .alignItems(VerticalAlign.Center);
            }.width('100%').alignItems(VerticalAlign.Center);
            Row({ space: 8 }) {
              Text(formatMs(this.dragging ? this.dragValueMs : this.currentTimeMs))
                .fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
              // Alignment.Start = left edge, vertically centered. With Center the
              // partial-width fill rows get centered in the track and appear to
              // grow outward from the middle instead of filling left-to-right.
              Stack() {
                Row()
                  .width('100%').height(4).borderRadius(2).backgroundColor(CONTROL_TRACK_SOFT);
                // Downloaded/buffered span — grey, behind the played fill.
                Row()
                  .width(`${Math.max(0, Math.min(100, this.bufferedPercent))}%`)
                  .height(4).borderRadius(2).backgroundColor(CONTROL_TRACK_SOFT_FILL);
                Row()
                  .width(this.durationMs > 0
                    ? `${Math.max(0, Math.min(100, ((this.dragging ? this.dragValueMs : this.currentTimeMs) / this.durationMs) * 100))}%`
                    : '0%')
                  .height(4).borderRadius(2).backgroundColor(CONTROL_TRACK);
                Slider({
                  value: this.dragging ? this.dragValueMs : this.currentTimeMs,
                  min: 0, max: this.durationMs > 0 ? this.durationMs : 1, step: 1
                })
                  .width('100%')
                  .trackColor('#00000000').selectedColor('#00000000').blockColor(CONTROL_ACCENT)
                  .blockSize({ width: 16, height: 16 })
                  .onChange((value: number, mode: SliderChangeMode) => { this.onSeekChange(value, mode); });
              }
              .layoutWeight(1)
              .height(20)
              .align(Alignment.Start);
              Text(formatMs(this.durationMs)).fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
            }.width('100%').alignItems(VerticalAlign.Center);
          }
          .margin({
            left: 12,
            right: 12,
            bottom: Math.max(14, this.bottomSafe + 8)
          })
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          // 控制条和查看器顶栏是同一层东西，走同一档材质（见 overlayMaterial
          // 的 'viewer'：底永远是黑的，不跟随主题）。
          .backgroundColor(overlayGlassFill('viewer', CONTROL_BAR_BG))
          .backdropBlur(overlayBackdropBlur('viewer'))
          .attributeModifier(materialModifier('viewer'))
          .borderRadius(18)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: 10 }))
            .animation({ duration: 180, curve: Curve.EaseOut }));
          // NOTE: no hitTestBehavior on this wrapper or the bar. Block suppresses
          // hit-testing of CHILDREN (killed every button), and Transparent leaks
          // gesture events through to the XComponent (buttons lose to its onClick).
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.OPACITY
          .animation({ duration: 160, curve: Curve.EaseOut }));
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .onAreaChange((_old: Area, area: Area): void => {
      const width = area.width as number;
      const height = area.height as number;
      if (width > 0 && height > 0) {
        this.viewportWidth = width;
        this.viewportHeight = height;
      }
    });
  }
}
