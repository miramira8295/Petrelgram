// 「用户的光感档位」→「HDS 的 MaterialLevel 枚举」的唯一转换点。
//
// 拆成单独一个文件，是因为标题栏（HdsNavigation 的 TitleBarStyleOptions）和
// 底栏（HdsTabs 的 barFloatingStyle）都要用，而两边都必须遵守同一条规矩：
//
//   **hdsMaterial.MaterialLevel / MaterialType 是 6.1.0(23) 起的枚举，
//     在低版本运行时里解引用会在模块加载那一刻就抛。**
//
// 所以数值下标由 materialTuning 那个纯文件算（它不 import 任何 kit），
// 换成枚举只发生在这里、且调用方必须先过版本闸（hdsFloatingAvailable /
// immersiveGradientAvailable）。v1.3.6 的启动崩溃就是模块级取了这类成员。

import { hdsMaterial, SystemMaterialParams } from '@kit.UIDesignKit';
import {
  HDS_LEVEL_EXQUISITE, HDS_LEVEL_GENTLE, HDS_LEVEL_SMOOTH
} from './materialTuning';

export function hdsLevelEnum(index: number): hdsMaterial.MaterialLevel {
  if (index === HDS_LEVEL_EXQUISITE) {
    return hdsMaterial.MaterialLevel.EXQUISITE;
  }
  if (index === HDS_LEVEL_GENTLE) {
    return hdsMaterial.MaterialLevel.GENTLE;
  }
  if (index === HDS_LEVEL_SMOOTH) {
    return hdsMaterial.MaterialLevel.SMOOTH;
  }
  return hdsMaterial.MaterialLevel.ADAPTIVE;
}

// materialType 按栏动不动分：官方样例里**滚动模糊开着的栏用 ADAPTIVE(100)、
// enableScrollEffect:false 的静态栏用 IMMERSIVE(101)**（Spatialization 样例的
// MainPage/AdaptiveTabView 是前者，DetailView/ToolBarListView 是后者）。
export function hdsMaterialEffect(levelIndex: number, immersive: boolean = false): SystemMaterialParams {
  return {
    materialType: immersive ? hdsMaterial.MaterialType.IMMERSIVE : hdsMaterial.MaterialType.ADAPTIVE,
    materialLevel: hdsLevelEnum(levelIndex)
  };
}
