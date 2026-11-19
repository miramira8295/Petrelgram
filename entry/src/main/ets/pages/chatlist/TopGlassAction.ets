// 聊天列表顶栏那两颗圆钮（搜索 / 更多）。
//
// 【为什么单独抽成组件】「按住拖动跟手」需要每帧写位移量；ChatListPage 是整页级
// V1 组件，一次 @State 更新会让整页重渲染（交接文档里实测单次 >1ms、峰值 14.8ms）。
// 把状态关进这个只包一颗圆钮的小组件，重渲染范围就只剩这几十个节点。
//
// 按下缩放/透明度与跟手位移都写在最外层 Stack 上，这样整颗按钮（含命中区）
// 一起反馈，不会出现只有图标动、外层纹丝不动。
import { NativeGlassHost } from '../chat/NativeGlassHost';

@Component
export struct TopGlassAction {
  @Prop actionSize: number = 42;
  @Prop icon: string = 'sys.symbol.more';
  @Prop busy: boolean = false;
  @Prop dark: boolean = false;
  @Prop interactive: boolean = true;
  @Prop iconColor: ResourceColor = '#7F000000';
  @Prop accentColor: ResourceColor = '#0A59F7';
  label: Resource = $r('app.string.cl_more_actions');
  onTap: () => void = (): void => {};

  // 【圆形玻璃保留，只去掉材质外投的那层阴影】用户 2026-11-19：圆玻璃按钮要留，
  // 问题只是按钮底部多出一层「像玻璃的阴影」。那层阴影来自材质面自带的
  // applyShadow（util/overlayMaterial.ets 的 buildMaterial：'menu' 面为 true，
  // 'control' 面为 false），它会在节点下沿投一块比按钮大一圈的底板，圆边糊出
  // 一圈白晕——就是「多套了一层玻璃」的观感。
  // 所以这里改传 surface: 'control'：材质滤镜/染色/圆角/按压反馈全保留，只是不再
  // 投阴影。聊天页顶栏的返回/菜单圆钮（pages/chat/ChatHeader.ets 的 backButton）
  // 用的是同一配置，两处顶栏观感一致。

  @State private pressed: boolean = false;
  @State private grabDX: number = 0;
  @State private grabDY: number = 0;
  private grabStartX: number = 0;
  private grabStartY: number = 0;

  // 按下记原点，Move 只算与原点之差（黏在手指上），幅度夹 ±3vp；松手归零。
  private track(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressed = true;
      this.grabDX = 0;
      this.grabDY = 0;
      if (event.touches.length > 0) {
        this.grabStartX = event.touches[0].x;
        this.grabStartY = event.touches[0].y;
      }
      return;
    }
    if (event.type === TouchType.Move) {
      if (!this.pressed || event.touches.length === 0) {
        return;
      }
      const dx: number = (event.touches[0].x - this.grabStartX) * 0.18;
      const dy: number = (event.touches[0].y - this.grabStartY) * 0.18;
      this.grabDX = dx > 3 ? 3 : (dx < -3 ? -3 : dx);
      this.grabDY = dy > 3 ? 3 : (dy < -3 ? -3 : dy);
      return;
    }
    this.pressed = false;
    this.grabDX = 0;
    this.grabDY = 0;
  }

  build() {
    Stack() {
      NativeGlassHost({
        hostWidth: this.actionSize,
        hostHeight: this.actionSize,
        hostRadius: this.actionSize / 2,
        dark: this.dark,
        surface: 'control'
      });
      Row() {
        if (this.busy) {
          LoadingProgress().width(20).height(20).color(this.accentColor);
        } else {
          SymbolGlyph($r(this.icon)).fontSize(23).fontColor([this.iconColor]);
        }
      }
      .width(this.actionSize)
      .height(this.actionSize)
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.None);
    }
    .width(this.actionSize)
    .height(this.actionSize)
    .opacity(this.pressed ? 0.75 : 1)
    .scale({ x: this.pressed ? 0.92 : 1, y: this.pressed ? 0.92 : 1 })
    // 位移放在 .animation() 之后：上面按下/抬起走 130ms 缓动，位移必须即时跟手。
    .animation({ duration: 130, curve: Curve.EaseOut })
    .translate({ x: this.grabDX, y: this.grabDY })
    .enabled(this.interactive)
    .accessibilityText(this.label)
    .onTouch((event: TouchEvent): void => { this.track(event); })
    .onClick((): void => { this.onTap(); });
  }
}
