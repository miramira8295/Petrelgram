// 下拉露出「归档的聊天」时那张卡片的形变曲线。
//
// 【为什么要形变】原来只有高度和透明度跟着下拉深度线性变化，卡片是"从一条缝里
// 平推出来"的，没有被拉出来的手感。加两条跟手的形变：卡片整体从 0.86 缩放到 1，
// 归档图标同时从 -90° 转正、从 0.6 放大到 1——手指还在拉的时候它就在"成形"，
// 松手到位那一下再用弹簧收尾。
//
// 【为什么是纯函数】这三条曲线要在 onDidScroll 每一帧被读到，改坏了只能靠肉眼
// 在真机上看。抽出来就能用断言钉住端点和单调性。

// 卡片完全成形时的缩放（即 1），和最小缩放。
const CARD_SCALE_MIN: number = 0.86;
// 图标转正之前的起始角度（度）。负值 = 逆时针转进来。
const ICON_SPIN_START: number = -90;
const ICON_SCALE_MIN: number = 0.6;

// 下拉进度，0..1。revealed 为真时恒为 1——已经锁定展开，不再跟手。
export function archiveRevealProgress(
  pullPx: number, rowHeight: number, revealed: boolean
): number {
  if (revealed) {
    return 1;
  }
  if (!Number.isFinite(pullPx) || !Number.isFinite(rowHeight) || rowHeight <= 0) {
    return 0;
  }
  const p: number = pullPx / rowHeight;
  if (p <= 0) {
    return 0;
  }
  return p >= 1 ? 1 : p;
}

// 卡片整体缩放：0.86 → 1。
export function archiveCardScale(progress: number): number {
  const p: number = clamp01(progress);
  return CARD_SCALE_MIN + (1 - CARD_SCALE_MIN) * p;
}

// 归档图标的旋转角（度）：-90 → 0。
export function archiveIconSpin(progress: number): number {
  return ICON_SPIN_START * (1 - clamp01(progress));
}

// 归档图标的缩放：0.6 → 1。比卡片本身更夸张一档，成形感集中在图标上。
export function archiveIconScale(progress: number): number {
  const p: number = clamp01(progress);
  return ICON_SCALE_MIN + (1 - ICON_SCALE_MIN) * p;
}

function clamp01(v: number): number {
  if (!Number.isFinite(v) || v <= 0) {
    return 0;
  }
  return v >= 1 ? 1 : v;
}
