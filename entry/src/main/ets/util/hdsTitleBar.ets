// HDS 导航标题栏的滚动模糊档位。
//
// HdsNavigation 自带「标题栏随内容区滚动的动态模糊」，档位由 ScrollEffectType
// 决定。四档的起始版本各不相同，而本应用 compatibleSdkVersion 是 6.0.0(20)：
//
//   COMMON_BLUR              5.1.0(18)
//   GRADUAL_BLUR             6.0.0(20)
//   GRADIENT_BLUR            6.0.0(20)   ← 我们的底线能拿到的最好一档
//   IMMERSIVE_GRADIENT_BLUR  6.1.0(23)   ← issue #44 点名的那一档
//
// 所以只能"有就用、没有就退"，而不能直接写死最高那档。
//
// **绝不能在模块级解引用 ScrollEffectType。** 这不是谨慎过度：v1.3.6 的启动
// 崩溃就是 overlayMaterial 在模块级取 uiMaterial.ImmersiveStyle.ULTRA_THIN
// 造成的——低版本上那个对象根本不存在，取成员在模块加载那一刻就抛，而模块被
// 几十个页面引用，结果是整个应用起不来。这里照 overlayMaterial 的写法办：
// 版本号先比，枚举只在函数体里、确认版本够了之后才碰。

import { deviceInfo } from '@kit.BasicServicesKit';
import { LengthMetrics } from '@kit.ArkUI';
import {
  BlurStrategy, HdsNavigationTitleBarStyle, ScrollEffectType, SystemMaterialParams,
  TitleBarStyleOptions
} from '@kit.UIDesignKit';
import { hdsMaterialEffect } from './hdsMaterialLevel';
import { hdsMaterialLevelIndex, materialOff } from './overlayMaterial';

// IMMERSIVE_GRADIENT_BLUR 的起始 API 版本。hdsMaterial 的 MaterialType /
// MaterialLevel 同样是 6.1.0(23) 起，共用这个门槛。
const IMMERSIVE_GRADIENT_BLUR_API: number = 23;

// deviceInfo 返回的是设备常量，官方建议只读一次缓存起来。读的是数字，
// 不涉及任何高版本符号，模块级安全。
const apiVersion: number = deviceInfo.sdkApiVersion;

export function immersiveGradientAvailable(): boolean {
  return apiVersion >= IMMERSIVE_GRADIENT_BLUR_API;
}

// 标题栏用哪一档模糊。函数而不是常量——见文件头那段。
export function titleScrollEffectType(): ScrollEffectType {
  return immersiveGradientAvailable()
    ? ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
    : ScrollEffectType.GRADIENT_BLUR;
}

// 模糊从滚动多少距离开始生效、到多少距离完全生效。官方示例用的是 0 → 20vp，
// 抽成常量是为了各页面口径一致：同一个应用里两个页面的标题栏在不同滚动距离上
// 变实，看着像 bug。
export const TITLE_BLUR_START_VP: number = 0;
export const TITLE_BLUR_END_VP: number = 20;

// 标题栏的沉浸光感（官方《沉浸光感》「整体框架适配」：HDS 组件通过
// systemMaterialEffect 一个属性即可，且始终跟随最新规范）。
//
// **字段本身放着 undefined 无害**——它只是个对象属性，不是要在低版本上取方法。
// 真正危险的是 hdsMaterial 的两个枚举（同样 6.1.0(23) 起），所以解引用收在
// hdsMaterialLevel 里，且必须先过 immersiveGradientAvailable() 这道版本闸
// （文件头写过：MaterialType / MaterialLevel 和 IMMERSIVE_GRADIENT_BLUR 共用
// 23 这个门槛）。
//
// 用户把材质厚度调到「关闭」时不给：那个开关的语义是"所有面都不要材质"，
// HDS 自己画的栏不该是例外。等级则接用户调的光感档（四档一一对应）。
function titleMaterialEffect(immersive: boolean): SystemMaterialParams | undefined {
  if (!immersiveGradientAvailable() || materialOff()) {
    return undefined;
  }
  return hdsMaterialEffect(hdsMaterialLevelIndex(), immersive);
}

function barStyle(background: ResourceColor, mainTitleColor: ResourceColor): HdsNavigationTitleBarStyle {
  return {
    backgroundStyle: { backgroundColor: background },
    contentStyle: {
      titleStyle: {
        mainTitleColor: mainTitleColor,
        subTitleColor: $r('app.color.text_secondary')
      },
      menuStyle: {
        backgroundColor: $r('app.color.surface_alt'),
        iconColor: $r('app.color.text_primary')
      },
      backIconStyle: {
        backgroundColor: $r('app.color.surface_alt'),
        iconColor: $r('app.color.text_primary')
      }
    }
  };
}

// mainTitleColor：首页把应用名染成强调色，其它页默认正文色。
// scrollEffect=false：**滑动时整条栏一动不动**——不随滚动量爬升模糊、也不换
// 背板。观感全部由材质提供（因此 materialType 换成 IMMERSIVE，见
// hdsMaterialEffect 的注释）。会话页用的是这一档：那一页的列表是贴底锚定的，
// 用户往上滑是在翻历史，栏跟着变反而碍事。
export function titleBarStyle(background: ResourceColor,
  mainTitleColor: ResourceColor = $r('app.color.text_primary'),
  scrollEffect: boolean = true): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: scrollEffect,
      // 有 IMMERSIVE_GRADIENT_BLUR（API 23+）就用，没有退到 GRADIENT_BLUR。
      scrollEffectType: titleScrollEffectType(),
      blurEffectiveStartOffset: LengthMetrics.vp(TITLE_BLUR_START_VP),
      blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BLUR_END_VP)
    },
    // **静止时不透明，滚过阈值后才变玻璃——这是 HDS 的既定模型，不是 bug。**
    //
    // 官方示例里 originalStyle 的背景就是不透明的 ohos_id_color_background，
    // 只有 scrollEffectStyle 才是 ..._transparent。模糊是"内容滑到标题栏底下"
    // 这件事的表现，内容还没滑上来的时候没有东西可透，自然也就不该透。
    //
    // 曾经把静止态也改成透明、并额外加了 systemMaterialEffect 与 blurStrategy
    // ——那两项官方示例里根本没有。结果是两套机制打架：材质要自己的背板，
    // scrollEffect 要按滚动量换背板，最后整块发实，反而比不加还糟。剥回官方
    // 形状之后，滚动时的渐变模糊才是干净的。
    originalStyle: barStyle(background, mainTitleColor),
    scrollEffectStyle: barStyle(Color.Transparent, mainTitleColor),
    // **这次只加这一项，背板一个字没动。** 上一次失败是三改齐上（originalStyle
    // 改透明 + systemMaterialEffect + blurStrategy），分不清是谁的锅。官方样例
    // 里连 originalStyle / scrollEffectStyle 都不设、背板整个交给材质——那是
    // 下一步要单独试的，先看这一刀本身够不够。
    systemMaterialEffect: titleMaterialEffect(!scrollEffect),
    // **模糊恒定，不随滑动变弱。**
    //
    // BlurStrategy 三档 ENABLE(0) / DISABLE(1) / ADAPTIVE(2)，不给时走的是
    // 自适应——系统按性能/滚动状态自己把模糊调弱，用户报的「滑动的时候会变弱」
    // 就是它。ENABLE 是钉死。
    //
    // 这个枚举和字段都是 6.0.0(20)，**不需要版本闸**（和 systemMaterialEffect
    // 那两个 23+ 的枚举不同）。
    //
    // 历史注记：blurStrategy 在上一次失败的尝试里出现过，但那次是三改齐上
    // （originalStyle 改透明 + 材质 + 它），分不清是谁的锅。这次背板没动，
    // 只加这一项。
    blurStrategy: BlurStrategy.ENABLE
  };
}
