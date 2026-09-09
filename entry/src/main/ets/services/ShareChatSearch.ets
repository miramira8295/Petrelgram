import { getChatStore, getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { ChatEntry, computeInitials } from '../store/ChatEntry';
import { listKeyOf } from '../store/ListKey';
import { ShareRow, localRows, mergeRows, unknownIds } from '../util/shareSearch';
import { logE } from '../util/log';

// 「分享到…」搜会话的取数。合并规则在 util/shareSearch（纯函数、有单测），
// 这里只负责发请求。
//
// 【为什么不能只搜界面上那份列表】原来选择器过滤的是 getChats('main')，
// 而 ChatStore 把会话按列表分桶存：**归档会话在 'archive' 桶里，压根不在
// 'main' 里**——归档的人永远搜不到（用户实测）。另外 'main' 本身是翻页
// 加载的，排在后面的群还没进内存，同样搜不到。
//
// 所以候选集改成两层，界面先出快的：
//   1. ChatStore.allEntries()——本机已知的**全部**会话，不分桶、不受翻页影响；
//   2. searchChats——TDLib 的本地索引，覆盖本机知道但还没建成 entry 的。
//
// 【候选集还要再筛一道】用户定的规则：**在任何文件夹里的都该搜得到，只躺在
// 归档里、不属于任何文件夹的不该出现**。判据是 ChatStore.inNonArchiveList，
// 不能写成 `!isArchived()`——文件夹可以收录归档会话，那样会把"归档 + 在文件夹
// 里"的一起否掉。
//
// 也因此**不查 searchChatsOnServer**：它返回的是连本机都不认识的陌生人，
// 而分享的目标只可能是已有的会话。

// 每层各取多少。列表再长用户也不会翻，取多了只是白解析。
const PER_SOURCE_LIMIT: number = 50;
const RESULT_LIMIT: number = 60;
// 远端查详情的并发上限。一次几十个 getChat 会把请求队列堵住，而用户只看得见
// 前十几行。
const MAX_DETAIL_LOOKUPS: number = 20;

// 第 1 层。同步，输入的每一下都能立刻出结果。
export function localShareRows(query: string): ShareRow[] {
  const store = getChatStore();
  return localRows(store.allEntries(), query, PER_SOURCE_LIMIT,
    (chatId: number): boolean => store.inNonArchiveList(chatId));
}

function searchChatIds(query: string, type: string): Promise<number[]> {
  const request: TdRequest = { '@type': type };
  request['query'] = query;
  request['limit'] = PER_SOURCE_LIMIT;
  return getTdClient().send(request, 12000).then((result: TdObject): number[] =>
    ((result['chat_ids'] as number[] | undefined) ?? []).slice()
  ).catch((): number[] => []);
}

// 这个 chat 至少在一个非归档列表里吗。ChatStore 还不认识它，所以只能读
// chat 自己带的 positions（和 ChatStore.inNonArchiveList 同一条规则）。
function chatInNonArchiveList(chat: TdObject): boolean {
  const positions = (chat['positions'] as TdObject[] | undefined) ?? [];
  for (let i = 0; i < positions.length; i++) {
    const list = positions[i]['list'] as TdObject | undefined;
    if (list !== undefined && listKeyOf(list) !== 'archive' && listKeyOf(list) !== '') {
      return true;
    }
  }
  return false;
}

// 裸 chat 对象 → 展示行。本机没有 entry 时只能从 chat 上取，副标题就空着。
function rowFromChat(chat: TdObject): ShareRow | null {
  const id: number = (chat['id'] as number | undefined) ?? 0;
  if (id === 0 || !chatInNonArchiveList(chat)) {
    return null;
  }
  const title: string = (chat['title'] as string | undefined) ?? '';
  const photo = chat['photo'] as TdObject | undefined;
  const small = photo?.['small'] as TdObject | undefined;
  const local = small?.['local'] as TdObject | undefined;
  return {
    chatId: id,
    title: title,
    subtitle: '',
    avatarPath: (local?.['path'] as string | undefined) ?? '',
    initials: computeInitials(title),
    // 远端补回来的行不判收藏：搜索结果里出现自己那条的概率极低，
    // 而判它要额外查一次自己的 user id。
    isSavedMessages: false
  };
}

function detailOf(chatId: number): Promise<ShareRow | null> {
  const cached: ChatEntry | undefined = getChatStore().entryOf(chatId);
  if (cached !== undefined) {
    if (!getChatStore().inNonArchiveList(chatId)) {
      return Promise.resolve(null);
    }
    const row: ShareRow = {
      chatId: cached.id, title: cached.title, subtitle: cached.lastMessageText,
      avatarPath: cached.avatarPath, initials: cached.initials,
      isSavedMessages: cached.isSavedMessages
    };
    return Promise.resolve(row);
  }
  const request: TdRequest = { '@type': 'getChat' };
  request['chat_id'] = chatId;
  return getTdClient().send(request)
    .then((chat: TdObject): ShareRow | null => rowFromChat(chat))
    .catch((): ShareRow | null => null);
}

// 第 2 层，合并进第 1 层的结果。整条链任何一段失败都退回本机结果，
// 不让一次网络抖动把搜索变成空白。
export function searchShareRows(query: string): Promise<ShareRow[]> {
  const trimmed: string = query.trim();
  const local: ShareRow[] = localShareRows(trimmed);
  if (trimmed === '') {
    return Promise.resolve(local);
  }
  return searchChatIds(trimmed, 'searchChats')
    .then((flat: number[]): Promise<(ShareRow | null)[]> => {
    const known: Set<number> = new Set<number>(
      local.map((row: ShareRow): number => row.chatId));
    const missing: number[] = unknownIds(flat, (id: number): boolean => known.has(id))
      .slice(0, MAX_DETAIL_LOOKUPS);
    return Promise.all(missing.map(detailOf));
  }).then((rows: (ShareRow | null)[]): ShareRow[] => {
    const remote: ShareRow[] = [];
    for (let i = 0; i < rows.length; i++) {
      const row: ShareRow | null = rows[i];
      if (row !== null && row.title !== '') {
        remote.push(row);
      }
    }
    return mergeRows(local, remote, RESULT_LIMIT);
  }).catch((e: Object): ShareRow[] => {
    logE(`searchShareRows failed: ${e}`);
    return local;
  });
}
