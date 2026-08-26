// dock 胶囊两侧的留白。四个格子是 layoutWeight 均分的，藏掉「联系人」之后格子
// 会各自变宽、胶囊看着更空（issue #135）。按「保持每格宽度不变」反推：少一格
// 就把那一格的宽度均摊到两侧留白里。
//
// 纯函数：avail 是可用宽度（vp），base 是四格时的单侧留白。
export const DOCK_SIDE_PADDING: number = 40;
const FULL_ITEMS: number = 4;

export function dockSidePadding(availableVp: number, itemCount: number,
  base: number = DOCK_SIDE_PADDING): number {
  if (!Number.isFinite(availableVp) || availableVp <= 0
    || itemCount >= FULL_ITEMS || itemCount <= 0) {
    return base;
  }
  const inner: number = availableVp - base * 2;
  if (inner <= 0) {
    return base;
  }
  const perItem: number = inner / FULL_ITEMS;
  return Math.round(base + perItem * (FULL_ITEMS - itemCount) / 2);
}
