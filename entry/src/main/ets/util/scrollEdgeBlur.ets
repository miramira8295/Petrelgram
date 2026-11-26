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
 *
 * 【统一开关】全部页面共用 util/edgeBlurSetting.ets 里的 KEY_EDGE_BLUR_ON：
 * V1 组件把半径写成 `this.edgeBlurOn ? BLUR_MAX_VP : 0`（@StorageProp 绑定），
 * V2 组件写 `edgeBlurRadiusOf(edgeBlurSwitch.on)`。传 0 等价于不画，绝不要为了
 * 关掉它去条件渲染整棵滚动树。
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

/**
 * 只有顶部带、没有底部带的版本。
 *
 * 设置类二级页面的内容通常不长、底部紧跟着导航/按钮区，底部再糊一条会显得
 * 页面"往下陷"（用户 2026-11-05）。顶部那条保留：内容仍然穿到标题栏底下。
 */
export function edgeBlurRadiusOf(on: boolean, maxVp: number = BLUR_MAX_VP): number {
  return on ? maxVp : 0;
}

/**
 * 头像下拉放大（形变）期间专用的半径。
 *
 * 两处资料页下拉放大头像时暂停整屏模糊，结束后恢复顶、底边缘设置。
 */
export function edgeBlurRadiusWhileMorphing(morphing: boolean, topOn: boolean, bottomOn: boolean): number {
  return morphing ? 0 : edgeBlurRadiusOf(topOn || bottomOn);
}

/**
 * 顶部带的上边界分数（与 edgeBlurStops 内部同一公式，Ex 版本要用它判断哪一段属顶部）。
 */
function topCutFrac(vh: number, topOffsetVp: number): number {
  const startFrac: number = Math.max(0, Math.min(topOffsetVp / vh, 0.4));
  return Math.min(startFrac + TOP_BAND_VP / vh, 0.45);
}

/** 底部带的下边界分数。 */
function botStartFrac(vh: number): number {
  return Math.max(1 - BOTTOM_BAND_VP / vh, 0.55);
}

/**
 * 带顶部/底部独立开关的版本。
 *
 * 为什么不是"关掉就换个函数"：linearGradientBlur 只有一个半径参数，要分别关顶、
 * 关底只能落到 fractionStops 上——把不启用那一侧的停靠点半径全部置 0。这样：
 *   · 只关顶部 → 底部照旧糊，顶部那条带子读到的半径恒 0，等于不画；
 *   · 只关底部 → 对称；
 *   · 两侧都关 → 整组 stops 半径全 0，配合半径传 0，渲染侧是恒等变换。
 * 全程不摘除属性、不重建滚动树，滚动位置和缓存都不受影响。
 */
export function edgeBlurStopsEx(viewH: number, fallbackH: number = 780, topOffsetVp: number = 0,
  topOn: boolean = true, bottomOn: boolean = true): FractionStop[] {
  const vh: number = viewH > 0 ? viewH : (fallbackH > 0 ? fallbackH : 780);
  const all: FractionStop[] = edgeBlurStops(vh, fallbackH, topOffsetVp);
  if (topOn && bottomOn) {
    return all;
  }
  const topCut: number = topCutFrac(vh, topOffsetVp);
  const botStart: number = botStartFrac(vh);
  const out: FractionStop[] = [];
  for (const stop of all) {
    const radius: number = stop[0];
    const position: number = stop[1];
    const inTop: boolean = position <= topCut + 0.0001;
    const inBottom: boolean = position >= botStart - 0.0001;
    const mute: boolean = (inTop && !topOn) || (inBottom && !bottomOn);
    out.push([mute ? 0 : radius, position]);
  }
  return out;
}

export function topEdgeBlurStops(viewH: number, fallbackH: number = 780): FractionStop[] {
  const vh: number = viewH > 0 ? viewH : (fallbackH > 0 ? fallbackH : 780);
  const topCut: number = Math.min(TOP_BAND_VP / vh, 0.45);
  const out: FractionStop[] = [];
  out.push([1, 0]);
  out.push([0.86, topCut * 0.18]);
  out.push([0.66, topCut * 0.38]);
  out.push([0.44, topCut * 0.58]);
  out.push([0.22, topCut * 0.78]);
  out.push([0.08, topCut * 0.92]);
  out.push([0, topCut]);
  out.push([0, 1]);
  return out;
}
