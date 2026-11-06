import { describe, expect, it } from '@ohos/hypium';
import { TdClient, TimerFns } from '../main/ets/tdkit/TdClient';
import { TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { ChatStore } from '../main/ets/store/ChatStore';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import { OrderSnapshot } from '../main/ets/store/chatListOrder';
import { setChatListSourceForTest } from '../main/ets/util/chatListV2';

// V2 场景：V1 的数据面完全不在更新流上，列表成员来自 worker 的排序快照，
// 实体来自 worker 投递的镜像。这组用例直接调那两个入口，不喂 update。
class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(_json: string): void {}
}

const timer: TimerFns = {
  setTimeout: (_cb: () => void, _ms: number): number => 1,
  clearTimeout: (_id: number): void => {}
};

function entryOf(id: number, unread: number): ChatEntry {
  return {
    id, revision: 0, title: `chat-${id}`, isMuted: true, usesDefaultMute: false,
    unreadCount: unread, unreadMentionCount: 0, rawUnreadCount: unread, lastReadInboxId: 0,
    lastReadOutboxId: 0, lastMessageSendState: 'none', typingText: '',
    lastMessageText: '', lastMessageThumb: '', lastMessageDate: 0, lastMessageId: 100 + id,
    lastSenderName: '', photoFileId: 0, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'private', isMarkedUnread: false, actionBar: '', actionBarCanUnarchive: false,
    canDeleteOnlyForSelf: false, canDeleteForAllUsers: false, isSavedMessages: false,
    background: null, themeName: '', liveGroupCallId: 0, isLive: false, isRtmpLive: false
  } as ChatEntry;
}

function snapshotOf(key: string, ids: number[], pinned: number[]): OrderSnapshot {
  return { key, ids, pinned };
}

export default function chatStoreV2Test() {
  describe('chatStoreV2', () => {
    it('列表成员来自 worker 快照，顺序照抄', 0, (): void => {
      setChatListSourceForTest(true);
      const client = new TdClient(new FakeBridge());
      const store = new ChatStore(client, new UserStore(client), timer);
      store.applyWorkerOrder([snapshotOf('main', [3, 1, 2], [1])]);
      store.compareWorkerEntries([entryOf(1, 2), entryOf(2, 0), entryOf(3, 5)]);
      const ids: string = store.getChats('main').map((e: ChatEntry): number => e.id).join(',');
      expect(ids).assertEqual('3,1,2');
      expect(store.hasChats('main')).assertTrue();
      setChatListSourceForTest(false);
    });

    it('置顶与分组归属读 worker 快照，不读本地 positions', 0, (): void => {
      setChatListSourceForTest(true);
      const client = new TdClient(new FakeBridge());
      const store = new ChatStore(client, new UserStore(client), timer);
      store.applyWorkerOrder([
        snapshotOf('main', [7, 8], [8]),
        snapshotOf('archive', [9], []),
        snapshotOf('folder:4', [8], [])
      ]);
      store.compareWorkerEntries([entryOf(7, 0), entryOf(8, 0), entryOf(9, 0)]);
      expect(store.isPinned('main', 8)).assertTrue();
      expect(store.isPinned('main', 7)).assertFalse();
      expect(store.isInFolder(4, 8)).assertTrue();
      expect(store.isInFolder(4, 7)).assertFalse();
      expect(store.isArchived(9)).assertTrue();
      expect(store.isArchived(7)).assertFalse();
      setChatListSourceForTest(false);
    });

    it('未读角标按 worker 成员 + 镜像实体统计', 0, (): void => {
      setChatListSourceForTest(true);
      const client = new TdClient(new FakeBridge());
      const store = new ChatStore(client, new UserStore(client), timer);
      store.applyWorkerOrder([snapshotOf('main', [1, 2, 3], [])]);
      store.compareWorkerEntries([entryOf(1, 2), entryOf(2, 0), entryOf(3, 4)]);
      const badge = store.unreadChatBadge('main');
      expect(badge.total).assertEqual(2);
      setChatListSourceForTest(false);
    });

    it('镜像没有的成员回退本地（V2 早期不至于空行）', 0, (): void => {
      setChatListSourceForTest(true);
      const client = new TdClient(new FakeBridge());
      const store = new ChatStore(client, new UserStore(client), timer);
      store.applyWorkerOrder([snapshotOf('main', [5], [])]);
      // 只投递了 6，没有 5：成员 5 既不在镜像也不在本地 → 列表为空是预期，
      // 一旦镜像补上就会出现。
      store.compareWorkerEntries([entryOf(6, 0)]);
      expect(store.getChats('main').length).assertEqual(0);
      store.compareWorkerEntries([entryOf(5, 0)]);
      expect(store.getChats('main').length).assertEqual(1);
      setChatListSourceForTest(false);
    });
  });
}
