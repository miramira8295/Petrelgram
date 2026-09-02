// plain 行自绘 fast path 的排版缓存（绘制面刀 2，survey：
// docs/superpowers/specs/2026-09-02-draw-plane-survey.md）。
//
// 动机：富文本多路复用之外，纯文本行的 ArkUI Text 每次进视口都要原生排版
// （录制 20260902T162854：装填帧 ~5ms/行的成分之一）。这里用
// @ohos.graphics.text 自己排版一次、按内容键控缓存 Paragraph——同一条消息
// 在复用/翻页/回滚里反复进出视口时零重排，绘制走 DrawModifier.paint。
//
// ⚠️ 尚未接线（DrawnPlainText 组件有了但没有调用方）：graphics.text 与
// ArkUI Text 的排版一致性（行高取整/字重/emoji/RTL）必须真机 spike 验证
// 后才逐步放开。fast path 只接无实体、无链接的纯文本。
import { text } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { logE } from './log';

// 排版结果。paragraph 为 null 只出现在测试替身或排版失败的兜底里——调用方
// 拿到 null 必须回退 ArkUI Text 路径。
export interface PlainParagraph {
  paragraph: text.Paragraph | null;
  widthVp: number;
  heightVp: number;
}

export type ParagraphFactory = (
  content: string, maxWidthVp: number, fontSizeVp: number, colorArgb: number
) => PlainParagraph;

const CACHE_LIMIT: number = 192;
const cache: Map<string, PlainParagraph> = new Map<string, PlainParagraph>();

// vp→px 需要屏幕密度；display 在单测环境不可用，惰性取 + 兜底常数。
let cachedDensity: number = 0;
function densityPx(): number {
  if (cachedDensity > 0) {
    return cachedDensity;
  }
  try {
    cachedDensity = display.getDefaultDisplaySync().densityPixels;
  } catch (e) {
    logE(`paragraphCache density fallback: ${(e as Error).message}`);
    cachedDensity = 3.25;
  }
  return cachedDensity;
}

function buildParagraph(
  content: string, maxWidthVp: number, fontSizeVp: number, colorArgb: number
): PlainParagraph {
  try {
    const px: number = densityPx();
    const style: text.TextStyle = {
      color: {
        alpha: (colorArgb >>> 24) & 0xFF,
        red: (colorArgb >>> 16) & 0xFF,
        green: (colorArgb >>> 8) & 0xFF,
        blue: colorArgb & 0xFF
      },
      fontSize: fontSizeVp * px
    };
    const paragraphStyle: text.ParagraphStyle = { textStyle: style };
    const builder: text.ParagraphBuilder =
      new text.ParagraphBuilder(paragraphStyle, text.FontCollection.getGlobalInstance());
    builder.pushStyle(style);
    builder.addText(content);
    const paragraph: text.Paragraph = builder.build();
    paragraph.layoutSync(Math.max(1, maxWidthVp * px));
    return {
      paragraph: paragraph,
      widthVp: Math.min(maxWidthVp, Math.ceil(paragraph.getLongestLine() / px)),
      heightVp: Math.ceil(paragraph.getHeight() / px)
    };
  } catch (e) {
    // 排版失败不缓存 null 之外的东西：调用方回退 Text 路径。
    logE(`paragraphCache build failed: ${(e as Error).message}`);
    return { paragraph: null, widthVp: maxWidthVp, heightVp: 0 };
  }
}

let factory: ParagraphFactory = buildParagraph;

// 单测替身：注入假排版器，避免在测试环境触碰原生字体栈。传 null 还原。
export function setParagraphFactoryForTest(fn: ParagraphFactory | null): void {
  factory = fn ?? buildParagraph;
  cache.clear();
}

export function plainParagraphFor(
  content: string, maxWidthVp: number, fontSizeVp: number, colorArgb: number
): PlainParagraph {
  const key: string =
    `${fontSizeVp}|${colorArgb}|${Math.round(maxWidthVp)}|${content}`;
  const hit: PlainParagraph | undefined = cache.get(key);
  if (hit !== undefined) {
    // 命中挪到队尾（FIFO 变 LRU-ish：常驻视口的行不被淘汰）。
    cache.delete(key);
    cache.set(key, hit);
    return hit;
  }
  const laid: PlainParagraph = factory(content, maxWidthVp, fontSizeVp, colorArgb);
  if (laid.paragraph !== null || laid.heightVp > 0) {
    cache.set(key, laid);
    while (cache.size > CACHE_LIMIT) {
      const oldest: string | undefined = cache.keys().next().value as string | undefined;
      if (oldest === undefined) {
        break;
      }
      cache.delete(oldest);
    }
  }
  return laid;
}

export function paragraphCacheSize(): number {
  return cache.size;
}
