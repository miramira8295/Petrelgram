import { image } from '@kit.ImageKit';
import { AvLoopVideo } from './AvLoopVideo';
import { acquireAvatarFrames, trimAvatarFrames } from '../../services/AvatarFrameStore';
import { AvatarFrameAsset, AvatarFrameLease } from '../../util/avatarFramePool';
import { chatEnv, ChatEnvMirror } from '../../util/chatEnvMirror';

// 只用于聊天发送者头像。短片缓存成功后交给系统ImageAnimator，不在JS逐帧刷新。
@ComponentV2
export struct AvatarFrameView {
  @Param videoPath: string = '';
  @Param avatarSize: number = 38;
  @Param paused: boolean = false;
  @Param onWorking: () => void = (): void => {};
  @Param onFailed: () => void = (): void => {};
  @Local private frames: ImageFrameInfo[] = [];
  @Local private fallback: boolean = false;
  @Local private epoch: number = 0;
  private env: ChatEnvMirror = chatEnv;
  // 普通字段保持单调；@Local会在复用时重置，不能用它拒绝旧异步结果。
  private generation: number = 0;
  private active: boolean = false;
  private loading: boolean = false;
  private lease: AvatarFrameLease<image.PixelMap> | null = null;

  aboutToAppear(): void { this.active = true; this.reset(); }
  aboutToDisappear(): void { this.active = false; this.clear(); }
  aboutToRecycle(): void { this.active = false; this.clear(); }
  aboutToReuse(): void { this.active = true; this.reset(); }

  @Monitor('videoPath', 'avatarSize')
  onSourceChanged(): void { if (this.active) { this.reset(); } }

  @Monitor('paused', 'env.appIsForeground')
  onPlaybackChanged(): void {
    if (!this.env.appIsForeground) { trimAvatarFrames(); }
    if (this.active && !this.paused && this.env.appIsForeground) { this.load(); }
  }

  private reset(): void { this.clear(); this.load(); }
  private clear(): void {
    this.epoch = ++this.generation;
    const held = this.lease;
    this.lease = null;
    const hadFrames = this.frames.length > 0;
    this.frames = [];
    this.fallback = false;
    this.loading = false;
    if (held !== null) {
      // ImageAnimator撤下发生在下一帧，不能在它仍持有PixelMap时允许LRU释放。
      if (hadFrames) {
        setTimeout((): void => { held.release(); if (!chatEnv.appIsForeground) { trimAvatarFrames(); } }, 200);
      } else { held.release(); }
    }
  }

  private load(): void {
    if (!this.active || this.loading || this.fallback || this.frames.length > 0 ||
      this.paused || !this.env.appIsForeground || this.videoPath === '') { return; }
    this.loading = true;
    const token = this.generation;
    acquireAvatarFrames(this.videoPath, this.getUIContext().vp2px(this.avatarSize))
      .then((held: AvatarFrameLease<image.PixelMap>): void => {
        if (!this.active || token !== this.generation) { held.release(); return; }
        this.lease = held;
        held.ready.then((asset: AvatarFrameAsset<image.PixelMap> | null): void => {
          if (!this.active || token !== this.generation) { return; }
          this.loading = false;
          if (asset === null) {
            held.release();
            this.lease = null;
            this.fallback = true;
            return;
          }
          const frames: ImageFrameInfo[] = [];
          for (let i = 0; i < asset.frames.length; i++) {
            frames.push({ src: asset.frames[i] as PixelMap, duration: asset.durationsMs[i] });
          }
          this.frames = frames;
        });
      });
  }

  build() {
    Stack() {
      if (this.frames.length > 0) {
        // images不支持动态换源，换素材/复用时用新epoch明确创建新动画节点。
        ForEach([this.epoch], (_epoch: number) => {
          ImageAnimator()
            .images(this.frames)
            .state(this.paused || !this.env.appIsForeground ? AnimationStatus.Paused : AnimationStatus.Running)
            .iterations(-1)
            .fillMode(FillMode.Forwards)
            .onStart((): void => { this.onWorking(); })
            .width(this.avatarSize).height(this.avatarSize);
        }, (epoch: number): string => `${epoch}`);
      } else if (this.fallback) {
        AvLoopVideo({ videoPath: this.videoPath, boxWidth: this.avatarSize, boxHeight: this.avatarSize,
          loop: true, muted: true, paused: this.paused || !this.env.appIsForeground,
          onWorking: this.onWorking, onFailed: this.onFailed });
      }
    }.width(this.avatarSize).height(this.avatarSize);
  }
}
