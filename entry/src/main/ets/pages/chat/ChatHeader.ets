import { AvatarView } from '../chatlist/AvatarView';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_ICON_ON_DARK, COLOR_ICON_ON_LIGHT,
  COLOR_TEXT_ON_LIGHT, COLOR_TEXT_SECONDARY, KEY_APP_DARK } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  overlayBackdropBlur, overlayGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { str } from '../../util/strings';
import { APPEARANCE_EPOCH } from '../../util/appearance';

// HDS 标题栏里的会话身份内容。标题栏背板、返回键和右侧菜单都由
// HdsNavDestination 负责；这里只有标准 title 无法表达的头像和动态状态。

export const CHAT_HEADER_ACTION_SIZE: number = 42;
export const CHAT_HEADER_RADIUS: number = 22;

@Component
export struct ChatHeader {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // 顶栏浮在聊天壁纸上：深色模式 + 浅色壁纸时它其实坐在亮底上，白色前景会掉到
  // 2.22:1。由 ChatPage 算好传进来（判据见 util/chatChrome），这里只按它选前景。
  @Prop onLightBg: boolean = false;
  @StorageProp(KEY_APP_DARK) appDark: boolean = false;
  @Prop titleText: string;
  @Prop subtitleText: string;
  // 'ready' | 'loading' | 'error'——error 时副标题变红，点击是重试而不是进资料页。
  @Prop headerState: string;
  @Prop avatarPath: string;
  // 动态头像（MP4 小循环）。'' 表示没有或没取到，AvatarView 自己退回静态图。
  @Prop avatarAnimPath: string = '';
  @Prop initials: string;
  // 「我的收藏」：头像位画书签而不是自己的头像（issue #8）。
  @Prop savedMessages: boolean = false;
  @Prop chatId: number;
  // 名字后面的 emoji 状态：'tgs' 动画、'webm' 视频、其余当静态图。
  @Prop emojiPath: string;
  @Prop emojiFormat: string;
  @Prop isMuted: boolean;
  @Prop muteUpdating: boolean;
  @Prop profileOpening: boolean;
  onOpenProfile: () => void = (): void => {};
  onResolveIdentity: () => void = (): void => {};

  @Styles
  identityNormalStyle() {
    .backgroundColor(overlayGlassFill('bar', $r('app.color.surface')))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  identityPressedStyle() {
    .backgroundColor(overlayGlassFill('bar', $r('app.color.surface_alt')))
    .opacity(0.78)
    .scale({ x: 0.985, y: 0.96 })
  }

  @Builder
  titleAccessory() {
    if (this.headerState === 'loading' || this.profileOpening) {
      LoadingProgress().width(15).height(15).color(this.accent()).margin({ left: 5 });
    } else if (this.emojiPath !== '') {
      if (this.emojiFormat === 'tgs') {
        TgsStickerView({
          tgsPath: this.emojiPath, boxWidth: 18, boxHeight: 18, powerCategory: 'emojiStatus'
        }).margin({ left: 4 });
      } else if (this.emojiFormat === 'webm') {
        WebmStickerView({
          webmPath: this.emojiPath, boxWidth: 18, boxHeight: 18, powerCategory: 'emojiStatus'
        }).margin({ left: 4 });
      } else {
        Image(`file://${this.emojiPath}`).draggable(false)
          .width(18).height(18).objectFit(ImageFit.Contain).margin({ left: 4 });
      }
    }
    if (this.muteUpdating) {
      LoadingProgress().width(14).height(14).color(this.fgSecondary()).margin({ left: 4 });
    } else if (this.isMuted) {
      SymbolGlyph($r('sys.symbol.bell_slash'))
        .fontSize(14).fontColor([this.fgIcon()]).margin({ left: 4 });
    }
  }

  private fgPrimary(): ResourceColor {
    return this.onLightBg ? COLOR_TEXT_ON_LIGHT : COLOR_TEXT_PRIMARY;
  }

  private fgIcon(): ResourceColor {
    if (this.onLightBg) {
      return COLOR_ICON_ON_LIGHT;
    }
    // 和输入栏同一套：顶栏浮在壁纸上，深色下用亮白，浅色下用次级灰。
    return this.appDark ? COLOR_ICON_ON_DARK : COLOR_ICON_SECONDARY;
  }

  private fgSecondary(): ResourceColor {
    // 亮底上没有"次级灰"可用：#8E8E93 在浅紫合成底上只有 1.5:1。副标题（成员数/
    // 在线数）本来就短，宁可和主标题同色也别看不见。
    return this.onLightBg ? COLOR_TEXT_ON_LIGHT : COLOR_TEXT_SECONDARY;
  }

  build() {
    Row({ space: 10 }) {
      AvatarView({
        avatarPath: this.avatarPath,
        animPath: this.avatarAnimPath,
        initials: this.initials,
        colorSeed: this.chatId,
        avatarSize: 38,
        savedMessages: this.savedMessages
      })
        .margin({ left: -4, right: 0 });
      Column() {
        Row() {
          Text(this.titleText)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.fgPrimary())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1);
          this.titleAccessory();
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
        Text(this.subtitleText)
          .fontSize(12)
          .fontColor(this.headerState === 'error' ? '#E64646' : this.fgSecondary())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 1 });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .width('calc(100% - 124vp)')
    .height(CHAT_HEADER_ACTION_SIZE)
    .padding({ left: 7, right: 12 })
    .borderRadius(CHAT_HEADER_RADIUS)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .stateStyles({ normal: this.identityNormalStyle, pressed: this.identityPressedStyle })
    .backdropBlur(overlayBackdropBlur('bar'))
    .attributeModifier(materialModifier('bar'))
    .accessibilityText(str('cp_header_a11y', this.titleText, this.subtitleText))
    .onClick((): void => {
      if (this.headerState === 'error') {
        this.onResolveIdentity();
      } else {
        this.onOpenProfile();
      }
    })
    // stackBuilder 覆盖整条标题栏，给 HDS 的原生返回键和菜单各留出一格。
    .margin({ left: 62, right: 62, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }
}
