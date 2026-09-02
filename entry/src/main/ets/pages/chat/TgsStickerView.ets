import lottie, { AnimationItem } from '@ohos/lottie';
import { gunzipTgs } from '../../util/gunzipTgs';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { probeHit } from '../../util/panelProbe';
import { logE, logW } from '../../util/log';

// Cap on simultaneously running Lottie animations: a screenful of TGS emoji
// cells (40+) redrawing canvases every frame stutters badly. Cells over the
// cap render their static thumbnail; scrolling releases slots so fresh cells
// animate again.
const MAX_LIVE_TGS: number = 14;
// A chat row is much larger than a picker cell and competes with message-list
// layout. Four live canvases cover a normal viewport while keeping Lottie's
// per-frame shape interpolation inside the UI budget.
const MAX_LIVE_CHAT_TGS: number = 4;
const TGS_FIRST_DELAY_MS: number = 120;
// 一帧只放一个进来，别让它们挤在一起。
const TGS_STAGGER_MS: number = 70;
// 下一个可以开始的时刻，全局共享——错开的是所有实例，不是单个。
let tgsNextStartAt: number = 0;

let liveTgs: number = 0;
let liveChatTgs: number = 0;

type ChatTgsGateListener = (suspended: boolean) => void;
let chatTgsSuspended: boolean = false;
let chatTgsGateListeners: ChatTgsGateListener[] = [];

// ChatPage drives this directly from navigation, initial row staging and list
// scrolling. A tiny module channel avoids putting a high-frequency scroll flag
// into every MessageBubble's @Prop tree.
export function setChatTgsSuspended(suspended: boolean): void {
  if (chatTgsSuspended === suspended) {
    return;
  }
  chatTgsSuspended = suspended;
  logW(`[TgsGate] suspended=${suspended} live=${liveTgs}/${MAX_LIVE_TGS} chat=${liveChatTgs}/${MAX_LIVE_CHAT_TGS} listeners=${chatTgsGateListeners.length}`);
  for (const listener of chatTgsGateListeners) {
    listener(suspended);
  }
}

// 名额腾出来了：叫醒因为超预算被推迟的视图。没有这一步，第 MAX_LIVE_CHAT_TGS+1
// 张起的贴纸会一直停在「推迟」——没缩略图就是空白加转圈，只有重进聊天页才重来。
// 只在门开着时广播；各视图的监听器自己判断"正在播的不动、推迟的才重试"。
function notifyChatTgsSlotFreed(): void {
  if (chatTgsSuspended) {
    return;
  }
  for (const listener of chatTgsGateListeners) {
    listener(false);
  }
}

function subscribeChatTgsGate(listener: ChatTgsGateListener): () => void {
  chatTgsGateListeners = [...chatTgsGateListeners, listener];
  listener(chatTgsSuspended);
  return (): void => {
    chatTgsGateListeners = chatTgsGateListeners.filter(
      (candidate: ChatTgsGateListener): boolean => candidate !== listener);
  };
}

// Plays a Telegram TGS sticker (gzipped Lottie JSON) on a Canvas via
// @ohos/lottie. On any decode failure it renders the raster thumbnail instead.
// Do not mark this child @Reusable: a reusable ancestor would create a nested
// cache, while a normal ancestor cannot preserve this cache across row teardown.
// P4 批 6b：迁 @ComponentV2（配方同批 1~6a）。9 个省电键走 chatEnv 镜像，
// onPowerChanged 用 @Monitor 深层路径一次挂 9 条。本组件无复用钩子（不进
// 复用池的门控自绘），@Watch→@Monitor 即完成。
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
  // 播一次并定格在最后一帧（骰子/老虎机结果动画的官方语义），不循环。
  @Param playOnce: boolean = false;
  @Param onFailed: () => void = (): void => {};
  private env: ChatEnvMirror = chatEnv;
  @Local failed: boolean = false;
  @Local private budgetDeferred: boolean = false;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private anim: AnimationItem | null = null;
  private disposed: boolean = false;
  private holdsSlot: boolean = false;
  private canvasReady: boolean = false;
  private startTimer: number = -1;
  private visible: boolean = false;
  private chatGateSuspended: boolean = false;
  private holdsChatSlot: boolean = false;
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
    } else if (this.canvasReady && this.visible && !this.chatGateSuspended) {
      this.scheduleStart();
    }
  }

  private stopAnim(): void {
    this.cancelScheduledStart();
    if (this.holdsSlot) {
      liveTgs--;
      this.holdsSlot = false;
    }
    if (this.holdsChatSlot) {
      liveChatTgs--;
      this.holdsChatSlot = false;
      notifyChatTgsSlotFreed();
    }
    if (this.anim !== null) {
      this.anim.destroy();
      this.anim = null;
    }
  }

  aboutToAppear(): void {
    probeHit('tgs.mount');
    this.disposed = false;
    if (this.chatTimeline && this.unsubChatGate === null) {
      this.unsubChatGate = subscribeChatTgsGate((suspended: boolean): void => {
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
      });
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
    this.stopAnim();
    if (this.animationSuspended() || this.disposed || !this.visible) {
      return;
    }
    if (liveTgs >= MAX_LIVE_TGS || (this.chatTimeline && liveChatTgs >= MAX_LIVE_CHAT_TGS)) {
      logW(`[TgsGate] deferred live=${liveTgs}/${MAX_LIVE_TGS} chat=${liveChatTgs}/${MAX_LIVE_CHAT_TGS} thumb=${this.thumbPath !== ''}`);
      this.budgetDeferred = true; // over budget — static thumbnail instead
      return;
    }
    this.holdsSlot = true;
    liveTgs++;
    if (this.chatTimeline) {
      this.holdsChatSlot = true;
      liveChatTgs++;
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

  private powerSuspended(): boolean {
    if (this.env.powerSaving || this.env.reduceAnim) {
      return true;
    }
    if (this.powerCategory === 'emojiPicker') {
      return !this.env.animatedEmoji;
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

  private animationSuspended(): boolean {
    return this.powerSuspended() ||
      (this.chatTimeline && this.chatGateSuspended);
  }

  build() {
    Stack() {
      if (this.powerSuspended()) {
        if (this.thumbPath !== '') {
          Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath).draggable(false)
            .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
        }
      } else if ((this.failed || this.budgetDeferred) && this.thumbPath !== '') {
        Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath).draggable(false)
          .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
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
