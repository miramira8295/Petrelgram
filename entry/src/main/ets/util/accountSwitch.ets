// 切换账号的共同两步：先收掉直播悬浮窗（它挂在旧账号的会话上），再切 TDLib 槽位。
// 设置页和页签栏的长按菜单都走这里；页面自己的忙碌态/错误态仍由页面管。
import { promptAction } from '@kit.ArkUI';
import { floatingLiveWindow } from '../pages/chat/LiveFloatingWindow';
import { switchTdAccount } from '../tdkit/Globals';
import { logE } from './log';
import { str } from './strings';

export function switchAccountWithLiveWindow(slotId: string): Promise<void> {
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
