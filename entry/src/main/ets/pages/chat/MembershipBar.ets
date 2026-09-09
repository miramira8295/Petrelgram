// 【自绘玻璃，不走组件级系统材质】系统已经把**组件级**的 systemMaterial 收回，
// 只有 HDS 导航级的栏（HdsNavigation 的 titleBar、HdsTabs 的 barFloatingStyle）
// 还拿得到。继续用 overlayGlassFill + overlayBackdropBlur 的面会两头落空——
// 前者按"底下还有材质在画"返回 25% 的淡色，后者按"把观感让给材质"返回 0 半径，
// 结果既没有材质也没有自己的玻璃，就是一块平板（用户 2026-09-07：
// 「会话详情底下的几个控制条实现样式和输入框不太一样」）。
// 输入框（ChatComposerInput）早已迁到 plainGlassFill + plainBackdropBlur +
// hdsVisualEffect 这一套，这里跟上，三者的档位保持各自原有的 surface 不变。
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  MEMBERSHIP_BLOCKED, MEMBERSHIP_CHECKING, MEMBERSHIP_JOINABLE, MEMBERSHIP_READONLY,
} from '../../util/membershipState';
import { MEMBERSHIP_BOT_START } from '../../util/botStart';
import {
  MEMBERSHIP_SECRET_CLOSED, MEMBERSHIP_SECRET_PENDING, secretBarTextKey
} from '../../util/secretChat';
import { str } from '../../util/strings';
import { plainBackdropBlur, plainGlassFill } from '../../util/overlayMaterial';
import { hdsVisualEffect } from '../../util/hdsPointLight';
import {
  BOTTOM_PILL_HEIGHT, BOTTOM_PILL_PADDING, bottomPillRadius
} from '../../util/bottomPill';

// 没有发言权时，输入区的位置放什么。
//
// 四种形态各一副样子：正在确认身份（转圈）、被挡在外面（一句说明）、只读频道
// （让位给静音开关）、可加入（加入按钮）。判定本身在 util/membershipState，
// 有单测；这里只按结果画。
//
// 高度要上报给页面：它决定消息列表底部留多少空，和输入框走的是同一个字段。

// 状态管理 V2（B2 批：六个 V1 宿主迁 @ComponentV2）。迁的理由不是统一风格，而是
// 前置条件：后面几批要让这个宿主直接接收 @ObservedV2 控制器实例、在 build() 里
// 读 @Trace，V1 @Component 既不能声明 @Param 也订阅不了 @Trace。本批只换体系，
// 零行为变更。
@ComponentV2
export struct MembershipBar {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅——B2 迁移更正：V2 没有 @StorageProp 的等价物，
  // 所以这里不再自订阅 MATERIAL_EPOCH，改由 ChatPage 透传（页面自己持有这个
  // 纪元 @Param，来自 V1 外壳 ChatPageEntry）。链路多两次 === 比较，无行为差。
  @Param materialEpoch: number = 0;
  // util/membershipState 的取值，外加 util/botStart 的 botStart；
  // writable 时页面根本不挂这个组件。
  // B2 迁移更正：原来是 @Prop（对复杂类型深拷贝），现在是 @Param（引用传递）。
  // 这五个都是 string/number/boolean，两者等价；@Param 只读，本组件从头到尾
  // 也没写过它们。
  @Param state: string = '';
  @Param isMuted: boolean = false;
  @Param joining: boolean = false;
  // 密聊是不是自己发起的。等待期两侧话术不同（见 util/secretChat）。
  @Param secretOutbound: boolean = false;
  // 底部让出的高度，由页面按键盘/抽屉状态算好传进来。
  @Param bottomGap: number = 0;

  // 一律 @Event：调用点传的是内联箭头函数，每次页面重建都是新闭包，@Param 的
  // !== 恒不相等会让本层白刷；@Event 不具备观测能力，正好复现迁移前普通字段的
  // 行为。空实现默认值让组件能脱离父组件独立预览。
  @Event onJoin: () => void = (): void => {};
  @Event onStartBot: () => void = (): void => {};
  @Event onToggleMute: () => void = (): void => {};

  // 底部这一层的**唯一一副轮廓**：按内容收紧的胶囊。
  //
  // 【为什么不再按状态分两种】原来只有"只读（取消静音）"那一档是收紧的胶囊，
  // 其余六档都是 `width('100%')` 的整条——同一个位置、同一种东西，宽度却随状态
  // 跳来跳去。现在统一（用户 2026-09-08：「统一样式包裹内容即可，不需要横向
  // 一整个屏幕」）。几何只写一份，内容才按状态分支。
  //
  // 点击层仍然占满底栏（见 build()），胶囊变窄不牺牲可点范围。
  //
  // 玻璃走 plainGlassFill / plainBackdropBlur / hdsVisualEffect 这三件套，
  // 它们本来就吃设置里的「样式强度 / 关闭」：关掉时回落实色 + 模糊 0，厚度
  // 走 thicknessOffset()。所以这里不需要自己判断开关。
  @Builder
  private surface() {
    Row({ space: 8 }) {
      if (this.state === MEMBERSHIP_READONLY) {
        SymbolGlyph($r(this.isMuted ? 'sys.symbol.bell' : 'sys.symbol.bell_slash'))
          .fontSize(17).fontColor([COLOR_PRIMARY]).width(17);
        Text(this.isMuted ? $r('app.string.cp_unmute') : $r('app.string.cp_mute'))
          .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
          // 17vp icon + 8vp gap + 32vp horizontal padding must fit beside the
          // label; constraining only the parent does not activate TextOverflow.
          .constraintSize({ maxWidth: 'calc(100% - 57vp)' })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      } else if (this.state === MEMBERSHIP_CHECKING) {
        LoadingProgress()
          .width(20).height(20).color(COLOR_PRIMARY);
        Text($r('app.string.cp_fetching_membership'))
          .fontSize(15).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.state === MEMBERSHIP_BLOCKED) {
        Text($r('app.string.cp_cannot_join'))
          .fontSize(16).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
      } else if (this.state === MEMBERSHIP_SECRET_PENDING ||
        this.state === MEMBERSHIP_SECRET_CLOSED) {
        // 密聊未就绪。两种都只是说明，点了没有任何动作——所以下面那条
        // enabled 的正面枚举里不列它们。
        SymbolGlyph($r(this.state === MEMBERSHIP_SECRET_PENDING
          ? 'sys.symbol.lock' : 'sys.symbol.lock_open'))
          .fontSize(17).fontColor([COLOR_TEXT_SECONDARY]);
        Text(str(secretBarTextKey(this.state, this.secretOutbound)))
          .fontSize(15).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      } else if (this.state === MEMBERSHIP_BOT_START) {
        Text($r('app.string.cp_bot_start'))
          .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
      } else {
        if (this.joining) {
          LoadingProgress()
            .width(20).height(20).color(COLOR_PRIMARY);
        }
        Text(this.joining ? $r('app.string.cp_joining') : $r('app.string.cp_join'))
          .fontSize(16).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
      }
    }
    // 几何来自 util/bottomPill，底部各条共用同一副（见那个文件的说明）。
    .constraintSize({ minHeight: BOTTOM_PILL_HEIGHT, maxWidth: '100%' })
    .padding({ left: BOTTOM_PILL_PADDING, right: BOTTOM_PILL_PADDING, top: 4, bottom: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(plainGlassFill($r('app.color.surface')))
    .borderRadius(bottomPillRadius())
    .backdropBlur(plainBackdropBlur('card'))
    .visualEffect(hdsVisualEffect('card'));
  }

  build() {
    Column() {
      Row() {
        this.surface();
      }
      // 点击层仍占满底栏，视觉胶囊变窄后也不牺牲可点范围。
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      // 只有"可加入且没在加入中"和"只读（点了是切静音）"可点。确认中、被挡住
      // 都不可点：前者点了没意义，后者点了只会失败。
      // 照抄原式的正面枚举，而不是反过来排除——反写在遇到意外状态时行为会翻转。
      .enabled((this.state === MEMBERSHIP_JOINABLE && !this.joining) ||
        this.state === MEMBERSHIP_READONLY || this.state === MEMBERSHIP_BOT_START)
      .onClick((): void => {
        if (this.state === MEMBERSHIP_READONLY) {
          this.onToggleMute();
        } else if (this.state === MEMBERSHIP_BOT_START) {
          this.onStartBot();
        } else {
          this.onJoin();
        }
      });
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 6, bottom: this.bottomGap })
    .alignItems(HorizontalAlign.Center);
  }
}
