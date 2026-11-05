/**
 * 滚动边缘渐变模糊（linearGradientBlur）参数。
 *
 * 【为什么是这个方案】
 *
 * 顶部/底部的「淡化模糊」如果叠一条固定色带（不管是白条、黑条还是透明度条），
 * 在不同壁纸上都是硬边——壁纸一变颜色，那条带子就露馅。真正自然的效果是让
 * **内容自己在边缘处逐渐变糊**，背景原样透出来，没有第二层东西盖着。
 *
 * ArkUI 的 `linearGradientBlur` 就是干这个的：挂在滚动容器上，按 fractionStops
 * 指定的位置给内容做渐变模糊。CFLark 里验证过的参数直接搬过来——它那边的
 * 顶部带 118vp / 底部带 106.7vp / 峰値 22vp 是照着改造前「条带覆盖到标题区」
 * 的高度量出来的，视觉上刚好罩住状态栏和底部导航条的过渡区。
 *
 * 用法（挂在 List / Scroll 上）：
 *
 *   .linearGradientBlur(BLUR_MAX_VP, {
 *     fractionStops: edgeBlurStops(this.listViewH),
 *     direction: GradientDirection.Bottom
 *   })
 *
 * 其中 listViewH 来自同一容器的 `.onAreaChange` 实测高度——手机/平板/横竖屏
 * 视口高度都不一样，必须运行时取，不能写死。
 */

/** 顶部模糊带高度（vp）。 */
const TOP_BAND_VP: number = 118;

/** 底部模糊带高度（vp）——与顶部同高（用户 2026-11-01 要求两端参数一致）。 */
const BOTTOM_BAND_VP: number = 118;

/** 最大模糊半径（vp / 即 linearGradientBlur 的 px 值）。 */
export const BLUR_MAX_VP: number = 22;

/**
 * 滚动容器要往上顶掉的布局高度 = HDS 标题栏 56vp + 状态栏 39vp = 95vp。
 *
 * 实测口径：手机 5557 上 NavBar 188px / 状态栏 132px（density 3.375），
 * 真机平板 118px / 83px（density 2.125）——两台设备状态栏都是 39vp、标题栏都是 56vp。
 *
 * linearGradientBlur 的渐变原点在**容器自己的上沿**，而容器在 HdsNavigation 里是从
 * 标题栏下沿开始布局的。只有把容器上沿提到屏幕顶，顶部虚化带才会从屏幕最上沿开始
 * 衰减，而不是在状态栏/标题那一段留一截清晰的内容。
 */
export const EDGE_OVERLAY_VP: number = 95;

/**
 * 按视口高度生成 fractionStops。
 *
 * 两端用**同一条曲线**：顶部是「贴近上沿满模糊 → 往下衰减到 0」的 S 曲线
 * （4 个停靠点，避免线性过渡在中段看起来「突然清了」）；底部是它的镜像——
 * 从清晰区往下逐渐变糊、贴到下沿时满模糊。带宽、峰值都与顶部相同。
 *
 * 视口过矮时两带会交叠，clamp 保证 topCut < botStart，否则 stops 非递增会被
 * 框架整段丢弃（表现为完全没模糊）。
 */
export function edgeBlurStops(viewH: number, fallbackH: number = 780, topOffsetVp: number = 0): FractionStop[] {
  const vh: number = viewH > 0 ? viewH : (fallbackH > 0 ? fallbackH : 780);
  // 容器上沿可能被负 margin 顶到屏幕之上（topOffsetVp > 0）。虚化带必须从
  // **屏幕最上沿**开始衰减，而不是从容器自己的上沿——否则屏幕顶部会留一条
  // 清晰带，或者雾带整条往下挪。这里把偏移折进分数：0..offset/vh 保持满模糊，
  // 之后再用 TOP_BAND_VP 走衰减。
  const startFrac: number = Math.max(0, Math.min(topOffsetVp / vh, 0.4));
  const topCut: number = Math.min(startFrac + TOP_BAND_VP / vh, 0.45);
  const botStart: number = Math.max(1 - BOTTOM_BAND_VP / vh, 0.55);
  const botSpan: number = 1 - botStart;
  const out: FractionStop[] = [];
  // 顶部：满模糊 → 0。
  // 原来只有 4 个停靠点（1 / 0.7 / 0.3 / 0），最后一段 0.3→0 只占带子的 39%，
  // 半径在那一小段里从 6.6px 掉到 0，真机上看着就是「雾到一半突然清晰」的硬边。
  // 现在把尾段拆细：越往下掉得越慢，收尾更长，过渡不再有台阶。
  if (startFrac > 0) {
    out.push([1, 0]);
    out.push([1, startFrac]);
  } else {
    out.push([1, 0]);
  }
  const span: number = Math.max(topCut - startFrac, 0.0001);
  out.push([0.86, startFrac + span * 0.18]);
  out.push([0.66, startFrac + span * 0.38]);
  out.push([0.44, startFrac + span * 0.58]);
  out.push([0.22, startFrac + span * 0.78]);
  out.push([0.08, startFrac + span * 0.92]);
  out.push([0, topCut]);
  // 中部：清晰
  out.push([0, botStart]);
  // 底部：顶部的镜像 —— 0 → 满，与顶部同一组衰减点
  out.push([0.08, botStart + botSpan * 0.1]);
  out.push([0.22, botStart + botSpan * 0.26]);
  out.push([0.44, botStart + botSpan * 0.48]);
  out.push([0.66, botStart + botSpan * 0.68]);
  out.push([0.86, botStart + botSpan * 0.86]);
  out.push([1, 1]);
  return out;
}
