import { RECENT_OUTGOING_CAP, pushRecentOutgoing } from './shareTargets';

// 「最近我主动发过消息的会话」。系统分享的目标名单要按它排（见 util/shareTargets）。
//
// 【为什么不用会话列表的顺序】会话列表按最后一条消息时间排，里面绝大多数是
// **别人发给我**的——频道推送、群里的闲聊。分享的去处几乎总是"我主动联系的人"，
// 两者顺序差得很远。TDLib 的 chat 对象上没有现成的"我最后发言时间"，
// ChatEntry 也没有这个字段，所以自己记一份。
//
// 【为什么是这个文件】MessageStore 要在发送时调它。放成不依赖 store 的叶子模块，
// 避免 MessageStore → ShareTargetService → ChatStore 这条环。
// 刷新快照的活儿交给订阅者（services/ShareTargetService）。

export const KEY_RECENT_OUTGOING: string = 'shareRecentOutgoing';

// 进程内的当前值。启动时由 initRecentOutgoing 从 Preferences 灌一次。
let recent: number[] = [];
let persist: (value: string) => void = (): void => {};
const listeners: Set<() => void> = new Set<() => void>();

// 逗号分隔的 id 串 ↔ 数组。preferences 只收基本类型，与 AppSettings 里
// chatIdList 同一套路。坏数据（非数字、0）直接丢，不让它污染名单。
export function parseRecentOutgoing(raw: string): number[] {
  if (raw === '') {
    return [];
  }
  const out: number[] = [];
  const parts: string[] = raw.split(',');
  for (let i = 0; i < parts.length && out.length < RECENT_OUTGOING_CAP; i++) {
    const id: number = Number.parseInt(parts[i], 10);
    if (!Number.isNaN(id) && id !== 0 && out.indexOf(id) < 0) {
      out.push(id);
    }
  }
  return out;
}

export function serializeRecentOutgoing(list: number[]): string {
  return list.join(',');
}

// 由 AppSettings 初始化完成后调用一次：把存下来的名单灌进来，并交出写回的钩子。
// 传函数而不是直接 import setString，是为了不让这个叶子模块反过来依赖 store。
export function initRecentOutgoing(raw: string, save: (value: string) => void): void {
  recent = parseRecentOutgoing(raw);
  persist = save;
  notify();
}

export function recentOutgoingChats(): number[] {
  return recent;
}

export function onRecentOutgoingChanged(listener: () => void): () => void {
  listeners.add(listener);
  return (): void => {
    listeners.delete(listener);
  };
}

function notify(): void {
  listeners.forEach((listener: () => void): void => listener());
}

// 用户在某个会话里主动发了东西。由 MessageStore 的各个发送出口调用。
// 顺序没变（已经在第一位）就什么都不做——发一条消息刷一次盘是浪费。
export function noteOutgoingChat(chatId: number): void {
  if (chatId === 0 || (recent.length > 0 && recent[0] === chatId)) {
    return;
  }
  recent = pushRecentOutgoing(recent, chatId);
  persist(serializeRecentOutgoing(recent));
  notify();
}

// 退出登录/切账号：名单是上一个账号的会话 id，留着会串号。
export function clearRecentOutgoing(): void {
  if (recent.length === 0) {
    return;
  }
  recent = [];
  persist('');
  notify();
}
