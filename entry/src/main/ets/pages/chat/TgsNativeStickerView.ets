import { image } from '@kit.ImageKit';
import { StickerPoster } from '../common/StickerPoster';
import {
  queueTgsOpenTicketed, queueTgsRenderTicketed, tgsClose, TgsOpenOutcome, TgsOpenResult, TgsRenderResult,
  TgsRenderTicket
} from '../../util/tgsRenderQueue';
import { AnimationSlotPool } from '../../util/animationSlotPool';
import { stickerAnimationSlots } from '../../util/stickerAnimationBudget';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { tgsPowerSuspended } from '../../util/tgsPowerGate';
import {
  tgsFinished, tgsFrameDue, tgsFrameIndexAt, tgsHighRateCategory, tgsNextDelayMs, tgsPlaybackFps,
  tgsRenderSize
} from '../../util/tgsPlayback';
import { stickerFrameClock } from '../../util/stickerFrameClock';
import { subscribeAnimationGateFor } from '../../util/stickerPanelGate';
import { logE, logW } from '../../util/log';

// 出帧节奏的一键回退开关（2026-09-17）。true = 共享 displaySync 时钟，对齐屏幕刷新；
// false = 原来的「画完一帧再 setTimeout」。真机上若出问题（比如贴纸停在缩略图不动、
// 反而更卡），改这一个常量即可回到旧路径。为什么要换，见 util/stickerFrameClock。
const TGS_USE_DISPLAY_SYNC: boolean = true;

// TGS 贴纸的原生渲染（rlottie）。UI 线程只做一件事：把 worker 上渲好的一张
// PixelMap 画进 Canvas。
//
// 【与 lottie 那支的区别，也是换掉它的理由】@ohos/lottie 的 renderer 只能是
// 'canvas'，每一帧都在 UI 线程上重算形状再画一遍。代价直接写在那个文件里：
// 会话同时只允许 4 张动（MAX_LIVE_CHAT_TGS）、面板 14 张，超出的画静态缩略图。
// 这里没有这个上限——每帧的 UI 成本只是一次 drawImage。
// 【2026-09-15 起与 WebM 共用名额】UI 线程便宜不等于没有代价：每张在动的贴纸每帧都要合成，
// 扫描采样里 GPU 六成时间满载。名额按区域分池，见 util/stickerAnimationBudget。
//
// 【为什么不整段预解码】设备实测 24/25 个 .tgs 是 60fps × 3 秒 = 180 帧，
// 按气泡尺寸 256px 算整段是 46MB 一张。Lottie 任意帧可独立渲染（不像 VP9 有
// 帧间预测），所以按需渲染 + 一两帧在手才是对的形状。
//
// 【打开的那一份要还】tgsClose 必须配对调用，否则解析后的模型一直留在 native。
@ComponentV2
export struct TgsNativeStickerView {
  @Param tgsPath: string = '';
  @Param thumbPath: string = '';
  @Param boxWidth: number = 160;
  @Param boxHeight: number = 160;
  @Param powerCategory: string = 'sticker';
  // 会话时间线里的贴纸：滚动时统一按闸门暂停（同 lottie 那支）。
  @Param chatTimeline: boolean = false;
  // 贴纸抽屉里的格子：滚动时按抽屉那道闸暂停（见 util/stickerPanelGate）。与 chatTimeline 互斥。
  @Param panelGated: boolean = false;
  @Param playOnce: boolean = false;
  @Param loop: boolean = true;
  // 原生这条路走不通（没编进来 / 文件解析失败）时通知调用方退回 lottie。
  @Param onFailed: () => void = (): void => {};

  @Local private failed: boolean = false;
  @Local private painted: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private env: ChatEnvMirror = chatEnv;

  private handle: number = 0;
  private totalFrames: number = 0;
  private sourceFps: number = 60;
  private startedAt: number = 0;
  private timer: number = -1;
  // 共享出帧时钟的退订函数（TGS_USE_DISPLAY_SYNC 时取代 timer）。
  private unsubClock: (() => void) | null = null;
  // 上一次要帧对应的上屏时刻（时钟的时间基，毫秒）与最近一次画出的帧号。
  private lastRequestMs: number = -1;
  private lastIndex: number = -1;
  private canvasReady: boolean = false;
  private visible: boolean = false;
  private chatGateSuspended: boolean = false;
  private disposed: boolean = false;
  private rendering: boolean = false;
  // 同时在动的名额（与 WebM 共用）。只在屏幕上、要开始要帧时才取，滑出屏幕立刻还。
  private holdsSlot: boolean = false;
  private cancelSlotWait: (() => void) | null = null;
  // 在队列里排着的渲染/打开请求的票：停泵、换贴纸、下树时作废，轮到时直接跳过。
  private renderTicket: TgsRenderTicket | null = null;
  private openTicket: TgsRenderTicket | null = null;
  // 换路径/销毁时作废在途的异步渲染——它回来得比下一次打开晚，会把新贴纸盖掉。
  private seq: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    if (this.chatTimeline || this.panelGated) {
      // 第二个参数让闸门排开闸先后：屏幕上的先放（见 util/chatAnimationGate）。
      this.unsubGate = subscribeAnimationGateFor(this.panelGated, (suspended: boolean): void => {
        this.chatGateSuspended = suspended;
        if (suspended) {
          this.stopPump();     // 定格在当前帧，不清画布
        } else {
          this.maybeStart();
        }
      }, (): boolean => this.visible);
    }
    this.open();
  }

  private unsubGate: (() => void) | null = null;

  aboutToDisappear(): void {
    this.disposed = true;
    this.visible = false;
    this.stopPump();
    this.cancelOpen();
    this.releaseSlot();
    this.close();
    if (this.unsubGate !== null) {
      this.unsubGate();
      this.unsubGate = null;
    }
  }

  @Monitor('tgsPath')
  onPathChanged(): void {
    this.resetForNewSource();
  }

  // 【行复用必须接住，否则贴纸串台】这个组件挂在 @ReusableV2 的消息行里。复用时
  // @Param 已经换成新贴纸，但重置期间 @Monitor('tgsPath') 是静默的：旧 handle 不关、
  // open() 看到 handle≠0 直接返回，pump 继续画上一张；@Local painted 却被重置成
  // false，新缩略图又垫在旧画面底下——就是「残留上个贴纸内容、并且叠加」
  // （用户 2026-09-14）。webm 那几支（SmartLoopVideo/WebmStickerView/
  // AlphaWebmStickerView）早就挂了这对钩子，这支是 09-14 管线重做时漏的。
  //
  // 回收时就关：进了复用池的行不该还攥着 native 模型、还在渲帧。
  // **visible 不动**：滚动时回收和复用常在同一帧里发生，节点摘下又挂上、中间没有
  // 一次可见性结算，框架不会再报一次 true（只有节点销毁才强制报消失）——手动置
  // false 会让复用后的贴纸一直停在缩略图上。
  aboutToRecycle(): void {
    this.seq++;
    this.stopPump();
    this.cancelOpen();
    this.releaseSlot();
    this.close();
    this.clearCanvas();
    this.startedAt = 0;
    this.lastRequestMs = -1;
    this.lastIndex = -1;
  }

  aboutToReuse(): void {
    this.resetForNewSource();
  }

  private resetForNewSource(): void {
    this.seq++;
    this.stopPump();
    this.cancelOpen();
    this.releaseSlot();
    this.close();
    this.clearCanvas();
    // 新贴纸从第 0 帧起播，不接着上一张的进度。
    this.startedAt = 0;
    this.lastRequestMs = -1;
    this.lastIndex = -1;
    this.painted = false;
    this.failed = false;
    this.open();
  }

  private slotPool(): AnimationSlotPool {
    return stickerAnimationSlots(this.chatTimeline, this.panelGated);
  }

  private releaseSlot(): void {
    if (this.cancelSlotWait !== null) {
      this.cancelSlotWait();
      this.cancelSlotWait = null;
    }
    if (this.holdsSlot) {
      this.holdsSlot = false;
      this.slotPool().release();
    }
  }

  // 名额满了：停在缩略图/当前帧，排队；名额转过来时直接起泵。
  private waitForSlot(): void {
    this.cancelSlotWait = this.slotPool().wait((): void => {
      this.cancelSlotWait = null;
      if (this.disposed || !this.visible) {
        this.slotPool().release();
        return;
      }
      this.holdsSlot = true;
      this.maybeStart();
    });
  }

  private currentRenderTicket(): TgsRenderTicket {
    if (this.renderTicket === null) {
      this.renderTicket = new TgsRenderTicket();
    }
    return this.renderTicket;
  }

  private cancelOpen(): void {
    if (this.openTicket !== null) {
      this.openTicket.cancelled = true;
      this.openTicket = null;
    }
  }

  private clearCanvas(): void {
    try {
      this.ctx.clearRect(0, 0, this.boxWidth, this.boxHeight);
    } catch (e) {
      logE(`TgsNativeStickerView clear failed: ${e}`);
    }
  }

  @Monitor('env.powerSaving', 'env.stickers', 'env.animatedEmoji', 'env.stickerAutoplay',
    'env.emojiChat', 'env.emojiReactions', 'env.emojiStatus', 'env.reduceAnim')
  onPowerChanged(): void {
    if (this.suspended()) {
      this.stopPump();
      if (tgsPowerSuspended(this.env, this.powerCategory)) {
        this.releaseSlot();   // 省电停播：名额还掉（滑动闸只是暂停，名额留着）
      }
    } else {
      this.maybeStart();
    }
  }

  private suspended(): boolean {
    return tgsPowerSuspended(this.env, this.powerCategory)
      || ((this.chatTimeline || this.panelGated) && this.chatGateSuspended);
  }

  private open(): void {
    if (this.tgsPath === '' || this.handle !== 0) {
      return;
    }
    // vp2px(1) 就是当前屏幕密度；chatEnv 里没有这一项，也不必为它加一项。
    const size: number = tgsRenderSize(Math.max(this.boxWidth, this.boxHeight), vp2px(1));
    const token: number = this.seq;
    const ticket: TgsRenderTicket = new TgsRenderTicket();
    this.openTicket = ticket;
    queueTgsOpenTicketed(this.tgsPath, size, size, ticket).then((outcome: TgsOpenOutcome): void => {
      const info: TgsOpenResult | null = outcome.info;
      if (this.disposed || token !== this.seq) {
        // 已经换了路径/下了树：这个 handle 没人要了，立刻还回去。
        if (info !== null) {
          tgsClose(info.handle);
        }
        return;
      }
      if (outcome.skipped) {
        return;   // 排队期间被作废（换贴纸/下树），不是解析失败
      }
      if (info === null || info.totalFrames <= 0) {
        this.failed = true;
        this.onFailed();
        return;
      }
      this.handle = info.handle;
      this.totalFrames = info.totalFrames;
      this.sourceFps = info.frameRate > 0 ? info.frameRate : 60;
      this.maybeStart();
    }).catch((e: Error): void => {
      if (this.disposed || token !== this.seq) {
        return;   // 换过贴纸：旧的那次失败与新贴纸无关，别让它触发回退
      }
      logE(`TgsNativeStickerView open failed: ${e.message}`);
      this.failed = true;
      this.onFailed();
    });
  }

  private close(): void {
    if (this.handle !== 0) {
      tgsClose(this.handle);
      this.handle = 0;
      this.totalFrames = 0;
    }
  }

  private maybeStart(): void {
    // `rendering` 也要拦：一帧在途时 timer 是 -1，光看 timer 会让每一次闸门
    // 变化（滚动中很频繁）都再叫起一个 pump，请求速率成倍往上翻。
    if (this.disposed || this.handle === 0 || !this.canvasReady || !this.visible
      || this.suspended() || this.timer !== -1 || this.unsubClock !== null || this.rendering) {
      return;
    }
    if (!this.holdsSlot) {
      if (this.cancelSlotWait !== null) {
        return;   // 已经在排队
      }
      if (!this.slotPool().tryAcquire()) {
        this.waitForSlot();
        return;
      }
      this.holdsSlot = true;
    }
    if (TGS_USE_DISPLAY_SYNC) {
      this.startClock();
      return;
    }
    if (this.startedAt === 0) {
      this.startedAt = Date.now();
    }
    this.pump();
  }

  // 挂到共享时钟上。帧率在起播时定：大表情最高 60，其余 30，省电 15。
  private startClock(): void {
    const fps: number = tgsPlaybackFps(this.sourceFps, this.env.powerSaving,
      tgsHighRateCategory(this.powerCategory));
    this.lastRequestMs = -1;
    this.unsubClock = stickerFrameClock.subscribe(this.getUIContext(), fps,
      (timestampMs: number, targetMs: number): void => {
        this.onClockFrame(timestampMs, targetMs, fps);
      });
  }

  // 时钟的一拍。与 pump 同一套判据，差别只在时刻：起点和帧号都用时钟给的时间，
  // 帧号按**下一帧上屏的时刻**（targetMs）算，渲好正好赶上那一帧。
  private onClockFrame(timestampMs: number, targetMs: number, fps: number): void {
    if (this.disposed || this.failed || this.handle === 0 || this.suspended() || !this.visible
      || !this.holdsSlot) {
      this.stopPump();
      return;
    }
    if (this.rendering) {
      return;   // 上一帧还没回来（设备忙）：跳过这一拍，不排队堆积
    }
    if (this.startedAt === 0) {
      this.startedAt = timestampMs;
    }
    if (!tgsFrameDue(this.lastRequestMs, targetMs, fps)) {
      return;
    }
    const elapsed: number = targetMs - this.startedAt;
    const looping: boolean = this.loop && !this.playOnce;
    if (!looping && tgsFinished(elapsed, this.sourceFps, this.totalFrames)) {
      this.stopPump();
      this.releaseSlot();
      return;   // 定格在最后一帧
    }
    const index: number = tgsFrameIndexAt(elapsed, this.sourceFps, this.totalFrames, looping);
    this.lastRequestMs = targetMs;
    if (index === this.lastIndex) {
      return;   // 源帧还没前进（源帧率低于时钟），不重复渲同一帧
    }
    this.renderFrame(index);
  }

  private stopPump(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    if (this.unsubClock !== null) {
      this.unsubClock();
      this.unsubClock = null;
    }
    // 排着队还没轮到的那一帧作废；已经在渲的回来后照常处理。
    if (this.renderTicket !== null) {
      this.renderTicket.cancelled = true;
      this.renderTicket = null;
    }
  }

  // 一拍：算此刻该是第几帧 → 让 worker 渲出来 → 画上去 → 约下一拍。
  //
  // 帧号按**源帧率**从起播时刻算（见 util/tgsPlayback），所以即使我们只按
  // 30fps 去要帧，3 秒的贴纸也还是 3 秒走完——按播放帧率累加会让它慢一倍。
  private pump(): void {
    this.timer = -1;
    if (this.disposed || this.handle === 0 || this.suspended() || !this.visible || !this.holdsSlot) {
      return;
    }
    if (this.rendering) {
      // 上一帧还没回来（设备忙）：跳过这一拍，不排队堆积。
      this.timer = setTimeout((): void => { this.pump(); },
        tgsNextDelayMs(tgsPlaybackFps(this.sourceFps, this.env.powerSaving)));
      return;
    }
    const elapsed: number = Date.now() - this.startedAt;
    const looping: boolean = this.loop && !this.playOnce;
    if (!looping && tgsFinished(elapsed, this.sourceFps, this.totalFrames)) {
      this.releaseSlot();
      return;   // 定格在最后一帧
    }
    const index: number = tgsFrameIndexAt(elapsed, this.sourceFps, this.totalFrames, looping);
    this.renderFrame(index);
  }

  // 要一帧并画上。pump（定时器）和 onClockFrame（共享时钟）共用。
  private renderFrame(index: number): void {
    const token: number = this.seq;
    this.rendering = true;
    queueTgsRenderTicketed(this.handle, index, this.currentRenderTicket()).then((result: TgsRenderResult): void => {
      this.rendering = false;
      const frame: image.PixelMap | null = result.frame;
      if (this.disposed || token !== this.seq) {
        if (frame !== null) {
          frame.release();
        }
        // 这一帧在途时换了贴纸：新 handle 可能已经开好、却被 rendering 拦在
        // maybeStart 外面——补叫一次，否则新贴纸停在缩略图上不动。
        this.maybeStart();
        return;
      }
      if (result.skipped) {
        // 排队期间被作废（停泵/滑出屏幕）：不是渲染失败。条件恢复时再叫起。
        this.maybeStart();
        return;
      }
      if (frame === null) {
        logW('TgsNativeStickerView: render returned null');
        this.failed = true;
        this.onFailed();
        return;
      }
      this.draw(frame);
      this.lastIndex = index;
      if (TGS_USE_DISPLAY_SYNC) {
        // 时钟模式下不用约下一拍，时钟自己会跳。但若这一帧在途时被暂停又恢复（滚动闸门
        // 很频繁），恢复时的 maybeStart 被 rendering 挡了回去、又没人再订阅时钟——
        // 贴纸就会永远停在这一帧。这里补叫一次；它是幂等的，已订阅时直接返回。
        this.maybeStart();
        return;
      }
      if (!this.suspended() && this.visible && this.holdsSlot) {
        this.timer = setTimeout((): void => { this.pump(); },
          tgsNextDelayMs(tgsPlaybackFps(this.sourceFps, this.env.powerSaving)));
      }
    }).catch((e: Error): void => {
      this.rendering = false;
      if (this.disposed || token !== this.seq) {
        this.maybeStart();
        return;
      }
      logE(`TgsNativeStickerView render failed: ${e.message}`);
      this.failed = true;
      this.onFailed();
    });
  }

  // 画完就把这张还掉：每帧都是一张新的 PixelMap，不还就是每秒几 MB 的原生内存。
  private draw(frame: image.PixelMap): void {
    try {
      this.ctx.clearRect(0, 0, this.boxWidth, this.boxHeight);
      this.ctx.drawImage(frame, 0, 0, this.boxWidth, this.boxHeight);
      this.painted = true;
    } catch (e) {
      logE(`TgsNativeStickerView draw failed: ${e}`);
    }
    frame.release();
  }

  build() {
    Stack() {
      // 第一帧画出来之前先顶着缩略图，避免一块空白。
      if (!this.painted && this.thumbPath !== '') {
        StickerPoster({ path: this.thumbPath, boxWidth: this.boxWidth, boxHeight: this.boxHeight });
      }
      Canvas(this.ctx)
        .width(this.boxWidth).height(this.boxHeight)
        .onReady((): void => {
          this.canvasReady = true;
          this.maybeStart();
        });
    }
    .width(this.boxWidth).height(this.boxHeight)
    .onVisibleAreaChange([0.01], (isVisible: boolean, ratio: number): void => {
      const next: boolean = isVisible && ratio > 0;
      if (this.visible === next) {
        return;
      }
      this.visible = next;
      if (next) {
        this.maybeStart();
      } else {
        this.stopPump();
        this.releaseSlot();   // 滑出屏幕立刻还名额
      }
    });
  }
}
