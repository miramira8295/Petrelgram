import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, MessageEntry } from '../main/ets/store/MessageEntry';
import { collapseAlbums, AlbumGroup } from '../main/ets/util/collapseAlbums';
import {
  AlbumGroupDataSource, contentFingerprint, countDeferredFlips, reuseUnchangedRows,
  sameRenderSnapshot, sameRowArray
} from '../main/ets/pages/chat/AlbumGroupDataSource';
import { stageInitialMessageGroups } from '../main/ets/util/initialMessageStage';

// P4：列表已从 LazyForEach 换成 Repeat.virtualScroll，这个文件里原来那 12 个
// 用例测的是已经删掉的增量差分引擎（ADD/CHANGE/DELETE/RELOAD 通知）。留下来的
// 是 Repeat 之下仍然承重的那几个纯函数。

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

function entry(id: number, date: number, users: UserStore, text: string = ''): MessageEntry {
  const ft: TdObject = { '@type': 'formattedText' }; ft['text'] = text !== '' ? text : `t${id}`;
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

export default function albumGroupDataSourceTest() {
  describe('AlbumGroupDataSource', () => {
    it('content_fingerprint_is_stable_and_short', 0, () => {
      const a: string = contentFingerprint('hello world');
      const b: string = contentFingerprint('hello world');
      const c: string = contentFingerprint('hello worlds');
      expect(a).assertEqual(b);
      expect(a === c).assertFalse();
      expect(a.length < 8).assertTrue();
    });

    it('same_render_snapshot_ignores_nothing_that_renders', 0, () => {
      const users = usersOf();
      const first = groupsOf([[10, 100], [20, 5000]], users);
      const second = groupsOf([[10, 100], [20, 5000]], users);
      // 两次独立构造出来的行是不同对象，但渲染快照相同。
      expect(first[0] === second[0]).assertFalse();
      expect(sameRenderSnapshot(first[0], second[0])).assertTrue();
      // 首屏占位副本与真身共用 key，但渲染快照不同 —— 这正是 initialDeferred
      // 参与差分、却不进行 key 的那条语义。
      const staged = stageInitialMessageGroups(first, first.length - 1, false, 1);
      expect(staged[0].key).assertEqual(first[0].key);
      expect(sameRenderSnapshot(staged[0], first[0])).assertFalse();
    });

    it('reuse_unchanged_rows_keeps_previous_objects', 0, () => {
      const users = usersOf();
      const prev = groupsOf([[10, 100], [20, 5000], [30, 9000]], users);
      const republished = groupsOf([[10, 100], [20, 5000], [30, 9000]], users);
      const merged = reuseUnchangedRows(prev, republished);
      // 内容一个字没变 ⇒ 全部还原成上一份快照的对象，Repeat 因此一行都不刷新。
      expect(merged.length).assertEqual(3);
      expect(merged[0] === prev[0]).assertTrue();
      expect(merged[1] === prev[1]).assertTrue();
      expect(merged[2] === prev[2]).assertTrue();
      expect(sameRowArray(prev, merged)).assertTrue();
    });

    it('reuse_unchanged_rows_keeps_the_changed_row_new', 0, () => {
      const users = usersOf();
      const prev = groupsOf([[10, 100], [20, 5000]], users);
      const edited = collapseAlbums([entry(10, 100, users), entry(20, 5000, users, 'edited')]);
      const merged = reuseUnchangedRows(prev, edited);
      expect(merged[0] === prev[0]).assertTrue();
      expect(merged[1] === edited[1]).assertTrue();
      expect(sameRowArray(prev, merged)).assertFalse();
    });

    it('reuse_unchanged_rows_survives_a_prepend', 0, () => {
      const users = usersOf();
      const prev = groupsOf([[20, 5000], [30, 9000]], users);
      const withOlder = groupsOf([[10, 100], [20, 5000], [30, 9000]], users);
      const merged = reuseUnchangedRows(prev, withOlder);
      expect(merged.length).assertEqual(3);
      // 前插的那一行是新的；下移的两行按身份配对，仍然是原来的对象。
      expect(merged[0] === withOlder[0]).assertTrue();
      expect(merged[2] === prev[1]).assertTrue();
    });

    it('reuse_unchanged_rows_does_not_reuse_across_a_deferred_flip', 0, () => {
      const users = usersOf();
      const real = groupsOf([[10, 100], [20, 5000], [30, 9000]], users);
      const staged = stageInitialMessageGroups(real, real.length - 1, false, 1);
      // 占位 → 真身：翻转的那几行必须拿到新对象，否则 Repeat 判定 item 没变、
      // 屏幕上就是留在占位状态的空白行。
      const merged = reuseUnchangedRows(staged, real);
      expect(merged[0] === real[0]).assertTrue();
      expect(merged[real.length - 1] === staged[real.length - 1]).assertTrue();
    });

    it('deferred_flip_probe_counts_placeholder_admissions', 0, () => {
      const users = usersOf();
      const real = groupsOf([[10, 100], [20, 5000], [30, 9000]], users);
      const staged = stageInitialMessageGroups(real, real.length - 1, false, 1);
      // 三行里最后一行是真身，前两行是占位。
      expect(countDeferredFlips(staged, real)).assertEqual(2);
      expect(countDeferredFlips(real, real)).assertEqual(0);
      expect(countDeferredFlips([], real)).assertEqual(0);
    });

    it('prefetch_source_tracks_the_published_rows', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      expect(ds.totalCount()).assertEqual(0);
      const groups = groupsOf([[10, 100], [20, 5000]], users);
      ds.setRows(groups);
      expect(ds.totalCount()).assertEqual(2);
      expect(ds.getData(1).head.id).assertEqual(20);
      ds.setRows([]);
      expect(ds.totalCount()).assertEqual(0);
      // 纯文本行没有可预取的图片，prefetch/cancel 不该抛。
      ds.setRows(groups);
      ds.prefetch(0);
      ds.cancel(0);
      expect(ds.totalCount()).assertEqual(2);
    });
  });
}
