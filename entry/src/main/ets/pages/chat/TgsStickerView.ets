import lottie, { AnimationItem } from '@ohos/lottie';
import { StickerPoster } from '../common/StickerPoster';
import { gunzipTgs } from '../../util/gunzipTgs';
import { tgsPowerSuspended } from '../../util/tgsPowerGate';
import { AnimationSlotPool } from '../../util/animationSlotPool';
import { stickerAnimationSlots } from '../../util/stickerAnimationBudget';
import { subscribeAnimationGateFor } from '../../util/stickerPanelGate';
import { TgsNativeStickerView } from './TgsNativeStickerView';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { probeHit } from '../../util/panelProbe';
import { logE, logW } from '../../util/log';

// Cap on simultaneously running Lottie animations: a screenful of TGS emoji
// cells (40+) redrawing canvases every frame stutters badly. Cells over the
// cap render their static thumbnail; scrolling releases slots so fresh cells
// animate again.
// 总开关：TGS 走原生渲染（rlottie，见 TgsNativeStickerView）。
// 一键回退到下面这整套 lottie 实现——真机上万一有问题，改这一个常量即可，
// 不必回滚代码。原生那支自己失败时也会退回来（onFailed）。
export const TGS_NATIVE_ENABLED: boolean = true;

// 同时在动的名额与原生 TGS、WebM 帧序列共用，按区域分池（2026-09-15），见 util/stickerAnimationBudget。
// 原来这里是面板 14 张 / 会话 4 张的独立计数。
const TGS_FIRST_DELAY_MS: number = 120;
// 一帧只放一个进来，别让它们挤在一起。
const TGS_STAGGER_MS: number = 70;
// 下一个可以开始的时刻，全局共享——错开的是所有实例，不是单个。
let tgsNextStartAt: number = 0;


// Plays a Telegram TGS sticker (gzipped Lottie JSON) on a Canvas via
// @ohos/lottie. On any decode failure it renders the raster thumbnail instead.
// Do not mark this child @Reusable: a reusable ancestor would create a nested
// cache, while a normal ancestor cannot preserve this cache across row teardown.
// P4 批 6b：迁 @ComponentV2（配方同批 1~6a）。9 个省电键走 chatEnv 镜像，
// onPowerChanged 用 @Monitor 深层路径一次挂 9 条。它随 @ReusableV2 消息行
// 一起复用，复用钩子见 aboutToRecycle（2026-09-14 补，之前漏了会串台）。
@ComponentV2
export struct TgsStickerView {
  @Param tgsPath: string = '';
  @Param thumbPath: string = '';
  @Param boxWidth: number = 160;
  @Param boxHeight: number = 160;
  @Param powerCategory: string = 'sticker';
  // True only for a message-timeline cell. Picker/status/login animations can
  // use the same power category without inheriting ChatPage's scroll gate or
  // its tighter four-canvas budget.
  @Param chatTimeline: boolean = false;
  // 贴纸抽屉里的格子：滚动时按抽屉那道闸暂停（见 util/stickerPanelGate）。与 chatTimeline 互斥。
  @Param panelGated: boolean = false;
  // 播一次并定格在最后一帧（骰子/老虎机结果动画的官方语义），不循环。
  @Param playOnce: boolean = false;
  @Param onFailed: () => void = (): void => {};
  private env: ChatEnvMirror = chatEnv;
  @Local failed: boolean = false;
  @Local private budgetDeferred: boolean = false;
  // 原生渲染那支报了失败：本组件退回 lottie。一次性的，不再往回切。
  @Local private nativeFailed: boolean = false;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private anim: AnimationItem | null = null;
  private disposed: boolean = false;
  private holdsSlot: boolean = false;
  private canvasReady: boolean = false;
  private startTimer: number = -1;
  private visible: boolean = false;
  private chatGateSuspended: boolean = false;
  private cancelSlotWait: (() => void) | null = null;
  private unsubChatGate: (() => void) | null = null;
  // Invalidates an async gunzip/JSON load when this component receives a new
  // path. Without it, the old sticker could finish last and paint over the new
  // value.
  private loadSeq: number = 0;

  @Monitor('tgsPath')
  onTgsPathChanged(): void {
    this.loadSeq++;
    this.stopAnim();
    this.disposed = false;
    this.failed = false;
    this.budgetDeferred = false;
    if (this.canvasReady && this.visible && !this.animationSuspended()) {
      this.scheduleStart();
    }
  }

  @Monitor('env.powerSaving', 'env.stickers', 'env.animatedEmoji', 'env.stickerAutoplay',
    'env.stickerLoop', 'env.emojiChat', 'env.emojiReactions', 'env.emojiStatus', 'env.reduceAnim')
  onPowerChanged(): void {
    if (this.powerSuspended()) {
      this.loadSeq++;
      this.stopAnim();
    } else if (this.canvasReady && this.visible && !this.chatGateSuspended
      && (this.budgetDeferred || this.anim === null)) {
      // 【`budgetDeferred || anim === null` 这个守卫是补上的】
      // 这个分支的意思是"名额/闸门放开了，叫醒之前没能起来的"，而不是"重启everything"。
      // 隔壁处理滚动闸门的分支（见 aboutToAppear 里的 subscribeChatTgsGate 回调）
      // 早就带着这个守卫，注释写的是「只叫醒没在播的，正在播的别重启」——
      // 同一件事，这里当初漏了。
      //
      // 后果是实打实的：scheduleStart → startAnimation 开头无条件 stopAnim()，
      // 于是 9 个省电键任一变化都会把正在播的贴纸重新 loadAnimation、回到第 0 帧。
      // 而 applyPowerState 在每次电量变化时都会重写省电键（已在
      // util/chatEnvMirror 加了同值短路，但守卫该有还是要有——两道防线针对的是
      // 不同的失败：那边防"值没变也通知"，这里防"值真变了但不该重启在播的"）。
      this.scheduleStart();
    }
  }

  private stopAnim(keepSlot: boolean = false): void {
    this.cancelScheduledStart();
    if (!keepSlot) {
      this.releaseSlot();
    }
    if (this.anim !== null) {
      this.anim.destroy();
      this.anim = null;
    }
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

  // 名额满了：显示缩略图，排队；名额转过来时直接起播（不再靠"名额释放"的广播叫醒）。
  private waitForSlot(): void {
    if (this.cancelSlotWait !== null) {
      return;
    }
    this.cancelSlotWait = this.slotPool().wait((): void => {
      this.cancelSlotWait = null;
      if (this.disposed || !this.visible || this.animationSuspended()) {
        this.slotPool().release();
        return;
      }
      this.holdsSlot = true;
      this.budgetDeferred = false;
      this.scheduleStart();
    });
  }

  aboutToAppear(): void {
    probeHit('tgs.mount');
    this.disposed = false;
    if ((this.chatTimeline || this.panelGated) && this.unsubChatGate === null) {
      this.unsubChatGate = subscribeAnimationGateFor(this.panelGated, (suspended: boolean): void => {
        this.chatGateSuspended = suspended;
        if (suspended) {
          // 滑动期间只暂停、不销毁（issue #164）。原来走 stopAnim() → destroy()，
          // 而 lottie 的 destroy 会顺手 clearRect 把画布擦空，Canvas 又一直挂着，
          // 整段滑动里已经画出来的贴纸全变成白框，停下来还要重新 gunzip +
          // JSON.parse + loadAnimation（错峰 120ms 起）才回来。pause() 停掉
          // ticker、定格在当前帧，省下的主线程时间是一样的。名额不放：门关着时
          // 没人能起新的。还没起来的（排队中 / 正在解压）照旧作废，门开后重排。
          this.cancelScheduledStart();
          if (this.anim !== null) {
            this.anim.pause();
          } else {
            this.loadSeq++;
            this.stopAnim();
          }
        } else if (this.anim !== null) {
          // 门开：滑动前正在播的接着播；已经播完定格的（playOnce）isPaused 也是
          // true，play() 从最后一帧起走等于没动，不会重放。
          if (this.anim.isPaused && this.visible && !this.powerSuspended()) {
            this.anim.play();
          }
        } else if (this.canvasReady && this.visible && !this.powerSuspended()
          && (this.budgetDeferred || this.anim === null)) {
          // 门开 / 名额释放：只叫醒没在播的，正在播的别重启。
          this.budgetDeferred = false;
          this.scheduleStart();
        }
      }, (): boolean => this.visible);   // 开闸时屏幕上的先放（见 util/chatAnimationGate）
    }
    if (this.canvasReady && this.visible && !this.animationSuspended()) {
      this.scheduleStart();
    }
  }

  aboutToDisappear(): void {
    probeHit('tgs.unmount');
    this.disposed = true;
    this.visible = false;
    this.loadSeq++;
    this.stopAnim();
    if (this.unsubChatGate !== null) {
      this.unsubChatGate();
      this.unsubChatGate = null;
    }
  }

  // 行复用（@ReusableV2）：@Param 已是新贴纸，重置期间 @Monitor('tgsPath') 静默
  // ——lottie 这支不接住就会接着播上一张（原生那支同一个坑，见
  // TgsNativeStickerView.aboutToRecycle）。visible 同样不动，理由也在那里。
  aboutToRecycle(): void {
    this.loadSeq++;
    this.stopAnim();
  }

  aboutToReuse(): void {
    this.onTgsPathChanged();
  }

  private onVisibleAreaChanged(isVisible: boolean, currentRatio: number): void {
    const next: boolean = isVisible && currentRatio > 0;
    if (this.visible === next) {
      return;
    }
    this.visible = next;
    if (!next) {
      // Cached LazyForEach rows may stay mounted outside the viewport, so
      // aboutToDisappear alone is not an animation-lifetime signal.
      this.loadSeq++;
      this.stopAnim();
      return;
    }
    this.budgetDeferred = false;
    if (this.canvasReady && !this.animationSuspended()) {
      this.scheduleStart();
    }
  }

  // Staggered, never in the frame that asked for it.
  //
  // Bringing one of these up costs about 35ms of main-thread work — gunzip,
  // JSON.parse, then lottie.loadAnimation — and a chat opening with several
  // animated stickers on screen put all of that into the frame that was
  // supposed to present the page. Spacing the starts lets the chat appear
  // first and the stickers come alive over the next moment, which is what they
  // look like anyway.
  private scheduleStart(): void {
    this.cancelScheduledStart();
    if (!this.visible || this.animationSuspended()) {
      return;
    }
    const now = Date.now();
    const at = Math.max(now + TGS_FIRST_DELAY_MS, tgsNextStartAt);
    tgsNextStartAt = at + TGS_STAGGER_MS;
    this.startTimer = setTimeout((): void => {
      this.startTimer = -1;
      this.startAnimation();
    }, at - now);
  }

  private cancelScheduledStart(): void {
    if (this.startTimer !== -1) {
      clearTimeout(this.startTimer);
      this.startTimer = -1;
    }
  }

  private async startAnimation(): Promise<void> {
    const seq: number = ++this.loadSeq;
    const path: string = this.tgsPath;
    // 名额留着：排队转过来的名额正是为这一次起播准备的。
    this.stopAnim(true);
    if (this.animationSuspended() || this.disposed || !this.visible) {
      this.releaseSlot();
      return;
    }
    if (!this.holdsSlot) {
      if (!this.slotPool().tryAcquire()) {
        this.budgetDeferred = true; // over budget — static thumbnail instead
        this.waitForSlot();
        return;
      }
      this.holdsSlot = true;
    }
    const json = await gunzipTgs(path);
    if (this.disposed || seq !== this.loadSeq || path !== this.tgsPath) {
      return;
    }
    if (json === '') {
      this.failed = true;
      this.onFailed();
      this.stopAnim();
      return;
    }
    try {
      this.ctx.imageSmoothingEnabled = true;
      this.anim = lottie.loadAnimation({
        container: this.ctx,
        renderer: 'canvas', // the only supported renderer
        loop: this.playOnce ? false : (this.powerCategory === 'sticker' ? this.env.stickerLoop : true),
        autoplay: true,
        animationData: JSON.parse(json),
        contentMode: 'Contain'
      });
    } catch (e) {
      logE(`TgsStickerView lottie load failed: ${e}`);
      this.failed = true;
      this.onFailed();
      this.stopAnim();
    }
  }

  // 判据搬到了 util/tgsPowerGate：原生渲染那支要用同一份。
  private powerSuspended(): boolean {
    return tgsPowerSuspended(this.env, this.powerCategory);
  }

  private animationSuspended(): boolean {
    return this.powerSuspended() ||
      ((this.chatTimeline || this.panelGated) && this.chatGateSuspended);
  }

  private useNative(): boolean {
    return TGS_NATIVE_ENABLED && !this.nativeFailed;
  }

  build() {
    Stack() {
      if (this.useNative() && !this.powerSuspended()) {
        // 原生渲染。lottie 那套（名额、错峰、gunzip+JSON.parse）整个不参与：
        // 下面所有 scheduleStart 的调用点都以 canvasReady 为前提，而那块
        // Canvas 在这一支里根本不挂树。
        TgsNativeStickerView({
          tgsPath: this.tgsPath,
          thumbPath: this.thumbPath,
          boxWidth: this.boxWidth,
          boxHeight: this.boxHeight,
          powerCategory: this.powerCategory,
          chatTimeline: this.chatTimeline,
          panelGated: this.panelGated,
          playOnce: this.playOnce,
          loop: this.playOnce ? false : (this.powerCategory === 'sticker' ? this.env.stickerLoop : true),
          onFailed: (): void => {
            logW('TgsStickerView: native render failed, falling back to lottie');
            this.nativeFailed = true;
          }
        });
      } else if (this.powerSuspended()) {
        if (this.thumbPath !== '') {
          StickerPoster({ path: this.thumbPath, boxWidth: this.boxWidth, boxHeight: this.boxHeight });
        }
      } else if ((this.failed || this.budgetDeferred) && this.thumbPath !== '') {
        StickerPoster({ path: this.thumbPath, boxWidth: this.boxWidth, boxHeight: this.boxHeight });
      } else {
        Canvas(this.ctx)
          .width(this.boxWidth).height(this.boxHeight)
          .onReady(() => {
            this.canvasReady = true;
            if (this.visible && !this.animationSuspended()) {
              this.scheduleStart();
            }
          });
      }
    }
    .width(this.boxWidth).height(this.boxHeight)
    .onVisibleAreaChange([0.01], (isVisible: boolean, currentRatio: number): void => {
      this.onVisibleAreaChanged(isVisible, currentRatio);
    });
  }
}
