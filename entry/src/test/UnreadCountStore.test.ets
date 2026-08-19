import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UnreadCountStore } from '../main/ets/store/UnreadCountStore';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function pushUnread(bridge: FakeBridge, listType: string, unmuted: number, markedUnmuted: number = 0): void {
  const cl: TdObject = { '@type': listType };
  const u: TdObject = { '@type': 'updateUnreadChatCount' };
  u['chat_list'] = cl;
  u['unread_unmuted_count'] = unmuted;
  u['marked_as_unread_unmuted_count'] = markedUnmuted;
  bridge.onReceive(JSON.stringify(u));
}

export default function unreadCountStoreTest() {
  describe('UnreadCountStore', () => {
    it('stores_unmuted_by_list', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      pushUnread(bridge, 'chatListMain', 3);
      pushUnread(bridge, 'chatListArchive', 7);
      expect(store.getUnread('main')).assertEqual(3);
      expect(store.getUnread('archive')).assertEqual(7);
    });
    it('unknown_list_zero', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      expect(store.getUnread('folder:9')).assertEqual(0);
    });
    it('subscribe_fires', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      let fires = 0;
      store.subscribe(() => { fires += 1; });
      expect(fires).assertEqual(1); // replay
      pushUnread(bridge, 'chatListMain', 2);
      expect(fires).assertEqual(2);
    });

    // 只数有未读消息的会话。TDLib 另有一个 marked_as_unread_unmuted_count
    // 装"手动标记为未读"的，刻意不加——文件夹角标那边也只数有未读消息的
    // （ChatStore.unreadChatCount），两边必须同一个口径，否则同一批会话在两
    // 个标签上显示不同的数字。
    it('ignores_chats_that_are_only_marked_as_unread', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      pushUnread(bridge, 'chatListMain', 3, 2);
      expect(store.getUnread('main')).assertEqual(3);
    });

    it('handles_a_missing_marked_field', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      const cl: TdObject = { '@type': 'chatListMain' };
      const u: TdObject = { '@type': 'updateUnreadChatCount' };
      u['chat_list'] = cl;
      u['unread_unmuted_count'] = 4;
      bridge.onReceive(JSON.stringify(u));
      expect(store.getUnread('main')).assertEqual(4);
    });
  });
}
