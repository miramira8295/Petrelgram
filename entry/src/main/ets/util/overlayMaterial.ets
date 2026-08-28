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
import { hdsMaterial } from '@kit.UIDesignKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { logW } from './log';
import {
  LIGHT_DEFAULT, THICKNESS_DEFAULT, fallbackBlurRadius, interactiveOn,
  isThicknessOff, lightEffectOn, normalizeLightLevel, normalizeThickness, shiftedStyleIndex
} from './materialTuning';
import { KEY_MATERIAL_LIGHT_DARK, KEY_MATERIAL_THICKNESS_DARK, appIsDark } from './appearance';
import { KEY_MATERIAL_LIGHT, KEY_MATERIAL_THICKNESS, KEY_POWER_ACTIVE } from '../store/AppSettings';

// The API version that introduced ImmersiveMaterial. Below this the material
// does not exist and every surface stays exactly as it shipped.
const IMMERSIVE_MATERIAL_API: number = 26;

// 低于 API 26 时，全屏查看器控制层自绘玻璃用的底色。和查看器原本写死的那个
// 值一致，所以老设备上观感不变；新设备上它整个让位给材质。
const VIEWER_GLASS_FALLBACK: string = '#6e3e3e40';

// 用户的两个档位。这是个 util 而不是组件，订阅不了 @StorageProp，所以每次
// 取值都现读 AppStorage——这些 getter 只在组件 build 时跑，不在每帧路径上。
//
// 读不到（设置还没落地、或者键不存在）就用出厂值，由 materialTuning 那边的
// normalize 兜底，不让脏值把档位推到边上。
// 厚度/光感按浅色/深色各存一份，读当前模式那份（appIsDark 由 EntryAbility 维护）。
function thicknessOffset(): number {
  const key = appIsDark() ? KEY_MATERIAL_THICKNESS_DARK : KEY_MATERIAL_THICKNESS;
  return normalizeThickness(AppStorage.get<number>(key) ?? THICKNESS_DEFAULT);
}

// 用户把厚度调到「关闭」：所有面都不挂材质、不模糊，纯色兜底。
export function materialOff(): boolean {
  return isThicknessOff(thicknessOffset());
}

function lightLevel(): string {
  const key = appIsDark() ? KEY_MATERIAL_LIGHT_DARK : KEY_MATERIAL_LIGHT;
  return normalizeLightLevel(AppStorage.get<string>(key) ?? LIGHT_DEFAULT);
}

function powerSavingNow(): boolean {
  return AppStorage.get<boolean>(KEY_POWER_ACTIVE) ?? false;
}

// ImmersiveStyle 的枚举值就是 0..4，但别写 `as ImmersiveStyle` 硬转——查表换，
// 顺序改了也不会悄悄错位。
// 绝不能在**模块级**解引用 uiMaterial.ImmersiveStyle。
//
// 它是 API 26 才有的，低版本上这个对象根本不存在，取 .ULTRA_THIN 会在模块
// 加载的那一刻就抛——而 overlayMaterial 被 31 个页面引用，结果是整个应用
// 启动即崩。实测 6.1.0.135（API 24）上 1.3.6 就是这么挂的。
//
// 1.3.5 没事，是因为那时这些枚举只出现在 styleOf() 函数体里，而 styleOf 只
// 有材质可用时才会被调到。加厚度设置时我把它们提成了模块级常量，等于把
// 「用到才碰」变成了「加载就碰」。
//
// 所以写成函数：调用点全都在 materialAvailable 为真之后。
function styleByIndex(index: number): uiMaterial.ImmersiveStyle {
  switch (index) {
    case 0:
      return uiMaterial.ImmersiveStyle.ULTRA_THIN;
    case 1:
      return uiMaterial.ImmersiveStyle.THIN;
    case 2:
      return uiMaterial.ImmersiveStyle.REGULAR;
    case 3:
      return uiMaterial.ImmersiveStyle.THICK;
    default:
      return uiMaterial.ImmersiveStyle.ULTRA_THICK;
  }
}

// 降级路径上框架容器吃的 BlurStyle，同样按 0..4 排。
const BLUR_STYLE_BY_INDEX: BlurStyle[] = [
  BlurStyle.COMPONENT_ULTRA_THIN,
  BlurStyle.COMPONENT_THIN,
  BlurStyle.COMPONENT_REGULAR,
  BlurStyle.COMPONENT_THICK,
  BlurStyle.COMPONENT_ULTRA_THICK
];

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
  // 全屏媒体查看器的控制层：顶栏胶囊、⋮ 按钮、视频控制条。
  //
  // 单开一档而不是复用 'bar'，因为它有一条别的面都没有的性质：**底永远是黑的**。
  // 其余每个面都浮在应用自己的界面上，跟随浅色/深色主题；这一档浮在照片或视频
  // 上，无论主题如何，文字和图标都是白的。直接用 'bar' 会在低于 API 26 的设备
  // 上回退到 dock_glass 那个跟随主题的资源色——浅色主题下就是在照片上糊一块
  // 亮色药丸。见 overlayGlassFill 里的分支。
  | 'viewer'
  // 聊天气泡。只有用户在「外观」里打开气泡材质才会挂上（气泡组件按屏内/省电
  // 再门控一次）；不按压、不流光，只是半透明染色透壁纸。
  | 'bubble'
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

// 设备自报的材质能力里，「沉浸材质」这一档的枚举值（hdsMaterial.MaterialType
// .IMMERSIVE）。写成常量是为了让下面那条判据能脱离 HDS 单测——枚举本身在
// API 23 以下解引用就会抛，宿主单测里碰不得。
export const MATERIAL_TYPE_IMMERSIVE: number = 101;

// 设备到底给不给沉浸材质。
//
// **为什么光看 API 版本不够**（用户报：HarmonyOS 7.0.0.105 SP6 升级后玻璃全没了，
// 顶栏/输入框/附件抽屉变成彻底透明的窟窿）：材质可用与否不只取决于 API 版本，
// 还取决于设备档位和系统版本自己的策略。而我们在「材质可用」这一支里把两个
// 兜底**都关死了**——底色透明、模糊归 0——赌的就是材质一定会画出来。它不画，
// 就什么都不剩。官方 HDS 指南给的正确做法是先查 getSystemMaterialTypes()。
//
// 查不到（接口抛、或者返回空数组）一律当「不知道」，维持按版本的老判断：宁可
// 保持现状，也不要在材质本来好好的设备上把它关掉。
export function immersiveTypeSupported(types: number[]): boolean {
  if (types.length === 0) {
    return true;
  }
  for (const type of types) {
    if (type === MATERIAL_TYPE_IMMERSIVE) {
      return true;
    }
  }
  return false;
}

// deviceInfo returns device constants; the official note is to read them once
// rather than per frame, and these getters sit on the render path. 能力查询同理
// ——只在第一次用到时查一次，之后走缓存。
let materialProbed: boolean = false;
let materialProbeResult: boolean = false;

function materialAvailable(): boolean {
  if (materialProbed) {
    return materialProbeResult;
  }
  materialProbed = true;
  // 版本闸必须排在最前：hdsMaterial 的枚举和接口都是 API 23 起，低版本上
  // **解引用就抛**（同一个坑见本文件 styleByIndex 上面那段，1.3.6 在 API 24
  // 上启动即崩）。
  if (!materialWinsAt(deviceInfo.sdkApiVersion)) {
    materialProbeResult = false;
    return false;
  }
  const types: number[] = [];
  let queried: boolean = false;
  try {
    const reported: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    for (const type of reported) {
      types.push(type as number);
    }
    queried = true;
  } catch (e) {
    logW(`[Material] getSystemMaterialTypes failed: ${e}`);
  }
  materialProbeResult = queried ? immersiveTypeSupported(types) : true;
  // 这一行是下次用户报「玻璃没了」时唯一能回答问题的东西：设备报了什么、
  // 我们据此判成了什么。只在第一次查询时打一行。
  logW(`[Material] api=${deviceInfo.sdkApiVersion} types=[${types.join(',')}]` +
    ` queried=${queried} material=${materialProbeResult}`);
  return materialProbeResult;
}

// 材质档位变更纪元。overlayMaterial 的这些 getter 是普通函数，util 订阅不了
// AppStorage，所以"改了设置要重绘"只能由调用方订阅——和语言切换的
// LANGUAGE_EPOCH 是同一套办法，见 util/appLanguage.ets 的说明。
//
// 用一个纪元而不是让每个组件分别订阅两个设置键：调用方只关心"材质变了"，
// 不关心变的是厚度还是光感，订阅一个数就够。
export const MATERIAL_EPOCH: string = 'materialEpoch';

export function bumpMaterialEpoch(): void {
  AppStorage.setOrCreate(MATERIAL_EPOCH, (AppStorage.get<number>(MATERIAL_EPOCH) ?? 0) + 1);
}

export function immersiveMaterialAvailable(): boolean {
  return materialAvailable();
}

// 按压形变的**基准**：只给 'control'——整块面板跟着手指变形会很怪，背景板
// 不该动。用户的光感档位在这之上决定给不给，见 materialTuning。
function interactionBase(surface: OverlaySurface): boolean {
  return surface === 'control';
}

function usesInteraction(surface: OverlaySurface): boolean {
  return interactiveOn(lightLevel(), interactionBase(surface), powerSavingNow());
}

// 触点光晕。比形变宽一档：面板自己被摸到时也该有光感反馈，那正是"沉浸光感"
// 里"光感"的部分，而且它不改变任何几何，叠在大面积背景上没有副作用。
// 菜单和弹窗不给：它们是一次性出现、点一下就走的东西，摸上去发光没有意义。
function lightEffectBase(surface: OverlaySurface): boolean {
  return surface === 'control' || surface === 'card' || surface === 'bar'
    || surface === 'viewer' || surface === 'bubble';
}

function usesLightEffect(surface: OverlaySurface): boolean {
  return lightEffectOn(lightLevel(), lightEffectBase(surface), powerSavingNow());
}

// 材质接管按压时，调用方手写的按压动画必须让位——两层形变叠加是官方点名的坑。
// 调用点写成 `pressAnimationWins('control') ? 0.9 : 1` 这种形式。
export function pressAnimationWins(surface: OverlaySurface): boolean {
  return !(materialAvailable() && usesInteraction(surface));
}

// 每个面调好的**基准**厚度档，用下标表示（0=超薄 … 4=超厚）。用户的厚度偏移
// 在这之上整体平移，相对次序不变——见 materialTuning 的说明。
function baseStyleIndex(surface: OverlaySurface): number {
  switch (surface) {
    // 菜单：REGULAR 而不是 THICK。THICK 把背后压得太实，真机上几乎读不出
    // 玻璃感，看着就是一块浅色板；REGULAR 仍然把内容推远、文字照样清楚，
    // 但透出的层次让它像一块玻璃。同一档同时用于消息长按菜单和顶栏菜单，
    // 两者本来就该长得一样（见 ActionMenuRow 的注释）。
    case 'menu':
      return 2;
    // A modal covers what it interrupts; nothing behind it should read.
    case 'dialog':
      return 4;
    // 输入框胶囊和底部抽屉。THIN 而不是 REGULAR：REGULAR 糊得太狠，壁纸的
    // 花纹被抹平成一片纯渐变，抽屉看着像贴上去的另一块东西（真机截图为证）。
    // 薄一档能透出花纹，才读得出"同一张壁纸上蒙了层玻璃"。官方对浮动工具栏
    // 的建议也是 THIN。
    case 'card':
    case 'bubble': // 和输入框同一基准，用户在设置里调的是同一个偏移
      return 1;
    // 控件比它所在的面板更靠前，用薄一档让它从面板里"浮"出来。官方建议
    // 浮动工具栏用 THIN。
    case 'control':
      return 1;
    // Bars sit over live content and have to stay see-through enough that a
    // list scrolling under them still reads as continuous.
    // 查看器的控制层最薄。它盖住的是用户此刻正在看的那张照片——糊一点点
    // 让文字读得出就够，多一档都是在挡内容。
    case 'viewer':
    case 'bar':
    default:
      return 0;
  }
}

function styleOf(surface: OverlaySurface): uiMaterial.ImmersiveStyle {
  return styleByIndex(shiftedStyleIndex(baseStyleIndex(surface), thicknessOffset()));
}

// The material draws its own shadow, and it is tuned to go with the material,
// so almost every surface takes it — an existing `.shadow()` is overridden
// rather than drawn twice. The exception is the glass bars, whose shadow is
// part of a floating look deliberately tuned against a translucent fill
// (MainScreen.ets:296); those keep theirs and switch the material's off, which
// is the documented way to run a custom shadow under a material.
function usesOwnShadow(surface: OverlaySurface): boolean {
  // 'bubble'：材质自带的阴影/高光边是按**节点矩形**画的，而气泡整块是按轮廓
  // （圆角矩形 + 三角尾巴）裁剪的，两者对不上——底边和右侧会多出几条亮线
  // （真机可见）。关掉它自绘的那层，边缘交给裁剪。
  return surface === 'bar' || surface === 'bubble';
}

// Auto-invert only takes effect on THIN and ULTRA_THIN materials, and it costs
// a colour computation per resource-set colour in the subtree — so it is scoped
// to the one surface thin enough for it to apply and whose contrast is at risk.
// 'viewer' 明确不开自动反色：它是按子树里每个**资源色**逐个算反色的，而查看器
// 控制层的文字和图标写的是字面量 Color.White（底永远是黑的，不跟主题走），
// 反色对它们本来就不生效，开着只是白付一笔计算。
function usesColorInvert(surface: OverlaySurface): boolean {
  if (surface !== 'bar') {
    return false;
  }
  // 官方注明自动反色只在材质足够薄（THIN / ULTRA_THIN）时才可能生效，而它
  // 是按子树里每个资源色逐个算反色的。用户把厚度调上去之后反色不再生效，
  // 那笔计算就纯属白付——档位超过 THIN 就别开。
  return shiftedStyleIndex(baseStyleIndex(surface), thicknessOffset()) <= 1;
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

// 'viewer' **不参与沉浸材质**，无论 API 多少。
//
// 沉浸材质的整个前提是"适应身后的东西"，而这一面身后是**用户随便一张照片**：
// 材质算出来是亮是暗全看那张图，前景色再怎么跟也总有一半照片不成立。别的面
// 浮在应用自己的界面上，底色可知，材质因此成立；只有这一面不是。
//
// 这条在 overlayGlassFill 的注释里本来就写着——「查看器的底永远是黑的、文字
// 图标永远是白的，不跟主题走」——但那句话只在 API 26 以下的降级路径上兑现，
// 26 上材质把它悄悄推翻了。#122 的顶栏做成通栏之后仍然看不清，就是这个原因：
// 通栏的底色是透明的，观感全交给了材质。
//
// 所以固定成"深色半透明 + 高斯模糊 + 白色前景"，三样一起，缺一不可。
export function usesImmersiveMaterial(surface: OverlaySurface): boolean {
  return surface !== 'viewer';
}

// The blur a framework-managed container used before the material. Returning it
// solely while the material is unavailable is what keeps the two from stacking.
export function overlayBlur(surface: OverlaySurface): BlurStyle | undefined {
  if (materialOff() || materialAvailable() || !frameworkContainer(surface)) {
    return undefined;
  }
  // 菜单要把背后压实，模态更甚；两者的基准都是最厚的一档，再吃用户的厚度
  // 偏移——调薄时这条降级路径也得跟着薄，否则设置在 26 以下只对自绘面生效。
  return BLUR_STYLE_BY_INDEX[shiftedStyleIndex(4, thicknessOffset())];
}

// The backdrop-blur radius a self-drawn glass surface uses before the material.
// Zero means no blur, so this is safe to apply unconditionally at the call site.
// 明确要高斯模糊、不要材质的面用这个。和 overlayBackdropBlur 不同：那个在
// 材质可用时返回 0（把观感让给材质），这个无条件给出模糊半径。
export function plainBackdropBlur(): number {
  return materialOff() ? 0 : fallbackBlurRadius(thicknessOffset());
}

export function overlayBackdropBlur(surface: OverlaySurface): number {
  // 不参与材质的面（'viewer'）自己画玻璃，任何 API 上都要模糊半径——返回 0
  // 是"把观感让给材质"的意思，而它没有材质可让。
  return (materialOff() || (materialAvailable() && usesImmersiveMaterial(surface)))
    ? 0 : fallbackBlurRadius(thicknessOffset());
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
// 气泡尾巴的填充色。系统材质是合成层，**不吃 clipShape**——挂到三角形节点上会
// 在三角外面糊出一块圆角矩形背板（用户报的「框框把尾巴盖住」）。所以尾巴不挂
// 材质，用材质的回退玻璃色实心填充，视觉上接得住。
export function glassTailFill(): ResourceColor {
  return $r('app.color.bubble_glass_tail');
}

// 尾巴的背景模糊半径。模糊不是合成层、吃 clipShape，所以三角能真糊出玻璃感；
// 材质在的时候 overlayBackdropBlur('bubble') 会返回 0（那时由材质负责），
// 尾巴用不了材质，只能自己要一份非材质的模糊半径。
export function glassTailBlur(): number {
  return plainBackdropBlur();
}

export function overlayGlassFill(surface: OverlaySurface, solid: ResourceColor): ResourceColor {
  if (materialOff()) {
    return solid;
  }
  // 查看器控制层：**任何 API 上**都是这个固定的深色半透明，不是透明。
  // 透明意味着观感全交给材质，而这一面不参与材质（见 usesImmersiveMaterial）。
  if (!usesImmersiveMaterial(surface)) {
    return VIEWER_GLASS_FALLBACK;
  }
  if (materialAvailable()) {
    return Color.Transparent;
  }
  // 这个色由本模块自己持有，不回显调用方传进来的 solid：这个模块的职责就是
  // 替调用方决定，而不是指望调用方传来的恰好是半透明的（不透明底色会把
  // backdropBlur 完全盖住，OverlayMaterial.test 里钉着这条）。
  return $r('app.color.dock_glass');
}

// Materials are built once per surface and reused. Rebuilding one per frame
// re-triggers the material computation the guidance warns about, and none of
// these parameters change at runtime.
//
// 缓存键必须带上用户档位，不能只按面缓存：只按面缓存时，第一次建好的那个
// 材质会一直被返回，用户调厚度或光感全都不生效。带上档位则新档位自然落到
// 新条目，旧条目留着——档位调回去时还能命中，不必失效重建。
const cache: Map<string, uiMaterial.Material> = new Map<string, uiMaterial.Material>();

function cacheKey(surface: OverlaySurface): string {
  return `${surface}_${thicknessOffset()}_${lightLevel()}_${powerSavingNow() ? 'p' : 'n'}`;
}

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
  if (materialOff() || !materialAvailable() || !usesImmersiveMaterial(surface)) {
    return undefined;
  }
  const key: string = cacheKey(surface);
  const hit = cache.get(key);
  if (hit !== undefined) {
    return hit;
  }
  const built = buildMaterial(surface);
  cache.set(key, built);
  return built;
}
