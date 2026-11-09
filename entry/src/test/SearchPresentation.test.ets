import { EmptySearchPageState, emptySearchPageAction, SEARCH_PAGE_NONE, SEARCH_PAGE_EMPTY, SEARCH_PAGE_FETCH, SEARCH_PAGE_MORE } from '../main/ets/util/searchPresentation';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdBridge } from '../main/ets/tdkit/TdTypes';
import { GlobalSearchStore, SearchRow } from '../main/ets/store/GlobalSearchStore';
import { describe, expect, it } from '@ohos/hypium';
import { searchSegments, searchHit, searchExcerpt, messageMatch, messageScopeRequest,
  channelSearchCursor, activeSearchUsernames, SEARCH_TAB_RECENT, searchTabForQuery } from '../main/ets/util/searchPresentation';
import { TdObject } from '../main/ets/tdkit/TdTypes';
import { rememberSearchSession, takeSearchSession, forgetSearchSession } from '../main/ets/util/searchSession';

class SearchBridge implements TdBridge {
  sent: TdObject[] = [];
  receive: (json: string) => void = (_json: string): void => {};
  init(callback: (json: string) => void): void { this.receive = callback; }
  send(json: string): void { this.sent.push(JSON.parse(json) as TdObject); }
  reply(index: number, result: TdObject): void {
    result['@extra'] = this.sent[index]['@extra']; this.receive(JSON.stringify(result));
  }
}
function chatIds(ids: number[]): TdObject {
  const result: TdObject = { '@type': 'chats' }; result['chat_ids'] = ids; return result;
}
function namedChat(id: number, title: string): TdObject {
  const type: TdObject = { '@type': 'chatTypeBasicGroup' };
  const result: TdObject = { '@type': 'chat' }; result['id'] = id; result['title'] = title;
  result['type'] = type; return result;
}
async function settleSearch(): Promise<void> { for (let i = 0; i < 12; i++) { await Promise.resolve(); } }

function recentRow(id: number): SearchRow {
  return { chatId: id, userId: 0, title: 'chat', initials: 'C', avatarPath: '', subtitle: '', isChannel: false };
}

function emptyPageState(): EmptySearchPageState {
  return { searched: true, busy: false, failed: false, resolving: false,
    visibleCount: 0, nextOffset: 'next', automaticPages: 0 };
}

export default function searchPresentationTest() {
  describe('SearchPresentation', () => {
    it('empty message pages continue while a next cursor exists', 0, () => {
      expect(emptySearchPageAction(emptyPageState(), 5)).assertEqual(SEARCH_PAGE_FETCH);
    });
    it('automatic paging budget offers continuation instead of reporting no matches', 0, () => {
      const page = emptyPageState(); page.automaticPages = 5;
      expect(emptySearchPageAction(page, 5)).assertEqual(SEARCH_PAGE_MORE);
      page.automaticPages = 0;
      expect(emptySearchPageAction(page, 5)).assertEqual(SEARCH_PAGE_FETCH);
    });
    it('only a settled empty result without continuation is exhausted', 0, () => {
      const page = emptyPageState(); page.nextOffset = '';
      expect(emptySearchPageAction(page, 5)).assertEqual(SEARCH_PAGE_EMPTY);
      page.searched = false;
      expect(emptySearchPageAction(page, 5)).assertEqual(SEARCH_PAGE_NONE);
    });
    it('pending requests and failures cannot fetch again or display no matches', 0, () => {
      const page = emptyPageState(); page.busy = true;
      expect(emptySearchPageAction(page, 5)).assertEqual(SEARCH_PAGE_NONE);
      page.busy = false; page.failed = true;
      expect(emptySearchPageAction(page, 5)).assertEqual(SEARCH_PAGE_NONE);
    });
    it('unresolved chat metadata is not an empty result', 0, () => {
      const page = emptyPageState(); page.resolving = true;
      expect(emptySearchPageAction(page, 5)).assertEqual(SEARCH_PAGE_NONE);
    });
    it('a later visible hit stops automatic empty-page traversal', 0, () => {
      const page = emptyPageState(); page.visibleCount = 1;
      expect(emptySearchPageAction(page, 5)).assertEqual(SEARCH_PAGE_NONE);
    });
    it('empty search defaults to Recent and clearing any category returns there', 0, () => {
      expect(searchTabForQuery('', 0)).assertEqual(SEARCH_TAB_RECENT);
      expect(searchTabForQuery('   ', 9)).assertEqual(SEARCH_TAB_RECENT);
      expect(searchTabForQuery('', SEARCH_TAB_RECENT)).assertEqual(SEARCH_TAB_RECENT);
    });
    it('typing from Recent selects names while an explicit search category stays selected', 0, () => {
      expect(searchTabForQuery('电影', SEARCH_TAB_RECENT)).assertEqual(0);
      expect(searchTabForQuery('电影', 1)).assertEqual(1);
      expect(searchTabForQuery('新词', 9)).assertEqual(9);
      const cleared = searchTabForQuery('', 1);
      expect(searchTabForQuery('再搜索', cleared)).assertEqual(0);
    });
    it('highlights all literal Chinese matches without changing text', 0, () => {
      const parts = searchSegments('电影推荐，周末电影', '电影');
      expect(parts.filter(p => p.hit).length).assertEqual(2);
      expect(parts.map(p => p.text).join('')).assertEqual('电影推荐，周末电影');
    });
    it('matching is case insensitive and preserves original casing', 0, () => {
      const parts = searchSegments('@Movie_daily', 'movie');
      expect(parts.find(p => p.hit)!.text).assertEqual('Movie');
    });
    it('regex characters are treated as plain text', 0, () => {
      expect(searchHit('film[1].pdf', '[1].')).assertTrue();
      expect(searchHit('filmA.pdf', '[1].')).assertFalse();
    });
    it('empty or unmatched queries do not invent hits', 0, () => {
      expect(searchHit('电影', ' ')).assertFalse(); expect(searchHit('cinema', '电影')).assertFalse();
      expect(searchSegments('cinema', '电影')[0].text).assertEqual('cinema');
    });
    it('recycled rows with missing query keep the full text without highlighting', 0, () => {
      expect(searchSegments('最近聊天', undefined)[0].text).assertEqual('最近聊天');
      expect(searchHit('最近聊天', undefined)).assertFalse();
      expect(searchHit('最近聊天', null)).assertFalse();
      expect(searchExcerpt('最近聊天', undefined)).assertEqual('最近聊天');
    });
    it('missing recycled text is rendered empty for both empty and active queries', 0, () => {
      expect(searchSegments(undefined, '')[0].text).assertEqual('');
      expect(searchHit(undefined, '电影')).assertFalse();
      expect(searchHit(null, '电影')).assertFalse();
      expect(searchExcerpt(undefined, '电影')).assertEqual('');
      expect(searchExcerpt(null, null)).assertEqual('');
    });
    it('Unicode case expansion never highlights the wrong positions', 0, () => {
      expect(searchSegments('İmovie', 'movie').some(p => p.hit)).assertFalse();
    });
    it('emoji and repeated matches preserve all text', 0, () => {
      const parts = searchSegments('🎬电影🎬电影', '电影');
      expect(parts.map(p => p.text).join('')).assertEqual('🎬电影🎬电影');
      expect(parts.filter(p => p.hit).length).assertEqual(2);
    });
    it('long excerpts move the actual hit into the visible preview', 0, () => {
      const preview = searchExcerpt('a'.repeat(500) + '电影' + 'b'.repeat(500), '电影');
      expect(preview.startsWith('…')).assertTrue(); expect(preview.includes('电影')).assertTrue();
      expect(preview.length < 225).assertTrue();
    });
    it('message body and file name are independent match targets', 0, () => {
      const caption: TdObject = { '@type': 'formattedText' }; caption['text'] = '周末一起看';
      const doc: TdObject = { '@type': 'document' }; doc['file_name'] = '电影.pdf';
      const content: TdObject = { '@type': 'messageDocument' }; content['caption'] = caption; content['document'] = doc;
      const message: TdObject = { '@type': 'message' }; message['content'] = content;
      const match = messageMatch(message);
      expect(searchHit(match.body, '电影')).assertFalse(); expect(searchHit(match.fileName, '电影')).assertTrue();
    });
    it('voice messages are not falsely treated as searchable transcripts', 0, () => {
      const content: TdObject = { '@type': 'messageVoiceNote' };
      const message: TdObject = { '@type': 'message' }; message['content'] = content;
      expect(messageMatch(message).body).assertEqual('');
    });
    it('username matching uses active aliases and excludes disabled ones', 0, () => {
      const names: TdObject = { '@type': 'usernames' }; names['active_usernames'] = ['Movie', 'Cinema']; names['disabled_usernames'] = ['Old'];
      const user: TdObject = { '@type': 'user' }; user['usernames'] = names;
      expect(activeSearchUsernames(user).join(',')).assertEqual('Movie,Cinema');
    });
    it('all-message search does not exclude archived chats', 0, () => {
      const req = messageScopeRequest('电影', 'all', 0, 'cursor');
      expect(req['@type']).assertEqual('searchMessages'); expect(req['offset']).assertEqual('cursor');
      expect(req['chat_list'] === undefined).assertTrue(); expect(req['chat_type_filter'] === undefined).assertTrue();
    });
    it('channel category filters content at the server before pagination', 0, () => {
      const req = messageScopeRequest('电影', 'channel', 0, '');
      expect((req['chat_type_filter'] as TdObject)['@type']).assertEqual('searchMessagesChatTypeFilterChannel');
    });
    it('private and group scopes use distinct server filters', 0, () => {
      expect((messageScopeRequest('q', 'user', 0, '')['chat_type_filter'] as TdObject)['@type'])
        .assertEqual('searchMessagesChatTypeFilterPrivate');
      expect((messageScopeRequest('q', 'group', 0, '')['chat_type_filter'] as TdObject)['@type'])
        .assertEqual('searchMessagesChatTypeFilterGroup');
    });
    it('fixed channel uses its own message cursor and never global search', 0, () => {
      const req = messageScopeRequest('电影', 'channel', -123, '456');
      expect(req['@type']).assertEqual('searchChatMessages'); expect(req['chat_id']).assertEqual(-123);
      expect(req['from_message_id']).assertEqual(456); expect(req['offset']).assertEqual(0);
      expect(req['chat_type_filter'] === undefined).assertTrue();
    });
    it('changing channel resets the first page while preserving the query', 0, () => {
      const req = messageScopeRequest('电影', 'channel', -456, '');
      expect(req['chat_id']).assertEqual(-456); expect(req['from_message_id']).assertEqual(0);
      expect(req['query']).assertEqual('电影');
    });
    it('fixed channel pagination respects server continuation and detects end or loops', 0, () => {
      const response: TdObject = { '@type': 'foundChatMessages' }; response['next_from_message_id'] = 123;
      expect(channelSearchCursor(response, '')).assertEqual('123');
      expect(channelSearchCursor(response, '123')).assertEqual(''); response['next_from_message_id'] = 0;
      expect(channelSearchCursor(response, '')).assertEqual('');
    });
    it('returning from a result retains a single selected channel and filters', 0, () => {
      rememberSearchSession('电影', 1, 100, 'group', 'channel', -123, '推荐');
      const state = takeSearchSession(101)!;
      expect(state.channelId).assertEqual(-123); expect(state.channelTitle).assertEqual('推荐');
      expect(state.messageScope).assertEqual('channel'); expect(state.objectScope).assertEqual('group');
      forgetSearchSession(); expect(takeSearchSession(102) === null).assertTrue();
    });
    it('name search never starts a message search and deduplicates public results', 0, async () => {
      const bridge = new SearchBridge(); const client = new TdClient(bridge); client.start();
      const store = new GlobalSearchStore(client); store.searchChats('电影');
      bridge.reply(0, chatIds([1])); await settleSearch();
      bridge.reply(1, chatIds([1, 2])); await settleSearch();
      bridge.reply(2, namedChat(1, '电影群')); bridge.reply(3, namedChat(2, '电影公开群')); await settleSearch();
      expect(store.results.length).assertEqual(2);
      expect(store.results[0].identity!.existing).assertTrue(); expect(store.results[1].identity!.existing).assertFalse();
      expect(bridge.sent.some((r: TdObject): boolean => r['@type'] === 'searchMessages')).assertFalse();
      store.close(); client.dispose();
    });
    it('channel discovery applies a server filter to local and public name searches', 0, async () => {
      const bridge = new SearchBridge(); const client = new TdClient(bridge); client.start();
      const store = new GlobalSearchStore(client); store.searchChats('电影', 'channel');
      expect((bridge.sent[0]['type_filter'] as TdObject)['@type']).assertEqual('searchChatTypeFilterChannel');
      bridge.reply(0, chatIds([])); await settleSearch();
      expect((bridge.sent[1]['type_filter'] as TdObject)['@type']).assertEqual('searchChatTypeFilterChannel');
      bridge.reply(1, chatIds([])); await settleSearch(); store.close(); client.dispose();
    });
    it('a late old query response cannot replace a newer search', 0, async () => {
      const bridge = new SearchBridge(); const client = new TdClient(bridge); client.start();
      const store = new GlobalSearchStore(client); store.searchChats('old'); store.searchChats('new');
      bridge.reply(0, chatIds([99])); await settleSearch(); expect(bridge.sent.length).assertEqual(2);
      bridge.reply(1, chatIds([])); await settleSearch(); bridge.reply(2, chatIds([])); await settleSearch();
      expect(store.results.length).assertEqual(0); store.close(); client.dispose();
    });
    it('closing a search rejects late resolved objects', 0, async () => {
      const bridge = new SearchBridge(); const client = new TdClient(bridge); client.start();
      const store = new GlobalSearchStore(client); store.searchChats('电影');
      bridge.reply(0, chatIds([1])); await settleSearch(); bridge.reply(1, chatIds([])); await settleSearch();
      store.close(); bridge.reply(2, namedChat(1, 'late')); await settleSearch();
      expect(store.results[0].title).assertEqual(''); client.dispose();
    });
    it('removes only the selected recent visit after server success', 0, async () => {
      const bridge = new SearchBridge(); const client = new TdClient(bridge); client.start();
      const store = new GlobalSearchStore(client); store.recent = [recentRow(1), recentRow(2)];
      const pending = store.removeRecent(1);
      expect(bridge.sent[0]['@type']).assertEqual('removeRecentlyFoundChat');
      expect(bridge.sent[0]['chat_id']).assertEqual(1);
      expect(store.recent.length).assertEqual(2);
      bridge.reply(0, { '@type': 'ok' }); await pending;
      expect(store.recent.map((row: SearchRow): number => row.chatId).join(',')).assertEqual('2');
      store.close(); client.dispose();
    });
    it('a failed recent deletion cannot restore a concurrently deleted row', 0, async () => {
      const bridge = new SearchBridge(); const client = new TdClient(bridge); client.start();
      const store = new GlobalSearchStore(client); store.recent = [recentRow(1), recentRow(2)];
      let failed = false;
      const first = store.removeRecent(1).catch((): void => { failed = true; });
      const second = store.removeRecent(2);
      bridge.reply(1, { '@type': 'ok' }); await second;
      const error: TdObject = { '@type': 'error' }; error['code'] = 500; error['message'] = 'failed';
      bridge.reply(0, error); await first;
      expect(failed).assertTrue();
      expect(store.recent.map((row: SearchRow): number => row.chatId).join(',')).assertEqual('1');
      store.close(); client.dispose();
    });
    it('failed clear-all preserves the result of a successful single deletion', 0, async () => {
      const bridge = new SearchBridge(); const client = new TdClient(bridge); client.start();
      const store = new GlobalSearchStore(client); store.recent = [recentRow(1), recentRow(2)];
      const single = store.removeRecent(1);
      let failed = false;
      const clear = store.clearRecent().catch((): void => { failed = true; });
      bridge.reply(0, { '@type': 'ok' }); await single;
      const error: TdObject = { '@type': 'error' }; error['code'] = 500; error['message'] = 'failed';
      bridge.reply(1, error); await clear;
      expect(failed).assertTrue();
      expect(store.recent.map((row: SearchRow): number => row.chatId).join(',')).assertEqual('2');
      store.close(); client.dispose();
    });
    it('closing the store ignores a late recent deletion response', 0, async () => {
      const bridge = new SearchBridge(); const client = new TdClient(bridge); client.start();
      const store = new GlobalSearchStore(client); store.recent = [recentRow(1)];
      const pending = store.removeRecent(1); store.close();
      bridge.reply(0, { '@type': 'ok' }); await pending;
      expect(store.recent.length).assertEqual(1); client.dispose();
    });
    it('legacy short channel pages continue until the cursor stops advancing', 0, () => {
      const response: TdObject = { '@type': 'messages' }; const message: TdObject = { '@type': 'message' }; message['id'] = 17;
      response['messages'] = [message]; expect(channelSearchCursor(response, '')).assertEqual('17');
      expect(channelSearchCursor(response, '17')).assertEqual('');
    });
  });
}
