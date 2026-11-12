import { senderHasAnimatedPhoto } from '../../services/PhotoAnimationFetch';
import { SenderAnimatedLayer } from './SenderAnimatedLayer';
import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { EMPTY_SENDER_AVATAR_STATE, SenderAvatarSpec, SenderAvatarState } from '../../util/messageBubblePresentation';
import { AVATAR_PALETTE } from '../../util/theme';
import { senderAvatarFor, senderChannelKey, subscribeSenderAvatar } from '../../util/senderAvatarChannel';


@ComponentV2
export struct MessageSenderAvatar {
  // One atomic input keeps sender identity/path together and resets one Param
  // per reuse. The caller keeps the 38vp sender / 22vp comment policies.
  @Require @Param spec: SenderAvatarSpec;
  @Local private avatarState: SenderAvatarState = EMPTY_SENDER_AVATAR_STATE;
  private get path(): string { return this.avatarState.path; }
  private get animated(): boolean { return this.avatarState.animated; }

  private setAvatarState(path: string, animated: boolean): void {
    if (this.path !== path || this.animated !== animated) {
      this.avatarState = { path, animated };
    }
  }
  // 无装饰器成员复用时不重置（官方表格 + 批 0.5 实测），照旧记订阅与回收态。
  private unsubAvatar: (() => void) | null = null;
  private attachedAvatarKey: string = '';

  private attachAvatarChannel(senderId: number, senderIsUser: boolean, initialPath: string): void {
    const key: string = senderChannelKey(senderId, senderIsUser);
    const known: string = senderAvatarFor(key);
    this.setAvatarState(known !== '' ? known : initialPath,
      this.spec.animate && senderHasAnimatedPhoto(senderId, senderIsUser));
    if (this.unsubAvatar !== null && this.attachedAvatarKey === key) { return; }
    this.detachAvatarChannel();
    this.attachedAvatarKey = key;
    this.unsubAvatar = subscribeSenderAvatar(key, (path: string): void => {
      if (this.attachedAvatarKey !== key) { return; }
      const spec = this.spec;
      this.setAvatarState(path, spec.animate && senderHasAnimatedPhoto(spec.senderId, spec.senderIsUser));
    });
  }

  @Monitor('spec')
  onSpecChanged(): void {
    const spec = this.spec;
    if (this.unsubAvatar === null ||
      this.attachedAvatarKey !== senderChannelKey(spec.senderId, spec.senderIsUser)) {
      this.attachAvatarChannel(spec.senderId, spec.senderIsUser, spec.initialPath);
      return;
    }
    this.setAvatarState(this.path !== '' ? this.path : spec.initialPath,
      spec.animate && senderHasAnimatedPhoto(spec.senderId, spec.senderIsUser));
  }

  private detachAvatarChannel(): void {
    if (this.unsubAvatar !== null) {
      this.unsubAvatar();
      this.unsubAvatar = null;
    }
    this.attachedAvatarKey = '';
  }

  aboutToAppear(): void {
    const spec = this.spec;
    this.attachAvatarChannel(spec.senderId, spec.senderIsUser, spec.initialPath);
  }

  aboutToRecycle(): void {
    this.detachAvatarChannel();
  }

  aboutToReuse(): void {
    // @Param 已是新值、@Local path 已被框架重置（批 0.5 判读）：同步重挂+
    // 重播种即可。initialPath 也是新行的值，I-2 串头像坑在这条路不存在；
    // #137 的「按 key 保留 path」不再需要——同步重播种（通道现值或新行
    // initialPath）的窗口是零帧，比保留旧值更不闪。
    const spec = this.spec;
    this.attachAvatarChannel(spec.senderId, spec.senderIsUser, spec.initialPath);
  }

  aboutToDisappear(): void {
    this.detachAvatarChannel();
  }

  private preparedImageSpec: CachedImageSpec | undefined = undefined;

  private imageSpec(): CachedImageSpec {
    const size: number = this.spec.avatarSize;
    const path: string = this.path;
    const previous = this.preparedImageSpec;
    // All other fields are fixed policy or derived from size. Read live values
    // before comparing so channel updates and in-place input changes still win.
    if (previous !== undefined && previous.path === path && previous.boxWidth === size) {
      return previous;
    }
    // Preserve bounded pinning; render cached pixels on the container. Misses decode on the
    // TaskPool so a recycled row never blocks the UI thread. No Computed: the
    // child expression reads the current path/size.
    const next: CachedImageSpec = {
      path: path, boxWidth: size, boxHeight: size, radius: size / 2,
      fit: ImageFit.Cover, pinBounded: true, syncDisplay: true, drawOnCanvas: true
    };
    this.preparedImageSpec = next;
    return next;
  }

  build() {
    // One fixed subtree for initials and decoded bitmap. The old AvatarView
    // changed branches between empty/non-empty paths; under a recycled message
    // shell that both defeated reuse and accounted for 110 ms of build/destroy
    // work in the captured scroll trace.
    Stack() {
      // 底色圆和首字母合成一个 Text（背景色 + 半径圆角 = 原来的 Circle），头像少一个节点。
      // 字母只在真没头像时画；有路径但图还没到（极少数走异步的情况）就是纯色圆，
      // 色块→照片比字母→照片柔和得多——所以有图时只清空文字、不藏背景。
      Text(this.path === '' ? this.spec.initials : '')
        .width(this.spec.avatarSize).height(this.spec.avatarSize).borderRadius(this.spec.avatarSize / 2)
        .backgroundColor(AVATAR_PALETTE[Math.abs(this.spec.senderId) % AVATAR_PALETTE.length])
        .textAlign(TextAlign.Center).align(Alignment.Center)
        .fontColor(Color.White).fontSize(this.spec.avatarSize * 0.4).fontWeight(FontWeight.Medium);
      CachedImage({ spec: this.imageSpec() })
        .visibility(this.path !== '' ? Visibility.Visible : Visibility.None);
      if (this.animated) {
        SenderAnimatedLayer({
          senderId: this.spec.senderId, senderIsUser: this.spec.senderIsUser, avatarSize: this.spec.avatarSize
        });
      }
    }
    .width(this.spec.avatarSize).height(this.spec.avatarSize);
  }
}
