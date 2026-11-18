// 输入栏的「菜单玻璃」画布。
//
// 结论（2026-11-18 真机 + 反汇编 + 官方材料三方对齐）：
//   1. 系统沉浸材质（systemMaterial / ImmersiveMaterial）只画在白名单宿主里：
//      弹窗/菜单/bindSheet、**Toggle 承载层**、HDS 导航栏 titleBar、BarPosition.End 的底部 TabBar。
//      普通容器（Stack/Row/Column/Button/Search…）挂 systemMaterial 静默不渲染——
//      真机日志原文：Material inactive: out of scope.
//   2. 本文件原来走 backgroundEffect 自绘（OpenGram 的 GlassPillStyle 那条路），
//      能画，但 70% 白色底把壁纸颜色洗掉了，出来是一块灰白板，和右上角菜单对不上。
//   3. 现在改成「Toggle 当不可见画布」：Toggle 在白名单里，挂的又是菜单同一套
//      overlayMaterial('menu') 参数（ImmersiveMaterial + material_tint），
//      所以出来的就是菜单那块玻璃。材质不可用时退回 backgroundEffect 自绘。
//
// 尺寸一律用调用方量出来的绝对 vp，不用 '100%'（百分比在这一层解析不可靠，实测会偏）。
import { immersiveMaterialAvailable, OverlaySurface } from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';

@ComponentV2
export struct NativeGlassHost {
  @Param hostWidth: number = 100;
  @Param hostHeight: number = 46;
  @Param hostRadius: number = 23;
  // 深色主题换一套染色，否则玻璃在深色壁纸上会发死白（只影响降级路径）。
  @Param dark: boolean = false;
  // 材质面：与 overlayMaterial 的档位同名。'menu' = 右上角菜单那块玻璃（默认）。
  // 'viewer' 那片底永远是黑的（图片/视频查看器的控制条），需要时由调用方传。
  @Param surface: OverlaySurface = 'menu';
  // 让材质层自己吃触摸（交互光效 / 按压形变都挂在触摸上，触摸被挡就什么都不发生）。
  // 打开后：① Toggle 不再 enabled(false)；② 本组件与 Toggle 都允许命中；
  // ③ 点击交给 Toggle 调 onHostTap —— 调用方那一行图标必须 hitTestBehavior(None)，
  //    否则图标行先吃到触摸，材质层收不到按下。
  @Param tapHost: boolean = false;
  @Event onHostTap: () => void = (): void => {};

  // 材质可用：走 Toggle 承载层，参数与右上角功能菜单一致（'menu' 面）。
  private materialOn(): boolean {
    return immersiveMaterialAvailable();
  }

  private fill(): ResourceColor {
    return this.dark ? '#B32F3F52' : '#B3F8F8F8';
  }

  build() {
    Stack() {
      if (this.materialOn()) {
        // 为什么是 Toggle：内容区唯一「既在材质白名单里、又能任意定尺寸」的组件。
        // 三条硬性条件缺一不画（踩过）：① 显式 width/height；② 走 attributeModifier
        // 的 applyNormalAttribute 回调，不在 @Builder 里链式调用；③ 自己 enabled(false)
        // + hitTestBehavior(None)，不抢输入栏的点击。
        Toggle({ type: ToggleType.Button, isOn: false })
          .width(this.hostWidth)
          .height(this.hostHeight)
          .borderRadius(this.hostRadius)
          .backgroundColor(Color.Transparent)
          .enabled(this.tapHost)
          .focusable(false)
          .hitTestBehavior(this.tapHost ? HitTestMode.Default : HitTestMode.None)
          .onClick((): void => { if (this.tapHost) { this.onHostTap(); } })
          .accessibilityLevel('no-hide-descendants')
          // flat=false：保留材质自带的外投阴影。
          // 这一层「沿圆角糊出去的白光」正是菜单面板边缘那圈光晕，用户认的 19:13 版就带着它；
          // 之前用 flat=true 去掉后整体变成一块扁平塑料片，才被判定为「搞回去了」。
          .attributeModifier(materialModifierWhen(this.surface, true, false));
      } else {
        // 降级：材质不可用（API < 26 / 设备不支持 / 用户把厚度调到关闭）时自绘。
        Row()
          .width(this.hostWidth)
          .height(this.hostHeight)
          .borderRadius(this.hostRadius)
          .backgroundColor(this.fill())
          .backgroundEffect({ radius: 36, saturation: 1.12, brightness: 1.0 })
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no-hide-descendants');
      }
    }
    .width(this.hostWidth)
    .height(this.hostHeight)
    .position({ x: 0, y: 0 })
    .hitTestBehavior(this.tapHost ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.tapHost ? 'auto' : 'no-hide-descendants');
  }
}
