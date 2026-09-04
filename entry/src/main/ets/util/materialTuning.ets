// 沉浸光感的两个用户档位：浮层材质厚度、光感等级。
//
// 只做决策，不碰 uiMaterial、不碰 AppStorage——那些要设备和运行时，测不动。
// overlayMaterial.ets 负责把这里的结果翻译成真正的材质对象和降级参数。

// ── 浮层材质厚度 ──────────────────────────────────────────────────────
//
// 存的是**相对偏移**而不是绝对档位，这是有意的。每个面的厚度是分别调过的
// （顶栏胶囊超薄、输入框薄、菜单常规、弹窗超厚），绝对档位会把它们压平成
// 同一厚度——弹窗跟着顶栏一起变超薄，背后的内容就透出来了，那不是"薄"，
// 是坏了。偏移则整体平移、保住相对次序。
//
// 0 是出厂手感，界面上显示成"标准"。
// 关闭：不挂材质、不模糊，所有面纯色兜底。放在最薄档之下，只有这一处特判。
export const THICKNESS_OFF: number = -3;
export const THICKNESS_ULTRA_THIN: number = -2;
export const THICKNESS_THIN: number = -1;
export const THICKNESS_REGULAR: number = 0;
export const THICKNESS_THICK: number = 1;
export const THICKNESS_ULTRA_THICK: number = 2;
export const THICKNESS_DEFAULT: number = THICKNESS_REGULAR;

// ImmersiveStyle 的五个枚举值就是 0..4（ULTRA_THIN..ULTRA_THICK），这里按
// 下标算，由调用方查表换成枚举，避免这一层依赖 @kit.ArkUI。
const STYLE_MIN: number = 0;
const STYLE_MAX: number = 4;

// 自绘玻璃的高斯模糊半径基准值与步长。
// 步长挑 6：22 上下各两档落在 10..34，10 已经能看出玻璃、34 还没糊成一块板。
export const FALLBACK_BLUR_BASE: number = 22;
const FALLBACK_BLUR_STEP: number = 6;
// 按**档位下标**（0..4，即 ImmersiveStyle 的超薄..超厚）算半径，而不是只按用户
// 偏移算。两者的区别是"这个面自己该多厚"要不要算进去：
//
//   fallbackBlurRadius(offset)          所有面同一个数
//   fallbackBlurForIndex(styleIndex)    顶栏薄、输入框次之、菜单常规、弹窗最厚
//
// 以前只有材质那条路带面的分档（ImmersiveStyle），自绘那条一直是平的——材质
// 还在时看不出来，材质被系统收回之后就露馅了：用户把厚度调到「超薄」，输入框
// 和弹窗仍然一样厚。下标 0..4 映射到 10/16/22/28/34，中间那档正好是原来的 22。
const FALLBACK_BLUR_MIN: number = FALLBACK_BLUR_BASE - FALLBACK_BLUR_STEP * 2;

export function fallbackBlurForIndex(styleIndex: number): number {
  return FALLBACK_BLUR_MIN + clampStyle(styleIndex) * FALLBACK_BLUR_STEP;
}

function clampStyle(index: number): number {
  return Math.max(STYLE_MIN, Math.min(STYLE_MAX, index));
}

// 用户偏移只在 [-2, 2] 内有意义；越界值当作没设置，而不是让它把档位推到边上。
export function isThicknessOff(offset: number): boolean {
  return offset === THICKNESS_OFF;
}

export function normalizeThickness(offset: number): number {
  if (!Number.isFinite(offset)) {
    return THICKNESS_DEFAULT;
  }
  const rounded: number = Math.round(offset);
  if (rounded < THICKNESS_OFF || rounded > THICKNESS_ULTRA_THICK) {
    return THICKNESS_DEFAULT;
  }
  return rounded;
}

// 某个面调好的基准档位，按用户偏移平移后的实际档位。
export function shiftedStyleIndex(baseIndex: number, offset: number): number {
  return clampStyle(baseIndex + normalizeThickness(offset));
}

// 低于 API 26 时自绘玻璃的模糊半径。厚度档在这条路上也必须有效果，否则
// 老设备上这个设置就是个调了没反应的死开关。
export function fallbackBlurRadius(offset: number): number {
  return Math.max(0, FALLBACK_BLUR_BASE + normalizeThickness(offset) * FALLBACK_BLUR_STEP);
}

// ── 光感等级 ──────────────────────────────────────────────────────────
//
// 官方那三档（EXQUISITE/GENTLE/SMOOTH）是 UI Design Kit 给 HDS 导航/页签用的
// systemMaterialEffect，只作用在 HDS 组件的标题栏/页签栏上，管不到本模块负责
// 的这些自绘面（菜单容器、dock、分组栏、卡片）；ArkUI 的 ImmersiveOptions 里
// 也没有"强度"参数——强度由设备算力档和**系统设置**里的沉浸光感强弱决定，
// 应用写不了。
//
// 注：设置页从 issue #44 起用了 HdsNavigation，那一处的标题栏理论上可以设
// TitleBarStyleOptions.systemMaterialEffect。但那是 HDS 自己那一块的事，
// 和这里的四档是两套口径，别混。
//
// 所以这里按 ArkUI 真正能调的两个字段来分档：lightEffect（触点流光）和
// interactive（按压形变）。官方注明这两个"对所有算力档都生效"，不会被低端
// 设备悄悄降级掉，正适合做成用户档位。
//
// 四档是单调包含的：平滑 ⊂ 柔和 ⊂ 自适应 ⊂ 精致。
export const LIGHT_SMOOTH: string = 'smooth';        // 都不给，最省
export const LIGHT_GENTLE: string = 'gentle';        // 只给流光
export const LIGHT_ADAPTIVE: string = 'adaptive';    // 按面分档 + 跟随省电
export const LIGHT_EXQUISITE: string = 'exquisite';  // 流光给到每一个面
export const LIGHT_DEFAULT: string = LIGHT_ADAPTIVE;

export function normalizeLightLevel(level: string): string {
  if (level === LIGHT_SMOOTH || level === LIGHT_GENTLE ||
    level === LIGHT_ADAPTIVE || level === LIGHT_EXQUISITE) {
    return level;
  }
  return LIGHT_DEFAULT;
}

// 触点流光给不给。
//
// surfaceDefault 是这个面按自身角色该不该有（见 overlayMaterial 的
// usesLightEffect）。精致把它推到每一个面，柔和与自适应尊重分档，平滑全关。
//
// 省电只压自适应：用户明确挑了档位就按他挑的来，不替他改。自适应的字面
// 意思就是"你看着办"，那才轮得到省电插手。
export function lightEffectOn(
  level: string, surfaceDefault: boolean, powerSaving: boolean
): boolean {
  const lv: string = normalizeLightLevel(level);
  if (lv === LIGHT_EXQUISITE) {
    return true;
  }
  if (lv === LIGHT_SMOOTH) {
    return false;
  }
  if (lv === LIGHT_ADAPTIVE && powerSaving) {
    return false;
  }
  return surfaceDefault;
}

// 按压形变给不给。柔和及以下一律不给：形变改的是几何，比流光扎眼得多，
// 用户要"柔和"时它就不该在。
export function interactiveOn(
  level: string, surfaceDefault: boolean, powerSaving: boolean
): boolean {
  const lv: string = normalizeLightLevel(level);
  if (lv === LIGHT_SMOOTH || lv === LIGHT_GENTLE) {
    return false;
  }
  if (lv === LIGHT_ADAPTIVE && powerSaving) {
    return false;
  }
  return surfaceDefault;
}

// ── 映射到 HDS 的材质等级 ──────────────────────────────────────────────
//
// HdsNavigation / HdsTabs 的 `systemMaterialEffect.materialLevel` 收的是
// `hdsMaterial.MaterialLevel`，而它的四个取值和我们这四档**恰好一一对应**：
//
//   EXQUISITE = 0   GENTLE = 1   SMOOTH = 2   ADAPTIVE = 10
//
// 返回的是**数值下标**而不是枚举：那个枚举是 6.1.0(23) 起的，在这一层解引用
// 会在低版本上加载即抛（见 util/hdsTitleBar 文件头记的 v1.3.6 启动崩溃）。
// 由调用方在版本闸内侧换成枚举。
export const HDS_LEVEL_EXQUISITE: number = 0;
export const HDS_LEVEL_GENTLE: number = 1;
export const HDS_LEVEL_SMOOTH: number = 2;
export const HDS_LEVEL_ADAPTIVE: number = 10;

export function hdsLevelIndexOf(level: string): number {
  const lv: string = normalizeLightLevel(level);
  if (lv === LIGHT_EXQUISITE) {
    return HDS_LEVEL_EXQUISITE;
  }
  if (lv === LIGHT_GENTLE) {
    return HDS_LEVEL_GENTLE;
  }
  if (lv === LIGHT_SMOOTH) {
    return HDS_LEVEL_SMOOTH;
  }
  return HDS_LEVEL_ADAPTIVE;
}
