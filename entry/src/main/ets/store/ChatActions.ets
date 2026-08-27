import { promptAction } from '@kit.ArkUI';
import { getFolderStore, getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { chatListOf } from './ListKey';
import { serializeFolderMutation } from './FolderApi';
import { ChatKind } from './ChatEntry';
import { deleteChatRevoke } from './ClearHistoryOptions';
import { str } from '../util/strings';
import { logE } from '../util/log';

// Every chat-list context-menu action, as a plain TDLib call. The UI never
// mutates the store directly — TDLib echoes each change back as an update
// (updateChatPosition / updateChatNotificationSettings / ...) and ChatStore
// re-renders from that, so the list stays consistent with the server.

// TDLib treats "muted forever" as this sentinel, NOT 0xFFFFFFFF (which
// overflows int32 and is rejected).
export const MUTE_FOREVER: number = 2147483647;

// 曾经怀疑 MUTE_FOREVER 这个哨兵值会被服务端拒绝（现象是本地先生效、约
// 400ms 后被回退成"跟随默认"），因此一度改用 366 天。后来确认：那个回退是
// **服务端对通知设置变更的限流** —— 短时间内连续修改多个会话就会触发，
// 隔一会儿再点同一个会话就能成功。和 mute_for 的取值无关。
// 所以恢复用哨兵值，"永久静音"才是真的永久，不会一年后自己解除。
export const MUTE_LONG: number = MUTE_FOREVER;

export interface MuteOption {
  label: string;
  seconds: number;
}

export const MUTE_OPTIONS: MuteOption[] = [
  { label: str('ca_mute_1h'), seconds: 3600 },
  { label: str('ca_mute_8h'), seconds: 8 * 3600 },
  { label: str('ca_mute_2d'), seconds: 2 * 24 * 3600 },
  { label: str('ca_mute_forever'), seconds: MUTE_LONG }
];

function fail(what: string, e: TdError): void {
  logE(`ChatActions.${what} failed: ${e.message}`);
  promptAction.showToast({ message: str('ca_action_failed_msg', e.message), duration: 2000 });
}

// TDLib 的 chat 级方法都要求该会话在当前运行期"已加载"，否则一律拒为
// Wrong chat identifier specified。会话列表很长时，多数会话并不在最近活跃的
// 那批，从列表长按触发的操作就会莫名失败。getChat 会把它从数据库读回内存。
//
// 只用在用户主动触发的一次性操作上 —— 多一次往返换确定性是划算的；
// 高频路径（比如滚动时的批量读取）不该走这里。
function withChat(chatId: number, what: string, run: () => Promise<TdObject>): void {
  const load: TdRequest = { '@type': 'getChat' };
  load['chat_id'] = chatId;
  getTdClient().send(load)
    .then((): Promise<TdObject> => run())
    .catch((e: TdError) => { fail(what, e); });
}

export function togglePin(listKey: string, chatId: number, pinned: boolean): void {
  withChat(chatId, 'togglePin', (): Promise<TdObject> => {
    const req: TdRequest = { '@type': 'toggleChatIsPinned' };
    req['chat_list'] = chatListOf(listKey);
    req['chat_id'] = chatId;
    req['is_pinned'] = pinned;
    return getTdClient().send(req);
  });
}

// chatNotificationSettings 是一个**整体**：它有 8 个 use_default_* 开关，
// 只发其中一两个字段时，其余在 JSON 转换里全部缺省为 false —— 等于顺带声明
// "提示音、预览、置顶、提及也都不跟随默认"，而它们的值字段又是空的。
// 服务端会拒绝这一整套非法组合：本地先生效，约 400ms 后被整体回退成跟随默认。
//
// 所以必须先读回当前设置，只覆盖要改的字段，再把完整对象发回去。
// getChat 同时解决了另一个问题：TDLib 只认当前运行期加载过的会话，
// 冷会话直接调用会被拒为 Wrong chat identifier specified。
function updateChatNotificationSettings(
  chatId: number, mutate: (settings: TdObject) => void, what: string
): Promise<boolean> {
  const load: TdRequest = { '@type': 'getChat' };
  load['chat_id'] = chatId;
  return getTdClient().send(load).then((chat: TdObject): Promise<TdObject> => {
    const current = chat['notification_settings'] as TdObject | undefined;
    // 复制而不是原地改 TDLib 回给我们的对象。
    const settings: TdObject = { '@type': 'chatNotificationSettings' };
    if (current !== undefined) {
      for (const key of Object.keys(current)) {
        settings[key] = current[key];
      }
      settings['@type'] = 'chatNotificationSettings';
    }
    mutate(settings);
    const req: TdRequest = { '@type': 'setChatNotificationSettings' };
    req['chat_id'] = chatId;
    req['notification_settings'] = settings;
    return getTdClient().send(req);
  }).then((): boolean => true).catch((e: TdError): boolean => {
    fail(what, e);
    return false;
  });
}

// 恢复成"跟随作用域默认值"。撤销操作需要它 —— 如果原本就是跟随默认，
// 用 setMute 回写会留下一条显式设置，和撤销前的状态并不等价。
export function useDefaultMute(chatId: number): Promise<boolean> {
  return updateChatNotificationSettings(chatId, (settings: TdObject): void => {
    settings['use_default_mute_for'] = true;
    settings['mute_for'] = 0;
  }, 'useDefaultMute');
}

// seconds = 0 unmutes; 长期静音传 MUTE_LONG。
export function setMute(chatId: number, seconds: number): Promise<boolean> {
  return updateChatNotificationSettings(chatId, (settings: TdObject): void => {
    settings['use_default_mute_for'] = false;
    settings['mute_for'] = seconds;
  }, 'setMute');
}

// Reads everything up to the newest message and clears a manual unread flag.
export function markAsRead(chatId: number, lastMessageId: number): void {
  const client = getTdClient();
  if (lastMessageId !== 0) {
    const view: TdRequest = { '@type': 'viewMessages' };
    view['chat_id'] = chatId;
    view['message_ids'] = [lastMessageId];
    view['force_read'] = true;
    client.send(view).catch((e: TdError) => { fail('markAsRead', e); });
  }
  markUnread(chatId, false);
}

export function markUnread(chatId: number, unread: boolean): void {
  withChat(chatId, 'markUnread', (): Promise<TdObject> => {
    const req: TdRequest = { '@type': 'toggleChatIsMarkedAsUnread' };
    req['chat_id'] = chatId;
    req['is_marked_as_unread'] = unread;
    return getTdClient().send(req);
  });
}

export function setArchived(chatId: number, archived: boolean): void {
  withChat(chatId, 'setArchived', (): Promise<TdObject> => {
    const req: TdRequest = { '@type': 'addChatToList' };
    req['chat_id'] = chatId;
    req['chat_list'] = chatListOf(archived ? 'archive' : 'main');
    return getTdClient().send(req);
  });
}

// TDLib has no "add chat to folder" call: the whole folder must be read,
// edited and written back.
export async function setInFolder(folderId: number, chatId: number, include: boolean): Promise<void> {
  try {
    await serializeFolderMutation(async (): Promise<void> => {
      const client = getTdClient();
      const get: TdRequest = { '@type': 'getChatFolder' };
      get['chat_folder_id'] = folderId;
      const folder = await client.send(get);
      const included = (folder['included_chat_ids'] as number[] | undefined) ?? [];
      const next = include
        ? (included.includes(chatId) ? included : [...included, chatId])
        : included.filter((id: number) => id !== chatId);
      const pinned = (folder['pinned_chat_ids'] as number[] | undefined) ?? [];
      const excluded = (folder['excluded_chat_ids'] as number[] | undefined) ?? [];
      const nextFolder: TdObject = folder;
      nextFolder['included_chat_ids'] = next;
      // Explicit inclusion and exclusion are mutually exclusive.
      if (include) {
        nextFolder['excluded_chat_ids'] = excluded.filter((id: number) => id !== chatId);
      } else {
        nextFolder['pinned_chat_ids'] = pinned.filter((id: number) => id !== chatId);
      }
      const edit: TdRequest = { '@type': 'editChatFolder' };
      edit['chat_folder_id'] = folderId;
      edit['folder'] = nextFolder;
      const info = await client.send(edit);
      getFolderStore().applyServerFolderInfo(info);
    });
    promptAction.showToast({ message: include ? str('ca_added_to_folder') : str('ca_removed_from_folder'), duration: 1500 });
  } catch (e) {
    fail('setInFolder', e as TdError);
  }
}

// revoke: 为所有人清空，而不是只为自己清空。两种做法各有前置条件，见
// ClearHistoryOptions —— 调用方必须先按 chat 的能力位挑，不能硬写。
export function clearHistory(chatId: number, revoke: boolean): void {
  withChat(chatId, 'clearHistory', (): Promise<TdObject> => {
    const req: TdRequest = { '@type': 'deleteChatHistory' };
    req['chat_id'] = chatId;
    req['remove_from_chat_list'] = false;
    req['revoke'] = revoke;
    return getTdClient().send(req);
  });
}

// 屏蔽私聊对方。私聊的 chat_id 就是对方的 user_id，所以可以直接用；密聊不行
// （chat_id 是密聊会话 id，不是用户 id），调用方只对 private 开放这个入口。
export function blockPrivateChatSender(chatId: number): Promise<void> {
  const sender: TdObject = { '@type': 'messageSenderUser' };
  sender['user_id'] = chatId;
  const req: TdRequest = { '@type': 'setMessageSenderBlockList' };
  req['sender_id'] = sender;
  req['block_list'] = { '@type': 'blockListMain' } as TdObject;
  return getTdClient().send(req).then((): void => {});
}

// 屏蔽并删除。先屏蔽再删除：反过来的话，删除到屏蔽之间对方新发的消息会把
// 会话重新拉回列表，看起来像"删了又冒出来"。
// revoke 固定为 false 是安全的：这个入口只对 private 开放（见 blockPrivateChatSender
// 的注释），而 TDLib 对 User 类型的会话恒有 can_be_deleted_only_for_self=true
// （MessagesManager::can_delete_dialog 的 DialogType::User 分支返回 {true, …}）。
export function blockAndDeleteChat(chatId: number): void {
  withChat(chatId, 'blockAndDelete', (): Promise<TdObject> => {
    return blockPrivateChatSender(chatId).then((): Promise<TdObject> => {
      const req: TdRequest = { '@type': 'deleteChatHistory' };
      req['chat_id'] = chatId;
      req['remove_from_chat_list'] = true;
      req['revoke'] = false;
      return getTdClient().send(req);
    });
  });
}

// Groups/channels are left; private and secret chats are deleted from the list.
// revoke 由会话的能力位决定，不能硬写 false：活跃密聊在 TDLib 里是
// {can_be_deleted_only_for_self:false, can_be_deleted_for_all_users:true}
// （"active secret chats can be deleted only for both users"），带 revoke=false
// 会直接报 "Can't delete history of X only for self"。
export function leaveOrDeleteChat(
  chatId: number, kind: ChatKind,
  canDeleteOnlyForSelf: boolean, canDeleteForAllUsers: boolean
): void {
  if (kind === 'basicGroup' || kind === 'supergroup' || kind === 'channel') {
    withChat(chatId, 'leaveChat', (): Promise<TdObject> => {
      const req: TdRequest = { '@type': 'leaveChat' };
      req['chat_id'] = chatId;
      return getTdClient().send(req);
    });
    return;
  }
  withChat(chatId, 'deleteChat', (): Promise<TdObject> => {
    const req: TdRequest = { '@type': 'deleteChatHistory' };
    req['chat_id'] = chatId;
    req['remove_from_chat_list'] = true;
    req['revoke'] = deleteChatRevoke(canDeleteOnlyForSelf, canDeleteForAllUsers);
    return getTdClient().send(req);
  });
}

// Menu label for the destructive last item, by chat kind.
export function leaveLabel(kind: ChatKind): string {
  if (kind === 'channel') {
    return str('cp_leave_channel');
  }
  if (kind === 'basicGroup' || kind === 'supergroup') {
    return str('cp_leave_group');
  }
  return str('ca_delete_chat');
}

// A full sentence per kind rather than a verb spliced out of leaveLabel(). The
// caller used to do label.substring(0, 2) to get "退出" / "删除" — a character
// slice of display text, which yields "De" the moment the label is English.
export function leaveConfirmMessage(kind: ChatKind, title: string): string {
  if (kind === 'channel') {
    return str('ca_confirm_leave_channel', title);
  }
  if (kind === 'basicGroup' || kind === 'supergroup') {
    return str('ca_confirm_leave_group', title);
  }
  return str('ca_confirm_delete_chat', title);
}
