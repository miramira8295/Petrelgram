import { TdObject, TdRequest } from '../tdkit/TdTypes';

// Keep existing search category IDs stable for remembered sessions.
export const SEARCH_TAB_RECENT: number = -1;
export function searchTabForQuery(query: string, currentTab: number): number {
  if (query.trim() === '') { return SEARCH_TAB_RECENT; }
  return currentTab === SEARCH_TAB_RECENT ? 0 : currentTab;
}

export const SEARCH_PAGE_NONE: string = 'none';
export const SEARCH_PAGE_EMPTY: string = 'empty';
export const SEARCH_PAGE_FETCH: string = 'fetch';
export const SEARCH_PAGE_MORE: string = 'more';
export interface EmptySearchPageState {
  searched: boolean;
  busy: boolean;
  failed: boolean;
  resolving: boolean;
  visibleCount: number;
  nextOffset: string;
  automaticPages: number;
}
// An empty page is not the end while TDLib still supplies a continuation cursor.
export function emptySearchPageAction(state: EmptySearchPageState, automaticLimit: number): string {
  if (!state.searched || state.busy || state.failed || state.resolving || state.visibleCount > 0) {
    return SEARCH_PAGE_NONE;
  }
  if (state.nextOffset === '') { return SEARCH_PAGE_EMPTY; }
  return state.automaticPages < automaticLimit ? SEARCH_PAGE_FETCH : SEARCH_PAGE_MORE;
}

export interface SearchSegment { text: string; hit: boolean; }
export interface SearchIdentity {
  kind: string;
  isBot?: boolean;
  usernames: string[];
  existing: boolean;
  joined?: boolean;
}
export interface MessageMatch { body: string; fileName: string; }

// Literal, case-insensitive highlighting; no regular-expression interpretation of input.
export function searchSegments(text: string | undefined | null, query: string | undefined | null): SearchSegment[] {
  const content = text ?? '';
  const needle = (query ?? '').trim().toLowerCase();
  if (needle === '') { return [{ text: content, hit: false }]; }
  const haystack = content.toLowerCase();
  // Some Unicode lowercasing expands characters, invalidating UTF-16 offsets.
  if (haystack.length !== content.length) { return [{ text: content, hit: false }]; }
  const result: SearchSegment[] = [];
  let from = 0;
  let at = haystack.indexOf(needle);
  while (at >= 0) {
    if (at > from) { result.push({ text: content.slice(from, at), hit: false }); }
    result.push({ text: content.slice(at, at + needle.length), hit: true });
    from = at + needle.length; at = haystack.indexOf(needle, from);
  }
  if (from < content.length) { result.push({ text: content.slice(from), hit: false }); }
  return result;
}
export function searchHit(text: string | undefined | null, query: string | undefined | null): boolean {
  return searchSegments(text, query).some((part: SearchSegment): boolean => part.hit);
}
export function searchExcerpt(text: string | undefined | null, query: string | undefined | null): string {
  const content = text ?? '';
  const at = content.toLowerCase().indexOf((query ?? '').trim().toLowerCase());
  const start = at > 45 ? at - 30 : 0;
  return (start > 0 ? '…' : '') + content.slice(start, start + 220) + (content.length > start + 220 ? '…' : '');
}
export function activeSearchUsernames(object: TdObject): string[] {
  const usernames = object['usernames'] as TdObject | undefined;
  const active = (usernames?.['active_usernames'] as string[] | undefined) ?? [];
  const legacy = (object['username'] as string | undefined) ?? '';
  return active.length > 0 ? active : (legacy === '' ? [] : [legacy]);
}
export function messageMatch(message: TdObject): MessageMatch {
  const content = message['content'] as TdObject | undefined;
  if (content === undefined) { return { body: '', fileName: '' }; }
  const text = (content['text'] ?? content['caption']) as TdObject | undefined;
  const media = (content['document'] ?? content['audio'] ?? content['video'] ?? content['animation']) as TdObject | undefined;
  return { body: (text?.['text'] as string | undefined) ?? '', fileName: (media?.['file_name'] as string | undefined) ?? '' };
}
export function messageScopeRequest(query: string, scope: string, channelId: number, offset: string): TdRequest {
  const request: TdRequest = { '@type': channelId !== 0 ? 'searchChatMessages' : 'searchMessages' };
  request['query'] = query; request['limit'] = 30;
  if (channelId !== 0) {
    request['chat_id'] = channelId; request['from_message_id'] = offset === '' ? 0 : Number(offset);
    request['offset'] = 0;
  } else {
    request['offset'] = offset;
    if (scope !== 'all') {
      const type: TdObject = { '@type': scope === 'user' ? 'searchMessagesChatTypeFilterPrivate' :
        (scope === 'group' ? 'searchMessagesChatTypeFilterGroup' : 'searchMessagesChatTypeFilterChannel') };
      request['chat_type_filter'] = type;
    }
  }
  return request;
}
export function channelSearchCursor(result: TdObject, previous: string): string {
  const explicit = result['next_from_message_id'] as number | undefined;
  const rows = (result['messages'] as TdObject[] | undefined) ?? [];
  const next = explicit !== undefined ? explicit : (rows.length > 0 ? rows[rows.length - 1]['id'] as number : 0);
  return !next || String(next) === previous ? '' : String(next);
}
