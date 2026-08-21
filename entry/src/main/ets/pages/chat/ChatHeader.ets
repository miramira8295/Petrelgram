import { AvatarView } from '../chatlist/AvatarView';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  overlayBackdropBlur, overlayBlur, overlayGlassFill, overlayMaterial, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifier } from '../../util/materialModifier';
import { str } from '../../util/strings';

// 聊天页顶栏：返回、头像+名称+副标题、⋮ 菜单。
//
// 从 ChatPage 搬出来。它几乎全是渲染——23 个引用里只有 4 个是动作（返回、
// 打开资料、重试解析身份、展开菜单），其余都是"显示什么"。菜单内容留在页面
// （那 18 个动作只有页面做得了），用 @BuilderParam 传进来。
//
// 菜单开关是 @Link：页面里有七处要主动关它（退出选择、跳转、关页面等），
// 单向传值合不上。

export const CHAT_HEADER_ACTION_SIZE: number = 42;
export const CHAT_HEADER_RADIUS: number = 22;

@Component
export struct ChatHeader {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
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
  @Prop headerVisible: boolean;
  @Prop topSafe: number;
  @Prop pageClosing: boolean;
  @Link menuShow: boolean;

  @BuilderParam menu: () => void;
  onBack: () => void = (): void => {};
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
      LoadingProgress().width(15).height(15).color(COLOR_PRIMARY).margin({ left: 5 });
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
      LoadingProgress().width(14).height(14).color(COLOR_TEXT_SECONDARY).margin({ left: 4 });
    } else if (this.isMuted) {
      SymbolGlyph($r('sys.symbol.bell_slash'))
        .fontSize(14).fontColor([COLOR_TEXT_SECONDARY]).margin({ left: 4 });
    }
  }

  @Builder
  backButton() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
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
          .fillColor(COLOR_TEXT_PRIMARY)
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
          .fontSize(19).fontColor([COLOR_TEXT_PRIMARY])
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
    // 和左边两颗顶栏胶囊同一档：半透明底 + backdropBlur 自绘玻璃，API 26 上
    // 让位给沉浸光感。
    .backdropBlur(overlayBackdropBlur('bar'))
    .attributeModifier(materialModifier('bar'))
    .bindMenu(this.menuShow, this.menu, {
      // 菜单容器要自己透出来才看得到模糊：框架默认给的是一块不透明底板。
      // backgroundBlurStyle 是低于 API 26 时的降级，systemMaterial 是 26 起
      // 的材质，两者互斥（overlayBlur 在材质可用时返回 undefined）。
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: overlayBlur('menu'),
      systemMaterial: overlayMaterial('menu'),
      onDisappear: (): void => { this.menuShow = false; }
    })
    .enabled(!this.pageClosing && this.chatId !== 0)
    .accessibilityText($r('app.string.cp_more_actions'))
    .onClick((): void => {
      if (!this.menuShow) {
        this.menuShow = true;
      }
    });
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
        });
        Column() {
          Row() {
            Text(this.titleText)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLOR_TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1);
            this.titleAccessory();
          }
          .width('100%')
          .alignItems(VerticalAlign.Center);
          Text(this.subtitleText)
            .fontSize(12)
            .fontColor(this.headerState === 'error' ? '#E64646' : COLOR_TEXT_SECONDARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: CHAT_HEADER_ACTION_SIZE })
      .padding({ left: 7, right: 12, top: 4, bottom: 4 })
      .borderRadius(CHAT_HEADER_RADIUS)
      .shadow({ radius: 4, color: '#12000000', offsetX: 0, offsetY: 1 })
      .stateStyles({ normal: this.identityNormalStyle, pressed: this.identityPressedStyle })
      // 顶栏的三个胶囊都浮在消息列表之上，正对「浮动工具栏」那一档。材质生效
      // 时会把 stateStyles 的背景色清成透明并接管边框，按压反馈仍由 stateStyles
      // 的缩放/透明度体现；'bar' 档的 applyShadow:false 让这里手调的阴影继续生效。
      //
      // 注意：它悬浮在滚动列表上，官方明确提醒材质要逐帧重采样背后内容，
      // 这一处的滑动开销必须实测，不能想当然。
      .backdropBlur(overlayBackdropBlur('bar'))
      .attributeModifier(materialModifier('bar'))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 140),
        curve: Curve.EaseOut
      })
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
    .padding({ left: 12, right: 12, top: this.topSafe + 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.headerVisible ? 1 : 0)
    .translate({ y: this.headerVisible ? 0 : -6 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
      curve: Curve.EaseOut
    })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -5 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }
}
