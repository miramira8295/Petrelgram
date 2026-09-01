// 文件夹页签角标的旁路通道。
//
// unreadMap 曾是 ChatListPage 的一整个 @State Map：任何一个计数变化都让全部
// chips 重渲染 + 标题栏重测（长竖滑结束后实测 26.5ms 单帧）。改成每个页签一个
// @Observed 模型，chip 里的角标子组件用 @ObjectLink 各自订阅，refreshUnread
// 只写有变化的 key——脏区从整页缩到单个角标。

@Observed
export class FolderBadge {
  count: number = 0;
}

const badges: Map<string, FolderBadge> = new Map<string, FolderBadge>();

// 同一 key 永远拿到同一实例：@ObjectLink 的绑定靠对象身份存活；换新对象
// 等于把订阅整个换掉，又回到父层重渲染那条路。
export function folderBadge(key: string): FolderBadge {
  let badge = badges.get(key);
  if (badge === undefined) {
    badge = new FolderBadge();
    badges.set(key, badge);
  }
  return badge;
}

// 值没变不写：对 @Observed 字段的每次赋值都是一次该角标的重渲染。
export function setFolderBadge(key: string, count: number): void {
  const badge = folderBadge(key);
  if (badge.count !== count) {
    badge.count = count;
  }
}

// 99+ 截断，原 ChatListPage.tabBadgeText 的逻辑原样搬出来好测。
export function badgeLabel(count: number, max: number): string {
  return count > max ? `${max}+` : `${count}`;
}
