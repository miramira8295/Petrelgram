import { describe, it, expect } from '@ohos/hypium';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import { ChatListDataSource } from '../main/ets/pages/chatlist/ChatListDataSource';

// 首页列表原本只要长度一变就整表 RELOAD，而滑动加载更多会话正是长度在变——
// RELOAD 让 LazyForEach 把所有行作废重建。这几条钉住：
//   追加 / 前插 / 删除 → 增量 ADD/DELETE
//   重排              → 仍然 RELOAD（刻意保留，见 update 里的注释）
//   身份不变只有内容变 → 只对变了的行发 CHANGE

function chat(id: number): ChatEntry {
  return {
    id, revision: 0, title: `c${id}`, isMuted: false, usesDefaultMute: true, unreadCount: 0,
    lastMessageText: '', lastMessageDate: 0, lastMessageId: 0, lastSenderName: '',
    photoFileId: 0, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'supergroup', isMarkedUnread: false, background: null, themeName: '',
    liveGroupCallId: 0, isLive: false, isRtmpLive: false
  };
}

function chats(ids: number[]): ChatEntry[] {
  return ids.map((id: number): ChatEntry => chat(id));
}

// 默认按 id 生成 key；传 bump 可以在不改身份的前提下让某一行的内容签名变化。
function keysOf(ids: number[], bump: number = -1): string[] {
  return ids.map((id: number): string => id === bump ? `k${id}_v2` : `k${id}`);
}

class Recording implements DataChangeListener {
  batches: string[] = [];
  addedKeys: string[] = [];
  changedIndexes: number[] = [];
  deleted: number[] = [];
  onDataReloaded(): void {}
  onDataAdd(_index: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDelete(_index: number): void {}
  onDataChange(_index: number): void {}
  onDataAdded(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDatasetChange(operations: DataOperation[]): void {
    const kinds: string[] = [];
    for (const op of operations) {
      if (op.type === DataOperationType.ADD) {
        kinds.push('add');
        const k = (op as DataAddOperation).key;
        if (k !== undefined) {
          for (const one of k as string[]) {
            this.addedKeys.push(one);
          }
        }
      } else if (op.type === DataOperationType.DELETE) {
        kinds.push('delete');
        this.deleted.push((op as DataDeleteOperation).count ?? 0);
      } else if (op.type === DataOperationType.CHANGE) {
        kinds.push('change');
        this.changedIndexes.push((op as DataChangeOperation).index);
      } else if (op.type === DataOperationType.RELOAD) {
        kinds.push('reload');
      }
    }
    this.batches.push(kinds.join(','));
  }
}

function seeded(ids: number[]): ChatListDataSource {
  const ds = new ChatListDataSource();
  ds.update(chats(ids), keysOf(ids));
  return ds;
}

export default function chatListDataSourceTest() {
  describe('ChatListDataSource', () => {
    it('追加一页只发 ADD，不整表 RELOAD', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3, 4, 5]), keysOf([1, 2, 3, 4, 5]));
      expect(rec.batches.join('|')).assertEqual('add');
      expect(rec.addedKeys.join(',')).assertEqual('k4,k5');
    });

    it('顶部插入一条新会话也是 ADD', 0, () => {
      const ds = seeded([2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3]), keysOf([1, 2, 3]));
      expect(rec.batches.join('|')).assertEqual('add');
      expect(rec.addedKeys.join(',')).assertEqual('k1');
    });

    it('删除中间一条只发 DELETE', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 3]), keysOf([1, 3]));
      expect(rec.batches.join('|')).assertEqual('delete');
      expect(rec.deleted.join(',')).assertEqual('1');
    });

    it('重排仍然 RELOAD——CHANGE 的语义对不上，之前踩过', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([3, 1, 2]), keysOf([3, 1, 2]));
      expect(rec.batches.join('|')).assertEqual('reload');
    });

    it('身份不变、只有内容变时只发变了的那一行', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3]), keysOf([1, 2, 3], 2));
      expect(rec.batches.join('|')).assertEqual('change');
      expect(rec.changedIndexes.join(',')).assertEqual('1');
    });

    it('什么都没变时一条通知都不发', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3]), keysOf([1, 2, 3]));
      expect(rec.batches.length).assertEqual(0);
    });

    it('插入与幸存行的内容变化分成两批发，且内容通知用插入后的下标', 0, () => {
      // 结构与内容混在一批里，ADD 会一边移动后续下标、CHANGE 又按原下标定位。
      const ds = seeded([2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3]), keysOf([1, 2, 3], 3));
      expect(rec.batches.join('|')).assertEqual('add|change');
      // 3 在新列表里是下标 2，不是旧列表里的 1。
      expect(rec.changedIndexes.join(',')).assertEqual('2');
    });

    it('首次填充走 ADD 而不是 RELOAD', 0, () => {
      const ds = new ChatListDataSource();
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2]), keysOf([1, 2]));
      expect(rec.batches.join('|')).assertEqual('add');
    });
  });
}
