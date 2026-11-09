// 长按菜单要不要带气泡预览图（MenuPreviewMode.IMAGE）。
//
// 窗口装不下「预览 + 菜单」时 ArkUI 不是弹个小的，而是**干脆不弹**：悬浮小窗 +
// 键盘展开就是这样（issue #114，1ef1599）。判据两条：键盘起来了，或窗口本身就
// 矮——480vp 以下只有悬浮小窗和分屏下半截会碰到，正常手机竖屏远大于此。
//
// 抽成纯函数是因为两种气泡（MessageBubble / LightweightPlainTextBubble）都要
// 判：1.4.2 只在 MessageBubble 上做了，纯文本走的是轻量气泡，最常见的长按目标
// 依旧弹不出来。
export const MENU_PREVIEW_MIN_WINDOW_H: number = 480;

export function menuPreviewCompact(keyboardH: number, windowH: number): boolean {
  return keyboardH > 0 || windowH < MENU_PREVIEW_MIN_WINDOW_H;
}
