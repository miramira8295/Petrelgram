// 打开全局搜索。
//
// 搜索页原来是整页 router 页，盖在页签栈上面：从搜索结果点进会话时必须先把
// 自己弹掉（会话推进的是页签栈、在它下面），于是从会话返回就回不到搜索结果了
// （issue #129）。现在它是**聊天页签栈里的一个 NavDestination**，栈变成
//   聊天列表 → 搜索 → 会话
// 返回天然回到还活着的那一页搜索结果，什么都不用重建。
//
// 形状与 util/chatNav、util/profileNav 一致：拿不到栈就退回整页路由（那种情况
// 只有页签树还没建好，比如从通知冷启动直接进来）。
import { router } from '@kit.ArkUI';
import { NavStackLike, stackOf } from './navStacks';
import { CHAT_TAB_INDEX, KEY_MAIN_TAB } from './chatNav';
import { logE } from './log';

export const SEARCH_DEST_NAME: string = 'GlobalSearchPage';
export const SEARCH_PAGE_URL: string = 'pages/search/GlobalSearchPage';

export function navigateToSearch(params?: Record<string, Object>): void {
  const stack: NavStackLike | undefined = stackOf('chat');
  if (stack === undefined) {
    router.pushUrl({ url: SEARCH_PAGE_URL, params: params }).catch((e: Object): void => {
      logE(`searchNav.pushUrl failed: ${JSON.stringify(e)}`);
    });
    return;
  }
  // 搜索永远开在聊天页签里：从别的页签（设置里的链接、话题标签）点进来也一样。
  AppStorage.setOrCreate<number>(KEY_MAIN_TAB, CHAT_TAB_INDEX);
  stack.pushPath({ name: SEARCH_DEST_NAME, param: params ?? {} as Record<string, Object> });
}
