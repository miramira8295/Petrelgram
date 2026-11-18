// 【自绘玻璃，不走组件级系统材质】系统已经把**组件级**的 systemMaterial 收回，
// 只有 HDS 导航级的栏（HdsNavigation 的 titleBar、HdsTabs 的 barFloatingStyle）
// 还拿得到。继续用 overlayGlassFill + overlayBackdropBlur 的面会两头落空——
// 前者按"底下还有材质在画"返回 25% 的淡色，后者按"把观感让给材质"返回 0 半径，
// 结果既没有材质也没有自己的玻璃，就是一块平板（用户 2026-09-07：
// 「会话详情底下的几个控制条实现样式和输入框不太一样」）。
// 输入框（ChatComposerInput）早已迁到 plainGlassFill + plainBackdropBlur +
// hdsVisualEffect 这一套，这里跟上，三者的档位保持各自原有的 surface 不变。
import { chromeOutline } from '../../util/chromeOutline';
import { AvatarView } from '../chatlist/AvatarView';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { COLOR_PRIMARY } from '../../util/theme';
import { chromeIconColorOf, chromeTextColorOf } from '../../util/chatChrome';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { plainGlassFill } from '../../util/overlayMaterial';
import { NativeGlassHost } from './NativeGlassHost';
import { SystemGlassSurface } from './SystemGlassSurface';
import { str } from '../../util/strings';
import { HeaderIdentitySession } from './HeaderIdentitySession';
import { TypingIndicatorState } from './TypingIndicatorState';
import { headerTypingTextOf } from '../../util/typingIndicator';
import { emojiStatusVisible } from '../../util/emojiStatus';

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

// 状态管理 V2（B2 批：六个 V1 宿主迁 @ComponentV2）。迁移本身不为性能——它是
// **前置**：V1 @Component 既不能声明 @Param，也订阅不了 @ObservedV2 类上的
// @Trace，后面「宿主接收控制器实例、在自己的 build() 里读 @Trace」那一整套
// （B5–B13，唯一能真正缩小 ChatPage 重渲染半径的做法）落不了地。配方照既有
// 先例 25d3797（MediaViewerOverlay / ReactionSheet 那次）。
// 本文件的 @Prop 全是 string/number/boolean，V1 的「深拷贝」与 V2 的「引用
// 传递」在基本类型上等价，所以这一批是零行为变更的。
//
// 子组件都过了「V2 普通组件 → V1 **复用**组件不支持」这一关（官方混用支持表；
// 本仓实测是运行时静默失败、连编译告警都没有，整块子树一个节点都不建）：
// AvatarView 是 V1 **普通**组件（V2 → V1 普通组件：支持），TgsStickerView /
// WebmStickerView 早在 P4 批 6b 就是 @ComponentV2 了。
@ComponentV2
export struct ChatHeader {
  @Param animationsAllowed: boolean = true;
  // V2 没有 @StorageProp 的等价物（官方：V2 组件不提供 @StorageProp/@StorageLink）。
  // 三个全局键（外观纪元 / 材质纪元 / 深色模式）改由 ChatPage 透传——页面自己
  // 就持有这三个 @Param（来自 V1 外壳 ChatPageEntry）。纪元变化的路径从「本层
  // 自订阅 AppStorage」变成「ChatPageChrome → ChatPage → 本层」，多两次 ===
  // 比较，无行为差。（B2 迁移）
  @Param appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  // B2 迁移：原来是 @StorageProp(MATERIAL_EPOCH) private，见上面那条——改成由
  // ChatPage 透传的 @Param，private 去掉（@Param 要由父组件构造传参）。
  @Param materialEpoch: number = 0;
  // 顶栏浮在聊天壁纸上：深色模式 + 浅色壁纸时它其实坐在亮底上，白色前景会掉到
  // 2.22:1。由 ChatPage 算好传进来（判据见 util/chatChrome），这里只按它选前景。
  @Param onLightBg: boolean = false;
  // 浅色模式 + 暗壁纸那一侧，见 util/chatChrome.chromeOnDarkBgOf。
  @Param onDarkBg: boolean = false;
  // B2 迁移前是 @StorageProp(KEY_APP_DARK)，同样改成 ChatPage 透传。
  @Param appDark: boolean = false;
  // B8：titleText/subtitleText/headerState/avatarPath/avatarAnimPath/initials/
  // savedMessages/emojiPath/emojiFormat/isMuted/muteUpdating/profileOpening 这
  // 12 个标量 @Param 换成一个控制器引用——本组件直接持有 HeaderIdentitySession、
  // 在自己的 build()/@Builder 里读它的 @Trace。
  //
  // 副标题是这一步唯一改变"谁读"的地方：改前页面用 this.headerText().
  // subtitleText 把 subtitle/secretSubtitle 拼好再传进来，页面 build 因此订阅了
  // 这两个字段——对方在线/输入中每次翻转 subtitle，都要重跑一遍页面的
  // chatTitleBar 闭包。改后本组件在 build 里自己调 this.header.subtitleTextOf()，
  // 页面不再算 subtitleText、也就不再读 subtitle/secretSubtitle；页面仍然会算
  // titleText（confirmLeaveChat/openDeleteConfirm 等簇外读者也要用），但那是
  // 通过控制器的 titleTextOf() 现取，不再经这个组件的 @Param 转手。
  // 引用由 ChatPage 的字段初始化器 new 出来、全生命周期不变，@Require 已保证
  // 调用点必须传，不带默认值（同 TopBanners.topCard / ChatSearchBars 的写法）。
  @Require @Param header: HeaderIdentitySession;
  @Param typing: TypingIndicatorState = new TypingIndicatorState();
  @Param chatId: number = 0;
  // 菜单展开态：只用来把汉堡切成叉。真正的开关在页面那边（ChatHeaderMenuController）。
  @Param menuShow: boolean = false;
  // 菜单浮层的锚点。promptAction.openMenu 按组件 id 定位，所以这颗键要挂上它。
  @Param menuAnchorId: string = '';
  // 顶栏最右的「置顶显隐」箭头（2026-11-18 用户要求）。
  //
  // pinnedAvailable 决定这颗键存不存在：会话里一条置顶都没有时，隐藏/展示
  // 置顶条没有任何作用对象，摆一个按了没反应的箭头只会让人以为坏了。
  // pinnedBarShown 是箭头方向的唯一依据——置顶条正在显示就朝上（点=收起），
  // 已经收起就朝下（点=展开）。两者都从 TopCard 控制器的 @Trace 现取，页面
  // 那侧不做第二份状态，避免三处入口（设置开关 / 菜单项 / 这颗箭头）各记一份。
  @Param pinnedAvailable: boolean = false;
  @Param pinnedBarShown: boolean = false;
  // 五个回调一律 @Event：调用点传的是内联箭头函数，页面每重建一次都是新闭包，
  // 若用 @Param，那个 `!==` 恒不相等会让本层跟着页面的每一次重建白刷一遍；
  // @Event 不具备观测能力，正好复现迁移前「普通字段只在构造时赋值一次」的行为。
  // 空实现默认值是仓库惯例（让组件能脱离父组件独立预览）。（B2 迁移）
  @Event onBack: () => void = (): void => {};
  @Event onMenuTap: () => void = (): void => {};
  @Event onOpenProfile: () => void = (): void => {};
  @Event onResolveIdentity: () => void = (): void => {};
  // 置顶条显隐。页面那边包了 animateTo，本组件只负责把点击抛上去。
  @Event onTogglePinned: () => void = (): void => {};

  // 返回 / 菜单两颗键的按压态、菜单图标的展开态，全部显式驱动（2026-09-15）。
  //
  // 原来是 stateStyles + 键上常驻的 .animation(120)、两个图标上常驻的 .animation(180)。常驻修饰器在
  // ChatHeader **每次**重渲染时都会开隐式动画上下文，并在里面冲刷渲染任务——进会话时真实壁纸颜色到货、
  // 返回键图标换色被卷了进去，系统给符号配了一个 1.4s 的弹簧缩放（先压到 0.92 再冲到 1.02）；它下面是
  // 带 backdropBlur 的胶囊，RS 整页每帧重算模糊、关掉硬件合成，连续 1.4s（trace 20260915T174809，调用链
  // CustomNodeUpdate ChatHeader → JSAnimation duration:120 → Text paint → SetSymbolAnimation）。
  // 现在 animateTo 只包按压 / 展开这一个状态，别的更新不再进动画。
  //
  // 低于 API 26 自己画玻璃时底色必须半透明，否则 backdropBlur 被盖死；按下时也留在玻璃上（换成不透明的
  // surface_alt 会让玻璃"闪一下变实心"），按压反馈由 opacity + scale 表达。
  @Local private backPressed: boolean = false;
  @Local private menuPressed: boolean = false;
  @Local private menuIconOpen: boolean = false;
  @Local private pinnedPressed: boolean = false;
  // 身份胶囊的按压态：变换必须作用在**带玻璃的那一层**（外层 Stack），
  // 否则只有文字/头像在缩，系统材质那块玻璃纹丝不动——观感就是「没有按压」。
  @Local private identityPressed: boolean = false;
  // 「按住拖动时跟着手指走」：三颗胶囊同一时刻只可能按一颗，所以共用一套位移量。
  // 位移 = 手指相对按下点的偏移 × 0.18，夹在 ±3vp；松手归零。槽位 0=返回 1=身份 2=菜单。
  // 放在 @Local 而不是 AppStorage：本组件很小，重渲染只涉及这几十个节点。
  @Local private grabSlot: number = -1;
  @Local private grabDX: number = 0;
  @Local private grabDY: number = 0;
  private grabStartX: number = 0;
  private grabStartY: number = 0;
  @Local private typingDotPhase: number = 0;
  private typingAnimTimer: number = -1;

  aboutToAppear(): void {
    this.menuIconOpen = this.menuShow;
    this.syncTypingAnimTimer();
  }

  aboutToDisappear(): void {
    this.stopTypingAnimTimer();
  }

  @Monitor('typing.label', 'animationsAllowed')
  onTypingAnimStateChanged(): void {
    this.syncTypingAnimTimer();
  }

  private stopTypingAnimTimer(): void {
    if (this.typingAnimTimer !== -1) {
      clearInterval(this.typingAnimTimer);
      this.typingAnimTimer = -1;
    }
  }

  private syncTypingAnimTimer(): void {
    const shouldRun = this.typing.label !== '' && this.animationsAllowed;
    if (!shouldRun) {
      this.stopTypingAnimTimer();
      this.typingDotPhase = 0;
      return;
    }
    if (this.typingAnimTimer !== -1) {
      return;
    }
    this.typingAnimTimer = setInterval((): void => {
      if (this.typing.label === '' || !this.animationsAllowed) {
        this.stopTypingAnimTimer();
        return;
      }
      try {
        this.getUIContext().animateTo({
          duration: 240,
          curve: Curve.EaseInOut
        }, (): void => {
          this.typingDotPhase = (this.typingDotPhase + 1) % 3;
        });
      } catch (_e) {
        this.typingDotPhase = (this.typingDotPhase + 1) % 3;
      }
    }, 280);
  }

  private typingDotOpacity(index: number): number {
    if (!this.animationsAllowed) {
      return 1;
    }
    if (this.typingDotPhase === index) {
      return 1;
    }
    if ((this.typingDotPhase + 2) % 3 === index) {
      return 0.65;
    }
    return 0.35;
  }

  private typingDotScale(index: number): number {
    if (!this.animationsAllowed) {
      return 1;
    }
    if (this.typingDotPhase === index) {
      return 1.12;
    }
    if ((this.typingDotPhase + 2) % 3 === index) {
      return 0.92;
    }
    return 0.78;
  }

  @Monitor('menuShow')
  onMenuShowChanged(): void {
    this.getUIContext().animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
      curve: Curve.EaseInOut
    }, (): void => {
      this.menuIconOpen = this.menuShow;
    });
  }

  // 1 = 按下，0 = 抬起 / 取消，-1 = 其它（Move 不动状态）。
  private pressEdge(event: TouchEvent): number {
    if (event.type === TouchType.Down) {
      return 1;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      return 0;
    }
    return -1;
  }

  // 按住后手指移动的跟随量。按下的那一刻记原点，之后每次 Move 只算偏移，
  // 不复位——这样手指来回拖时胶囊是「黏在手指上」的，不是每帧从零抖一下。
  private trackGrab(event: TouchEvent, slot: number): void {
    if (event.type === TouchType.Down) {
      this.grabSlot = slot;
      this.grabDX = 0;
      this.grabDY = 0;
      if (event.touches.length > 0) {
        this.grabStartX = event.touches[0].x;
        this.grabStartY = event.touches[0].y;
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (this.grabSlot !== slot || event.touches.length === 0) {
        return;
      }
      const dx: number = (event.touches[0].x - this.grabStartX) * 0.18;
      const dy: number = (event.touches[0].y - this.grabStartY) * 0.18;
      this.grabDX = dx > 3 ? 3 : (dx < -3 ? -3 : dx);
      this.grabDY = dy > 3 ? 3 : (dy < -3 ? -3 : dy);
      return;
    }
    this.grabSlot = -1;
    this.grabDX = 0;
    this.grabDY = 0;
  }

  private animatePress(apply: () => void): void {
    this.getUIContext().animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
      curve: Curve.EaseOut
    }, apply);
  }

  // 身份胶囊的按压数值（0.78 / 0.985×0.96）直接写在外层 Stack 的属性链上，
  // 不再放 @Styles：stateStyles 只能作用于被打的那个节点，而玻璃在它外一层。

  @Builder
  titleAccessory() {
    if (this.header.state === 'loading' || this.header.profileOpening) {
      LoadingProgress().width(15).height(15).color(this.accent()).margin({ left: 5 });
    } else if (emojiStatusVisible(this.header.emojiPath, this.header.emojiUid)) {
      if (!this.animationsAllowed) {
        // 保持标题占位，隐藏时不挂动态表情播放器。
        Row().width(18).height(18).margin({ left: 4 });
      } else if (this.header.emojiFormat === 'tgs') {
        TgsStickerView({
          tgsPath: this.header.emojiPath, boxWidth: 18, boxHeight: 18, powerCategory: 'emojiStatus'
        }).margin({ left: 4 });
      } else if (this.header.emojiFormat === 'webm') {
        WebmStickerView({
          webmPath: this.header.emojiPath, stickerUid: this.header.emojiUid,
          boxWidth: 18, boxHeight: 18, powerCategory: 'emojiStatus'
        }).margin({ left: 4 });
      } else {
        Image(`file://${this.header.emojiPath}`).draggable(false)
          .width(18).height(18).objectFit(ImageFit.Contain).margin({ left: 4 });
      }
    }
    if (this.header.muteUpdating) {
      LoadingProgress().width(14).height(14).color(this.fgSecondary()).margin({ left: 4 });
    } else if (this.header.isMuted) {
      SymbolGlyph($r('sys.symbol.bell_slash'))
        .fontSize(14).fontColor([chromeIconColorOf(this.onLightBg, this.appDark, this.onDarkBg)]).margin({ left: 4 });
    }
  }

  // B8（顺手去重，记在 B3 抽出 chromeTextColorOf/chromeIconColorOf 时留下的账）：
  // 这两个方法原来在这里各自重写了一遍 util/chatChrome 里同名纯函数逐字相同的
  // if/else——B3 把判据抽出去时漏了这一处调用点。现在直接调
  // chromeTextColorOf(this.onLightBg, this.onDarkBg) / chromeIconColorOf(this.onLightBg,
  // this.appDark) 取代，本文件不再维护第二份判据。

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
    return chromeTextColorOf(this.onLightBg, this.onDarkBg);
  }

  private activeSubtitleText(): string {
    if (this.typing.label !== '' && this.header.state !== 'error') {
      return headerTypingTextOf(this.typing.label);
    }
    return this.header.subtitleTextOf();
  }

  @Builder
  backButton() {
    // 玻璃交给系统沉浸材质（Toggle 承载层）：原来那身自绘玻璃——半透明底 +
    // backdropBlur + materialModifier + visualEffect + chromeOutline 描边——在
    // 内容区一件都画不出来，只剩一圈白描边，正是用户说的"白色轮廓线很怪"。
    Stack() {
      NativeGlassHost({
        hostWidth: CHAT_HEADER_ACTION_SIZE,
        hostHeight: CHAT_HEADER_ACTION_SIZE,
        hostRadius: CHAT_HEADER_RADIUS,
        dark: this.appDark,
        surface: 'control'
      });
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22)
          .fontColor([chromeTextColorOf(this.onLightBg, this.onDarkBg)]);
      }
      .width(CHAT_HEADER_ACTION_SIZE)
      .height(CHAT_HEADER_ACTION_SIZE)
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.None)
      .accessibilityText($r('app.string.cp_back_to_chat'));
      // 命中层：材质承载层是 enabled(false) 的 Toggle，收不到触摸，这里用一颗透明
      // Button 接管点击。它自己的 stateEffect 关掉——真机上那颗系统按压态只让玻璃
      // 变暗、不改变外框，看着像闪了一下；按压反馈统一交给外层 Stack 做位移，
      // 和已提交版本（PR #21：按下 0.9 缩放 + 78% 不透明）同一个观感。
      Button({ type: ButtonType.Circle })
        .width(CHAT_HEADER_ACTION_SIZE)
        .height(CHAT_HEADER_ACTION_SIZE)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .onTouch((event: TouchEvent): void => {
          this.trackGrab(event, 0);
          const edge: number = this.pressEdge(event);
          if (edge >= 0 && (edge === 1) !== this.backPressed) {
            this.animatePress((): void => {
              this.backPressed = edge === 1;
            });
          }
        })
        .accessibilityText($r('app.string.cp_back_to_chat'))
        .onClick((): void => { this.onBack(); });
    }
    .width(CHAT_HEADER_ACTION_SIZE)
    .height(CHAT_HEADER_ACTION_SIZE)
    .opacity(this.backPressed ? 0.72 : 1)
    .scale({ x: this.backPressed ? 0.9 : 1, y: this.backPressed ? 0.9 : 1 })
    // 按住拖动时整颗胶囊轻微跟着手指走（幅度夹在 ±3vp）。写在 .animation() 之外，
    // 位移必须即时跟手，不能带缓动，否则会拖一条尾巴。
    .translate({ x: this.grabSlot === 0 ? this.grabDX : 0, y: this.grabSlot === 0 ? this.grabDY : 0 });
  }

  @Builder
  menuButton() {
    // 与返回键同一副：材质垫底，图标行只管点击与按压反馈。
    Stack() {
      NativeGlassHost({
        hostWidth: CHAT_HEADER_ACTION_SIZE,
        hostHeight: CHAT_HEADER_ACTION_SIZE,
        hostRadius: CHAT_HEADER_RADIUS,
        dark: this.appDark
      });
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
          .fillColor(chromeTextColorOf(this.onLightBg, this.onDarkBg))
          .draggable(false)
          // 交叉淡入 + 反向旋转由 onMenuShowChanged 的 animateTo 驱动，图标上不挂常驻 .animation()
          // （理由见本组件开头按压态那段）。
          .opacity(this.menuIconOpen ? 0 : 1)
          .rotate({ angle: this.menuIconOpen ? 90 : 0 });
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(19).fontColor([chromeTextColorOf(this.onLightBg, this.onDarkBg)])
          .opacity(this.menuIconOpen ? 1 : 0)
          .rotate({ angle: this.menuIconOpen ? 0 : -90 });
      }
      .width(CHAT_HEADER_ACTION_SIZE).height(CHAT_HEADER_ACTION_SIZE);
    }
    .width(CHAT_HEADER_ACTION_SIZE)
    .height(CHAT_HEADER_ACTION_SIZE)
    .justifyContent(FlexAlign.Center)
    .enabled(this.chatId !== 0)
    .onTouch((event: TouchEvent): void => {
      this.trackGrab(event, 2);
      const edge: number = this.pressEdge(event);
      if (edge >= 0 && (edge === 1) !== this.menuPressed) {
        this.animatePress((): void => {
          this.menuPressed = edge === 1;
        });
      }
    })
    .accessibilityText($r('app.string.cp_more_actions'))
    .onClick((): void => { this.onMenuTap(); });
    }
    .width(CHAT_HEADER_ACTION_SIZE)
    .height(CHAT_HEADER_ACTION_SIZE)
    // 缩放/透明度放在外层：玻璃层是独立子节点，只缩里面的图标行会让玻璃纹丝不动，
    // 看着像"图标自己在抖"。整颗一起缩才和提交版本一致。
    .opacity(this.menuPressed ? 0.72 : 1)
    .scale({ x: this.menuPressed ? 0.9 : 1, y: this.menuPressed ? 0.9 : 1 })
    // 同返回键：位移即时跟手。
    .translate({ x: this.grabSlot === 2 ? this.grabDX : 0, y: this.grabSlot === 2 ? this.grabDY : 0 })
    // 菜单浮层按这个 id 定位（ChatHeaderMenuController.open 的 targetId）。
    .id(this.menuAnchorId);
  }

  build() {
    Row({ space: 8 }) {
      this.backButton();
      // 身份胶囊：宽度自适应（layoutWeight 1），所以用铺满模式让外壳跟住父容器，
      // 材质层再由外壳自己量到的像素铺。
      Stack() {
        SystemGlassSurface({ radius: CHAT_HEADER_RADIUS, fill: true, dark: this.appDark }) {
          Row({ space: 10 }) {
      AvatarView({
        avatarPath: this.header.avatarPath,
        // 顶栏身份胶囊自身带 backdropBlur('bar')，内部若挂载 30fps XComponent 视频纹理
        // 会每帧作废毛玻璃 FilterCache 并迫使整屏退出硬件直接合成（与 ChatRow 同理保持静态，
        // 点进资料页 ChatProfilePage 才播放大图动态头像）。
        animPath: '',
        animationPaused: !this.animationsAllowed,
        initials: this.header.initials,
        colorSeed: this.chatId,
        avatarSize: 38,
        autoDeleteTime: this.header.autoDeleteTime,
        // 「我的收藏」判定不读任何 @Trace（现查 ChatStore），本来就该在 build
        // 期间现取；不再由页面算好经 @Param 传入。
        savedMessages: this.header.isSavedMessages()
      })
        .margin({ left: -4, right: 0 });
      Column() {
        Row() {
          Text(this.header.titleTextOf())
            .fontSize(16)
            // Medium 与会话列表行的标题同一档（issue #169 第 4 条：从列表点进来群名「变粗了」）。
            .fontWeight(FontWeight.Medium)
            .fontColor(chromeTextColorOf(this.onLightBg, this.onDarkBg))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1);
          this.titleAccessory();
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
        // B8：副标题不再由页面用 headerText().subtitleText 算好传入——那样页面
        // build 就订阅了 subtitle/secretSubtitle，对方在线/输入中每次翻转都要
        // 重跑一遍页面的 chatTitleBar 闭包。本组件直接持有控制器引用，这里现读
        // 它的 @Trace 自己合成，翻转只刷新这一个 Text 节点，页面一个字都不读——
        // 这是本批性能收益的关键。
        if (this.typing.label !== '' && this.header.state !== 'error') {
          Row() {
            Row({ space: 2.5 }) {
              Circle({ width: 4.5, height: 4.5 })
                .fill(this.accent())
                .opacity(this.typingDotOpacity(0))
                .scale({ x: this.typingDotScale(0), y: this.typingDotScale(0) });
              Circle({ width: 4.5, height: 4.5 })
                .fill(this.accent())
                .opacity(this.typingDotOpacity(1))
                .scale({ x: this.typingDotScale(1), y: this.typingDotScale(1) });
              Circle({ width: 4.5, height: 4.5 })
                .fill(this.accent())
                .opacity(this.typingDotOpacity(2))
                .scale({ x: this.typingDotScale(2), y: this.typingDotScale(2) });
            }
            .alignItems(VerticalAlign.Center)
            .margin({ right: 5 })
            .flexShrink(0);
            Text(headerTypingTextOf(this.typing.label))
              .fontSize(12)
              .fontColor(this.accent())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1);
            Row({ space: 1.5 }) {
              Circle({ width: 2.2, height: 2.2 }).fill(this.accent());
              Circle({ width: 2.2, height: 2.2 }).fill(this.accent());
              Circle({ width: 2.2, height: 2.2 }).fill(this.accent());
            }
            .alignItems(VerticalAlign.Center)
            .margin({ left: 2, top: 3 })
            .flexShrink(0);
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 1 });
        } else {
          Text(this.header.subtitleTextOf())
            .fontSize(12)
            .fontColor(this.header.state === 'error' ? '#E64646' : this.fgSecondary())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 });
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
            // 置顶条的显隐键（2026-11-18 用户口径）：不单独占一颗胶囊，直接挂在
            // 身份胶囊内部的最右端——胶囊本身就是「群组名称信息展示的顶栏」，
            // 箭头属于它的附属操作。方向语义：置顶条正在显示 → 朝上，点一下收起；
            // 已经收起 → 朝下，点一下展开。
            //
            // 点击不会连带触发胶囊的资料页跳转：ArkUI 的 onClick 不向祖先冒泡，
            // 子节点消费掉就到此为止。
            if (this.pinnedAvailable) {
              Row() {
                SymbolGlyph($r(this.pinnedBarShown ? 'sys.symbol.chevron_up' : 'sys.symbol.chevron_down'))
                  .fontSize(18)
                  .fontColor([chromeTextColorOf(this.onLightBg, this.onDarkBg)]);
              }
              .width(30)
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .opacity(this.pinnedPressed ? 0.72 : 1)
              .accessibilityText(this.pinnedBarShown ? $r('app.string.cp_hide_pinned') : $r('app.string.cp_show_pinned'))
              .onTouch((event: TouchEvent): void => {
                const edge: number = this.pressEdge(event);
                if (edge >= 0 && (edge === 1) !== this.pinnedPressed) {
                  this.animatePress((): void => {
                    this.pinnedPressed = edge === 1;
                  });
                }
              })
              .onClick((): void => { this.onTogglePinned(); });
            }
          }
          .width('100%')
          .height('100%')
          // 有箭头时右内边距收窄：箭头自己占了 30vp 的命中区，再留 12 会把图标
          // 顶到离胶囊边缘太远的地方，视觉上像浮在半空。
          .padding({ left: 7, right: this.pinnedAvailable ? 4 : 12 })
          // 按压态不再用 stateStyles（那只作用于本 Row，玻璃在外层 Stack 上）。
          // 改为驱动 identityPressed，由外层 Stack 连同系统材质一起缩放/变暗。
          .onTouch((event: TouchEvent): void => {
            this.trackGrab(event, 1);
            const edge: number = this.pressEdge(event);
            if (edge >= 0 && (edge === 1) !== this.identityPressed) {
              // 过渡由外层 Stack 的 .animation() 负责，这里直接赋值，
              // 免得 animateTo 与隐式动画两层叠加。
              this.identityPressed = edge === 1;
            }
          })
          .accessibilityText(str('cp_header_a11y', this.header.titleTextOf(), this.activeSubtitleText()))
          .onClick((): void => {
            if (this.header.state === 'error') {
              this.onResolveIdentity();
            } else {
              this.onOpenProfile();
            }
          });
        }
      }
      .layoutWeight(1)
      .height(CHAT_HEADER_ACTION_SIZE)
      // 玻璃层（SystemGlassSurface 的材质承载）跟着一起缩，才是整颗胶囊的按压反馈。
      .opacity(this.identityPressed ? 0.78 : 1)
      .scale({ x: this.identityPressed ? 0.985 : 1, y: this.identityPressed ? 0.96 : 1 })
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      })
      // 位移放在 .animation() 之后：上面的缩放/透明度走 120ms 缓动，
      // 下面的跟手位移必须逐帧直达，不能被隐式动画拖慢。
      .translate({ x: this.grabSlot === 1 ? this.grabDX : 0, y: this.grabSlot === 1 ? this.grabDY : 0 });
      this.menuButton();
    }
    .width('100%')
    .padding({ left: 12, right: 12 })
    .margin({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center);
  }
}
