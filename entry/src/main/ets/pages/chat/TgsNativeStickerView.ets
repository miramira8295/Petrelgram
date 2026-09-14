import { image } from '@kit.ImageKit';
import {
  queueTgsOpen, queueTgsRender, tgsClose, TgsOpenResult
} from '../../util/tgsRenderQueue';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { tgsPowerSuspended } from '../../util/tgsPowerGate';
import {
  tgsFinished, tgsFrameIndexAt, tgsNextDelayMs, tgsPlaybackFps, tgsRenderSize
} from '../../util/tgsPlayback';
import { subscribeChatAnimationGate } from '../../util/chatAnimationGate';
import { logE, logW } from '../../util/log';

// TGS 贴纸的原生渲染（rlottie）。UI 线程只做一件事：把 worker 上渲好的一张
// PixelMap 画进 Canvas。
//
// 【与 lottie 那支的区别，也是换掉它的理由】@ohos/lottie 的 renderer 只能是
// 'canvas'，每一帧都在 UI 线程上重算形状再画一遍。代价直接写在那个文件里：
// 会话同时只允许 4 张动（MAX_LIVE_CHAT_TGS）、面板 14 张，超出的画静态缩略图。
// 这里没有这个上限——每帧的 UI 成本只是一次 drawImage。
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
  private canvasReady: boolean = false;
  private visible: boolean = false;
  private chatGateSuspended: boolean = false;
  private disposed: boolean = false;
  private rendering: boolean = false;
  // 换路径/销毁时作废在途的异步渲染——它回来得比下一次打开晚，会把新贴纸盖掉。
  private seq: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    if (this.chatTimeline) {
      this.unsubGate = subscribeChatAnimationGate((suspended: boolean): void => {
        this.chatGateSuspended = suspended;
        if (suspended) {
          this.stopPump();     // 定格在当前帧，不清画布
        } else {
          this.maybeStart();
        }
      });
    }
    this.open();
  }

  private unsubGate: (() => void) | null = null;

  aboutToDisappear(): void {
    this.disposed = true;
    this.visible = false;
    this.stopPump();
    this.close();
    if (this.unsubGate !== null) {
      this.unsubGate();
      this.unsubGate = null;
    }
  }

  @Monitor('tgsPath')
  onPathChanged(): void {
    this.seq++;
    this.stopPump();
    this.close();
    this.painted = false;
    this.failed = false;
    this.open();
  }

  @Monitor('env.powerSaving', 'env.stickers', 'env.animatedEmoji', 'env.stickerAutoplay',
    'env.emojiChat', 'env.emojiReactions', 'env.emojiStatus', 'env.reduceAnim')
  onPowerChanged(): void {
    if (this.suspended()) {
      this.stopPump();
    } else {
      this.maybeStart();
    }
  }

  private suspended(): boolean {
    return tgsPowerSuspended(this.env, this.powerCategory)
      || (this.chatTimeline && this.chatGateSuspended);
  }

  private open(): void {
    if (this.tgsPath === '' || this.handle !== 0) {
      return;
    }
    // vp2px(1) 就是当前屏幕密度；chatEnv 里没有这一项，也不必为它加一项。
    const size: number = tgsRenderSize(Math.max(this.boxWidth, this.boxHeight), vp2px(1));
    const token: number = this.seq;
    queueTgsOpen(this.tgsPath, size, size).then((info: TgsOpenResult | null): void => {
      if (this.disposed || token !== this.seq) {
        // 已经换了路径/下了树：这个 handle 没人要了，立刻还回去。
        if (info !== null) {
          tgsClose(info.handle);
        }
        return;
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
      || this.suspended() || this.timer !== -1 || this.rendering) {
      return;
    }
    if (this.startedAt === 0) {
      this.startedAt = Date.now();
    }
    this.pump();
  }

  private stopPump(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  // 一拍：算此刻该是第几帧 → 让 worker 渲出来 → 画上去 → 约下一拍。
  //
  // 帧号按**源帧率**从起播时刻算（见 util/tgsPlayback），所以即使我们只按
  // 30fps 去要帧，3 秒的贴纸也还是 3 秒走完——按播放帧率累加会让它慢一倍。
  private pump(): void {
    this.timer = -1;
    if (this.disposed || this.handle === 0 || this.suspended() || !this.visible) {
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
      return;   // 定格在最后一帧
    }
    const index: number = tgsFrameIndexAt(elapsed, this.sourceFps, this.totalFrames, looping);
    const token: number = this.seq;
    this.rendering = true;
    queueTgsRender(this.handle, index).then((frame: image.PixelMap | null): void => {
      this.rendering = false;
      if (this.disposed || token !== this.seq) {
        if (frame !== null) {
          frame.release();
        }
        return;
      }
      if (frame === null) {
        logW('TgsNativeStickerView: render returned null');
        this.failed = true;
        this.onFailed();
        return;
      }
      this.draw(frame);
      if (!this.suspended() && this.visible) {
        this.timer = setTimeout((): void => { this.pump(); },
          tgsNextDelayMs(tgsPlaybackFps(this.sourceFps, this.env.powerSaving)));
      }
    }).catch((e: Error): void => {
      this.rendering = false;
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
        Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath)
          .draggable(false)
          .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
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
      }
    });
  }
}
