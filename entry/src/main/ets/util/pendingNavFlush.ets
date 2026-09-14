// 挂起的跳转在这里重放。
//
// 单独一个文件而不是塞进 pendingNav：那一份要保持纯数据（能在宿主上跑单测），
// 而重放必须调用四个 nav 漏斗。放在一起会把 AppStorage/router 拖进单测。
import { navigateToChat, logChatNavFailure } from './chatNav';
import { navigateToSearch, SEARCH_DEST_NAME } from './searchNav';
import { replayProfileNav } from './profileNav';
import { navigateToSetting } from './settingsNav';
import { PendingNav, takePendingNavs } from './pendingNav';
import { PushOrigin } from './splitRouting';
import { TabKind } from './navStacks';
import { logW } from './log';

// 某个页签的栈刚注册好，把等它的那些跳转放出去。
// **取走即移除**：重放失败不再重试——无限重放比丢一次更糟。
export function flushPendingNavs(tab: TabKind): void {
  const items: PendingNav[] = takePendingNavs(tab);
  for (const item of items) {
    logW(`[PendingNav] replay ${item.kind} on ${tab}`);
    const origin: PushOrigin = item.origin === 'content' ? 'content'
      : (item.origin === 'search' ? 'search' : 'navbar');
    if (item.kind === 'chat') {
      navigateToChat(item.params, origin).catch(logChatNavFailure);
    } else if (item.kind === SEARCH_DEST_NAME || item.kind === 'search') {
      navigateToSearch(item.params);
    } else if (item.kind.startsWith('settings:')) {
      navigateToSetting(item.dest, item.params['param'], origin);
    } else {
      replayProfileNav(item.dest, item.params, origin, tab);
    }
  }
}
