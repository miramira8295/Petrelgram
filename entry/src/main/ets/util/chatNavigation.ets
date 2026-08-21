import { promptAction } from '@kit.ArkUI';
import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logChatNavFailure, navigateToChat } from './chatNav';
import { logE } from './log';

// 点"转发自 X"时的跳转。不碰页面状态，之前只是被关在 ChatPage 里。

// 点"转发自 X"：开原帖所在的频道/会话；若来源是个人，则开与他的私聊。
// 隐藏来源的转发不带任何 id，两个分支都不满足，静默不动。
export function openForwardOrigin(
  originChatId: number, originMsgId: number, originUserId: number
): void {
  if (originChatId !== 0) {
    const params: Record<string, Object> = { 'chatId': originChatId };
    if (originMsgId !== 0) {
      params['jumpTo'] = originMsgId;
    }
    navigateToChat(params).catch(logChatNavFailure);
    return;
  }
  if (originUserId === 0) {
    return;
  }
  const req: TdRequest = { '@type': 'createPrivateChat' };
  req['user_id'] = originUserId;
  req['force'] = true;
  getTdClient().send(req).then((chat: TdObject): void => {
    const id = (chat['id'] as number | undefined) ?? 0;
    if (id !== 0) {
      const params: Record<string, Object> = { 'chatId': id };
      navigateToChat(params).catch(logChatNavFailure);
    }
  }).catch((e: TdError): void => {
    logE(`openForwardOrigin createPrivateChat failed: ${e.message}`);
    promptAction.showToast({ message: $r('app.string.cp_cannot_open_source'), duration: 1500 });
  });
}
