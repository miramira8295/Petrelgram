import lottie, { AnimationItem } from '@ohos/lottie';
import { gunzipTgs } from '../../util/gunzipTgs';
import {
  KEY_POWER_ACTIVE, KEY_POWER_EMOJI, KEY_POWER_EMOJI_CHAT, KEY_POWER_EMOJI_REACTIONS,
  KEY_POWER_EMOJI_STATUS, KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY, KEY_POWER_STICKER_LOOP,
  KEY_REDUCE_ANIM
} from '../../store/AppSettings';
import { probeHit } from '../../util/panelProbe';
import { logE } from '../../util/log';

// Cap on simultaneously running Lottie animations: a screenful of TGS emoji
// cells (40+) redrawing canvases every frame stutters badly. Cells over the
// cap render their static thumbnail; scrolling releases slots so fresh cells
// animate again.
const MAX_LIVE_TGS: number = 14;
const TGS_FIRST_DELAY_MS: number = 120;
// 一帧只放一个进来，别让它们挤在一起。
const TGS_STAGGER_MS: number = 70;
// 下一个可以开始的时刻，全局共享——错开的是所有实例，不是单个。
let tgsNextStartAt: number = 0;

let liveTgs: number = 0;

// Plays a Telegram TGS sticker (gzipped Lottie JSON) on a Canvas via
// @ohos/lottie. On any decode failure it renders the raster thumbnail instead.
// Do not mark this child @Reusable: a reusable ancestor would create a nested
// cache, while a normal ancestor cannot preserve this cache across row teardown.
@Component
export struct TgsStickerView {
  @Prop @Watch('onTgsPathChanged') tgsPath: string;
  @Prop thumbPath: string = '';
  @Prop boxWidth: number = 160;
  @Prop boxHeight: number = 160;
  @Prop powerCategory: string = 'sticker';
  // 播一次并定格在最后一帧（骰子/老虎机结果动画的官方语义），不循环。
  @Prop playOnce: boolean = false;
  onFailed: () => void = (): void => {};
  @StorageProp(KEY_POWER_ACTIVE) @Watch('onPowerChanged') powerSaving: boolean = false;
  @StorageProp(KEY_POWER_STICKERS) @Watch('onPowerChanged') stickersEnabled: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) @Watch('onPowerChanged') emojiEnabled: boolean = true;
  @StorageProp(KEY_POWER_STICKER_AUTOPLAY) @Watch('onPowerChanged') stickerAutoplay: boolean = true;
  @StorageProp(KEY_POWER_STICKER_LOOP) @Watch('onPowerChanged') stickerLoop: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_CHAT) @Watch('onPowerChanged') emojiChat: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) @Watch('onPowerChanged') emojiReactions: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_STATUS) @Watch('onPowerChanged') emojiStatus: boolean = true;
  @StorageProp(KEY_REDUCE_ANIM) @Watch('onPowerChanged') reduceAnimations: boolean = false;
  @State failed: boolean = false;
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private anim: AnimationItem | null = null;
  private disposed: boolean = false;
  private holdsSlot: boolean = false;
  private canvasReady: boolean = false;
  private startTimer: number = -1;
  // Invalidates an async gunzip/JSON load when this component receives a new
  // path. Without it, the old sticker could finish last and paint over the new
  // value.
  private loadSeq: number = 0;

  private onTgsPathChanged(): void {
    this.loadSeq++;
    this.stopAnim();
    this.disposed = false;
    this.failed = false;
    if (this.canvasReady) {
      this.scheduleStart();
    }
  }

  private onPowerChanged(): void {
    if (this.powerSuspended()) {
      this.stopAnim();
    } else if (this.canvasReady) {
      this.scheduleStart();
    }
  }

  private stopAnim(): void {
    this.cancelScheduledStart();
    if (this.holdsSlot) {
      liveTgs--;
      this.holdsSlot = false;
    }
    if (this.anim !== null) {
      this.anim.destroy();
      this.anim = null;
    }
  }

  aboutToAppear(): void {
    probeHit('tgs.mount');
    this.disposed = false;
    if (this.canvasReady) {
      this.scheduleStart();
    }
  }

  aboutToDisappear(): void {
    probeHit('tgs.unmount');
    this.disposed = true;
    this.loadSeq++;
    this.stopAnim();
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
    if (this.powerSuspended() || this.disposed) {
      return;
    }
    if (liveTgs >= MAX_LIVE_TGS) {
      this.failed = true; // over budget — static thumbnail instead
      return;
    }
    this.holdsSlot = true;
    liveTgs++;
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
        loop: this.playOnce ? false : (this.powerCategory === 'sticker' ? this.stickerLoop : true),
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
    if (this.powerSaving || this.reduceAnimations) {
      return true;
    }
    if (this.powerCategory === 'emojiPicker') {
      return !this.emojiEnabled;
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
      Canvas(this.ctx)
        .width(this.boxWidth).height(this.boxHeight)
        .onReady(() => {
          this.canvasReady = true;
          this.scheduleStart();
        });
    }
  }
}
