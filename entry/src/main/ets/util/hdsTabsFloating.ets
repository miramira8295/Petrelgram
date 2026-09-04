// HdsTabs 悬浮胶囊样式（barFloatingStyle）的**唯一**出口。
//
// 理由和 navFullScreenModifier / materialModifier 一模一样：`barFloatingStyle`
// 是 6.1.0(23) 起的属性，而本工程 compatibleSdkVersion 是 6.0.0(20)。低版本运行时里
// **这个方法根本不存在，取它那一步就抛**——不是"传 undefined 会被忽略"能救的，
// 参数都还没轮到求值。1.4.2 登录后进主界面必崩就是这类坑。
//
// 所以出口收在 AttributeModifier 里，apply 时先问版本，不够就一次都不碰
// instance.barFloatingStyle。低版本上底栏仍然是 HdsTabs，仍然有 barOverlap 的
// 浮层（那是 20 就有的），只是不是胶囊形态——不需要第二套实现。
//
// **枚举也只在版本够了之后才解引用**：hdsMaterial.MaterialType / MaterialLevel
// 同样是 23 起，模块级取成员会在加载时就抛（见 util/hdsTitleBar 文件头记的
// v1.3.6 启动崩溃）。

import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsTabsAttribute, SystemMaterialParams } from '@kit.UIDesignKit';
import { hdsMaterialLevelIndex, materialOff } from './overlayMaterial';
import { hdsMaterialEffect } from './hdsMaterialLevel';

// barFloatingStyle / miniBar / systemMaterialEffect / adaptToHandedness 共用这个门槛。
export const HDS_FLOATING_API: number = 23;

export function hdsFloatingAvailable(): boolean {
  return deviceInfo.sdkApiVersion >= HDS_FLOATING_API;
}

export interface HdsTabsFloatingOptions {
  // 胶囊与屏幕底边的距离，通常给手势条高度。
  bottomMargin: number;
  // 胶囊两侧留白。**不给的话 HDS 画的是接近满宽的胶囊**，比我们自绘那条宽出
  // 一大截（用户实测："拉长了"）。这里接回原来那套算法（util/mainTabsWidth 的
  // dockSidePadding：按"每格宽度保持不变"反推，藏掉一格就把那格的宽度均摊到
  // 两侧留白里，issue #135），比例和迁移前一致。
  sideMargin: number;
  // 迷你栏的内容。null = 这一刻没有正在播放，不挂 miniBar。
  miniBar: ComponentContent<Object> | null;
  // 宽屏上底栏跟随握持手左右移动（智感握姿）。
  adaptToHandedness: boolean;
  // 侧边竖排时页签栏的宽度；横排（悬浮胶囊）时传 null。
  //
  // **横排必须一次都不碰组件级的 barWidth。** 官方文档里这是两个不同的东西：
  //
  //   · HdsTabs 的属性 `barWidth(value: Length)` —— 设的是 **TabBar 节点**的宽度，
  //     「设置属性 vertical 为 false 时，默认值为 HdsTabs 组件的宽度」；
  //   · `HdsTabsFloatingStyle.barWidth`（HdsBarWidthRangeOptions） —— 设的才是
  //     **悬浮胶囊**的分档宽度，「页签个数大于等于 4 时，页签栏最大宽度不超过
  //     328vp」。
  //
  // 悬浮样式下 HDS 会把 TabBar 收成胶囊那么宽；外面再写一句 barWidth('100%')
  // 就把这一步覆盖回整宽——格子行铺满屏幕、胶囊仍是它自己的宽度，两者对不齐。
  // 真机实测：胶囊只裹住右边两格，「聊天」「联系人」露在外面直接压在会话列表上。
  //
  // 想调胶囊宽度请走 HdsTabsFloatingStyle.barWidth，不要走组件属性。
  sideBarWidth: number | null;
  // 竖排（侧边页签）时整套悬浮样式都不应用。
  // 官方约束：悬浮样式仅在 barOverlap=true、**vertical=false**、
  // barPosition=End 三者同时满足时生效——大屏挪到侧边之后这三条不再成立，
  // 继续设它只会让 HdsTabs 拿到一组自相矛盾的配置。
  floating: boolean;
  // 胶囊上方那层渐变遮罩的颜色。HdsTabs 默认会铺一层浅色渐变，让内容在胶囊
  // 后面淡出——但压在壁纸上就是一大片白雾（用户："能不这么白吗"）。
  // 传透明即可关掉；`HdsTabsBackgroundStyle` 只有 maskColor / maskHeight 两个字段。
  gradientMaskColor: ResourceColor;
  // **材质纪元**。本身不参与计算，但必须由调用方读进来：materialOff /
  // hdsMaterialLevelIndex 都是普通函数、订阅不了 AppStorage，只有把纪元读进
  // build() 的依赖里，用户改了厚度/光感这条属性才会重新 apply（和
  // materialModifierWhen 的缓存分代是同一个理由）。
  epoch: number;
}

export class HdsTabsFloatingModifier implements AttributeModifier<HdsTabsAttribute> {
  private readonly options: HdsTabsFloatingOptions;

  constructor(options: HdsTabsFloatingOptions) {
    this.options = options;
  }

  applyNormalAttribute(instance: HdsTabsAttribute): void {
    // 宽度先处理：它与版本闸、悬浮样式都无关，而且横排时**必须不设**（见
    // sideBarWidth 的说明）。
    if (this.options.sideBarWidth !== null) {
      instance.barWidth(this.options.sideBarWidth);
    }
    // 版本不够：一次都不碰这个方法，包括"清除"那一支。
    if (!hdsFloatingAvailable()) {
      return;
    }
    // 侧边竖排页签：悬浮样式的三个前置条件不再成立，整套不应用。
    if (!this.options.floating) {
      return;
    }
    const mini: ComponentContent<Object> | null = this.options.miniBar;
    // **用户把材质厚度调到「关闭」时不挂 systemMaterialEffect**：那个开关的
    // 语义就是"所有面都不要材质"，HDS 自己画的栏不该是例外。胶囊形态和
    // barBottomMargin 保留——那是布局，不是材质。
    const off: boolean = materialOff();
    // 等级接用户在「外观」里调的光感档，不再写死 ADAPTIVE。
    const effect: SystemMaterialParams | undefined =
      off ? undefined : hdsMaterialEffect(hdsMaterialLevelIndex());
    if (mini === null) {
      instance.barFloatingStyle({
        barBottomMargin: this.options.bottomMargin,
        barSideMargin: this.options.sideMargin,
        gradientMask: { maskColor: this.options.gradientMaskColor },
        adaptToHandedness: this.options.adaptToHandedness,
        systemMaterialEffect: effect
      });
      return;
    }
    instance.barFloatingStyle({
      barBottomMargin: this.options.bottomMargin,
      barSideMargin: this.options.sideMargin,
      gradientMask: { maskColor: this.options.gradientMaskColor },
      adaptToHandedness: this.options.adaptToHandedness,
      systemMaterialEffect: effect,
      miniBar: { miniBarBuilder: mini }
    });
  }
}
