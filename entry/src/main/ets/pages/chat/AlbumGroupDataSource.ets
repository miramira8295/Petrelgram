import { IDataSourcePrefetching } from '@kit.ArkUI';
import { AlbumGroup } from '../../util/collapseAlbums';
import { mediaBoxFor } from '../../util/mediaBox';
import { cancelPixelMap, loadPixelMap, PixelRequest } from '../../util/pixelCache';
import { keyTableAdd, keyTableDelete, keyTableReload, newKeyTableId } from '../../util/keyGuard';

// LazyForEach data source for the message list.
//
// Why this exists: List.maintainVisibleContentPosition (keep scroll position
// when older pages are prepended) ONLY works with LazyForEach fine-grained
// notifications — with plain ForEach the list stays index-anchored and jumps
// to the top of every newly prepended page.
//
// update() diffs the old/new group lists by key (common prefix + suffix) and
// emits the minimal notification: ADD for pure prepend/append, CHANGE for
// in-place mutations, DELETE for removals, RELOAD only for complex mixed edits.
//
// The return value tells the caller which path was taken: 'incremental' ops
// let List.maintainVisibleContentPosition hold the scroll anchor by itself;
// only 'reload' rebuilds the list and needs a manual anchor restore.
export type DataSourceUpdateKind = 'none' | 'incremental' | 'reload';

// Builds the LazyForEach key for a row. ChatPage owns the format because the
// key embeds the language epoch, which is page state; the data source needs it
// so it can name the rows its operations affect.
export type GroupKeyBuilder = (g: AlbumGroup) => string;

// Short fingerprint of a row's content signature, for embedding in the
// LazyForEach key.
//
// The framework's reuse machinery is entirely key-driven — the SDK contract for
// reload is "for data items whose key remains unchanged, the ORIGINAL child
// component is used". A key built from identity alone therefore makes every
// RELOAD resurrect the old component with its old content, and after a
// background stretch (where the framework's key -> node table is already
// inconsistent — "Use repeat key") the resurrected node can be a NEIGHBOR'S:
// on the device, one sender's adjacent messages came back wearing each other's
// content. Embedding the content fingerprint makes a changed row's key a new
// key, which is the one thing the reload contract promises to rebuild.
//
// g.key itself is the precise signature but runs to kilobytes (message text,
// entity JSON, file paths); the framework stores and compares every key, so it
// is hashed down. The identity prefix stays plaintext in the final key, so a
// hash collision could at worst miss one rebuild of one row — it can never
// mix two different rows.
export function contentFingerprint(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.charCodeAt(i)) & 0x7fffffff;
  }
  return h.toString(36);
}

// 同一个列表位置，内容可以不同。
//
// 对齐检查问的不是"是不是同一个 LazyForEach item"（那是 sameIdentity），而是
// "旧的这一行在新快照里还在不在"。相册跨页边界被截断时两者会分叉：旧页只加载
// 到相册的一部分成员，新页补齐后它们合并成一行，而相册头是第一条消息，于是
// head.id 变成了更早的那条。按 head.id 对齐必然判定失败，整表 RELOAD ——
// 真机实测媒体多的频道每翻一页都命中（[DS] misaligned 诊断，47 次）。
//
// 一份快照里一个 albumId 只可能对应一行（collapseAlbums 把连续的同 albumId
// 成员合成一行），所以用它对齐不会把两行错配到一起。行的 key 确实变了，由
// 随后的 CHANGE 带上新 key 通知框架——这正是 DataChangeOperation.key 的用途。
function sameRowSlot(a: AlbumGroup, b: AlbumGroup): boolean {
  if (a.head.id === b.head.id) {
    return true;
  }
  const album: string = a.head.albumId;
  return album !== '' && album === b.head.albumId;
}

// What the list's LazyForEach key is built from (see ChatPage). Two rows are
// the same item only if these match; anything else is a different row wearing
// the same index.
function sameIdentity(a: AlbumGroup, b: AlbumGroup): boolean {
  if (a.head.id !== b.head.id || a.memberIds.length !== b.memberIds.length) {
    return false;
  }
  for (let i = 0; i < a.memberIds.length; i++) {
    if (a.memberIds[i] !== b.memberIds[i]) {
      return false;
    }
  }
  return true;
}

export class AlbumGroupDataSource implements IDataSourcePrefetching {
  private groups: AlbumGroup[] = [];
  private listeners: DataChangeListener[] = [];
  // Diagnostic only: names this instance's key table, which must be per-page
  // because each page has its own LazyForEach. ChatPage passes it to guardKey.
  readonly keyTableId: string = newKeyTableId('messages');

  // Named keys on ADD/CHANGE, rather than letting the framework infer them.
  //
  // Inference is where the list came apart. A prepend inserts at index 0 and
  // every row below shifts down; the framework has to re-associate its whole
  // key -> index table, and the device log showed it not keeping up — "Use
  // repeat key for index: 18" while that key was still registered at 48, always
  // after a prepend, always at an index inside the shifted region. Spelling the
  // keys out in the operation leaves nothing to infer.
  private keyOf: GroupKeyBuilder = (g: AlbumGroup): string =>
    `message_group_${g.head.id}_${g.memberIds.join('_')}_${contentFingerprint(g.key)}`;

  // ChatPage supplies the real builder (its key also carries the language
  // epoch) and MUST use the same one for the LazyForEach key generator — two
  // spellings of the format would put the framework's table and ours out of
  // step in a way nothing in the toolchain would catch.
  setKeyBuilder(builder: GroupKeyBuilder): void {
    this.keyOf = builder;
  }

  private keysIn(list: AlbumGroup[], from: number, count: number): string[] {
    const keys: string[] = [];
    for (let i = from; i < from + count; i++) {
      keys.push(this.keyOf(list[i]));
    }
    return keys;
  }

  // --- prefetching -----------------------------------------------------------
  //
  // BasicPrefetcher drives these from the visible range: prefetch() for rows
  // about to arrive, cancel() for rows the user has scrolled past. Decoding a
  // row's photo before it is on screen is the difference between a bubble that
  // appears with its image and one that appears empty and fills in.
  //
  // The size has to match what MessageBubble will ask for exactly, or the
  // decode lands under a key the bubble never looks up — hence the shared
  // mediaBoxFor(). Albums are deliberately not prefetched: their cell sizes
  // come out of a packing pass over the whole row, and getting that subtly
  // wrong would decode a second, unused copy of every picture.
  private imageRequestFor(index: number): PixelRequest | null {
    const group = this.groups[index];
    if (group === undefined || group.memberIds.length > 1) {
      return null;
    }
    const head = group.head;
    if (head.photoPath === '' ||
      (head.contentType !== 'photo' && head.contentType !== 'video')) {
      return null;
    }
    const screenW = AppStorage.get<number>('screenWidthVp') ?? 0;
    if (screenW <= 0) {
      return null;
    }
    const box = mediaBoxFor(screenW, head.photoWidth, head.photoHeight,
      head.contentType === 'video');
    return { path: head.photoPath, width: vp2px(box.width), height: vp2px(box.height) };
  }

  prefetch(index: number): void {
    const req = this.imageRequestFor(index);
    if (req !== null) {
      loadPixelMap(req);
    }
  }

  cancel(index: number): void {
    const req = this.imageRequestFor(index);
    if (req !== null) {
      cancelPixelMap(req);
    }
  }

  totalCount(): number {
    return this.groups.length;
  }

  getData(index: number): AlbumGroup {
    return this.groups[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  // Force a rebuild when the ROW KEY changes for a reason the data itself
  // cannot express. The list's key embeds the language epoch, so bumping that
  // renames every row at once — and a LazyForEach whose keys all change without
  // any notification is left holding a key table that matches nothing, which
  // shows up as rows rendering the wrong messages. onConfigurationUpdate bumps
  // the epoch for any configuration change (dark mode, font scale, locale),
  // and returning from the background is a common moment for one.
  reload(): void {
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  update(next: AlbumGroup[]): DataSourceUpdateKind {
    return this.updateInner(next);
  }

  // Authoritative on its own: this looks at ONE snapshot, so a hit here means
  // two rows in the same dataset carry the same LazyForEach key — a data bug,
  // no notification timing involved. Silence means the data is clean and any
  // "Use repeat key" the framework reports is about its table, not ours.
  // NOTE: not group.key — that is the content signature used for diffing,
  // while the LazyForEach key is identity only. keyOf is the one the list
  // actually uses.
  //
  // Only called for a snapshot that actually differs from the last one (see
  // updateInner). keyOf runs contentFingerprint over each row's full content
  // signature — hundreds of characters per row — so at 494 rows this scan cost
  // 13-15ms, and running it on every notification burned 130-265ms per second
  // while media was loading, most of it re-checking a dataset whose keys had
  // not moved. A key sequence identical to the previous one was already checked
  // when that one arrived, so skipping it there loses no coverage: a duplicate
  // that survives into an unchanged snapshot was present in its predecessor and
  // gets reported one round earlier, not never.
  private assertNoDuplicateKeys(next: AlbumGroup[]): void {
    const keysSeen: Map<string, number> = new Map();
    for (let i = 0; i < next.length; i++) {
      const rowKey = this.keyOf(next[i]);
      const at = keysSeen.get(rowKey);
      if (at !== undefined) {
        console.error(`[DS] duplicate row key in snapshot at ${i} and ${at} -> ${rowKey}`);
      } else {
        keysSeen.set(rowKey, i);
      }
    }
  }

  private updateInner(next: AlbumGroup[]): DataSourceUpdateKind {
    const prev = this.groups;
    this.groups = next;
    const minLen = Math.min(prev.length, next.length);
    let p = 0;
    while (p < minLen && prev[p].key === next[p].key) {
      p++;
    }
    let s = 0;
    while (s < minLen - p && prev[prev.length - 1 - s].key === next[next.length - 1 - s].key) {
      s++;
    }
    const oldMid = prev.length - p - s;
    const newMid = next.length - p - s;
    if (oldMid === 0 && newMid === 0) {
      return 'none'; // keys identical — nothing to tell the list
    }
    // 数据集确实变了才查，且仍在任何 notify 之前。
    this.assertNoDuplicateKeys(next);
    if (oldMid === newMid) {
      // CHANGE means "this same item's content changed". If the row at an
      // index is a DIFFERENT message — a delete plus an append leaves the
      // length untouched — then saying CHANGE tells the list the identity is
      // unchanged while its LazyForEach key has become one that is registered
      // at another index. The framework logs "Use repeat key" and reuses the
      // wrong row. Identity shifts have to be a reload.
      for (let i = 0; i < oldMid; i++) {
        if (!sameIdentity(prev[p + i], next[p + i])) {
          this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
          return 'reload';
        }
      }
      // Same-length middle region: in-place item changes (photo arrived,
      // send state advanced, reactions updated, ...).
      //
      // Only the rows whose keys actually differ. The prefix/suffix scan finds
      // the FIRST and LAST changed rows, so the span between them also covers
      // every untouched row in between — and this used to raise CHANGE for all
      // of them. With two images downloading ten rows apart, every row between
      // was rebuilt on every progress tick, which is why unrelated photos and
      // inline emoji flickered for as long as anything was still loading.
      // Every CHANGE row's content signature differs here, so keyOf yields a
      // genuinely NEW key — which is exactly what DataChangeOperation.key is
      // for ("new key to assign to the changed data"). A key identical to the
      // registered one must never be passed: that made the framework
      // re-register the entry against itself and mis-reuse the node.
      const ops: DataOperation[] = [];
      for (let i = 0; i < oldMid; i++) {
        if (prev[p + i].key !== next[p + i].key) {
          ops.push({
            type: DataOperationType.CHANGE,
            index: p + i,
            key: this.keyOf(next[p + i])
          } as DataChangeOperation);
        }
      }
      if (ops.length === 0) {
        return 'none';
      }
      this.notify(ops);
      return 'incremental';
    }
    if (oldMid === 0) {
      // Pure insert (prepend when p === 0 — the case scroll position must survive).
      this.notify([{
        type: DataOperationType.ADD,
        index: p,
        count: newMid,
        key: this.keysIn(next, p, newMid)
      } as DataAddOperation]);
      return 'incremental';
    }
    if (newMid === 0) {
      this.notify([{ type: DataOperationType.DELETE, index: p, count: oldMid } as DataDeleteOperation]);
      return 'incremental';
    }
    // Insert + in-place changes in one notify. This is the NORMAL page case,
    // not a rare one: prepending an older page always mutates the old first
    // row's key (its date pill moves away / its sender-run flags flip), and
    // appending a same-sender message flips the old last row's avatar flag.
    // Falling back to RELOAD here would rebuild the list and lose the scroll
    // anchor — the "jumps to the top of the loaded page" bug.
    // All op indexes reference the ORIGINAL dataset.
    if (newMid > oldMid) {
      const added = newMid - oldMid;
      // Append case: surviving old rows pair with the FRONT of the new middle.
      let frontAligned = true;
      for (let i = 0; i < oldMid; i++) {
        if (!sameRowSlot(prev[p + i], next[p + i])) {
          frontAligned = false;
          break;
        }
      }
      // Prepend case: surviving old rows pair with the BACK of the new middle.
      let backAligned = !frontAligned;
      if (backAligned) {
        for (let i = 0; i < oldMid; i++) {
          if (!sameRowSlot(prev[p + i], next[p + added + i])) {
            backAligned = false;
            break;
          }
        }
      }
      if (!frontAligned && !backAligned) {
        // Diagnostic: every older-page prepend is landing here instead of on the
        // incremental path, and the RELOAD it falls through to is what rebuilds
        // the list. Name the rows that failed to line up. Temporary.
        console.info(`[DS] misaligned added=${added} prevHead=${prev[p].head.id}` +
          ` frontCand=${next[p].head.id} backCand=${next[p + added].head.id}` +
          ` prevMembers=${prev[p].memberIds.join('/')}` +
          ` backMembers=${next[p + added].memberIds.join('/')}`);
      }
      if (frontAligned || backAligned) {
        // Two notifications, structure first — NOT one mixed batch.
        //
        // Mixing them meant CHANGE and ADD indexes both referred to the
        // original dataset while the ADD was shifting everything after its
        // insertion point. Whether that lands correctly depends on the order
        // the framework applies the operations in, and the device log caught it
        // going wrong on exactly this path: a prepend of 30 rows onto 31,
        // emitted as `change,add`, left the list showing the wrong rows.
        //
        // Split, each notification is unambiguous: the ADD reshapes the list,
        // then the CHANGE indexes are plain positions in the list as it now is.
        const addAt: number = backAligned ? p : p + oldMid;
        this.notify([{
          type: DataOperationType.ADD,
          index: addAt,
          count: added,
          key: this.keysIn(next, addAt, added)
        } as DataAddOperation]);
        // Same narrowing as above: an insert does not make the surviving rows
        // around it dirty, only the ones whose keys really moved — and those
        // carry their new content-fingerprinted key, same as the branch above.
        const ops: DataOperation[] = [];
        for (let i = 0; i < oldMid; i++) {
          const newIndex = backAligned ? p + added + i : p + i;
          if (prev[p + i].key !== next[newIndex].key) {
            ops.push({
              type: DataOperationType.CHANGE,
              index: newIndex,
              key: this.keyOf(next[newIndex])
            } as DataChangeOperation);
          }
        }
        if (ops.length > 0) {
          this.notify(ops);
        }
        return 'incremental';
      }
    }
    // Genuinely mixed structural edit (e.g. a loadAround window replacement).
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
    return 'reload';
  }

  private notify(ops: DataOperation[]): void {
    // Keep the diagnostic key table in step with what the framework is being
    // told, so its duplicate reports mean what they say.
    for (const op of ops) {
      if (op.type === DataOperationType.RELOAD) {
        keyTableReload(this.keyTableId);
      } else if (op.type === DataOperationType.ADD) {
        const add = op as DataAddOperation;
        keyTableAdd(this.keyTableId, add.index, add.count ?? 1);
      } else if (op.type === DataOperationType.DELETE) {
        const del = op as DataDeleteOperation;
        keyTableDelete(this.keyTableId, del.index, del.count ?? 1);
      }
    }
    for (const l of this.listeners) {
      l.onDatasetChange(ops);
    }
  }
}
