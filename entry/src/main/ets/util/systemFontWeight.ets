import { Configuration } from '@kit.AbilityKit';
import { text } from '@kit.ArkGraphics2D';

// 系统「字体大小和界面缩放 › 字体粗细」的比例（Configuration.fontWeightScale）。
//
// ArkUI 的 Text 组件会自动跟随这个比例渲染，而自绘气泡走的是
// @ohos.graphics.text 的 paragraph，字重是写死的绝对值（W400/W500/W700）。
// 结果就是：用户在系统里把字调粗之后，除了聊天页，其它页面全都变粗了，
// 聊天页仍是 Regular —— 反馈里被描述成「聊天界面字体粗细没有了，全是最细的」。
//
// 所以自绘的每一处字重都要自己乘上这个比例，见 drawnWeightNormal/Medium/Bold。
export const KEY_SYS_FONT_WEIGHT_SCALE: string = 'sysFontWeightScale';
const DEFAULT_SCALE: number = 1;
// TEMP-EXPERIMENT：>0 时强制使用该比例做真机 A/B，交付前必须是 0。
const DEBUG_FORCE_SCALE: number = 0;

const WEIGHTS: text.FontWeight[] = [text.FontWeight.W100, text.FontWeight.W200, text.FontWeight.W300,
  text.FontWeight.W400, text.FontWeight.W500, text.FontWeight.W600, text.FontWeight.W700,
  text.FontWeight.W800, text.FontWeight.W900];

// 写进 AppStorage 供自绘缓存把它算进 key：比例一变，旧 plan 自然失效。
// 返回是否真的变了。
export function seedSystemFontWeightScale(config: Configuration | undefined): boolean {
  const raw: number | undefined = config === undefined ? undefined : config.fontWeightScale;
  const next: number = raw !== undefined && raw > 0 ? raw : DEFAULT_SCALE;
  const current: number | undefined = AppStorage.get<number>(KEY_SYS_FONT_WEIGHT_SCALE);
  if (current !== undefined && Math.abs(current - next) < 0.001) {
    return false;
  }
  AppStorage.setOrCreate<number>(KEY_SYS_FONT_WEIGHT_SCALE, next);
  return true;
}

export function systemFontWeightScale(): number {
  if (DEBUG_FORCE_SCALE > 0) {
    return DEBUG_FORCE_SCALE;
  }
  const value: number | undefined = AppStorage.get<number>(KEY_SYS_FONT_WEIGHT_SCALE);
  return value !== undefined && value > 0 ? value : DEFAULT_SCALE;
}

// 枚举值是 0..8 的下标（W400 = 3），所以先还原成 100..900 再乘比例，
// 取整回最近的整百档，最后夹在 [100, 900]。
function scaledWeight(baseWeight: number): text.FontWeight {
  const scale: number = systemFontWeightScale();
  if (scale === 1) {
    return WEIGHTS[baseWeight / 100 - 1];
  }
  const weight: number = Math.min(900, Math.max(100, Math.round(baseWeight * scale / 100) * 100));
  return WEIGHTS[weight / 100 - 1];
}

export function drawnWeightNormal(): text.FontWeight {
  return scaledWeight(400);
}

export function drawnWeightMedium(): text.FontWeight {
  return scaledWeight(500);
}

export function drawnWeightBold(): text.FontWeight {
  return scaledWeight(700);
}
