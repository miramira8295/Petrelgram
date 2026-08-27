import { describe, it, expect } from '@ohos/hypium';
import { TdClient } from '../main/ets/tdkit/TdClient';
import { TdObject, TdBridge } from '../main/ets/tdkit/TdTypes';
import { UserStore } from '../main/ets/store/UserStore';
import { buildMessageEntry, cloneMessage, MessageEntry } from '../main/ets/store/MessageEntry';
import { collapseAlbums, AlbumGroup } from '../main/ets/util/collapseAlbums';
import {
  AlbumGroupDataSource, clampPrefetchRange, contentFingerprint, countDeferredFlips,
  appendBreaksAnchor, PrefetchRange, prependBreaksAnchor, reuseUnchangedRows, sameRenderSnapshot,
  sameRowArray
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

// BasicPrefetcher 注册进数据源的就是这样一个 DataChangeListener（它内部叫
// DataSourceObserver）。这里只数 onDataReloaded 被调了几次——那正是让
// BasicPrefetcher 重新读 totalCount() 的那一条通知。
class CountingListener implements DataChangeListener {
  reloaded: number = 0;
  onDataReloaded(): void { this.reloaded++; }
  onDataAdded(_index: number): void {}
  onDataAdd(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataChange(_index: number): void {}
  onDatasetChange(_ops: DataOperation[]): void {}
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

    // ── 向上翻页的锚点复位判据（F-1，P4 误删后接回来）─────────────────

    it('prepend_breaks_the_anchor_when_the_old_first_row_key_moves', 0, () => {
      const users = usersOf();
      const prev = groupsOf([[20, 5000], [30, 9000]], users);
      const withOlder = groupsOf([[10, 100], [20, 5000], [30, 9000]], users);
      // 这就是"向上翻一页"的常态：老首行第一次有了 prev，日期胶囊也搬走了，
      // 它的 key 因此变了 ⇒ Repeat 会把视口顶端那一行删旧插新。
      expect(withOlder[1].key === prev[0].key).assertFalse();
      expect(prependBreaksAnchor(prev, withOlder)).assertTrue();
    });

    it('prepend_anchor_stays_untouched_when_nothing_was_prepended', 0, () => {
      const users = usersOf();
      const prev = groupsOf([[20, 5000], [30, 9000]], users);
      // 追加：老首行仍在下标 0，前面一行都没多。
      const appended = groupsOf([[20, 5000], [30, 9000], [40, 12000]], users);
      expect(prependBreaksAnchor(prev, appended)).assertFalse();
      // 等长的原地编辑不是翻页。
      const edited = collapseAlbums([entry(20, 5000, users), entry(30, 9000, users, 'edited')]);
      expect(prependBreaksAnchor(prev, edited)).assertFalse();
      // 首次填充（prev 为空）由首屏定位负责，不是翻页。
      expect(prependBreaksAnchor([], prev)).assertFalse();
      // 变短（删消息）也不是翻页。
      expect(prependBreaksAnchor(prev, groupsOf([[30, 9000]], users))).assertFalse();
    });

    // ── 向下翻页的锚点复位判据 ───────────────────────────────────────

    it('append_breaks_the_anchor_because_the_list_is_end_anchored', 0, () => {
      const users = usersOf();
      const prev = groupsOf([[20, 5000], [30, 9000]], users);
      const withNewer = groupsOf([[20, 5000], [30, 9000], [40, 12000], [50, 20000]], users);
      // 老首行仍然是首行 —— 增长发生在末尾。stackFromEnd 下这会把可见内容顶走。
      expect(appendBreaksAnchor(prev, withNewer)).assertTrue();
    });

    it('append_anchor_ignores_everything_that_is_not_tail_growth', 0, () => {
      const users = usersOf();
      const prev = groupsOf([[20, 5000], [30, 9000]], users);
      // 前插由 prependBreaksAnchor 那条路负责，两条判据互斥。
      const withOlder = groupsOf([[10, 100], [20, 5000], [30, 9000]], users);
      expect(appendBreaksAnchor(prev, withOlder)).assertFalse();
      expect(prependBreaksAnchor(prev, withOlder)).assertTrue();
      // 等长的原地编辑不是翻页。
      const edited = collapseAlbums([entry(20, 5000, users), entry(30, 9000, users, 'edited')]);
      expect(appendBreaksAnchor(prev, edited)).assertFalse();
      // 首次填充（prev 为空）由首屏定位负责。
      expect(appendBreaksAnchor([], prev)).assertFalse();
      // 变短（删消息）也不是翻页。
      expect(appendBreaksAnchor(prev, groupsOf([[20, 5000]], users))).assertFalse();
    });

    it('prepend_without_a_key_change_is_left_to_maintainVisibleContentPosition', 0, () => {
      const users = usersOf();
      const prev = groupsOf([[20, 5000], [30, 9000]], users);
      const older = groupsOf([[10, 100]], users);
      // 人工构造"老首行 key 一个字都没变"的前插：那时 Repeat 只是在前面插入
      // 新节点，锚点行本身没被删，强行复位反而会打断惯性滑动。
      const untouched: AlbumGroup[] = [older[0], prev[0], prev[1]];
      expect(prependBreaksAnchor(prev, untouched)).assertFalse();
    });

    // ── 预取源必须拿到 fresh 数组（F-3）───────────────────────────────
    //
    // 钉住的是一条会静默失效的接线：photoPath 刻意不进行 key，于是缩略图落地
    // 那一次发布 reuseUnchangedRows 会把**旧对象**还回来，photoPath 永远停在
    // ''。ChatPage.publishGroupsNow 因此必须把**原始**那份喂给
    // AlbumGroupDataSource，把合并那份留给 Repeat。
    it('prefetch_source_must_be_fed_the_fresh_rows_not_the_merged_ones', 0, () => {
      const users = usersOf();
      const base: MessageEntry = cloneMessage(entry(10, 100, users));
      base.contentType = 'photo';
      base.photoWidth = 800;
      base.photoHeight = 600;
      const landed: MessageEntry = cloneMessage(base);
      landed.photoPath = '/data/thumb_10.jpg';

      const prev: AlbumGroup[] = collapseAlbums([base]);
      const fresh: AlbumGroup[] = collapseAlbums([landed]);
      // 缩略图落地不改行 key —— 这正是它走旁路通道的代价。
      expect(fresh[0].key).assertEqual(prev[0].key);
      expect(sameRenderSnapshot(prev[0], fresh[0])).assertTrue();

      const merged: AlbumGroup[] = reuseUnchangedRows(prev, fresh);
      expect(merged[0] === prev[0]).assertTrue();
      expect(merged[0].head.photoPath).assertEqual('');

      const ds = new AlbumGroupDataSource();
      ds.setRows(fresh);
      expect(ds.getData(0).head.photoPath).assertEqual('/data/thumb_10.jpg');
      // 喂合并那份就是那条 bug：imageRequestFor 看见 '' 就 return null，
      // BasicPrefetcher 对这些行一次都不预取。
      ds.setRows(merged);
      expect(ds.getData(0).head.photoPath).assertEqual('');
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

    // ── 崩溃回归：BasicPrefetcher 必须收到集合变更通知 ────────────────
    //
    // 钉住的是 2026-08-27 那个「进任何会话都必崩」的 'Invalid range'：
    // register/unregister 曾是空实现，BasicPrefetcher 内部的 totalItems 因此
    // 永远停在 0，第一次 onScrollIndex 就 new IndexRange(30, 0) 抛异常。
    it('registered_listeners_are_notified_when_the_row_count_changes', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      const listener = new CountingListener();
      ds.registerDataChangeListener(listener);
      expect(listener.reloaded).assertEqual(0);

      // 空 → 2 行：这一次通知是必须的，否则 totalItems 停在 0。
      ds.setRows(groupsOf([[10, 100], [20, 5000]], users));
      expect(listener.reloaded).assertEqual(1);
      expect(ds.totalCount()).assertEqual(2);

      // 前插一页（行数变长）也要通知。
      ds.setRows(groupsOf([[1, 10], [2, 20], [10, 100], [20, 5000]], users));
      expect(listener.reloaded).assertEqual(2);
      expect(ds.totalCount()).assertEqual(4);

      // 变短同样要通知，否则 totalItems 偏大 ⇒ 预取越界读到 undefined。
      ds.setRows(groupsOf([[10, 100]], users));
      expect(listener.reloaded).assertEqual(3);

      // 清空。
      ds.setRows([]);
      expect(listener.reloaded).assertEqual(4);
      expect(ds.totalCount()).assertEqual(0);
    });

    // 行数不变的发布**不**通知：setRows 在每一次发布上都被调用，包括下载进度
    // 跳动那种只改旁路字段的发布，而 onDataReloaded 会让 BasicPrefetcher
    // clearFetched 整个可见窗口再重发一轮 prefetch。理由写在 setRows 的注释里。
    it('same_length_republish_does_not_re_notify', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      const listener = new CountingListener();
      ds.registerDataChangeListener(listener);
      ds.setRows(groupsOf([[10, 100], [20, 5000]], users));
      expect(listener.reloaded).assertEqual(1);
      // 全新的行对象，但行数一样。
      ds.setRows(groupsOf([[10, 100], [20, 5000]], users));
      expect(listener.reloaded).assertEqual(1);
    });

    it('listener_registration_dedupes_and_unregister_stops_notifications', 0, () => {
      const users = usersOf();
      const ds = new AlbumGroupDataSource();
      const listener = new CountingListener();
      // 重复注册同一个监听器只算一次——BasicPrefetcher.setDataSource 会先
      // unregister 再 register，重进同一个数据源不该收到双份通知。
      ds.registerDataChangeListener(listener);
      ds.registerDataChangeListener(listener);
      ds.setRows(groupsOf([[10, 100]], users));
      expect(listener.reloaded).assertEqual(1);

      ds.unregisterDataChangeListener(listener);
      ds.setRows(groupsOf([[10, 100], [20, 5000]], users));
      expect(listener.reloaded).assertEqual(1);

      // 注销一个没注册过的监听器不该抛。
      ds.unregisterDataChangeListener(new CountingListener());
      expect(ds.totalCount()).assertEqual(2);
    });

    // ── 下标钳制 ────────────────────────────────────────────────────────
    //
    // visibleAreaChanged 的形参文档写着「取值范围为 [0, totalCount()-1]，超出
    // 范围时计算错误」，而实际后果是 IndexRange 抛 'Invalid range' 并被转抛。
    it('clamp_visible_range_keeps_indices_inside_the_collection', 0, () => {
      // 正常区间原样通过。
      const ok: PrefetchRange | null = clampPrefetchRange(3, 9, 100);
      expect(ok !== null).assertTrue();
      expect((ok as PrefetchRange).start).assertEqual(3);
      expect((ok as PrefetchRange).end).assertEqual(9);

      // 集合在两帧之间变短：行号合法但已越界，钳到最后一行。
      const shrunk: PrefetchRange | null = clampPrefetchRange(30, 40, 10);
      expect(shrunk !== null).assertTrue();
      expect((shrunk as PrefetchRange).start).assertEqual(9);
      expect((shrunk as PrefetchRange).end).assertEqual(9);

      // 只有 end 越界。
      const tail: PrefetchRange | null = clampPrefetchRange(5, 40, 10);
      expect((tail as PrefetchRange).start).assertEqual(5);
      expect((tail as PrefetchRange).end).assertEqual(9);

      // 首帧之前 curEndIdx 是 -1；start > end 正是 IndexRange 抛异常的形状，
      // 钳完必须 start <= end。
      const early: PrefetchRange | null = clampPrefetchRange(0, -1, 10);
      expect((early as PrefetchRange).start).assertEqual(0);
      expect((early as PrefetchRange).end).assertEqual(0);

      const negative: PrefetchRange | null = clampPrefetchRange(-5, -3, 10);
      expect((negative as PrefetchRange).start).assertEqual(0);
      expect((negative as PrefetchRange).end).assertEqual(0);

      // 单行集合。
      const single: PrefetchRange | null = clampPrefetchRange(0, 0, 1);
      expect((single as PrefetchRange).start).assertEqual(0);
      expect((single as PrefetchRange).end).assertEqual(0);

      // 空集合：一次都不该调 visibleAreaChanged（0 和 -1 都不是合法下标）。
      expect(clampPrefetchRange(0, 0, 0)).assertNull();
      expect(clampPrefetchRange(0, 5, 0)).assertNull();
    });

    // 钳制之后的区间永远满足 IndexRange 的前置条件：0 <= start <= end <= total-1。
    it('clamp_visible_range_never_produces_an_invalid_range', 0, () => {
      const totals: number[] = [1, 2, 10, 494];
      const probes: number[] = [-7, -1, 0, 1, 9, 10, 493, 494, 1000];
      for (const total of totals) {
        for (const start of probes) {
          for (const end of probes) {
            const r: PrefetchRange | null = clampPrefetchRange(start, end, total);
            expect(r !== null).assertTrue();
            const range: PrefetchRange = r as PrefetchRange;
            expect(range.start >= 0).assertTrue();
            expect(range.end >= range.start).assertTrue();
            expect(range.end <= total - 1).assertTrue();
          }
        }
      }
    });
  });
}
