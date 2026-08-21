import { router } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationMenuItemOptions, HdsNavigationTitleMode
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';

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
    .titleMode(HdsNavigationTitleMode.FREE)
    .bindToScrollable([this.scroller])
    .width('100%').height('100%')
    .backgroundColor(this.pageBackground);
  }
}
