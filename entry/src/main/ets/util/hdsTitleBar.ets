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
import { ScrollEffectType } from '@kit.UIDesignKit';

// IMMERSIVE_GRADIENT_BLUR 的起始 API 版本。
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
