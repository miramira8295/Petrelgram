import { TdObject } from '../tdkit/TdTypes';

// 「全部置顶」面板里的一条。
//
// 【为什么单独建模】置顶条原来只需要一行预览文本，所以 MessageStore 从
// searchChatMessages 的结果里只留了 id 和 formatPreview 的字符串，发送人和时间
// 当场丢掉。面板要按「谁 · 什么时候 · 说了什么」列出来，就得把那两样一起留住。
//
// 【为什么不直接复用 MessageEntry】那是气泡的渲染模型，七十多个字段、还挂着
// 下载态和旁路通道。置顶列表只读四样，为它拖进整条链路不成比例（媒体缩略图
// 同理，这一版刻意不做）。
//
// 【senderId 为什么和名字分开存】名字要经 UserStore 解，而 UserStore 是异步补全
// 的——刚进会话时 displayName 可能还是空。存 id 就能在面板每次 build 时重新问一次，
// 名字到货自然就出来了，不必为此再搭一条通知。
export interface PinnedEntry {
  id: number;
  preview: string;
  // 发送者。频道消息和匿名管理员没有用户 id，这时为 0，界面回落到会话名。
  senderId: number;
  // 消息时间（unix 秒）。0 = 解析不出来，界面就不显示时间那一段。
  date: number;
}

// 从 searchChatMessages 返回的一条原始消息里取出 senderId。
//
// sender_id 有两种形状：messageSenderUser（user_id）和 messageSenderChat（chat_id）。
// 这里**只认前者**——后者是"以频道/群身份发言"，那种情况下显示会话名比显示一个
// 陌生的 chat_id 更有意义，交给界面回落。
export function pinnedSenderId(message: TdObject): number {
  const sender = message['sender_id'] as TdObject | undefined;
  if (sender === undefined) {
    return 0;
  }
  const kind: string = (sender['@type'] as string | undefined) ?? '';
  if (kind !== 'messageSenderUser') {
    return 0;
  }
  return (sender['user_id'] as number | undefined) ?? 0;
}

export function pinnedDate(message: TdObject): number {
  const d = message['date'] as number | undefined;
  return d !== undefined && d > 0 ? d : 0;
}

// id 缺失的条目一律丢掉：没有 id 就跳不过去，列出来只会让人点了没反应。
export function pinnedEntryOf(message: TdObject, preview: string): PinnedEntry | null {
  const id = message['id'] as number | undefined;
  if (id === undefined || id === 0) {
    return null;
  }
  return {
    id, preview,
    senderId: pinnedSenderId(message),
    date: pinnedDate(message)
  };
}

// 面板标题右边那个计数。超过一屏时给个上限提示——searchChatMessages 一次最多
// 取 100 条，再多的置顶我们根本没拉下来，显示真实条数会让人以为列表不全是 bug。
export const PINNED_FETCH_LIMIT: number = 100;

export function pinnedCountLabel(count: number): string {
  return count >= PINNED_FETCH_LIMIT ? `${PINNED_FETCH_LIMIT}+` : `${count}`;
}
