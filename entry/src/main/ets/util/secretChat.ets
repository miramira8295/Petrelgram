// 密聊（端到端加密会话）的状态判定。
//
// **为什么单独一个文件**：这三种状态决定了三处 UI（顶栏副标题、输入区、
// 会话行的锁标），逐处各写一遍 if 必然对不齐。判定是纯函数，能单测。
//
// 【历史】1.4.5 之前 `setTdlibParameters` 里写的是 `use_secret_chats=false`，
// 而资料页一直挂着「开始秘密聊天」的入口。TDLib 那条创建路径**没有闸**
// （Requests.cpp → UserManager::create_new_secret_chat →
// SecretChatsManager::create_chat，是该文件里唯一不检查 use_secret_chats_ 的
// 创建函数），actor 建出来、一关闭就撞上 SecretChatsManager.cpp:455 的
// `CHECK(use_secret_chats_)` → abort。线上崩溃 2026-09-04 08:14 就是它。
// 现在参数打开，这一族状态也随之要真正显示出来。

import { TdObject } from '../tdkit/TdTypes';

// secretChatStatePending / Ready / Closed 三态，去掉前缀存。
export const SECRET_PENDING: string = 'pending';
export const SECRET_READY: string = 'ready';
export const SECRET_CLOSED: string = 'closed';

// 输入区的替代形态。和 util/membershipState、util/botStart 的取值同一个命名空间
// ——ChatPage 的 membershipState 一个字段承载全部「输入区此刻是什么」。
export const MEMBERSHIP_SECRET_PENDING: string = 'secretPending';
export const MEMBERSHIP_SECRET_CLOSED: string = 'secretClosed';

export interface SecretChatInfo {
  // secret_chat_id，不是 chat_id。
  id: number;
  // 对方的 user id。顶栏靠它取头像/在线状态。
  userId: number;
  state: string;
  // 是不是我发起的。等待期的话术两边不同：发起方等对方上线，接收方是在建密钥。
  isOutbound: boolean;
  // 双方协商到的加密层。0 表示还没协商出来。
  layer: number;
}

export function emptySecretChat(): SecretChatInfo {
  return { id: 0, userId: 0, state: SECRET_PENDING, isOutbound: false, layer: 0 };
}

// TDLib 的 SecretChatState → 我们的三态。
//
// 认不出来的一律当 closed 而不是 pending：未知状态下把输入区收起来、告诉用户
// 会话已关闭，最坏是少发一条；反过来放行则是让用户对着一个必然失败的输入框打字。
export function secretStateOf(rawType: string): string {
  if (rawType === 'secretChatStateReady') {
    return SECRET_READY;
  }
  if (rawType === 'secretChatStatePending') {
    return SECRET_PENDING;
  }
  return SECRET_CLOSED;
}

export function parseSecretChat(raw: TdObject | undefined): SecretChatInfo {
  if (raw === undefined) {
    return emptySecretChat();
  }
  const stateObj = raw['state'] as TdObject | undefined;
  const rawState: string = (stateObj?.['@type'] as string | undefined) ?? '';
  const info: SecretChatInfo = {
    id: (raw['id'] as number | undefined) ?? 0,
    userId: (raw['user_id'] as number | undefined) ?? 0,
    state: secretStateOf(rawState),
    isOutbound: (raw['is_outbound'] as boolean | undefined) ?? false,
    layer: (raw['layer'] as number | undefined) ?? 0
  };
  return info;
}

// 这个密聊此刻能不能发消息。只有 ready 能。
export function canSendInSecretChat(info: SecretChatInfo): boolean {
  return info.state === SECRET_READY;
}

// 输入区该换成哪种条。空串 = 不换，照常显示输入框。
export function secretMembershipState(info: SecretChatInfo): string {
  if (info.state === SECRET_READY) {
    return '';
  }
  return info.state === SECRET_PENDING ? MEMBERSHIP_SECRET_PENDING : MEMBERSHIP_SECRET_CLOSED;
}

// 输入区那条替代栏上写什么。
export function secretBarTextKey(state: string, isOutbound: boolean): string {
  if (state === MEMBERSHIP_SECRET_CLOSED) {
    return 'cp_secret_closed';
  }
  return isOutbound ? 'cp_secret_pending_out' : 'cp_secret_pending_in';
}

// 顶栏副标题。空串 = 用原来那句「加密聊天」。
export function secretHeaderKey(info: SecretChatInfo): string {
  if (info.state === SECRET_PENDING) {
    return 'chat_header_secret_pending';
  }
  if (info.state === SECRET_CLOSED) {
    return 'chat_header_secret_closed';
  }
  return '';
}
