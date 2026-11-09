import { describe, expect, it } from '@ohos/hypium';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { MentionItem } from '../main/ets/store/InputSuggestions';
import { SearchSession } from '../main/ets/pages/chat/SearchSession';
import { SearchSenderSuggestions } from '../main/ets/pages/chat/SearchSenderSuggestions';
import { senderSearchKeywords, senderSearchToken } from '../main/ets/util/searchSenderText';

const ALICE: MentionItem = { userId: 7, name: 'Alice Smith', username: 'alice', avatarFileId: 0 };
const NO_USERNAME: MentionItem = { userId: 8, name: '张 三', username: '', avatarFileId: 0 };

class SearchBridge implements TdBridge {
  receive: (json: string) => void = (): void => {};
  requests: TdObject[] = [];
  init(cb: (json: string) => void): void { this.receive = cb; }
  send(json: string): void { this.requests.push(JSON.parse(json) as TdObject); }
  reply(index: number, data: TdObject): void {
    data['@extra'] = this.requests[index]['@extra'];
    this.receive(JSON.stringify(data));
  }
}

class SenderHarness {
  bridge: SearchBridge = new SearchBridge();
  client: TdClient = new TdClient(this.bridge);
  search: SearchSession = new SearchSession();
  chatId: number = -100;
  jumps: number[] = [];
  constructor() {
    this.client.start();
    this.search.bind({
      chatId: (): number => this.chatId, client: (): TdClient => this.client,
      canSuggestSenders: (): boolean => true,
      threadRootId: (): number => 0, forumTopicId: (): number => 11,
      directMessagesTopicId: (): number => 0,
      jumpToMessage: (id: number): void => { this.jumps.push(id); },
      onNavigatedResult: (): void => {}, cancelFlash: (): void => {}
    });
    this.search.enter();
  }
  // A candidate list returned by member lookup; exercise the real pick/run path.
  choose(item: MentionItem, query: string = '@a'): void {
    this.search.updateQuery(query);
    this.search.senders.items = [item];
    this.search.pickSender(item);
  }
  finish(): void {
    this.search.dispose();
    for (let i: number = 0; i < this.bridge.requests.length; i++) {
      this.bridge.reply(i, { '@type': 'foundChatMessages', 'total_count': 1,
        'messages': [{ '@type': 'message', 'id': 99 } as TdObject] });
    }
  }
}

function waitSuggestions(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => { setTimeout(resolve, 220); });
}
async function flushSender(): Promise<void> {
  for (let i: number = 0; i < 12; i++) { await Promise.resolve(); }
}

export default function searchSenderTest() {
  describe('SearchSender', () => {
    it('completion_prefers_username_and_supports_names_with_spaces', 0, () => {
      expect(senderSearchToken('Alice Smith', 'alice', 7)).assertEqual('@alice');
      expect(senderSearchToken('张 三', '', 8)).assertEqual('@张 三');
      expect(senderSearchKeywords('@张 三 会议', '@张 三', 0)).assertEqual('会议');
    });
    it('only_exact_completed_token_is_removed_from_search_text', 0, () => {
      expect(senderSearchKeywords('会议 @alice 记录', '@alice', 3)).assertEqual('会议  记录');
      expect(senderSearchKeywords('@alice', '@alice', 0)).assertEqual('');
      expect(senderSearchKeywords('@alice2 记录', '@alice', 0)).assertEqual(null);
      expect(senderSearchKeywords('mail@alice', '@alice', 4)).assertEqual(null);
      expect(senderSearchKeywords('@ali 记录', '@alice', 0)).assertEqual(null);
    });
    it('typed_username_without_picking_remains_literal_text', 0, () => {
      const t: SenderHarness = new SenderHarness();
      t.search.updateQuery('@alice'); t.search.run(0, 0);
      const request: TdObject = t.bridge.requests[0];
      expect(request['query']).assertEqual('@alice');
      expect(request['sender_id']).assertEqual(undefined);
      expect(t.search.senders.open).assertFalse();
      t.finish();
    });
    it('picked_sender_completes_text_and_preserves_topic_and_paging_filters', 0, () => {
      const t: SenderHarness = new SenderHarness();
      t.choose(ALICE);
      expect(t.search.query).assertEqual('@alice ');
      expect(t.search.senderId).assertEqual(7);
      expect(t.bridge.requests[0]['query']).assertEqual('');
      t.search.updateQuery('@alice meeting'); t.search.run(30, 0);
      const request: TdObject = t.bridge.requests[1];
      expect(request['query']).assertEqual('meeting');
      expect((request['sender_id'] as TdObject)['user_id']).assertEqual(7);
      expect(request['from_message_id']).assertEqual(30);
      expect((request['topic_id'] as TdObject)['forum_topic_id']).assertEqual(11);
      t.finish();
    });
    it('name_only_member_is_bound_by_id_not_by_display_name', 0, () => {
      const t: SenderHarness = new SenderHarness();
      t.choose(NO_USERNAME, '@张');
      expect(t.search.query).assertEqual('@张 三 ');
      expect((t.bridge.requests[0]['sender_id'] as TdObject)['user_id']).assertEqual(8);
      t.search.updateQuery('@张 三 文件'); t.search.run(0, 0);
      expect(t.bridge.requests[1]['query']).assertEqual('文件');
      expect(t.search.senderId).assertEqual(8);
      t.finish();
    });
    it('editing_identity_removes_filter_and_rejects_old_message_results', 0, async () => {
      const t: SenderHarness = new SenderHarness(); t.choose(ALICE);
      t.search.updateQuery('@alice2');
      expect(t.search.senderId).assertEqual(0);
      t.bridge.reply(0, { '@type': 'foundChatMessages', 'total_count': 1,
        'messages': [{ '@type': 'message', 'id': 99 } as TdObject] });
      await flushSender();
      expect(t.jumps.length).assertEqual(0);
      t.search.run(0, 0);
      expect(t.bridge.requests[1]['query']).assertEqual('@alice2');
      expect(t.bridge.requests[1]['sender_id']).assertEqual(undefined);
      t.finish();
    });
    it('clearing_and_reopening_do_not_retain_sender_filter', 0, () => {
      const t: SenderHarness = new SenderHarness(); t.choose(ALICE);
      t.search.updateQuery(''); expect(t.search.senderId).assertEqual(0);
      t.choose(ALICE); t.search.enter();
      expect(t.search.senderId).assertEqual(0); expect(t.search.query).assertEqual('');
      t.search.exit(); expect(t.search.senders.open).assertFalse();
      t.finish();
    });
    it('member_lookup_filters_on_server_and_completes_real_candidate', 0, async () => {
      const t: SenderHarness = new SenderHarness();
      t.search.updateQuery('@a'); t.search.updateQuery('@ali');
      await waitSuggestions();
      expect(t.bridge.requests.length).assertEqual(1);
      expect(t.bridge.requests[0]['@type']).assertEqual('searchChatMembers');
      expect(t.bridge.requests[0]['query']).assertEqual('ali');
      t.bridge.reply(0, { '@type': 'chatMembers', 'members': [{ '@type': 'chatMember',
        'member_id': { '@type': 'messageSenderUser', 'user_id': 7 } as TdObject } as TdObject] });
      await flushSender();
      t.bridge.reply(1, { '@type': 'user', 'id': 7, 'first_name': 'Alice',
        'usernames': { '@type': 'usernames', 'active_usernames': ['alice'] } as TdObject });
      await flushSender();
      expect(t.search.senders.items.length).assertEqual(1);
      t.search.pickSender(t.search.senders.items[0]);
      expect(t.search.query).assertEqual('@alice ');
      expect((t.bridge.requests[2]['sender_id'] as TdObject)['user_id']).assertEqual(7);
      t.finish();
    });
    it('late_suggestions_are_ignored_after_new_query_and_clear', 0, async () => {
      const s: SearchSenderSuggestions = new SearchSenderSuggestions();
      const resolvers: Array<(items: MentionItem[]) => void> = [];
      s.bind({ chatId: (): number => 1, enabled: (): boolean => true,
        find: (): Promise<MentionItem[]> => new Promise<MentionItem[]>((resolve) => { resolvers.push(resolve); }) });
      s.update('@a'); await waitSuggestions();
      s.update('@b'); await waitSuggestions();
      resolvers[0]([ALICE]); await flushSender();
      expect(s.items.length).assertEqual(0);
      s.clear(); resolvers[1]([NO_USERNAME]); await flushSender();
      expect(s.open).assertFalse(); expect(s.items.length).assertEqual(0);
    });
    it('switching_chat_rejects_late_members_and_email_does_not_trigger_lookup', 0, async () => {
      const s: SearchSenderSuggestions = new SearchSenderSuggestions();
      let chatId: number = 1;
      let resolveMembers: (items: MentionItem[]) => void = (): void => {};
      s.bind({ chatId: (): number => chatId, enabled: (): boolean => true,
        find: (): Promise<MentionItem[]> => new Promise<MentionItem[]>((resolve) => { resolveMembers = resolve; }) });
      s.update('@a'); await waitSuggestions(); chatId = 2;
      resolveMembers([ALICE]); await flushSender();
      expect(s.items.length).assertEqual(0);
      s.update('mail@example.com'); expect(s.open).assertFalse();
      s.clear();
    });
  });
}
