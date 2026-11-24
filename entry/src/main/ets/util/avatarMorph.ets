// 个人资料 / 联系人 / 群组三种资料页共用的「下拉放大头像」几何参数。
//
// 曲线是**分轴**的（ArkGram v3.3 设置页 ProfileHeader 的真实形态）：宽先顶满屏宽、
// 高后到 390，圆角与卡底圆环按 ratio 收到 0，同时整块往上移，直到照片顶边贴住屏幕 0。
//
// 行程（用户 2026-11-24 定的）：手指要拉出去 115vp 才完全展开，实测慢拖越界能到 187vp，
// 覆盖手指行程的六成以上——太短（60/80）会「一下就拉出来、没有 Q 弹感」。
//
// 关键：Scroll/List 越界时**内容整体被向下平移 |yOffset|**，所以 offsetY 里必须再减掉
// pull，否则手指后半程会把照片整体往下带（顶上露出白条，只有松手回弹才合上）。

export const AVATAR_BASE: number = 100;        // 收起态照片边长
export const AVATAR_RATIO_SPAN: number = 115;  // 圆角/圆环/上移走完的行程（照片顶边在这贴到 0）
export const AVATAR_W_GAIN: number = 3.39;     // 下拉每 vp 宽涨多少（≈86vp 顶满屏宽）
export const AVATAR_H_GAIN: number = 2.6;      // 下拉每 vp 高涨多少（≈112vp 到 390）
export const AVATAR_TOP_LIFT: number = 12;     // 收起态整体上移多少 vp（用户：提一点点）
export const AVATAR_EXPANDED_H: number = 390;  // 展开态高度
export const AVATAR_CARD_RADIUS: number = 16; // 展开态圆角（跟内容卡片一致，不再收成 0）
export const AVATAR_RING: number = 4;          // 头像卡底圆环宽度（随 ratio 收到 0）
export const AVATAR_EXPAND_AT: number = 115;   // 下拉超过它自动展开（= 形变走完的位置）
export const AVATAR_COLLAPSE_AT: number = 14;  // 展开后回滚超过它自动收起
export const AVATAR_SNAP_MS: number = 420;     // 展开/收起动画时长
export const AVATAR_TEXT_INSET: number = 20;   // 展开态文字的左缩进
export const AVATAR_TEXT_BOTTOM: number = 28;  // 展开态文字块底边距照片底边
export const AVATAR_TEXT_H: number = 60;       // 名字 + 副标题块的固定高度（**不测量**，见页内注释）
export const AVATAR_HEAD_ROW: number = 44;     // 页头返回/菜单那一行占的高度（收起态预留）
export const AVATAR_HEAD_GAP: number = 8;      // 那一行与头像之间的间距
export const AVATAR_BUTTON_INSET: number = 12; // 展开态两颗悬浮圆钮从照片上边/左右边往里让出多少

export function avatarRatioOf(pull: number, expanded: boolean): number {
  return expanded ? 1 : Math.min(pull / AVATAR_RATIO_SPAN, 1);
}

export function avatarWidthOf(pull: number, expanded: boolean, maxW: number): number {
  if (expanded) {
    return maxW;
  }
  return Math.min(AVATAR_BASE + AVATAR_W_GAIN * pull, maxW);
}

export function avatarHeightOf(pull: number, expanded: boolean): number {
  if (expanded) {
    return AVATAR_EXPANDED_H;
  }
  return Math.min(AVATAR_BASE + AVATAR_H_GAIN * pull, AVATAR_EXPANDED_H);
}

// 形变中从半圆收到卡片圆角；展开态**不再收成 0**：分栏右栏里展开后要跟本页卡片一样带圆角
// （用户 2026-11-25：铺满整栏像一条横幅，看着和左栏不搭）。
export function avatarRadiusOf(pull: number, expanded: boolean, cardRadius: number = AVATAR_CARD_RADIUS): number {
  const ratio: number = avatarRatioOf(pull, expanded);
  return (AVATAR_BASE / 2) * (1 - ratio) + cardRadius * ratio;
}

export function avatarRingOf(pull: number, expanded: boolean): number {
  if (expanded) {
    return 0;
  }
  return AVATAR_RING * (1 - avatarRatioOf(pull, expanded));
}

// 形变中的上移量：ratio 走完之前按比例抬，之后靠 -pull 抵消越界平移，照片钉在屏幕顶。
export function avatarOffsetYOf(pull: number, expanded: boolean, topInset: number): number {
  return -(topInset * avatarRatioOf(pull, expanded) + pull);
}
