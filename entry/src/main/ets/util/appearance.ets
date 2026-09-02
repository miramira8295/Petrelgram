// 本地外观设置：应用强调色、收发气泡色（浅/深各一套）、气泡材质开关，以及
// 材质厚度/光感的深色份键。全部只存本机，不同步账号——和 PC 版的「主题」一个语义。
//
// 读取方不要直接拿键去 AppStorage 取色：走 recomputeAppearance()，它把当前模式
// 那份算进 theme.ets 的活绑定（COLOR_PRIMARY / COLOR_BUBBLE_*）再 bump epoch，
// 订阅了 APPEARANCE_EPOCH 的组件随之重绘。
import { isValidHex, textOn } from './colorMath';
import { mirrorChatEnvKey } from './chatEnvMirror';
import { BubbleColorSet, KEY_APP_DARK, applyAccentPrimary, applyBubbleColors } from './theme';

export const KEY_ACCENT_CUSTOM_ON: string = 'accentCustomOn';
export const KEY_ACCENT_HEX: string = 'accentHex';
export const KEY_ACCENT_HEX_DARK: string = 'accentHexDark';
export const KEY_BUBBLE_OUT_HEX: string = 'bubbleOutHex';
export const KEY_BUBBLE_OUT_HEX_DARK: string = 'bubbleOutHexDark';
export const KEY_BUBBLE_IN_HEX: string = 'bubbleInHex';
export const KEY_BUBBLE_IN_HEX_DARK: string = 'bubbleInHexDark';
export const KEY_BUBBLE_MATERIAL_ON: string = 'bubbleMaterialOn';
// 状态栏图标色是否跟着首页标题的颜色走。默认关：HDS 不设 systemBarStyle 时会
// 按标题栏内容色自己推，标题染了强调色状态栏就跟着变（用户报的），默认钉死
// 在深浅色上；想要那个联动效果的可以打开。
export const KEY_STATUS_FOLLOW_TITLE: string = 'statusFollowTitle';
// 厚度/光感的浅色份沿用 AppSettings 里原有的 materialThickness / materialLight，
// 深色份加 Dark 后缀——与 bgPatternStrength / bgPatternStrengthDark 同一套约定。
export const KEY_MATERIAL_THICKNESS_DARK: string = 'materialThicknessDark';
export const KEY_MATERIAL_LIGHT_DARK: string = 'materialLightDark';
export const APPEARANCE_EPOCH: string = 'appearanceEpoch';

export const APPEARANCE_HEX_KEYS: string[] = [
  KEY_ACCENT_HEX, KEY_ACCENT_HEX_DARK, KEY_BUBBLE_OUT_HEX, KEY_BUBBLE_OUT_HEX_DARK,
  KEY_BUBBLE_IN_HEX, KEY_BUBBLE_IN_HEX_DARK
];
export const BUBBLE_HEX_KEYS: string[] = [
  KEY_BUBBLE_OUT_HEX, KEY_BUBBLE_OUT_HEX_DARK, KEY_BUBBLE_IN_HEX, KEY_BUBBLE_IN_HEX_DARK
];

// 默认值 = resources/{base,dark}/element/color.json 里 primary / bubble_out / bubble_in。
export const ACCENT_DEFAULT_LIGHT: string = '#3390EC';
export const ACCENT_DEFAULT_DARK: string = '#57A8F2';
export const BUBBLE_OUT_DEFAULT_LIGHT: string = '#E1FFC7';
export const BUBBLE_OUT_DEFAULT_DARK: string = '#2B5278';
export const BUBBLE_IN_DEFAULT_LIGHT: string = '#FFFFFF';
export const BUBBLE_IN_DEFAULT_DARK: string = '#182533';

export function modeKey(base: string, dark: boolean): string {
  return dark ? `${base}Dark` : base;
}

export function hexOrDefault(raw: string | undefined, fallback: string): string {
  return raw !== undefined && isValidHex(raw) ? raw.toUpperCase() : fallback;
}

export function defaultHexFor(key: string): string {
  switch (key) {
    case KEY_ACCENT_HEX: return ACCENT_DEFAULT_LIGHT;
    case KEY_ACCENT_HEX_DARK: return ACCENT_DEFAULT_DARK;
    case KEY_BUBBLE_OUT_HEX: return BUBBLE_OUT_DEFAULT_LIGHT;
    case KEY_BUBBLE_OUT_HEX_DARK: return BUBBLE_OUT_DEFAULT_DARK;
    case KEY_BUBBLE_IN_HEX: return BUBBLE_IN_DEFAULT_LIGHT;
    case KEY_BUBBLE_IN_HEX_DARK: return BUBBLE_IN_DEFAULT_DARK;
    default: return ACCENT_DEFAULT_LIGHT;
  }
}

export function resolveBubbleColors(dark: boolean, outLight: string, outDark: string,
  inLight: string, inDark: string): BubbleColorSet {
  const out = dark ? outDark : outLight;
  const inn = dark ? inDark : inLight;
  return { out, inn, textOut: textOn(out), textIn: textOn(inn) };
}

export function appIsDark(): boolean {
  return AppStorage.get<boolean>(KEY_APP_DARK) ?? false;
}

export function bumpAppearanceEpoch(): void {
  const next: number = (AppStorage.get<number>(APPEARANCE_EPOCH) ?? 0) + 1;
  AppStorage.setOrCreate(APPEARANCE_EPOCH, next);
  mirrorChatEnvKey(APPEARANCE_EPOCH, next);
}

export function storedHex(key: string): string {
  return hexOrDefault(AppStorage.get<string>(key), defaultHexFor(key));
}

// 四个气泡色有任何一个偏离默认才接管；全默认时交回资源色，深浅色由资源系统切。
function bubbleCustomised(): boolean {
  for (const key of BUBBLE_HEX_KEYS) {
    if (storedHex(key) !== defaultHexFor(key)) {
      return true;
    }
  }
  return false;
}

export function currentAccentHex(): string {
  return storedHex(modeKey(KEY_ACCENT_HEX, appIsDark()));
}

export function currentBubbleColors(): BubbleColorSet {
  return resolveBubbleColors(appIsDark(), storedHex(KEY_BUBBLE_OUT_HEX),
    storedHex(KEY_BUBBLE_OUT_HEX_DARK), storedHex(KEY_BUBBLE_IN_HEX), storedHex(KEY_BUBBLE_IN_HEX_DARK));
}

// 读设置 → 重算 theme 的活绑定 → bump epoch。设置页写完值、模式切换、冷启动都调它。
export function recomputeAppearance(): void {
  const customAccent = AppStorage.get<boolean>(KEY_ACCENT_CUSTOM_ON) ?? false;
  applyAccentPrimary(customAccent ? currentAccentHex() : '');
  applyBubbleColors(bubbleCustomised() ? currentBubbleColors() : null);
  bumpAppearanceEpoch();
}
