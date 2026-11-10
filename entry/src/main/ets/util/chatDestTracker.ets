import { currentUIContext } from './uiContext';
import { router } from '@kit.ArkUI';

// 聊天页签栈（chatStack）当前是否有目的地真正在屏上显示。
//
// 1. 为什么不能只信 HdsNavigation.onNavBarStateChange(isVisible)：
//    在单栏（手机）模式下，当 chatStack 里正压着 ChatPage / ChatProfilePage 等页面时，
//    一旦通过 router.pushUrl 打开整页 @Entry 路由页（如群管理 GroupAdminPage、
//    内嵌浏览器 InAppBrowserPage 等）并按返回键（router.back()）退回，HdsNavigation
//    会误补发一次 onNavBarStateChange(true)，导致底部 Tab 栏在群资料页/聊天页上误弹出。
//
// 2. 为什么不能只看 chatStack.size() > 0：
//    某些整页路由退回列表根页的场景下，chatStack 里可能残留未渲染的幽灵记录
//    （只触发过 onReady，未触发 onWillShow / onShown，或已触发 onHidden / aboutToDisappear）。
//
// 3. 为什么按实例 token 集合维护：
//    从 ChatPage 推入二级页（如点击群头像进入 ChatProfilePage）时，新页先触发
//    onWillShow / onShown，旧页随后触发 onHidden。按活跃目的地 token 集合维护可确保
//    栈内仍有可见页面时标志保持为 true，直到栈内最后一个可见目的地退场才归为 false。
export const KEY_CHAT_DETAIL_SHOWN: string = 'chatDetailShown';

let nextChatDestToken: number = 1;
const shownChatDests: Set<number> = new Set<number>();

export function allocChatDestToken(): number {
  return nextChatDestToken++;
}

function isCoveredByRouterEntryPage(): boolean {
  try {
    const state = currentUIContext()?.getRouter().getState();
    if (state !== undefined && state.name !== undefined && state.name !== '' && state.name !== 'Index') {
      return true;
    }
  } catch (_e) {
    // 单测或非 UI 上下文下忽略。
  }
  return false;
}

function syncChatDetailShownStorage(): void {
  const shown: boolean = shownChatDests.size > 0;
  if (AppStorage.get<boolean>(KEY_CHAT_DETAIL_SHOWN) !== shown) {
    AppStorage.setOrCreate<boolean>(KEY_CHAT_DETAIL_SHOWN, shown);
  }
}

export function markChatDestShown(token: number): void {
  if (token <= 0) {
    return;
  }
  shownChatDests.add(token);
  syncChatDetailShownStorage();
}

export function markChatDestHidden(token: number, force: boolean = false): void {
  // 若当前并非目的地在 chatStack 内出栈/被栈内新页覆盖，而是 Index 被外层
  // router.pushUrl 页面（如 GroupAdminPage / InAppBrowserPage）整页盖住触发的
  // onHidden，则保留其活跃 token，确保 router.back() 返回瞬间（即便早于 onWillShow
  // 或不补发 onShown）也能拦截 HdsNavigation 误报的 onNavBarStateChange(true)。
  // 目的地真正销毁（aboutToDisappear，force=true）时无条件移除。
  if (!force && isCoveredByRouterEntryPage()) {
    return;
  }
  if (!shownChatDests.delete(token)) {
    return;
  }
  syncChatDetailShownStorage();
}

export function clearChatDestShownIfStackEmpty(stackDepth: number): void {
  if (stackDepth <= 0 && shownChatDests.size > 0) {
    shownChatDests.clear();
    syncChatDetailShownStorage();
  }
}

export function resetChatDestShownForTest(): void {
  shownChatDests.clear();
  AppStorage.setOrCreate<boolean>(KEY_CHAT_DETAIL_SHOWN, false);
}
