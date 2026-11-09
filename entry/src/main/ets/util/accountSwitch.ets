// 切换账号的共同两步：先收掉直播悬浮窗（它挂在旧账号的会话上），再切 TDLib 槽位。
// 设置页和页签栏的长按菜单都走这里；页面自己的忙碌态/错误态仍由页面管。
import { promptAction } from '@kit.ArkUI';
import { floatingLiveWindow } from '../pages/chat/LiveFloatingWindow';
import { clearPendingNavs } from './pendingNav';
import { resetFavoriteStickers } from '../store/FavoriteStickers';
import { switchTdAccount } from '../tdkit/Globals';
import { logE } from './log';
import { str } from './strings';

export function switchAccountWithLiveWindow(slotId: string): Promise<void> {
  // 账号级缓存必须在切之前清掉：收藏贴纸表是按账号的，留着会让新账号的
  // 长按菜单显示上一个账号的收藏状态。
  resetFavoriteStickers();
  // 挂起的跳转同理：旧账号的 chatId 在新账号下是另一个会话。
  clearPendingNavs();
  return floatingLiveWindow.closeForAccountSwitch()
    .then((): Promise<void> => switchTdAccount(slotId));
}

// 没有页面态可挂的调用方（页签栏菜单）用这个：失败只提示，不留状态。
export function switchAccountOrToast(slotId: string): void {
  switchAccountWithLiveWindow(slotId).catch((caught: Error): void => {
    logE(`accountSwitch failed: ${caught.message}`);
    promptAction.showToast({ message: str('settings_switch_failed'), duration: 1800 });
  });
}
