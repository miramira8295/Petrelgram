// 点已经选中的页签：按顺序跳到下一个未读，走完后回顶（issue #35）。
// MainScreen 只负责发信号，各页签自己决定怎么响应。
export const TAB_RETAP_EPOCH: string = 'tabReTapEpoch';
export const TAB_RETAP_INDEX: string = 'tabReTapIndex';

export function publishTabReTap(index: number): void {
  AppStorage.setOrCreate(TAB_RETAP_INDEX, index);
  AppStorage.setOrCreate(TAB_RETAP_EPOCH, (AppStorage.get<number>(TAB_RETAP_EPOCH) ?? 0) + 1);
}

// 从 fromIndex 之后找第一个未读，不回绕；走完全部未读后由调用方回到顶部。
// 「在顶部」按第一行是不是可见判断，由调用方传 atTop。
export function nextUnreadIndex(unread: boolean[], fromIndex: number): number {
  const n = unread.length;
  if (n === 0) {
    return -1;
  }
  const start = Math.max(-1, Math.min(n - 1, Math.floor(fromIndex)));
  for (let i = start + 1; i < n; i++) {
    if (unread[i]) {
      return i;
    }
  }
  return -1;
}

// 只把未静音未读当成定位目标。静音会话的未读通常很多，若也参与，重复点击
// 会在用户并不关心的频道之间轮转，反而够不着真正需要处理的消息。
export function isPriorityUnread(unreadCount: number, isMarkedUnread: boolean, muted: boolean): boolean {
  return !muted && (unreadCount > 0 || isMarkedUnread);
}

// 优先跳未静音未读；没有时才回顶。旧实现先看 atTop，人在列表中部时第一次
// 点击必定只回顶，必须再点一次才可能定位，正是 issue #35 实测“不生效”的原因。
export function reTapAction(atTop: boolean, hasPriorityUnread: boolean): string {
  if (hasPriorityUnread) {
    return 'unread';
  }
  return atTop ? 'none' : 'top';
}
