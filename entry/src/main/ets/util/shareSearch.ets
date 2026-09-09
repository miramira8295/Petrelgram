import { ChatEntry } from '../store/ChatEntry';

// 「分享到…」里搜会话的取数与合并。纯函数，无 IO。
//
// 【为什么不能只过滤界面上那份列表】选择器原来是拿 `getChats('main')` 的结果
// 做 `title.indexOf(q)`，而那是**翻页加载出来的一段**——会话多的账号里，
// 排在几百位之后的群根本还没进内存，搜索就"搜不到"。这不是匹配规则的问题，
// 是候选集本来就不全。
//
// 正确的候选集有两层：
//   1. 本机已知的全部会话（ChatStore.allEntries，不分桶、不受翻页影响）——立刻可得；
//   2. TDLib 的本地索引 searchChats——本机知道但还没建成 entry 的。
// 界面先出第 1 层，第 2 层回来再补，避免输入时的空窗。
//
// 【但候选集要再筛一道】用户定的规则：**在任何文件夹里的都该搜得到，
// 只躺在归档里、不属于任何文件夹的不该出现**。所以每一层都过
// `eligible` 这道闸（实现是 ChatStore.inNonArchiveList）。
// 也因此**不查 searchChatsOnServer**——那返回的是连本机都不认识的陌生人，
// 分享的目标只可能是已有的会话。

export interface ShareRow {
  chatId: number;
  title: string;
  // 副标题：本机有 entry 时是最后一条消息，远端补回来的就是空串。
  subtitle: string;
  avatarPath: string;
  initials: string;
  // 「我的收藏」。TDLib 对它没有任何特殊标记——标题就是自己的昵称、头像就是
  // 自己的头像，换成"我的收藏"是渲染层的活（见 store/ChatEntry 的说明）。
  isSavedMessages: boolean;
}

export function rowFromEntry(entry: ChatEntry): ShareRow {
  return {
    chatId: entry.id,
    title: entry.title,
    subtitle: entry.lastMessageText,
    avatarPath: entry.avatarPath,
    initials: entry.initials,
    isSavedMessages: entry.isSavedMessages
  };
}

// 标题匹配。大小写不敏感；空查询返回全部（调用方自己决定要不要用）。
export function matchesQuery(title: string, query: string): boolean {
  const q: string = query.trim().toLowerCase();
  return q === '' || title.toLowerCase().indexOf(q) >= 0;
}

// 第 1 层：本机全部会话里按标题过滤，按最后消息时间从新到旧。
// 不改入参——先复制再排。
//
// `eligible` 是候选集的闸：默认全放行，真实调用传的是
// `ChatStore.inNonArchiveList`（见文件头）。做成参数是为了能单测。
export function localRows(entries: ChatEntry[], query: string, limit: number,
  eligible: (chatId: number) => boolean = (): boolean => true): ShareRow[] {
  const hits: ChatEntry[] = entries.filter((entry: ChatEntry): boolean =>
    entry.id !== 0 && eligible(entry.id) && matchesQuery(entry.title, query));
  hits.sort((a: ChatEntry, b: ChatEntry): number => b.lastMessageDate - a.lastMessageDate);
  return hits.slice(0, limit).map(rowFromEntry);
}

// 合并。本机的排前面（有副标题、有头像，信息更全），远端补在后面，去重。
export function mergeRows(local: ShareRow[], remote: ShareRow[], limit: number): ShareRow[] {
  const out: ShareRow[] = [];
  const seen: Set<number> = new Set<number>();
  const take = (row: ShareRow): void => {
    if (row.chatId === 0 || seen.has(row.chatId) || out.length >= limit) {
      return;
    }
    seen.add(row.chatId);
    out.push(row);
  };
  for (let i = 0; i < local.length; i++) {
    take(local[i]);
  }
  for (let i = 0; i < remote.length; i++) {
    take(remote[i]);
  }
  return out;
}

// 远端结果里真正需要再去查一次详情的 id：本机已经有 entry 的不必查。
// 顺序保持服务器给的相关性顺序。
export function unknownIds(ids: number[], known: (chatId: number) => boolean): number[] {
  const out: number[] = [];
  for (let i = 0; i < ids.length; i++) {
    const id: number = ids[i];
    if (id !== 0 && !known(id) && out.indexOf(id) < 0) {
      out.push(id);
    }
  }
  return out;
}

// 「我的收藏」提到最前。
//
// 主列表是 TDLib 按最后消息时间排的，收藏经常沉在很后面；而它是分享最高频的
// 去处（"存一下"），用户明确要求置顶。只挪位置，不复制——它在列表里仍然只有
// 一份。不改入参。
export function pinSavedFirst(rows: ShareRow[]): ShareRow[] {
  const at: number = rows.findIndex((row: ShareRow): boolean => row.isSavedMessages);
  if (at <= 0) {
    return rows;
  }
  const out: ShareRow[] = [rows[at]];
  for (let i = 0; i < rows.length; i++) {
    if (i !== at) {
      out.push(rows[i]);
    }
  }
  return out;
}
