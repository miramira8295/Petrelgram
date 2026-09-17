import { AvLoopVideo } from '../common/AvLoopVideo';
import { requestSenderAnimation } from '../../services/PhotoAnimationFetch';
import { AnimationSlotPool } from '../../util/animationSlotPool';
import { subscribeChatAnimationGate } from '../../util/chatAnimationGate';
import { chatEnv, ChatEnvMirror } from '../../util/chatEnvMirror';
import { logW } from '../../util/log';
import { senderChannelKey } from '../../util/senderAvatarChannel';
import {
  markSenderAnimationBroken, senderAnimationFor, subscribeSenderAnimation
} from '../../util/senderAnimationChannel';

// 群聊气泡左侧的动态头像（issue #140，2026-09-17）。叠在静态头像上面的一层，
// 只有头像带动画的发送者才会挂（LiveSenderAvatar / LightweightSenderAvatar 按
// UserStore/ChatStore 的 has_animation 标志决定）。
//
// 【什么时候动】
// - 在屏幕上：滑出屏幕立刻还名额、拆播放器；但**滑动中**滑出去的先留着（它已经暂停了），
//   停稳后再拆——拆播放器也是活，不该挤在滑动帧里；
// - 停稳了：滚动闸（chatAnimationGate）关着时一律暂停在当前帧，也不新建播放器；
// - 有名额：同时在放的不超过 SENDER_AVATAR_ANIMATION_SLOTS 个，拿不到就排队，名额让出时
//   转给最后排进来的（最新进屏幕的那个）；
// - 省电设置「播放动图头像」开着、且不在省电模式（同 AvatarView.shouldAnimate）。
//
// 【取什么】160×160 的 small_animation（大份最大 1280×1280），见 util/photoAnimation。
// 在屏幕上且停稳时才去取；同一个人只取一次，结果走 senderAnimationChannel 广播。
//
// 【不闪】播放器真正开始出帧（onWorking）之前透明，底下的静态头像照常显示。

// 每个都是一路硬件解码器实例；会话里的 GIF 也用同一种播放器。一屏群聊通常三到六个头像。
export const SENDER_AVATAR_ANIMATION_SLOTS: number = 4;
const senderAvatarSlots: AnimationSlotPool = new AnimationSlotPool(SENDER_AVATAR_ANIMATION_SLOTS);

@ComponentV2
export struct SenderAnimatedLayer {
  @Param senderId: number = 0;
  @Param senderIsUser: boolean = true;
  @Param avatarSize: number = 38;
  @Local private videoPath: string = '';
  @Local private holding: boolean = false;
  @Local private gateSuspended: boolean = false;
  @Local private shown: boolean = false;
  private env: ChatEnvMirror = chatEnv;
  private visible: boolean = false;
  private disposed: boolean = false;
  private attachedKey: string = '';
  private unsubPath: (() => void) | null = null;
  private unsubGate: (() => void) | null = null;
  private cancelWait: (() => void) | null = null;

  aboutToAppear(): void {
    this.disposed = false;
    this.attach();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.detach();
  }

  // visible 不动：回收与复用常在同一帧，中间没有可见性结算（同 TgsNativeStickerView）。
  aboutToRecycle(): void {
    this.detach();
  }

  aboutToReuse(): void {
    this.attach();
  }

  @Monitor('senderId', 'senderIsUser')
  onSenderChanged(): void {
    this.detach();
    this.attach();
  }

  @Monitor('env.animatedAvatar', 'env.powerSaving')
  onPowerChanged(): void {
    this.evaluate();
  }

  private attach(): void {
    const key: string = senderChannelKey(this.senderId, this.senderIsUser);
    this.attachedKey = key;
    this.videoPath = senderAnimationFor(key);
    this.unsubPath = subscribeSenderAnimation(key, (path: string): void => {
      this.videoPath = path;
      this.evaluate();
    });
    // 订阅时立刻回调一次当前值；第二个参数让开闸时屏幕上的先放。
    this.unsubGate = subscribeChatAnimationGate((suspended: boolean): void => {
      this.gateSuspended = suspended;
      this.evaluate();
    }, (): boolean => this.visible);
    this.evaluate();
  }

  private detach(): void {
    if (this.unsubPath !== null) {
      this.unsubPath();
      this.unsubPath = null;
    }
    if (this.unsubGate !== null) {
      this.unsubGate();
      this.unsubGate = null;
    }
    this.releaseSlot();
    this.videoPath = '';
    this.attachedKey = '';
  }

  private allowed(): boolean {
    return this.env.animatedAvatar && !this.env.powerSaving;
  }

  // 所有状态变化（可见性、闸门、路径、省电开关、名额）都回到这里重新判一次。
  private evaluate(): void {
    if (this.disposed || this.attachedKey === '') {
      return;
    }
    if (!this.allowed() || !this.visible) {
      if (this.holding && this.gateSuspended && this.allowed()) {
        return; // 滑动中滑出屏幕：已暂停，停稳后再拆
      }
      this.releaseSlot();
      return;
    }
    if (this.gateSuspended) {
      return; // 滑动中不取、不新建播放器；已有的由 paused 暂停
    }
    if (this.videoPath === '') {
      this.releaseSlot();
      requestSenderAnimation(this.senderId, this.senderIsUser);
      return;
    }
    if (this.holding || this.cancelWait !== null) {
      return;
    }
    if (senderAvatarSlots.tryAcquire()) {
      this.holding = true;
      return;
    }
    this.cancelWait = senderAvatarSlots.wait((): void => {
      this.cancelWait = null;
      if (this.disposed || !this.visible || this.videoPath === '' || !this.allowed() || this.gateSuspended) {
        senderAvatarSlots.release();
        return;
      }
      this.holding = true;
    });
  }

  private releaseSlot(): void {
    if (this.cancelWait !== null) {
      this.cancelWait();
      this.cancelWait = null;
    }
    if (this.holding) {
      this.holding = false;
      this.shown = false;
      senderAvatarSlots.release();
    }
  }

  // 文件放不了：同一个人别的行也别再试（通道广播空路径，大家各自拆掉）。
  private onPlaybackFailed(): void {
    logW(`[SenderAnim] ${this.attachedKey} playback failed`);
    if (this.attachedKey !== '') {
      markSenderAnimationBroken(this.attachedKey);
    }
    this.releaseSlot();
  }

  build() {
    Stack() {
      if (this.holding && this.videoPath !== '') {
        AvLoopVideo({
          videoPath: this.videoPath,
          boxWidth: this.avatarSize,
          boxHeight: this.avatarSize,
          loop: true,
          muted: true,
          paused: this.gateSuspended,
          onWorking: (): void => {
            this.shown = true;
          },
          onFailed: (): void => {
            this.onPlaybackFailed();
          }
        })
          // 透明度只加在播放器上，不加在根节点：根节点要参与可见区判定。
          .opacity(this.shown ? 1 : 0);
      }
    }
    .width(this.avatarSize).height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
    .clip(true)
    // 点头像看资料、长按提及都挂在外层头像上，这一层不接触摸。
    .hitTestBehavior(HitTestMode.None)
    .onVisibleAreaChange([0.01], (isVisible: boolean, ratio: number): void => {
      const next: boolean = isVisible && ratio > 0;
      if (this.visible === next) {
        return;
      }
      this.visible = next;
      this.evaluate();
    });
  }
}
