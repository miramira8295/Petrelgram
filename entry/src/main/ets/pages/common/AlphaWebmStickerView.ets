import { image } from '@kit.ImageKit';
import { acquireAlphaSticker, AlphaClip, releaseAlphaSticker } from '../../services/AlphaStickerStore';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';

// 带 alpha 的 webm 贴纸：预解码好的 RGBA 帧画到 Canvas 上循环播放。
//
// 为什么不能沿用 ijkplayer：它的 libijkplayer.so 里没有 libvpx，而 ffmpeg 的
// VP9 alpha 拼装只在 libvpxdec 里实现，原生 VP9 解码器不认 BlockAdditional
// 里的那一路——透明区被填成实色，真机上就是一块白底。
//
// 形状照 TgsStickerView 抄：同样是 Canvas 自绘、同样的省电门控、同样在失败时
// 退回静态缩略图。差别只在帧从哪儿来。

// 播放时钟的心跳。贴纸最高 30fps，30ms 一拍足够跟上，又不至于空转太多。
const TICK_MS: number = 30;

// 同时自绘的上限。内存预算管的是"解出多少帧"，管不了"多少块画布在重画"——
// 贴纸面板一屏几十格各自 33fps 地 drawImage，主线程一样会卡。超出的格子退回
// ijkplayer（白底，但那本来就是现在的样子），不会更糟。
// 这个数字对齐 TgsStickerView 的 MAX_LIVE_TGS，两条自绘链路加起来才是主线程
// 真正的负担。
const MAX_LIVE_ALPHA: number = 12;
let liveAlpha: number = 0;

// P4 批 5：迁 @ComponentV2（配方同批 1~4）。9 个省电键走 chatEnv 镜像，
// onPowerChanged 的 @Watch 改成 @Monitor 深层路径一次挂 8 条；复用在
// aboutToReuse 同步重载（@Param webmPath 已是新值，V1 的写回 @Prop 与延帧
// 兜底退役）。
@ComponentV2
export struct AlphaWebmStickerView {
  @Param webmPath: string = '';
  @Param thumbPath: string = '';
  @Param boxWidth: number = 160;
  @Param boxHeight: number = 160;
  @Param powerCategory: string = 'sticker';
  @Param forcePlay: boolean = false;
  // 这条链路走不通时通知父组件切回 ijkplayer。只会调用一次。
  @Param onFallback: () => void = (): void => {};
  @Param onWorking: () => void = (): void => {};
  private env: ChatEnvMirror = chatEnv;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  // 不叫 clip：那是 ArkUI 的通用属性名，组件成员重名会编译失败。
  private sequence: AlphaClip | null = null;
  private timer: number = -1;
  private startedAt: number = 0;
  private shownIndex: number = -1;
  private disposed: boolean = false;
  private loading: boolean = false;
  private reportedWorking: boolean = false;
  private holdsSlot: boolean = false;
  private loadSeq: number = 0;

  // 自愈：挂错时这一格播的是上一张贴纸。复用路径由 aboutToReuse 覆盖。
  @Monitor('webmPath')
  onWebmPathChanged(): void {
    this.disposePlayback();
    this.disposed = false;
    this.reportedWorking = false;
    this.shownIndex = -1;
    this.load();
  }

  aboutToAppear(): void {
    this.disposed = false;
  }

  aboutToDisappear(): void {
    this.disposePlayback();
  }

  aboutToRecycle(): void {
    this.disposePlayback();
  }

  aboutToReuse(): void {
    // @Param webmPath 已是新值：同步重载。
    this.loadSeq++;
    this.disposed = false;
    this.reportedWorking = false;
    this.shownIndex = -1;
    this.load();
  }

  private disposePlayback(): void {
    this.loadSeq++;
    this.disposed = true;
    this.stopTicker();
    this.releaseSlot();
    releaseAlphaSticker(this.sequence);
    this.sequence = null;
    this.reportedWorking = false;
    this.shownIndex = -1;
  }

  private releaseSlot(): void {
    if (this.holdsSlot) {
      this.holdsSlot = false;
      liveAlpha--;
    }
  }

  @Monitor('env.powerSaving', 'env.stickers', 'env.animatedEmoji', 'env.stickerAutoplay',
    'env.emojiChat', 'env.emojiReactions', 'env.emojiStatus', 'env.reduceAnim')
  onPowerChanged(): void {
    if (this.powerSuspended()) {
      this.stopTicker();
    } else if (this.sequence !== null) {
      this.startTicker();
    }
  }

  private stopTicker(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private startTicker(): void {
    this.stopTicker();
    if (this.sequence === null || this.disposed) {
      return;
    }
    this.startedAt = Date.now();
    this.shownIndex = -1;
    this.drawFrame(0);
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
    const total = Math.max(1, clip.durationMs);
    let elapsed = Date.now() - this.startedAt;
    if (elapsed >= total) {
      if (!this.loopEnabled()) {
        this.drawFrame(clip.frames.length - 1);
        this.stopTicker();
        return;
      }
      elapsed = elapsed % total;
      this.startedAt = Date.now() - elapsed;
    }
    let index = 0;
    for (let i = 0; i < clip.timesMs.length; i++) {
      if (clip.timesMs[i] <= elapsed) {
        index = i;
      } else {
        break;
      }
    }
    this.drawFrame(index);
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
    if (this.loading || this.sequence !== null || this.disposed || this.webmPath === '') {
      return;
    }
    if (liveAlpha >= MAX_LIVE_ALPHA) {
      this.fallback();
      return;
    }
    this.holdsSlot = true;
    liveAlpha++;
    this.loading = true;
    const seq: number = ++this.loadSeq;
    const path: string = this.webmPath;
    // 显示尺寸决定解码尺寸：聊天气泡里的贴纸和面板里的小格差着一个数量级，
    // 一律按原生 512 解码就是白烧内存。
    const boxPx = Math.max(vp2px(this.boxWidth), vp2px(this.boxHeight));
    const clip = await acquireAlphaSticker(path, boxPx);
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
      this.fallback();
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
    if (this.powerSuspended()) {
      if (this.thumbPath !== '') {
        Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath).draggable(false)
          .width(this.boxWidth).height(this.boxHeight).objectFit(ImageFit.Contain);
      } else {
        Stack().width(this.boxWidth).height(this.boxHeight);
      }
    } else {
      Canvas(this.ctx)
        .width(this.boxWidth).height(this.boxHeight)
        .onReady(() => {
          this.load();
        });
    }
  }
}
