import { ChatKind } from './ChatEntry';

// 「清空聊天记录」能不能做、能怎么做，由 TDLib 放在 chat 上的两个能力位决定，
// 不是由会话类型推出来的。td_api.tl:
//
//   //@can_be_deleted_only_for_self True, if the chat messages can be deleted
//   //  only for the current user while other users will continue to see the messages
//   //@can_be_deleted_for_all_users True, if the chat messages can be deleted for all users
//   //@description Deletes all messages in the chat. Use chat.can_be_deleted_only_for_self
//   //  and chat.can_be_deleted_for_all_users fields to find whether and how the
//   //  method can be applied to the chat
//   deleteChatHistory chat_id:int53 remove_from_chat_list:Bool revoke:Bool = Ok;
//
// 对应关系（MessagesManager::delete_dialog_history）：revoke=false 需要
// can_be_deleted_only_for_self，否则报 "Can't delete history of X only for self"；
// revoke=true 需要 can_be_deleted_for_all_users，缺了但 only_for_self 为真时
// TDLib 会自己降级成 revoke=false，不报错。
//
// 两个位都为假是常见情况，不是异常：公开超级群、广播频道、话题群对非创建者
// 都是 {false,false}（issue 里那个「老张观影群」即此）。这种会话根本不该出现
// 清空入口。反过来，活跃密聊是 {false,true} —— 只能为双方清空，按"私聊就给
// revoke=false"的老逻辑同样会报错。
export interface ClearHistoryOption {
  // 按钮文案的资源 key（走 $r('app.string.<key>')）。
  labelKey: string;
  // 这个按钮对应的 deleteChatHistory.revoke。
  revoke: boolean;
}

// revoke=true 的文案要分会话类型：私聊/密聊只有对方一个人，群和频道是所有人。
function forAllLabelKey(kind: ChatKind): string {
  if (kind === 'private' || kind === 'secret') {
    return 'cl_clear_for_both';
  }
  return 'cl_clear_for_everyone';
}

// 能力位 → 确认框里给出的清空选项。返回空数组表示这个会话清不了，调用方应当
// 连菜单项都不显示。顺序即按钮顺序（前面是破坏性更小的那个）。
export function clearHistoryOptions(
  canDeleteOnlyForSelf: boolean, canDeleteForAllUsers: boolean, kind: ChatKind
): ClearHistoryOption[] {
  const options: ClearHistoryOption[] = [];
  if (canDeleteOnlyForSelf) {
    options.push({ labelKey: 'clear_all', revoke: false });
  }
  if (canDeleteForAllUsers) {
    options.push({ labelKey: forAllLabelKey(kind), revoke: true });
  }
  return options;
}

export function canClearHistory(canDeleteOnlyForSelf: boolean, canDeleteForAllUsers: boolean): boolean {
  return canDeleteOnlyForSelf || canDeleteForAllUsers;
}

// 「删除聊天」（deleteChatHistory + remove_from_chat_list）该带哪个 revoke。
// 只为自己删得掉就为自己删；删不掉但能为所有人删（活跃密聊就是这种）才升级。
export function deleteChatRevoke(canDeleteOnlyForSelf: boolean, canDeleteForAllUsers: boolean): boolean {
  return !canDeleteOnlyForSelf && canDeleteForAllUsers;
}
