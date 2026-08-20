import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { navigateToChat } from './chatNav';
import { openWebUrl } from './webBrowserNav';

// 从会话里跳到别的会话或资料页的两条路。都不碰页面状态，之前只是被关在
// ChatPage 里；context 现在作为参数传入。

// 解析一个裸 @username：是人就开资料卡，是群/频道就开它的会话页。
// original 是被点击的原始 URL，解析不出来时交给浏览器兜底——比什么都不做好，
// 至少用户还能看到那个链接指向哪。
export function openByUsername(
  context: common.UIAbilityContext, name: string, original: string
): void {
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = name;
  getTdClient().send(req).then((chat: TdObject): void => {
    const chatId = (chat['id'] as number | undefined) ?? 0;
    const type = chat['type'] as TdObject | undefined;
    const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
    if (typeName === 'chatTypePrivate') {
      const uid = ((type as TdObject)['user_id'] as number | undefined) ?? 0;
      if (uid > 0) {
        const params: Record<string, Object> = { 'userId': uid };
        router.pushUrl({ url: 'pages/profile/ProfilePage', params: params });
        return;
      }
    }
    if (chatId !== 0) {
      const params: Record<string, Object> = { 'chatId': chatId };
      navigateToChat(params);
      return;
    }
    openWebUrl(context, original);
  }).catch((e: TdError): void => {
    console.error(`openByUsername(${name}) failed: ${e.message}`);
    openWebUrl(context, original);
  });
}

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
    navigateToChat(params);
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
      navigateToChat(params);
    }
  }).catch((e: TdError): void => {
    console.error(`openForwardOrigin createPrivateChat failed: ${e.message}`);
    promptAction.showToast({ message: $r('app.string.cp_cannot_open_source'), duration: 1500 });
  });
}
