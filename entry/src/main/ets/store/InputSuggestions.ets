import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from '../util/log';

// Data sources for the chat input's '@' mention and '/' command suggestion
// panels. Pure request helpers — no state; ChatPage owns filtering/UI.

export interface MentionItem {
  userId: number;
  name: string;     // display name (first + last)
  username: string; // '' when the member has no public username
  // 小头像的文件 id（0 = 没有头像，或还不知道）。@ 弹窗拿它去取真头像
  // （issue #211：原来那里写死 avatarPath: ''，永远只画首字母）。
  avatarFileId: number;
}

// user.profile_photo.small.id。**只在这里解一次**：调用方拿到的就是 file id，
// 不必各自再走一遍 TdObject 的取值链。
function smallPhotoFileId(user: TdObject): number {
  const photo = user['profile_photo'] as TdObject | undefined;
  if (photo === undefined) {
    return 0;
  }
  const small = photo['small'] as TdObject | undefined;
  if (small === undefined) {
    return 0;
  }
  return (small['id'] as number | undefined) ?? 0;
}

export interface CommandItem {
  command: string;     // without the leading '/'
  description: string;
  botUserId: number;   // 0 only for malformed/legacy data
  botUsername: string; // group commands send as /command@bot; private chat keeps this empty
}

const MENTION_LIMIT: number = 12;

function displayNameOf(user: TdObject): string {
  const first = (user['first_name'] as string | undefined) ?? '';
  const last = (user['last_name'] as string | undefined) ?? '';
  return `${first} ${last}`.trim();
}

function usernameOf(user: TdObject): string {
  const u = user['usernames'] as TdObject | undefined;
  if (u === undefined) {
    return '';
  }
  const editable = (u['editable_username'] as string | undefined) ?? '';
  if (editable !== '') {
    return editable;
  }
  const active = u['active_usernames'] as string[] | undefined;
  return active !== undefined && active.length > 0 ? active[0] : '';
}

function memberUserIds(res: TdObject): number[] {
  const members = res['members'] as TdObject[] | undefined;
  const ids: number[] = [];
  if (members === undefined) {
    return ids;
  }
  for (const m of members) {
    const sender = m['member_id'] as TdObject | undefined;
    if (sender === undefined || (sender['@type'] as string | undefined) !== 'messageSenderUser') {
      continue;
    }
    const uid = (sender['user_id'] as number | undefined) ?? 0;
    if (uid > 0) {
      ids.push(uid);
    }
  }
  return ids;
}

function getUser(client: TdClient, userId: number): Promise<TdObject> {
  const req: TdRequest = { '@type': 'getUser' };
  req['user_id'] = userId;
  return client.send(req);
}

// Group members matching `query` (server-side prefix search on name/username).
export function searchMentions(client: TdClient, chatId: number, query: string): Promise<MentionItem[]> {
  const req: TdRequest = { '@type': 'searchChatMembers' };
  req['chat_id'] = chatId;
  req['query'] = query;
  req['limit'] = MENTION_LIMIT;
  return client.send(req).then((res: TdObject) => {
    const ids = memberUserIds(res);
    const fetches: Array<Promise<TdObject>> = ids.map((uid: number) => getUser(client, uid));
    return Promise.all(fetches).then((users: TdObject[]) => {
      const items: MentionItem[] = [];
      for (let i = 0; i < users.length; i++) {
        const name = displayNameOf(users[i]);
        const t = users[i]['type'] as TdObject | undefined;
        const typeName = t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '';
        if (name === '' || typeName === 'userTypeDeleted') {
          continue;
        }
        items.push({
          userId: ids[i], name, username: usernameOf(users[i]),
          avatarFileId: smallPhotoFileId(users[i])
        });
      }
      return items;
    });
  }).catch((e: TdError) => {
    logE(`searchMentions failed: ${e.message}`);
    const empty: MentionItem[] = [];
    return empty;
  });
}

// One member by id, for mentioning straight from a message avatar (the
// message entry carries the sender's name but not their username).
export function mentionOfUser(client: TdClient, userId: number): Promise<MentionItem> {
  return getUser(client, userId).then((user: TdObject): MentionItem => {
    return {
      userId, name: displayNameOf(user), username: usernameOf(user),
      avatarFileId: smallPhotoFileId(user)
    };
  }).catch((e: TdError): MentionItem => {
    logE(`mentionOfUser failed: ${e.message}`);
    return { userId, name: '', username: '', avatarFileId: 0 };
  });
}

export interface CommandTarget {
  updateType: string;
  idField: string;
  infoField: string;
  id: number;
  privateChat: boolean;
}

function commandRows(commands: TdObject[], botUserId: number, botUsername: string): CommandItem[] {
  const seen: Set<string> = new Set<string>();
  const items: CommandItem[] = [];
  for (const c of commands) {
    const command = (c['command'] as string | undefined) ?? '';
    if (!/^[a-zA-Z0-9_]{1,32}$/.test(command) || seen.has(command)) { continue; }
    seen.add(command);
    items.push({ command, description: (c['description'] as string | undefined) ?? '', botUserId, botUsername });
  }
  return items;
}

// Only commands declared for this chat; a bot's private menu can differ from its group menu.
export async function commandsFromInfo(client: TdClient, target: CommandTarget, full: TdObject): Promise<CommandItem[]> {
  if (target.privateChat) {
    const info = full['bot_info'] as TdObject | undefined;
    return commandRows((info?.['commands'] as TdObject[] | undefined) ?? [], target.id, '');
  }
  const groups = (full['bot_commands'] as TdObject[] | undefined) ?? [];
  const items: CommandItem[] = [];
  const seen: Set<number> = new Set<number>();
  // Small bounded batches avoid flooding TDLib when a group has many bots.
  for (let i = 0; i < groups.length; i += 8) {
    const batch = groups.slice(i, i + 8);
    const lists = await Promise.all(batch.map(async (group: TdObject): Promise<CommandItem[]> => {
      const id = (group['bot_user_id'] as number | undefined) ?? 0;
      if (id <= 0 || seen.has(id)) { return []; }
      seen.add(id);
      const commands = (group['commands'] as TdObject[] | undefined) ?? [];
      if (commands.length === 0) { return []; }
      const user = await getUser(client, id);
      const username = usernameOf(user);
      // A group command without its bot address could target the wrong bot.
      return username === '' ? [] : commandRows(commands, id, username);
    }));
    for (const list of lists) { items.push(...list); }
  }
  return items;
}

export async function loadBotCommands(client: TdClient, chatId: number, peerUserId: number,
  onTarget: (target: CommandTarget) => void = (): void => {}): Promise<CommandItem[]> {
  let peer = peerUserId;
  let type: TdObject = { '@type': 'chatTypePrivate' };
  if (peer <= 0) {
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = chatId;
    const chat = await client.send(req);
    type = (chat['type'] as TdObject | undefined) ?? { '@type': '' };
    if (type['@type'] === 'chatTypePrivate') { peer = (type['user_id'] as number | undefined) ?? 0; }
  }
  let target: CommandTarget;
  let method: string;
  if (peer > 0) {
    target = { updateType: 'updateUserFullInfo', idField: 'user_id', infoField: 'user_full_info', id: peer, privateChat: true };
    method = 'getUserFullInfo';
  } else if (type['@type'] === 'chatTypeBasicGroup') {
    target = { updateType: 'updateBasicGroupFullInfo', idField: 'basic_group_id', infoField: 'basic_group_full_info',
      id: (type['basic_group_id'] as number | undefined) ?? 0, privateChat: false };
    method = 'getBasicGroupFullInfo';
  } else if (type['@type'] === 'chatTypeSupergroup' && type['is_channel'] !== true) {
    target = { updateType: 'updateSupergroupFullInfo', idField: 'supergroup_id', infoField: 'supergroup_full_info',
      id: (type['supergroup_id'] as number | undefined) ?? 0, privateChat: false };
    method = 'getSupergroupFullInfo';
  } else { return []; }
  if (target.id <= 0) { return []; }
  onTarget(target);
  const req: TdRequest = { '@type': method };
  req[target.idField] = target.id;
  return commandsFromInfo(client, target, await client.send(req));
}
