import { image } from '@kit.ImageKit';
import { AvLoopVideo } from './AvLoopVideo';
import { DrawnImageReceiver } from './DrawnImageReceiver';
import { acquireAvatarFrames, trimAvatarFrames } from '../../services/AvatarFrameStore';
import { AvatarFrameAsset, AvatarFrameLease } from '../../util/avatarFramePool';
import { chatEnv, ChatEnvMirror } from '../../util/chatEnvMirror';
import { stickerFrameClock } from '../../util/stickerFrameClock';
import { alphaClipFps, alphaPlayableIndex } from '../../util/webm/alphaPlayback';

// 只用于聊天发送者头像。短片帧缓存完成后通过 DrawModifier + 共享 displaySync 时钟播放，
// 避免 ImageAnimator 每换一帧触发父容器 Measure/Layout 与整页 onAreaChange 扫描。
@ComponentV2
export struct AvatarFrameView {
  @Param videoPath: string = '';
  @Param avatarSize: number = 38;
  @Param paused: boolean = false;
  @Param onWorking: () => void = (): void => {};
  @Param onFailed: () => void = (): void => {};
  @Local private fallback: boolean = false;
  private env: ChatEnvMirror = chatEnv;
  private receiver: DrawnImageReceiver = new DrawnImageReceiver();
  // 普通字段保持单调；@Local 会在复用时重置，不能用它拒绝旧异步结果。
  private generation: number = 0;
  private active: boolean = false;
  private loading: boolean = false;
  private lease: AvatarFrameLease<image.PixelMap> | null = null;
  private asset: AvatarFrameAsset<image.PixelMap> | null = null;
  private timesMs: number[] = [];
  private durationMs: number = 0;
  private startedAt: number = 0;
  private shownIndex: number = -1;
  private reportedWorking: boolean = false;
  private unsubClock: (() => void) | null = null;

  aboutToAppear(): void { this.active = true; this.reset(); }
  aboutToDisappear(): void { this.active = false; this.clear(); }
  aboutToRecycle(): void { this.active = false; this.clear(); }
  aboutToReuse(): void { this.active = true; this.reset(); }

  @Monitor('videoPath', 'avatarSize')
  onSourceChanged(): void { if (this.active) { this.reset(); } }

  // @Monitor needs a decorated root; the singleton itself remains private.
  // Read every input so changing one policy flag cannot hide another dependency.
  @Computed
  private get playbackEnvironmentKey(): number {
    return (this.env.appIsForeground ? 1 : 0);
  }

  @Monitor('paused', 'playbackEnvironmentKey')
  onPlaybackChanged(): void {
    if (!this.env.appIsForeground) { trimAvatarFrames(); }
    if (this.paused || !this.env.appIsForeground) {
      this.stopClock();
      return;
    }
    if (this.active) {
      if (this.asset !== null) {
        this.startClock();
      } else {
        this.load();
      }
    }
  }

  private reset(): void { this.clear(); this.load(); }

  private stopClock(): void {
    if (this.unsubClock !== null) {
      this.unsubClock();
      this.unsubClock = null;
    }
  }

  private clear(): void {
    this.generation++;
    this.stopClock();
    this.receiver.setPixels(undefined);
    const held = this.lease;
    this.lease = null;
    this.asset = null;
    this.timesMs = [];
    this.durationMs = 0;
    this.startedAt = 0;
    this.shownIndex = -1;
    this.reportedWorking = false;
    this.fallback = false;
    this.loading = false;
    if (held !== null) {
      held.release();
      if (!chatEnv.appIsForeground) { trimAvatarFrames(); }
    }
  }

  private drawFrame(index: number): void {
    const asset = this.asset;
    if (asset === null || index < 0 || index >= asset.frames.length || index === this.shownIndex) {
      return;
    }
    this.shownIndex = index;
    try {
      this.receiver.bind(this.getUIContext(), this.avatarSize, this.avatarSize, ImageFit.Cover, true);
      this.receiver.setPixels(asset.frames[index]);
      if (!this.reportedWorking) {
        this.reportedWorking = true;
        this.onWorking();
      }
    } catch (_e) {
      this.stopClock();
    }
  }

  private startClock(): void {
    this.stopClock();
    const asset = this.asset;
    if (!this.active || asset === null || asset.frames.length === 0 || this.paused || !this.env.appIsForeground) {
      return;
    }
    if (this.shownIndex < 0) {
      this.drawFrame(0);
    }
    if (asset.frames.length < 2) {
      return;
    }
    this.startedAt = 0;
    const fps = alphaClipFps(asset.frames.length, this.durationMs);
    this.unsubClock = stickerFrameClock.subscribe(this.getUIContext(), fps,
      (timestampMs: number, targetMs: number): void => {
        if (!this.active || this.asset === null || this.paused || !this.env.appIsForeground) {
          this.stopClock();
          return;
        }
        if (this.startedAt === 0) {
          this.startedAt = timestampMs;
        }
        const total = Math.max(1, this.durationMs);
        let elapsed = targetMs - this.startedAt;
        if (elapsed >= total) {
          elapsed = elapsed % total;
          this.startedAt = targetMs - elapsed;
        }
        this.drawFrame(alphaPlayableIndex(this.timesMs, elapsed, this.asset.frames.length));
      });
  }

  private load(): void {
    if (!this.active || this.loading || this.fallback || this.asset !== null ||
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
          if (asset === null || asset.frames.length === 0) {
            held.release();
            this.lease = null;
            this.fallback = true;
            return;
          }
          const times: number[] = [];
          let acc = 0;
          for (let i = 0; i < asset.frames.length; i++) {
            times.push(acc);
            acc += Math.max(16, asset.durationsMs[i] ?? 33);
          }
          this.timesMs = times;
          this.durationMs = Math.max(1, acc);
          this.asset = asset;
          this.shownIndex = -1;
          this.startClock();
        });
      });
  }

  build() {
    Stack() {
      if (this.fallback) {
        AvLoopVideo({ videoPath: this.videoPath, boxWidth: this.avatarSize, boxHeight: this.avatarSize,
          loop: true, muted: true, paused: this.paused || !this.env.appIsForeground,
          onWorking: this.onWorking, onFailed: this.onFailed });
      } else {
        Row()
          .width(this.avatarSize).height(this.avatarSize)
          .drawModifier(this.receiver);
      }
    }.width(this.avatarSize).height(this.avatarSize);
  }
}
