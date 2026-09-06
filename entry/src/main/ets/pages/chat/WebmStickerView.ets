import { IjkMediaPlayer, OnPreparedListener, OnErrorListener, OnCompletionListener } from '@ohos/ijkplayer';
import { AlphaWebmStickerView } from '../common/AlphaWebmStickerView';
import { alphaStickerPipelineAvailable } from '../../services/AlphaStickerStore';
import { alphaStickerCandidate } from '../../util/webm/alphaStickerGate';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { probeHit } from '../../util/panelProbe';
import { logE, logW } from '../../util/log';

let nextWebmStickerId: number = 1;
// Pre-EOF rewind: poll the position and seek to 0 this far before the end.
//
// 【2026-09-06：这两个常量本身就是"贴纸没播完就从头 / 看着变快"的根因】
// 原值 poll=50 / ahead=100：轮询粒度叠在提前量上，**每一圈最坏丢 150ms**。
// Telegram 视频贴纸多在 1~2 秒，那是 5%~15%，而且砍掉的正是结尾的收势动作。
// 上一版注释自己就写着「a large value visibly "speeds up" short stickers」,
// 只是没意识到 100 对 1 秒的贴纸**已经是那个 large value**。
//
// 现在提前量按时长自适应（见 rewindAheadMs），常量只留边界：
//   · 下界 16ms —— 一帧，再小就等于不提前，EOF 卡顿会回来；
//   · 上界 40ms —— 1 秒贴纸也只丢 4%，肉眼基本看不出。
// 轮询降到 16ms 是为了让粒度不再主导误差（原来 50ms 粒度比提前量的一半还大）。
// 唤醒的下界：算出来的剩余时间再短也不至于忙等。
const LOOP_MIN_SLEEP_MS: number = 32;
// 位置没推进（暂停、缓冲、被系统降频）时的退避间隔。
const LOOP_STALL_SLEEP_MS: number = 250;
const LOOP_REWIND_MIN_MS: number = 16;
const LOOP_REWIND_MAX_MS: number = 40;
// 时长的百分之二：短贴纸拿下界，长贴纸也不会超过上界。
const LOOP_REWIND_RATIO: number = 0.02;

// Native player setup/teardown scheduler. A sticker-grid tab switch destroys
// and creates ~15 ijkplayer instances at once; each native_setup/release is
// main-thread heavy, so running them inline freezes the UI for seconds.
// Two queues: releases run FIRST (a few per tick, so rapid tab switching
// can't pile up zombie players), inits run one per tick only once every
// pending release has been processed.
type PlayerJob = () => void;
const releaseJobs: PlayerJob[] = [];
const initJobs: PlayerJob[] = [];
let playerJobTimer: number = -1;
const PLAYER_JOB_INTERVAL_MS: number = 30;
const RELEASES_PER_TICK: number = 3;
let livePlayers: number = 0;

function runJob(job: PlayerJob): void {
  try {
    job();
  } catch (e) {
    logE(`WebmStickerView player job failed: ${e}`);
  }
}

// 释放队列的"闸门"。系统输入法要弹出时先摁住：一次关面板会排进一屏
// （实测 29 个）ijk 播放器的销毁，每个几十毫秒，主线程被占满，键盘的第一次
// 布局排不进去——实测从手指抬起到键盘出现 1859ms，输入框先落下、快两秒后
// 又被顶上去，就是这两跳。
//
// 摁住不减少总工作量，只是把它挪到键盘落定之后。那时用户正在看键盘，
// 几百毫秒的零碎销毁看不出来。
let jobsHeldUntil: number = 0;

export function holdPlayerJobs(ms: number): void {
  const until: number = Date.now() + ms;
  if (until > jobsHeldUntil) {
    jobsHeldUntil = until;
  }
}

function pumpPlayerJobs(): void {
  if (playerJobTimer !== -1) {
    return;
  }
  playerJobTimer = setInterval(() => {
    if (Date.now() < jobsHeldUntil) {
      // 闸门关着：这一拍什么都不做，但定时器留着，开闸后自然继续。
      return;
    }
    if (releaseJobs.length > 0) {
      // Drain teardowns first — they free native resources.
      for (let i = 0; i < RELEASES_PER_TICK; i++) {
        const r = releaseJobs.shift();
        if (r === undefined) {
          break;
        }
        runJob(r);
      }
    } else {
      const init = initJobs.shift();
      if (init !== undefined) {
        runJob(init);
      }
    }
    if (releaseJobs.length === 0 && initJobs.length === 0) {
      clearInterval(playerJobTimer);
      playerJobTimer = -1;
    }
  }, PLAYER_JOB_INTERVAL_MS);
}

function enqueueRelease(job: PlayerJob): void {
  releaseJobs.push(job);
  pumpPlayerJobs();
}

function enqueueInit(job: PlayerJob): void {
  initJobs.push(job);
  pumpPlayerJobs();
}

// Loops a Telegram WEBM (VP9) video sticker inline, muted, via ijkplayer on a
// TEXTURE XComponent (composites within ArkUI, unlike SURFACE). Falls back to
// the raster thumbnail if playback fails.
//
// 真带透明通道的贴纸走 AlphaWebmStickerView（自解封装 + 系统 VP9 + 自绘），
// 那条路走不通时原样退回下面的 ijk 播放器——所有调用点都经过这里，所以判定
// 只在这一个地方做。
// P4 批 6b：迁 @ComponentV2（配方同批 1~6a）。11 个省电键走 chatEnv 镜像；
// 复用同步化（@Param 已是新值，V1 写回 @Prop 的做法退役）。
@ComponentV2
export struct WebmStickerView {
  @Param webmPath: string = '';
  @Param thumbPath: string = '';
  @Param boxWidth: number = 160;
  @Param boxHeight: number = 160;
  @Param powerCategory: string = 'sticker';
  @Param forcePlay: boolean = false;
  private env: ChatEnvMirror = chatEnv;
  @Param onWorking: () => void = (): void => {};
  @Param onFailed: () => void = (): void => {};
  @Local failed: boolean = false;
  // 先试自解码链路；它自己会读文件头判断有没有 alpha，判不出来就把这面旗降下
  // 来，退回 ijk。**不再看设备 API 版本**——解码器是随包自带的 libvpx，唯一的
  // 运行期条件是原生模块加载成功。
  @Local useAlpha: boolean = false;
  private player: IjkMediaPlayer | null = null;
  private readonly instanceId: number = nextWebmStickerId++;
  private loopTimer: number = -1;
  // 上一次醒来时读到的播放位置，用来判断"位置有没有推进"（见 armLoopWatch）。
  // -1 表示本轮还没读过。
  private lastLoopPos: number = -1;
  private durationMs: number = 0;
  // 本片源的提前回卷量，拿到 duration 之后算一次（见上方常量的说明）。
  private rewindAheadMs: number = LOOP_REWIND_MAX_MS;
  private surfaceContext: object | null = null;

  private componentId(): string {
    return `webm_sticker_${this.instanceId}`;
  }

  aboutToAppear(): void {
    probeHit('webm.mount');
    this.useAlpha = alphaStickerCandidate(this.powerCategory) && alphaStickerPipelineAvailable();
    console.warn(`[AlphaDiag] gate cat=${this.powerCategory}` +
      ` candidate=${alphaStickerCandidate(this.powerCategory)} useAlpha=${this.useAlpha}`);
  }

  aboutToDisappear(): void {
    probeHit('webm.unmount');
    this.release();
  }

  aboutToRecycle(): void {
    this.release();
    this.failed = false;
  }

  aboutToReuse(): void {
    // @Param 已是新值（批 0.5 判读）：V1 时代写回 @Prop 的整段退役。
    this.destroyed = false;
    this.failed = false;
    this.durationMs = 0;
    this.useAlpha = alphaStickerCandidate(this.powerCategory) && alphaStickerPipelineAvailable();
    if (this.surfaceContext !== null && !this.useAlpha) {
      const context: object = this.surfaceContext;
      enqueueInit((): void => {
        if (!this.destroyed && this.initPlayer(context)) {
          livePlayers++;
        }
      });
    }
  }

  // Seamless loop: jump back to 0 shortly BEFORE the end, so playback never
  // hits EOF — ijk's own loop path (EOF → buffering state → seek) visibly
  // hitches even with packet-buffering disabled.
  //
  // 【2026-09-06：从"定时轮询"改成"算准了到点再醒"】
  // 上一版是 setInterval(16ms)，也就是每个可见的 webm 播放器**每秒 60 次**
  // 跨 NAPI 调 getCurrentPosition()。贴纸抽屉一屏十几个，就是每秒近千次跨语言
  // 调用，而其中 99% 的答案是"还没到，接着等"——纯粹的空转，前台耗电与发热
  // 的一份贡献。
  //
  // 现在改成自续的 setTimeout：读一次位置，算出**离回卷点还有多久**，睡那么久
  // 再醒。1.5 秒的贴纸每圈从约 94 次轮询降到 1~2 次。
  //
  // 【为什么醒来还要再读一次位置，而不是直接 seek】
  // 睡眠时长是按"1 倍速正常播放"推的，而现实里会偏：缓冲、系统降频、
  // 用户滚动导致的 pause、seek。所以醒来先核对——没到就按剩余时间重排，
  // 到了才 seek。这条自校正让预测出错时只是多睡一觉，不会砍错位置。
  //
  // 【位置不推进时退避】暂停/缓冲时剩余时间恒定不变，若仍按剩余时间重排会
  // 变成固定频率的空转。检测到位置没动就退到 LOOP_STALL_SLEEP_MS，
  // 播放恢复后第一次醒来就会回到正常节奏。
  private startLoopWatch(): void {
    this.stopLoopWatch();
    if (!this.loopEnabled()) {
      return;
    }
    this.lastLoopPos = -1;
    this.armLoopWatch();
  }

  private armLoopWatch(): void {
    const p = this.player;
    if (p === null || this.destroyed || this.durationMs <= 0 || !this.loopEnabled()) {
      return;
    }
    let pos: number = 0;
    try {
      pos = p.getCurrentPosition();
    } catch (e) {
      logE(`WebmStickerView loop watch failed: ${e}`);
      return;
    }
    const target: number = this.durationMs - this.rewindAheadMs;
    let sleep: number;
    if (pos >= target) {
      try {
        p.seekTo('0');
      } catch (e) {
        logE(`WebmStickerView loop rewind failed: ${e}`);
        return;
      }
      // 刚回到 0，下一次回卷点就是一整圈之后。
      sleep = target;
      this.lastLoopPos = 0;
    } else if (this.lastLoopPos >= 0 && pos <= this.lastLoopPos) {
      // 位置没推进：暂停、缓冲、或被系统降频。退避，别空转。
      sleep = LOOP_STALL_SLEEP_MS;
      this.lastLoopPos = pos;
    } else {
      sleep = target - pos;
      this.lastLoopPos = pos;
    }
    this.loopTimer = setTimeout((): void => {
      this.loopTimer = -1;
      this.armLoopWatch();
    }, Math.max(LOOP_MIN_SLEEP_MS, Math.round(sleep)));
  }

  private stopLoopWatch(): void {
    if (this.loopTimer !== -1) {
      clearTimeout(this.loopTimer);
      this.loopTimer = -1;
    }
  }

  private destroyed: boolean = false;

  private release(): void {
    this.destroyed = true;
    this.stopLoopWatch();
    if (this.player !== null) {
      const p = this.player;
      this.player = null;
      // Deferred: releasing inline (e.g. a whole grid page unmounting on a
      // tab switch) serializes many native teardowns into one frame.
      enqueueRelease(() => {
        p.release();
        livePlayers--;
      });
    }
  }

  private initPlayer(context: object): boolean {
    if (this.destroyed || this.player !== null || this.webmPath === '' || this.powerSuspended()) {
      return false;
    }
    try {
      const componentId = this.componentId();
      const player = new IjkMediaPlayer(componentId);
      this.player = player;
      player.setContext(context, componentId);
      player.native_setup();
      const preparedListener: OnPreparedListener = {
        onPrepared: (): void => {
          if (this.player !== player) {
            return;
          }
          player.setVolume('0', '0'); // stickers are always silent
          player.setLoopCount(this.loopEnabled());  // safety net if the pre-EOF rewind misses
          player.start();
          this.onWorking();
          this.durationMs = Math.max(0, player.getDuration());
          // 提前量按本片源时长定：短贴纸丢得少，长贴纸也够躲开 EOF 卡顿。
          this.rewindAheadMs = this.durationMs > 0
            ? Math.min(LOOP_REWIND_MAX_MS,
              Math.max(LOOP_REWIND_MIN_MS, Math.round(this.durationMs * LOOP_REWIND_RATIO)))
            : LOOP_REWIND_MAX_MS;
          this.startLoopWatch();
        }
      };
      // EOF safety net: if the pre-EOF rewind misses (longer MP4 avatar
      // loops report duration less precisely than webm stickers), restart
      // playback instead of stopping after one pass.
      const completionListener: OnCompletionListener = {
        onCompletion: (): void => {
          if (this.player !== player || this.destroyed || !this.loopEnabled()) {
            return;
          }
          try {
            player.seekTo('0');
            player.start();
          } catch (e) {
            logE(`WebmStickerView loop restart failed: ${e}`);
          }
        }
      };
      player.setOnCompletionListener(completionListener);
      const errorListener: OnErrorListener = {
        onError: (what: number, extra: number): void => {
          logE(`WebmStickerView error: what=${what}, extra=${extra}`);
          this.failed = true;
          this.onFailed();
        }
      };
      player.setOnPreparedListener(preparedListener);
      player.setOnErrorListener(errorListener);
      player.setMessageListener();
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'start-on-prepared', '0');
      // Loop-seam smoothing: without these, every loop restart re-enters ijk's
      // packet-buffering state and the seek back to 0 visibly hitches.
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'packet-buffering', '0');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'framedrop', '1');
      player.setOptionLong(IjkMediaPlayer.OPT_CATEGORY_PLAYER, 'enable-accurate-seek', '1');
      player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, 'fflags', 'fastseek');
      player.setDataSource(this.webmPath);
      player.prepareAsync();
      return true;
    } catch (e) {
      logE(`WebmStickerView.init failed: ${e}`);
      this.failed = true;
      this.onFailed();
      this.release();
      return false;
    }
  }

  private powerSuspended(): boolean {
    if (this.forcePlay) {
      return false;
    }
    if (this.env.powerSaving || this.env.reduceAnim) {
      return true;
    }
    if (this.powerCategory === 'emojiPicker') {
      return !this.env.animatedEmoji;
    }
    if (this.powerCategory === 'gif') {
      return !this.env.autoplayGif;
    }
    if (this.powerCategory === 'video') {
      return !this.env.autoplayVideo;
    }
    if (this.powerCategory === 'emojiStatus' || this.powerCategory === 'emoji') {
      return !this.env.animatedEmoji || !this.env.emojiStatus;
    }
    if (this.powerCategory === 'emojiReaction') {
      return !this.env.animatedEmoji || !this.env.emojiReactions;
    }
    if (this.powerCategory === 'emojiChat') {
      return !this.env.animatedEmoji || !this.env.emojiChat;
    }
    return !this.env.stickers || !this.env.stickerAutoplay;
  }

  private loopEnabled(): boolean {
    return this.powerCategory === 'sticker' ? this.env.stickerLoop : true;
  }

  build() {
    if (this.powerSuspended()) {
      if (this.thumbPath !== '') {
        Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath).draggable(false)
          .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
      } else {
        Stack().width(this.boxWidth).height(this.boxHeight);
      }
    } else if (this.failed && this.thumbPath !== '') {
      Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath).draggable(false)
        .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
    } else if (this.useAlpha) {
      AlphaWebmStickerView({
        webmPath: this.webmPath, thumbPath: this.thumbPath,
        boxWidth: this.boxWidth, boxHeight: this.boxHeight,
        powerCategory: this.powerCategory,
        forcePlay: this.forcePlay,
        onWorking: (): void => { this.onWorking(); },
        onFallback: (): void => {
          console.warn('[AlphaDiag] fallback to ijkplayer');
          this.useAlpha = false;
        }
      });
    } else {
      XComponent({ id: this.componentId(), type: XComponentType.TEXTURE, libraryname: 'ijkplayer_napi' })
        .width(this.boxWidth).height(this.boxHeight)
        .onLoad((context: object) => {
          this.surfaceContext = context;
          this.destroyed = false;
          // Deferred: a screenful of cells mounting together would otherwise
          // run all their native setups in the same frame.
          enqueueInit(() => {
            if (this.destroyed) {
              return; // cell died while queued (rapid tab switching)
            }
            if (this.initPlayer(context)) {
              livePlayers++;
              if (livePlayers > 24) {
                logW(`WebmStickerView: ${livePlayers} live players`);
              }
            }
          });
        })
        .onDestroy(() => {
          this.surfaceContext = null;
          this.release();
        });
    }
  }
}
