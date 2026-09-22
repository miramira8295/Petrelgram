import { image } from '@kit.ImageKit';
import {
  LatexMathColorFormat, TeXParseResult, TeXResultCode, latexStringToImageWithError
} from '@cangjie-tpc/formula_hybrid';
import { KEY_APP_DARK } from './theme';
import { logW } from './log';

// LaTeX 公式 → 位图。进程级缓存。
//
// 【为什么要缓存】渲染一次要过一趟仓颉侧的 TeX 排版，结果是一张位图。消息行
// 会反复 build（滚动、复用、旁路快照更新），每次都重排一遍公式既慢又白费。
// 同一条公式 + 同一档字号颜色 = 同一张图，算一次就够。
//
// 【为什么按 表达式+字号+颜色 做键】颜色是**烘进位图**的（库的入参就是前景色），
// 深浅色切换后旧图颜色不对；字号同理，超采样倍率变了图就得重出。
//
// 【失败要记下来】公式写错时 resultCode 非 0。不记的话每次 build 都会重新去
// 排一遍同一条坏公式——记成"这条不行"，调用方退回显示 LaTeX 原文。

export interface MathImage {
  pixel: image.PixelMap;
  // 位图的像素尺寸。ImageSpan 要显式宽高，按超采样倍率换算回显示尺寸。
  width: number;
  height: number;
}

// 公式很少，几十条足够；超了按插入顺序淘汰最旧的。
const MAX_ENTRIES: number = 64;

const cache: Map<string, MathImage> = new Map<string, MathImage>();
const failed: Set<string> = new Set<string>();
const inFlight: Set<string> = new Set<string>();

// 公式的前景色（ARGB 数值）。**颜色是烘进位图的**，所以它必须进缓存键。
//
// 【为什么在这里读 AppStorage，而不是让组件传进来】RichMessageView 是
// @ComponentV2，订阅不了 AppStorage；而气泡那一层现在根本没有深浅色这个信号，
// 为一条偶尔出现的公式往气泡的入参和复用键里加一个字段不划算。深浅色切换时
// EntryAbility 会 recomputeAppearance + bump 材质纪元，气泡本来就会整体重建，
// 那时这里自然读到新值、按新键重排一张。
export function mathForegroundColor(): number {
  return (AppStorage.get<boolean>(KEY_APP_DARK) ?? false) ? 0xFFFFFFFF : 0xFF0E1621;
}

export function mathKeyOf(expression: string, fontSize: number, colorArgb: number): string {
  return `${expression}|${fontSize}|${colorArgb}`;
}

export function mathImageFor(key: string): MathImage | undefined {
  return cache.get(key);
}

export function mathImageFailed(key: string): boolean {
  return failed.has(key);
}

function remember(key: string, entry: MathImage): void {
  cache.delete(key);
  cache.set(key, entry);
  while (cache.size > MAX_ENTRIES) {
    const oldest: string | undefined = cache.keys().next().value as string | undefined;
    if (oldest === undefined) {
      break;
    }
    cache.delete(oldest);
  }
}

// 排一条公式。已经有结果、已经失败过、或正在排的，直接返回不重复发起。
// onReady 只在**这一次真的产出新图**时回调，调用方据此触发重绘。
export function ensureMathImage(expression: string, fontSize: number, colorArgb: number,
  onReady: () => void): void {
  const trimmed: string = expression.trim();
  if (trimmed === '' || fontSize <= 0) {
    return;
  }
  const key: string = mathKeyOf(trimmed, fontSize, colorArgb);
  if (cache.has(key) || failed.has(key) || inFlight.has(key)) {
    return;
  }
  inFlight.add(key);
  // 背景透明：公式要落在气泡底色/壁纸上，不能自带一块白板。
  latexStringToImageWithError(trimmed, fontSize, colorArgb, 0x00000000,
    LatexMathColorFormat.COLOR_FORMAT_BGRA_8888)
    .then((result: TeXParseResult): Promise<void> => {
      if (result.resultCode !== TeXResultCode.Success) {
        inFlight.delete(key);
        failed.add(key);
        logW(`[Math] parse failed code=${result.resultCode}`);
        return Promise.resolve();
      }
      const source: image.ImageSource = image.createImageSource(result.imageBytes);
      return source.createPixelMap().then((pixel: image.PixelMap): Promise<void> => {
        return pixel.getImageInfo().then((info: image.ImageInfo): void => {
          inFlight.delete(key);
          remember(key, {
            pixel, width: info.size.width, height: info.size.height
          });
          onReady();
        });
      });
    })
    .catch((e: Error): void => {
      inFlight.delete(key);
      failed.add(key);
      logW(`[Math] render failed: ${e.message}`);
    });
}

export function resetMathImageCacheForTest(): void {
  cache.clear();
  failed.clear();
  inFlight.clear();
}
