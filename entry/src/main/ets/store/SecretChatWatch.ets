import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logE } from '../util/log';
import { SecretChatInfo, parseSecretChat } from '../util/secretChat';

// 盯住一个密聊的状态。
//
// **为什么不是一次性 getSecretChat**：密聊建立是异步的——发起方发出请求后
// 会话处于 pending，要等对方设备上线接受才变 ready，中间没有任何轮询点。
// 只取一次的话，用户看到的永远是刚创建那一刻的状态（"等待对方接受"卡住不动），
// 而实际上对方早就接受了。TDLib 用 updateSecretChat 推这个变化。
//
// **为什么不做成常驻 store**：订阅要跟着 TdClient 走，而账号切换会重建 client
// （见 Globals）。页面级订阅 + 页面消失时退订，是本项目里其它更新（chatAction、
// forumTopic 等）一直用的形状，不会留下指向旧 client 的悬空订阅。
export function watchSecretChat(
  secretChatId: number, onInfo: (info: SecretChatInfo) => void
): () => void {
  if (secretChatId <= 0) {
    return (): void => {};
  }
  let disposed: boolean = false;
  const req: TdRequest = { '@type': 'getSecretChat' };
  req['secret_chat_id'] = secretChatId;
  getTdClient().send(req).then((raw: TdObject): void => {
    if (!disposed) {
      onInfo(parseSecretChat(raw));
    }
  }).catch((e: TdError): void => {
    logE(`watchSecretChat(${secretChatId}) getSecretChat failed: ${e.message}`);
  });
  const off: () => void = getTdClient().onUpdate('updateSecretChat', (u: TdObject): void => {
    const raw = u['secret_chat'] as TdObject | undefined;
    if (raw === undefined || disposed) {
      return;
    }
    // 一个订阅收所有密聊的更新，自己筛 id——TDLib 的更新不带过滤。
    if (((raw['id'] as number | undefined) ?? 0) !== secretChatId) {
      return;
    }
    onInfo(parseSecretChat(raw));
  });
  return (): void => {
    disposed = true;
    off();
  };
}
