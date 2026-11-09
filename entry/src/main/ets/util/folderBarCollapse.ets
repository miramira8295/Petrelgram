// 首页文件夹条的收起 / 展开（2026-10-30 用户提出并定规则）。
//
// 想要的效果：往上滑（往列表尾部走）时整条文件夹条收起来，当前文件夹缩成标题
// 旁边的一小块；往回滑时它从标题旁边落下来、放大成整条。收起态点那块缩略，
// 直接展开；收起态左右滑切换文件夹时，滑的过程中也走一遍完整动画，松手回缩。
//
// 判定规则是用户从三个选项里选的「方向 + 到顶双保险」：
//   · 方向驱动 —— 同方向累计滑过阈值才切换，反向立即开始反向累计；
//   · 到顶强制展开 —— 列表首行一露出来就一定是展开的，不能让用户回到顶部
//     却看见一个收起的标题栏。
//
// 「同方向累计、方向一反就归零」这条形状和 util/immersiveBars 一模一样，是同一
// 个问题的同一个解（惯性末尾和手指微抖会在正负之间来回，按单帧判会让横条一闪
// 一闪）。**没有合并成一个模块**：两者生命周期、阈值、触发集合都不同——横条还
// 有「点缩略」「横拖中」两种强制展开来源，以后调阈值也不会一起动。

// 同方向累计滑过这么多才切换。
export const FOLDER_BAR_COLLAPSE_VP: number = 24;

// 收起态横拖文件夹条时，拖动超过这么多就展开。**必须过阈值，不能按下就展开**：
// 用户只是点了其中一个文件夹、手指轻微一动，整条横条弹出来会显得很吵。
export const FOLDER_BAR_DRAG_REVEAL_VP: number = 10;

export class FolderBarCollapseState {
  collapsed: boolean = false;
  // 当前方向的累计量：正 = 内容往上走（往列表尾部滑），负 = 往回滑。
  accumulated: number = 0;
}

// 已展开的初始状态。单独给一个函数是为了让调用方不必记住 accumulated 要归零。
export function expandedFolderBar(): FolderBarCollapseState {
  return new FolderBarCollapseState();
}

// delta：本帧滚动偏移的变化量（List.onDidScroll 的第一个参数），正数 = 往尾部滑。
// forceExpand：下列任一情况为真时一律展开——
//   · 列表已经回到顶部（首行可见）；
//   · 一个文件夹都没有（那就没有可收的东西）；
//   · 用户正在横拖文件夹条（见 folderDragReveals）。
// 一次性把三种情况合成一个入参，是因为它们对状态机的要求完全相同：**立刻展开
// 并把累计量清零**。清零这一步很关键：回到顶部之后残留的正向累计量会让紧接着
// 一次很小的同向滚动就把它收回去。
// 返回新状态，不改入参。
export function nextFolderBarCollapse(prev: FolderBarCollapseState, delta: number,
  forceExpand: boolean): FolderBarCollapseState {
  const next: FolderBarCollapseState = new FolderBarCollapseState();
  if (forceExpand) {
    next.collapsed = false;
    next.accumulated = 0;
    return next;
  }
  if (!Number.isFinite(delta) || delta === 0) {
    next.collapsed = prev.collapsed;
    next.accumulated = prev.accumulated;
    return next;
  }
  const sameDirection: boolean = (delta > 0) === (prev.accumulated > 0) || prev.accumulated === 0;
  const acc: number = sameDirection ? prev.accumulated + delta : delta;
  next.collapsed = prev.collapsed;
  next.accumulated = acc;
  if (!prev.collapsed && acc >= FOLDER_BAR_COLLAPSE_VP) {
    next.collapsed = true;
    next.accumulated = 0;
  } else if (prev.collapsed && acc <= -FOLDER_BAR_COLLAPSE_VP) {
    next.collapsed = false;
    next.accumulated = 0;
  }
  return next;
}

// 收起态的文件夹条上，横向拖动到没到「展开」的距离。
// currentOffset 是 Tabs.onGestureSwipe 的 event.currentOffset，单位 vp、带正负
// （正负表示往哪个邻居切），所以这里看绝对值——左右都要展开。
export function folderDragReveals(currentOffset: number): boolean {
  return Number.isFinite(currentOffset) && Math.abs(currentOffset) >= FOLDER_BAR_DRAG_REVEAL_VP;
}

// 这一帧要不要一律展开（就是 nextFolderBarCollapse 的 forceExpand 入参）。
//
// scrollHideOn 是设置里的「列表滑动隐藏文件夹」开关（默认开）。关掉时横条常驻，
// 做法就是**每一帧都算强制展开**：状态机照旧推进，只是永远停在展开档。没有另外
// 写一条"开关关了就跳过滚动回调"的分支——两条路会各推一次累计量，反而会在开关
// 翻面的那一帧打架。
export function folderBarForceExpand(atTop: boolean, dragReveal: boolean, hasFolders: boolean,
  scrollHideOn: boolean): boolean {
  return !scrollHideOn || atTop || dragReveal || !hasFolders;
}
