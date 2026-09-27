import { ChatBackgroundState, emptyChatBackground } from '../store/ChatBackgroundStore';

// 纯色背景（2026-09-27 用户定：聊天背景支持纯色模式，默认跟随系统明暗）。
//
// 「跟随系统」不是色板里的一格颜色，而是**什么都不设**：状态为空时渲染层画
// app.color.chat_bg，它本身就随深浅色切换（浅 #EFEFF4 / 深 #0E1621）。
// 色板按深浅色各给一套：浅色档是低饱和的浅底，深色档是压暗的深底，两套都让
// 气泡与文字保持原有对比度，不去碰气泡配色。

export const SOLID_LIGHT_COLORS: string[] = [
  '#FFFFFF', '#F2F2F7', '#E4EEF8', '#E3F2E6', '#FFF3DE', '#FBE7EC', '#ECE6F6', '#DFF1EF'
];

export const SOLID_DARK_COLORS: string[] = [
  '#000000', '#1C1C1E', '#0F1C2B', '#12231A', '#251D12', '#27161C', '#1D172A', '#0F2120'
];

export function solidPaletteFor(dark: boolean): string[] {
  return dark ? SOLID_DARK_COLORS : SOLID_LIGHT_COLORS;
}

// '#RRGGBB' → TDLib backgroundFillSolid.color（24 位 RGB 整数）。格式不对返回 -1。
export function hexColorToInt(hex: string): number {
  if (!/^#[0-9a-fA-F]{6}$/.test(hex)) {
    return -1;
  }
  return Number.parseInt(hex.substring(1), 16);
}

// 纯色的背景状态。与 TDLib 回流的 backgroundTypeFill + backgroundFillSolid 经
// backgroundStateOf 得到的形状一致（一个颜色、无文件），APP 槽位直接存它。
export function solidBackgroundState(color: string): ChatBackgroundState {
  const state: ChatBackgroundState = emptyChatBackground();
  state.custom = true;
  state.colors = [color.toUpperCase()];
  return state;
}

// 当前背景是不是「跟随系统」：没有颜色也没有文件。
export function isSystemBackground(state: ChatBackgroundState): boolean {
  return state.colors.length === 0 && state.path === '';
}

// 当前背景是不是色板里的这一格纯色。图案 / 整图壁纸即使底色相同也不算。
export function isSolidBackgroundOf(state: ChatBackgroundState, color: string): boolean {
  return state.colors.length === 1 && state.path === '' && !state.isPattern &&
    state.colors[0].toUpperCase() === color.toUpperCase();
}

// 「跟随系统」那一格的色块颜色：与 resources 里 app.color.chat_bg 的浅 / 深两值一致。
// 设置页按**槽位**的深浅色画它，不能用 $r（那只会取当前系统模式的值）。
export const SYSTEM_CHAT_BG_LIGHT: string = '#EFEFF4';
export const SYSTEM_CHAT_BG_DARK: string = '#0E1621';

export function systemChatColor(dark: boolean): string {
  return dark ? SYSTEM_CHAT_BG_DARK : SYSTEM_CHAT_BG_LIGHT;
}
