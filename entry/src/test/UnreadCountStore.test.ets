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

    // 「全部」和文件夹的角标必须是同一个口径，否则同一批会话在两个标签上
    // 显示不同的数字。文件夹侧数的是 `未读 > 0 或被标记为未读`，所以这边
    // 也必须把 marked_as_unread_unmuted_count 加上——TDLib 把"手动标记为
    // 未读"单独放在这个字段里，不含在 unread_unmuted_count 中。
    it('counts_marked_as_unread_chats_too', 0, () => {
      const bridge = new FakeBridge();
      const client = new TdClient(bridge);
      const store = new UnreadCountStore(client);
      client.start();
      pushUnread(bridge, 'chatListMain', 3, 2);
      expect(store.getUnread('main')).assertEqual(5);
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
