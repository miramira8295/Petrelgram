import { image } from '@kit.ImageKit';
import { StickerPoster } from './StickerPoster';
import { DrawnImageReceiver } from './DrawnImageReceiver';
import { subscribeAnimationGateFor } from '../../util/stickerPanelGate';
import {
  acquireAlphaSticker, AlphaAcquireResult, AlphaClip, releaseAlphaSticker
} from '../../services/AlphaStickerStore';
import { AnimationSlotPool } from '../../util/animationSlotPool';
import { stickerAnimationSlots } from '../../util/stickerAnimationBudget';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { stickerFrameClock } from '../../util/stickerFrameClock';
import { alphaClipFps, alphaPlayableIndex } from '../../util/webm/alphaPlayback';
import { alphaStickerHighBudget } from '../../util/webm/AlphaStickerBudget';

// 带 alpha 的 webm 贴纸：解码好的 RGBA 帧通过 DrawModifier 直接画到节点上循环播放。
//
// 边解边播（2026-10-09）：拿到第一帧就开始播，后面的帧由解码线程陆续追加进
// 同一个 frames 数组。时间轴按完整的时间戳表走，帧没追上就停在最新那一帧
// （alphaPlayableIndex）；中途解坏了（clip.failed）就回退。
//
// 为什么不交回 ImageAnimator（2026-11-20 真机 trace）：
// ImageAnimator 内部是 Stack + Image 子节点，每换一帧都会触发 CreateTaskMeasure/Layout
// 与 FlushLayoutTask，顺带把整页 43 个 onAreaChange + 12 个 onVisibleAreaChange 扫一遍，
// 单次换帧主线程耗时 ~5ms；同时不再需要 Canvas 离屏位图拷贝。
// 改用 DrawnImageReceiver（DrawModifier.drawFront -> drawImageRectWithSrc），每拍仅
// 替换 PixelMap 引用并 invalidate 自身，零布局、零面积回调、零离屏画布分配。

// 播放时钟的心跳（仅非 displaySync 回退路径用）。
const TICK_MS: number = 30;

// 出帧节奏开关：true = 共享 displaySync 时钟（util/stickerFrameClock），对齐屏幕刷新。
const ALPHA_USE_DISPLAY_SYNC: boolean = true;

@ComponentV2
export struct AlphaWebmStickerView {
  @Param webmPath: string = '';
  @Param playOnce: boolean = false;
  @Param replayToken: number = 0;
  // 贴纸文件的 remote.unique_id（2026-10-09）。帧序列那条路按它查磁盘缓存——命中了
  // 源文件可以没下载（路径为空）。
  @Param stickerUid: string = '';
  @Param thumbPath: string = '';
  @Param boxWidth: number = 160;
  @Param boxHeight: number = 160;
  @Param powerCategory: string = 'sticker';
  @Param forcePlay: boolean = false;
  // 在不在会话时间线上（常量）。为真就自己订阅滑动闸。
  @Param chatTimeline: boolean = false;
  // 贴纸抽屉里的格子：订阅抽屉那道闸（见 util/stickerPanelGate），同样跟踪可见性。与 chatTimeline 互斥。
  @Param panelGated: boolean = false;
  @Local private scrollPaused: boolean = false;
  private unsubGate: (() => void) | null = null;
  // 这一格此刻在不在屏幕上（只在滑动闸上的格子跟踪：会话、贴纸抽屉）。屏幕外不画；开闸时也
  // 排在屏幕上的后面（见 util/chatAnimationGate）。
  private onScreen: boolean = false;
  // 这条链路走不通时通知父组件切回 ijkplayer。只会调用一次。
  @Param onFallback: () => void = (): void => {};
  @Param onWorking: () => void = (): void => {};
  private env: ChatEnvMirror = chatEnv;
  private receiver: DrawnImageReceiver = new DrawnImageReceiver();
  // 不叫 clip：那是 ArkUI 的通用属性名，组件成员重名会编译失败。
  private sequence: AlphaClip | null = null;
  private timer: number = -1;
  // 共享出帧时钟的退订函数（ALPHA_USE_DISPLAY_SYNC 时取代 timer）。
  private unsubClock: (() => void) | null = null;
  private startedAt: number = 0;
  private shownIndex: number = -1;
  private disposed: boolean = false;
  private loading: boolean = false;
  private reportedWorking: boolean = false;
  private holdsSlot: boolean = false;
  // 排队等名额或内存、或首帧尚未画出时由缩略图占位。
  @Local private waitingSlot: boolean = false;
  @Local private hasFrame: boolean = false;
  private cancelSlotWait: (() => void) | null = null;
  private loadSeq: number = 0;

  // 自愈：挂错时这一格播的是上一张贴纸。复用路径由 aboutToReuse 覆盖。
  @Monitor('webmPath', 'replayToken')
  onWebmPathChanged(): void {
    this.disposePlayback();
    this.disposed = false;
    this.reportedWorking = false;
    this.shownIndex = -1;
    this.load();
  }

  aboutToAppear(): void {
    this.disposed = false;
    if (this.tracksVisibility() && this.unsubGate === null) {
      // 订阅时会立刻回调一次当前值：挂载在滑动中途的行不能默认"门是开的"。
      this.unsubGate = subscribeAnimationGateFor(this.panelGated, (suspended: boolean): void => {
        this.onGateChanged(suspended);
      }, (): boolean => this.onScreen);
    }
  }

  aboutToDisappear(): void {
    this.disposePlayback();
    if (this.unsubGate !== null) {
      this.unsubGate();
      this.unsubGate = null;
    }
  }

  aboutToRecycle(): void {
    this.disposePlayback();
  }

  aboutToReuse(): void {
    // @Param webmPath 已是新值：同步重载。
    this.clearSurface();
    this.loadSeq++;
    this.disposed = false;
    this.reportedWorking = false;
    this.shownIndex = -1;
    this.load();
  }

  private clearSurface(): void {
    this.receiver.setPixels(undefined);
    if (this.hasFrame) {
      this.hasFrame = false;
    }
  }

  private disposePlayback(): void {
    this.loadSeq++;
    this.disposed = true;
    this.stopTicker();
    if (this.cancelSlotWait !== null) {
      this.cancelSlotWait();
      this.cancelSlotWait = null;
    }
    this.releaseSlot();
    // 必须先清 DrawModifier 对 PixelMap 的引用再归还 clip，避免绘制命中已释放位图。
    this.clearSurface();
    releaseAlphaSticker(this.sequence);
    this.sequence = null;
    this.reportedWorking = false;
    this.shownIndex = -1;
  }

  private releaseSlot(): void {
    if (this.holdsSlot) {
      this.holdsSlot = false;
      this.slotPool().release();
    }
  }

  private slotPool(): AnimationSlotPool {
    return stickerAnimationSlots(this.chatTimeline, this.panelGated);
  }

  // 让出名额与帧序列，组件本身还在（和 disposePlayback 的区别：不置 disposed）。
  private releasePlayback(): void {
    this.loadSeq++;
    if (this.cancelSlotWait !== null) {
      this.cancelSlotWait();
      this.cancelSlotWait = null;
    }
    this.releaseSlot();
    this.clearSurface();
    releaseAlphaSticker(this.sequence);
    this.sequence = null;
    this.shownIndex = -1;
  }

  // 内存预算这一刻不够（全被在播的占着）。悄悄还掉名额再排队。
  private waitForMemory(): void {
    if (this.holdsSlot) {
      this.holdsSlot = false;
      this.slotPool().releaseQuietly();
    }
    this.waitForSlot();
  }

  private waitForSlot(): void {
    this.waitingSlot = true;
    this.cancelSlotWait = this.slotPool().wait((): void => {
      this.cancelSlotWait = null;
      if (this.disposed) {
        this.slotPool().release();   // 转过来的名额原样让出去
        return;
      }
      this.holdsSlot = true;
      this.load();
    });
  }

  private onGateChanged(suspended: boolean): void {
    if (this.scrollPaused === suspended) {
      return;
    }
    this.scrollPaused = suspended;
    if (suspended) {
      this.stopTicker();     // 定格在当前帧，不清画面
    } else if (this.sequence !== null && !this.powerSuspended()) {
      this.startTicker();
    }
  }

  // @Monitor needs a decorated root; the singleton itself remains private.
  // Read every input so changing one policy flag cannot hide another dependency.
  @Computed
  private get playbackEnvironmentKey(): number {
    return (this.env.powerSaving ? 1 : 0) +
      (this.env.stickers ? 2 : 0) +
      (this.env.animatedEmoji ? 4 : 0) +
      (this.env.stickerAutoplay ? 8 : 0) +
      (this.env.emojiChat ? 16 : 0) +
      (this.env.emojiReactions ? 32 : 0) +
      (this.env.emojiStatus ? 64 : 0) +
      (this.env.reduceAnim ? 128 : 0);
  }

  @Monitor('playbackEnvironmentKey')
  onPowerChanged(): void {
    if (this.powerSuspended()) {
      this.stopTicker();
    } else if (this.sequence !== null) {
      this.startTicker();
    } else {
      this.load();
    }
  }

  // 在滑动闸上（会话时间线或贴纸抽屉）：订阅闸门、跟踪可见性。
  private tracksVisibility(): boolean {
    return this.chatTimeline || this.panelGated;
  }

  private onVisibleChanged(isVisible: boolean, ratio: number): void {
    const next: boolean = isVisible && ratio > 0;
    if (this.onScreen === next) {
      return;
    }
    this.onScreen = next;
    if (!next) {
      // 滑出屏幕：名额和帧内存立刻还掉，回到屏幕上再取。
      this.stopTicker();
      this.releasePlayback();
    } else if (this.sequence !== null && !this.powerSuspended()) {
      this.startTicker();
    } else {
      this.load();
    }
  }

  private stopTicker(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    if (this.unsubClock !== null) {
      this.unsubClock();
      this.unsubClock = null;
    }
  }

  private startTicker(): void {
    this.stopTicker();
    if (this.sequence === null || this.disposed || this.scrollPaused || (this.tracksVisibility() && !this.onScreen)) {
      return;
    }
    const clip: AlphaClip | null = this.sequence;
    if (clip === null) {
      return;
    }
    this.shownIndex = -1;
    this.drawFrame(0);
    if (ALPHA_USE_DISPLAY_SYNC) {
      // 起点在第一拍用时钟的时间基定（与 Date.now 不是同一个基准，不能混用）。
      this.startedAt = 0;
      // 帧率按完整的时间戳表算：边解边播时 frames 还没到齐，按它算会偏低。
      this.unsubClock = stickerFrameClock.subscribe(this.getUIContext(),
        alphaClipFps(clip.timesMs.length, clip.durationMs),
        (timestampMs: number, targetMs: number): void => {
          this.onClockTick(timestampMs, targetMs);
        });
      return;
    }
    this.startedAt = Date.now();
    this.timer = setInterval((): void => {
      this.onTick();
    }, TICK_MS);
  }

  // 用"经过的时间 -> 帧号"而不是"每拍前进一帧"：按时间查表才不会越播越慢。
  private onTick(): void {
    const clip = this.sequence;
    if (clip === null || this.disposed) {
      return;
    }
    if (clip.failed) {
      this.stopTicker();
      this.fallback();
      return;
    }
    const total = Math.max(1, clip.durationMs);
    let elapsed = Date.now() - this.startedAt;
    if (elapsed >= total) {
      if (!this.loopEnabled() && clip.complete) {
        this.drawFrame(clip.frames.length - 1);
        this.stopTicker();
        return;
      }
      elapsed = elapsed % total;
      this.startedAt = Date.now() - elapsed;
    }
    this.drawFrame(alphaPlayableIndex(clip.timesMs, elapsed, clip.frames.length));
  }

  // 共享时钟的一拍：按下一帧上屏时刻（targetMs）查表并直接更新 DrawModifier。
  private onClockTick(timestampMs: number, targetMs: number): void {
    const clip = this.sequence;
    if (clip === null || this.disposed) {
      this.stopTicker();
      return;
    }
    if (clip.failed) {
      this.stopTicker();
      this.fallback();
      return;
    }
    if (this.startedAt === 0) {
      this.startedAt = timestampMs;
    }
    const total = Math.max(1, clip.durationMs);
    let elapsed = targetMs - this.startedAt;
    if (elapsed >= total) {
      // 不循环的贴纸要等帧到齐才算播完：还在解就先回卷，免得停在半截。
      if (!this.loopEnabled() && clip.complete) {
        this.drawFrame(clip.frames.length - 1);
        this.stopTicker();
        return;
      }
      elapsed = elapsed % total;
      this.startedAt = targetMs - elapsed;
    }
    this.drawFrame(alphaPlayableIndex(clip.timesMs, elapsed, clip.frames.length));
  }

  private drawFrame(index: number): void {
    const clip = this.sequence;
    if (clip === null || index < 0 || index >= clip.frames.length || index === this.shownIndex) {
      return;
    }
    this.shownIndex = index;
    try {
      this.receiver.bind(this.getUIContext(), this.boxWidth, this.boxHeight, ImageFit.Contain, true);
      this.receiver.setPixels(clip.frames[index] as image.PixelMap, clip.width, clip.height);
      if (!this.hasFrame) {
        this.hasFrame = true;
      }
      if (this.waitingSlot) {
        this.waitingSlot = false;   // 第一帧画上了，撤掉排队时盖着的缩略图
      }
      if (!this.reportedWorking) {
        this.reportedWorking = true;
        this.onWorking();
      }
    } catch (e) {
      console.error(`AlphaWebmStickerView draw failed: ${e}`);
      this.stopTicker();
      this.fallback();
    }
  }

  private fallback(): void {
    this.releaseSlot();
    this.clearSurface();
    releaseAlphaSticker(this.sequence);
    this.sequence = null;
    if (!this.disposed) {
      this.onFallback();
    }
  }

  private async load(): Promise<void> {
    if (this.loading || this.sequence !== null || this.disposed || this.powerSuspended()
      || (this.webmPath === '' && this.stickerUid === '')
      || this.cancelSlotWait !== null || (this.tracksVisibility() && !this.onScreen)) {
      return;
    }
    if (!this.holdsSlot) {
      if (!this.slotPool().tryAcquire()) {
        this.waitForSlot();
        return;
      }
      this.holdsSlot = true;
    }
    this.loading = true;
    const seq: number = ++this.loadSeq;
    const path: string = this.webmPath;
    // 显示尺寸决定解码尺寸：聊天气泡里的贴纸和面板里的小格差着一个数量级，
    // 一律按原生 512 解码就是白烧内存。
    const boxPx = Math.max(this.getUIContext().vp2px(this.boxWidth), this.getUIContext().vp2px(this.boxHeight));
    const result: AlphaAcquireResult =
      await acquireAlphaSticker(path, boxPx, alphaStickerHighBudget(this.powerCategory), this.stickerUid);
    const clip: AlphaClip | null = result.clip;
    this.loading = false;
    if (this.disposed || seq !== this.loadSeq || path !== this.webmPath) {
      this.releaseSlot();
      releaseAlphaSticker(clip);
      if (!this.disposed) {
        setTimeout((): void => { this.load(); }, 0);
      }
      return;
    }
    if (clip === null) {
      if (result.status === 'busy') {
        this.waitForMemory();
      } else {
        this.fallback();
      }
      return;
    }
    this.sequence = clip;
    if (!this.powerSuspended()) {
      this.startTicker();
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
    return !this.playOnce && (this.powerCategory === 'sticker' ? this.env.stickerLoop : true);
  }

  build() {
    if (this.tracksVisibility()) {
      // 只有滑动闸上的格子跟踪可见性（开闸排先后、屏幕外不画）；其余调用点省掉这笔每帧的可见区计算。
      Stack() {
        this.surface();
      }
      .width(this.boxWidth).height(this.boxHeight)
      .onVisibleAreaChange([0.01], (isVisible: boolean, ratio: number): void => {
        this.onVisibleChanged(isVisible, ratio);
      });
    } else {
      this.surface();
    }
  }

  @Builder
  surface() {
    if (this.powerSuspended()) {
      if (this.thumbPath !== '') {
        StickerPoster({ path: this.thumbPath, boxWidth: this.boxWidth, boxHeight: this.boxHeight });
      } else {
        Stack().width(this.boxWidth).height(this.boxHeight);
      }
    } else {
      Stack() {
        Row()
          .width(this.boxWidth).height(this.boxHeight)
          .drawModifier(this.receiver)
          .onAppear((): void => {
            this.load();
          });
        if ((this.waitingSlot || !this.hasFrame) && this.thumbPath !== '') {
          StickerPoster({ path: this.thumbPath, boxWidth: this.boxWidth, boxHeight: this.boxHeight });
        }
      }
      .width(this.boxWidth).height(this.boxHeight);
    }
  }
}
