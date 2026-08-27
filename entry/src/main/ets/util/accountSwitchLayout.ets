// 长按「个人资料」页签弹出的账号切换菜单：几何全在这里算，组件只负责画。
//
// 弹窗出现在手按下的位置：底边贴在按下点上方 ABOVE_FINGER，横向以按下点为中心，
// 整体钳在屏幕内。行数多到超过屏高的 MAX_HEIGHT_RATIO 就限高、内部滚动。
// 「手指不抬、滑到某行松开」也在这里判：给一个坐标，返回落在第几行。

export const ACCOUNT_ROW_H: number = 56;
export const ACCOUNT_POPUP_W: number = 248;
const SIDE_MARGIN: number = 12;
const ABOVE_FINGER: number = 8;
const MAX_HEIGHT_RATIO: number = 0.6;

export interface PopupRect {
  x: number;
  y: number;
  w: number;
  h: number;
  // 行数太多被限高了，内容要能滚。
  scrolls: boolean;
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

export function accountPopupRect(pressX: number, pressY: number, screenW: number, screenH: number,
  rowCount: number, rowH: number = ACCOUNT_ROW_H, w: number = ACCOUNT_POPUP_W): PopupRect {
  const rows: number = Math.max(0, rowCount);
  const natural: number = rows * rowH;
  const maxH: number = Math.max(rowH, Math.floor(screenH * MAX_HEIGHT_RATIO));
  const h: number = Math.min(natural, maxH);
  const width: number = Math.min(w, Math.max(0, screenW - SIDE_MARGIN * 2));
  const x: number = clamp(pressX - width / 2, SIDE_MARGIN, Math.max(SIDE_MARGIN, screenW - SIDE_MARGIN - width));
  const y: number = clamp(pressY - ABOVE_FINGER - h, SIDE_MARGIN, Math.max(SIDE_MARGIN, screenH - SIDE_MARGIN - h));
  return { x: x, y: y, w: width, h: h, scrolls: natural > h };
}

// 坐标落在第几行；不在弹窗里返回 -1。scrollOffset 是内容已经向上滚了多少。
export function accountRowAt(rect: PopupRect, rowCount: number, x: number, y: number,
  rowH: number = ACCOUNT_ROW_H, scrollOffset: number = 0): number {
  if (rowCount <= 0 || x < rect.x || x >= rect.x + rect.w || y < rect.y || y >= rect.y + rect.h) {
    return -1;
  }
  const idx: number = Math.floor((y - rect.y + scrollOffset) / rowH);
  return idx >= 0 && idx < rowCount ? idx : -1;
}
