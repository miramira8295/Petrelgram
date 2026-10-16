import { describe, it, expect } from '@ohos/hypium';
import { ChatEntry } from '../main/ets/store/ChatEntry';
import { ChatListDataSource } from '../main/ets/pages/chatlist/ChatListDataSource';
import { chatListRowKeys, ChatListRowKeyCache } from '../main/ets/pages/chatlist/chatListRowKeys';

// 首页列表原本只要长度一变就整表 RELOAD，而滑动加载更多会话正是长度在变——
// RELOAD 让 LazyForEach 把所有行作废重建。这几条钉住：
//   追加 / 前插 / 删除 → 增量 ADD/DELETE
//   重排              → 仍然 RELOAD（刻意保留，见 update 里的注释）
//   身份不变只有内容变 → 更新可观察快照，不发会重建节点的 CHANGE

function chat(id: number): ChatEntry {
  return {
    id, revision: 0, title: `c${id}`, isMuted: false, usesDefaultMute: true, unreadCount: 0, unreadMentionCount: 0, rawUnreadCount: 0, lastReadInboxId: 0,
    lastMessageText: '', lastMessageThumb: '', lastMessageDate: 0, lastMessageId: 0, lastSenderName: '',
    photoFileId: 0, avatarPath: '', initials: '', autoDeleteTime: 0,
    kind: 'supergroup', isMarkedUnread: false, actionBar: '', actionBarCanUnarchive: false,
    canDeleteOnlyForSelf: false, canDeleteForAllUsers: false,
    isSavedMessages: false, background: null, themeName: '',
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

class KeyReadingListener extends Recording {
  private source: ChatListDataSource;
  snapshots: string[] = [];

  constructor(source: ChatListDataSource) {
    super();
    this.source = source;
  }

  onDatasetChange(operations: DataOperation[]): void {
    super.onDatasetChange(operations);
    const rows: string[] = [];
    for (let i = 0; i < this.source.totalCount(); i++) {
      rows.push(`${this.source.getData(i).id}:${this.source.getData(i).snapshot.contentKey}`);
    }
    this.snapshots.push(rows.join(','));
  }
}

function seeded(ids: number[]): ChatListDataSource {
  const ds = new ChatListDataSource();
  ds.update(chats(ids), keysOf(ids));
  return ds;
}

export default function chatListDataSourceTest() {
  describe('ChatListRowKeyCache', () => {
    it('首次键格式与原规则一致，连续单行更新不再全表查置顶', 0, () => {
      const cache = new ChatListRowKeyCache();
      let pinReads = 0;
      const pinned = (id: number): boolean => { pinReads++; return id === 1; };
      let items = chats([1, 2, 3]);
      const first = cache.keys(items, 'main', 3, 4, 0, pinned);
      expect(first.join(',')).assertEqual('1_0_1_3_4,2_0_0_3_4,3_0_0_3_4');
      for (let i = 1; i <= 20; i++) {
        items = chats([1, 2, 3]); items[1].revision = i;
        const keys = cache.keys(items, 'main', 3, 4, 0, pinned);
        expect(keys[1]).assertEqual(`2_${i}_0_3_4`);
      }
      expect(pinReads).assertEqual(3);
      expect(first.join(',')).assertEqual('1_0_1_3_4,2_0_0_3_4,3_0_0_3_4');
    });

    it('重排按身份复用键且仍发RELOAD', 0, () => {
      const cache = new ChatListRowKeyCache();
      const ds = new ChatListDataSource();
      let pinReads = 0;
      const pinned = (_id: number): boolean => { pinReads++; return false; };
      ds.update(chats([1, 2, 3]), cache.keys(chats([1, 2, 3]), 'main', 0, 0, 0, pinned));
      const rec = new Recording(); ds.registerDataChangeListener(rec);
      const next = chats([3, 1, 2]);
      ds.update(next, cache.keys(next, 'main', 0, 0, 0, pinned));
      expect(pinReads).assertEqual(3);
      expect(ds.getData(0).snapshot.contentKey).assertEqual('3_0_0_0_0');
      expect(rec.batches.join('|')).assertEqual('reload');
    });

    it('pinEpoch变化但revision不变时只刷新实际置顶变化行', 0, () => {
      const cache = new ChatListRowKeyCache(); const ds = new ChatListDataSource();
      const items = chats([1, 2]);
      ds.update(items, cache.keys(items, 'main', 0, 0, 0, (_id) => false));
      const rec = new Recording(); ds.registerDataChangeListener(rec);
      ds.update(items, cache.keys(items, 'main', 0, 0, 1, (id) => id === 2));
      expect(rec.changedIndexes.length).assertEqual(0);
      expect(ds.getData(1).snapshot.contentKey).assertEqual('2_0_1_0_0');
    });

    it('语言静音纪元变化全量换键但复用置顶查询结果', 0, () => {
      const cache = new ChatListRowKeyCache(); const ds = new ChatListDataSource();
      const items = chats([1, 2]); let reads = 0;
      const pinned = (_id: number): boolean => { reads++; return false; };
      ds.update(items, cache.keys(items, 'main', 0, 0, 0, pinned));
      const rec = new Recording(); ds.registerDataChangeListener(rec);
      ds.reload(cache.keys(items, 'main', 1, 0, 0, pinned));
      ds.reload(cache.keys(items, 'main', 1, 2, 0, pinned));
      ds.update(items, cache.keys(items, 'main', 1, 2, 0, pinned));
      expect(ds.getData(1).snapshot.contentKey).assertEqual('2_0_0_1_2');
      expect(reads).assertEqual(2);
      expect(rec.batches.join('|')).assertEqual('reload|reload');
    });

    it('同长度成员替换会清理离开会话，重入重新查置顶', 0, () => {
      const cache = new ChatListRowKeyCache(); let reads = 0;
      const pinned = (_id: number): boolean => { reads++; return false; };
      cache.keys(chats([1, 2]), 'main', 0, 0, 0, pinned);
      cache.keys(chats([1, 3]), 'main', 0, 0, 0, pinned);
      expect(reads).assertEqual(3);
      cache.keys(chats([1, 2]), 'main', 0, 0, 0, pinned);
      expect(reads).assertEqual(4);
    });

    it('空列表清空缓存，重新填充不会沿用旧置顶', 0, () => {
      const cache = new ChatListRowKeyCache();
      cache.keys(chats([1]), 'main', 0, 0, 0, (_id) => true);
      expect(cache.keys([], 'main', 0, 0, 0, (_id) => false).length).assertEqual(0);
      expect(cache.keys(chats([1]), 'main', 0, 0, 0, (_id) => false)[0]).assertEqual('1_0_0_0_0');
    });

    it('不同列表相同置顶纪元不会串缓存，销毁清理后重新取值', 0, () => {
      const cache = new ChatListRowKeyCache(); const items = chats([1]);
      cache.keys(items, 'main', 0, 0, 0, (_id) => true);
      expect(cache.keys(items, 'folder:9', 0, 0, 0, (_id) => false)[0]).assertEqual('1_0_0_0_0');
      cache.clear();
      expect(cache.keys(items, 'folder:9', 0, 0, 0, (_id) => true)[0]).assertEqual('1_0_1_0_0');
    });

    it('追加与删除夹带内容变化仍使用正确的新下标和键', 0, () => {
      const cache = new ChatListRowKeyCache(); const ds = new ChatListDataSource();
      const pin = (_id: number): boolean => false;
      const initial = chats([1, 3]); ds.update(initial, cache.keys(initial, 'main', 0, 0, 0, pin));
      const rec = new KeyReadingListener(ds); ds.registerDataChangeListener(rec);
      const added = chats([1, 2, 3]); added[2].revision = 1;
      ds.update(added, cache.keys(added, 'main', 0, 0, 0, pin));
      expect(rec.batches.join('|')).assertEqual('add');
      expect(rec.changedIndexes.length).assertEqual(0);
      expect(rec.addedKeys.join(',')).assertEqual('2_0');
      const removed = chats([2, 3]); removed[0].revision = 1; removed[1].revision = 1;
      ds.update(removed, cache.keys(removed, 'main', 0, 0, 0, pin));
      expect(rec.batches.join('|')).assertEqual('add|delete');
      expect(rec.changedIndexes.length).assertEqual(0);
      expect(ds.getData(0).snapshot.contentKey).assertEqual('2_1_0_0_0');
    });

    it('冻结后的旧修订与最新修订交替发布仍各自生成正确键', 0, () => {
      const cache = new ChatListRowKeyCache(); const old = chats([1]); const fresh = chats([1]);
      fresh[0].revision = 5;
      cache.keys(fresh, 'main', 0, 0, 0, (_id) => false);
      expect(cache.keys(old, 'main', 1, 0, 0, (_id) => false)[0]).assertEqual('1_0_0_1_0');
      expect(cache.keys(fresh, 'main', 1, 0, 0, (_id) => false)[0]).assertEqual('1_5_0_1_0');
    });

    it('混合增删重排内容和规则变化与原全量算法逐轮一致', 0, () => {
      const cache = new ChatListRowKeyCache(); let seed = 12345;
      let ids: number[] = [1, 2, 3, 4, 5]; let nextId = 6;
      let pinEpoch = 0; let language = 0; let mute = 0;
      const revisions: Map<number, number> = new Map(); const pins: Set<number> = new Set();
      for (let turn = 0; turn < 240; turn++) {
        seed = (seed * 16807) % 2147483647;
        const index = seed % ids.length;
        switch (turn % 6) {
          case 0: revisions.set(ids[index], (revisions.get(ids[index]) ?? 0) + 1); break;
          case 1: ids = [ids[ids.length - 1], ...ids.slice(0, -1)]; break;
          case 2: ids.splice(index, 1, nextId++); break;
          case 3:
            if (pins.has(ids[index])) { pins.delete(ids[index]); } else { pins.add(ids[index]); }
            pinEpoch++; break;
          case 4: language++; break;
          case 5: mute++; break;
        }
        const items = ids.map((id: number): ChatEntry => { const row = chat(id); row.revision = revisions.get(id) ?? 0; return row; });
        const pin = (id: number): boolean => pins.has(id);
        expect(cache.keys(items, 'main', language, mute, pinEpoch, pin).join(','))
          .assertEqual(chatListRowKeys(items, language, mute, pin).join(','));
      }
    });
  });

  describe('ChatListDataSource', () => {
    it('内容刷新保留行对象和身份键，只替换变化行快照', 0, () => {
      const ds = seeded([1, 2]); const first = ds.getData(0); const second = ds.getData(1);
      const snapshot = first.snapshot; const oldSecond = second.snapshot; const identity = ds.getKey(1);
      const next = chats([1, 2]); next[1].revision = 1;
      next[1].title = 'new title'; next[1].lastMessageText = 'new text';
      next[1].unreadCount = 8; next[1].unreadMentionCount = 2;
      next[1].avatarPath = '/new/avatar'; next[1].lastMessageThumb = 'new thumb'; next[1].isLive = true;
      ds.update(next, keysOf([1, 2], 2));
      expect(ds.getData(0) === first).assertTrue(); expect(first.snapshot === snapshot).assertTrue();
      expect(ds.getData(1) === second).assertTrue(); expect(second.snapshot === oldSecond).assertFalse();
      expect(ds.getKey(1)).assertEqual(identity); expect(second.snapshot.chat === next[1]).assertTrue();
      expect(second.snapshot.chat.unreadMentionCount).assertEqual(2);
      expect(second.snapshot.chat.avatarPath).assertEqual('/new/avatar');
      expect(oldSecond.chat.unreadCount).assertEqual(0);
    });

    it('更新与重排同时发生，旧行引用和身份键继续指向同一会话', 0, () => {
      const ds = seeded([1, 2, 3]); const row = ds.getData(2); const identity = ds.getKey(2);
      const next = chats([3, 1, 2]); next[0].lastMessageText = 'moved'; next[0].revision = 4;
      ds.update(next, keysOf([3, 1, 2], 3));
      expect(ds.getData(0) === row).assertTrue(); expect(ds.getKey(0)).assertEqual(identity);
      expect(row.snapshot.chat.lastMessageText).assertEqual('moved');
    });

    it('置顶变化不增加revision也能替换可观察快照', 0, () => {
      const ds = seeded([1]); const row = ds.getData(0); const before = row.snapshot;
      const key = ds.getKey(0); ds.update(chats([1]), ['pin-changed']);
      expect(row.snapshot === before).assertFalse(); expect(row.snapshot.chat.revision).assertEqual(0);
      expect(ds.getKey(0)).assertEqual(key);
    });

    it('语言静音强制刷新更换身份代次，后续内容发布不撤销代次', 0, () => {
      const ds = seeded([1]); const row = ds.getData(0); const oldKey = ds.getKey(0);
      ds.reload(['context-1']); const first = ds.getKey(0);
      expect(first === oldKey).assertFalse(); expect(ds.getData(0) === row).assertTrue();
      ds.update(chats([1]), ['context-1']); expect(ds.getKey(0)).assertEqual(first);
      ds.reload(['context-2']); expect(ds.getKey(0) === first).assertFalse();
    });

    it('移出后重入创建新持有者，旧回调不会读到重入会话的新状态', 0, () => {
      const ds = seeded([1, 2]); const removed = ds.getData(0);
      ds.update(chats([2]), keysOf([2]));
      const next = chats([1, 2]); next[0].lastMessageId = 99;
      ds.update(next, ['new1', 'k2']);
      expect(ds.getData(0) === removed).assertFalse();
      expect(removed.snapshot.chat.lastMessageId).assertEqual(0);
      expect(ds.getData(0).snapshot.chat.lastMessageId).assertEqual(99);
    });

    it('内容更新后延迟执行的行操作读取最新消息水位', 0, () => {
      const ds = seeded([1]); const row = ds.getData(0);
      const readLater = (): number => row.snapshot.chat.lastMessageId;
      const next = chats([1]); next[0].lastMessageId = 800; next[0].unreadCount = 3;
      ds.update(next, ['changed']); expect(readLater()).assertEqual(800);
    });

    it('未发布的Store快照不能改变已显示的可观察行', 0, () => {
      const ds = seeded([1]); const row = ds.getData(0);
      const pending = chats([1]); pending[0].revision = 1; pending[0].lastMessageText = 'pending';
      expect(row.snapshot.chat.lastMessageText).assertEqual('');
      ds.update(pending, ['published']); expect(row.snapshot.chat.lastMessageText).assertEqual('pending');
    });

    it('同一会话在两个列表有独立冻结快照与置顶签名', 0, () => {
      const main = seeded([1]); const folder = seeded([1]);
      const pending = chats([1]); pending[0].unreadCount = 4;
      main.update(pending, ['main-changed']);
      expect(main.getData(0) === folder.getData(0)).assertFalse();
      expect(folder.getData(0).snapshot.chat.unreadCount).assertEqual(0);
      folder.update(pending, ['folder-pinned']);
      expect(folder.getData(0).snapshot.contentKey).assertEqual('folder-pinned');
      expect(main.getData(0).snapshot.contentKey).assertEqual('main-changed');
    });

    it('结构通知的新增身份键与回调读取键一致', 0, () => {
      const ds = seeded([1]); ds.reload(['lang']);
      const rec = new Recording(); ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2]), ['lang', 'new2']);
      expect(rec.addedKeys[0]).assertEqual(ds.getKey(1));
    });

    it('空表清理后重填不保留之前的可观察对象', 0, () => {
      const ds = seeded([1]); const old = ds.getData(0);
      ds.update([], []); ds.update(chats([1]), ['k1']);
      expect(ds.getData(0) === old).assertFalse();
    });

    it('行键保留身份修订置顶语言静音语义', 0, () => {
      const items = chats([1, 2]);
      items[0].revision = 9;
      const keys = chatListRowKeys(items, 3, 4, (id: number): boolean => id === 1);
      expect(keys.join(',')).assertEqual('1_9_1_3_4,2_0_0_3_4');
      // 同一会话在不同列表的置顶状态独立。
      const folderKeys = chatListRowKeys(items, 3, 4, (_id: number): boolean => false);
      expect(folderKeys[0]).assertEqual('1_9_0_3_4');
    });

    it('LazyForEach读取发布键不会反复查询置顶状态', 0, () => {
      const ds = new ChatListDataSource();
      let pinReads: number = 0;
      let pinned: boolean = false;
      const items = chats([1, 2]);
      ds.update(items, chatListRowKeys(items, 0, 0, (_id: number): boolean => {
        pinReads++;
        return pinned;
      }));
      pinned = true;
      for (let i = 0; i < 20; i++) {
        expect(ds.getData(i % 2).snapshot.contentKey).assertEqual(`${i % 2 + 1}_0_0_0_0`);
      }
      expect(pinReads).assertEqual(2);
    });

    it('更新通知发出之前快照和键已同步可读', 0, () => {
      const ds = new ChatListDataSource();
      const rec = new KeyReadingListener(ds);
      ds.registerDataChangeListener(rec);
      ds.update(chats([7, 8]), ['first7', 'first8']);
      ds.update(chats([8, 7]), ['second8', 'second7']);
      expect(rec.snapshots.join('|')).assertEqual('7:first7,8:first8|8:second8,7:second7');
    });

    it('语言切换刷新缓存键并保留RELOAD，下一次相同发布不重复CHANGE', 0, () => {
      const ds = new ChatListDataSource();
      const items = chats([1, 2]);
      ds.update(items, chatListRowKeys(items, 0, 0, (_id: number): boolean => false));
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.reload(chatListRowKeys(items, 1, 0, (_id: number): boolean => false));
      expect(ds.getData(0).snapshot.contentKey).assertEqual('1_0_0_1_0');
      expect(rec.batches.join('|')).assertEqual('reload');
      ds.update(items, chatListRowKeys(items, 1, 0, (_id: number): boolean => false));
      expect(rec.batches.join('|')).assertEqual('reload');
    });

    it('静音规则切换即使没有新消息也更新行键', 0, () => {
      const ds = new ChatListDataSource();
      const items = chats([1]);
      ds.update(items, chatListRowKeys(items, 0, 0, (_id: number): boolean => false));
      const rec = new KeyReadingListener(ds);
      ds.registerDataChangeListener(rec);
      ds.reload(chatListRowKeys(items, 0, 1, (_id: number): boolean => false));
      expect(rec.snapshots.join('|')).assertEqual('1:1_0_0_0_1');
      expect(ds.getData(0).snapshot.chat === items[0]).assertTrue();
    });

    it('空快照与重新填充后数据和缓存键一致', 0, () => {
      const ds = seeded([1]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update([], []);
      expect(ds.totalCount()).assertEqual(0);
      ds.reload([]);
      ds.update(chats([2]), ['new2']);
      expect(ds.totalCount()).assertEqual(1);
      expect(ds.getData(0).id).assertEqual(2);
      expect(ds.getData(0).snapshot.contentKey).assertEqual('new2');
      expect(rec.batches.join('|')).assertEqual('delete|reload|add');
    });

    it('仅置顶状态变化更新快照但不通知CHANGE', 0, () => {
      const ds = new ChatListDataSource();
      const items = chats([1, 2]);
      ds.update(items, chatListRowKeys(items, 0, 0, (_id: number): boolean => false));
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(items, chatListRowKeys(items, 0, 0, (id: number): boolean => id === 2));
      expect(rec.batches.join('|')).assertEqual('');
      expect(rec.changedIndexes.length).assertEqual(0);
      expect(ds.getData(1).snapshot.contentKey).assertEqual('2_0_1_0_0');
    });

    it('新消息修订只刷新对应行且保持普通快照引用', 0, () => {
      const ds = new ChatListDataSource();
      const before = chats([1, 2]);
      ds.update(before, chatListRowKeys(before, 0, 0, (_id: number): boolean => false));
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      const next = chats([1, 2]);
      next[1].revision = 1;
      next[1].unreadCount = 3;
      ds.update(next, chatListRowKeys(next, 0, 0, (_id: number): boolean => false));
      expect(rec.changedIndexes.length).assertEqual(0);
      expect(ds.getData(1).snapshot.chat === next[1]).assertTrue();
      expect(ds.getData(1).snapshot.chat.unreadCount).assertEqual(3);
      expect(before[1].revision).assertEqual(0);
    });

    it('追加一页只发 ADD，不整表 RELOAD', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3, 4, 5]), keysOf([1, 2, 3, 4, 5]));
      expect(rec.batches.join('|')).assertEqual('add');
      expect(rec.addedKeys.join(',')).assertEqual('4_0,5_0');
    });

    it('顶部插入一条新会话也是 ADD', 0, () => {
      const ds = seeded([2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3]), keysOf([1, 2, 3]));
      expect(rec.batches.join('|')).assertEqual('add');
      expect(rec.addedKeys.join(',')).assertEqual('1_0');
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

    it('身份不变、只有内容变时不发重建通知', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3]), keysOf([1, 2, 3], 2));
      expect(rec.batches.join('|')).assertEqual('');
      expect(rec.changedIndexes.length).assertEqual(0);
    });

    it('什么都没变时一条通知都不发', 0, () => {
      const ds = seeded([1, 2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3]), keysOf([1, 2, 3]));
      expect(rec.batches.length).assertEqual(0);
    });

    it('插入夹带幸存行内容变化时只发结构通知', 0, () => {
      // 幸存行通过稳定对象拿到新快照，不再依赖CHANGE的下标语义。
      const ds = seeded([2, 3]);
      const rec = new Recording();
      ds.registerDataChangeListener(rec);
      ds.update(chats([1, 2, 3]), keysOf([1, 2, 3], 3));
      expect(rec.batches.join('|')).assertEqual('add');
      expect(ds.getData(2).snapshot.contentKey).assertEqual('k3_v2');
      expect(rec.changedIndexes.length).assertEqual(0);
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
