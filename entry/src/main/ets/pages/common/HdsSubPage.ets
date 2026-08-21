import { router } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { readableContentWidth } from '../../util/contentWidth';

// 设置类子页面的外壳：HdsNavigation 大标题 + 返回键 + 滚动渐变模糊。
//
// 十六个子页面的顶栏本来长得几乎一样——返回箭头（44×44）加一行 22px 粗体
// 标题——各写各的。抽成一个组件不是为了省那几行，是为了把**容易写错的地方
// 收在一处**：
//
//   avoidLayoutSafeArea / enableComponentSafeArea 这对字段都默认 false 且管的
//   是两件不同的事，漏一个标题栏就顶进状态栏（设置页真机踩过）；
//   内容区必须 clip(false)，否则内容不会穿到标题栏底下，渐变模糊无从模糊起；
//   bindToScrollable 要拿到内容那个 Scroll 的控制器，否则标题栏不会收缩；
//   平板上内容要限宽居中，否则一列内容被拉满 2880px（build() 里那段长注释）。
//
// 用法（尾随闭包，this 仍绑在调用页上）：
//
//   HdsSubPage({ title: $r('app.string.settings_media'), scroller: this.scroller }) {
//     Scroll(this.scroller) { ... }
//   }
//
// scroller 由调用页自己 new 并同时给 Scroll —— 壳子拿不到调用页 Scroll 的
// 控制器，只能这样把两头接上。

@Component
export struct HdsSubPage {
  // 标题栏的材质档位读的是设置里的「光感等级」，而 titleBarStyle 是普通函数、
  // 订阅不了 AppStorage。订阅这个纪元，用户改了设置这一层才会重绘（和别处
  // 同一套办法）。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // 窗口宽（不是屏幕宽），分屏 / 悬浮窗 / 折叠屏改变窗口时 EntryAbility 的
  // windowSizeChange 会刷新它。平板上用来给内容限宽——见 util/contentWidth。
  @StorageProp('screenWidthVp') private screenW: number = 360;
  @Prop title: ResourceStr;
  // 空串表示不显示副标题。
  @Prop subTitle: ResourceStr = '';
  @Prop pageBackground: ResourceColor = $r('app.color.page_bg');
  // 返回键的动作。默认 router.back()；有离场动画/需要拦截的页面自己传。
  onBack: () => void = (): void => { router.back(); };
  // 右上角的图标按钮，最多三个（HDS 自己会把多的收进"更多"）。
  menuItems: HdsNavigationMenuItemOptions[] = [];
  // 内容区的滚动控制器，必须和内容里那个 Scroll/List 用的是同一个。
  scroller: Scroller = new Scroller();

  @BuilderParam content: () => void;

  build() {
    HdsNavigation() {
      // 内容限宽（平板）。两层 Column 和 Task 1 那三个 tab 是同一个形状：
      // 外层铺满、负责居中，内层才是被限宽的那一层。
      //
      // 【和三个 tab 的一处差别，是这里唯一能落的位置】
      // 三个 tab 的限宽落在 Scroll **里面**的内容 Column 上，滚动容器本身仍是
      // 满宽。这里落不到那儿：内容是 @BuilderParam，整棵子树由调用页传进来，
      // 外壳只能从**外面**套一层。十七个调用页里九个的子树根就是那个 Scroll，
      // 另外八个是包着 Scroll 的 Column——两种情况下滚动容器都会跟着收窄。
      // 代价与缓解：
      //   · 滚动条：十七个页面全都 scrollBar(BarState.Off)（已逐个 grep 核过），
      //     所以"滚动条跟着缩进来"这一条在这里不成立。
      //   · 侧边留白里拖不动页面：这是真代价，平板上留白区域不再响应滑动。
      //     要消掉它得改成"外壳提供限宽容器、调用页把内容放进去"，那是会波及
      //     十七个调用页的形状变更，不在这一轮范围内。
      //
      // 【为什么两层都写 height('100%')】
      // 有调用页（InteractionSettingsPage / AccentColorPage 等）在子树根上用
      // layoutWeight(1) 或 height('100%') 吃满内容区高度。这两层若不给定高，
      // 它们会退化成按内容高度收缩，layoutWeight(1) 直接算成 0。
      //
      // 【为什么两层都显式 clip(false)】
      // 从可滚动容器一路到 HdsNavigation，中间**每一层**都要 clip(false)，断
      // 一层内容就在标题栏下缘被切平、渐变模糊没有东西可糊（2026-08-21 首页
      // 那次排查的结论）。Column 默认本来就不裁剪，写出来是为了这两层以后被
      // 人加背景/圆角时不会顺手把裁剪打开。
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
      // 所以这里必须自己避让，少了它标题栏就顶进状态栏（真机两次实测）。
      //
      // 但**不要**再在 HdsNavigation 根上加 expandSafeArea：那会把标题栏往状态栏
      // 里推，和这一行正好对着干，两者抵消之后渐变模糊的合成也跟着废掉。状态栏
      // 那条的底色由 HdsNavigation 自己的 backgroundColor 铺——全屏布局下它本来
      // 就盖到那儿。
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      style: titleBarStyle(this.pageBackground),
      content: {
        title: { mainTitle: this.title, subTitle: this.subTitle },
        backIcon: { action: (): void => { this.onBack(); } },
        menu: { value: this.menuItems }
      }
    })
    // 子页面都有返回键——这正是它们和设置/联系人那两个一级页面的区别。
    // 强制单栏：HdsNavigation 在宽屏（平板/横屏）会自动进分栏模式，我们只拿
    // 它当标题栏容器、不用 NavDestination——分栏的结果是整页内容挤进左列、
    // 右边一片空白（平板用户报"没法用了"）。
    .mode(NavigationMode.Stack)
    .titleMode(HdsNavigationTitleMode.FREE)
    .bindToScrollable([this.scroller])
    .width('100%').height('100%')
    .backgroundColor(this.pageBackground);
  }
}
