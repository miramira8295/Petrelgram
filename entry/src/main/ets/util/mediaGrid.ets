// 共享媒体网格的格子尺寸——群资料页（ChatProfilePage）和个人资料页
// （ProfilePage）两处共用，原来是两份逐字复制的算式。
//
// **为什么不能按窗口宽 screenW 算。**
//
// 网格装在一张玻璃卡里：卡片是 `width('calc(100% - 24vp)')` + `glassCard()`，
// 而 glassCard 带一条 0.7vp 的描边。ArkUI 的描边算在组件宽度**之内**、不算在
// "父组件内容区"里——matchParent 的文档原文是「其大小与父组件内容区相等，
// 不包括 padding，border 和 safeAreaPadding」。所以子组件真正能用的宽是
//
//     screenW - 24（左右外边距） - 0.7 * 2（描边）
//
// 老写法是 `(screenW - 30) / 3`，每格再挂一条 2vp 右外边距，于是三格合计
//
//     (screenW - 30) + 3 * 2 = screenW - 24
//
// ——正好等于卡片的**外**宽，比内容区宽 1.4vp。差这一丁点，第三格就永远被挤
// 到下一行：每行只剩两格，右边空掉整整三分之一（用户截图）。这种"分毫不差"
// 的排版只要父链上多出任何内边距就会塌，所以修法不是把 30 改成 31.4，而是
// 不再猜宽度。
//
// **改成按实测宽算。** 调用方用 onAreaChange 量 Flex 的实际宽度传进来。首帧
// 还没量到时用 mediaFallbackContentWidth 兜一下（它把外边距和描边都减掉）。
// 实测宽顺带兜住分栏、折叠屏、多窗口这些 screenW ≠ 容器宽的情形。
//
// 另外格宽向下取整、再留 1vp 余量：格宽是浮点数，逐格换算成物理像素时的舍入
// 会累加，正好卡在边界上又会把第三格顶下去。余量摊在最右边，肉眼看不出来。

// 一行几格。
export const MEDIA_GRID_COLS: number = 3;
// 每格的右/下外边距，占位时要算进去。
export const MEDIA_GRID_GAP: number = 2;
// 窗口太窄时的保底格宽：宁可横向放不下三格，也不要把格子压成一条线。
export const MEDIA_GRID_MIN_CELL: number = 92;
// 卡片左右各留的外边距，和 `calc(100% - 24vp)` 是同一个 12。
export const MEDIA_CARD_MARGIN: number = 12;
// glassCard 的描边宽。改这里要连 @Styles 里的 `.border({ width: 0.7 })` 一起改。
export const GLASS_BORDER_W: number = 0.7;
// 亚像素舍入的余量，见顶部注释。
const MEDIA_GRID_SLACK: number = 1;

// 按容器内容宽算每格边长（正方形）。contentWidth 取自 onAreaChange。
export function mediaCellSize(contentWidth: number): number {
  // 还没量到（0）、拿到脏值（负数 / NaN）时不要算出 0 或负数把格子塌掉。
  if (!(contentWidth > 0)) {
    return MEDIA_GRID_MIN_CELL;
  }
  const usable: number = contentWidth - MEDIA_GRID_COLS * MEDIA_GRID_GAP - MEDIA_GRID_SLACK;
  return Math.max(MEDIA_GRID_MIN_CELL, Math.floor(usable / MEDIA_GRID_COLS));
}

// 首帧还没量到时的兜底内容宽：窗口宽减掉卡片外边距，再减掉描边。
export function mediaFallbackContentWidth(screenW: number): number {
  return screenW - MEDIA_CARD_MARGIN * 2 - GLASS_BORDER_W * 2;
}
