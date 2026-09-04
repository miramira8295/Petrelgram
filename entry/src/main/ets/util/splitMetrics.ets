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

// 底部页签**挪去侧边**的断点，vp。**这是官方给的数，不是我们挑的**：
// 《大屏应用UX体验标准》——「当应用窗口宽度达到或超过 840vp，横向断点为 lg 时，
// 建议采用挪移布局，将底部导航栏变更为侧边导航栏。实现原理：导航页签使用 Tabs
// 组件实现，窗口为 lg 断点时，页签位于页面左侧，此时 vertical=true，
// barPosition=Start」。
//
// **和 SPLIT_BREAKPOINT_VP（600）是两条不同的线**，别合并：600 是
// HdsNavigation 进双栏的断点，840 是底栏形态切换的断点。600–840 之间是
// 「已经双栏、但底栏仍在底部」的区间。
//
// 为什么必须切而不是把悬浮胶囊挪到左栏：官方对悬浮样式写死了三个同时成立的
// 条件——barOverlap=true、**vertical=false**、barPosition=End；而
// barSideMargin 只有一个值、两侧同宽，胶囊必然按容器（整窗）居中。
// 也就是说"固定在左栏"这个能力根本不存在，大屏下本来就不该有那颗胶囊。
export const SIDE_TABS_BREAKPOINT_VP: number = 840;

// 底栏该不该变成侧边竖排页签。
export function useSideTabs(windowWidthVp: number): boolean {
  return Number.isFinite(windowWidthVp) && windowWidthVp >= SIDE_TABS_BREAKPOINT_VP;
}

// 底栏该不该挪去侧边——**本应用真正该用的判据**。
//
// 官方那条 840vp 是给"单栏应用变宽了"写的：在它之下仍是一栏，底部横条没问题。
// 但**本应用在 600vp 就分栏了**（isSplitLayout），于是 600–840 这一段是
// "两栏 + 底部悬浮胶囊"，胶囊按整窗居中，正好落在两栏的分割线上——用户实测
// 「dock 跑中间了」，把断点提到 840 之后这一段依旧原样。
//
// 而 HdsTabs 的悬浮样式给不了非对称边距（barSideMargin 是对称的，胶囊永远
// 居中于容器），所以"把胶囊挪到左栏"这条路本身不存在。
//
// 判据因此不是宽度，是**布局形态**：只要分了栏，底部横条就跨着两栏，必须挪
// 到侧边。840 那条仍然保留在 useSideTabs 里，给不分栏但很宽的场景用。
export function sideTabsForLayout(windowWidthVp: number, windowHeightVp: number): boolean {
  return isSplitLayout(windowWidthVp, windowHeightVp) || useSideTabs(windowWidthVp);
}

// 「dock 此刻是否还在底部」的单一真相，写进 AppStorage 由各列表读。
//
// 为什么不逐层传参：给列表留底部避让的地方分散在 ChatListView.endInset()、
// MainTabBody 的 contentEndOffset、ChatPage 的 bottomChromeH 等处，中间隔着
// 好几层组件。侧边模式下 dock 不在底部了，这些避让不撤就是一条空白
// （用户问的正是这个）。用一个键比把 boolean 串下去可靠得多。
export const KEY_DOCK_AT_BOTTOM: string = 'dockAtBottom';

export function dockAtBottom(): boolean {
  return AppStorage.get<boolean>(KEY_DOCK_AT_BOTTOM) ?? true;
}

// 当前窗口下 HdsNavigation 会不会分栏。喂的必须是**窗口尺寸**而不是屏幕尺寸
// （AppStorage 的 'screenWidthVp' / 'screenHeightVp' 存的正是窗口宽高，分屏/
// 悬浮窗/折叠屏改变窗口时由 EntryAbility 的 windowSizeChange 刷新），否则平板
// 分屏到一半时判断会与组件实际的单栏状态相反。
//
// **两条边都要过线，不是只看宽。** 只看宽的版本把「手机横过来」判成了平板：
// 手机竖屏 376×809vp，转到横屏就是 809×376——宽度一下越过 600，整个应用进
// 分栏，而屏幕其实只有一巴掌高。用户报的现象是「点视频全屏被强制分栏，但我
// 没动过 dpi」（issue #125）：全屏播放会把窗口转成横屏，转的一瞬间就撞上了。
//
// 取两边的较小值，等价于 Android 的 smallestScreenWidthDp——它描述的是设备
// 类别而不是当前姿势，横竖屏切换不会改变结论。折叠屏也因此天然正确：展开后
// 短边约 720vp 进分栏，合上约 380vp 回单栏，不需要额外判断机型。
export function isSplitLayout(windowWidthVp: number, windowHeightVp: number): boolean {
  if (!(windowWidthVp >= SPLIT_BREAKPOINT_VP)) {
    return false;
  }
  // 高度读不到时退回只看宽度的老行为。喂进 NaN/0 的场景只有"AppStorage 还没
  // 被 windowSizeChange 填过"，那一瞬间按宽度判断至少不会比拒绝分栏更差。
  if (!Number.isFinite(windowHeightVp) || windowHeightVp <= 0) {
    return true;
  }
  return windowHeightVp >= SPLIT_BREAKPOINT_VP;
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

// ── 侧边竖排页签的纵向尺寸 ──────────────────────────────────────────────
//
// 侧边模式下三个页签是 layoutWeight(1) 均分**整条页签栏的高**，而栏高原本是
// '100%'：于是图标相隔一屏的三分之一（真机 2026-09-04：约 154vp 一格，用户：
// 「左边 dock 的上下图标能紧凑一点吗」）。
//
// 紧凑度因此**只由栏高决定**：栏收多高，一格就是它的三分之一。均分那条路
// 反倒要留着——它是这个组件里唯一被实测证明"三格永远等距"的机制。
//
// 【两条实测记录，别再走回头路】
//   · ExtendBarMode.HALF_SCREEN_FIXED：生效，但只把"均分整屏"压成"均分半屏"，
//     一格仍有 154vp；键盘弹起时窗口变矮，它跟着缩成一格 35vp 并整个顶到状态栏
//     底下（用户截图：「聊天」压在时钟上）。官方给它的第二条依赖「页签使用
//     BottomTabBarStyle 样式」我们也不满足（自绘 builder）。
//   · 给每格定高 + layoutWeight(0)：三格变成"前两格挨着、第三格掉在下面"的
//     不等距（真机量出的间距 87px / 175px）。内部仍按 barHeight ÷ 页签数 分槽，
//     定高的盒子落进槽里怎么对齐没有文档。**别再动 layoutWeight**。
//
// 栏高设定值之后组件把整条栏在竖直方向**居中**（真机验算：栏高 236vp、屏高
// 2000px 时栏顶落在 742px，正是 (2000−515)/2）——所以不需要为状态栏留位。
export const SIDE_DOCK_ITEM_H: number = 64;

// 侧边页签栏的总高 = 页签数 × 一格。
//
// 64 的来历：图标 24 + 间距 2 + 文字行高约 14 = 40 的内容，上下各留 12 的呼吸。
// 低于 48 就碰官方最小点击区域了。
export function sideDockBarHeight(tabCount: number): number {
  const n: number = Math.max(1, Math.round(Number.isFinite(tabCount) ? tabCount : 1));
  return n * SIDE_DOCK_ITEM_H;
}
