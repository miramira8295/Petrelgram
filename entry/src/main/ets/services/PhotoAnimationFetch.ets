import { getChatStore, getTdClient, getUserStore } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logE, logI } from '../util/log';
import { fullInfoRequestForChatType, photoFromFullInfo, pickPhotoAnimationFileId } from '../util/photoAnimation';
import { senderChannelKey } from '../util/senderAvatarChannel';
import { claimSenderAnimation, resolveSenderAnimation } from '../util/senderAnimationChannel';

// 取动态头像：完整资料 → 选一份 MP4 → 下载到本地。顶栏与群聊气泡左侧共用。
// 判据在 util/photoAnimation（纯函数、有单测），这里只管发请求。

const FULL_INFO_TIMEOUT_MS: number = 15000;
const DOWNLOAD_TIMEOUT_MS: number = 30000;
// 顶栏是用户正盯着的那一个；气泡左侧一屏可能有十几个人，排在它后面。
export const HEADER_ANIMATION_PRIORITY: number = 2;
const SENDER_ANIMATION_PRIORITY: number = 1;

function downloadedPath(file: TdObject): string {
  const local = file['local'] as TdObject | undefined;
  if (local === undefined) {
    return '';
  }
  // synchronous 下载本应只在完成后返回；万一回来的是半截文件，交给播放器只会报错。
  if ((local['is_downloading_completed'] as boolean | undefined) === false) {
    return '';
  }
  return (local['path'] as string | undefined) ?? '';
}

// 解析出本地路径；没有动画、请求失败、超时都返回 ''，从不 reject。tag 只用于日志。
export function fetchPhotoAnimationPath(req: TdRequest, preferSmall: boolean, priority: number,
  tag: string): Promise<string> {
  return getTdClient().send(req, FULL_INFO_TIMEOUT_MS).then((full: TdObject): Promise<string> => {
    const photo: TdObject | undefined = photoFromFullInfo(full);
    const fileId: number = pickPhotoAnimationFileId(photo, preferSmall);
    if (fileId <= 0) {
      return Promise.resolve('');
    }
    const dl: TdRequest = { '@type': 'downloadFile' };
    dl['file_id'] = fileId;
    dl['priority'] = priority;
    dl['synchronous'] = true;
    return getTdClient().send(dl, DOWNLOAD_TIMEOUT_MS).then((f: TdObject): string => downloadedPath(f))
      .catch((e: TdError): string => {
        logE(`PhotoAnimationFetch(${tag}) download failed: ${e.message}`);
        return '';
      });
  }).catch((e: TdError): string => {
    // 拿不到完整资料就保持静态头像，不打扰。
    logE(`PhotoAnimationFetch(${tag}) fullInfo failed: ${e.message}`);
    return '';
  });
}

// 发送者头像带不带动画。只看列表里已经有的标志，不发请求——没有动画的人一趟都不该取。
export function senderHasAnimatedPhoto(senderId: number, isUser: boolean): boolean {
  if (senderId === 0) {
    return false;
  }
  return isUser ? getUserStore().hasAnimatedPhoto(senderId) : getChatStore().hasAnimatedPhoto(senderId);
}

function senderFullInfoRequest(senderId: number, isUser: boolean): Promise<TdRequest | null> {
  if (isUser) {
    const req: TdRequest = { '@type': 'getUserFullInfo' };
    req['user_id'] = senderId;
    return Promise.resolve(req);
  }
  // 以会话身份发言（频道、匿名管理员）：先取会话类型再决定问哪种完整资料。
  const getChat: TdRequest = { '@type': 'getChat' };
  getChat['chat_id'] = senderId;
  return getTdClient().send(getChat, FULL_INFO_TIMEOUT_MS).then((chat: TdObject): TdRequest | null =>
    fullInfoRequestForChatType(chat['type'] as TdObject | undefined)
  ).catch((e: TdError): TdRequest | null => {
    logE(`PhotoAnimationFetch getChat(${senderId}) failed: ${e.message}`);
    return null;
  });
}

// 群聊气泡左侧：按发送者取一次，结果进 senderAnimationChannel 广播。可以随便多调——
// 在取、已到、冷却中都会被通道挡回去。
export function requestSenderAnimation(senderId: number, isUser: boolean): void {
  if (!senderHasAnimatedPhoto(senderId, isUser)) {
    return;
  }
  const key: string = senderChannelKey(senderId, isUser);
  const token: number = claimSenderAnimation(key, Date.now());
  if (token === 0) {
    return;
  }
  senderFullInfoRequest(senderId, isUser).then((req: TdRequest | null): Promise<string> =>
    req === null ? Promise.resolve('') : fetchPhotoAnimationPath(req, true, SENDER_ANIMATION_PRIORITY, key)
  ).then((path: string): void => {
    logI(`[SenderAnim] ${key} ${path !== '' ? 'ready' : 'none'}`);
    resolveSenderAnimation(key, token, path, Date.now());
  });
}
