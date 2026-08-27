import {
  HdsNavDestination, HdsNavDestinationTitleMode, HdsNavigationMenuItemOptions,
  TitleBarContentOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { readableContentWidth } from '../../util/contentWidth';
import { logE } from '../../util/log';

// 设置类子页面的外壳 —— HdsSubPage 的 HdsNavDestination 版本。
//
// 对外接口和 HdsSubPage **逐字段相同**（title / subTitle / pageBackground /
// onBack / menuItems / scroller / content），所以调用页迁移时只需要把组件名
// 换掉，其余一个字不用动。两者并存：还没迁的页面继续用 HdsSubPage。
//
//   HdsSubDestination({ title: $r('app.string.settings_media'), scroller: this.scroller }) {
//     Scroll(this.scroller) { ... }
//   }
//
// ┌────────────────────────────────────────────────────────────────────────┐
// │ 标题在 MINI 栏里，和返回键同一行                                           │
// └────────────────────────────────────────────────────────────────────────┘
// HdsNavDestinationTitleMode 只有 MINI(56vp) 和 MODAL 两档，没有 FREE（枚举声明
// 见 @hms.hds.hdsBaseComponent.d.ets:864）。这里曾经为了保住大标题，做成
// 「MINI 栏只放返回键 + bottomBuilder 里自己画一行 24fp 的大标题」，还试过用
// dynamicHideTitleBar 做"大标题滚走、小标题浮现"（做不到：它只有单向隐藏，
// 没有任何钩子让另一块浮现，且文档写明配了动态显隐就不能切标题模式）。
//
// 四个一级页签在 issue #111 里统一成 MINI（标题与图标同一行）之后，子页再留一行
// 大标题就成了全应用唯一的例外，用户问"顶部的文字和返回按钮为啥不在一行内"。
// 现在标题/副标题直接交给 MINI 栏，自绘那一行连同它的常量一起删了。
//


@Component
export struct HdsSubDestination {
  // 标题栏的材质档位读的是设置里的「光感等级」，而 titleBarStyle 是普通函数、
  // 订阅不了 AppStorage。订阅这个纪元，用户改了设置这一层才会重绘（和 HdsSubPage
  // 同一套办法）。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // 窗口宽（不是屏幕宽），分屏 / 悬浮窗 / 折叠屏改变窗口时 EntryAbility 的
  // windowSizeChange 会刷新它。平板上用来给内容限宽——见 util/contentWidth。
  @StorageProp('screenWidthVp') private screenW: number = 360;
  @Prop title: ResourceStr;
  // 空串表示不显示副标题。
  @Prop subTitle: ResourceStr = '';
  @Prop pageBackground: ResourceColor = $r('app.color.page_bg');
  // 返回键的动作。默认**出 Navigation 栈**；有离场动画/需要拦截的页面自己传。
  //
  // 【和 HdsSubPage 唯一的行为差别，也是这个文件最容易写错的地方】
  // HdsSubPage 的默认值是 router.back()。放到 NavDestination 上那是错的：
  // router.back() 弹的是 router 页栈，而本页已经不是 router 页——router 栈里
  // 只剩 Index 一层，弹掉的就是 Index，现象是**点返回箭头直接退到桌面**
  // （Task 7 修复轮 1 在设备上实测过）。所以这里必须出 Navigation 栈。
  onBack: () => void = (): void => { this.popSelf(); };
  // 右上角的图标按钮，最多三个（HDS 自己会把多的收进"更多"）。
  //
  // 必须是 @Prop：调用页会按自己的状态重新算这组菜单项（AccountEditPage 的保存
  // 勾在 loading 期间禁用、加载完再启用）。没有装饰器的成员只在构造时从父组件
  // 拿一次值、之后再不同步，勾就永远停在第一帧的禁用态（issue #165）。
  @Prop menuItems: HdsNavigationMenuItemOptions[] = [];

  // ┌──────────────────────────────────────────────────────────────────────┐
  // │ router 页生命周期 / 入参的转发入口                                     │
  // └──────────────────────────────────────────────────────────────────────┘
  // 这四个回调都挂在外壳内部的 HdsNavDestination 上，调用页够不着，只能由外壳
  // 转发。映射关系（router 页 → NavDestination）：
  //   onPageShow      → onShown
  //   onPageHide      → onHidden
  //   onBackPress     → onBackPressed
  //   router.getParams() → onReady(ctx.pathInfo.param) → onRouteParams
  //
  // 【默认值为什么保证已经迁过来的页面零变化】它们一个都没传这四个 Prop：
  //   · onShown / onHidden 注册一个空 lambda，与不注册该属性无区别；
  //   · onBackPressed 返回 **false** 就是"本页不拦截"，返回键交回 NavDestination
  //     的默认处理（出栈）——与根本不注册这个属性等价。返回 true 才是拦截。
  //   · onRouteParams 空实现，不读也不写任何状态。
  // 所以这四行是纯增量，不动既有页面的任何一条路径。
  onShown: () => void = (): void => {};
  onHidden: () => void = (): void => {};
  // 返回 true 表示本页自己消化了这次返回（例如先关掉一个浮层），不出栈。
  onBackPressed: () => boolean = (): boolean => false;
  // 路由参数就绪。**必须用这个回调而不是在 aboutToAppear 里读**：onReady 实测
  // 晚于调用页的 aboutToAppear（平板 API 26，见 ChatPage 里那段实测注释），
  // 照 router 时代的位置读会拿到 undefined，现象是静默的空白页。
  //
  // 页面复用时（MOVE_TO_TOP_SINGLETON / onNewParam）onReady 可能触发不止一次，
  // 需要"只吃一次"的调用页自己加守卫——外壳不替调用页决定这件事，因为将来也
  // 可能有页面想每次都重新吃参数。
  onRouteParams: (param: Object | undefined) => void = (): void => {};
  // 本页落在**哪一条** Navigation 栈上，onReady 时转发给调用页。
  //
  // 【为什么需要它】绝大多数子页用不着：外壳默认的 onBack 已经用自己的
  // navStack 正确出栈。要用它的是那种**自己传了 onBack**、因而必须自己出栈的
  // 页面（目前只有 AccountEditPage：未保存确认框要先弹）。这类页面此前只能靠
  // 全局注册表按 tab 名硬取一条栈，而同一个页面从此可能被推到不止一条栈上
  //（AccountEditPage：设置页签的列表 / 深链推设置栈，个人资料页签的「编辑信息」
  // 推 profile 栈），硬编码的那条就会弹错栈——现象是返回键没反应。
  // 框架给的 ctx.pathStack 才是「本实例所在的栈」的唯一可靠来源。
  //
  // 纯增量：默认空 lambda，不传的十六个页面一条路径都不变。
  onNavStack: (stack: NavPathStack) => void = (): void => {};
  // 内容区的滚动控制器，必须和内容里那个 Scroll/List 用的是同一个。
  //
  // bindToScrollable 按 Scroller **对象引用**绑定，与布局层级无关——控制器被
  // 包了几层 Column 不影响它认人。
  scroller: Scroller = new Scroller();

  @BuilderParam content: () => void;

  // 本页所在的 Navigation 栈，onReady 时拿到。
  private navStack: NavPathStack | undefined = undefined;

  // 出栈。形状和 ProfilePage / ChatProfilePage / ArchivePage 里 Task 7 建立的
  // goBack() 一致：navStack 缺失时只记一条日志，**故意不回退到 router.back()**
  // ——那正是会把应用关掉的那条路，返回键"什么都不做 + 一条日志"远比退到桌面好。
  private popSelf(): void {
    const stack: NavPathStack | undefined = this.navStack;
    if (stack === undefined) {
      // navStack 由 onReady(ctx.pathStack) 填，而 onReady 必先于本页可见，所以
      // 这一支不该发生。
      logE('HdsSubDestination.popSelf: navStack missing, back ignored');
      return;
    }
    // pop() 弹的就是本页这一层。栈空时它返回 undefined，但那意味着"本页正显示
    // 却不在栈里"，不可能发生，故不另做处理。
    stack.pop();
  }




  // 标题和副标题直接交给 MINI 栏：和返回键同一行。
  //
  // 曾经是「MINI 栏只放返回键 + 下面自己画一行大标题」（bottomBuilder），理由是
  // HdsNavDestination 的标题模式没有 FREE、不想让子页降成小标题。四个一级页签在
  // issue #111 里已经统一成 MINI（标题与图标同一行），子页再留一行大标题就成了
  // 唯一的例外——用户问的正是"顶部的文字和返回按钮为啥不在一行内"。
  private titleBarContent(): TitleBarContentOptions {
    return {
      title: { mainTitle: this.title, subTitle: this.subTitle },
      backIcon: { action: (): void => { this.onBack(); } },
      menu: { value: this.menuItems }
    };
  }

  build() {
    HdsNavDestination() {
      // 内容限宽（平板）。这一段和 HdsSubPage 里那段是同一个形状，理由也一样，
      // 照抄过来是为了迁移前后不出现观感差异：外层铺满、负责居中，内层才是被
      // 限宽的那一层。
      //
      // 【限宽只能落在外面这一层】内容是 @BuilderParam，整棵子树由调用页传进来，
      // 外壳只能从外面套。十七个调用页里九个的子树根就是那个 Scroll，另外八个是
      // 包着 Scroll 的 Column——两种情况下滚动容器都会跟着收窄。代价与缓解：
      //   · 滚动条：那十七个页面全都 scrollBar(BarState.Off)，所以"滚动条跟着
      //     缩进来"在这里不成立。
      //   · 侧边留白里拖不动页面：这是真代价，平板上留白区域不再响应滑动。要消掉
      //     它得改成"外壳提供限宽容器、调用页把内容放进去"，那是会波及全部调用页
      //     的形状变更，不在这一轮范围内。
      //
      // 【为什么两层都写 height('100%')】有调用页（InteractionSettingsPage /
      // AccentColorPage 等）在子树根上用 layoutWeight(1) 或 height('100%') 吃满
      // 内容区高度。这两层若不给定高，它们会退化成按内容高度收缩，layoutWeight(1)
      // 直接算成 0。
      //
      // 【为什么两层都显式 clip(false)】从可滚动容器一路到 HdsNavDestination，
      // 中间**每一层**都要 clip(false)，断一层内容就在标题栏下缘被切平、渐变模糊
      // 没有东西可糊（2026-08-21 首页那次排查的结论）。Column 默认本来就不裁剪，
      // 写出来是为了这两层以后被人加背景/圆角时不会顺手把裁剪打开。
      Column() {
        Column() {
          this.content();
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
        .clip(false);
      }
      .width('100%')
      .height('100%')
      // Column 默认左对齐：限了宽不居中就是把内容全堆在屏幕左边，比不限还难看。
      .alignItems(HorizontalAlign.Center)
      .clip(false);
    }
    .titleBar({
      // 两个都要，各管一头：
      //
      //   avoidLayoutSafeArea     标题栏**自己**避让系统安全区
      //   enableComponentSafeArea 标题栏成为**内容区**的安全区，内容避让它
      //
      // 官方示例里只有后者，因为那是个普通非全屏窗口。**本应用整体是全屏沉浸
      // 布局**（EntryAbility 调了 setWindowLayoutFullScreen(true)），页面的布局区
      // 本来就覆盖状态栏——这也是全应用每个页面都要手动 padding(topSafe) 的原因。
      // 所以这里必须自己避让，少了它标题栏就顶进状态栏（HdsSubPage 那边真机两次
      // 实测的结论，这里同源）。
      //
      // 但**不要**再在 HdsNavDestination 根上加 expandSafeArea：那会把标题栏往
      // 状态栏里推，和这一行正好对着干，两者抵消之后渐变模糊的合成也跟着废掉。
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      style: titleBarStyle(this.pageBackground),
      content: this.titleBarContent()
    })
    // 只有 MINI 和 MODAL 可选，见文件头。大标题由 bottomBuilder 补。
    .titleMode(HdsNavDestinationTitleMode.MINI)
    // 按 Scroller 对象引用绑定，与布局层级无关。绑了它标题栏的渐变模糊才会跟着
    // 内容滚动生效（titleBarStyle 里的 scrollEffectOpts）。
    .bindToScrollable([this.scroller])
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
      // 调用页也要拿到同一条栈（见 onNavStack 的说明）。与下面同理：它可能在
      // onRouteParams 里直接决定退场，那时它自己的出栈动作得已经有栈可用。
      this.onNavStack(ctx.pathStack);
      // 先存栈再交参数：调用页在 onRouteParams 里可能直接决定退场，那时
      // popSelf() 得已经有栈可用。
      this.onRouteParams(ctx.pathInfo.param as Object | undefined);
    })
    // 三个转发。默认值是空操作 / 返回 false，见上面 Prop 声明处的说明。
    .onShown((): void => { this.onShown(); })
    .onHidden((): void => { this.onHidden(); })
    .onBackPressed((): boolean => { return this.onBackPressed(); })
    .width('100%').height('100%')
    .backgroundColor(this.pageBackground);
  }
}
