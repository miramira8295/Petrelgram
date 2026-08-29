import { relativeLuminance } from './colorMath';

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
export function chromeSitsOnLight(wallpaperColors: string[], tintArgb: string,
  fallbackOnLight: boolean): boolean {
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
  const tint: number[] = argbOf(tintArgb);
  const a: number = tint[0] < 0 ? 0 : tint[0];
  const mixed: string = '#' +
    hex2(a * tint[1] + (1 - a) * (r / n)) +
    hex2(a * tint[2] + (1 - a) * (g / n)) +
    hex2(a * tint[3] + (1 - a) * (b / n));
  return relativeLuminance(mixed) > LIGHT_THRESHOLD;
}
