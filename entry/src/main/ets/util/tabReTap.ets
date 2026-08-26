// 点已经选中的页签：先回顶，已经在顶就跳到下一个未读会话（issue #35，官方也是
// 这个手感）。MainScreen 只负责发信号，各页签自己决定怎么响应。
export const TAB_RETAP_EPOCH: string = 'tabReTapEpoch';
export const TAB_RETAP_INDEX: string = 'tabReTapIndex';

export function publishTabReTap(index: number): void {
  AppStorage.setOrCreate(TAB_RETAP_INDEX, index);
  AppStorage.setOrCreate(TAB_RETAP_EPOCH, (AppStorage.get<number>(TAB_RETAP_EPOCH) ?? 0) + 1);
}

// 从 fromIndex 之后找第一个未读，找不到就从头绕一圈；一个未读都没有返回 -1。
// 「在顶部」按第一行是不是可见判断，由调用方传 atTop。
export function nextUnreadIndex(unread: boolean[], fromIndex: number): number {
  const n = unread.length;
  if (n === 0) {
    return -1;
  }
  const start = Math.max(-1, Math.min(n - 1, Math.floor(fromIndex)));
  for (let step = 1; step <= n; step++) {
    const i = (start + step + n) % n;
    if (unread[i]) {
      return i;
    }
  }
  return -1;
}

// 这一次点击该干什么：'top' 回顶 / 'unread' 跳下一个未读 / 'none' 什么都不做。
export function reTapAction(atTop: boolean, hasUnread: boolean): string {
  if (!atTop) {
    return 'top';
  }
  return hasUnread ? 'unread' : 'none';
}
