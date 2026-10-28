import { describe, expect, it } from '@ohos/hypium';
import { TdBridge, TdObject } from '../main/ets/tdkit/TdTypes';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { SearchSession } from '../main/ets/pages/chat/SearchSession';

class DrawerBridge implements TdBridge {
  requests: TdObject[] = [];
  receive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.receive = cb; }
  send(json: string): void { this.requests.push(JSON.parse(json) as TdObject); }
  reply(index: number, data: TdObject): void {
    data['@extra'] = this.requests[index]['@extra'];
    this.receive(JSON.stringify(data));
  }
  page(index: number, ids: number[], total: number): void {
    const data: TdObject = { '@type': 'foundChatMessages' };
    data['total_count'] = total;
    data['messages'] = ids.map((id: number): TdObject => {
      const message: TdObject = { '@type': 'message' };
      message['id'] = id;
      message['date'] = 100;
      return message;
    });
    this.reply(index, data);
  }
}

class DrawerHarness {
  bridge: DrawerBridge = new DrawerBridge();
  client: TdClient = new TdClient(this.bridge);
  search: SearchSession = new SearchSession();
  jumps: number[] = [];
  navigated: number[] = [];
  constructor() {
    this.client.start();
    this.search.bind({
      client: (): TdClient => this.client, chatId: (): number => -100,
      threadRootId: (): number => 0, forumTopicId: (): number => 11,
      directMessagesTopicId: (): number => 0,
      jumpToMessage: (id: number): void => { this.jumps.push(id); },
      onNavigatedResult: (id: number): void => { this.navigated.push(id); },
      cancelFlash: (): void => {}
    });
    this.search.enter();
    this.search.updateQuery('hello');
  }
  start(): void { this.search.run(0, 0); }
  finish(): void {
    this.search.dispose();
    for (let i = 0; i < this.bridge.requests.length; i++) {
      this.bridge.reply(i, { '@type': 'ok' });
    }
  }
}

async function flushDrawer(): Promise<void> {
  for (let i = 0; i < 12; i++) { await Promise.resolve(); }
}

export default function searchResultsDrawerTest(): void {
  describe('SearchResultsDrawer', (): void => {
    it('opening_uses_cached_rows_without_jumping_or_requerying', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.start(); h.bridge.page(0, [30, 20], 3); await flushDrawer();
      h.search.openResults();
      expect(h.search.resultsOpen).assertTrue();
      expect(h.search.resultMessages.get(20)?.['date']).assertEqual(100);
      expect(h.bridge.requests.length).assertEqual(1);
      expect(h.jumps.join(',')).assertEqual('30');
      h.finish();
    });
    it('choosing_result_closes_and_uses_existing_jump_and_selection_hook', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.start(); h.bridge.page(0, [30, 20], 3); await flushDrawer();
      h.search.openResults(); h.search.chooseResult(20);
      expect(h.search.resultsOpen).assertFalse(); expect(h.search.idx).assertEqual(1);
      expect(h.jumps.join(',')).assertEqual('30,20'); expect(h.navigated.join(',')).assertEqual('20');
      h.search.chooseResult(999); expect(h.jumps.length).assertEqual(2);
      h.finish();
    });
    it('paging_deduplicates_without_moving_chat_or_current_result', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.start(); h.bridge.page(0, [30, 20], 4); await flushDrawer();
      h.search.chooseResult(20); h.search.loadMoreResults(); h.search.loadMoreResults();
      expect(h.bridge.requests.length).assertEqual(2);
      expect(h.bridge.requests[1]['from_message_id']).assertEqual(20);
      const topic = h.bridge.requests[1]['topic_id'] as TdObject;
      expect(topic['forum_topic_id']).assertEqual(11);
      h.bridge.page(1, [20, 10, 5], 4); await flushDrawer();
      expect(h.search.results.join(',')).assertEqual('30,20,10,5'); expect(h.search.idx).assertEqual(1);
      expect(h.jumps.join(',')).assertEqual('30,20'); expect(h.search.canLoadMoreResults()).assertFalse();
      h.finish();
    });
    it('failed_page_can_retry_same_cursor_without_losing_rows', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.start(); h.bridge.page(0, [30, 20], 3); await flushDrawer();
      h.search.loadMoreResults();
      h.bridge.reply(1, { '@type': 'error', 'code': 500, 'message': 'network' }); await flushDrawer();
      expect(h.search.loading).assertFalse(); expect(h.search.loadFailed).assertTrue();
      expect(h.search.results.join(',')).assertEqual('30,20');
      h.search.loadMoreResults(); expect(h.bridge.requests[2]['from_message_id']).assertEqual(20);
      h.bridge.page(2, [10], 3); await flushDrawer();
      expect(h.search.loadFailed).assertFalse(); expect(h.search.results.length).assertEqual(3);
      h.finish();
    });
    it('nonadvancing_page_stops_repeated_requests', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.start(); h.bridge.page(0, [30], 8); await flushDrawer();
      h.search.loadMoreResults(); h.bridge.page(1, [30], 8); await flushDrawer();
      expect(h.search.canLoadMoreResults()).assertFalse();
      h.search.loadMoreResults(); expect(h.bridge.requests.length).assertEqual(2);
      h.finish();
    });
    it('query_change_closes_sheet_and_discards_old_page', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.start(); h.bridge.page(0, [30], 2); await flushDrawer();
      h.search.openResults(); h.search.loadMoreResults(); h.search.updateQuery('new'); h.start();
      h.bridge.page(2, [90], 1); await flushDrawer();
      h.bridge.page(1, [20], 2); await flushDrawer();
      expect(h.search.resultsOpen).assertFalse(); expect(h.search.results.join(',')).assertEqual('90');
      expect(h.search.resultMessages.has(20)).assertFalse(); expect(h.search.loading).assertFalse();
      h.finish();
    });
    it('old_failure_does_not_change_new_search_state', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.start(); h.search.updateQuery('new'); h.start();
      h.bridge.page(1, [90], 1); await flushDrawer();
      h.bridge.reply(0, { '@type': 'error', 'code': 500, 'message': 'old' }); await flushDrawer();
      expect(h.search.loadFailed).assertFalse(); expect(h.search.results.join(',')).assertEqual('90');
      h.finish();
    });
    it('missing_route_anchor_is_hydrated_without_navigation', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.search.seedFromRoute('hello', true, 25); h.start();
      h.bridge.page(0, [30, 20], 2); await flushDrawer(); h.search.openResults();
      expect(h.bridge.requests[1]['@type']).assertEqual('getMessage');
      expect(h.bridge.requests[1]['message_id']).assertEqual(25);
      h.bridge.reply(1, { '@type': 'message', 'id': 25, 'date': 200 }); await flushDrawer();
      expect(h.search.resultMessages.get(25)?.['date']).assertEqual(200);
      expect(h.jumps.length).assertEqual(0); expect(h.search.idx).assertEqual(1);
      h.finish();
    });
    it('empty_search_cannot_open_and_disposal_closes_sheet', 0, async (): Promise<void> => {
      const h = new DrawerHarness(); h.search.openResults(); expect(h.search.resultsOpen).assertFalse();
      h.start(); h.bridge.page(0, [30], 1); await flushDrawer(); h.search.openResults();
      h.search.dispose(); expect(h.search.resultsOpen).assertFalse(); expect(h.search.loading).assertFalse();
      h.search.chooseResult(30); h.search.openResults(); h.search.loadMoreResults();
      expect(h.jumps.length).assertEqual(1);
      expect(h.search.resultsOpen).assertFalse(); h.finish();
    });
  });
}
