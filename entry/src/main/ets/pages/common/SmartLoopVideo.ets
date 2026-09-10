import { AvLoopVideo } from './AvLoopVideo';
import { WebmStickerView } from '../chat/WebmStickerView';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { subscribeChatTgsGate } from '../chat/TgsStickerView';
import { logW } from '../../util/log';

// One-time probe verdict for VP9/WEBM on the system AVPlayer:
// 0 = unknown (try AVPlayer), 1 = works, -1 = unsupported (go straight to ijk).
let avWebmVerdict: number = 0;

// Looping muted video that prefers the system AVPlayer (hardware decode) and
// silently falls back to ijkplayer (ffmpeg software VP9) when the system
// codec can't handle the file. The verdict is remembered process-wide.
// P4 批 6b：迁 @ComponentV2（配方同批 1~6a）。11 个省电键走 chatEnv 镜像；
// 复用同步化（@Param 已是新值）。
@ComponentV2
export struct SmartLoopVideo {
  @Param videoPath: string = '';
  @Param thumbPath: string = '';
  @Param boxWidth: number = 160;
  @Param boxHeight: number = 160;
  @Param powerCategory: string = 'sticker';
  // A deliberate tap may play a GIF even when automatic playback is disabled
  // by its category/power policy. The parent still pauses it when off-screen
  // or when the app enters the background.
  @Param forcePlay: boolean = false;
  @Param onPlaybackFailed: () => void = (): void => {};
  // 参与聊天列表的滑动闸（贴纸那套）。**只有会话内的 GIF 传 true**——面板里的
  // GIF/贴纸不在那条列表上，跟着聊天页的滚动停播毫无道理。
  //
  // 滑动时**暂停，不换成缩略图**：换 subtree 会让播放器 surface 消失一帧，
  // 那正是用户报的"滑动时 GIF 闪一下"。暂停把最后一帧留在原地。
  @Param scrollGated: boolean = false;
  @Local private scrollPaused: boolean = false;
  private unsubGate: (() => void) | null = null;
  private env: ChatEnvMirror = chatEnv;
  // 透明素材必须走 ijk，见 aboutToAppear。这里的初值只管非透明那一类。
  @Local useIjk: boolean = avWebmVerdict === -1;
  @Local videoReady: boolean = false;
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
    if (this.scrollGated && this.unsubGate === null) {
      this.unsubGate = subscribeChatTgsGate((suspended: boolean): void => {
        if (this.scrollPaused !== suspended) {
          this.scrollPaused = suspended;
        }
      });
    }
  }

  aboutToDisappear(): void {
    this.resetPlaybackState();
    if (this.unsubGate !== null) {
      this.unsubGate();
      this.unsubGate = null;
    }
  }

  aboutToRecycle(): void {
    this.resetPlaybackState();
  }

  // 【两条复用路径都要覆盖】aboutToReuse 只在 @ReusableV2 那条路上触发；打开
  // Repeat 自己的复用（virtualScroll reusable:true）时它**不会被调用**（官方：
  // 「Repeat 自身能够进行复用，不会走到自定义组件复用的生命周期」）。而
  // @ReusableV2 复用的重置期间 @Monitor 又是静默的——两者互补，缺一不可。
  @Monitor('videoPath')
  onVideoSourceChanged(): void {
    this.resetForNewSource();
  }

  aboutToReuse(): void {
    // @Param 已是新值（批 0.5 判读）：直接按新素材类别判定。
    this.resetForNewSource();
  }

  private resetForNewSource(): void {
    this.resetPlaybackState();
    this.useIjk = this.isTransparentAsset() || avWebmVerdict === -1;
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
    if (this.env.powerSaving || this.env.reduceAnim) {
      return true;
    }
    if (this.powerCategory === 'emojiPicker') {
      return !this.env.animatedEmoji;
    }
    if (this.powerCategory === 'gif') {
      return !this.env.autoplayGif;
    }
    if (this.powerCategory === 'video') {
      return !this.env.autoplayVideo;
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
            paused: this.scrollPaused,
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
