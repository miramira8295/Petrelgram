import { IDataSourcePrefetching } from '@kit.ArkUI';
import { AlbumGroup } from '../../util/collapseAlbums';
import { mediaBoxFor } from '../../util/mediaBox';
import { cancelPixelMap, loadPixelMap, PixelRequest } from '../../util/pixelCache';
import { keyTableAdd, keyTableDelete, keyTableReload, newKeyTableId } from '../../util/keyGuard';
import { logI, logW } from '../../util/log';
import { chatContentWidth } from '../../util/chatContentWidth';

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

// Initial-page staging republishes the same row signatures across several
// bounded batches. A 256-entry cache thrashed as soon as a long history held
// 494 rows, so the same signatures were hashed again on the next publication.
// 2048 covers several large windows while retaining a strict process-wide cap.
const CONTENT_FINGERPRINT_CACHE_LIMIT: number = 2048;
const contentFingerprintCache: Map<string, string> = new Map<string, string>();

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
  const cached: string | undefined = contentFingerprintCache.get(s);
  if (cached !== undefined) {
    return cached;
  }
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h + s.charCodeAt(i)) & 0x7fffffff;
  }
  const fingerprint: string = h.toString(36);
  if (contentFingerprintCache.size >= CONTENT_FINGERPRINT_CACHE_LIMIT) {
    contentFingerprintCache.clear();
  }
  contentFingerprintCache.set(s, fingerprint);
  return fingerprint;
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
  if (a.head.rowId !== b.head.rowId || a.rowMemberIds.length !== b.rowMemberIds.length) {
    return false;
  }
  for (let i = 0; i < a.rowMemberIds.length; i++) {
    if (a.rowMemberIds[i] !== b.rowMemberIds[i]) {
      return false;
    }
  }
  return true;
}

// initialDeferred changes only how this existing row is built (fixed-height
// placeholder vs real bubble). It must participate in the data-source diff but
// not in the LazyForEach key: a keyless CHANGE preserves the row identity and
// avoids a delete+insert around the current scroll anchor.
function sameRenderSnapshot(a: AlbumGroup, b: AlbumGroup): boolean {
  return a.key === b.key && (a.initialDeferred === true) === (b.initialDeferred === true);
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
  // rowId / rowMemberIds 而不是 id / memberIds：发送成功时 TDLib 把临时 id
  // 换成真实 id，用 id 拼 key 会让那一行被当成新 item 销毁重建。
  private keyOf: GroupKeyBuilder = (g: AlbumGroup): string =>
    `message_group_${g.head.rowId}_${g.rowMemberIds.join('_')}_${contentFingerprint(g.key)}`;

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
    // 内容列宽而不是窗口宽：必须和 MessageBubble 算出同一个尺寸，像素缓存按
    // 尺寸建 key，差一像素就是两份解码（见 util/mediaBox 文件头）。
    const screenW = chatContentWidth();
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

  private updateInner(next: AlbumGroup[]): DataSourceUpdateKind {
    const prev = this.groups;
    this.groups = next;
    const minLen = Math.min(prev.length, next.length);
    let p = 0;
    while (p < minLen && sameRenderSnapshot(prev[p], next[p])) {
      p++;
    }
    let s = 0;
    while (s < minLen - p &&
      sameRenderSnapshot(prev[prev.length - 1 - s], next[next.length - 1 - s])) {
      s++;
    }
    const oldMid = prev.length - p - s;
    const newMid = next.length - p - s;
    if (oldMid === 0 && newMid === 0) {
      return 'none'; // keys identical — nothing to tell the list
    }
    // Do not scan and hash the complete snapshot here. The per-live-row
    // keyGuard still diagnoses duplicate keys as LazyForEach materializes them,
    // without charging every dataset update for off-screen diagnostic work.
    if (oldMid === newMid) {
      // CHANGE means "this same item's content changed". If the row at an
      // index is a DIFFERENT message — a delete plus an append leaves the
      // length untouched — then saying CHANGE tells the list the identity is
      // unchanged while its LazyForEach key has become one that is registered
      // at another index. The framework logs "Use repeat key" and reuses the
      // wrong row. Identity shifts have to be a reload.
      for (let i = 0; i < oldMid; i++) {
        if (!sameIdentity(prev[p + i], next[p + i])) {
          // 中段只有一行时不必整表重建。发送成功就是这个形状：TDLib 的
          // updateMessageSendSucceeded 让 store 删掉临时 id 那条、插入真实 id
          // 那条（MessageStore.onSendSucceeded），位置没动、其余行的 key 和
          // 下标也都没动，只是这一格换了身份。
          //
          // 上面那段注释担心的是"删一条又追加一条，长度不变但每个下标坐着的
          // 都是别人"——那种情况中段会是一大片，不是一行。而只有一行变化时，
          // 它的新 key 不可能已经注册在别的下标上（同一快照内 key 唯一，
          // sameRowSlot 已确认仍是同一个列表槽位，把新 key 交给这一格正是
          // DataChangeOperation.key 的用途。
          //
          // 整表 RELOAD 会让所有行销毁重建，表现为发消息时列表"闪一下"、
          // 入场动画播第二遍。
          if (oldMid === 1) {
            break;
          }
          return this.notifyReloadWithDeferredFlips(prev, next, p, oldMid, newMid);
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
      // Ordinary content changes carry a genuinely NEW key. Initial placeholder
      // admission is the one deliberate exception: its content key stays the
      // same, and a keyless CHANGE asks the framework to rebuild that same item
      // instead of re-registering or replacing it.
      const ops: DataOperation[] = [];
      for (let i = 0; i < oldMid; i++) {
        const before: AlbumGroup = prev[p + i];
        const after: AlbumGroup = next[p + i];
        if (!sameRenderSnapshot(before, after)) {
          if (before.key === after.key) {
            ops.push({
              type: DataOperationType.CHANGE,
              index: p + i
            } as DataChangeOperation);
            continue;
          }
          ops.push({
            type: DataOperationType.CHANGE,
            index: p + i,
            key: this.keyOf(after)
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
        logI(`[DS] misaligned added=${added} prevHead=${prev[p].head.id}` +
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
          const before: AlbumGroup = prev[p + i];
          const after: AlbumGroup = next[newIndex];
          if (!sameRenderSnapshot(before, after)) {
            if (before.key === after.key) {
              ops.push({
                type: DataOperationType.CHANGE,
                index: newIndex
              } as DataChangeOperation);
              continue;
            }
            ops.push({
              type: DataOperationType.CHANGE,
              index: newIndex,
              key: this.keyOf(after)
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
    return this.notifyReloadWithDeferredFlips(prev, next, p, oldMid, newMid);
  }

  // Rows that a RELOAD would silently leave holding their placeholder.
  //
  // The SDK contract for reload is "for data items whose key remains unchanged,
  // the ORIGINAL child component is used", and initialDeferred is deliberately
  // NOT part of the key (see sameRenderSnapshot). So a row that flips from
  // placeholder to real content inside a RELOAD batch keeps its placeholder
  // Column — while updateInner has already swapped this.groups over to the real
  // snapshot, which means no later diff will ever name that row again. That is
  // the blank first-screen row: full height, nothing drawn at all, self-healing
  // only once the list scrolls it out of the cache and rebuilds it.
  //
  // Pairing is by KEY, not by index: the fallback exit below is reached exactly
  // when the middle regions do not line up by index. A placeholder and its real
  // row produce the identical key (initialMessageStage.deferredCopy keeps the
  // identity and content key intact), which is what makes the lookup meaningful
  // here and what made the framework skip the row in the first place.
  private deferredFlipIndexes(
    prev: AlbumGroup[],
    next: AlbumGroup[],
    p: number,
    oldMid: number,
    newMid: number
  ): number[] {
    const flipped: number[] = [];
    if (oldMid <= 0 || newMid <= 0) {
      return flipped;
    }
    const wasDeferred: Map<string, boolean> = new Map<string, boolean>();
    for (let i = 0; i < oldMid; i++) {
      const row: AlbumGroup = prev[p + i];
      wasDeferred.set(this.keyOf(row), row.initialDeferred === true);
    }
    for (let i = 0; i < newMid; i++) {
      const row: AlbumGroup = next[p + i];
      const before: boolean | undefined = wasDeferred.get(this.keyOf(row));
      if (before !== undefined && before !== (row.initialDeferred === true)) {
        flipped.push(p + i);
      }
    }
    return flipped;
  }

  // RELOAD, plus a targeted re-notification of the rows the RELOAD would drop.
  private notifyReloadWithDeferredFlips(
    prev: AlbumGroup[],
    next: AlbumGroup[],
    p: number,
    oldMid: number,
    newMid: number
  ): DataSourceUpdateKind {
    const flipped: number[] = this.deferredFlipIndexes(prev, next, p, oldMid, newMid);
    // 诊断：修好之后屏幕上不该再有空白行，但这个数不会因此归零 —— 它统计的是
    // "RELOAD 本会吞掉多少翻转"，补发正是靠它。下次上机进十几个会话：
    // flips>0 且仍有空白 ⇒ 补发没覆盖到；flips>0 而无空白 ⇒ 补发生效；
    // 恒为 0 ⇒ 这条机理没被命中，回去查排查文档里的候选 C。
    logW(`[BlankRow] reload flips=${flipped.length} oldMid=${oldMid} newMid=${newMid}`);
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
    if (flipped.length === 0) {
      return 'reload';
    }
    // 单独一次 notify，跟在 RELOAD 后面 —— 不混批。混在同一批里，CHANGE 的
    // 下标既可以按重建前也可以按重建后解释；本文件上面那段 ADD+CHANGE 的注释
    // 记着同样的坑（30 行的 prepend 混批发出去，列表显示了错的行）。拆开之后
    // 下标含义唯一：next 里的位置，也就是 RELOAD 之后列表的当前位置。
    const ops: DataOperation[] = [];
    for (const index of flipped) {
      // 无 key。占位和真身是同一个 item，key 本来就没变（这正是 RELOAD 漏掉
      // 它的原因）；带 key 会让框架把一个已经注册的 key 重新注册一遍。
      // 只覆盖真正翻转的行 —— 整段一起 CHANGE 就是上面记着的老毛病。
      ops.push({ type: DataOperationType.CHANGE, index: index } as DataChangeOperation);
    }
    this.notify(ops);
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
