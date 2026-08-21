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
  HdsNavigationTitleBarStyle, ScrollEffectType, TitleBarStyleOptions
} from '@kit.UIDesignKit';

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

function barStyle(background: ResourceColor): HdsNavigationTitleBarStyle {
  return {
    backgroundStyle: { backgroundColor: background },
    contentStyle: {
      titleStyle: {
        mainTitleColor: $r('app.color.text_primary'),
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

export function titleBarStyle(background: ResourceColor): TitleBarStyleOptions {
  return {
    scrollEffectOpts: {
      enableScrollEffect: true,
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
    originalStyle: barStyle(background),
    scrollEffectStyle: barStyle(Color.Transparent)
  };
}
