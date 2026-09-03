import { AvatarView } from '../chatlist/AvatarView';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_ICON_ON_DARK, COLOR_ICON_ON_LIGHT,
  COLOR_TEXT_ON_LIGHT, KEY_APP_DARK } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  overlayBackdropBlur, overlayGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { str } from '../../util/strings';
import { APPEARANCE_EPOCH } from '../../util/appearance';

// 聊天页顶栏：返回、头像+名称+副标题、⋮ 菜单。整条画在 HdsNavDestination 的
// **stackBuilder** 里，HDS 只负责背板和滚动模糊。
//
// **两颗动作键为什么自绘，而不是用 HDS 的 backIconStyle / content.menu。**
// 首页（ChatListPage.topAction）早就是这么做的，理由在这一页同样成立，而且更硬：
//
//   1. HdsNavigationIconItemStyle 只有 backgroundColor / iconColor / textColor，
//      **没有模糊、没有材质**。顶栏浮在壁纸上，只靠一个底色画不出玻璃——深色模式
//      下尤其明显（用户报「深色模式两个按钮玻璃样式没有了」）。自绘才能把
//      overlayGlassFill + backdropBlur + 材质三层都挂上。
//   2. 按压反馈（stateStyles 的缩放/透明度）HDS 也不给。
//   3. **菜单展开时汉堡变叉这类高频状态，绝不能进 TitleBarContentOptions。**
//      那个对象每次重建都会让 HDS 把整条标题栏（菜单 + stackBuilder +
//      bottomBuilder）重画一遍——实测就是"点一下整条 bar 闪一下"。状态待在
//      stackBuilder 的子树里，重画的才只有那一颗键。

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
  // 菜单展开态：只用来把汉堡切成叉。真正的开关在页面那边（ChatHeaderMenuController）。
  @Prop menuShow: boolean;
  // 菜单浮层的锚点。promptAction.openMenu 按组件 id 定位，所以这颗键要挂上它。
  @Prop menuAnchorId: string;
  onBack: () => void = (): void => {};
  onMenuTap: () => void = (): void => {};
  onOpenProfile: () => void = (): void => {};
  onResolveIdentity: () => void = (): void => {};

  // 低于 API 26 自己画玻璃时底色必须半透明，否则 backdropBlur 被盖死。
  @Styles
  actionNormalStyle() {
    .backgroundColor(overlayGlassFill('bar', $r('app.color.surface')))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    // 按下时也留在玻璃上：换成不透明的 surface_alt 会让玻璃"闪一下变实心"。
    // 按压反馈由 opacity + scale 表达，不靠底色。
    .backgroundColor(overlayGlassFill('bar', $r('app.color.surface_alt')))
    .opacity(0.72)
    .scale({ x: 0.9, y: 0.9 })
  }

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
    // **和主标题同色，深浅色模式都是。** 这条规则原本只在 onLightBg 那一支生效，
    // 而 onLightBg 自己带着 `appDark &&` 的闸（见 ChatPage.chromeOnLightBg）——于是
    // 浅色模式下这整套对比度机制是关着的：副标题拿到 #8E8E93，压在「25% 白胶囊 +
    // 深色壁纸」的合成底上只有约 1:1，屏幕上就是一行看不见的字（真机
    // 2026-09-03 截图，用户报「标题下面字体颜色根本看不清」）。
    //
    // 顶栏浮在用户自己挑的壁纸上，底色**事先不可知**，所以这一层就不该出现
    // "次级灰"这种预设了底色的颜色。副标题（成员数/在线数）本来就短，和主标题
    // 同色不会喧宾夺主——层次交给字号和字重（12 常规 vs 16 加粗）。
    return this.fgPrimary();
  }

  @Builder
  backButton() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([this.fgPrimary()]);
    }
    .width(CHAT_HEADER_ACTION_SIZE)
    .height(CHAT_HEADER_ACTION_SIZE)
    .borderRadius(CHAT_HEADER_RADIUS)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    .backdropBlur(overlayBackdropBlur('bar'))
    .attributeModifier(materialModifier('bar'))
    .accessibilityText($r('app.string.cp_back_to_chat'))
    .onClick((): void => { this.onBack(); });
  }

  @Builder
  menuButton() {
    Row() {
      // 菜单展开时汉堡变叉。两个图标叠着做交叉淡入淡出 + 反向旋转，比直接
      // 替换更像"同一个东西转过去了"。SVG 是位图路径、没法真正形变，这是
      // 视觉上最接近的做法。
      //
      // 系统符号库里没有汉堡线条（list_bullet 带项目符号，不是一回事），
      // 所以横线用自带的 SVG；fillColor 能染色，深浅色主题下跟其它图标一致。
      Stack() {
        Image($r('app.media.ic_header_menu'))
          .width(18).height(18)
          .fillColor(this.fgPrimary())
          .draggable(false)
          .opacity(this.menuShow ? 0 : 1)
          .rotate({ angle: this.menuShow ? 90 : 0 })
          // animation 必须挂在**属性发生变化的那个节点**上。挂在外层 Stack
          // 上不会生效——隐式动画只作用于同一节点自身的属性变化。
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseInOut
          });
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(19).fontColor([this.fgPrimary()])
          .opacity(this.menuShow ? 1 : 0)
          .rotate({ angle: this.menuShow ? 0 : -90 })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseInOut
          });
      }
      .width(CHAT_HEADER_ACTION_SIZE).height(CHAT_HEADER_ACTION_SIZE);
    }
    .width(CHAT_HEADER_ACTION_SIZE)
    .height(CHAT_HEADER_ACTION_SIZE)
    .borderRadius(CHAT_HEADER_RADIUS)
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
    .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    })
    // 和身份胶囊同一档：半透明底 + backdropBlur 自绘玻璃，API 26 上让位给材质。
    .backdropBlur(overlayBackdropBlur('bar'))
    .attributeModifier(materialModifier('bar'))
    // 菜单浮层按这个 id 定位（ChatHeaderMenuController.open 的 targetId）。
    .id(this.menuAnchorId)
    .enabled(this.chatId !== 0)
    .accessibilityText($r('app.string.cp_more_actions'))
    .onClick((): void => { this.onMenuTap(); });
  }

  build() {
    Row({ space: 8 }) {
      this.backButton();
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
      .layoutWeight(1)
      .height(CHAT_HEADER_ACTION_SIZE)
      .padding({ left: 7, right: 12 })
      .borderRadius(CHAT_HEADER_RADIUS)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .stateStyles({ normal: this.identityNormalStyle, pressed: this.identityPressedStyle })
      // 顶栏的三个胶囊都浮在消息列表之上，正对「浮动工具栏」那一档。材质生效
      // 时会把 stateStyles 的背景色清成透明并接管边框，按压反馈仍由 stateStyles
      // 的缩放/透明度体现；'bar' 档的 applyShadow:false 让这里手调的阴影继续生效。
      .backdropBlur(overlayBackdropBlur('bar'))
      .attributeModifier(materialModifier('bar'))
      .accessibilityText(str('cp_header_a11y', this.titleText, this.subtitleText))
      .onClick((): void => {
        if (this.headerState === 'error') {
          this.onResolveIdentity();
        } else {
          this.onOpenProfile();
        }
      });
      this.menuButton();
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .margin({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }
}
