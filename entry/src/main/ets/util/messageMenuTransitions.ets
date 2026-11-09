import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../store/AppSettings';

// 消息气泡长按菜单的两条 TransitionEffect 链（菜单本体 + 预览图）。
//
// 【为什么要缓存】(2026-09-11 帧 trace) 它们原先写在 .bindContextMenu 的选项
// 字面量里，于是**每次重新绑定**都要现建一遍：OPACITY.combine(scale(...))
// .animation(...) 一条链就是三个对象，两条链六个，还都要过一次 NAPI。而
// bindContextMenu 在行复用路径上每建一行就重绑一次——富气泡与轻量纯文本气泡
// 两处合计 85.5ms。
//
// 它们唯一的自变量是动效时长（跟着「平滑过渡」这个省电档位走，用户不改就不
// 变），所以按时长记住即可。
//
// **每个组件持有自己的一份**（私有字段，不是模块级单例）：TransitionEffect 是
// 要挂到具体节点上的描述对象，跨组件共用同一个实例没有官方保证，不值得赌。
export class MessageMenuTransitions {
  private duration: number = -1;
  private previewFx: TransitionEffect = TransitionEffect.IDENTITY;
  private menuFx: TransitionEffect = TransitionEffect.IDENTITY;

  private ensure(): void {
    const next: number = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180);
    if (next === this.duration) {
      return;
    }
    this.duration = next;
    this.previewFx = TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
      .animation({ duration: next, curve: Curve.FastOutSlowIn });
    this.menuFx = TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
      .animation({ duration: next, curve: Curve.FastOutSlowIn });
  }

  // 菜单预览图的入场。
  preview(): TransitionEffect {
    this.ensure();
    return this.previewFx;
  }

  // 菜单本体的入场/出场。
  menu(): TransitionEffect {
    this.ensure();
    return this.menuFx;
  }
}
