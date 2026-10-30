// 首页会话列表里的论坛超级群双栏抽屉状态（图 1 形态：左侧会话头像窄栏 + 右侧话题列表）。
//
// 抽屉面板常驻于渲染树（关闭时平移至屏幕右侧外并置于 enabled(false) + HitTestMode.None），
// 进出全程仅翻转 activeForumDrawerOpen 触发同步位移动画，结束后不做任何延迟卸载或显隐切换，
// 从而彻底杜绝动画结束后的闪动与布局抖动。

export const KEY_ACTIVE_FORUM_CHAT_ID: string = 'activeForumChatId';
export const KEY_ACTIVE_FORUM_OPEN: string = 'activeForumDrawerOpen';
export const KEY_ACTIVE_FORUM_LIST_KEY: string = 'activeForumListKey';
export const KEY_ACTIVE_FORUM_SEARCH_QUERY: string = 'activeForumSearchQuery';
export const KEY_ACTIVE_FORUM_NEW_TOPIC_EPOCH: string = 'activeForumNewTopicEpoch';

export const FORUM_DRAWER_OPEN_MS: number = 280;
export const FORUM_DRAWER_CLOSE_MS: number = 260;

export function activeForumChatId(): number {
  return AppStorage.get<number>(KEY_ACTIVE_FORUM_CHAT_ID) ?? 0;
}

export function isForumDrawerOpen(): boolean {
  return AppStorage.get<boolean>(KEY_ACTIVE_FORUM_OPEN) ?? false;
}

export function activeForumListKey(): string {
  return AppStorage.get<string>(KEY_ACTIVE_FORUM_LIST_KEY) ?? 'main';
}

export function openForumDrawer(chatId: number, listKey: string = 'main'): void {
  if (chatId === 0) {
    closeForumDrawer();
    return;
  }
  const normalizedKey: string = listKey !== '' ? listKey : 'main';
  if (activeForumListKey() !== normalizedKey) {
    AppStorage.setOrCreate<string>(KEY_ACTIVE_FORUM_LIST_KEY, normalizedKey);
  }
  if (activeForumChatId() !== chatId) {
    AppStorage.setOrCreate<string>(KEY_ACTIVE_FORUM_SEARCH_QUERY, '');
    AppStorage.setOrCreate<number>(KEY_ACTIVE_FORUM_CHAT_ID, chatId);
  }
  if (!isForumDrawerOpen()) {
    AppStorage.setOrCreate<boolean>(KEY_ACTIVE_FORUM_OPEN, true);
  }
}

export function requestForumNewTopic(): void {
  const prev: number = AppStorage.get<number>(KEY_ACTIVE_FORUM_NEW_TOPIC_EPOCH) ?? 0;
  AppStorage.setOrCreate<number>(KEY_ACTIVE_FORUM_NEW_TOPIC_EPOCH, prev + 1);
}

// 若当前开着论坛话题分栏抽屉则触发滑出收起动画并返回 true；否则返回 false。
export function closeForumDrawer(): boolean {
  if (!isForumDrawerOpen()) {
    return false;
  }
  AppStorage.setOrCreate<string>(KEY_ACTIVE_FORUM_SEARCH_QUERY, '');
  AppStorage.setOrCreate<boolean>(KEY_ACTIVE_FORUM_OPEN, false);
  return true;
}
