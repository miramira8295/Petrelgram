import { ChatEntry } from '../store/ChatEntry';

// 系统分享进来之后，"发给谁"这份候选名单的排序与序列化。纯函数，无 IO。
//
// 【为什么要单独一份而不是直接用会话列表】会话列表是按"最后一条消息时间"排的，
// 里面混着大量**别人发给我**的会话（频道推送、群里的闲聊）。分享的目标几乎总是
// "我主动联系的人"，两者顺序差得很远。所以名单 = 收藏置顶 + 我主动发过消息的
// 会话（近到远）+ 会话列表兜底。
//
// 【为什么要序列化】分享面板里的那份 UI 跑在 ShareExtensionAbility 里，那是
// 独立进程、没有登录态、拿不到 TDLib。它只能读主应用预先落盘的这份快照。
// 见 services/ShareTargetSnapshot。

// 快照格式版本。字段含义变了就 +1，老版本快照直接丢弃（宁可少一行推荐，
// 也不要拿旧字段去喂新界面）。
export const SHARE_SNAPSHOT_VERSION: number = 1;

// 快照里最多存几个。分享面板横排一行只看得见 4–6 个，多存是给应用内的
// 选择页做"最近"分组用的。
export const SHARE_TARGET_LIMIT: number = 12;

// 「最近主动聊过」这份 id 表最多记多长。比 SHARE_TARGET_LIMIT 长一些，
// 这样有会话被删/被过滤掉时后面还有货补上。
export const RECENT_OUTGOING_CAP: number = 30;

export interface ShareTarget {
  chatId: number;
  title: string;
  // 头像文件的本地绝对路径。空串表示还没下载好，界面退回首字母。
  avatarPath: string;
  initials: string;
  isSavedMessages: boolean;
}

// 「我主动发过消息」的 id 表：最近的在前，去重，定长。
// 不可变——返回新数组，原表不动。
export function pushRecentOutgoing(list: number[], chatId: number,
  cap: number = RECENT_OUTGOING_CAP): number[] {
  if (chatId === 0 || cap <= 0) {
    return list;
  }
  const out: number[] = [chatId];
  for (let i = 0; i < list.length && out.length < cap; i++) {
    if (list[i] !== chatId) {
      out.push(list[i]);
    }
  }
  return out;
}

function targetOf(chat: ChatEntry): ShareTarget {
  return {
    chatId: chat.id,
    title: chat.title,
    avatarPath: chat.avatarPath,
    initials: chat.initials,
    isSavedMessages: chat.isSavedMessages
  };
}

// 候选名单。顺序是三段拼起来的：
//   1. 我的收藏（用户明确要求置顶；它是"发给自己存一下"最高频的去处）
//   2. 我主动发过消息的会话，近到远
//   3. 会话列表兜底，按最后消息时间——新装的应用第 2 段是空的，
//      没有这一段用户第一次分享会看到空白
// 三段都跳过已经进过名单的 id，跳过占位条目（id === 0）。
export function orderShareTargets(chats: ChatEntry[], recentOutgoing: number[],
  limit: number = SHARE_TARGET_LIMIT): ShareTarget[] {
  if (limit <= 0) {
    return [];
  }
  const byId: Map<number, ChatEntry> = new Map<number, ChatEntry>();
  for (let i = 0; i < chats.length; i++) {
    const chat: ChatEntry = chats[i];
    if (chat.id !== 0) {
      byId.set(chat.id, chat);
    }
  }
  const out: ShareTarget[] = [];
  const taken: Set<number> = new Set<number>();
  const take = (chat: ChatEntry | undefined): void => {
    if (chat === undefined || taken.has(chat.id) || out.length >= limit) {
      return;
    }
    taken.add(chat.id);
    out.push(targetOf(chat));
  };

  // 1. 收藏
  for (let i = 0; i < chats.length; i++) {
    if (chats[i].isSavedMessages) {
      take(chats[i]);
      break;
    }
  }
  // 2. 最近主动
  for (let i = 0; i < recentOutgoing.length; i++) {
    take(byId.get(recentOutgoing[i]));
  }
  // 3. 兜底：按最后消息时间从新到旧。不改入参——先浅拷贝再排。
  const rest: ChatEntry[] = chats.filter((chat: ChatEntry): boolean =>
    chat.id !== 0 && !taken.has(chat.id));
  rest.sort((a: ChatEntry, b: ChatEntry): number => b.lastMessageDate - a.lastMessageDate);
  for (let i = 0; i < rest.length; i++) {
    take(rest[i]);
  }
  return out;
}

export function serializeShareTargets(targets: ShareTarget[]): string {
  const payload: Record<string, Object> = {
    'version': SHARE_SNAPSHOT_VERSION,
    'targets': targets
  };
  return JSON.stringify(payload);
}

// 反序列化。快照文件是跨进程读的，格式错、被截断、版本不符一律当成"没有快照"
// 而不是抛异常——分享面板宁可少一行推荐，也不能因为解析失败起不来。
export function parseShareTargets(text: string): ShareTarget[] {
  if (text === '') {
    return [];
  }
  let raw: Record<string, Object> | null = null;
  try {
    raw = JSON.parse(text) as Record<string, Object>;
  } catch (e) {
    return [];
  }
  if (raw === null || (raw['version'] as number | undefined) !== SHARE_SNAPSHOT_VERSION) {
    return [];
  }
  const list = raw['targets'] as Object[] | undefined;
  if (list === undefined || !Array.isArray(list)) {
    return [];
  }
  const out: ShareTarget[] = [];
  for (let i = 0; i < list.length; i++) {
    const row = list[i] as Record<string, Object> | null;
    if (row === null) {
      continue;
    }
    const chatId = row['chatId'] as number | undefined;
    const title = row['title'] as string | undefined;
    if (chatId === undefined || chatId === 0 || typeof chatId !== 'number') {
      continue;
    }
    out.push({
      chatId: chatId,
      title: title ?? '',
      avatarPath: (row['avatarPath'] as string | undefined) ?? '',
      initials: (row['initials'] as string | undefined) ?? '',
      isSavedMessages: (row['isSavedMessages'] as boolean | undefined) ?? false
    });
  }
  return out;
}
