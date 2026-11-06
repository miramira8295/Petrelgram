// 气泡玻璃层的几何缓存。
//
// 【为什么单独成类】玻璃背景要跟着"内容布局完成后的实际宽高"走，而内容是普通
// 布局节点、没有可订阅的尺寸状态。之前的做法是在组件里放一个 @Local 记号
// （glassStamp）当"尺寸换过了"的信号，再让部分属性间接读它——更新关系不直观，
// 范围也难界定：谁读了谁才更新，漏读就漏更新。
//
// 这里把"几何"本身做成可观测对象：
//   · 父组件只在真正测量到新尺寸时写 setSize()，同值不写；
//   · 背景相关属性直接读 geo.w / geo.h，依赖关系就是字面意思；
//   · @Trace 是属性级依赖，写 geo.w 只重算读了它的属性，不会重跑内容 build，
//     也不会反过来影响布局（尺寸只从布局结果写进来，不从这里流回布局）。
//
// 复用语义：实例是普通成员，不随 aboutToReuse 重置；复用时由 aboutToReuse
// 用上次实测值 setSize()（同值 no-op）。颜色、方向、圆角这些**不在这里**——
// 它们由 msg / env 直接决定，复用时的整棵重建天然会重新求值，不会沿用旧外观。
@ObservedV2
export class BubbleGlassGeometry {
  @Trace w: number = 0;
  @Trace h: number = 0;

  // 只在真的变化时写：@Trace 写同值虽然会被框架去重，但显式守卫能让调用点
  // 一行看出"这里不会产生通知"。
  setSize(w: number, h: number): void {
    if (w === this.w && h === this.h) {
      return;
    }
    this.w = w;
    this.h = h;
  }

  get ready(): boolean {
    return this.w > 0 && this.h > 0;
  }
}
