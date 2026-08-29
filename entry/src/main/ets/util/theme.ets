import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';

// Shared palette and dimensions for the UI. Colors resolve through the
// resource system (resources/base|dark/element/color.json), so the whole app
// follows the system light/dark mode automatically.
// Mutable on purpose: the user's local accent colour (util/appearance.ets)
// drives the app primary. ES module live bindings propagate reassignment to
// every importer; components subscribed to APPEARANCE_EPOCH redraw at once,
// the rest pick the new value when they rebuild. COLOR_TAB_SELECTED follows it.
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

// 强调色的淡底，给"整块染一层主色"的地方用（消息里的引用块）。
//
// COLOR_PRIMARY 有两种形态，必须分开处理：用户没自定义强调色时它是 Resource
// （跟随深浅色由资源系统解析），自定义之后是一个 '#RRGGBB' 字符串。
//
// Resource 那支没法在这里加透明度，直接交给 selected_pill——那本来就是默认
// 强调色 #3390EC 在深浅两套资源里各自调好的淡底（浅色 #E3F0FB / 深色
// #2B5278），比自己算一个准。字符串那支按 12% alpha 合成 '#AARRGGBB'，压在
// 气泡底色上深浅两种模式都读得出来。
export const ACCENT_SOFT_ALPHA: string = '1F';

export function accentSoftOf(primary: ResourceColor): ResourceColor {
  if (typeof primary === 'string' && primary.length === 7 && primary.startsWith('#')) {
    return `#${ACCENT_SOFT_ALPHA}${primary.substring(1)}`;
  }
  return $r('app.color.selected_pill');
}

export function accentSoft(): ResourceColor {
  return accentSoftOf(COLOR_PRIMARY);
}

export function applyAccentPrimary(hex: string): void {
  const next: ResourceColor = hex !== '' ? hex : $r('app.color.primary');
  COLOR_PRIMARY = next;
  COLOR_TAB_SELECTED = next;
}
export const COLOR_TEXT_PRIMARY: ResourceColor = $r('app.color.text_primary');
export const COLOR_TEXT_SECONDARY: ResourceColor = $r('app.color.text_secondary');
// 次级**图标**专用。和 text_secondary 在浅色下同值，深色下明显更亮：
// 深色的 text_secondary 是 #7D8B99，在 surface_alt(#2B3A4C) 上只有 3.32:1，
// 低于 4.5 的门槛；而图标是细笔画，同样对比度下比文字更难辨认，旁边又常年
// 挨着纯白的主文字，一比就发灰（用户报：深色模式下附件/表情/底栏图标看不清）。
// #AEBACA 在 page_bg/surface/surface_alt 三种底上是 8.28/6.99/5.89，够看又不至于
// 抢主文字的白。**浅色模式一个像素都没动**。
export const COLOR_ICON_SECONDARY: ResourceColor = $r('app.color.icon_secondary');
// 深色模式下 chrome 站到了**亮壁纸**上时用的前景（判定见 util/chatChrome）。
// 不做成主题资源：它们是为"亮底"挑的，与 app 处于哪个模式无关——深色模式下
// 恰好站到亮底上，正是这两个值存在的全部理由。
// 取值依据：在截图那种浅紫合成底 RGB(174,172,196) 上，图标 5.0:1、文字 12.6:1。
// APP 壁纸铺开之后，主界面的列表行改成浮在壁纸上的**半透明卡片**（用户选的方案 1）。
//
// 80% 不透明度不是随手取的：卡片压在最坏的壁纸（纯白/纯黑）上，合成底与行内文字
// 的对比度分别是 7.2:1 和 15.5:1，都远在 4.5 之上。也就是说这一层把**行内可读性
// 和壁纸彻底解耦**——列表里不需要再走一遍 util/chatChrome 那套按亮度翻前景的机制，
// 那套只留给真正浮在壁纸上、没有卡片托底的 chrome。
// 低于 0.7 就开始吃紧（纯白壁纸下 5.3:1），别往下调。
export function mainCardFill(wallpaperOn: boolean, pressed: boolean): ResourceColor {
  if (wallpaperOn) {
    return pressed ? $r('app.color.card_on_wallpaper_alt') : $r('app.color.card_on_wallpaper');
  }
  return pressed ? $r('app.color.surface_alt') : $r('app.color.surface');
}

// 主界面整页的底。壁纸生效时必须透明，否则壁纸被这层盖死。
export function mainPageFill(wallpaperOn: boolean): ResourceColor {
  return wallpaperOn ? Color.Transparent : $r('app.color.surface');
}

export const COLOR_ICON_ON_LIGHT: ResourceColor = '#333D49';
// 聊天页 chrome（顶栏 / 输入栏）在**暗底**上的前景：亮白，不是列表里那种次级灰。
//
// 这两条栏浮在壁纸上、周围没有卡片托底，用 #AEBACA 那种灰会糊进背景；而列表里的
// 图标坐在 surface 上、旁边就是卡片边界，灰一点反而不吵。用户原话：「深色模式，
// 会话详情输入框图标、顶栏文字应该都是亮白色」。
export const COLOR_ICON_ON_DARK: ResourceColor = '#FFFFFF';
export const COLOR_TEXT_ON_LIGHT: ResourceColor = '#0E1621';
export const COLOR_MUTED_BADGE: ResourceColor = $r('app.color.badge_bg');
export const AVATAR_SIZE: number = 56;
export const ROW_PAD_H: number = 14;
export const ROW_PAD_V: number = 8;
// Avatar placeholder palette — identical in both modes (like official clients).
export const AVATAR_PALETTE: string[] = ['#E17076', '#7BC862', '#65AADD', '#EE7AAE', '#6EC9CB', '#EFA92E', '#FAA774', '#A695E7'];
export let COLOR_TAB_SELECTED: ResourceColor = $r('app.color.primary');
// 底栏未选中态。**指向 icon_secondary 而不是 text_secondary**：它管的是底栏那排
// 图标和它们的标签，属于"浮在玻璃条上的 chrome"，和正文的次级文字是两回事。
//
// 这里曾经是 text_secondary，于是 2026-08-29 那轮提亮把它整条漏掉了——当时的
// 判别式是字面量 `fontColor([COLOR_TEXT_SECONDARY])`，而底栏写的是这个**别名**，
// 扫不到。用户报「底栏图标还是黑的看不清」，实测深色下 3.77:1（dock_glass 压在
// page_bg 上约 RGB(36,49,64)），换成 icon_secondary 是 6.68:1。
export const COLOR_TAB_UNSELECTED: ResourceColor = $r('app.color.icon_secondary');
export const COLOR_BADGE_BG: ResourceColor = $r('app.color.badge_bg');
export const COLOR_TAB_PILL_BG: ResourceColor = $r('app.color.tab_pill_bg');
// 三个气泡色也是活绑定：用户在「外观」里改了颜色，appearance.recomputeAppearance()
// 通过 applyBubbleColors() 重新赋值；没自定义时交回资源色跟随深浅色。
export let COLOR_BUBBLE_OUT: ResourceColor = $r('app.color.bubble_out');
export let COLOR_BUBBLE_IN: ResourceColor = $r('app.color.bubble_in');
// 收到气泡上的文字色。发出/收到底色可能一深一浅，气泡组件请用 bubbleTextFor()。
export let COLOR_BUBBLE_TEXT: ResourceColor = $r('app.color.bubble_text');
let bubbleTextOut: ResourceColor = $r('app.color.bubble_text');
let bubbleTextIn: ResourceColor = $r('app.color.bubble_text');

export interface BubbleColorSet {
  out: string;
  inn: string;
  textOut: string;
  textIn: string;
}

export function applyBubbleColors(c: BubbleColorSet | null): void {
  COLOR_BUBBLE_OUT = c !== null ? c.out : $r('app.color.bubble_out');
  COLOR_BUBBLE_IN = c !== null ? c.inn : $r('app.color.bubble_in');
  bubbleTextOut = c !== null ? c.textOut : $r('app.color.bubble_text');
  bubbleTextIn = c !== null ? c.textIn : $r('app.color.bubble_text');
  COLOR_BUBBLE_TEXT = bubbleTextIn;
}

export function bubbleTextFor(outgoing: boolean): ResourceColor {
  return outgoing ? bubbleTextOut : bubbleTextIn;
}
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
