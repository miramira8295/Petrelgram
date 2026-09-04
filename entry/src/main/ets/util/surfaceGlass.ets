// 全局界面模糊质感：首页会话列表 / 气泡 / 联系人 / 设置 / 搜索。
//
// 【和 overlayMaterial 那套是什么关系】
// overlayMaterial 管的是**沉浸材质那条线**：材质可用就把观感让给
// systemMaterial，不可用才退回自绘模糊。而这个模块是**明确不指望材质**的一条
// 独立线——配方和会话详情里的输入栏一模一样（plainGlassFill + plainBackdropBlur），
// 因为那一对是今天唯一在这台设备上真的画得出玻璃的写法（系统收回了 HdsNav
// 级别以外的材质，见 overlayMaterial.overlayGlassFill 里 08-29 那段实测记录）。
//
// 【为什么要单独一个开关而不是复用厚度】
// 厚度偏移（KEY_MATERIAL_THICKNESS）管的是"材质/自绘面有多厚"，它的取值对
// 已有的十几个面都有意义。而这里要控制的是"**要不要**把玻璃铺到列表行、气泡、
// 设置卡片这些**数量巨大**的节点上"——那是一个性能取舍，不是观感浓淡：
// backdropBlur 每帧真渲染，而 09-03 真机 trace 里滤镜缓存命中率只有 4.6%
// （背景在滚，缓存永远失效）。所以它必须是一个能整体关掉的独立开关。
//
// 【输入栏不走这个配置】会话详情的输入栏保持原样、不受这里的开关影响——
// 它是"质感基准"，用户是拿它当参照来调其余面的。

import { normalizeThickness } from './materialTuning';
import { appIsDark } from './appearance';
import { blurStyleByIndex } from './overlayMaterial';

// 两个独立开关：**整体**（会话列表 / 联系人 / 设置 / 我的）与**气泡**。
//
// 【为什么拆】两者的代价完全不是一个量级：整体那几个面是一屏十几行的列表，
// 气泡则是一屏几十个、还带尾巴和轮廓裁剪。想只要气泡玻璃、或者只要列表玻璃，
// 在一个开关下做不到——只能全开全关。
//
// 【为什么档位不拆】档位是"这套玻璃多浓"，是同一种质感的浓淡，不是两种东西。
// 拆成两个档位只会让设置页变成四个控件，而两边用不同浓度并没有实际诉求。
export const KEY_SURFACE_GLASS_ON: string = 'surfaceGlassOn';
export const KEY_BUBBLE_GLASS_ON: string = 'bubbleGlassOn';
// 档位。语义与厚度偏移一致（-2 超薄 … 0 常规 … 2 超厚），复用同一套归一化，
// 用户在两处看到的"薄/厚"是同一个刻度。
export const KEY_SURFACE_GLASS_LEVEL: string = 'surfaceGlassLevel';
// 气泡那一面的档位。**两面各有各的档**——整体是一屏十几行的列表，气泡是一屏
// 几十个带尾巴和轮廓裁剪的节点，想给它们不同浓度是合理诉求。
export const KEY_BUBBLE_GLASS_LEVEL: string = 'bubbleGlassLevel';

// 默认**关**：backdropBlur / 框架材质每帧实时渲染，而这个开关覆盖的是全应用
// 数量最多的那些节点（会话行、气泡）。09-03 真机 trace：滤镜缓存命中率只有
// 4.6%（背景在滚，缓存永远失效）、GPU 活跃段 p90 恒为 100%。这是性能与功耗
// 的取舍，必须由用户主动打开。
export const SURFACE_GLASS_ON_DEFAULT: boolean = false;
export const BUBBLE_GLASS_ON_DEFAULT: boolean = false;

// 「薄纱」档：**只有那层纱，不挂任何模糊**。
//
// 它是档位里最轻的一档，也是打开开关后的默认档。理由有两层：
//   观感 —— 用户要的"原有薄纱"本来就是纯色那一层（迁到框架材质之前气泡就长这样），
//     不该只能作为"模糊之上再叠一层"存在；
//   性能 —— 这一档一次 backgroundBlurStyle 都不挂，是全档位里唯一不吃每帧
//     实时渲染的（09-03 真机 trace：滤镜缓存命中率 4.6%）。开关默认关就是因为
//     那个开销，那么"打开之后"的默认档更该是不花这笔钱的这一档。
//
// **取值刻意落在 normalizeThickness 的量程之外**（它钳在 -2..2），这样它不可能
// 被当成某一档厚度误用；所有解释它的地方都必须显式判等。
//
// **不能取 -3**：那是 materialTuning.THICKNESS_OFF（「关闭」档）已经占了的值。
// 第一版取了 -3，于是设置里「关闭」和「薄纱」两个选项的 value 完全相同，
// 点薄纱走进了 `v === THICKNESS_OFF` 那一支，直接把开关关掉——用户实测
// 「点了薄纱，再进去还是关闭状态，气泡也没变」。SurfaceGlass.test 钉了这一条。
export const SURFACE_GLASS_LEVEL_VEIL: number = -4;
export const SURFACE_GLASS_LEVEL_DEFAULT: number = SURFACE_GLASS_LEVEL_VEIL;

export function surfaceGlassOn(): boolean {
  return AppStorage.get<boolean>(KEY_SURFACE_GLASS_ON) ?? SURFACE_GLASS_ON_DEFAULT;
}

export function bubbleGlassOn(): boolean {
  return AppStorage.get<boolean>(KEY_BUBBLE_GLASS_ON) ?? BUBBLE_GLASS_ON_DEFAULT;
}

// 任一面开着。档位行只在这时才出现，持久化/纪元也按它判。
export function anyGlassOn(): boolean {
  return surfaceGlassOn() || bubbleGlassOn();
}

export function surfaceGlassLevel(): number {
  return readLevel(KEY_SURFACE_GLASS_LEVEL);
}

export function bubbleGlassLevel(): number {
  return readLevel(KEY_BUBBLE_GLASS_LEVEL);
}

function readLevel(key: string): number {
  const raw: number = AppStorage.get<number>(key) ?? SURFACE_GLASS_LEVEL_DEFAULT;
  // 薄纱档原样透出——它不在厚度量程里，归一化会把它钳成"超薄"。
  return raw === SURFACE_GLASS_LEVEL_VEIL ? raw : normalizeThickness(raw);
}

// 当前是不是「只有薄纱、不挂模糊」那一档。
export function surfaceGlassVeilOnly(): boolean {
  return anyGlassOn() && surfaceGlassLevel() === SURFACE_GLASS_LEVEL_VEIL;
}

// **别再加回 backdropBlur 版本的半径函数。**
// 它在节点边缘有采样衰减（四个角最明显，用户实测"颜色偏浅/透明度高"），
// 所有面都改用 surfaceGlassBlurStyle 那层框架容器材质了。

// 底色的**不透明度也跟着档位走**，不只是模糊半径。
//
// 【为什么】原来档位只改 backdropBlur 的半径，底色恒定是 dock_glass（55% 白）。
// 但决定"卡片和壁纸之间那条缝扎不扎眼"的是**卡片与壁纸的亮度差**，不是模糊有
// 多糊：实测浅绿壁纸上卡片亮度 215、壁纸 165，差 50，缝就被读成一圈描边
// （用户报的"黑边"，逐像素量下来并没有黑线，就是这个反差）。
// 调薄 → 卡片更透 → 反差变小、缝不跳；调厚 → 卡片更实、更像一张纸。
// 现在这两件事都由同一个档位控制，用户能自己调到想要的位置。
//
// 五档的 alpha 取值（超薄 → 超厚）。0x8C 那一档就是原来的 dock_glass，
// 保证默认档与改动前逐字节等价。
const FILL_ALPHA_BY_LEVEL: string[] = ['66', '79', '8C', 'A6', 'BF'];

// 玻璃底色的 RGB。与 dock_glass 同源：浅色白、深色是那支蓝灰。
const FILL_RGB_LIGHT: string = 'FFFFFF';
const FILL_RGB_DARK: string = '2F3F52';

// **框架容器材质**，不是 backdropBlur。
//
// backdropBlur 是把节点背后那块内容做卷积，**模糊核在节点边缘要采到节点外面**，
// 那里没有内容可采，效果就被稀释——四个角是两条边同时缺，所以最明显：用户报的
// 「四个角颜色偏浅 / 透明度高」就是它。`.clip(true)` 治不了（裁的是子节点，
// 不是这个效果本身）。
//
// backgroundBlurStyle 是框架自己实现的容器材质，边缘由框架处理，没有这个衰减。
// 代价是只有五个离散档，给不了任意半径——而我们本来就是按档位走的，正好。
export function surfaceGlassBlurStyle(): BlurStyle | undefined {
  return glassBlurStyleFor(surfaceGlassOn(), surfaceGlassLevel());
}

// 气泡那一面：自己的开关、自己的档位。
export function bubbleGlassBlurStyle(): BlurStyle | undefined {
  return glassBlurStyleFor(bubbleGlassOn(), bubbleGlassLevel());
}

function glassBlurStyleFor(on: boolean, level: number): BlurStyle | undefined {
  if (!on) {
    return undefined;
  }
  // 薄纱档：一次模糊都不挂，只留 surfaceGlassScrim() 那层纱色。
  if (level === SURFACE_GLASS_LEVEL_VEIL) {
    return undefined;
  }
  // **档位直接映射五档，不走 base + offset。**
  //
  // 原来是 shiftedStyleIndex(1, level) = clamp(1 + level)，量程被压掉一半：
  //   超薄 -2 → 0 ULTRA_THIN
  //   薄   -1 → 0 ULTRA_THIN   ← 和超薄完全一样
  //   常规  0 → 1 THIN
  //   厚   +1 → 2 REGULAR
  //   超厚 +2 → 3 THICK        ← 根本到不了 ULTRA_THICK
  // base + offset 那套是给"每个面各有基准厚度、用户偏移整体平移"用的
  // （见 overlayMaterial.baseStyleIndex）；而这里是一个独立的全局设置，
  // 没有"面"的概念，套用它只会把量程白白压窄、还让两个档位重名。
  return blurStyleByIndex(normalizeThickness(level) + 2);
}

// 自绘兜底用的半透色。当前没有调用方——所有面都走 backgroundBlurStyle 了。
// 留着是给挂不上 backgroundBlurStyle 的面备用。
export function surfaceGlassFillHex(): string {
  if (surfaceGlassLevel() === SURFACE_GLASS_LEVEL_VEIL) {
    return `#${FILL_ALPHA_BY_LEVEL[0]}${appIsDark() ? FILL_RGB_DARK : FILL_RGB_LIGHT}`;
  }
  const idx: number = normalizeThickness(surfaceGlassLevel()) + 2;
  const alpha: string = FILL_ALPHA_BY_LEVEL[idx] ?? FILL_ALPHA_BY_LEVEL[2];
  return `#${alpha}${appIsDark() ? FILL_RGB_DARK : FILL_RGB_LIGHT}`;
}

// 压在材质上的那一层。**两成分合成一个色**：一层原有的薄纱 + 一点中性压暗。
//
// 为什么合成而不是叠两层：一个节点只有一个 backgroundColor，而材质是画在它
// 之下的另一层，没有"再插一层"的位置。所以两个成分在这里先合成好再交出去。
//
// 两成分各自解决一件事：
//   薄纱（白）—— 迁到框架材质之前气泡就是这一层 25% 白（material_tint），
//     用户要的"原有薄纱"就是它。它让卡片看得出是一块面，而不是一块糊。
//   压暗（黑）—— 框架材质是提亮的，壁纸偏暖时黄色会透上来且被放大
//     （用户实测"底下黄色透上来的更黄了"）。纯薄纱压不住，得掺一点黑。
//
// **要调浓淡只改这两个常量。** VEIL 往上给会更"实"、更盖住材质；
// SCRIM 往上给会更压暗、更去黄。合成后的 alpha 有上限保护（见单测）。
const VEIL_ALPHA: number = 0x2A;   // 薄纱：约 16% 白
const SCRIM_ALPHA: number = 0x14;  // 压暗：约 8% 黑

// 薄纱与压暗叠在一起之后的等效单色。
// 先按 alpha 合成不透明度，再按各自权重合成 RGB —— 这样"两层"和"一层"在
// 视觉上等价，而节点只需要一个 backgroundColor。
export function surfaceGlassScrim(): ResourceColor {
  const dark: boolean = appIsDark();
  // 薄纱在深色模式下用那支蓝灰而不是纯白，否则深色界面上是一层灰雾。
  const veilR: number = dark ? 0x2F : 0xFF;
  const veilG: number = dark ? 0x3F : 0xFF;
  const veilB: number = dark ? 0x52 : 0xFF;
  const va: number = VEIL_ALPHA / 255;
  const sa: number = SCRIM_ALPHA / 255;
  // 合成不透明度：1 - (1-va)(1-sa)
  const outA: number = 1 - (1 - va) * (1 - sa);
  // 合成颜色：薄纱在上、压暗（黑，RGB 全 0）在下，按各自贡献加权。
  const w: number = va / outA;
  const r: number = Math.round(veilR * w);
  const g: number = Math.round(veilG * w);
  const b: number = Math.round(veilB * w);
  const a: number = Math.round(outA * 255);
  const hex = (n: number): string => (n < 16 ? '0' : '') + n.toString(16).toUpperCase();
  return `#${hex(a)}${hex(r)}${hex(g)}${hex(b)}`;
}

// 关掉时原样返回调用方的实色。
export function surfaceGlassFill(solid: ResourceColor): ResourceColor {
  return surfaceGlassOn() ? surfaceGlassScrim() : solid;
}

export function bubbleGlassFill(solid: ResourceColor): ResourceColor {
  return bubbleGlassOn() ? surfaceGlassScrim() : solid;
}

// 开关/档位变一次，所有读它的组件都要重新求值。与 MATERIAL_EPOCH 同一套办法。
export const SURFACE_GLASS_EPOCH: string = 'surfaceGlassEpoch';

export function bumpSurfaceGlassEpoch(): void {
  const now: number = AppStorage.get<number>(SURFACE_GLASS_EPOCH) ?? 0;
  AppStorage.setOrCreate(SURFACE_GLASS_EPOCH, now + 1);
}
