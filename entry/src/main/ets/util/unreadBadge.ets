// 「↓」按钮右上角那颗未读数角标的尺寸与落点。
//
// 角标宽度随位数变（1 位 / 2 位 / 3 位 / 999+ 四档），而它是用绝对定位挂在按钮右上角
// 的——**位置得跟着宽度一起变**，否则数字一多角标就往右溢出。原来这两处是
// 分开写的两个表达式（width(...) 和 position({ x: 52 - ... })），改一处忘另一处
// 就是角标歪掉，而这种歪在截图里未必看得出来。
//
// 这里把"右边缘固定在 52"变成算出来的结果，并由单测钉住。

// 角标右边缘相对 Stack 左边的位置。按钮 46 宽、position x=6，所以右边缘正好
// 落在 6 + 46 = 52，角标与按钮右对齐。
export const BADGE_RIGHT_EDGE: number = 52;
export const BADGE_HEIGHT: number = 22;

// 上限 999+（2026-09-23 从 99+ 提上来）。4 个字符那档 41：12fp 中粗数字约
// 6.8vp/字，加左右各 ~6 的内边距；落点 52 − 41 = 11 仍在按钮范围内。
export const BADGE_TEXT_CAP: number = 999;

export function unreadBadgeWidth(count: number): number {
  if (count > BADGE_TEXT_CAP) {
    return 41;
  }
  if (count > 99) {
    return 34;
  }
  return count > 9 ? 27 : 22;
}

export function unreadBadgeOffsetX(count: number): number {
  return BADGE_RIGHT_EDGE - unreadBadgeWidth(count);
}

// 角标上的文字。超过 999 一律 999+，否则原样。
export function unreadBadgeText(count: number): string {
  return count > BADGE_TEXT_CAP ? `${BADGE_TEXT_CAP}+` : `${count}`;
}
