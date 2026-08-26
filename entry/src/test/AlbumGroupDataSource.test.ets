import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { collapseAlbums, AlbumGroup } from '../main/ets/util/collapseAlbums';
import { AlbumGroupDataSource, contentFingerprint } from '../main/ets/pages/chat/AlbumGroupDataSource';
import { stageInitialMessageGroups } from '../main/ets/util/initialMessageStage';

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
    it('initial_placeholder_reveal_changes_without_renaming_row', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      const source = groupsOf([[10, 100], [20, 5000], [30, 90000]], users);
      ds.update(stageInitialMessageGroups(source, 2, false, 0));

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      expect(ds.update(stageInitialMessageGroups(source, 2, false, 1)))
        .assertEqual('incremental');
      expect(listener.batches.join('|')).assertEqual('change');
      // No replacement key: placeholder and real content are the same item.
      expect(listener.changeKeys.length).assertEqual(0);
      expect(listener.ops.length).assertEqual(1);
      expect(listener.ops[0]).assertEqual(2);
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

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      // A loadAround jump replaces the window with unrelated rows (different
      // row count, no shared prefix/suffix) — the only case that reloads.
      expect(ds.update(groupsOf([[50, 100], [60, 5000], [70, 90000]], users)))
        .assertEqual('reload');
      // 没有 deferred 翻转时不能顺手补发 CHANGE：整表 RELOAD 已经重建了一切，
      // 再补一批就是这个文件 :283 记着的老毛病（把整段无关的行一起重建）。
      expect(listener.batches.length).assertEqual(1);
      expect(listener.batches[0]).assertEqual('reload');
      expect(listener.ops.length).assertEqual(0);
    });

    // 本次 bug 的核心。收尾那一次发布同时携带「结构增删」和「一批
    // deferred→真身的翻转」。RELOAD 的契约是"key 未变 → 沿用原组件"，而
    // initialDeferred 刻意不进 key，于是占位 Column 被原地留下；同时
    // this.groups 已经换成真身，此后再不会对这一行发 CHANGE —— 屏幕上就是
    // 一条占着高度、连气泡背景都没有的空白行，滑出去再回来才自愈。
    // RELOAD 之后必须对真正翻转的那些行补发定向的无 key CHANGE。
    it('reload_with_structural_edit_republishes_deferred_flips', 0, () => {
      const users = usersOf();
      // 日期彼此远隔，每行自成一个发送者 run、各带各的日期胶囊 —— 删掉中间
      // 一行不会改动邻行的 key，测的就是 deferred 翻转本身。
      const layout: number[][] =
        [[10, 100], [20, 90000], [30, 180000], [40, 270000], [50, 360000]];
      const real = groupsOf(layout, users);
      // 只有末行是真身的那份 staged，用来按下标取占位副本。
      const staged = stageInitialMessageGroups(real, 4, false, 1);

      const ds = new AlbumGroupDataSource();
      // [占位10, 真身20, 占位30, 占位40, 真身50]
      ds.update([staged[0], real[1], staged[2], staged[3], real[4]]);

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      // 收尾形状：行 30 消失（结构增删）+ 剩下的占位全部翻成真身。
      // newMid < oldMid，没有任何对齐分支，一律落到兜底 RELOAD。
      expect(ds.update([real[0], real[1], real[3], real[4]])).assertEqual('reload');

      // RELOAD 单独一批，补发的 CHANGE 跟在后面 —— 不混批。
      expect(listener.batches.length).assertEqual(2);
      expect(listener.batches[0]).assertEqual('reload');
      expect(listener.batches[1]).assertEqual('change,change');
      // 只有真正翻转的两行：行 10（新下标 0）和行 40（新下标 2）。
      expect(listener.ops.length).assertEqual(2);
      expect(listener.ops[0]).assertEqual(0);
      expect(listener.ops[1]).assertEqual(2);
      // 行 20 前后都是真身，没被顺手 CHANGE。
      expect(listener.ops.indexOf(1)).assertEqual(-1);
      // 无 key：占位和真身是同一个 item，key 本来就没变（这正是 RELOAD 漏掉
      // 它的原因）。带 key 会让框架把这个 key 重新注册一遍。
      expect(listener.changeKeys.length).assertEqual(0);
    });

    // 另一个 RELOAD 出口：中段等长但每个下标都换了身份。补发同样要覆盖。
    it('reload_at_identity_shift_republishes_deferred_flips', 0, () => {
      const users = usersOf();
      const before =
        groupsOf([[10, 100], [20, 90000], [30, 180000], [40, 270000]], users);
      const ds = new AlbumGroupDataSource();
      // [占位10, 占位20, 占位30, 真身40]
      ds.update(stageInitialMessageGroups(before, 3, false, 1));

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      // 整窗右移一格：长度不变、每个下标都换了身份（oldMid === newMid > 1），
      // 同时行 20/30 从占位翻成真身。
      const after =
        groupsOf([[20, 90000], [30, 180000], [40, 270000], [50, 360000]], users);
      expect(ds.update(after)).assertEqual('reload');

      expect(listener.batches.length).assertEqual(2);
      expect(listener.batches[0]).assertEqual('reload');
      expect(listener.batches[1]).assertEqual('change,change');
      // 行 20 → 新下标 0，行 30 → 新下标 1。行 40 前后都是真身、行 50 是新
      // 行（旧快照里根本没有），都不补发。
      expect(listener.ops.length).assertEqual(2);
      expect(listener.ops[0]).assertEqual(0);
      expect(listener.ops[1]).assertEqual(1);
      expect(listener.changeKeys.length).assertEqual(0);
    });

    // 回归保护：只有翻转、没有结构变化时行为必须一字不变 —— 仍走逐行 CHANGE，
    // 不能因为这次修改而退化成 RELOAD。
    it('pure_deferred_flip_without_structural_edit_stays_incremental', 0, () => {
      const users = usersOf();
      const real =
        groupsOf([[10, 100], [20, 90000], [30, 180000], [40, 270000]], users);
      const ds = new AlbumGroupDataSource();
      ds.update(stageInitialMessageGroups(real, 3, false, 1));

      const listener: RecordingListener = new RecordingListener();
      ds.registerDataChangeListener(listener);

      expect(ds.update(real)).assertEqual('incremental');
      expect(listener.batches.join('|')).assertEqual('change,change,change');
      expect(listener.ops.length).assertEqual(3);
      expect(listener.ops[0]).assertEqual(0);
      expect(listener.ops[1]).assertEqual(1);
      expect(listener.ops[2]).assertEqual(2);
      expect(listener.changeKeys.length).assertEqual(0);
    });
  });
}
