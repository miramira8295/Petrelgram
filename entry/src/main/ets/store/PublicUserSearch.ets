import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { formatLastSeen } from '../util/formatLastSeen';
import { ContactItem } from './ContactsStore';
import { str } from '../util/strings';
import { logW } from '../util/log';

const SEARCH_REQUEST_TIMEOUT_MS: number = 4500;
const RESOLVE_REQUEST_TIMEOUT_MS: number = 3500;
const PUBLIC_SEARCH_BUDGET_MS: number = 8000;
const MAX_CANDIDATES: number = 24;

interface ChatSearchAttempt {
  ids: number[];
  success: boolean;
}

export interface PublicUserSearchResult {
  users: ContactItem[];
  state: string; // ready | empty | error | timeout
}

function chatIds(result: TdObject): number[] {
  return (result['chat_ids'] as number[] | undefined) ?? [];
}

async function runChatSearch(
  client: TdClient, type: string, query: string
): Promise<ChatSearchAttempt> {
  const request: TdRequest = { '@type': type };
  request['query'] = query;
  if (type === 'searchChatsOnServer') {
    request['limit'] = 30;
  }
  try {
    return { ids: chatIds(await client.send(request, SEARCH_REQUEST_TIMEOUT_MS)), success: true };
  } catch (error) {
    const caught = error as TdError;
    logW(`PublicUserSearch.${type} failed: ${caught.message}`);
    return { ids: [], success: false };
  }
}

function activeUsername(user: TdObject): string {
  const usernames = user['usernames'] as TdObject | undefined;
  const active = usernames !== undefined
    ? ((usernames['active_usernames'] as string[] | undefined) ?? [])
    : [];
  if (active.length > 0) {
    return active[0];
  }
  return (user['username'] as string | undefined) ?? '';
}

function avatarPath(user: TdObject, chat: TdObject): string {
  const profilePhoto = user['profile_photo'] as TdObject | undefined;
  const userSmall = profilePhoto !== undefined ? profilePhoto['small'] as TdObject | undefined : undefined;
  const userLocal = userSmall !== undefined ? userSmall['local'] as TdObject | undefined : undefined;
  const userPath = userLocal !== undefined ? ((userLocal['path'] as string | undefined) ?? '') : '';
  if (userPath !== '') {
    return userPath;
  }
  const chatPhoto = chat['photo'] as TdObject | undefined;
  const chatSmall = chatPhoto !== undefined ? chatPhoto['small'] as TdObject | undefined : undefined;
  const chatLocal = chatSmall !== undefined ? chatSmall['local'] as TdObject | undefined : undefined;
  return chatLocal !== undefined ? ((chatLocal['path'] as string | undefined) ?? '') : '';
}

async function resolvePrivateUser(client: TdClient, chatId: number): Promise<ContactItem | null> {
  try {
    const chatRequest: TdRequest = { '@type': 'getChat' };
    chatRequest['chat_id'] = chatId;
    const chat = await client.send(chatRequest, RESOLVE_REQUEST_TIMEOUT_MS);
    const type = chat['type'] as TdObject | undefined;
    if (type === undefined || type['@type'] !== 'chatTypePrivate') {
      return null;
    }
    const userId = (type['user_id'] as number | undefined) ?? 0;
    if (userId <= 0) {
      return null;
    }
    const userRequest: TdRequest = { '@type': 'getUser' };
    userRequest['user_id'] = userId;
    const user = await client.send(userRequest, RESOLVE_REQUEST_TIMEOUT_MS);
    const first = (user['first_name'] as string | undefined) ?? '';
    const last = (user['last_name'] as string | undefined) ?? '';
    const name = `${first}${last !== '' ? ` ${last}` : ''}`.trim();
    const username = activeUsername(user);
    const status = user['status'] as TdObject | undefined;
    const online = status !== undefined && status['@type'] === 'userStatusOnline';
    const statusText = username !== ''
      ? `@${username}`
      : formatLastSeen(status, Math.floor(Date.now() / 1000));
    return {
      id: userId,
      name: name !== '' ? name : (username !== '' ? username : str('bu_untitled_user')),
      initials: name !== '' ? name.substring(0, 1).toUpperCase() : '?',
      avatarPath: avatarPath(user, chat),
      statusText: statusText,
      online: online,
      sortKey: online ? Number.MAX_SAFE_INTEGER : 0
    };
  } catch (error) {
    const caught = error as TdError;
    logW(`PublicUserSearch.resolvePrivateUser(${chatId}) failed: ${caught.message}`);
    return null;
  }
}

function withinBudget<T>(work: Promise<T>, timeoutMs: number, fallback: T): Promise<T> {
  return new Promise<T>((resolve): void => {
    let settled = false;
    const timerId = setTimeout((): void => {
      if (settled) {
        return;
      }
      settled = true;
      logW(`PublicUserSearch exceeded ${timeoutMs}ms budget`);
      resolve(fallback);
    }, timeoutMs);
    work.then((value: T): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timerId);
      resolve(value);
    }).catch((error: Object): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timerId);
      logW(`PublicUserSearch failed: ${JSON.stringify(error)}`);
      resolve(fallback);
    });
  });
}

async function runPublicUserSearch(
  client: TdClient, query: string
): Promise<PublicUserSearchResult> {
  // Both TDLib searches are independent. Running them together avoids waiting
  // for two full request timeouts when the network is unavailable.
  const searchResults = await Promise.all([
    runChatSearch(client, 'searchPublicChats', query),
    runChatSearch(client, 'searchChatsOnServer', query)
  ]);
  const publicIds = searchResults[0].ids;
  const serverIds = searchResults[1].ids;
  if (!searchResults[0].success && !searchResults[1].success) {
    return { users: [], state: 'error' };
  }
  const ids: number[] = [];
  for (const id of [...publicIds, ...serverIds]) {
    if (ids.indexOf(id) < 0) {
      ids.push(id);
    }
  }

  // Candidate chats are independent too. The previous serial loop could take
  // minutes (getChat + getUser per candidate, each with a 15s timeout).
  const candidates = ids.slice(0, MAX_CANDIDATES);
  const resolved = await Promise.all(
    candidates.map((id: number): Promise<ContactItem | null> => resolvePrivateUser(client, id))
  );
  const users: ContactItem[] = [];
  for (const user of resolved) {
    if (user !== null && !users.some((item: ContactItem): boolean => item.id === user.id)) {
      users.push(user);
    }
  }
  return { users, state: users.length > 0 ? 'ready' : 'empty' };
}

// Telegram can only discover strangers who have a public username/searchable
// chat. Combine public search with server-side chat search, then keep private
// user chats and expose them in the same shape as the local contact list.
export function searchPublicUsers(client: TdClient, rawQuery: string): Promise<ContactItem[]> {
  return searchPublicUsersDetailed(client, rawQuery).then(
    (result: PublicUserSearchResult): ContactItem[] => result.users
  );
}

export function searchPublicUsersDetailed(
  client: TdClient, rawQuery: string
): Promise<PublicUserSearchResult> {
  const query = rawQuery.trim().replace(/^@/, '');
  if (query.length < 2) {
    return Promise.resolve({ users: [], state: 'empty' } as PublicUserSearchResult);
  }
  return withinBudget(
    runPublicUserSearch(client, query), PUBLIC_SEARCH_BUDGET_MS,
    { users: [], state: 'timeout' } as PublicUserSearchResult
  );
}
