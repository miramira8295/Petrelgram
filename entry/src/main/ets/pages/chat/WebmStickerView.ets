import { IjkMediaPlayer, OnPreparedListener, OnErrorListener, OnCompletionListener } from '@ohos/ijkplayer';
import {
  KEY_POWER_ACTIVE, KEY_POWER_AUTOPLAY_GIF, KEY_POWER_AUTOPLAY_VIDEO, KEY_POWER_EMOJI,
  KEY_POWER_EMOJI_CHAT, KEY_POWER_EMOJI_REACTIONS, KEY_POWER_EMOJI_STATUS,
  KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY, KEY_POWER_STICKER_LOOP, KEY_REDUCE_ANIM
} from '../../store/AppSettings';
import { probeHit } from '../../util/panelProbe';
import { logE, logW } from '../../util/log';

let nextWebmStickerId: number = 1;
// Pre-EOF rewind: poll the position and seek to 0 this far before the end.
const LOOP_POLL_MS: number = 50;
// Keep this small: every loop cycle drops this much tail, so a large value
// visibly "speeds up" short stickers. 100ms is enough to dodge the EOF hitch
// (packet-buffering=0 does the heavy lifting).
const LOOP_REWIND_AHEAD_MS: number = 100;

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
@Component
export struct WebmStickerView {
  @Prop webmPath: string;
  @Prop thumbPath: string = '';
  @Prop boxWidth: number = 160;
  @Prop boxHeight: number = 160;
  @Prop powerCategory: string = 'sticker';
  @Prop forcePlay: boolean = false;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_STICKERS) stickersEnabled: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) emojiEnabled: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_GIF) autoplayGif: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  @StorageProp(KEY_POWER_STICKER_AUTOPLAY) stickerAutoplay: boolean = true;
  @StorageProp(KEY_POWER_STICKER_LOOP) stickerLoop: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_CHAT) emojiChat: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) emojiReactions: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_STATUS) emojiStatus: boolean = true;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnimations: boolean = false;
  onWorking: () => void = (): void => {};
  onFailed: () => void = (): void => {};
  @State failed: boolean = false;
  private player: IjkMediaPlayer | null = null;
  private readonly instanceId: number = nextWebmStickerId++;
  private loopTimer: number = -1;
  private durationMs: number = 0;

  private componentId(): string {
    return `webm_sticker_${this.instanceId}`;
  }

  aboutToAppear(): void {
    probeHit('webm.mount');
  }

  aboutToDisappear(): void {
    probeHit('webm.unmount');
    this.release();
  }

  // Seamless loop: jump back to 0 shortly BEFORE the end, so playback never
  // hits EOF — ijk's own loop path (EOF → buffering state → seek) visibly
  // hitches even with packet-buffering disabled.
  private startLoopWatch(): void {
    this.stopLoopWatch();
    if (!this.loopEnabled()) {
      return;
    }
    this.loopTimer = setInterval(() => {
      const p = this.player;
      if (p === null || this.durationMs <= 0) {
        return;
      }
      try {
        const pos = p.getCurrentPosition();
        if (pos >= this.durationMs - LOOP_REWIND_AHEAD_MS) {
          p.seekTo('0');
        }
      } catch (e) {
        logE(`WebmStickerView loop watch failed: ${e}`);
      }
    }, LOOP_POLL_MS);
  }

  private stopLoopWatch(): void {
    if (this.loopTimer !== -1) {
      clearInterval(this.loopTimer);
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
    if (this.powerSaving || this.reduceAnimations) {
      return true;
    }
    if (this.powerCategory === 'emojiPicker') {
      return !this.emojiEnabled;
    }
    if (this.powerCategory === 'gif') {
      return !this.autoplayGif;
    }
    if (this.powerCategory === 'video') {
      return !this.autoplayVideo;
    }
    if (this.powerCategory === 'emojiStatus' || this.powerCategory === 'emoji') {
      return !this.emojiEnabled || !this.emojiStatus;
    }
    if (this.powerCategory === 'emojiReaction') {
      return !this.emojiEnabled || !this.emojiReactions;
    }
    if (this.powerCategory === 'emojiChat') {
      return !this.emojiEnabled || !this.emojiChat;
    }
    return !this.stickersEnabled || !this.stickerAutoplay;
  }

  private loopEnabled(): boolean {
    return this.powerCategory === 'sticker' ? this.stickerLoop : true;
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
    } else {
      XComponent({ id: this.componentId(), type: XComponentType.TEXTURE, libraryname: 'ijkplayer_napi' })
        .width(this.boxWidth).height(this.boxHeight)
        .onLoad((context: object) => {
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
          this.release();
        });
    }
  }
}
