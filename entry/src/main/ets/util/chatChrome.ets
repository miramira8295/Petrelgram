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

// 判"亮"的阈值取 0.18 而不是常见的 0.5。
//
// 0.5 是"哪种文字更搭"的中点，但我们要的是**够不够看**：纯白前景要拿到 4.5:1，
// 底色亮度必须 ≤ (1.05 / 4.5 - 0.05) ≈ 0.183。底色一过这条线，白色前景就已经
// 不合格了，必须翻成深色。用 0.5 会把 L=0.3 这种"白字只有 3:1"的底判成暗底。
const LIGHT_THRESHOLD: number = 0.18;

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
export function chromeSitsOnLight(wallpaperColors: string[], tintArgb: string,
  fallbackOnLight: boolean, darkMask: number = 0): boolean {
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
    return fallbackOnLight;
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
  return relativeLuminance(mixed) > LIGHT_THRESHOLD;
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

export function chromeIconColorOf(onLight: boolean, appDark: boolean): ResourceColor {
  if (onLight) {
    return COLOR_ICON_ON_LIGHT;
  }
  // 深色模式下这两条栏浮在暗壁纸上，用亮白；浅色模式保持原来的次级灰——白色在
  // 浅色底上等于没有。
  return appDark ? COLOR_ICON_ON_DARK : COLOR_ICON_SECONDARY;
}

export function chromeTextColorOf(onLight: boolean): ResourceColor {
  return onLight ? COLOR_TEXT_ON_LIGHT : COLOR_TEXT_PRIMARY;
}
