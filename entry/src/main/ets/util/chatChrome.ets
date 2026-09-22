import { relativeLuminance } from './colorMath';
import { COLOR_ICON_ON_DARK, COLOR_ICON_ON_LIGHT, COLOR_ICON_SECONDARY, COLOR_TEXT_ON_LIGHT,
  COLOR_TEXT_PRIMARY } from './theme';

// 聊天页的 chrome（顶栏 / 置顶条 / 输入栏）**浮在用户的聊天壁纸上**，玻璃层只是
// 薄薄一色。所以它们实际坐在亮底还是暗底，取决于**壁纸**，而不是 app 的深浅色模式。
//
// 【为什么必须按壁纸判——真机数字】深色模式 + 用户自设的浅紫壁纸，2026-08-29 截图：
//   · 玻璃走 material_tint（25% 深色）时，输入栏合成底约 RGB(174,172,196)；
//   · 图标 #AEBACA 在其上 **1.13:1**，连纯白的主文字也只有 **2.22:1** —— 整条栏
//     根本不可读，而且这跟图标取什么色关系不大：换回旧的 #7D8B99 也只有 1.57:1。
// 靠加厚玻璃救不了：把图标顶到 4.5:1 需要 alpha ≈ 0.90，那就不是玻璃是实心板了。
// 唯一的出路是让前景色跟着壁纸翻。
//
// 【默认壁纸不受影响】chat_bg 深色 #0E1621（L≈0.009）、浅色 #EFEFF4（L≈0.86），
// 本来就和主题一致。只有用户自己设了浅色壁纸，chrome 才会站到亮底上。

// 判"亮"的分界线。**不是一个常数**——见下。
//
// 【0.179 是白字和黑字的真正交点】前景取纯白时对比度 = 1.05/(L+0.05)，取纯黑时
// = (L+0.05)/0.05。两者相等解出 L = 0.179。底色比它亮，黑字更清楚；比它暗，白字
// 更清楚。第一版的 0.18 取的就是这个交点，推导没错。
const BREAKEVEN_LUMINANCE: number = 0.179;

// 【错的是把 chromeBackdropLuminance 当成了真实底色】它只合成
// 「壁纸填充 → 遮罩 → 玻璃」，漏掉两样**只会让底更暗、不会更亮**的东西：
//   1. 图案壁纸上那层深色涂鸦；
//   2. **chrome 浮在消息列表上，不是浮在壁纸上**——深色模式下背后大多是深色气泡
//      （连最亮的发出气泡 #1477D8 也只有 L≈0.183）。
// 所以它的输出是真实底色的**上界**，拿上界去卡交点必然偏向黑字。
//
// 2026-09-22 真机（深色模式，图案壁纸 #8ADBF2/#888DEC/#E39FEA/#679CED，
// 服务端 dimming=0、用户遮罩=0）探针 + 截图逐像素对照：
//
//   本函数算出来                                  L = 0.278  → 判"亮底"，前景翻黑
//   返回键那个圆（背后只有壁纸）                    L = 0.201
//   输入栏                                        L = 0.153
//   置顶条                                        L = 0.080
//   标题胶囊（背后压着一条深色气泡）                L = 0.044 → 黑字 1.88:1、白字 11.15:1
//
// 【余量为什么按玻璃的透明度缩放】没被建模的那部分，正好就是玻璃**没盖住**的
// 那一份：合成式里 (1-alpha) 这一项。玻璃越薄，背后的气泡透过来越多，上界越松；
// 玻璃越厚（材质不可用时的降级档 55%），玻璃自己就决定了观感，上界越准。
// 所以余量 = MARGIN_PER_UNSEEN x (1 - alpha)，而不是一个拍死的常数。
//
// 【0.20 这个系数的上下界都是真机/物理约束，不是拟合】
//   · 下界：本次 25% 材质玻璃，上界 0.278 必须判成"不亮"  → 系数 > 0.131
//   · 上界：55% 降级玻璃 + 纯白壁纸，上界 0.300（这一档玻璃厚、上界准，白字
//     只有 3.0:1）必须仍判"亮底" → 系数 < 0.266
//   取中间的 0.20。
//   · 2026-08-29 那次（本机制的起因，25% 材质玻璃 + 浅紫壁纸）屏幕上量到的合成底
//     就已经是 RGB(174,172,196) = L 0.427，估算只会更亮，照旧判亮底，行为不变。
const MARGIN_PER_UNSEEN: number = 0.20;

// 反过来那一侧：合成底暗到这个程度以下，**浅色模式**的深色前景就读不出来了
// （用户 2026-09-18：浅色模式 + 纯黑壁纸，按钮上的图标还是黑的）。
//
// 【为什么这一侧不缩放余量】上面那套余量说的是"背后的深色气泡会让底比估算更暗"，
// 那是**深色模式**独有的。浅色模式下背后是浅色气泡，估算偏差指向相反方向，
// 拿同一个余量套过来只会让它更早翻白。这条线维持常数，且刻意不和上面那条对称——
// 两条线之间留一段中间地带，灰壁纸才不会在两种前景之间来回跳。
const DARK_THRESHOLD: number = 0.10;

// '#AARRGGBB' 或 '#RRGGBB' → [alpha(0..1), r, g, b]。取不出来时返回全 0 的不透明黑，
// 由调用方的 fallback 兜住（脏色值不该让 chrome 变色）。
function argbOf(hex: string): number[] {
  const h: string = hex.startsWith('#') ? hex.substring(1) : hex;
  if (h.length === 8) {
    return [parseInt(h.substring(0, 2), 16) / 255, parseInt(h.substring(2, 4), 16),
      parseInt(h.substring(4, 6), 16), parseInt(h.substring(6, 8), 16)];
  }
  if (h.length === 6) {
    return [1, parseInt(h.substring(0, 2), 16), parseInt(h.substring(2, 4), 16),
      parseInt(h.substring(4, 6), 16)];
  }
  return [-1, 0, 0, 0];
}

function hex2(v: number): string {
  const n: number = Math.max(0, Math.min(255, Math.round(v)));
  return n < 16 ? `0${n.toString(16)}` : n.toString(16);
}

// 玻璃填充的 alpha；取不出来按"没有玻璃"算（余量给满）。
function tintAlphaOf(tintArgb: string): number {
  const tint: number[] = argbOf(tintArgb);
  return tint[0] < 0 ? 0 : tint[0];
}

function lightThresholdFor(tintArgb: string): number {
  return BREAKEVEN_LUMINANCE + MARGIN_PER_UNSEEN * (1 - tintAlphaOf(tintArgb));
}

// chrome 是不是坐在亮底上。
//
// wallpaperColors：ChatBackgroundState.colors（渐变/图案的填充色，图片壁纸时为空）。
// tintArgb：玻璃层的填充，形如 '#402F3F52'。
// fallbackOnLight：取不到壁纸颜色时的答案，由调用方按当前主题给（浅色 true）。
//
// 图片壁纸拿不到颜色（要解码采样，代价太大），一律走 fallback——那正是"按主题判"
// 的旧行为，不会比现在更差。
// darkMask：深色模式下压在整层壁纸上的黑色遮罩不透明度（0..1）。
//
// **漏掉它是个真错**（用户报：深色模式下顶栏/输入栏图标变成了深色）。Telegram 的
// 壁纸——尤其图案类——填充色常常是浅的（真机一例：#DBDDBB,#6BA587,#D5D88D,#88B884，
// 平均是浅绿），但深色模式下 ChatBackdrop 会在整层上再压一层黑：壁纸自带的
// dark_theme_dimming（服务端下发，通常 50% 以上）加上用户那根遮罩滑杆。
// 于是**填充浅 + 遮罩重 = 屏幕上其实是深的**，而只看填充色的判定会一口咬定"亮底"，
// 把前景翻成深色——正好和实际相反。
// 合成底的相对亮度；壁纸没有颜色（是图片）时返回 -1 表示"判不了"。
export function chromeBackdropLuminance(wallpaperColors: string[], tintArgb: string,
  darkMask: number = 0): number {
  let r: number = 0;
  let g: number = 0;
  let b: number = 0;
  let n: number = 0;
  for (const stop of wallpaperColors) {
    const c: number[] = argbOf(stop);
    if (c[0] < 0) {
      continue;
    }
    // 渐变按各停靠点取均值。chrome 横跨整条宽度，看到的本来就是平均，
    // 不需要还原真实的渐变分布。
    r += c[1];
    g += c[2];
    b += c[3];
    n++;
  }
  if (n === 0) {
    return -1;
  }
  // 合成顺序要和 ChatBackdrop 画的一致：壁纸 → 黑色遮罩 → 玻璃层。遮罩画在整层
  // 末尾（见 ChatBackdrop.darkMaskOpacity 那段注释），所以它先于玻璃压上去。
  const mask: number = Math.max(0, Math.min(1, darkMask));
  const wr: number = (r / n) * (1 - mask);
  const wg: number = (g / n) * (1 - mask);
  const wb: number = (b / n) * (1 - mask);
  const tint: number[] = argbOf(tintArgb);
  const a: number = tint[0] < 0 ? 0 : tint[0];
  const mixed: string = '#' +
    hex2(a * tint[1] + (1 - a) * wr) +
    hex2(a * tint[2] + (1 - a) * wg) +
    hex2(a * tint[3] + (1 - a) * wb);
  return relativeLuminance(mixed);
}

export function chromeSitsOnLight(wallpaperColors: string[], tintArgb: string,
  fallbackOnLight: boolean, darkMask: number = 0): boolean {
  const luminance: number = chromeBackdropLuminance(wallpaperColors, tintArgb, darkMask);
  return luminance < 0 ? fallbackOnLight : luminance > lightThresholdFor(tintArgb);
}

// 和 chromeSitsOnLight 同一套合成，只是判另一头：合成底够不够暗。
// 取不到壁纸颜色时返回 fallbackOnDark（调用方给 false = 保持旧行为）。
export function chromeSitsOnDark(wallpaperColors: string[], tintArgb: string,
  fallbackOnDark: boolean, darkMask: number = 0): boolean {
  const luminance: number = chromeBackdropLuminance(wallpaperColors, tintArgb, darkMask);
  return luminance < 0 ? fallbackOnDark : luminance < DARK_THRESHOLD;
}

// ── chrome 的前景要跟着**壁纸**翻，不是跟着深浅色模式 ───────────────────
//
// 下面四个是 ChatPage 的 chromeDarkMask/chromeOnLightBg/chromeIcon/chromeText
// 原样下沉（B3）。页面侧只剩「读字段 → 调这里 → 交给组件」的薄包装，判据全在
// 本文件，由 entry/src/test/ChatChrome.test.ets 钉住。

// 深色模式下压在整层壁纸上的黑，两层叠加：壁纸自带的 dark_theme_dimming（服务端
// 下发）和用户那根遮罩滑杆。ChatBackdrop 是分两层画的，所以这里按不透明度叠加
// 公式合成，而不是简单相加。
//
// 漏掉这一项就是用户报的那个错：图案壁纸的填充色常常是浅的，只看填充会判成
// 亮底、把前景翻成深色，而屏幕上其实是深的。
export function chromeDarkMaskOf(serverDimming: number, userDim: number): number {
  const server: number = Math.max(0, Math.min(1, serverDimming));
  const user: number = Math.max(0, Math.min(1, userDim));
  return 1 - (1 - server) * (1 - user);
}

// 顶栏/置顶条/输入栏浮在聊天壁纸上，玻璃只是薄薄一层。用户在深色模式下设了
// 一张浅色壁纸时，这几条栏其实坐在**亮底**上——真机实测合成底 RGB(174,172,196)，
// 图标 1.13:1、连纯白主文字也只有 2.22:1，整条栏不可读。加厚玻璃救不了
// （要 alpha≈0.90 才够，那就不是玻璃了），只能翻前景。判据见上面的
// chromeSitsOnLight。
//
// **只在深色模式下才翻**：浅色模式的前景本来就是给亮底挑的，不用动，也就
// 保证了这次改动对浅色模式零影响。
//
// 除了这道 appDark 闸，本函数就是 chromeSitsOnLight 的一层薄封装：
// tintArgb 由调用方给（页面传 glassTintHex(true)——玻璃厚度是设备态，不能进
// 纯函数），darkMask 由调用方先过 chromeDarkMaskOf。取不到壁纸颜色时的
// fallback 恒为 false：这条路径只在深色模式下走得到，暗底就是它的旧行为。
export function chromeOnLightBgOf(appDark: boolean, wallpaperColors: string[],
  tintArgb: string, darkMask: number): boolean {
  return appDark && chromeSitsOnLight(wallpaperColors, tintArgb, false, darkMask);
}

// 浅色模式 + 暗壁纸：和上面那条正好相反的一侧。
//
// 【为什么原来没有这一半】上面那段注释写着"只在深色模式下才翻，浅色模式的前景
// 本来就是给亮底挑的"——那句话的前提是"浅色模式下壁纸也是浅的"。用户把壁纸设成
// 纯黑就把这个前提打掉了：前景仍按亮底取深色，浮在黑壁纸上的那些按钮于是全黑
// （2026-09-18 实报）。
//
// tintArgb 这里要传**浅色**的玻璃色（glassTintHex(false)）：合成的是浅色模式下
// 那层玻璃，传错就等于按另一种模式在算底。
export function chromeOnDarkBgOf(appDark: boolean, wallpaperColors: string[],
  tintArgb: string, darkMask: number): boolean {
  return !appDark && chromeSitsOnDark(wallpaperColors, tintArgb, false, darkMask);
}

export function chromeIconColorOf(
  onLight: boolean, appDark: boolean, onDark: boolean = false
): ResourceColor {
  if (onLight) {
    return COLOR_ICON_ON_LIGHT;
  }
  if (onDark) {
    return COLOR_ICON_ON_DARK;
  }
  // 深色模式下这两条栏浮在暗壁纸上，用亮白；浅色模式保持原来的次级灰——白色在
  // 浅色底上等于没有。
  return appDark ? COLOR_ICON_ON_DARK : COLOR_ICON_SECONDARY;
}

export function chromeTextColorOf(onLight: boolean, onDark: boolean = false): ResourceColor {
  if (onLight) {
    return COLOR_TEXT_ON_LIGHT;
  }
  // 浅色模式 + 暗壁纸：主文字翻白，否则黑字压在黑壁纸上什么都看不见。
  return onDark ? COLOR_ICON_ON_DARK : COLOR_TEXT_PRIMARY;
}
