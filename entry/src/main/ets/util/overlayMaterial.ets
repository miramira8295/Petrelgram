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

// The blur a framework-managed menu container used before the material. Only
// 'menu' ever had one; returning it solely while the material is unavailable is
// what keeps the two from stacking.
export function overlayBlur(surface: OverlaySurface): BlurStyle | undefined {
  if (materialAvailable || surface !== 'menu') {
    return undefined;
  }
  return BlurStyle.COMPONENT_ULTRA_THICK;
}

// The backdrop-blur radius a self-drawn glass bar used before the material.
// Zero means no blur, so this is safe to apply unconditionally at the call site.
export function overlayBackdropBlur(surface: OverlaySurface): number {
  if (materialAvailable || surface !== 'bar') {
    return 0;
  }
  return BAR_BACKDROP_BLUR;
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
