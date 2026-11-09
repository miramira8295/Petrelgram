import { describe, expect, it } from '@ohos/hypium';
import { RecentChatHistory, RecentChatHistoryState, RecentChatHistoryStorage,
  emptyRecentChatHistory } from '../main/ets/util/recentChatHistory';

class HistoryStorageFake implements RecentChatHistoryStorage {
  state: RecentChatHistoryState = emptyRecentChatHistory();
  fail: boolean = false;
  writes: number = 0;
  read(): RecentChatHistoryState { return this.state; }
  write(state: RecentChatHistoryState): void {
    if (this.fail) { throw new Error('disk full'); }
    this.state = state; this.writes++;
  }
}

export default function recentChatHistoryTest() {
  describe('RecentChatHistory', () => {
    it('existing history is initially preserved in TDLib order', 0, () => {
      const history = new RecentChatHistory(new HistoryStorageFake());
      expect(history.filter([3, -2, 1]).join(',')).assertEqual('3,-2,1');
    });
    it('single removal preserves other chats and persists across recreation', 0, () => {
      const storage = new HistoryStorageFake(); const history = new RecentChatHistory(storage);
      history.remove(-2);
      expect(history.filter([3, -2, 1]).join(',')).assertEqual('3,1');
      expect(new RecentChatHistory(storage).filter([-2, 3]).join(',')).assertEqual('3');
    });
    it('clear hides even older entries outside the previously loaded page', 0, () => {
      const storage = new HistoryStorageFake(); const history = new RecentChatHistory(storage);
      history.clear();
      expect(history.filter([1, 2, 3, 999]).length).assertEqual(0);
      expect(new RecentChatHistory(storage).filter([999]).length).assertEqual(0);
    });
    it('opening a removed chat restores only that chat', 0, () => {
      const history = new RecentChatHistory(new HistoryStorageFake());
      history.remove(1); history.remove(2); history.opened(1);
      expect(history.filter([1, 2, 3]).join(',')).assertEqual('1,3');
    });
    it('after clearing only explicitly reopened chats can return', 0, () => {
      const storage = new HistoryStorageFake(); const history = new RecentChatHistory(storage);
      history.clear(); history.opened(2);
      expect(new RecentChatHistory(storage).filter([1, 2, 3]).join(',')).assertEqual('2');
    });
    it('removing a reopened chat and clearing again keep stale snapshots hidden', 0, () => {
      const history = new RecentChatHistory(new HistoryStorageFake());
      history.clear(); history.opened(1); history.opened(2); history.remove(1);
      expect(history.filter([1, 2, 3]).join(',')).assertEqual('2');
      history.clear(); expect(history.filter([1, 2, 3]).length).assertEqual(0);
    });
    it('failed removal or clear never publishes or changes visibility', 0, () => {
      const storage = new HistoryStorageFake(); const history = new RecentChatHistory(storage);
      let changes = 0; history.subscribe((): void => { changes++; });
      history.filter([1, 2]); storage.fail = true;
      try { history.remove(1); } catch (_error) {}
      try { history.clear(); } catch (_error) {}
      expect(history.filter([1, 2]).join(',')).assertEqual('1,2'); expect(changes).assertEqual(0);
    });
    it('failed reopen does not resurrect a deleted record', 0, () => {
      const storage = new HistoryStorageFake(); const history = new RecentChatHistory(storage);
      history.remove(1); storage.fail = true;
      try { history.opened(1); } catch (_error) {}
      expect(history.filter([1]).length).assertEqual(0);
    });
    it('accounts have independent deletion state', 0, () => {
      const first = new RecentChatHistory(new HistoryStorageFake());
      const second = new RecentChatHistory(new HistoryStorageFake());
      first.clear(); expect(second.filter([1]).length).assertEqual(1);
      second.remove(1); first.opened(1);
      expect(first.filter([1]).length).assertEqual(1); expect(second.filter([1]).length).assertEqual(0);
    });
    it('detached subscribers receive no late changes', 0, () => {
      const history = new RecentChatHistory(new HistoryStorageFake()); let changes = 0;
      const off = history.subscribe((): void => { changes++; }); history.remove(1); off(); history.clear();
      expect(changes).assertEqual(1);
    });
    it('ordinary opening does not write before history has been modified', 0, () => {
      const storage = new HistoryStorageFake(); const history = new RecentChatHistory(storage);
      history.opened(1); history.opened(-2); history.remove(0); history.opened(0);
      expect(storage.writes).assertEqual(0);
    });
    it('reopened history is bounded and repeated opens do not duplicate entries', 0, () => {
      const storage = new HistoryStorageFake(); const history = new RecentChatHistory(storage); history.clear();
      for (let id = 1; id <= 40; id++) { history.opened(id); }
      history.opened(40);
      expect(storage.state.reopened.length).assertEqual(30);
      expect(history.filter([1, 10, 11, 40]).join(',')).assertEqual('11,40');
    });
  });
}
