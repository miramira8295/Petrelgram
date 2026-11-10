import { image } from '@kit.ImageKit';
import { StickerPoster } from './StickerPoster';
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

// 带 alpha 的 webm 贴纸：解码好的 RGBA 帧画到 Canvas 上循环播放。
//
// 边解边播（2026-10-09）：拿到第一帧就开始播，后面的帧由解码线程陆续追加进
// 同一个 frames 数组。时间轴按完整的时间戳表走，帧没追上就停在最新那一帧
// （alphaPlayableIndex）；中途解坏了（clip.failed）就回退。
//
// 为什么不能沿用 ijkplayer：它的 libijkplayer.so 里没有 libvpx，而 ffmpeg 的
// VP9 alpha 拼装只在 libvpxdec 里实现，原生 VP9 解码器不认 BlockAdditional
// 里的那一路——透明区被填成实色，真机上就是一块白底。
//
// 形状照 TgsStickerView 抄：同样是 Canvas 自绘、同样的省电门控、同样在失败时
// 退回静态缩略图。差别只在帧从哪儿来。

// 播放时钟的心跳。贴纸最高 30fps，30ms 一拍足够跟上，又不至于空转太多。
// （仅回退路径用；默认走共享 displaySync 时钟，见下面的开关。）
const TICK_MS: number = 30;

// 出帧节奏的一键回退开关（2026-09-17）。true = 共享 displaySync 时钟（util/stickerFrameClock），
// 画帧对齐屏幕刷新；false = 原来的 30ms setInterval。原来那条的问题：30ms 的轮询和 33ms
// 一帧的内容、和屏幕刷新都对不齐，每帧在屏上停留的时长忽长忽短。
const ALPHA_USE_DISPLAY_SYNC: boolean = true;

// 帧到齐之后交给系统的 ImageAnimator 播（2026-10-10 验证中）：系统按每帧时长自己换图，
// JS 不再每帧 drawImage——一屏十几张贴纸时主线程省下的就是这一块。images 不支持动态更新，
// 所以边解边播期间仍走 Canvas，整段到齐、且 Canvas 恰好播完一轮回到第 0 帧时才切过去
// （ImageAnimator 总从第一帧起播，这样切换无缝）。false = 一直用 Canvas（一键回退）。
const ALPHA_USE_IMAGE_ANIMATOR: boolean = true;
const ANIMATOR_RELEASE_DELAY_MS: number = 200;

// 同时自绘的上限。内存预算管的是"解出多少帧"，管不了"多少块画布在重画"——
// 贴纸面板一屏几十格各自 33fps 地 drawImage，主线程一样会卡。
// 名额现在与 TGS 共用、按区域分池（2026-09-15），见 util/stickerAnimationBudget。
//
// 【超出的格子显示缩略图、排队等名额，不再退回 ijkplayer（2026-09-15）】
// 原来写的是“超出的退回 ijk，不会更糟”——那是只有透明贴纸走这条的年代。09-14 不透明
// 的也并进来之后，贴纸面板一屏超过 12 格就整批溢出成 ijk：崩溃现场 50 个 ff_read、
// 37 个软解 VP9 线程，越往下滑越卡。更要命的是每滑走一格就销毁一个还在往外发消息的
// 播放器，正撞 ijkplayer 2.0.9 自己的竞态：surface 销毁时把回调引用的删除排进 uv
// 线程池，比它早排队的消息可能后跑完，再去取这个已删的引用——主线程
// napi_get_reference_value 段错误（SEGV_MAPERR，寄存器里是 0x6b6b 的释放填充）。
// 所以 ijk 只留给“解码真失败”，名额不够、内存不够都等（见 waitForMemory）。

// P4 批 5：迁 @ComponentV2（配方同批 1~4）。9 个省电键走 chatEnv 镜像，
// onPowerChanged 的 @Watch 改成 @Monitor 深层路径一次挂 8 条；复用在
// aboutToReuse 同步重载（@Param webmPath 已是新值，V1 的写回 @Prop 与延帧
// 兜底退役）。
@ComponentV2
export struct AlphaWebmStickerView {
  @Param webmPath: string = '';
  // 贴纸文件的 remote.unique_id（2026-10-09）。帧序列那条路按它查磁盘缓存——命中了
  // 源文件可以没下载（路径为空）。
  @Param stickerUid: string = '';
  @Param thumbPath: string = '';
  @Param boxWidth: number = 160;
  @Param boxHeight: number = 160;
  @Param powerCategory: string = 'sticker';
  @Param forcePlay: boolean = false;
  // 在不在会话时间线上（常量）。为真就自己订阅滑动闸——**不能让上层把
  // paused 逐层传下来**：那会在每次开合闸时重渲染 SmartLoopVideo，而它的
  // 重渲染会进动画上下文、同步 flush 整棵树（2026-09-14 trace：单次 47.8ms）。
  //
  // 这道闸以前没有：那时只有少数透明贴纸走帧序列，看不出来；2026-09-14 不透明
  // webm 并进来之后，一屏十几张全在按 setInterval 往 Canvas 上画，滑动直接掉帧。
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
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
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
  // 排队等名额或内存：缩略图盖在画布上（有的话），画出第一帧再撤。
  @Local private waitingSlot: boolean = false;
  // 交给 ImageAnimator 之后：帧信息与播放状态。见 ALPHA_USE_IMAGE_ANIMATOR。
  @Local private animatorFrames: ImageFrameInfo[] = [];
  @Local private animatorState: AnimationStatus = AnimationStatus.Initial;
  @Local private animatorLoops: number = -1;
  private cancelSlotWait: (() => void) | null = null;
  private loadSeq: number = 0;

  // 自愈：挂错时这一格播的是上一张贴纸。复用路径由 aboutToReuse 覆盖。
  @Monitor('webmPath')
  onWebmPathChanged(): void {
    this.disposePlayback();
    this.clearCanvas();
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
    this.clearCanvas();
  }

  aboutToReuse(): void {
    // @Param webmPath 已是新值：同步重载。
    this.clearCanvas();
    this.loadSeq++;
    this.disposed = false;
    this.reportedWorking = false;
    this.shownIndex = -1;
    this.load();
  }

  // 换了贴纸（回收 / 复用 / 换路径）时擦掉画布。**不擦就叠图**：Canvas 一直留着上一张的最后一帧，
  // 复用出来的格子上面又盖着新贴纸的透明缩略图，两张透过透明区叠在一起（2026-09-15 抽屉格子改可复用
  // 之后的真机截图；TgsNativeStickerView 09-14 踩过同一个坑）。滑出屏幕、滑动暂停不擦——还是同一张，定格正好。
  private clearCanvas(): void {
    try {
      this.ctx.clearRect(0, 0, this.boxWidth, this.boxHeight);
    } catch (e) {
      console.error(`AlphaWebmStickerView clear failed: ${e}`);
    }
  }

  // 返回 true = 刚撤下了 ImageAnimator。
  private stopAnimator(): boolean {
    if (this.animatorFrames.length === 0) {
      return false;
    }
    // 【先停再清】顺序反过来的话，中间会有一帧处于"state 还是 Running、frames
    // 已经空了"的组合，ImageAnimator 照常推进 index，于是每个下标都会打一条
    // `ImageAnimator update index error, index: N, size: 0`（2026-11-09 的
    // hilog 里一次滚动会话 742 条，全是这个）。先把状态拨回 Initial，动画器就
    // 不再要帧了，随后清空数组才是安全的。
    this.animatorState = AnimationStatus.Initial;
    this.animatorFrames = [];
    return true;
  }

  // ImageAnimator 是下一帧重建时才撤掉的，这一拍它手里还拿着这些 PixelMap；
  // 引用晚一点还，免得帧被淘汰 release 后它再画一次已释放的图。
  private releaseClip(clip: AlphaClip | null, animatorWasUp: boolean): void {
    if (!animatorWasUp || clip === null) {
      releaseAlphaSticker(clip);
      return;
    }
    setTimeout(() => {
      releaseAlphaSticker(clip);
    }, ANIMATOR_RELEASE_DELAY_MS);
  }

  // Canvas 播完一轮、帧又已到齐：交给 ImageAnimator。返回 true = 已交出去，调用方别再画。
  private handOffToAnimator(clip: AlphaClip): boolean {
    if (!ALPHA_USE_IMAGE_ANIMATOR || !clip.complete || clip.frames.length < 2 || this.animatorFrames.length > 0) {
      return false;
    }
    const scale: number = Math.min(this.boxWidth / clip.width, this.boxHeight / clip.height);
    const frames: ImageFrameInfo[] = [];
    for (let i = 0; i < clip.frames.length; i++) {
      const next: number = i + 1 < clip.timesMs.length ? clip.timesMs[i + 1] : clip.durationMs;
      frames.push({
        src: clip.frames[i] as PixelMap,
        duration: Math.max(1, Math.round(next - clip.timesMs[i]))
      });
    }
    this.animatorSize = [clip.width * scale, clip.height * scale];
    this.animatorHandoffAt = Date.now();
    console.warn(`[AlphaAnimator] handoff frames=${frames.length} durMs=${Math.round(clip.durationMs)} ` +
      `lastFrameMs=${frames[frames.length - 1].duration} bpp=${clip.bytesPerPixel}`);
    this.animatorLoops = this.loopEnabled() ? -1 : 1;
    this.animatorFrames = frames;
    this.animatorState = this.scrollPaused ? AnimationStatus.Paused : AnimationStatus.Running;
    this.stopTicker();
    return true;
  }

  private animatorSize: number[] = [0, 0];
  // 诊断：交接时刻，用来量 ImageAnimator 真正开播 / 每轮回到开头花了多久。
  private animatorHandoffAt: number = 0;
  private animatorLastRepeatAt: number = 0;

  private disposePlayback(): void {
    const animatorWasUp: boolean = this.stopAnimator();
    this.loadSeq++;
    this.disposed = true;
    this.stopTicker();
    if (this.cancelSlotWait !== null) {
      this.cancelSlotWait();
      this.cancelSlotWait = null;
    }
    this.releaseSlot();
    this.releaseClip(this.sequence, animatorWasUp);
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
    const animatorWasUp: boolean = this.stopAnimator();
    this.loadSeq++;
    if (this.cancelSlotWait !== null) {
      this.cancelSlotWait();
      this.cancelSlotWait = null;
    }
    this.releaseSlot();
    this.releaseClip(this.sequence, animatorWasUp);
    this.sequence = null;
    this.shownIndex = -1;
  }

  // 内存预算这一刻不够（全被在播的占着）。**不回退**：预算一满还回退的话，每个新格子
  // 都开一个 ijk 播放器（2026-09-15 第二次崩溃：半秒 40 个）。悄悄还掉名额——不转给
  // 排队的，它们此刻同样拿不到内存，转来转去只会在微任务里空转——然后排队，等下一次
  // 有人正常让出名额（通常同时还掉了帧内存）再试。
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
    if (this.animatorFrames.length > 0) {
      this.animatorState = suspended ? AnimationStatus.Paused : AnimationStatus.Running;
      return;
    }
    if (suspended) {
      this.stopTicker();     // 定格在当前帧，不清画布
    } else if (this.sequence !== null && !this.powerSuspended()) {
      this.startTicker();
    }
  }

  @Monitor('env.powerSaving', 'env.stickers', 'env.animatedEmoji', 'env.stickerAutoplay',
    'env.emojiChat', 'env.emojiReactions', 'env.emojiStatus', 'env.reduceAnim')
  onPowerChanged(): void {
    if (this.animatorFrames.length > 0) {
      this.animatorState = this.powerSuspended() || this.scrollPaused ? AnimationStatus.Paused : AnimationStatus.Running;
      return;
    }
    if (this.powerSuspended()) {
      this.stopTicker();
    } else if (this.sequence !== null) {
      this.startTicker();
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
      // 滑出屏幕：名额和帧内存立刻还掉（定格在当前帧，不清画布），回到屏幕上再取。
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

  // 用"经过的时间 -> 帧号"而不是"每拍前进一帧"：定时器的实际间隔会漂，
  // 按时间查表才不会让贴纸越播越慢。
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

  // 共享时钟的一拍。帧在内存里（边解边播时可能还没到齐），这里按**下一帧上屏的时刻**（targetMs）
  // 查表、当场画上——画的时刻就对齐了屏幕刷新。与 onTick 同一套回卷规则。
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
      // 播完一轮回到开头：帧已到齐就交给 ImageAnimator（它从第 0 帧起播，正好接上）。
      if (this.handOffToAnimator(clip)) {
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
      // Contain 摆放：贴纸不一定是正方形，拉伸会变形。
      const scale = Math.min(this.boxWidth / clip.width, this.boxHeight / clip.height);
      const w = clip.width * scale;
      const h = clip.height * scale;
      this.ctx.clearRect(0, 0, this.boxWidth, this.boxHeight);
      this.ctx.drawImage(clip.frames[index] as image.PixelMap,
        (this.boxWidth - w) / 2, (this.boxHeight - h) / 2, w, h);
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
    releaseAlphaSticker(this.sequence);
    this.sequence = null;
    if (!this.disposed) {
      this.onFallback();
    }
  }

  private async load(): Promise<void> {
    if (this.loading || this.sequence !== null || this.disposed || (this.webmPath === '' && this.stickerUid === '')
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
    return this.powerCategory === 'sticker' ? this.env.stickerLoop : true;
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
      // 排队时缩略图**盖在**画布上，而不是换掉画布：重试可能又排回去，换来换去会让画布
      // 反复重建、onReady 反复进来，每重试一次闪一下。
      Stack() {
        if (this.animatorFrames.length > 0) {
          ImageAnimator()
            .images(this.animatorFrames)
            .state(this.animatorState)
            .iterations(this.animatorLoops)
            .fillMode(FillMode.Forwards)
            .onStart((): void => {
              this.animatorLastRepeatAt = Date.now();
              console.warn(`[AlphaAnimator] start after ${this.animatorLastRepeatAt - this.animatorHandoffAt}ms`);
            })
            .onRepeat((): void => {
              const now: number = Date.now();
              console.warn(`[AlphaAnimator] repeat loopMs=${now - this.animatorLastRepeatAt}`);
              this.animatorLastRepeatAt = now;
            })
            .width(this.animatorSize[0]).height(this.animatorSize[1]);
        } else {
          Canvas(this.ctx)
            .width(this.boxWidth).height(this.boxHeight)
            .onReady(() => {
              this.load();
            });
        }
        if (this.waitingSlot && this.thumbPath !== '') {
          StickerPoster({ path: this.thumbPath, boxWidth: this.boxWidth, boxHeight: this.boxHeight });
        }
      }
      .width(this.boxWidth).height(this.boxHeight);
    }
  }
}
