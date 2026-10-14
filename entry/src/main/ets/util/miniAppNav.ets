import { router, promptAction } from '@kit.ArkUI';
import { MiniAppLaunch } from './miniAppModel';
import { MessageEntry } from '../store/MessageEntry';
import { endLinkNav } from './linkTapGuard';

let pushing: boolean = false;

export function openMiniAppPage(launch: MiniAppLaunch): void {
  if (pushing) { return; }
  pushing = true;
  router.pushUrl({ url: 'pages/web/MiniAppPage', params: launch }).catch((): void => {
    promptAction.showToast({ message: $r('app.string.cp_cannot_open_miniapp') });
  }).finally((): void => {
    pushing = false;
    endLinkNav();
  });
}

export function openMessageMiniApp(chatId: number, message: MessageEntry | null, url: string): void {
  if (message === null || !message.senderIsUser || message.senderId <= 0) {
    promptAction.showToast({ message: $r('app.string.cp_cannot_open_miniapp') });
    return;
  }
  openMiniAppPage({ kind: 'web', chatId, botUserId: message.senderId, title: message.senderName, url });
}
