import { AvLoopVideo } from './AvLoopVideo';
import { WebmStickerView } from '../chat/WebmStickerView';
import {
  KEY_POWER_ACTIVE, KEY_POWER_AUTOPLAY_GIF, KEY_POWER_AUTOPLAY_VIDEO, KEY_POWER_EMOJI,
  KEY_POWER_EMOJI_CHAT, KEY_POWER_EMOJI_REACTIONS, KEY_POWER_EMOJI_STATUS,
  KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY, KEY_POWER_STICKER_LOOP, KEY_REDUCE_ANIM
} from '../../store/AppSettings';
import { logW } from '../../util/log';
import { reuseParam } from '../../util/reuseParams';

// One-time probe verdict for VP9/WEBM on the system AVPlayer:
// 0 = unknown (try AVPlayer), 1 = works, -1 = unsupported (go straight to ijk).
let avWebmVerdict: number = 0;

// Looping muted video that prefers the system AVPlayer (hardware decode) and
// silently falls back to ijkplayer (ffmpeg software VP9) when the system
// codec can't handle the file. The verdict is remembered process-wide.
@Component
export struct SmartLoopVideo {
  @Prop videoPath: string;
  @Prop thumbPath: string = '';
  @Prop boxWidth: number = 160;
  @Prop boxHeight: number = 160;
  @Prop powerCategory: string = 'sticker';
  // A deliberate tap may play a GIF even when automatic playback is disabled
  // by its category/power policy. The parent still pauses it when off-screen
  // or when the app enters the background.
  @Prop forcePlay: boolean = false;
  onPlaybackFailed: () => void = (): void => {};
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_AUTOPLAY_GIF) autoplayGif: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_VIDEO) autoplayVideo: boolean = true;
  @StorageProp(KEY_POWER_STICKERS) stickersEnabled: boolean = true;
  @StorageProp(KEY_POWER_STICKER_AUTOPLAY) stickerAutoplay: boolean = true;
  @StorageProp(KEY_POWER_STICKER_LOOP) stickerLoop: boolean = true;
  @StorageProp(KEY_POWER_EMOJI) emojiEnabled: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_CHAT) emojiChat: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) emojiReactions: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_STATUS) emojiStatus: boolean = true;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnimations: boolean = false;
  // 透明素材必须走 ijk，见 aboutToAppear。这里的初值只管非透明那一类。
  @State useIjk: boolean = avWebmVerdict === -1;
  @State videoReady: boolean = false;
  private firstFrameTimer: number = -1;

  aboutToAppear(): void {
    // 贴纸和表情带 alpha：系统 AVPlayer 把画面解到一个**不带透明通道**的
    // surface 上，透明区域被填成实色（真机上是白底）；ijk 走 TEXTURE
    // XComponent，能带 alpha 合成。所以这一类不参与"优先 AVPlayer"的探测。
    //
    // 这个坑还会扩散：AVPlayer 只要在某个不透明素材上成功过一次，
    // avWebmVerdict 就记成 1，之后所有贴纸都会走它——所以判断必须在这里按
    // 素材类别做，不能只靠那个全局探测结果。
    if (this.isTransparentAsset()) {
      this.useIjk = true;
    }
  }

  aboutToDisappear(): void {
    this.resetPlaybackState();
  }

  aboutToRecycle(): void {
    this.resetPlaybackState();
  }

  aboutToReuse(params: Record<string, Object>): void {
    this.resetPlaybackState();
    // reuseParam：params 是 {} 还是 undefined 都安全，取不到就落到已有的
    // isTransparentAsset() 兜底（P3 批 2 第 1 项，见 util/reuseParams.ets）。
    const category: string | undefined =
      reuseParam(params, 'powerCategory') as string | undefined;
    const transparent: boolean = category !== undefined
      ? this.transparentCategory(category) : this.isTransparentAsset();
    this.useIjk = transparent || avWebmVerdict === -1;
  }

  private resetPlaybackState(): void {
    if (this.firstFrameTimer !== -1) {
      clearTimeout(this.firstFrameTimer);
      this.firstFrameTimer = -1;
    }
    this.videoReady = false;
  }

  private onVideoWorking(): void {
    if (this.videoReady || this.firstFrameTimer !== -1) {
      return;
    }
    // Player "playing/prepared" precedes texture composition by a frame on
    // some devices. Keep the poster for a short grace period so no black frame
    // is exposed during the hand-off.
    this.firstFrameTimer = setTimeout((): void => {
      this.firstFrameTimer = -1;
      this.videoReady = true;
    }, 80);
  }

  private suspended(): boolean {
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

  private isTransparentAsset(): boolean {
    return this.transparentCategory(this.powerCategory);
  }

  private transparentCategory(category: string): boolean {
    return category === 'sticker' || category === 'emojiChat'
      || category === 'emojiPicker' || category === 'emoji'
      || category === 'emojiReaction' || category === 'emojiStatus';
  }

  build() {
    if (this.suspended()) {
      if (this.thumbPath !== '') {
        Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath).draggable(false)
          .width(this.boxWidth).height(this.boxHeight)
          .objectFit(this.isTransparentAsset() ? ImageFit.Contain : ImageFit.Cover);
      } else {
        Stack()
          .width(this.boxWidth).height(this.boxHeight)
          .backgroundColor(this.isTransparentAsset() ? Color.Transparent : '#AEB6C0');
      }
    } else {
      Stack() {
        // Keep the thumbnail mounted below the texture. Download progress can
        // update the parent row without flashing an empty player surface.
        if (this.thumbPath !== '') {
          Image(this.thumbPath.startsWith('/') ? `file://${this.thumbPath}` : this.thumbPath).draggable(false)
            .width(this.boxWidth).height(this.boxHeight)
            .objectFit(this.isTransparentAsset() ? ImageFit.Contain : ImageFit.Cover);
        } else {
          Stack() {
            LoadingProgress().width(28).height(28).color(Color.White);
          }
          .width(this.boxWidth).height(this.boxHeight)
          .backgroundColor(this.isTransparentAsset() ? Color.Transparent : '#AEB6C0');
        }
        if (this.useIjk) {
          WebmStickerView({
            webmPath: this.videoPath, thumbPath: this.thumbPath,
            boxWidth: this.boxWidth, boxHeight: this.boxHeight,
            powerCategory: this.powerCategory,
            forcePlay: this.forcePlay,
            onWorking: (): void => { this.onVideoWorking(); },
            onFailed: (): void => { this.onPlaybackFailed(); }
          })
            .opacity(this.videoReady ? 1 : 0)
            .animation({ duration: 140, curve: Curve.EaseOut });
        } else {
          AvLoopVideo({
            videoPath: this.videoPath,
            boxWidth: this.boxWidth, boxHeight: this.boxHeight,
            loop: this.loopEnabled(),
            onFailed: (): void => {
              if (avWebmVerdict === 0) {
                logW('SmartLoopVideo: AVPlayer cannot play this webm — falling back to ijkplayer');
              }
              this.videoReady = false;
              avWebmVerdict = -1;
              this.useIjk = true;
            },
            onWorking: (): void => {
              avWebmVerdict = 1;
              this.onVideoWorking();
            }
          })
            .opacity(this.videoReady ? 1 : 0)
            .animation({ duration: 140, curve: Curve.EaseOut });
        }
      }
      .width(this.boxWidth).height(this.boxHeight)
      .clip(true);
    }
  }
}
