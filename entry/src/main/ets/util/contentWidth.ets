// 不分栏页面的内容限宽。
//
// 平板上把一列内容拉满 2880px 的后果，设备截图上很清楚：账号资料行的图标贴最
// 左、复制按钮贴最右，中间一大片空白，眼睛要横扫整个屏幕才能把一行读完。
// 官方《大屏应用 UX 体验标准》对此有三条硬指标：
//   3.2.1.7 平板横屏一行不超过 52 字
//   3.2.1.8 左边距不大于屏幕宽度的 20%
//   3.2.1.9 留白比例不超过 70%
//
// 分栏页面不需要这个——右栏本身就已经把宽度约束住了。只有那些"整屏一列"的
// 页面（联系人 / 设置 / 个人资料）要用。
//
// 【三条指标彼此打架，取舍写在这里】
// 3.2.1.7 要求内容窄（52 全角字 @16vp ≈ 832vp 正文，加两侧 16vp 内边距 ≈ 864vp），
// 3.2.1.8 要求内容宽（边距 ≤20% ⇒ 内容 ≥60% 窗口宽）。窗口越宽两者越对立：
// 2560vp 下 3.2.1.8 要内容 ≥1536vp，那等于放弃 3.2.1.7、回到"横扫整屏"。
// 取舍是**定值上限优先**——上限一旦被 3.2.1.8 拖着按比例长，就没有上限了。
// 因此本模块保证的是：
//   · 3.2.1.9（留白 ≤70%）在 2560vp 以内**无条件成立**（最坏 65.6%）；
//   · 3.2.1.8（边距 ≤20%）在 1440vp 及以下成立（1440 下正好 19.4%）；
//     1440 以上按定值上限走，边距会超过 20%——这是上面那个取舍的已知代价。
//   · 3.2.1.7 逼近但略超（880 − 32 = 848vp 正文 ≈ 53 字）。

// 低于这个宽度不限宽：手机上本来就没有多余的宽度可让。与 splitMetrics 的分栏
// 阈值同值不是巧合——分栏和限宽解决的是同一件事的两面。
const NARROW_MAX_VP: number = 600;
// 内容宽度上限。再宽就不是"更好读"而是"又开始横扫"了。
// 取 880 而不是 840：840 在 1440vp 下留白 (1440−840)/2 = 300 = 20.8%，越了
// 3.2.1.8 的 20%。880 是既压着 52 字线又能在 1440vp 下守住 20% 的取值。
const CONTENT_CAP_VP: number = 880;
// 上限被吃满的窗口宽。600 到这里之间线性收窄，不是一过阈值就"啪"地缩掉一大截
// ——那种跳变在折叠屏展开、平板分屏拖拽这类**连续**改变窗口宽的场景里会看成
// 布局抖动。
const TAPER_FULL_VP: number = 1200;

// 限宽刚开始生效那一刻的内容宽度。
//
// 为什么是"窗口宽 − 1"而不是某个更小的值：限宽必须**单调不减**（窗口变宽内容
// 不能变窄，否则拖窗口时内容会反向抽搐），而 599vp 时内容就是 599vp。600vp 的
// 内容宽度因此只能落在 [599, 600) 里——除了 599 没有别的选择。也就是说 600vp
// 那一点上"限宽"只是名义上开始，真正让出边距要到 700vp 往上。
const TAPER_START_CONTENT_VP: number = NARROW_MAX_VP - 1;

export function readableContentWidth(windowWidthVp: number): number {
  // 手机：原样返回窗口宽 = 不限宽。手机上的观感必须一点都不变。
  if (windowWidthVp < NARROW_MAX_VP) {
    return windowWidthVp;
  }
  if (windowWidthVp >= TAPER_FULL_VP) {
    return CONTENT_CAP_VP;
  }
  const t: number = (windowWidthVp - NARROW_MAX_VP) / (TAPER_FULL_VP - NARROW_MAX_VP);
  const tapered: number = TAPER_START_CONTENT_VP + t * (CONTENT_CAP_VP - TAPER_START_CONTENT_VP);
  // floor 而不是 round：向下取整这一侧永远是"内容更窄"，不会因为进位反而超出
  // 窗口宽。下面那个 min 是防御——taper 段的斜率 (880−599)/600 < 1，几何上已经
  // 保证 tapered < windowWidthVp，但不想把这条正确性押在常量以后不会被人调上。
  return Math.min(Math.floor(tapered), windowWidthVp);
}

// 内容列单侧的留白宽度。
//
// 悬浮元素（联系人页右下角的 FAB）拿它把自己从**屏幕**边缘拉回**内容列**边缘：
// 2880px 平板上不加这个偏移，FAB 落在 x≈2790px，而内容列右边缘在 x≈2290px，
// 中间隔着约 500px 的空白——视线在居中的内容列上，手却要伸到屏幕最右边（设备
// 实测确认）。
//
// 手机上恒为 0（readableContentWidth 原样返回窗口宽），所以调用方直接把它加进
// 既有的 margin 里就行，手机上逐像素不变。
export function contentSideGutter(windowWidthVp: number): number {
  return (windowWidthVp - readableContentWidth(windowWidthVp)) / 2;
}
