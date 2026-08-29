import {
  KEY_APP_BG_BLUR, KEY_APP_BG_DIM, KEY_APP_BG_PATTERN_DARK, KEY_APP_BG_PATTERN_LIGHT,
  KEY_APP_BG_STATE_DARK, KEY_APP_BG_STATE_LIGHT, KEY_BG_BLUR, KEY_BG_BLUR_DARK,
  KEY_BG_PATTERN, KEY_BG_PATTERN_DARK, KEY_CHAT_DIM, KEY_CHAT_DIM_LIGHT
} from '../store/AppSettings';

// 壁纸的四个槽位：APP 浅色 / APP 深色 / 聊天浅色 / 聊天深色。
//
// 每个槽位有自己的壁纸和三根滑杆（纹理 / 深色遮罩 / 模糊）。把「槽位 → 该读写
// 哪几个键」收成一处纯函数，是因为这条映射会被四条路径各用一遍（渲染、设置页的
// 缩略图、编辑页的读、编辑页的写）；散着写必然有一处对不上，而那种错在界面上
// 表现为"调了浅色的滑杆、深色跟着变"，极难查。
export const SLOT_APP_LIGHT: string = 'appLight';
export const SLOT_APP_DARK: string = 'appDark';
export const SLOT_CHAT_LIGHT: string = 'chatLight';
export const SLOT_CHAT_DARK: string = 'chatDark';

export const WALLPAPER_SLOTS: string[] =
  [SLOT_APP_LIGHT, SLOT_APP_DARK, SLOT_CHAT_LIGHT, SLOT_CHAT_DARK];

export interface WallpaperSlotKeys {
  // 序列化的 ChatBackgroundState。**只有 APP 槽位有**——聊天槽位的壁纸由 TDLib
  // 下发（账号级同步），本地不存一份，否则两边会打架。
  state: string;
  pattern: string;
  blur: string;
  dim: string;
}

export function slotIsApp(slot: string): boolean {
  return slot === SLOT_APP_LIGHT || slot === SLOT_APP_DARK;
}

export function slotIsDark(slot: string): boolean {
  return slot === SLOT_APP_DARK || slot === SLOT_CHAT_DARK;
}

// 深色遮罩只对深色槽位有意义：那一层在浅色模式下恒为 0（压暗浅色界面只会发脏，
// 见 ChatBackdrop.darkMaskOpacity / AppBackdrop.maskOpacity）。浅色槽位仍然有
// 一个 dim 键，只是读写路径一致、值不参与渲染——给用户摆一根无效的滑杆会让人
// 以为坏了，所以设置页据此隐藏它。
export function slotHasDim(slot: string): boolean {
  return slotIsDark(slot);
}

export function wallpaperSlotKeys(slot: string): WallpaperSlotKeys {
  if (slot === SLOT_APP_LIGHT) {
    return {
      state: KEY_APP_BG_STATE_LIGHT, pattern: KEY_APP_BG_PATTERN_LIGHT,
      blur: KEY_APP_BG_BLUR, dim: KEY_APP_BG_DIM
    };
  }
  if (slot === SLOT_APP_DARK) {
    return {
      state: KEY_APP_BG_STATE_DARK, pattern: KEY_APP_BG_PATTERN_DARK,
      blur: KEY_APP_BG_BLUR, dim: KEY_APP_BG_DIM
    };
  }
  if (slot === SLOT_CHAT_DARK) {
    return {
      state: '', pattern: KEY_BG_PATTERN_DARK, blur: KEY_BG_BLUR_DARK, dim: KEY_CHAT_DIM
    };
  }
  // 聊天浅色，也是未知槽位的兜底：读到默认值总好过读到 undefined。
  return {
    state: '', pattern: KEY_BG_PATTERN, blur: KEY_BG_BLUR, dim: KEY_CHAT_DIM_LIGHT
  };
}
