import { componentUtils } from '@kit.ArkUI';
import { AvatarFrameView } from '../common/AvatarFrameView';
import { requestSenderAnimation } from '../../services/PhotoAnimationFetch';
import { AnimationSlotPool } from '../../util/animationSlotPool';
import { subscribeChatAnimationGate } from '../../util/chatAnimationGate';
import { subscribeSenderAnimationPark } from '../../util/senderAnimationPark';
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

// 同时播放名额：同屏最多 2 个不同发送者的动态头像硬解播放，且同一发送者同屏去重只播 1 个。
export const SENDER_AVATAR_ANIMATION_SLOTS: number = 2;
const senderAvatarSlots: AnimationSlotPool = new AnimationSlotPool(SENDER_AVATAR_ANIMATION_SLOTS);
const activeSenderKeys: Set<string> = new Set<string>();
const sameSenderWaiters: Map<string, Set<() => void>> = new Map<string, Set<() => void>>();

function notifySameSenderWaiter(key: string): void {
  const set: Set<() => void> | undefined = sameSenderWaiters.get(key);
  if (!set || set.size === 0) {
    return;
  }
  const callbacks: Array<() => void> = Array.from(set);
  for (let i: number = 0; i < callbacks.length; i++) {
    callbacks[i]();
    if (activeSenderKeys.has(key)) {
      break;
    }
  }
}
// 顶栏（ChatHeader + TopBanners + 68px 模糊采样核）与底栏（ChatComposerInput + 68px 模糊采样核）
// 避让区：落入毛玻璃采样核内的边缘头像保持静态底图，杜绝 30fps 视频纹理每帧炸穿 6 个毛玻璃胶囊的 FilterCache。
const TOP_BLUR_GUARD_VP: number = 148;
const BOTTOM_BLUR_GUARD_VP: number = 96;
let nextSenderAnimNodeSeq: number = 0;

@ComponentV2
export struct SenderAnimatedLayer {
  @Param senderId: number = 0;
  @Param senderIsUser: boolean = true;
  @Param avatarSize: number = 38;
  @Local private videoPath: string = '';
  @Local private holding: boolean = false;
  @Local private gateSuspended: boolean = false;
  // 「停车」：页面正在退场，播放器现在就卸掉，别等整棵树同步销毁时一起结账
  // （见 util/senderAnimationPark）。和 gateSuspended 不是一回事：那个只暂停。
  @Local private parked: boolean = false;
  @Local private shown: boolean = false;
  private readonly nodeId: string = `sender_anim_${++nextSenderAnimNodeSeq}`;
  private env: ChatEnvMirror = chatEnv;
  private visible: boolean = false;
  private disposed: boolean = true;
  @Local private attachmentEpoch: number = 0;
  private playbackEpoch: number = 0;
  private playbackKey: string = '';
  private attachedKey: string = '';
  private holdingKey: string = '';
  private unsubPath: (() => void) | null = null;
  private unsubGate: (() => void) | null = null;
  private unsubPark: (() => void) | null = null;
  private cancelWait: (() => void) | null = null;
  private sameSenderWake: (() => void) | null = null;
  private parkTimer: number = -1;

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
    this.disposed = true;
    this.detach();
  }

  aboutToReuse(): void {
    this.disposed = false;
    this.attach();
  }

  @Monitor('senderId', 'senderIsUser')
  onSenderChanged(): void {
    this.detach();
    this.attach();
  }

  // @Monitor needs a decorated root; the singleton itself remains private.
  // Read every input so changing one policy flag cannot hide another dependency.
  @Computed
  private get playbackEnvironmentKey(): number {
    return (this.env.animatedAvatar ? 1 : 0) +
      (this.env.powerSaving ? 2 : 0);
  }

  @Monitor('playbackEnvironmentKey')
  onPowerChanged(): void {
    this.evaluate();
  }

  private attach(): void {
    if (this.disposed) { return; }
    if (this.attachedKey !== '' || this.holding || this.unsubPath !== null) {
      this.detach();
    }
    const key: string = senderChannelKey(this.senderId, this.senderIsUser);
    this.attachedKey = key;
    const epoch = ++this.attachmentEpoch;
    this.videoPath = senderAnimationFor(key);
    this.unsubPath = subscribeSenderAnimation(key, (path: string): void => {
      if (!this.acceptsAttachment(epoch, key)) { return; }
      if (path !== this.videoPath) { this.playbackEpoch++; this.shown = false; }
      this.videoPath = path;
      this.evaluate();
    });
    // 订阅时立刻回调一次当前值；第二个参数让开闸时屏幕上的先放。
    this.unsubGate = subscribeChatAnimationGate((suspended: boolean): void => {
      if (!this.acceptsAttachment(epoch, key)) { return; }
      this.gateSuspended = suspended;
      this.evaluate();
    }, (): boolean => this.acceptsAttachment(epoch, key) && this.visible);
    this.unsubPark = subscribeSenderAnimationPark((next: boolean): void => {
      if (!this.acceptsAttachment(epoch, key)) { return; }
      if (this.parkTimer !== -1) {
        clearTimeout(this.parkTimer);
        this.parkTimer = -1;
      }
      if (next && this.holding) {
        // 避开退场起跳第 0 帧（第 0 帧已由 gateSuspended 暂停播放），在转场第 24ms 卸载 AVPlayer。
        this.parkTimer = setTimeout((): void => {
          if (!this.acceptsAttachment(epoch, key)) { return; }
          this.parkTimer = -1;
          this.parked = true;
          this.evaluate();
        }, 24);
        return;
      }
      this.parked = next;
      this.evaluate();
    });
    this.evaluate();
  }

  private detach(): void {
    this.attachmentEpoch++; this.playbackEpoch++; this.playbackKey = '';
    if (this.unsubPath !== null) {
      this.unsubPath();
      this.unsubPath = null;
    }
    if (this.unsubGate !== null) {
      this.unsubGate();
      this.unsubGate = null;
    }
    if (this.unsubPark !== null) {
      this.unsubPark();
      this.unsubPark = null;
    }
    if (this.parkTimer !== -1) {
      clearTimeout(this.parkTimer);
      this.parkTimer = -1;
    }
    this.releaseSlot();
    this.videoPath = '';
    this.attachedKey = '';
  }

  private allowed(): boolean {
    return this.env.animatedAvatar && !this.env.powerSaving && !this.parked;
  }

  private inSafeViewport(): boolean {
    try {
      const rect: componentUtils.ComponentInfo =
        this.getUIContext().getComponentUtils().getRectangleById(this.nodeId);
      const h: number = this.getUIContext().px2vp(rect.size.height);
      if (!(h > 0)) {
        return true;
      }
      const topVp: number = this.getUIContext().px2vp(rect.windowOffset.y);
      const bottomVp: number = topVp + h;
      const bottomLimit: number =
        this.env.screenHeightVp - this.env.keyboardHeightVp - BOTTOM_BLUR_GUARD_VP;
      return topVp >= TOP_BLUR_GUARD_VP && bottomVp <= bottomLimit;
    } catch (_) {
      return true;
    }
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
    // 停稳后若落入顶栏/底栏毛玻璃采样核区域，释放槽位保持静态头像，避免每帧炸穿 6 个毛玻璃 FilterCache。
    if (!this.inSafeViewport()) {
      this.releaseSlot();
      return;
    }
    if (this.videoPath === '') {
      this.releaseSlot();
      requestSenderAnimation(this.senderId, this.senderIsUser);
      return;
    }
    if (this.holding || this.cancelWait !== null) {
      return;
    }
    // 同屏同一发送者只起 1 个动态头像播放器，避免同一人连发多条消息时重复起多个 AVPlayer；
    // 登记候补回调，当正在播的那枚滚出安全区释放时由本枚立即接力。
    if (activeSenderKeys.has(this.attachedKey)) {
      this.registerSameSenderWaiter();
      return;
    }
    this.unregisterSameSenderWaiter();
    if (senderAvatarSlots.tryAcquire()) {
      this.holding = true;
      this.holdingKey = this.attachedKey;
      activeSenderKeys.add(this.holdingKey);
      return;
    }
    const epoch = this.attachmentEpoch, key = this.attachedKey;
    this.cancelWait = senderAvatarSlots.wait((): void => {
      if (!this.acceptsAttachment(epoch, key)) { senderAvatarSlots.release(); return; }
      this.cancelWait = null;
      if (this.disposed || !this.visible || this.videoPath === '' || !this.allowed() ||
        this.gateSuspended || !this.inSafeViewport()) {
        senderAvatarSlots.release();
        return;
      }
      if (activeSenderKeys.has(this.attachedKey)) {
        senderAvatarSlots.release();
        this.registerSameSenderWaiter();
        return;
      }
      this.holding = true;
      this.holdingKey = this.attachedKey;
      activeSenderKeys.add(this.holdingKey);
    });
  }

  private registerSameSenderWaiter(): void {
    if (this.sameSenderWake !== null || this.attachedKey === '') {
      return;
    }
    const key: string = this.attachedKey;
    const epoch = this.attachmentEpoch;
    const cb = (): void => {
      if (!this.acceptsAttachment(epoch, key)) { return; }
      this.unregisterSameSenderWaiter();
      this.evaluate();
    };
    let set: Set<() => void> | undefined = sameSenderWaiters.get(key);
    if (!set) {
      set = new Set<() => void>();
      sameSenderWaiters.set(key, set);
    }
    set.add(cb);
    this.sameSenderWake = (): void => {
      const s: Set<() => void> | undefined = sameSenderWaiters.get(key);
      if (s) {
        s.delete(cb);
        if (s.size === 0) {
          sameSenderWaiters.delete(key);
        }
      }
    };
  }

  private unregisterSameSenderWaiter(): void {
    if (this.sameSenderWake !== null) {
      this.sameSenderWake();
      this.sameSenderWake = null;
    }
  }

  private releaseSlot(): void {
    this.playbackEpoch++; this.playbackKey = '';
    this.unregisterSameSenderWaiter();
    if (this.cancelWait !== null) {
      this.cancelWait();
      this.cancelWait = null;
    }
    const releasedKey: string = this.holdingKey;
    if (this.holdingKey !== '') {
      activeSenderKeys.delete(this.holdingKey);
      this.holdingKey = '';
    }
    if (this.holding) {
      this.holding = false;
      this.shown = false;
      senderAvatarSlots.release();
    }
    if (releasedKey !== '') {
      notifySameSenderWaiter(releasedKey);
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

  private acceptsAttachment(epoch: number, key: string): boolean {
    return !this.disposed && this.attachmentEpoch === epoch && this.attachedKey === key &&
      senderChannelKey(this.senderId, this.senderIsUser) === key;
  }
  private playbackGeneration(): number {
    const key = `${this.attachmentEpoch}:${this.holding}:${this.videoPath}`;
    if (key !== this.playbackKey) { this.playbackKey = key; this.playbackEpoch++; }
    return this.playbackEpoch;
  }
  private workingCallback(): () => void {
    const epoch = this.attachmentEpoch, key = this.attachedKey, playback = this.playbackGeneration();
    return (): void => {
      if (this.acceptsAttachment(epoch, key) && this.holding && playback === this.playbackGeneration()) { this.shown = true; }
    };
  }
  private failedCallback(): () => void {
    const epoch = this.attachmentEpoch, key = this.attachedKey, playback = this.playbackGeneration();
    return (): void => {
      if (this.acceptsAttachment(epoch, key) && this.holding && playback === this.playbackGeneration()) { this.onPlaybackFailed(); }
    };
  }
  private visibleCallback(): (visible: boolean, ratio: number) => void {
    const epoch = this.attachmentEpoch, key = this.attachedKey;
    return (visible: boolean, ratio: number): void => {
      if (!this.acceptsAttachment(epoch, key)) { return; }
      const next = visible && ratio > 0;
      if (this.visible !== next) { this.visible = next; this.evaluate(); }
    };
  }

  build() {
    Stack() {
      if (this.holding && this.videoPath !== '') {
        AvatarFrameView({
          videoPath: this.videoPath,
          avatarSize: this.avatarSize,
          paused: this.gateSuspended,
          onWorking: this.workingCallback(),
          onFailed: this.failedCallback()
        })
          // 透明度只加在播放器上，不加在根节点：根节点要参与可见区判定。
          .opacity(this.shown ? 1 : 0);
      }
    }
    .id(this.nodeId)
    .width(this.avatarSize).height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
    .clip(true)
    // 点头像看资料、长按提及都挂在外层头像上，这一层不接触摸。
    .hitTestBehavior(HitTestMode.None)
    .onVisibleAreaChange([0.01], this.visibleCallback());
  }
}
