import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';

// Shared palette and dimensions for the UI. Colors resolve through the
// resource system (resources/base|dark/element/color.json), so the whole app
// follows the system light/dark mode automatically.
// Mutable on purpose: the profile accent color drives the app primary. ES
// module live bindings propagate reassignment to every importer; components
// built after applyAccentPrimary() pick the new value, already-mounted pages
// refresh when they rebuild (re-enter). COLOR_TAB_SELECTED follows it.
export let COLOR_PRIMARY: ResourceColor = $r('app.color.primary');

// Pure: does this colorMode value mean the app is currently in dark mode?
// Takes a plain number rather than an enum type so the same check works for
// resourceManager.ColorMode (DARK=0/LIGHT=1 — what
// getConfigurationSync().colorMode actually returns, and what this is
// written against) and for anything else numerically compatible, such as
// ConfigurationConstant.ColorMode (DARK=0/LIGHT=1/NOT_SET=-1, used
// elsewhere in AppSettings for setColorMode()) — both agree DARK is 0.
// NOTE: DARK === 0, not 1 — the enum order is the reverse of what most
// booleans-as-numbers APIs use. Never replace this with a raw `=== 1` check.
export function isDarkColorMode(colorMode: number): boolean {
  return colorMode === resourceManager.ColorMode.DARK;
}

// Whether the app is currently rendering in dark mode. Reads
// resourceManager's own reported colorMode directly instead of reading a
// themed color resource ($r('app.color.chat_bg')) and inferring brightness
// from its RGB via a luminance threshold — that indirect probe was found
// on-device to disagree with colorMode: getConfigurationSync().colorMode
// correctly reported dark while getColorSync(chat_bg) on the very same
// resourceManager still resolved the light-qualifier color. See
// .superpowers/sdd/background-diagnosis-report.md for the trace that
// pinned this down. This replaces five copies of the old luminance probe
// that used to live in ChatPage, MainScreen, ChatThemePage, AccentColorPage
// and accentTheme.
// 当前是否深色模式，供界面用 @StorageProp 订阅。darkResourceMode() 要拿
// context、只能算一次，做不到"模式一变界面就跟着变"；这个键由 EntryAbility
// 在窗口创建和 onConfigurationUpdate 时写，读的人自然会重建。
export const KEY_APP_DARK: string = 'appIsDark';

export function darkResourceMode(context: common.UIAbilityContext): boolean {
  try {
    return isDarkColorMode(context.resourceManager.getConfigurationSync().colorMode);
  } catch (_error) {
    return false;
  }
}

export function applyAccentPrimary(hex: string): void {
  const next: ResourceColor = hex !== '' ? hex : $r('app.color.primary');
  COLOR_PRIMARY = next;
  COLOR_TAB_SELECTED = next;
}
export const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.text_primary');
export const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.text_secondary');
export const COLOR_MUTED_BADGE: ResourceColor = $r('app.color.badge_bg');
export const AVATAR_SIZE: number = 56;
export const ROW_PAD_H: number = 14;
export const ROW_PAD_V: number = 8;
// Avatar placeholder palette — identical in both modes (like official clients).
export const AVATAR_PALETTE: string[] = ['#E17076', '#7BC862', '#65AADD', '#EE7AAE', '#6EC9CB', '#EFA92E', '#FAA774', '#A695E7'];
export let COLOR_TAB_SELECTED: ResourceColor = $r('app.color.primary');
export const COLOR_TAB_UNSELECTED: ResourceColor = $r('app.color.text_secondary');
export const COLOR_BADGE_BG: ResourceColor = $r('app.color.badge_bg');
export const COLOR_TAB_PILL_BG: ResourceColor = $r('app.color.tab_pill_bg');
export const COLOR_BUBBLE_OUT: ResourceColor = $r('app.color.bubble_out');
export const COLOR_BUBBLE_IN: ResourceColor = $r('app.color.bubble_in');
export const COLOR_BUBBLE_TEXT: ResourceColor = $r('app.color.bubble_text');
// Frequently used surfaces (cards, headers, inputs) and page backgrounds.
export const COLOR_SURFACE: ResourceColor = $r('app.color.surface');
export const COLOR_PAGE_BG: ResourceColor = $r('app.color.page_bg');
export const COLOR_CHAT_BG: ResourceColor = $r('app.color.chat_bg');
export const COLOR_DIVIDER: ResourceColor = $r('app.color.divider');

// Bot-chosen button colors (TDLib buttonStyle*): dark blue / green / red,
// matching the official clients. Returns `fallback` for the default style.
export function botButtonBg(style: string, fallback: ResourceColor): ResourceColor {
  if (style === 'primary') {
    return $r('app.color.primary');
  }
  if (style === 'success') {
    return '#34C759';
  }
  if (style === 'danger') {
    return '#FF3B30';
  }
  return fallback;
}
