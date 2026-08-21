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
  TitleBarStyleOptions, hdsMaterial
} from '@kit.UIDesignKit';
import {
  LIGHT_DEFAULT, LIGHT_EXQUISITE, LIGHT_GENTLE, LIGHT_SMOOTH, normalizeLightLevel
} from './materialTuning';
import { KEY_MATERIAL_LIGHT, KEY_POWER_ACTIVE } from '../store/AppSettings';

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

// 标题栏的完整样式。**每个用 HdsNavigation 的地方都必须走这里。**
//
// 起因是一个真机上很显眼的问题：只配了 backgroundStyle、没配 contentStyle 时，
// 标题、副标题、菜单图标、返回箭头全部用 HDS 的默认色，而那套默认色**不跟随
// 应用的深浅色模式**——夜间模式下标题还是深色，压在深色背板上几乎看不见。
// 官方示例里这几项是逐个显式给的，我第一版照抄了 scrollEffectOpts 却漏掉了
// contentStyle，二十个页面于是一起中招。
//
// 颜色一律用 app.color.*：这些资源在 resources/dark 下有对应值，跟随模式是
// 资源系统免费给的，不需要在代码里判断。
//
// originalStyle 和 scrollEffectStyle 都要给：前者是内容还没滚动时的样子，后者是
// 滚过 blurEffectiveEndOffset 之后的样子。只给前者的话，滚起来会跳回默认色。
// 标题栏的沉浸材质（毛玻璃 + 光影）。
//
// materialTuning 里那句"官方那三档 EXQUISITE/GENTLE/SMOOTH 是 UI Design Kit 给
// HDS 导航/页签用的 systemMaterialEffect，本应用够不着"——现在够得着了，因为
// 标题栏本身就是 HDS 组件。而且那三档的名字和设置里「光感等级」的档位一一对应，
// 直接把用户已有的选择接过来，不必再造一个开关。
//
// 6.1.0(23) 起才有；低于这个版本返回 undefined，标题栏退回纯色背板。枚举只在
// 函数体里解引用（v1.3.6 启动崩溃的教训）。
function titleBarMaterial(): SystemMaterialParams | undefined {
  if (apiVersion < IMMERSIVE_GRADIENT_BLUR_API) {
    return undefined;
  }
  // 省电模式下不上材质：它是纯观感，而这一档的用户诉求是省电。
  if (AppStorage.get<boolean>(KEY_POWER_ACTIVE) ?? false) {
    return undefined;
  }
  const level: string = normalizeLightLevel(
    AppStorage.get<string>(KEY_MATERIAL_LIGHT) ?? LIGHT_DEFAULT);
  let materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  if (level === LIGHT_EXQUISITE) {
    materialLevel = hdsMaterial.MaterialLevel.EXQUISITE;
  } else if (level === LIGHT_GENTLE) {
    materialLevel = hdsMaterial.MaterialLevel.GENTLE;
  } else if (level === LIGHT_SMOOTH) {
    materialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  }
  return { materialType: hdsMaterial.MaterialType.IMMERSIVE, materialLevel };
}

function materialOn(): boolean {
  return titleBarMaterial() !== undefined;
}

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
    // 材质接管时背板必须**透明**：官方《沉浸光感常见问题》写死，材质的视觉
    // 层级在 backgroundColor **之下**，不透明底色会把材质整个盖住看不见。
    // 这一条本应用在 overlayMaterial 上已经踩过一次。
    originalStyle: barStyle(materialOn() ? Color.Transparent : background),
    // 滚起来之后背板让位给模糊本身，其余颜色不变。
    scrollEffectStyle: barStyle(Color.Transparent),
    systemMaterialEffect: titleBarMaterial(),
    // ENABLE 而不是 ADAPTIVE。ADAPTIVE 是"由系统策略决定要不要模糊"，实测下来
    // 系统判成了不模糊，标题栏于是整块发实——毛玻璃根本没开。这里要的就是
    // 毛玻璃，明确要过来。
    //
    // 省电时不必在这里挡：titleBarMaterial() 已经在省电模式下返回 undefined，
    // 没有材质时这一项也就无从生效。
    blurStrategy: BlurStrategy.ENABLE
  };
}
