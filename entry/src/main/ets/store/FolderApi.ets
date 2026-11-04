import { getChatStore, getFolderStore, getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { ChatEntry, chatKindOf, computeInitials } from './ChatEntry';

// Folder mutations replace the complete TDLib chatFolder object. Serialize all
// writers (settings, row menus and invite management) so a stale read can't
// silently overwrite a change that completed a moment earlier.
let mutationTail: Promise<void> = Promise.resolve();

export function serializeFolderMutation<T>(operation: () => Promise<T>): Promise<T> {
  const result: Promise<T> = mutationTail.then(operation, operation);
  mutationTail = result.then((): void => {}, (): void => {});
  return result;
}

export interface FolderData {
  id: number;
  name: string;
  nameEntities: TdObject[];
  animateCustomEmoji: boolean;
  iconName: string;
  colorId: number;
  isShareable: boolean;
  pinnedChatIds: number[];
  includedChatIds: number[];
  excludedChatIds: number[];
  excludeMuted: boolean;
  excludeRead: boolean;
  excludeArchived: boolean;
  includeContacts: boolean;
  includeNonContacts: boolean;
  includeBots: boolean;
  includeGroups: boolean;
  includeChannels: boolean;
}

export interface RecommendedFolder {
  folder: FolderData;
  description: string;
}

// 选会话面板最多展示多少候选（防爆上限，不是业务限制）。
const FOLDER_PICKER_MAX_ROWS: number = 2000;

export interface FolderLimits {
  folderCount: number;
  chosenChatCount: number;
}

export interface FolderChatSummary {
  id: number;
  title: string;
  initials: string;
  avatarPath: string;
  kind: string;
}

export interface FolderInviteLinkData {
  inviteLink: string;
  name: string;
  chatIds: number[];
}

export function emptyFolder(): FolderData {
  return {
    id: 0, name: '', nameEntities: [], animateCustomEmoji: false,
    iconName: '', colorId: -1, isShareable: false,
    pinnedChatIds: [], includedChatIds: [], excludedChatIds: [],
    excludeMuted: false, excludeRead: false, excludeArchived: false,
    includeContacts: false, includeNonContacts: false, includeBots: false,
    includeGroups: false, includeChannels: false
  };
}

function nameParts(folder: TdObject): [string, TdObject[], boolean] {
  const name = folder['name'] as TdObject | undefined;
  const text = name?.['text'] as TdObject | undefined;
  const value = text !== undefined ? ((text['text'] as string | undefined) ?? '') : '';
  const entities = text !== undefined ? ((text['entities'] as TdObject[] | undefined) ?? []) : [];
  const animated = name !== undefined ? ((name['animate_custom_emoji'] as boolean | undefined) ?? false) : false;
  return [value, entities, animated];
}

export function folderDataFromTd(folder: TdObject, id: number = 0): FolderData {
  const name = nameParts(folder);
  const icon = folder['icon'] as TdObject | undefined;
  return {
    id,
    name: name[0],
    nameEntities: name[1].slice(),
    animateCustomEmoji: name[2],
    iconName: icon !== undefined ? ((icon['name'] as string | undefined) ?? '') : '',
    colorId: (folder['color_id'] as number | undefined) ?? -1,
    isShareable: (folder['is_shareable'] as boolean | undefined) ?? false,
    pinnedChatIds: ((folder['pinned_chat_ids'] as number[] | undefined) ?? []).slice(),
    includedChatIds: ((folder['included_chat_ids'] as number[] | undefined) ?? []).slice(),
    excludedChatIds: ((folder['excluded_chat_ids'] as number[] | undefined) ?? []).slice(),
    excludeMuted: (folder['exclude_muted'] as boolean | undefined) ?? false,
    excludeRead: (folder['exclude_read'] as boolean | undefined) ?? false,
    excludeArchived: (folder['exclude_archived'] as boolean | undefined) ?? false,
    includeContacts: (folder['include_contacts'] as boolean | undefined) ?? false,
    includeNonContacts: (folder['include_non_contacts'] as boolean | undefined) ?? false,
    includeBots: (folder['include_bots'] as boolean | undefined) ?? false,
    includeGroups: (folder['include_groups'] as boolean | undefined) ?? false,
    includeChannels: (folder['include_channels'] as boolean | undefined) ?? false
  };
}

export function toTdFolder(folder: FolderData): TdObject {
  const text: TdObject = { '@type': 'formattedText' };
  text['text'] = folder.name;
  text['entities'] = folder.nameEntities;
  const name: TdObject = { '@type': 'chatFolderName' };
  name['text'] = text;
  name['animate_custom_emoji'] = folder.animateCustomEmoji;
  const out: TdObject = { '@type': 'chatFolder' };
  out['name'] = name;
  if (folder.iconName !== '') {
    out['icon'] = { '@type': 'chatFolderIcon', 'name': folder.iconName } as TdObject;
  }
  out['color_id'] = folder.colorId;
  out['is_shareable'] = folder.isShareable;
  out['pinned_chat_ids'] = folder.pinnedChatIds;
  out['included_chat_ids'] = folder.includedChatIds;
  out['excluded_chat_ids'] = folder.excludedChatIds;
  out['exclude_muted'] = folder.excludeMuted;
  out['exclude_read'] = folder.excludeRead;
  out['exclude_archived'] = folder.excludeArchived;
  out['include_contacts'] = folder.includeContacts;
  out['include_non_contacts'] = folder.includeNonContacts;
  out['include_bots'] = folder.includeBots;
  out['include_groups'] = folder.includeGroups;
  out['include_channels'] = folder.includeChannels;
  return out;
}

export async function getFolder(id: number): Promise<FolderData> {
  const request: TdRequest = { '@type': 'getChatFolder' };
  request['chat_folder_id'] = id;
  return folderDataFromTd(await getTdClient().send(request), id);
}

async function performSave(folder: FolderData): Promise<number> {
  const request: TdRequest = { '@type': folder.id === 0 ? 'createChatFolder' : 'editChatFolder' };
  if (folder.id !== 0) { request['chat_folder_id'] = folder.id; }
  request['folder'] = toTdFolder(folder);
  const info = await getTdClient().send(request);
  getFolderStore().applyServerFolderInfo(info);
  return (info['id'] as number | undefined) ?? folder.id;
}

export function saveFolder(folder: FolderData): Promise<number> {
  return serializeFolderMutation((): Promise<number> => performSave(folder));
}

export function deleteFolder(id: number, leaveChatIds: number[] = []): Promise<void> {
  return serializeFolderMutation(async (): Promise<void> => {
    const request: TdRequest = { '@type': 'deleteChatFolder' };
    request['chat_folder_id'] = id;
    request['leave_chat_ids'] = leaveChatIds;
    await getTdClient().send(request);
    getFolderStore().removeFolder(id);
  });
}

export function reorderFolders(ids: number[], mainPosition: number = 0): Promise<void> {
  return serializeFolderMutation(async (): Promise<void> => {
    const request: TdRequest = { '@type': 'reorderChatFolders' };
    request['chat_folder_ids'] = ids;
    request['main_chat_list_position'] = mainPosition;
    await getTdClient().send(request);
    getFolderStore().applyLocalOrder(ids, mainPosition);
  });
}

export async function folderChatCount(folder: FolderData): Promise<number> {
  const request: TdRequest = { '@type': 'getChatFolderChatCount' };
  request['folder'] = toTdFolder(folder);
  const result = await getTdClient().send(request);
  return (result['count'] as number | undefined) ?? 0;
}

// optionValueInteger 的 value 是 int64，TDLib 在 JSON 里把它编码成**字符串**。
// 直接当 number 用会让 Number.isFinite 恒为 false，于是永远退回兜底值 ——
// 表现就是上限被写死成兜底的 10，从没真正读到过服务端的配额
// （Premium 账号本该是 20，却照样在第 10 个就被拦下）。
export function parseOptionInteger(raw: Object | undefined, fallback: number): number {
  if (typeof raw === 'number') {
    return Number.isFinite(raw) && raw > 0 ? raw : fallback;
  }
  if (typeof raw === 'string') {
    const parsed = Number(raw.trim());
    return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
  }
  return fallback;
}

async function optionInteger(name: string, fallback: number): Promise<number> {
  const request: TdRequest = { '@type': 'getOption' };
  request['name'] = name;
  try {
    const result = await getTdClient().send(request);
    return parseOptionInteger(result['value'], fallback);
  } catch (_error) {
    return fallback;
  }
}

export async function getFolderLimits(): Promise<FolderLimits> {
  const values: number[] = await Promise.all([
    optionInteger('chat_folder_count_max', 10),
    optionInteger('chat_folder_chosen_chat_count_max', 100)
  ]);
  return { folderCount: values[0], chosenChatCount: values[1] };
}

export async function getRecommendedFolders(): Promise<RecommendedFolder[]> {
  const result = await getTdClient().send({ '@type': 'getRecommendedChatFolders' } as TdRequest, 15000);
  const rows = (result['chat_folders'] as TdObject[] | undefined) ?? [];
  return rows.map((row: TdObject): RecommendedFolder => ({
    folder: folderDataFromTd((row['folder'] as TdObject | undefined) ?? emptyTdFolder()),
    description: (row['description'] as string | undefined) ?? ''
  }));
}

function emptyTdFolder(): TdObject {
  return toTdFolder(emptyFolder());
}

// 用户没有显式选图标时，Telegram 按筛选规则推导一个默认图标。这里照搬
// TDLib 的 DialogFilter::get_default_icon_name（DialogFilter.cpp:402），
// 这样列表里不会一整屏都是同一个通用文件夹方框。
// 做成纯函数而不是调 getChatFolderDefaultIconName：那是异步的，列表每行一次
// 往返既慢又难和渲染对齐。
export function derivedFolderIconName(folder: FolderData): string {
  if (folder.iconName !== '') {
    return folder.iconName;
  }
  if (folder.pinnedChatIds.length > 0 || folder.includedChatIds.length > 0 ||
    folder.excludedChatIds.length > 0) {
    return 'Custom';
  }
  if (folder.includeContacts || folder.includeNonContacts) {
    if (!folder.includeBots && !folder.includeGroups && !folder.includeChannels) {
      return 'Private';
    }
  } else {
    if (!folder.includeBots && !folder.includeChannels) {
      return folder.includeGroups ? 'Groups' : 'Custom';
    }
    if (!folder.includeBots && !folder.includeGroups) {
      return 'Channels';
    }
    if (!folder.includeGroups && !folder.includeChannels) {
      return 'Bots';
    }
  }
  if (folder.excludeRead && !folder.excludeMuted) {
    return 'Unread';
  }
  if (folder.excludeMuted && !folder.excludeRead) {
    return 'Unmuted';
  }
  return 'Custom';
}

export function setFolderTagsEnabled(enabled: boolean): Promise<void> {
  return serializeFolderMutation(async (): Promise<void> => {
    const request: TdRequest = { '@type': 'toggleChatFolderTags' };
    request['are_tags_enabled'] = enabled;
    await getTdClient().send(request);
    getFolderStore().applyTagsEnabled(enabled);
  });
}

export async function getFolderChatsToLeave(id: number): Promise<number[]> {
  const request: TdRequest = { '@type': 'getChatFolderChatsToLeave' };
  request['chat_folder_id'] = id;
  const result = await getTdClient().send(request);
  return ((result['chat_ids'] as number[] | undefined) ?? []).slice();
}

function summaryFromEntry(entry: ChatEntry): FolderChatSummary {
  return {
    id: entry.id, title: entry.title, initials: entry.initials,
    avatarPath: entry.avatarPath, kind: entry.kind
  };
}

// TDLib rejects createChatFolder/editChatFolder with "Chat is not in the chat
// list" for chats without a chat-list position (e.g. a public channel found by
// server search that the user never joined). Folder candidates must pass this.
export function chatIsInChatList(chat: TdObject): boolean {
  return ((chat['positions'] as TdObject[] | undefined) ?? []).length > 0;
}

// Chosen chat ids that TDLib would reject for a folder ("Chat is not in the
// chat list"): the chat has no chat-list position anymore, or can't be loaded.
export async function chatIdsNotInChatList(ids: number[]): Promise<number[]> {
  const checks: number[] = await Promise.all(ids.map(async (id: number): Promise<number> => {
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = id;
    try {
      const chat = await getTdClient().send(request);
      return chatIsInChatList(chat) ? 0 : id;
    } catch (_error) {
      return id;
    }
  }));
  return checks.filter((id: number): boolean => id !== 0);
}

function summaryFromChat(chat: TdObject): FolderChatSummary {
  const id = (chat['id'] as number | undefined) ?? 0;
  const title = (chat['title'] as string | undefined) ?? `${id}`;
  const photo = chat['photo'] as TdObject | undefined;
  const small = photo?.['small'] as TdObject | undefined;
  const local = small?.['local'] as TdObject | undefined;
  return {
    id, title, initials: computeInitials(title),
    avatarPath: (local?.['path'] as string | undefined) ?? '',
    kind: chatKindOf(chat['type'] as TdObject | undefined)
  };
}

export async function getFolderChatSummaries(ids: number[]): Promise<FolderChatSummary[]> {
  const unique: number[] = [];
  for (const id of ids) { if (id !== 0 && unique.indexOf(id) < 0) { unique.push(id); } }
  const requests: Promise<FolderChatSummary>[] = unique.map((id: number): Promise<FolderChatSummary> => {
    const cached = getChatStore().entryOf(id);
    if (cached !== undefined) { return Promise.resolve(summaryFromEntry(cached)); }
    const request: TdRequest = { '@type': 'getChat' };
    request['chat_id'] = id;
    return getTdClient().send(request).then((chat: TdObject): FolderChatSummary => summaryFromChat(chat))
      .catch((): FolderChatSummary => ({ id, title: `${id}`, initials: '?', avatarPath: '', kind: 'private' }));
  });
  return Promise.all(requests);
}

async function searchChatIds(query: string, type: string): Promise<number[]> {
  const request: TdRequest = { '@type': type };
  request['query'] = query;
  request['limit'] = 50;
  try {
    const result = await getTdClient().send(request, 12000);
    return ((result['chat_ids'] as number[] | undefined) ?? []).slice();
  } catch (_error) {
    return [];
  }
}

export async function searchFolderChats(query: string): Promise<FolderChatSummary[]> {
  const normalized = query.trim().toLowerCase();
  const summaries = new Map<number, FolderChatSummary>();
  for (const entry of getChatStore().allEntries()) {
    if (normalized === '' || entry.title.toLowerCase().includes(normalized)) {
      summaries.set(entry.id, summaryFromEntry(entry));
    }
  }
  if (normalized !== '') {
    const pages: number[][] = await Promise.all([
      searchChatIds(query.trim(), 'searchChats'), searchChatIds(query.trim(), 'searchChatsOnServer')
    ]);
    const missing: number[] = [];
    for (const page of pages) {
      for (const id of page) { if (!summaries.has(id) && missing.indexOf(id) < 0) { missing.push(id); } }
    }
    const remote = await Promise.all(missing.map((id: number): Promise<FolderChatSummary | null> => {
      const request: TdRequest = { '@type': 'getChat' };
      request['chat_id'] = id;
      return getTdClient().send(request)
        .then((chat: TdObject): FolderChatSummary | null =>
          chatIsInChatList(chat) ? summaryFromChat(chat) : null)
        .catch((): FolderChatSummary | null => null);
    }));
    for (const row of remote) { if (row !== null) { summaries.set(row.id, row); } }
  }
  // **不要截断到 100。**
  //
  // 选会话面板的数据源就是这个函数的返回值。原来 slice(0, 100) 让候选列表
  // 永远只有前 100 个会话，文件夹里加满 100 个之后，后面的群/频道在面板里
  // 根本不会出现（2026-11-04 用户报的「到一百就不能继续添加」）。而真正的
  // 上限是服务端给的 chat_folder_chosen_chat_count_max（当前账号读到 200），
  // 界面判据用的也是它，跟这里的 100 没有关系。
  //
  // 面板走 LazyForEach（FolderEditPage.pickerData），行是虚拟化的，放开不会
  // 增加首帧成本；这里只留一个防爆上限。
  return Array.from(summaries.values()).slice(0, FOLDER_PICKER_MAX_ROWS);
}

function inviteLinkFromTd(row: TdObject): FolderInviteLinkData {
  return {
    inviteLink: (row['invite_link'] as string | undefined) ?? '',
    name: (row['name'] as string | undefined) ?? '',
    chatIds: ((row['chat_ids'] as number[] | undefined) ?? []).slice()
  };
}

export async function getFolderInviteLinks(id: number): Promise<FolderInviteLinkData[]> {
  const request: TdRequest = { '@type': 'getChatFolderInviteLinks' };
  request['chat_folder_id'] = id;
  const result = await getTdClient().send(request, 15000);
  return ((result['invite_links'] as TdObject[] | undefined) ?? []).map(inviteLinkFromTd);
}

export async function getChatsForFolderInviteLink(id: number): Promise<number[]> {
  const request: TdRequest = { '@type': 'getChatsForChatFolderInviteLink' };
  request['chat_folder_id'] = id;
  const result = await getTdClient().send(request, 15000);
  return ((result['chat_ids'] as number[] | undefined) ?? []).slice();
}

export function createFolderInviteLink(id: number, name: string, chatIds: number[]): Promise<FolderInviteLinkData> {
  return serializeFolderMutation(async (): Promise<FolderInviteLinkData> => {
    const request: TdRequest = { '@type': 'createChatFolderInviteLink' };
    request['chat_folder_id'] = id;
    request['name'] = name;
    request['chat_ids'] = chatIds;
    return inviteLinkFromTd(await getTdClient().send(request, 20000));
  });
}

export function editFolderInviteLink(id: number, link: string, name: string,
  chatIds: number[]): Promise<FolderInviteLinkData> {
  return serializeFolderMutation(async (): Promise<FolderInviteLinkData> => {
    const request: TdRequest = { '@type': 'editChatFolderInviteLink' };
    request['chat_folder_id'] = id;
    request['invite_link'] = link;
    request['name'] = name;
    request['chat_ids'] = chatIds;
    return inviteLinkFromTd(await getTdClient().send(request, 20000));
  });
}

export function deleteFolderInviteLink(id: number, link: string): Promise<void> {
  return serializeFolderMutation(async (): Promise<void> => {
    const request: TdRequest = { '@type': 'deleteChatFolderInviteLink' };
    request['chat_folder_id'] = id;
    request['invite_link'] = link;
    await getTdClient().send(request, 20000);
  });
}

export async function getFolderNewChats(id: number): Promise<number[]> {
  const request: TdRequest = { '@type': 'getChatFolderNewChats' };
  request['chat_folder_id'] = id;
  const result = await getTdClient().send(request, 15000);
  return ((result['chat_ids'] as number[] | undefined) ?? []).slice();
}

export function processFolderNewChats(id: number, chatIds: number[]): Promise<void> {
  return serializeFolderMutation(async (): Promise<void> => {
    const request: TdRequest = { '@type': 'processChatFolderNewChats' };
    request['chat_folder_id'] = id;
    request['added_chat_ids'] = chatIds;
    await getTdClient().send(request, 20000);
  });
}
