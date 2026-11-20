// 整体卡片与气泡共用透明度档位；气泡保留自己的底色，不创建滤镜。
// 两面的开关与档位独立保存，首页卡片和聊天气泡可以分别调节。
import { normalizeThickness } from './materialTuning';
import {
  appIsDark, BUBBLE_IN_DEFAULT_LIGHT, BUBBLE_IN_DEFAULT_DARK,
  BUBBLE_OUT_DEFAULT_LIGHT, BUBBLE_OUT_DEFAULT_DARK
} from './appearance';
import { toRgbHex } from './colorMath';

export const KEY_SURFACE_GLASS_ON: string = 'surfaceGlassOn';
export const KEY_BUBBLE_GLASS_ON: string = 'bubbleGlassOn';
export const KEY_SURFACE_GLASS_LEVEL: string = 'surfaceGlassLevel';
export const KEY_BUBBLE_GLASS_LEVEL: string = 'bubbleGlassLevel';
export const SURFACE_GLASS_ON_DEFAULT: boolean = false;
export const BUBBLE_GLASS_ON_DEFAULT: boolean = false;

// 旧薄纱值只用于兼容，读取时统一解释为标准档，不再显示独立选项。
export const SURFACE_GLASS_LEVEL_VEIL: number = -4;
export const SURFACE_GLASS_LEVEL_DEFAULT: number = 0;

export function surfaceGlassOn(): boolean {
  return AppStorage.get<boolean>(KEY_SURFACE_GLASS_ON) ?? SURFACE_GLASS_ON_DEFAULT;
}

export function bubbleGlassOn(): boolean {
  return AppStorage.get<boolean>(KEY_BUBBLE_GLASS_ON) ?? BUBBLE_GLASS_ON_DEFAULT;
}

export function surfaceGlassLevel(): number {
  return readLevel(KEY_SURFACE_GLASS_LEVEL);
}

export function bubbleGlassLevel(): number {
  return readLevel(KEY_BUBBLE_GLASS_LEVEL);
}

function readLevel(key: string): number {
  return bubbleTintLevel(AppStorage.get<number>(key) ?? SURFACE_GLASS_LEVEL_DEFAULT);
}

// 开关另存布尔；档位异常或旧「关闭/薄纱」值不能变成数组的负下标。
export function bubbleTintLevel(level: number): number {
  const normalized: number = normalizeThickness(level);
  return normalized < -2 ? 0 : normalized;
}

// 超薄、薄、标准、厚、超厚：约 60%、70%、80%、90%、95%。
const BUBBLE_TINT_ALPHA: string[] = ['99', 'B3', 'CC', 'E6', 'F2'];
const BUBBLE_IN_RESOURCE_ID: number = $r('app.color.bubble_in').id;
const BUBBLE_OUT_RESOURCE_ID: number = $r('app.color.bubble_out').id;

export function bubbleTintFillHex(dark: boolean, level: number): string {
  const alpha = BUBBLE_TINT_ALPHA[bubbleTintLevel(level) + 2];
  return `#${alpha}${dark ? '232E3C' : 'FFFFFF'}`;
}

export function surfaceGlassFillHex(): string {
  return bubbleTintFillHex(appIsDark(), surfaceGlassLevel());
}

export function surfaceGlassFill(solid: ResourceColor): ResourceColor {
  return surfaceGlassOn() ? surfaceGlassFillHex() : solid;
}

export function bubbleGlassFill(solid: ResourceColor): ResourceColor {
  if (!bubbleGlassOn()) { return solid; }
  let hex: string = '';
  if (typeof solid === 'string') {
    hex = solid.length === 7 || solid.length === 9 ? toRgbHex(solid) : '';
  } else if (typeof solid === 'number') {
    hex = `#${(solid & 0xFFFFFF).toString(16).padStart(6, '0').toUpperCase()}`;
  } else {
    // These are the only resource fills supplied by bubble renderers. Resolve
    // the explicit app mode, not the potentially stale system resource mode.
    const name: string = String(solid.params?.[0] ?? '');
    if (name === 'app.color.bubble_in' || (name === '' && solid.id === BUBBLE_IN_RESOURCE_ID)) {
      hex = appIsDark() ? BUBBLE_IN_DEFAULT_DARK : BUBBLE_IN_DEFAULT_LIGHT;
    } else if (name === 'app.color.bubble_out' || (name === '' && solid.id === BUBBLE_OUT_RESOURCE_ID)) {
      hex = appIsDark() ? BUBBLE_OUT_DEFAULT_DARK : BUBBLE_OUT_DEFAULT_LIGHT;
    }
  }
  // Unknown colors retain their original fill instead of silently turning white.
  return hex === '' ? solid : `#${BUBBLE_TINT_ALPHA[bubbleGlassLevel() + 2]}${hex.substring(1)}`;
}

export const SURFACE_GLASS_EPOCH: string = 'surfaceGlassEpoch';

export function bumpSurfaceGlassEpoch(): void {
  const now: number = AppStorage.get<number>(SURFACE_GLASS_EPOCH) ?? 0;
  AppStorage.setOrCreate(SURFACE_GLASS_EPOCH, now + 1);
}
