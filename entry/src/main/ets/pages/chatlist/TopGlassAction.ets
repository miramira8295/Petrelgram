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
  @Prop embedded: boolean = false;
  @Prop plainFill: ResourceColor = Color.Transparent;
  @Prop actionSize: number = 42;
  @Prop icon: string = 'sys.symbol.more';
  @Prop busy: boolean = false;
  @Prop dark: boolean = false;
  @Prop interactive: boolean = true;
  @Prop iconColor: ResourceColor = '#7F000000';
  @Prop accentColor: ResourceColor = '#0A59F7';
  label: Resource = $r('app.string.cl_more_actions');
  onTap: () => void = (): void => {};

  // 顶栏圆钮共用 control 基准，厚度随设置变化；所有玻璃面统一不投阴影。

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
      if (!this.embedded) {
        NativeGlassHost({
          hostWidth: this.actionSize,
          hostHeight: this.actionSize,
          hostRadius: this.actionSize / 2,
          dark: this.dark,
          surface: 'control'
        });
      }
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
    .backgroundColor(this.embedded ? this.plainFill : Color.Transparent)
    .borderRadius(this.actionSize / 2)
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
