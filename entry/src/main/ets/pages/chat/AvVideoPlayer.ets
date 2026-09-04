// 全屏视频播放器的**系统 AVPlayer 版**，与 StreamingVideoPlayer（ijkplayer）
// 并存、可一键互换（开关见 store/AppSettings 的 KEY_VIDEO_ENGINE_AVPLAYER，
// 分流在 VideoPlayerHost）。
//
// 【为什么要有第二套】HDR。打包进来的 @ohos/ijkplayer 从渲染层就没有 HDR 通路：
// libijksdl 的着色器只有 BT.601/709 两个 SDR 色彩矩阵、没有 PQ/HLG 传递函数、
// EGL config 只有 rgb565/rgb888/rgbx8888，四个 so 里也找不到一次
// OH_NativeWindow_SetMetadataValue。HDR 片源解得出来（P010 那条通路在），但被
// 当成 SDR 压进 8 位，画面发灰发暗。系统 AVPlayer 有 PlaybackStrategy.preferredHdr。
//
// 【刻意保持的两件事】
//   1. prop 接口与 StreamingVideoPlayer **逐字段一致**，两者可以直接对换。
//   2. 控制条的颜色、倍速档位、双击跳转量全部来自 util/playerChrome，不在这里
//      另写字面量——切换引擎时界面不能变样。
//
// 【与 ijk 版的真实差异】（不是遗漏，是平台差异，都在下面对应位置注明）
//   · 旋转：AVPlayer 自己按 display matrix 出画，这里**没有** rotate()，也不做
//     宽高转置。ijk 版那套 info 10001 + 手工旋转在这里是多余且有害的。
//   · 音频焦点：走官方的 avPlayer.on('audioInterrupt')，不走 services/audioFocus
//     ——那个 AudioSession 方案是**因为 ijk 拿不到 audioInterrupt** 才有的
//     （见该文件开头的说明）。两套一起上会重复管理。
//   · 首帧：用 PlaybackStrategy.showFirstFrameOnPrepare，不需要 ijk 版
//     「静音起播→等 what===3→就地暂停」那套预热。

import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  MATERIAL_EPOCH, overlayBackdropBlur, overlayGlassFill
} from '../../util/overlayMaterial';
import { shouldShowPlayerStatus } from '../../util/playerStatusGate';
import { HDR_BADGE_TEXT, isHdrTrackValue } from '../../util/hdrBadge';
import { materialModifier } from '../../util/materialModifier';
import {
  AUTO_RETRY_DELAYS_MS, CONTROL_ACCENT, CONTROL_BAR_BG, CONTROL_TEXT_SOFT,
  CONTROL_TRACK, CONTROL_TRACK_SOFT, CONTROL_TRACK_SOFT_FILL, DEFAULT_SPEED_IDX,
  HEADSET_DEVICE_TYPES, QUICK_SEEK_MS, SPEEDS, SPEED_LABELS, STATUS_DELAY_MS,
  formatMs, formatSpeed
} from '../../util/playerChrome';
import { getTdClient, getUiAbilityContext } from '../../tdkit/Globals';
import { mediaPlaybackKeepAlive } from '../../services/MediaPlaybackKeepAlive';
import { KEY_BG_PLAY_VIDEO } from '../../store/AppSettings';
import { VideoRangeServer } from '../../services/VideoRangeServer';
import { VideoStreamSession } from '../../services/VideoStreamSession';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE, logI } from '../../util/log';

let nextAvPlayerInstanceId: number = 1;

// 倍速档位 → AVPlayer 的枚举。
//
// **枚举成员只在函数体里解引用，绝不放模块级常量**——v1.3.6 的启动崩溃就是
// 模块级取高版本枚举成员造成的（见 util/overlayMaterial 的说明）。
//
// SPEEDS 是 ['0.5','1.0','1.5','2.0']。AVPlayer 的档位是离散枚举，0.5 与 1.5
// 属于后加的成员；取不到时退回 1.0 而不是崩，由调用方把"没设上"回报给用户。
function avSpeedFor(label: string): media.PlaybackSpeed {
  if (label === '0.5') {
    return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
  }
  if (label === '1.5') {
    return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
  }
  if (label === '2.0') {
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
  }
  return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
}

@Component
export struct AvVideoPlayer {
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
  @Prop embedded: boolean = false;
  @StorageProp('appIsForeground') @Watch('onAppForegroundChanged')
  private appIsForeground: boolean = true;
  @Watch('onMutedChanged') @Prop muted: boolean = false;
  @Prop startPositionMs: number = 0;
  @Prop @Watch('onLiveToggleRequested') liveToggleSeq: number = 0;
  @Prop liveMode: boolean = false;
  onPlayStateChanged: (playing: boolean) => void = (): void => {};
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
  onFailed: () => void = (): void => {};

  private player: media.AVPlayer | null = null;
  private session: VideoStreamSession | null = null;
  private rangeServer: VideoRangeServer | null = null;
  private progressUnsub: (() => void) | null = null;
  private routingManager: audio.AudioRoutingManager | null = null;
  private deviceChangeCb: ((change: audio.DeviceChangeAction) => void) | null = null;
  // 本地文件走 fd://，句柄必须自己收——AVPlayer 不负责关它。
  private localFd: fileIo.File | null = null;
  private seekFeedbackTimer: number = -1;
  private speedFeedbackTimer: number = -1;
  private retryTimer: number = -1;
  private statusDelayTimer: number = -1;
  private autoRetries: number = 0;
  private surfaceId: string = '';
  private active: boolean = true;
  private lastBufferedBytes: number = 0;
  private lastSpeedSampleMs: number = 0;
  // 「被系统打断」才暂停的。打断结束只恢复这一种——用户自己按的暂停不该因为
  // 别人打完电话就自己动起来。
  private pausedByInterrupt: boolean = false;
  private readonly instanceId: number = nextAvPlayerInstanceId++;
  private readonly xController: XComponentController = new XComponentController();

  @State status: string = str('player_buffering_dots');
  @State statusVisible: boolean = false;
  @State hasError: boolean = false;
  @State errorDetail: string = '';
  @State isPrepared: boolean = false;
  @State videoVisible: boolean = false;
  @State bufferedPercent: number = 0;
  @State downloadSpeed: number = 0;
  @State @Watch('onPlayingChanged') isPlaying: boolean = false;
  @State currentTimeMs: number = 0;
  @State durationMs: number = 0;
  @State dragging: boolean = false;
  @State dragValueMs: number = 0;
  @State speedIdx: number = DEFAULT_SPEED_IDX;
  @State isCompleted: boolean = false;
  // AVPlayer 的 videoSizeChange 报的已经是**显示**尺寸（旋转已应用），
  // 所以这里只存一个宽高比，没有 quarterTurned 那套转置。
  @State decodedAspectRatio: number = 0;
  @State viewportWidth: number = 1;
  @State viewportHeight: number = 1;
  @State seekFeedbackSide: number = 0;
  @State seekFeedbackVisible: boolean = false;
  @State speedFeedbackVisible: boolean = false;
  @State speedFeedbackText: string = '';
  // 片源是不是 HDR（控制条左侧那枚角标）。prepared 之后查一次轨道信息就定了，
  // 播放过程中不会变。查不到一律为 false —— 见 util/hdrBadge 的「宁可不标」。
  @State isHdrSource: boolean = false;

  private onLiveToggleRequested(): void {
    if (this.liveToggleSeq > 0) {
      this.togglePlay();
    }
  }

  aboutToAppear(): void {
    this.active = true;
    this.armStatusDelay();
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
    if (this.surfaceId !== '') {
      this.initPlayer();
    }
  }

  private deactivate(): void {
    this.active = false;
    this.isPlaying = false;
    mediaPlaybackKeepAlive.release('video');
    this.release();
  }

  // 见 util/playerStatusGate（issue #192）：起播前的状态卡片延迟出现。
  private armStatusDelay(): void {
    this.statusVisible = false;
    if (this.statusDelayTimer !== -1) {
      clearTimeout(this.statusDelayTimer);
    }
    this.statusDelayTimer = setTimeout((): void => {
      this.statusDelayTimer = -1;
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
    this.seekFeedbackVisible = false;
    this.speedFeedbackVisible = false;
    this.isHdrSource = false;
  }

  onPlayingChanged(): void {
    this.onPlayStateChanged(this.isPlaying);
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

  // 拔耳机就暂停，和 ijk 版同一套约定。
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
        if (unpluggedHeadset && this.isPlaying) {
          this.pauseNative();
        }
      };
      routingManager.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG, this.deviceChangeCb);
    } catch (e) {
      logE(`AvVideoPlayer.setupAudioDeviceListener failed: ${e}`);
    }
  }

  private cleanupAudioDeviceListener(): void {
    if (this.routingManager !== null && this.deviceChangeCb !== null) {
      try {
        this.routingManager.off('deviceChange', this.deviceChangeCb);
      } catch (e) {
        logE(`AvVideoPlayer.cleanupAudioDeviceListener failed: ${e}`);
      }
    }
    this.routingManager = null;
    this.deviceChangeCb = null;
  }

  private clearTimers(): void {
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
    if (this.statusDelayTimer !== -1) {
      clearTimeout(this.statusDelayTimer);
      this.statusDelayTimer = -1;
    }
  }

  private release(): void {
    this.cleanupAudioDeviceListener();
    this.clearTimers();
    if (this.progressUnsub !== null) {
      this.progressUnsub();
      this.progressUnsub = null;
    }
    if (this.player !== null) {
      const p = this.player;
      this.player = null;
      // release() 之前先摘监听：AVPlayer 在释放过程中还会报 stateChange，
      // 那些回调打到一个已经作废的实例上只会引出「操作了 released 状态的
      // 播放器」这类错误日志。
      try {
        p.off('stateChange');
        p.off('error');
        p.off('timeUpdate');
        p.off('durationUpdate');
        p.off('videoSizeChange');
        p.off('audioInterrupt');
      } catch (e) {
        logE(`AvVideoPlayer.off failed: ${e}`);
      }
      p.release().catch((err: BusinessError): void => {
        logE(`AvVideoPlayer.release failed: ${err.code} ${err.message}`);
      });
    }
    if (this.rangeServer !== null) {
      this.rangeServer.close();
      this.rangeServer = null;
    }
    if (this.session !== null) {
      this.session.close();
      this.session = null;
    }
    if (this.localFd !== null) {
      const f = this.localFd;
      this.localFd = null;
      try {
        fileIo.closeSync(f);
      } catch (e) {
        logE(`AvVideoPlayer.closeFd failed: ${e}`);
      }
    }
    this.isPlaying = false;
  }

  private applyMutedVolume(): void {
    if (this.player === null || !this.isPrepared) {
      return;
    }
    try {
      this.player.setVolume(this.muted ? 0 : 1);
    } catch (e) {
      logE(`AvVideoPlayer.setVolume failed: ${e}`);
    }
  }

  private onMutedChanged(): void {
    this.applyMutedVolume();
  }

  // 起播源：本地文件走 fd://，否则起 TDLib 分片会话 + 本地 Range 服务拿 http://。
  // 两条都用 createMediaSourceWithUrl，因为 **PlaybackStrategy（HDR 开关在里面）
  // 只能通过 setMediaSource 传**，直接写 avPlayer.url 就没地方放策略了。
  private async buildSourceUrl(): Promise<string> {
    if (this.localPath !== '') {
      const file = fileIo.openSync(this.localPath, fileIo.OpenMode.READ_ONLY);
      this.localFd = file;
      return `fd://${file.fd}`;
    }
    const session = new VideoStreamSession(getTdClient(), this.fileId, this.fileSize);
    this.session = session;
    this.progressUnsub = session.subscribeProgress((buffered: number, total: number): void => {
      this.bufferedPercent = total > 0 ? Math.min(100, Math.floor((buffered / total) * 100)) : 0;
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
    return await rangeServer.start();
  }

  private async initPlayer(): Promise<void> {
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
    try {
      const sourceUrl: string = await this.buildSourceUrl();
      if (!this.active) {
        this.release();
        return;
      }
      const player: media.AVPlayer = await media.createAVPlayer();
      if (!this.active) {
        player.release();
        this.release();
        return;
      }
      this.player = player;
      this.attachCallbacks(player);
      const source: media.MediaSource = media.createMediaSourceWithUrl(sourceUrl);
      const strategy: media.PlaybackStrategy = {
        // 这一行就是这整个文件存在的理由。
        preferredHdr: true,
        // prepare 完成即出首帧：实况「静态照片」那一帧不用再靠静音起播去骗，
        // ijk 版的 primingFirstFrame 那套在这里整个不需要。
        showFirstFrameOnPrepare: true
      };
      await player.setMediaSource(source, strategy);
    } catch (e) {
      logE(`AvVideoPlayer.init failed: ${e}`);
      this.release();
      this.showError(str('player_load_failed'));
    }
  }

  private attachCallbacks(player: media.AVPlayer): void {
    player.on('stateChange', (state: string, _reason: media.StateChangeReason): void => {
      if (this.player !== player) {
        return;
      }
      this.onStateChange(player, state);
    });
    player.on('error', (err: BusinessError): void => {
      if (this.player !== player) {
        return;
      }
      this.onNativeError(err);
    });
    player.on('timeUpdate', (time: number): void => {
      if (this.player !== player || this.dragging) {
        return;
      }
      this.currentTimeMs = Math.max(0, time);
      this.onPositionChanged(this.currentTimeMs);
    });
    player.on('durationUpdate', (duration: number): void => {
      if (this.player !== player || duration <= 0) {
        return;
      }
      this.durationMs = duration;
    });
    player.on('videoSizeChange', (width: number, height: number): void => {
      if (this.player !== player) {
        return;
      }
      this.updateVideoAspect(width, height);
    });
    // 官方推荐的打断处理（见 services/audioFocus 开头：那套 AudioSession 方案
    // 正是**因为 ijk 拿不到这个回调**才存在的，这里不该两套一起上）。
    player.on('audioInterrupt', (event: audio.InterruptEvent): void => {
      if (this.player !== player) {
        return;
      }
      this.onAudioInterrupt(event);
    });
  }

  private onStateChange(player: media.AVPlayer, state: string): void {
    if (state === 'initialized') {
      player.surfaceId = this.surfaceId;
      player.prepare().catch((err: BusinessError): void => {
        logE(`AvVideoPlayer.prepare failed: ${err.code} ${err.message}`);
        this.onNativeError(err);
      });
      return;
    }
    if (state === 'prepared') {
      this.autoRetries = 0;
      this.status = '';
      this.hasError = false;
      this.isPrepared = true;
      this.isCompleted = false;
      this.durationMs = Math.max(0, player.duration);
      this.applySpeed(this.speedIdx);
      this.applyMutedVolume();
      // **缩放交给播放器，不要用节点尺寸去套画面比例。**
      //
      // 原来 XComponent 的宽高是按视频比例算出来的（surfaceWidth/Height），转屏时
      // 视口一变就得重算，而 XComponent 尺寸一变 = surface 重新配置 —— AVPlayer
      // 的 surface 重配很贵，转屏动画期间反复重配就是用户实测的"旋转屏幕卡顿"。
      // 改成 surface 恒等于视口、由 VIDEO_SCALE_TYPE_SCALED_ASPECT 在播放器内部
      // 保持比例（长边填满、短边居中、留黑），转屏只是一次容器尺寸变化。
      try {
        player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT;
      } catch (e) {
        logE(`AvVideoPlayer.videoScaleType failed: ${e}`);
      }
      if (this.startPositionMs > 0) {
        player.seek(Math.floor(this.startPositionMs), media.SeekMode.SEEK_CLOSEST);
        this.currentTimeMs = this.startPositionMs;
      }
      this.detectHdr(player);
      // showFirstFrameOnPrepare 让 prepare 完成时 Surface 里已经有第一帧，
      // 可以直接把封面撤掉，不会露黑。
      this.videoVisible = true;
      if (this.liveMode) {
        // 实况：停在首帧当「静态照片」，等胶囊那一下再播。
        return;
      }
      this.playNative();
      return;
    }
    if (state === 'playing') {
      this.isPlaying = true;
      this.videoVisible = true;
      return;
    }
    if (state === 'paused') {
      this.isPlaying = false;
      return;
    }
    if (state === 'completed') {
      this.isPlaying = false;
      this.currentTimeMs = this.durationMs;
      if (this.embedded) {
        this.onEnded();
        return;
      }
      this.isCompleted = true;
      if (this.liveMode) {
        // 播完回到静态首帧（iOS 的手感）。
        player.seek(0, media.SeekMode.SEEK_CLOSEST);
        this.currentTimeMs = 0;
      }
    }
  }

  // 查一次视频轨的 hdr_type。只在 prepared 之后调，且**不阻塞起播**——查失败
  // 或查不到就是角标不亮，播放不受任何影响。
  private detectHdr(player: media.AVPlayer): void {
    player.getTrackDescription().then((tracks: Array<media.MediaDescription>): void => {
      if (this.player !== player) {
        return;
      }
      for (const track of tracks) {
        const trackType: string = `${track[media.MediaDescriptionKey.MD_KEY_TRACK_TYPE]}`;
        if (Number(trackType) !== media.MediaType.MEDIA_TYPE_VID) {
          continue;
        }
        const raw: string = `${track[media.MediaDescriptionKey.MD_KEY_HDR_TYPE] ?? ''}`;
        const hdr: boolean = isHdrTrackValue(raw === 'undefined' ? '' : raw);
        logI(`AvVideoPlayer hdr_type=${raw} → badge=${hdr}`);
        this.isHdrSource = hdr;
        return;
      }
    }).catch((err: BusinessError): void => {
      logE(`AvVideoPlayer.getTrackDescription failed: ${err.code} ${err.message}`);
    });
  }

  private onNativeError(err: BusinessError): void {
    this.isPlaying = false;
    logE(`AvVideoPlayer error: code=${err.code} msg=${err.message}` +
      ` autoRetries=${this.autoRetries}`);
    if (this.autoRetries < AUTO_RETRY_DELAYS_MS.length && this.active) {
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

  private onAudioInterrupt(event: audio.InterruptEvent): void {
    if (!this.active || this.player === null) {
      return;
    }
    const hint: audio.InterruptHint = event.hintType;
    if (hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
      hint === audio.InterruptHint.INTERRUPT_HINT_STOP) {
      if (this.isPlaying) {
        this.pauseNative();
        // STOP 是永久失去焦点，不会再有 resume；标成「被打断」只会让它以后
        // 莫名其妙自己响起来。
        this.pausedByInterrupt = hint === audio.InterruptHint.INTERRUPT_HINT_PAUSE;
      }
      return;
    }
    if (hint === audio.InterruptHint.INTERRUPT_HINT_RESUME && this.pausedByInterrupt) {
      this.pausedByInterrupt = false;
      if (!this.isPlaying && this.isPrepared && !this.hasError && !this.isCompleted) {
        this.playNative();
      }
    }
    // DUCK / UNDUCK 不动：那是「压低音量让别人说话」，视频该继续放。
  }

  private playNative(): void {
    if (this.player === null) {
      return;
    }
    this.player.play().catch((err: BusinessError): void => {
      logE(`AvVideoPlayer.play failed: ${err.code} ${err.message}`);
    });
  }

  private pauseNative(): void {
    if (this.player === null) {
      return;
    }
    this.player.pause().catch((err: BusinessError): void => {
      logE(`AvVideoPlayer.pause failed: ${err.code} ${err.message}`);
    });
  }

  private showError(detail: string): void {
    this.status = '';
    this.hasError = true;
    this.errorDetail = detail;
    this.isPrepared = false;
    this.videoVisible = false;
    this.isPlaying = false;
    if (this.embedded) {
      this.onFailed();
    }
  }

  private retry(): void {
    if (this.surfaceId === '' || !this.active) {
      return;
    }
    this.release();
    this.hasError = false;
    this.errorDetail = '';
    this.status = str('player_reconnecting');
    this.isCompleted = false;
    this.currentTimeMs = 0;
    this.retryTimer = setTimeout((): void => {
      this.retryTimer = -1;
      if (this.active) {
        this.initPlayer();
      }
    }, 100);
  }

  // 切后台按「后台播放视频」这个设置决定停不停。理由同 ijk 版：
  // backgroundGraceTask 会让进程多活几分钟，不主动停就是带声音继续放。
  private onAppForegroundChanged(): void {
    if (this.appIsForeground || !this.isPlaying || this.player === null) {
      return;
    }
    if (!this.embedded && (AppStorage.get<boolean>(KEY_BG_PLAY_VIDEO) ?? false)) {
      return;
    }
    this.pauseNative();
  }

  private togglePlay(): void {
    if (this.player === null || this.hasError || !this.isPrepared) {
      return;
    }
    if (this.isCompleted) {
      this.replay();
      return;
    }
    // 用户自己动过手就不再算「被系统打断」。
    this.pausedByInterrupt = false;
    if (this.isPlaying) {
      this.pauseNative();
    } else {
      this.playNative();
    }
  }

  private replay(): void {
    if (this.player === null) {
      return;
    }
    this.isCompleted = false;
    this.currentTimeMs = 0;
    this.player.seek(0, media.SeekMode.SEEK_CLOSEST);
    this.playNative();
  }

  private seekBy(deltaMs: number): void {
    if (this.player === null || !this.isPrepared || this.durationMs <= 0 || this.hasError) {
      return;
    }
    const base = this.dragging ? this.dragValueMs : this.currentTimeMs;
    const target = Math.max(0, Math.min(this.durationMs, base + deltaMs));
    this.dragging = false;
    this.currentTimeMs = target;
    this.player.seek(Math.floor(target), media.SeekMode.SEEK_CLOSEST);
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

  private onSeekChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.dragging = true;
      this.dragValueMs = value;
      return;
    }
    this.dragging = false;
    this.currentTimeMs = value;
    if (this.player !== null && this.isPrepared) {
      this.player.seek(Math.floor(value), media.SeekMode.SEEK_CLOSEST);
    }
  }

  private applySpeed(idx: number): boolean {
    if (this.player === null || !this.isPrepared) {
      return true;
    }
    try {
      this.player.setSpeed(avSpeedFor(SPEEDS[idx]));
      return true;
    } catch (caught) {
      logE(`AvVideoPlayer.setSpeed failed: ${caught}`);
      return false;
    }
  }

  private cycleSpeed(): void {
    const nextIdx: number = (this.speedIdx + 1) % SPEEDS.length;
    const applied: boolean = this.applySpeed(nextIdx);
    logI(`AvVideoPlayer speed requested=${SPEEDS[nextIdx]} applied=${applied}`);
    // 就绪之前也记住选择：prepared 时 applySpeed 会补上。
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

  private componentId(): string {
    return `av_video_${this.fileId}_${this.instanceId}`;
  }

  private updateVideoAspect(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    const aspect = width / height;
    if (Number.isFinite(aspect) && aspect > 0 && Math.abs(aspect - this.decodedAspectRatio) > 0.001) {
      logI(`[AvVideoRot] display=${width}x${height} declared=${this.videoWidth}x${this.videoHeight}`);
      this.decodedAspectRatio = aspect;
    }
  }

  private displayAspectRatio(): number {
    if (this.decodedAspectRatio > 0) {
      return this.decodedAspectRatio;
    }
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
        .accessibilityText(forward
          ? $r('app.string.player_double_tap_forward') : $r('app.string.player_double_tap_back'))
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
  seekFeedbackBadge(side: number) {
    Column({ space: 3 }) {
      if (side < 0) {
        SymbolGlyph($r('sys.symbol.gobackward_15')).fontSize(36).fontColor([Color.White]);
      } else {
        SymbolGlyph($r('sys.symbol.goforward_15')).fontSize(36).fontColor([Color.White]);
      }
      Text(side < 0 ? $r('app.string.player_back_15') : $r('app.string.player_forward_15'))
        .fontSize(12)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium);
    }
    .width(96)
    .height(96)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000')
    .borderRadius(48)
    .opacity(this.seekFeedbackVisible && this.seekFeedbackSide === side ? 1 : 0)
    .scale({
      x: this.seekFeedbackVisible && this.seekFeedbackSide === side ? 1 : 0.82,
      y: this.seekFeedbackVisible && this.seekFeedbackSide === side ? 1 : 0.82
    })
    .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  seekFeedback() {
    Row() {
      this.seekFeedbackBadge(-1);
      Blank().layoutWeight(1);
      this.seekFeedbackBadge(1);
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
    .stateStyles({ normal: this.controlNormalStyle, pressed: this.controlPressedStyle })
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
    .backgroundColor(this.speedIdx === DEFAULT_SPEED_IDX
      ? Color.Transparent : $r('app.color.selected_pill'))
    .borderRadius(18)
    .stateStyles({ normal: this.controlNormalStyle, pressed: this.controlPressedStyle })
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
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(22).fontColor([CONTROL_ACCENT]).margin({ left: 2 });
      }
    }
    .width(56).height(42)
    .borderRadius(21)
    .stateStyles({ normal: this.controlNormalStyle, pressed: this.controlPressedStyle })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onClick(() => { this.togglePlay(); });
  }

  @Builder
  statusCard() {
    if (this.embedded) {
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

  @Builder
  controlBar() {
    Column() {
      Row() {
        this.tapZone(false);
        this.tapZone(true);
      }
      .width('100%')
      .layoutWeight(1);
      Column({ space: 10 }) {
        Row() {
          // 左槽：HDR 角标 + 下载速度。两者都是「有才显示」，槽本身恒占
          // layoutWeight(1)，所以中间那颗播放键始终居中。
          Row({ space: 6 }) {
            if (this.isHdrSource) {
              Text(HDR_BADGE_TEXT)
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(CONTROL_ACCENT)
                .letterSpacing(0.5)
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .border({ width: 1, color: CONTROL_TEXT_SOFT, radius: 4 })
                .accessibilityText(str('player_hdr_a11y'));
            }
            Row({ space: 3 }) {
              if (this.downloadSpeed > 0) {
                SymbolGlyph($r('sys.symbol.arrow_down')).fontSize(12).fontColor([CONTROL_TEXT_SOFT]);
                Text(formatSpeed(this.downloadSpeed))
                  .fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
              }
            }
            .alignItems(VerticalAlign.Center);
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
              () => { this.onOrientationChange(!this.landscape); }
            );
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Center);
        }.width('100%').alignItems(VerticalAlign.Center);
        Row({ space: 8 }) {
          Text(formatMs(this.dragging ? this.dragValueMs : this.currentTimeMs))
            .fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
          Stack() {
            Row().width('100%').height(4).borderRadius(2).backgroundColor(CONTROL_TRACK_SOFT);
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
          Text(formatMs(this.durationMs))
            .fontSize(11).fontColor(CONTROL_TEXT_SOFT).fontWeight(FontWeight.Medium);
        }.width('100%').alignItems(VerticalAlign.Center);
      }
      .margin({ left: 12, right: 12, bottom: Math.max(14, this.bottomSafe + 8) })
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .backgroundColor(overlayGlassFill('viewer', CONTROL_BAR_BG))
      .backdropBlur(overlayBackdropBlur('viewer'))
      .attributeModifier(materialModifier('viewer'))
      .borderRadius(18)
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 10 }))
        .animation({ duration: 180, curve: Curve.EaseOut }));
    }
    .width('100%')
    .height('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }));
  }

  build() {
    Stack() {
      if (this.posterPath !== '') {
        Image(this.posterSrc()).draggable(false)
          .width(this.surfaceWidth())
          .height(this.surfaceHeight())
          .objectFit(ImageFit.Contain)
          .opacity(this.hasError ? 0.54 : (this.liveMode ? 1 : 0.88));
      }
      // AVPlayer 版没有 libraryname（那是 ijk 的 NAPI 入口），画面靠
      // surfaceId 绑定；也**没有 rotate()**，旋转由 AVPlayer 自己按 display
      // matrix 做掉了，再转一次就是转两次。
      XComponent({
        id: this.componentId(),
        type: XComponentType.SURFACE,
        controller: this.xController
      })
        .opacity(this.videoVisible ? 1 : 0)
        .animation({ duration: 180, curve: Curve.EaseOut })
        // 恒等于视口，不再跟着视频比例变（见 onStateChange 里 videoScaleType 那段）。
        .width('100%')
        .height('100%')
        .onLoad((): void => {
          this.surfaceId = this.xController.getXComponentSurfaceId();
          this.initPlayer();
        })
        .onDestroy((): void => {
          this.release();
          this.surfaceId = '';
        });
      this.seekFeedback();
      if (!this.embedded && !this.showControls) {
        Row() {
          this.tapZone(false);
          this.tapZone(true);
        }
        .width('100%')
        .height('100%');
      }
      if (shouldShowPlayerStatus(this.status, this.hasError, this.statusVisible, this.isPrepared)) {
        this.statusCard();
      }
      if (this.hasError && !this.embedded) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(30).fontColor([Color.White]);
          Text($r('app.string.player_playback_failed'))
            .fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Medium);
          Text(this.errorDetail)
            .fontSize(11).fontColor(CONTROL_TEXT_SOFT).maxLines(2).textAlign(TextAlign.Center);
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([Color.White]);
            Text($r('app.string.settings_retry'))
              .fontSize(13).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
          .height(34)
          .padding({ left: 15, right: 15 })
          .backgroundColor('#29FFFFFF')
          .borderRadius(17)
          .stateStyles({ normal: this.controlNormalStyle, pressed: this.controlPressedStyle })
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
            .fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Medium);
        }
        .height(38)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#78000000')
        .borderRadius(19)
        .hitTestBehavior(HitTestMode.None);
      }
      if (this.isCompleted && !this.liveMode) {
        Stack() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(25).fontColor([Color.White]);
            Text($r('app.string.player_replay'))
              .fontSize(18).fontColor(Color.White).fontWeight(FontWeight.Medium);
          }
          .padding({ left: 20, right: 20, top: 14, bottom: 14 })
          .backgroundColor(CONTROL_BAR_BG)
          .borderRadius(20);
        }
        .constraintSize({ minWidth: 140, minHeight: 64 })
        .stateStyles({ normal: this.controlNormalStyle, pressed: this.controlPressedStyle })
        .animation({ duration: 120, curve: Curve.EaseOut })
        .onClick(() => { this.replay(); });
      }
      if (!this.embedded && this.showControls && !this.hasError) {
        this.controlBar();
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
