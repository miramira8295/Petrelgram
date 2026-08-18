import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { collapseAlbums, AlbumGroup } from '../main/ets/util/collapseAlbums';
import { AlbumGroupDataSource, contentFingerprint } from '../main/ets/pages/chat/AlbumGroupDataSource';

class FakeBridge implements TdBridge {
  onReceive: (json: string) => void = (): void => {};
  sent: string[] = [];
  init(cb: (json: string) => void): void { this.onReceive = cb; }
  send(json: string): void { this.sent.push(json); }
}

function usersOf(): UserStore {
  const b = new FakeBridge(); const c = new TdClient(b); const u = new UserStore(c); c.start();
  const user: TdObject = { '@type': 'user' }; user['id'] = 7; user['first_name'] = 'Ann';
  const upd: TdObject = { '@type': 'updateUser' }; upd['user'] = user;
  b.onReceive(JSON.stringify(upd));
  return u;
}

function entry(id: number, date: number, users: UserStore): MessageEntry {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = `t${id}`;
  const c: TdObject = { '@type': 'messageText' }; c['text'] = ft;
  const sender: TdObject = { '@type': 'messageSenderUser' }; sender['user_id'] = 7;
  const m: TdObject = { '@type': 'message' };
  m['id'] = id; m['is_outgoing'] = false; m['sender_id'] = sender;
  m['date'] = date; m['content'] = c;
  return buildMessageEntry(m, users);
}

function groupsOf(idsAndDates: number[][], users: UserStore): AlbumGroup[] {
  const entries: MessageEntry[] = [];
  for (const pair of idsAndDates) {
    entries.push(entry(pair[0], pair[1], users));
  }
  return collapseAlbums(entries);
}

// Captures the indexes the data source actually raises CHANGE for.
class RecordingListener implements DataChangeListener {
  ops: number[] = [];
  // One entry per onDatasetChange call, naming the op types it carried — so a
  // test can assert that structure and content arrive as SEPARATE batches.
  batches: string[] = [];
  // DataChangeListener carries both the current names and their deprecated
  // predecessors; a class has to satisfy all of them.
  onDataReloaded(): void {}
  onDataAdd(_index: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDelete(_index: number): void {}
  onDataChange(_index: number): void {}
  onDataAdded(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataChanged(_index: number): void {}
  // Keys carried by ADD operations, in order (whole array per ADD).
  keys: string[] = [];
  // Keys carried by CHANGE operations. Each must be a NEW key (content
  // fingerprint changed) — passing a key identical to the registered one made
  // the framework re-register the entry against itself and mis-reuse the node.
  changeKeys: string[] = [];
  onDatasetChange(operations: DataOperation[]): void {
    const kinds: string[] = [];
    for (const op of operations) {
      if (op.type === DataOperationType.ADD) {
        const addKey = (op as DataAddOperation).key;
        if (typeof addKey === 'string') {
          this.keys.push(addKey as string);
        } else if (addKey !== undefined) {
          for (const k of addKey as string[]) {
            this.keys.push(k);
          }
        }
      } else if (op.type === DataOperationType.CHANGE) {
        const changeKey = (op as DataChangeOperation).key;
        if (changeKey !== undefined) {
          this.changeKeys.push(changeKey);
        }
      }
      kinds.push(op.type === DataOperationType.CHANGE ? 'change'
        : (op.type === DataOperationType.ADD ? 'add'
          : (op.type === DataOperationType.RELOAD ? 'reload' : 'other')));
      if (op.type === DataOperationType.CHANGE) {
        this.ops.push((op as DataChangeOperation).index);
      }
    }
    this.batches.push(kinds.join(','));
  }
}

export default function albumGroupDataSourceTest() {
  describe('AlbumGroupDataSource', () => {
    it('identical_update_reports_none', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      const groups = groupsOf([[10, 100], [20, 5000]], users);
      ds.update(groups);
      expect(ds.update(groupsOf([[10, 100], [20, 5000]], users))).assertEqual('none');
    });
    it('older_page_prepend_reports_incremental', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      // Dates far apart so each message is its own visual run and a prepend
      // still mutates the old first row's key (date pill/run flags), the
      // normal mixed CHANGE+ADD page case.
      ds.update(groupsOf([[30, 90000], [40, 180000]], users));
      const next = groupsOf([[10, 100], [20, 5000], [30, 90000], [40, 180000]], users);
      expect(ds.update(next)).assertEqual('incremental');
    });
    // Two rows changing far apart must not drag every row between them into
    // the notification. That is what made unrelated photos and inline emoji
    // flicker for as long as anything on the page was still downloading.
    it('only_changed_rows_are_notified', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      const layout: number[][] = [[10, 100], [20, 5000], [30, 90000], [40, 180000], [50, 270000]];
      ds.update(groupsOf(layout, users));

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      // Same rows, but the first and last carry a new signature — the shape a
      // pair of in-flight downloads produces.
      const next = groupsOf(layout, users);
      next[0].key = `${next[0].key}_changed`;
      next[4].key = `${next[4].key}_changed`;
      expect(ds.update(next)).assertEqual('incremental');

      const recorded: number[] = listener.ops;
      expect(recorded.length).assertEqual(2);
      expect(recorded[0]).assertEqual(0);
      expect(recorded[1]).assertEqual(4);
    });
    // A delete plus an append leaves the length unchanged but puts a different
    // message at those indexes. Reporting that as CHANGE told the list the
    // items were the same, and their LazyForEach keys then collided with the
    // ones still registered elsewhere ("Use repeat key" in the device log,
    // rows rendering someone else's content).
    // 发送成功：TDLib 的 updateMessageSendSucceeded 让 store 删掉临时 id 那条、
    // 插入真实 id 那条，位置不变、其余行的 key 和下标都不动，只有这一格换了
    // 身份。整表 RELOAD 会让所有行销毁重建，界面上就是发消息时“闪一下”、
    // 入场动画播第二遍。中段只有一行时按 CHANGE + 新 key 处理即可。
    it('single_row_identity_swap_changes_instead_of_reloading', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      ds.update(groupsOf([[10, 100], [20, 5000], [30, 90000]], users));

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      // 末行 30（临时 id）换成 31（真实 id），其余两行原样。
      expect(ds.update(groupsOf([[10, 100], [20, 5000], [31, 90000]], users)))
        .assertEqual('incremental');
      expect(listener.batches.join('|')).assertEqual('change');
      expect(listener.changeKeys.length).assertEqual(1);
      // 交出去的必须是新身份的 key，不是那个已经注册过的旧 key。
      expect(listener.changeKeys[0].startsWith('message_group_31_')).assertTrue();
    });

    // 与上一条的分界：中段不止一行时仍然整表重建。删一条又追加一条会让每个
    // 下标都坐着别人，那时报 CHANGE 就是在骗框架说身份没变。
    it('identity_shift_at_same_length_reloads', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      ds.update(groupsOf([[10, 100], [20, 5000], [30, 90000]], users));
      // 10 dropped, 40 appended — still three rows.
      expect(ds.update(groupsOf([[20, 5000], [30, 90000], [40, 180000]], users)))
        .assertEqual('reload');
    });
    // A prepend also mutates the old first row (its date pill moves away), and
    // that used to go out as one mixed CHANGE+ADD batch whose indexes both
    // referred to the pre-insert array — while the insert was shifting them.
    // Structure and content must be separate notifications, ADD first, and the
    // CHANGE index must be the row's position AFTER the insert.
    it('prepend_notifies_add_before_change_with_post_insert_index', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      ds.update(groupsOf([[30, 90000], [40, 180000]], users));

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      // Two older messages from the SAME day arrive in front, so the date pill
      // moves off row 30 onto row 10 and row 30's key changes with it. (Older
      // messages from a different day would leave row 30's pill in place and
      // produce no CHANGE at all — which is what the first version of this test
      // accidentally set up.)
      expect(ds.update(groupsOf([[10, 87000], [20, 88000], [30, 90000], [40, 180000]], users)))
        .assertEqual('incremental');

      // ADD arrives on its own, before any CHANGE.
      expect(listener.batches.length).assertEqual(2);
      expect(listener.batches[0]).assertEqual('add');
      // The changed row was at index 0 and is at index 2 after the insert.
      expect(listener.ops[0]).assertEqual(2);
    });
    // Operations must name the keys of the rows they affect, and a CHANGE's
    // key must be a genuinely NEW key. The LazyForEach key embeds the content
    // fingerprint precisely so that a changed row's key changes — reload's
    // contract is "key unchanged -> original component reused", which is how
    // stale nodes were resurrected wearing a neighbor's content.
    it('operations_carry_fresh_row_keys', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      const before = groupsOf([[30, 90000], [40, 180000]], users);
      ds.update(before);
      // Row 30's key as the framework knows it, from the DEFAULT builder.
      const oldRow30Key =
        `message_group_30_30_${contentFingerprint(before[0].key)}`;

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      // Same shape as the prepend test: two same-day messages in front, so the
      // ADD covers rows 10 and 20 and the CHANGE covers row 30 (its date pill
      // moves onto row 10).
      expect(ds.update(groupsOf([[10, 87000], [20, 88000], [30, 90000], [40, 180000]], users)))
        .assertEqual('incremental');

      expect(listener.keys.length).assertEqual(2);
      expect(listener.keys[0].startsWith('message_group_10_')).assertTrue();
      expect(listener.keys[1].startsWith('message_group_20_')).assertTrue();
      expect(listener.changeKeys.length).assertEqual(1);
      expect(listener.changeKeys[0].startsWith('message_group_30_')).assertTrue();
      // The fingerprint moved with the content: never the already-registered key.
      expect(listener.changeKeys[0] === oldRow30Key).assertFalse();
    });
    it('window_replacement_reports_reload', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      ds.update(groupsOf([[10, 100], [20, 5000], [30, 90000], [40, 180000]], users));
      // A loadAround jump replaces the window with unrelated rows (different
      // row count, no shared prefix/suffix) — the only case that reloads.
      expect(ds.update(groupsOf([[50, 100], [60, 5000], [70, 90000]], users)))
        .assertEqual('reload');
    });
  });
}
