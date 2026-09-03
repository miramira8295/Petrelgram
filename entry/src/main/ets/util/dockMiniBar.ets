// 底栏迷你播放条的形态判据（issue：自适应悬浮导航 / 官方 MiniBar 的等价物）。
//
// **为什么是自绘而不是 HdsTabs.barFloatingStyle({ miniBar })。** 官方那套 MiniBar
// 是 HdsTabs 的能力，而本应用的底栏是 MainScreen.dock() 自绘的（宽度判据见
// mainTabsWidth）。为一个 MiniBar 把 Tabs 换成 HdsTabs 要动 ChatListPage 一千多行、
// dock 显隐的 AppStorage 闸、navBarReset、分栏宽度——和顶栏那次是同一个结论：
// 自绘的那套里做两态，别为了一个部件迁整个容器。
//
// 三态，判据只有两个输入：
//   FULL       没有正在播放         四个页签，和以前完全一样
//   COLLAPSED  在播放、播放条未展开  四个页签 + 右侧一颗专辑球
//   EXPANDED   在播放、播放条已展开  只留个人资料头像 + 播放条
//
// **EXPANDED 不是持久状态**：播放一停就必须掉回 FULL，否则底栏会永远停在
// 「只有一个头像」的样子，用户再也点不到会话页签。这条判据是纯的，钉在单测里。

export const DOCK_FULL: string = 'full';
export const DOCK_COLLAPSED: string = 'collapsed';
export const DOCK_EXPANDED: string = 'expanded';

export function dockMiniBarState(hasNowPlaying: boolean, expanded: boolean): string {
  if (!hasNowPlaying) {
    return DOCK_FULL;
  }
  return expanded ? DOCK_EXPANDED : DOCK_COLLAPSED;
}

// 页签格子还画不画。EXPANDED 下只留个人资料那一格——用户定的：点它只是收起
// 播放条，**不跳转**，所以留哪一格都不会把人挪走，留头像最不像"功能键"。
export function dockShowsTabs(state: string): boolean {
  return state !== DOCK_EXPANDED;
}

// 专辑球画不画（只有折叠态画；展开态那颗球变成播放条里的封面）。
export function dockShowsAlbumBall(state: string): boolean {
  return state === DOCK_COLLAPSED;
}

export function dockShowsPlayer(state: string): boolean {
  return state === DOCK_EXPANDED;
}

// 曲名兜底：没有元数据时退回文件名，再没有就交给调用方给占位文案。
export function nowPlayingTitle(title: string, fileName: string): string {
  const t: string = title.trim();
  if (t !== '') {
    return t;
  }
  return fileName.trim();
}
