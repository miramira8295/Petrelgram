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
  ;

// There is deliberately no 'control' surface for the material's press
// deformation and touch-following sheen. Every pressable in this app is a solid
// COLOR_PRIMARY shape with its own hand-written press animation — the material
// would clear that fill to transparent glass, and `interactive` would run a
// second deformation on top of the existing one.

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

function styleOf(surface: OverlaySurface): uiMaterial.ImmersiveStyle {
  switch (surface) {
    // Menus want what is behind them pushed firmly back but still legible —
    // the thickness the platform gives its own menus.
    case 'menu':
      return uiMaterial.ImmersiveStyle.THICK;
    // A modal covers what it interrupts; nothing behind it should read.
    case 'dialog':
      return uiMaterial.ImmersiveStyle.ULTRA_THICK;
    // The composer sits over the chat background and should read as a distinct
    // surface without hiding the wallpaper it floats on.
    case 'card':
      return uiMaterial.ImmersiveStyle.REGULAR;
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
export function overlayBackdropBlur(surface: OverlaySurface): number {
  return materialAvailable ? 0 : BAR_BACKDROP_BLUR;
}

// 自绘面的底色。**不透明底色会把 backdropBlur 完全盖住**——白色胶囊上加模糊
// 一点变化都没有，因为模糊的是它身后的东西，而它自己不透光。所以自己画玻璃
// 的时候，底色必须同时换成半透明的那一版（dock_glass，两个模式都已定好）。
//
// 材质接管时反过来：材质自带填充，底色交回调用方原来的实心色，由材质把它
// 清成透明玻璃。
export function overlayGlassFill(_surface: OverlaySurface, solid: ResourceColor): ResourceColor {
  return materialAvailable ? solid : $r('app.color.dock_glass');
}

// Materials are built once per surface and reused. Rebuilding one per frame
// re-triggers the material computation the guidance warns about, and none of
// these parameters change at runtime.
const cache: Map<OverlaySurface, uiMaterial.Material> = new Map<OverlaySurface, uiMaterial.Material>();

function buildMaterial(surface: OverlaySurface): uiMaterial.Material {
  return new uiMaterial.ImmersiveMaterial({
    style: styleOf(surface),
    colorInvert: usesColorInvert(surface),
    applyShadow: !usesOwnShadow(surface)
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
