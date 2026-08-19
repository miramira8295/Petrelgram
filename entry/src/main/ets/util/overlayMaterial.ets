// Immersive system material (沉浸光感, API 26+) for the app's overlay surfaces.
//
// This module is the single place that decides, per surface, between the new
// system material and whatever that surface looked like before. Never both: the
// material's own `materialFilter` already carries a background blur, so keeping
// `backgroundBlurStyle` or `backdropBlur` alive underneath it is duplicate GPU
// work the official guidance calls out by name.
//
// The fallback is not one thing, because the app's overlays are not one thing.
// Framework-managed menu containers take a `BlurStyle`; self-drawn translucent
// bars must not, because `BlurStyle.COMPONENT_*` carries an opaque backplate
// that renders those bars as solid grey — the reason MainScreen's dock and the
// folder bar reach for `backdropBlur` instead (see MainScreen.ets:292). Solid
// cards had no blur at all and keep having none.
//
// Call sites read:
//
//   .bindMenu(builder, {
//     backgroundBlurStyle: overlayBlur('menu'),   // undefined once material wins
//     systemMaterial: overlayMaterial('menu')     // undefined below API 26
//   })
//
//   .backdropBlur(overlayBackdropBlur('bar'))     // 0 once material wins
//   .systemMaterial(overlayMaterial('bar'))

import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

// The API version that introduced ImmersiveMaterial. Below this the material
// does not exist and every surface stays exactly as it shipped.
const IMMERSIVE_MATERIAL_API: number = 26;

// The blur radius the self-drawn glass bars used before the material existed.
const BAR_BACKDROP_BLUR: number = 22;

// Which overlay a surface is. The name describes the surface's role, because
// the thickness and the fallback both follow from the role.
export type OverlaySurface =
  // Framework-managed menu container: long-press menus, header ⋮, attach menu.
  'menu'
  // Modal that covers what it interrupts: bindSheet, CustomDialog.
  | 'dialog'
  // Self-drawn translucent bar content scrolls under: dock, folder bar.
  | 'bar'
  // Self-drawn opaque card: the composer.
  | 'card'
  // 可按压的控件：附件抽屉的格子这类。只有这一档开 interactive + lightEffect
  // ——按压形变和触点光晕由材质负责，调用方必须把自己那套按压动画让出来，
  // 否则两层形变叠加（官方明确点名的坑）。
  | 'control'
  ;

// 'control' 这一档来得晚：一开始刻意没有，因为本应用每个可按压元素都是实色
// + 手写按压动画，材质会把填充清成玻璃、interactive 还会再叠一层形变。现在
// 它存在了，前提是调用方按 pressAnimationWins() 把自己那套让出来——材质在的
// 时候手写动画归零，材质不在的时候手写动画照旧。

// Whether the material wins over the fallback on a system at this API level.
// Split out from the device lookup so the single rule every getter below
// consults is testable without a device.
export function materialWinsAt(apiVersion: number): boolean {
  return apiVersion >= IMMERSIVE_MATERIAL_API;
}

// deviceInfo returns device constants; the official note is to read them once
// rather than per frame, and these getters sit on the render path.
const materialAvailable: boolean = materialWinsAt(deviceInfo.sdkApiVersion);

export function immersiveMaterialAvailable(): boolean {
  return materialAvailable;
}

// 按压形变。只给 'control'：整块面板跟着手指变形会很怪，背景板不该动。
function usesInteraction(surface: OverlaySurface): boolean {
  return surface === 'control';
}

// 触点光晕。比形变宽一档：面板自己被摸到时也该有光感反馈，那正是"沉浸光感"
// 里"光感"的部分，而且它不改变任何几何，叠在大面积背景上没有副作用。
// 菜单和弹窗不给：它们是一次性出现、点一下就走的东西，摸上去发光没有意义。
function usesLightEffect(surface: OverlaySurface): boolean {
  return surface === 'control' || surface === 'card' || surface === 'bar';
}

// 材质接管按压时，调用方手写的按压动画必须让位——两层形变叠加是官方点名的坑。
// 调用点写成 `pressAnimationWins('control') ? 0.9 : 1` 这种形式。
export function pressAnimationWins(surface: OverlaySurface): boolean {
  return !(materialAvailable && usesInteraction(surface));
}

function styleOf(surface: OverlaySurface): uiMaterial.ImmersiveStyle {
  switch (surface) {
    // Menus want what is behind them pushed firmly back but still legible —
    // the thickness the platform gives its own menus.
    case 'menu':
      return uiMaterial.ImmersiveStyle.THICK;
    // A modal covers what it interrupts; nothing behind it should read.
    case 'dialog':
      return uiMaterial.ImmersiveStyle.ULTRA_THICK;
    // 输入框胶囊和底部抽屉。THIN 而不是 REGULAR：REGULAR 糊得太狠，壁纸的
    // 花纹被抹平成一片纯渐变，抽屉看着像贴上去的另一块东西（真机截图为证）。
    // 薄一档能透出花纹，才读得出"同一张壁纸上蒙了层玻璃"。官方对浮动工具栏
    // 的建议也是 THIN。
    case 'card':
      return uiMaterial.ImmersiveStyle.THIN;
    // 控件比它所在的面板更靠前，用薄一档让它从面板里"浮"出来。官方建议
    // 浮动工具栏用 THIN。
    case 'control':
      return uiMaterial.ImmersiveStyle.THIN;
    // Bars sit over live content and have to stay see-through enough that a
    // list scrolling under them still reads as continuous.
    case 'bar':
    default:
      return uiMaterial.ImmersiveStyle.ULTRA_THIN;
  }
}

// The material draws its own shadow, and it is tuned to go with the material,
// so almost every surface takes it — an existing `.shadow()` is overridden
// rather than drawn twice. The exception is the glass bars, whose shadow is
// part of a floating look deliberately tuned against a translucent fill
// (MainScreen.ets:296); those keep theirs and switch the material's off, which
// is the documented way to run a custom shadow under a material.
function usesOwnShadow(surface: OverlaySurface): boolean {
  return surface === 'bar';
}

// Auto-invert only takes effect on THIN and ULTRA_THIN materials, and it costs
// a colour computation per resource-set colour in the subtree — so it is scoped
// to the one surface thin enough for it to apply and whose contrast is at risk.
function usesColorInvert(surface: OverlaySurface): boolean {
  return surface === 'bar';
}

// 低于 API 26 时这些面自己画毛玻璃。沉浸光感要 API 26，但毛玻璃本身要得低
// 得多——backdropBlur 从 API 7 起、backgroundBlurStyle 从 9 起、
// COMPONENT_ULTRA_THICK 从 11 起，所以 6.0（API 20）设备一样画得出来。
// 这里区分的不是"能不能"，而是"这个面该由框架画还是自己画"。
//
// "由框架画还是自己画"是**调用点**的属性，不是面的属性：同一个 'dialog' 面，
// bindSheet 是框架容器，而 CustomDialog 里那个自己写的 Column 是自绘。所以
// 下面分成两套，由调用点挑一套用，别混：
//
//   框架容器（bindMenu / bindSheet）  → overlayBlur()
//   自绘（自己写的 Column / 胶囊）    → overlayBackdropBlur() + overlayGlassFill()
//
// 自绘面绝不能吃 BlurStyle：COMPONENT_* 自带一层不透明底板，会把自绘面渲染
// 成一块死灰——这正是 dock 和文件夹条一直用 backdropBlur 的原因
// （MainScreen.ets:292）。

// 能吃 BlurStyle 的框架容器面。'bar' 和 'card' 永远是自绘的。
function frameworkContainer(surface: OverlaySurface): boolean {
  return surface === 'menu' || surface === 'dialog';
}

// The blur a framework-managed container used before the material. Returning it
// solely while the material is unavailable is what keeps the two from stacking.
export function overlayBlur(surface: OverlaySurface): BlurStyle | undefined {
  if (materialAvailable || !frameworkContainer(surface)) {
    return undefined;
  }
  // 菜单要把背后压实，模态更甚；两者都取最厚的一档。
  return BlurStyle.COMPONENT_ULTRA_THICK;
}

// The backdrop-blur radius a self-drawn glass surface uses before the material.
// Zero means no blur, so this is safe to apply unconditionally at the call site.
// 明确要高斯模糊、不要材质的面用这个。和 overlayBackdropBlur 不同：那个在
// 材质可用时返回 0（把观感让给材质），这个无条件给出模糊半径。
export function plainBackdropBlur(): number {
  return BAR_BACKDROP_BLUR;
}

export function overlayBackdropBlur(surface: OverlaySurface): number {
  return materialAvailable ? 0 : BAR_BACKDROP_BLUR;
}

// 自绘面的底色。两种情况都不能是原来那个不透明实色，但理由不同：
//
// 材质可用时必须**透明**。官方《沉浸光感常见问题》写死：材质的视觉层级在
// backgroundColor **之下**，不透明底色会盖在材质层之上，"导致材质效果被遮挡
// 不可见"。这里原来返回的正是实色——当初以为"材质会把填充清成玻璃"，方向
// 反了，结果是顶栏胶囊、输入框、抽屉卡片上的材质一直被自己的底色盖着。
//
// 材质不可用时必须**半透明**。那时靠 backdropBlur 自己画玻璃，而不透明底色
// 会把模糊完全盖住——模糊的是身后的东西，它自己不透光。
export function overlayGlassFill(_surface: OverlaySurface, _solid: ResourceColor): ResourceColor {
  return materialAvailable ? Color.Transparent : $r('app.color.dock_glass');
}

// Materials are built once per surface and reused. Rebuilding one per frame
// re-triggers the material computation the guidance warns about, and none of
// these parameters change at runtime.
const cache: Map<OverlaySurface, uiMaterial.Material> = new Map<OverlaySurface, uiMaterial.Material>();

function buildMaterial(surface: OverlaySurface): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: styleOf(surface),
    colorInvert: usesColorInvert(surface),
    applyShadow: !usesOwnShadow(surface),
    // 这两个和材质本体不同：官方注明它们「takes effect for devices with all
    // levels of computing power」，低算力设备上不会被降级掉。
    interactive: usesInteraction(surface),
    lightEffect: usesLightEffect(surface) ? { color: Color.White } : null
  });
}

// The material for a surface, or undefined on systems without it — at which
// point that surface's own fallback getter is what takes effect.
export function overlayMaterial(surface: OverlaySurface): uiMaterial.Material | undefined {
  if (!materialAvailable) {
    return undefined;
  }
  const hit = cache.get(surface);
  if (hit !== undefined) {
    return hit;
  }
  const built = buildMaterial(surface);
  cache.set(surface, built);
  return built;
}
