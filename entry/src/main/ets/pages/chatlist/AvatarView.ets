import { AVATAR_PALETTE, AVATAR_SIZE, COLOR_PRIMARY } from '../../util/theme';
import { formatTTL } from '../../util/formatTTL';
import { AvLoopVideo } from '../common/AvLoopVideo';
import { CachedImage } from '../common/CachedImage';
import { KEY_POWER_ACTIVE, KEY_POWER_ANIMATED_AVATAR } from '../../store/AppSettings';

@Component
export struct AvatarView {
  @Prop avatarPath: string;
  @Prop initials: string;
  @Prop colorSeed: number;
  @Prop autoDeleteTime: number = 0;
  @Prop isLive: boolean = false;
  @Prop livePulseExpanded: boolean = false;
  // Animated profile photo (MPEG4 loop). Only profile pages pass this —
  // list rows stay static (one looping player per row would be too heavy).
  @Prop animPath: string = '';
  // 「我的收藏」：和自己的私聊。画书签而不是自己的头像——用户在列表里要一眼
  // 认出它，Telegram 各端都是这么处理的（issue #8）。
  @Prop savedMessages: boolean = false;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_ANIMATED_AVATAR) animatedAvatar: boolean = true;
  avatarSize: number = AVATAR_SIZE;

  // 动态头像播不播。
  //
  // 原来挂在"自动播放视频"（KEY_POWER_AUTOPLAY_VIDEO）上，那是把实现细节
  // 漏到了用户语义上——恰好都用播放器解码，就被绑到了同一个开关。可这两件
  // 事的用户预期完全不同：「自动播放视频」是"聊天里的视频别自动播"，动机是
  // 省流量；而动态头像是几十 KB 的循环片段、**而且早就下载完了**，不播它一
  // 点流量都省不了，只是让界面变呆。用户在设置里看到那一行，也不会想到它管
  // 的是头像。
  //
  // 改成省电设置里自己的一档「播放动图头像」。省电模式仍然是总闸。
  //
  // 别处的边界本来就是对的（MessageStore 里 isAnimation ? GIF : VIDEO），
  // 只有头像这一处错了。
  private shouldAnimate(): boolean {
    return this.animPath !== '' && this.animatedAvatar && !this.powerSaving;
  }

  @Builder
  base() {
    if (this.savedMessages) {
      Row() {
        SymbolGlyph($r('sys.symbol.bookmark_fill'))
          .fontSize(this.avatarSize * 0.5)
          .fontColor([Color.White]);
      }
      .width(this.avatarSize).height(this.avatarSize)
      .borderRadius(this.avatarSize / 2)
      .backgroundColor(COLOR_PRIMARY)
      .justifyContent(FlexAlign.Center);
    } else if (this.shouldAnimate()) {
      // Animated avatars are H.264 MP4 — the system AVPlayer loops them with
      // hardware decode (far lighter than ijkplayer's software path).
      Column() {
        AvLoopVideo({
          videoPath: this.animPath,
          boxWidth: this.avatarSize,
          boxHeight: this.avatarSize
        });
      }
      .width(this.avatarSize).height(this.avatarSize)
      .borderRadius(this.avatarSize / 2)
      .clip(true);
    } else if (this.avatarPath !== '') {
      // Through the PixelMap cache, like chat photos. Avatars are small but
      // there are a lot of them and they repeat: the same file is decoded for
      // every row showing that chat and again after every recycle. Straight
      // Image(file://…) redid all of that, which is why chat-list rows WITH an
      // avatar stuttered more than rows falling back to initials.
      Stack() {
        // The initials sit underneath so a pending decode shows the coloured
        // circle rather than a hole.
        this.initialsCircle();
        CachedImage({
          path: this.avatarPath,
          boxWidth: this.avatarSize,
          boxHeight: this.avatarSize,
          radius: this.avatarSize / 2,
          fit: ImageFit.Cover
        });
      }
      .width(this.avatarSize).height(this.avatarSize);
    } else {
      this.initialsCircle();
    }
  }

  @Builder
  initialsCircle() {
    Stack() {
      Circle({ width: this.avatarSize, height: this.avatarSize })
        .fill(AVATAR_PALETTE[Math.abs(this.colorSeed) % AVATAR_PALETTE.length]);
      Text(this.initials)
        .fontColor(Color.White).fontSize(this.avatarSize * 0.4).fontWeight(FontWeight.Medium);
    }
    .width(this.avatarSize).height(this.avatarSize);
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.base();
      if (this.autoDeleteTime > 0 && !this.isLive) {
        Text(formatTTL(this.autoDeleteTime))
          .fontSize(9).fontColor(Color.White).fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .backgroundColor(COLOR_PRIMARY)
          .borderRadius(8)
          .border({ width: 1.5, color: Color.White })
          .constraintSize({ minWidth: 16 })
          .padding({ left: 3, right: 3, top: 1, bottom: 1 });
      }
      if (this.isLive) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 22, height: 22 })
            .fill('#442AABEE')
            .opacity(this.livePulseExpanded ? 0.18 : 0.52)
            .scale({
              x: this.livePulseExpanded ? 1.12 : 0.92,
              y: this.livePulseExpanded ? 1.12 : 0.92
            });
          Circle({ width: 18, height: 18 })
            .fill('#F8FCFF')
            .shadow({ radius: 3, color: '#292A88C9', offsetX: 0, offsetY: 1 })
            .scale({
              x: this.livePulseExpanded ? 1.03 : 0.98,
              y: this.livePulseExpanded ? 1.03 : 0.98
            });
          Row({ space: 1.5 }) {
            Circle({ width: 2.5, height: 2.5 }).fill('#249FE8');
            Rect({ width: 2.5, height: 8, radius: 1.25 }).fill('#249FE8');
            Rect({ width: 2.5, height: 8, radius: 1.25 }).fill('#249FE8');
            Circle({ width: 2.5, height: 2.5 }).fill('#249FE8');
          }.alignItems(VerticalAlign.Center);
        }
        .width(22).height(22)
        .translate({ x: 1, y: 1 });
      }
    }
    .width(this.avatarSize).height(this.avatarSize);
  }
}
