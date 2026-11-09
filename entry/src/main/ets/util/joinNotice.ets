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
import { MessageEntry } from '../store/MessageEntry';
import { AlbumGroup } from './collapseAlbums';
import { TdObject } from '../tdkit/TdTypes';

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

// ── 本地那条「你加入了本群/频道」提示行 ─────────────────────────────────
//
// 从入群/进频道那条路由进来时，服务端的入群系统消息往往还没下发，页面先自己
// 合成一条摆在时间线末尾；等 isRealClientJoinNotice 认出真的那条，页面再把
// 本地这条撤掉（撤掉是有副作用的动作，留在页面，见下面 hasRealClientJoinNotice
// 的说明）。

// 合成行的哨兵 id。**刻意是 -1，绝不能改成 0**：0 是"没有消息"的自然默认值，
// 会和一堆按 id 取默认值的地方撞上；负数则不可能与任何真实 message id 相等，
// 查找与动作匹配都无从命中。tagClientJoinNoticeGroup 也靠它认出末组。
export const CLIENT_JOIN_NOTICE_ID: number = -1;

// 合成那条假的 TDLib message 对象。调用方拿它喂 buildMessageEntry。
// dateSec 是**秒**（Math.floor(Date.now() / 1000)），与 TDLib 的 date 字段同单位。
export function clientJoinNoticeRaw(
  chatId: number, dateSec: number, isChannel: boolean
): TdObject {
  const content: TdObject = isChannel
    ? { '@type': 'messageCustomServiceAction', 'text': str('cp_joined_channel') }
    : { '@type': 'messageChatJoinByLink' };
  const raw: TdObject = {
    '@type': 'message',
    // The row is page-local and memberIds is cleared below. A negative id
    // also makes accidental lookup/action matching impossible.
    'id': CLIENT_JOIN_NOTICE_ID,
    'chat_id': chatId,
    'date': dateSec,
    'is_outgoing': true,
    'content': content
  };
  return raw;
}

// 给合成行所在的那一组打标：**原地**改 groups 的末组（collapseAlbums 刚返回的
// 那个数组），与原实现逐字等价，不复制数组——它在每次消息快照发布路径上跑。
//
// 两件事：memberIds 清空（那不是真消息 id，不能让选择/回复/播放位按它去找），
// key 换成 `client_join_${chatId}_${date}`——**格式逐字保留**，它是这一行的行
// 身份，改了就等于每次快照都换 key、行被销毁重建。
//
// 末组不是合成行（head.id 不是哨兵）时什么都不做。
export function tagClientJoinNoticeGroup(
  groups: AlbumGroup[], chatId: number, dateSec: number
): void {
  if (groups.length === 0) {
    return;
  }
  const notice: AlbumGroup = groups[groups.length - 1];
  if (notice.head.id !== CLIENT_JOIN_NOTICE_ID) {
    return;
  }
  notice.memberIds = [];
  notice.key = `client_join_${chatId}_${dateSec}`;
}

// 这份快照里是不是已经有了真实的入群系统消息。
//
// 只是**判定**：认出来之后要做的"把本地行原子换成真行"（清 visible 标志与缓存）
// 是发生在渲染路径上的副作用，留在页面里，不搬进来——那条隐式协议（每次收到
// 消息快照都会跑一次、就地改页面字段）不适合藏在纯函数背后。
export function hasRealClientJoinNotice(list: MessageEntry[]): boolean {
  return list.some((message: MessageEntry): boolean => isRealClientJoinNotice({
    contentType: message.contentType, isOutgoing: message.isOutgoing,
    placeholderLabel: message.placeholderLabel, systemType: message.systemType
  }));
}
