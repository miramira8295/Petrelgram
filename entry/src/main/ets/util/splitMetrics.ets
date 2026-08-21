// 分栏（HdsNavigation / Navigation 双栏）的宽度取值。
//
// 抽成纯函数是为了能单测：这几个数字唯一的验证方式本来是「找一台那个尺寸的
// 设备打开看」，而真正会出事的区间（600–800vp：折叠屏内屏、平板分屏、悬浮窗）
// 恰恰是手上没有设备的那些。规则写成函数之后，四个断点直接在宿主用例里验算。
//
// 三条硬约束，任何取值都必须同时满足：
//   1. navBar ≤ 窗口宽的 40%（官方大屏 UX 标准 3.2.2.4，内容区至少 60%）
//   2. maxWidth + minContentWidth ≤ 窗口宽 —— 否则两个约束互相打架，
//      HdsNavigation 内部怎么裁决没有文档，属于未定义行为
//   3. maxWidth − minWidth ≥ 一段真实行程 —— 否则 enableDragBar(true) 画得出
//      把手却拖不动（官方文档：同时设置 navBarWidthRange 与 minContentWidth 时，
//      「满足 minContentWidth 后在 navBarWidthRange 范围内拖拽」）
//
// 【输入前提】三个函数都**假定 windowWidthVp ≥ 600**（NavigationMode.Auto 的分栏
// 断点），由调用方保证——这三个值只在分栏成立时才被 HdsNavigation 读取。
// 没有在函数里加下限保护，是因为 600 以下没有任何一组取值是「对」的：约束 1 和
// 约束 3 在那里必然互斥（0.4 × 500 = 200，再留 40 行程就只剩 160），随便挑一个
// 数只会让一段死代码看起来像是有意义的。
// **但区间合法性（minWidth ≤ maxWidth）是无条件保证的**——见 splitNavMinWidth
// 末尾那次收敛，用例里对 240–2560 逐 vp 断言过。也就是说即便哪天真被喂进一个
// 小于 600 的宽度，结果也只是「行程为 0、拖不动」，不会退化成 HdsNavigation
// 文档里那句「设置异常值时按默认值处理」把整组取值作废。

// 分栏断点，vp。**这是 NavigationMode.Auto 内部那条线**，不是我们挑的：
// HdsNavigation / Navigation 在窗口宽 ≥ 这个值时自动进双栏，小于它走单栏。
// 官方《一次开发多端部署》把它记作 sm/md 的分界。
//
// 导出它是因为断点判断已经不只发生在 HdsNavigation 内部：联系人页签要按
// 同一条线决定「点一个联系人是开会话（手机单栏）还是在右栏开资料页（平板
// 分栏）」——两处若各写一个字面量 600，哪天官方挪了断点就会错开一档，出现
// 「组件已经分栏了但代码还以为是手机」的半拉状态。
export const SPLIT_BREAKPOINT_VP: number = 600;

// 当前窗口宽下 HdsNavigation 会不会分栏。喂的必须是**窗口宽**而不是屏幕宽
// （AppStorage 的 'screenWidthVp' 存的正是窗口宽，分屏/悬浮窗/折叠屏改变窗口
// 时由 EntryAbility 的 windowSizeChange 刷新），否则平板分屏到一半时判断会
// 与组件实际的单栏状态相反。
export function isSplitLayout(windowWidthVp: number): boolean {
  return windowWidthVp >= SPLIT_BREAKPOINT_VP;
}

// 左栏想要的比例。窗口越宽，左栏越宽——但只按比例走，不按定值。
const SPLIT_NAV_RATIO: number = 1 / 3;
// 官方 40% 上限。maxWidth 永远不越它，minWidth 因此也不会。
const SPLIT_NAV_CAP_RATIO: number = 0.4;
// 比例式的两端兜底：下限取一个手机宽度（再窄会话行就没法看了），上限拦住超宽屏
// ——比例再乘下去左栏只是在拉白边，会话行本身早就够宽了。
// 注意这两个数只约束「想要的值」，最终仍要过 40% 上限和拖拽行程两道夹。
const SPLIT_NAV_MIN_VP: number = 320;
const SPLIT_NAV_MAX_VP: number = 480;
// 拖分割线能把左栏拉到的最宽处。
const SPLIT_NAV_DRAG_MAX_VP: number = 560;
// 右栏想要的最小宽度。窄窗口下让位（见 splitContentMinWidth）。
const SPLIT_CONTENT_MIN_VP: number = 400;
// 窄窗口下右栏最小宽度退成窗口的这个比例。取 0.6 不是随手定的：它正好是
// 左栏 40% 上限的补数，两者相加恰好铺满窗口，约束 2 自动成立。
const SPLIT_CONTENT_RATIO: number = 0.6;
// 保证「拖得动」的最小行程，vp。低于这个数拖拽手感等同于没有。
const SPLIT_DRAG_SPAN_VP: number = 40;
// minWidth 的绝对地板。600vp 窗口下 40% 上限就是 240，再减去行程只剩 200——
// 这是分栏临界点上的物理极限，不是我们想要的观感，但比「拖不动」或者
// 「minContentWidth 打架」都好。
const SPLIT_NAV_HARD_MIN_VP: number = 200;

// 右栏（内容区）最小宽度。
//
// 老版本这里是写死的 400：在 600–667vp 区间它和左栏的 40% 上限加起来超过窗口
// 宽（W=600 时 240 + 400 = 640 > 600），HdsNavigation 实际如何裁决无文档可依。
// 改成窗口宽的 60% 兜底之后，maxWidth + minContentWidth ≤ W 恒成立。
export function splitContentMinWidth(windowWidthVp: number): number {
  return Math.floor(Math.min(SPLIT_CONTENT_MIN_VP, windowWidthVp * SPLIT_CONTENT_RATIO));
}

// 左栏拖拽上限。floor 而不是 round：与 splitContentMinWidth 一样向下取整，
// 两者相加才能保证不超过窗口宽（各自 round 时最多能溢出 1vp）。
export function splitNavMaxWidth(windowWidthVp: number): number {
  return Math.floor(Math.min(SPLIT_NAV_DRAG_MAX_VP, windowWidthVp * SPLIT_NAV_CAP_RATIO));
}

// 左栏下限——**这才是真正决定观感的那个数**：HdsNavigation 没有开放 navBarWidth
// 设置项，内部默认 240vp，被 range 一夹就落在离 240 最近的那一端。宽屏上
// minWidth 远大于 240，静息宽度就等于 minWidth；窄窗口上 240 落在区间内部，
// 静息宽度就是 240（正好是 600vp 下的 40%）。
export function splitNavMinWidth(windowWidthVp: number): number {
  const byRatio: number = Math.round(Math.min(
    SPLIT_NAV_MAX_VP,
    Math.max(SPLIT_NAV_MIN_VP, windowWidthVp * SPLIT_NAV_RATIO)
  ));
  const max: number = splitNavMaxWidth(windowWidthVp);
  // 窄窗口下 40% 上限会把 byRatio 整个顶掉（W=800 时想要 320、上限也是 320），
  // 此时行程只能向下让：区间变成 [40% − 行程, 40%]。这仍然合标准——标准管的是
  // 上限，没有下限。
  const withSpan: number = Math.min(byRatio, max - SPLIT_DRAG_SPAN_VP);
  const floored: number = Math.max(SPLIT_NAV_HARD_MIN_VP, withSpan);
  // minWidth > maxWidth 是非法区间（文档：设置异常值时按默认值处理，等于本函数
  // 白算）。窗口 < 600vp 时压根不分栏，取不到这里，但兜住总比赌一把强。
  return Math.min(floored, max);
}
