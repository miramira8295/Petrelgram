import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { StoryStore, StoryRingEntry } from '../main/ets/store/StoryStore';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function feedActiveStories(b: FakeBridge, chatId: number, order: number,
  storyIds: number[], maxRead: number, listType: string = 'storyListMain'): void {
  const infos: TdObject[] = storyIds.map((id: number): TdObject => {
    const info: TdObject = { '@type': 'storyInfo' };
    info['story_id'] = id;
    info['date'] = 100;
    return info;
  });
  const active: TdObject = { '@type': 'chatActiveStories' };
  active['chat_id'] = chatId;
  active['list'] = { '@type': listType } as TdObject;
  active['order'] = order;
  active['max_read_story_id'] = maxRead;
  active['stories'] = infos;
  const u: TdObject = { '@type': 'updateChatActiveStories' };
  u['active_stories'] = active;
  b.onReceive(JSON.stringify(u));
}

function setup(): Array<Object> {
  const b = new FakeBridge();
  const c = new TdClient(b);
  const s = new StoryStore(c);
  c.start();
  return [b, s];
}

export default function storyStoreTest() {
  describe('StoryStore', () => {
    it('open_requests_main_story_list', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as StoryStore;
      s.open();
      const req = b.sent.map((json: string): TdObject => JSON.parse(json) as TdObject)
        .find((o: TdObject): boolean => o['@type'] === 'loadActiveStories');
      expect(req !== undefined).assertTrue();
      expect(((req!['story_list'] as TdObject)['@type'] as string)).assertEqual('storyListMain');
    });
    it('entries_sorted_by_order_with_unread_flag', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as StoryStore;
      feedActiveStories(b, 100, 5, [3, 1, 2], 2);
      feedActiveStories(b, 200, 9, [7], 7);
      const entries: StoryRingEntry[] = s.entries();
      expect(entries.length).assertEqual(2);
      expect(entries[0].chatId).assertEqual(200);
      expect(entries[0].hasUnread).assertFalse();
      expect(entries[1].chatId).assertEqual(100);
      expect(entries[1].hasUnread).assertTrue();
      expect(entries[1].storyIds.join(',')).assertEqual('1,2,3');
    });
    it('empty_or_archived_removes_entry', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as StoryStore;
      feedActiveStories(b, 100, 5, [1], 0);
      expect(s.entries().length).assertEqual(1);
      feedActiveStories(b, 100, 5, [], 0);
      expect(s.entries().length).assertEqual(0);
      feedActiveStories(b, 300, 2, [4], 0, 'storyListArchive');
      expect(s.entries().length).assertEqual(0);
    });
    it('read_state_updates_via_new_snapshot', 0, () => {
      const arr = setup(); const b = arr[0] as FakeBridge; const s = arr[1] as StoryStore;
      let latest: StoryRingEntry[] = [];
      s.subscribe((entries: StoryRingEntry[]): void => { latest = entries; });
      feedActiveStories(b, 100, 5, [1, 2], 0);
      expect(latest[0].hasUnread).assertTrue();
      feedActiveStories(b, 100, 5, [1, 2], 2);
      expect(latest[0].hasUnread).assertFalse();
      expect(latest[0].maxReadStoryId).assertEqual(2);
    });
  });
}
