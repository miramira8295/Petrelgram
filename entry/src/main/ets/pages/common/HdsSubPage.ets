import { LengthMetrics, router } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode
} from '@kit.UIDesignKit';
import {
  TITLE_BLUR_END_VP, TITLE_BLUR_START_VP, titleScrollEffectType
} from '../../util/hdsTitleBar';

// 设置类子页面的外壳：HdsNavigation 大标题 + 返回键 + 滚动渐变模糊。
//
// 十六个子页面的顶栏本来长得几乎一样——返回箭头（44×44）加一行 22px 粗体
// 标题——各写各的。抽成一个组件不是为了省那几行，是为了把**容易写错的地方
// 收在一处**：
//
//   avoidLayoutSafeArea / enableComponentSafeArea 这对字段都默认 false 且管的
//   是两件不同的事，漏一个标题栏就顶进状态栏（设置页真机踩过）；
//   内容区必须 clip(false)，否则内容不会穿到标题栏底下，渐变模糊无从模糊起；
//   bindToScrollable 要拿到内容那个 Scroll 的控制器，否则标题栏不会收缩。
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
      this.content();
    }
    .titleBar({
      // 两个都要，各管一头：前者让标题栏自己避开状态栏，后者让内容区避让
      // 标题栏。都默认 false，漏掉前者标题栏会顶进状态栏里。
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          // 有 IMMERSIVE_GRADIENT_BLUR（API 23+）就用，否则退到 GRADIENT_BLUR。
          scrollEffectType: titleScrollEffectType(),
          blurEffectiveStartOffset: LengthMetrics.vp(TITLE_BLUR_START_VP),
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BLUR_END_VP)
        },
        originalStyle: { backgroundStyle: { backgroundColor: this.pageBackground } }
      },
      content: {
        title: { mainTitle: this.title, subTitle: this.subTitle },
        backIcon: { action: (): void => { this.onBack(); } },
        menu: { value: this.menuItems }
      }
    })
    // 子页面都有返回键——这正是它们和设置/联系人那两个一级页面的区别。
    .titleMode(HdsNavigationTitleMode.FREE)
    .bindToScrollable([this.scroller])
    .width('100%').height('100%')
    .backgroundColor(this.pageBackground)
    // 背景色靠 expandSafeArea 才会延伸到状态栏和导航区底下（官方的
    // 「组件安全区方案」：布局仍在安全区内，绘制延伸出去）。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
