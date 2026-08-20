// 这条系统消息是不是"你加入了本群/频道"。
//
// 用来决定要不要在会话里显示那条本地生成的加入提示——如果服务端已经下发了
// 真实的加入系统消息，就不该再自己补一条，否则用户看到两条。
//
// 前两个判据比较的是**显示文案**，这本身很脆弱：那串字是服务端给的，却拿来
// 和本应用自己的翻译比对。两边现在都过 str()，至少语言一致，但真正靠得住的
// 是后面两个 systemType。这个脆弱性是既有的，抽出来不是为了修它，是为了让它
// 有测试盯着——将来把它换成合成行上的显式标记时，测试能证明换法等价。

import { str } from './strings';

export interface JoinNoticeInput {
  contentType: string;
  isOutgoing: boolean;
  placeholderLabel: string;
  systemType: string;
}

export function isRealClientJoinNotice(message: JoinNoticeInput): boolean {
  // 必须是自己发出的系统消息：别人入群的提示不算。
  if (message.contentType !== 'system' || !message.isOutgoing) {
    return false;
  }
  return message.placeholderLabel === str('cp_joined_group') ||
    message.placeholderLabel === str('cp_joined_channel') ||
    message.systemType === 'messageChatJoinByLink' ||
    message.systemType === 'messageChatJoinByRequest';
}
