import { IDataSourcePrefetching } from '@kit.ArkUI';
import { AlbumGroup } from '../../util/collapseAlbums';
import { mediaBoxFor } from '../../util/mediaBox';
import { cancelPixelMap, loadPixelMap, PixelRequest } from '../../util/pixelCache';
import { chatContentWidth } from '../../util/chatContentWidth';

// 图片预取源 —— **不再是 LazyForEach 的数据源**（P4：列表已换成 Repeat）。
//
// 这个文件曾经有 512 行，其中约 300 行是一台按 key 做「公共前缀 + 公共后缀」
// 差分、发 ADD / CHANGE / DELETE / RELOAD 的增量引擎。Repeat 自己按 .key() 差分，
// 那台引擎连同它的监听器、notify、诊断 key 表一起删掉了；行数组本身搬去
// ChatPage 的 @Local groups，从「镜像」升级成唯一真相。
//
// 留下的只有两件事：
//   1. IDataSourcePrefetching 的实现，喂给 BasicPrefetcher（官方预取算法）。
//      BasicPrefetcher 与 LazyForEach 之间没有任何耦合——它是被 ChatPage 的
//      onScrollIndex 手动喂的（imagePrefetcher.visibleAreaChanged(start, end)），
//      文档里说的「支持与 List、Grid、WaterFlow 和 Swiper 组件配合使用」说的是
//      容器，不是 LazyForEach。所以那一行一个字都没改。
//      registerDataChangeListener / unregisterDataChangeListener **必须是真的**：
//      Repeat 确实不调它们，但 BasicPrefetcher 调——见类尾那段注释。
//   2. 几个纯函数：行 key 的内容指纹、跨快照的行对象复用、[BlankRow] 诊断。
//      它们没有 UI 依赖，因此可以被单测直接覆盖。

// Initial-page staging republishes the same row signatures across several
// bounded batches. A 256-entry cache thrashed as soon as a long history held
// 494 rows, so the same signatures were hashed again on the next publication.
// 2048 covers several large windows while retaining a strict process-wide cap.
const CONTENT_FINGERPRINT_CACHE_LIMIT: number = 2048;
const contentFingerprintCache: Map<string, string> = new Map<string, string>();

// Short fingerprint of a row's content signature, for embedding in the row key.
//
// Repeat's reuse machinery is entirely key-driven, same as LazyForEach's was:
// a key built from identity alone would let a changed row keep an already
// rendered node forever. Embedding the content fingerprint makes a changed
// row's key a new key.
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

// 行身份：和行 key 的前半段同源（rowId + rowMemberIds）。
//
// rowId / rowMemberIds 而不是 id / memberIds：发送成功时 TDLib 把临时 id 换成
// 真实 id，用 id 拼身份会让那一行被当成新行销毁重建。
function rowIdentity(g: AlbumGroup): string {
  return `${g.head.rowId}_${g.rowMemberIds.join('_')}`;
}

// 两行是不是**完全同一份渲染快照**：身份、内容、以及首屏占位标志都一样。
export function sameRenderSnapshot(a: AlbumGroup, b: AlbumGroup): boolean {
  return a.key === b.key && rowIdentity(a) === rowIdentity(b) &&
    (a.initialDeferred === true) === (b.initialDeferred === true);
}

// 跨快照复用没变过的行对象。
//
// **为什么需要它**：MessageStore 每次发布都会跑一遍 collapseAlbums，产出的是
// 一整套全新的 AlbumGroup 对象——哪怕一个字都没变。LazyForEach 时代这不要紧，
// 因为通知是我们自己发的，只点名真正变了的那几行；Repeat 不看通知，它按官方
// 文档的说法「比较当前索引处节点数据 item 是否变化，以此判断是否进行 UI 刷新」。
// 直接把全新数组交给 Repeat，等于每次发布都把可见窗口里的每一行都判成变了，
// 一次下载进度跳动就要刷十几行——正是 P2 那轮修好的「无关图片跟着闪」。
//
// 这个函数把内容相同的行还给上一份快照的对象，于是 item 的引用不变，Repeat
// 就只刷新真正变了的那几行。它不改变任何一行的内容，只改变对象身份。
export function reuseUnchangedRows(prev: AlbumGroup[], next: AlbumGroup[]): AlbumGroup[] {
  if (prev.length === 0) {
    return next;
  }
  const byIdentity: Map<string, AlbumGroup> = new Map<string, AlbumGroup>();
  for (const row of prev) {
    const id: string = rowIdentity(row);
    // 同一份快照里一个身份只可能出现一次；真出现重复就以第一个为准，
    // 反正后面还要逐行比内容才会复用。
    if (!byIdentity.has(id)) {
      byIdentity.set(id, row);
    }
  }
  const merged: AlbumGroup[] = [];
  for (const row of next) {
    const before: AlbumGroup | undefined = byIdentity.get(rowIdentity(row));
    merged.push(before !== undefined && sameRenderSnapshot(before, row) ? before : row);
  }
  return merged;
}

// 向上翻页之后，视口锚点还需不需要**手动**复位。
//
// 【这段是被 P4 误删、再接回来的，理由写在这里，别再删第二次】
//
// 迁 Repeat 之前，ChatPage 只在数据源报 `updateKind === 'reload'` 时手动复位。
// 迁移时那一支连同增量引擎一起没了，注释里写成「相册跨页合并那一行的 key 才会
// 变」——**那句话是错的**，现已一并更正。真实情况是：
//
//   collapseAlbums 的第二遍扫描把 showAvatar / showSenderName 拼进行 key
//   （collapseAlbums.ets 末尾的 `_${'A'|'a'}${'N'|'n'}`），而 showSenderName 的
//   判据是 `prev !== null && dateLabel === '' && sameRun(prev, cur)`。前插一页
//   之后，原来的**首行第一次有了 prev**，同时它作为「窗口首行」拿到的日期胶囊
//   会移到新来的那一页上、dateLabel 被清掉 ⇒ 边界那一行的 key **每次向上翻页
//   都变**。这是翻页的**常态**，不是罕见情形。
//
// 老引擎为此把 ADD 与 CHANGE 拆成两次 notify，让这一行走「同一个 item 换新 key」
// 的路径。**Repeat 没有这个概念**：key 变了就是删旧插新，而被删掉的正好是视口
// 顶端那一行。List.maintainVisibleContentPosition(true) 能不能在锚点行本身被
// 删掉时守住位置，官方文档答不了——所以按下面这条判据把手动复位接回来，防的是
// 「向上翻页跳到已加载页顶部」那个历史 bug。
//
// 判据（三条同时成立才需要复位）：
//   1. 新快照更长——真的多了行，而不是编辑/删除；
//   2. 老首行在新快照里的位置 > 0——是**前插**，不是追加；
//   3. 老首行的**内容 key 变了**——Repeat 会把它删旧插新。key 没变时 Repeat
//      只是原地更新，maintainVisibleContentPosition 自己就守得住，这时复位反而
//      会打断用户的惯性滑动（那是当年「加载更多时一顿」的成因）。
export function prependBreaksAnchor(prev: AlbumGroup[], next: AlbumGroup[]): boolean {
  if (prev.length === 0 || next.length <= prev.length) {
    return false;
  }
  const firstId: string = rowIdentity(prev[0]);
  let at: number = -1;
  for (let i = 0; i < next.length; i++) {
    if (rowIdentity(next[i]) === firstId) {
      at = i;
      break;
    }
  }
  if (at <= 0) {
    return false;
  }
  return next[at].key !== prev[0].key;
}

// 两份行数组是不是逐项同一个对象。配合 reuseUnchangedRows 用：结果为 true 就
// 说明这次发布没有任何一行需要动。
export function sameRowArray(a: AlbumGroup[], b: AlbumGroup[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

// ── [BlankRow] 诊断 ────────────────────────────────────────────────────────
//
// 【这段历史必须留着，因为它记的是一个刚修好的用户可见 bug】
//
// LazyForEach 时代：占位符与真身共用同一个 key（initialDeferred 故意不进 key，
// 见上面的 sameRenderSnapshot），而 RELOAD 的 SDK 契约是「对于 key 没变的数据
// 项，沿用**原来的**子组件」。于是一行在 RELOAD 那一批里从占位翻成真身，框架
// 会**默默把它留在占位状态**——而数据源已经把数组换成了真快照，此后任何一次
// 差分都不会再点到那一行的名。屏幕上就是一条满高的空白行，只有滚出缓存区重建
// 才自愈。修法是 RELOAD 之后**单独再补发一次不带 key 的 CHANGE**，按 key 配对
// 找出被吞掉的翻转行（AlbumGroupDataSource.notifyReloadWithDeferredFlips）。
//
// 【Repeat 之后还需要吗——我的判断：不需要，但要上机确认】
//
// 依据是官方《Repeat：可复用的循环渲染》「节点更新/复用能力说明」的原话：
//   「Repeat 数据更新触发重新渲染的逻辑是比较当前索引处节点数据 item 是否变化，
//     以此判断是否进行 UI 刷新，仅改变键值不改变 item 的情况不会触发刷新。」
// 它的判据是 **item 变没变**，key 只用来配对。占位→真身正是「key 不变、item
// 换了新对象」（deferredCopy 造的是新对象），落在「刷新」那一侧；而被这条 bug
// 咬到的前提「key 没变就沿用原组件、且不看内容」在 Repeat 上不成立。换句话说，
// LazyForEach 的 RELOAD 契约和 Repeat 的更新规则在这一点上是**相反**的。
//
// 补发逻辑本身依赖 DataOperation / DataChangeListener，Repeat 之下这些 API 已
// 不存在，所以代码没法原样留着。留下的是**探针**：统计每次发布里有多少行发生
// 了占位↔真身的翻转。上机时：
//   flips>0 且屏幕上没有空白行 ⇒ 判断成立，可以把这个探针一起删掉；
//   flips>0 且仍有空白行       ⇒ 判断被推翻，Repeat 也需要一条补发路径，
//                                回到 git show cb3c158:entry/src/main/ets/pages/chat/
//                                AlbumGroupDataSource.ets 看当年那段代码；
//   恒为 0                     ⇒ 这条机理没被命中，去查
//                                docs/superpowers/specs/2026-08-26-blank-row-investigation.md
//                                里的候选 C。
//
// ── 删除清单（判断被证实/推翻之后，一次删干净）────────────────────────────
// 1. 本函数 countDeferredFlips 及其上面这整段注释；
// 2. ChatPage.ets：publishGroupsNow 里那段 `if (this.initialMessageStageActive)`
//    的 [BlankRow] 统计，以及 import 列表里的 countDeferredFlips；
// 3. entry/src/test/AlbumGroupDataSource.test.ets 的
//    deferred_flip_probe_counts_placeholder_admissions 用例及其 import；
// 4. docs/superpowers/specs/2026-08-26-blank-row-investigation.md（如果结论
//    已经写进别处的注释，这份调研稿就不必留）。
// 注：探针只在首屏分级揭示期间跑（见 ChatPage 那边的理由），日常滚动/发消息
//     的发布路径上一分钱都不付。
export function countDeferredFlips(prev: AlbumGroup[], next: AlbumGroup[]): number {
  if (prev.length === 0 || next.length === 0) {
    return 0;
  }
  const wasDeferred: Map<string, boolean> = new Map<string, boolean>();
  for (const row of prev) {
    wasDeferred.set(rowIdentity(row), row.initialDeferred === true);
  }
  let flips: number = 0;
  for (const row of next) {
    const before: boolean | undefined = wasDeferred.get(rowIdentity(row));
    if (before !== undefined && before !== (row.initialDeferred === true)) {
      flips++;
    }
  }
  return flips;
}

// 喂给 BasicPrefetcher.visibleAreaChanged 的可见区间。
export interface PrefetchRange {
  start: number;
  end: number;
}

// 把 onScrollIndex 报来的可见区间钳进 [0, total - 1]；集合为空时返回 null，
// 表示这一次**不要调** visibleAreaChanged。
//
// 【为什么需要它——不是防御性编程，是有崩溃日志的】
//
// 官方文档对 visibleAreaChanged 两个参数的原话是「取值范围为 [0, totalCount()-1]。
// **超出范围时计算错误**」，而读 jsPrefetcher.js 可以看到「计算错误」的真实后果
// 是抛异常、并且**转抛给调用方**：
//   · ItemsOnScreenProvider.update：new IndexRange(minVisible, maxVisible + 1)
//     ⇒ maxVisible < minVisible - 1 时 start > end，抛 'Invalid range'；
//   · PrefetchRangeRatio.calculateRatio：
//     new IndexRange(max(0, start - n), min(totalCount, end + n))
//     ⇒ 可见下标越过 totalCount 时同样 start > end，抛 'Invalid range'；
//   · FetchingDriver.visibleAreaChanged 的 catch 写的是
//     `reportError(...); throw e;` —— 记一笔然后原样抛出。
// 这正是 2026-08-27 那份崩溃栈（IndexRange:965 ← calculateRatio:687 ←
// ... ← ChatPage.ets 的 onScrollIndex）。那一次的成因是监听器空实现让
// totalItems 停在 0（见下面 AlbumGroupDataSource.listeners 的注释，已修）。
//
// 修好通知之后仍然需要钳制，因为还剩一条**时序**上的窄口：start / end 来自
// List 的 onScrollIndex，报的是**上一帧布局**里的可见行号；删除消息、切换会话、
// 首屏分级揭示这些场景里，行数组可能已经在这一帧之内变短了。此时行号合法而
// 集合已缩，越界的是行号本身——钳一下就把这条口子彻底堵上，代价是 O(1)。
export function clampPrefetchRange(start: number, end: number, total: number): PrefetchRange | null {
  if (total <= 0) {
    return null;
  }
  const last: number = total - 1;
  const lo: number = start < 0 ? 0 : (start > last ? last : start);
  const hi: number = end < lo ? lo : (end > last ? last : end);
  return { start: lo, end: hi };
}

// 图片预取源。名字保留成 AlbumGroupDataSource 是为了让这次的 diff 只有必须的
// 部分——它现在只是 BasicPrefetcher 的数据面，不再是列表的数据源。
export class AlbumGroupDataSource implements IDataSourcePrefetching {
  private groups: AlbumGroup[] = [];

  // BasicPrefetcher 注册进来的变更监听器。
  //
  // 【这里曾经是空实现，代价是「进任何会话都必崩」】
  //
  // P4 把这个类瘦身成「只是 BasicPrefetcher 的数据面」时，把 register /
  // unregister 写成了空实现，注释里写着「Repeat 不注册监听器」。Repeat 确实
  // 不注册——但 BasicPrefetcher **会**，而且它没有别的途径知道集合变了。
  //
  // 读 jsPrefetcher.js（arkui_ace_engine，frameworks/bridge/declarative_frontend/
  // engine/jsPrefetcher.js）可以把这条链一路对上：
  //   FetchingDriver.setDataSourceInternal
  //     → DataSourceObserver.setDataSource：dataSource.registerDataChangeListener(this)
  //   listener.onDataReloaded()
  //     → batchUpdate([{ kind: 'reloaded', totalCount: dataSource.totalCount() }])
  //     → FetchingDriver.collectionChanged
  //     → FetchingRangeEvaluator.onCollectionChanged：this.totalItems = totalCount
  // register 是空实现并不妨碍构造时那一次 onDataReloaded（它是直接调的），但
  // 此后**再没有人**能触发第二次 ⇒ totalItems 永远停在构造时的 0。
  //
  // 于是每一次 onScrollIndex 都走进 PrefetchRangeRatio.calculateRatio：
  //     start = Math.max(0, visibleRange.start - prefetchCount)   // 比如 30
  //     end   = Math.min(totalCount /* 0 */, visibleRange.end + prefetchCount) // 0
  //     new IndexRange(30, 0)   // start > end ⇒ throw new Error('Invalid range')
  // IndexRange 的构造函数没有钳制，FetchingDriver.visibleAreaChanged 的 catch
  // 是 `reportError(...); throw e;`（**转抛**，不是吞掉），所以异常一路冒到
  // ChatPage 的 onScrollIndex 回调，整个应用崩溃。
  private listeners: DataChangeListener[] = [];

  // ChatPage 每次发布行数组时同步进来。
  //
  // 行数变了就发一次 onDataReloaded：这是 BasicPrefetcher 认识的、表达「整个
  // 集合换了一份」的通知——它自己回头读 totalCount()，正好对应这里「换掉整个
  // 数组」的语义（对比 onDataAdd / onDataDelete 那种逐条的形状，我们根本没有
  // 逐条信息可给：Repeat 自己按 key 差分，P4 删掉的差分引擎不会搬回来）。
  //
  // **只在行数变化时发**，不是每次发布都发：setRows 在每一次发布上都被调用，
  // 包括下载进度跳动那种「只有旁路字段变了」的发布（见 ChatPage.publishGroupsNow
  // 里那段注释），而 onDataReloaded 会让 BasicPrefetcher clearFetched 整个可见
  // 窗口再重发一轮 prefetch。行数是 totalItems 的唯一来源，也是崩溃的唯一成因，
  // O(1) 就能判。代价是：行数不变而内容整体换掉（比如同一个页面切到另一个行数
  // 恰好相同的会话）时，预取的「已取过」账本会短暂陈旧 ⇒ 少预取几张图。那只是
  // 优化失效，气泡自己仍会按需加载——不是正确性问题。
  setRows(next: AlbumGroup[]): void {
    const sizeChanged: boolean = next.length !== this.groups.length;
    // 先落地，再通知：onDataReloaded 的实现会回头调 totalCount()。
    this.groups = next;
    if (sizeChanged) {
      this.notifyReloaded();
    }
  }

  private notifyReloaded(): void {
    // 先拿快照再遍历：监听器在回调里注销自己是允许的。
    const current: DataChangeListener[] = this.listeners;
    for (const listener of current) {
      listener.onDataReloaded();
    }
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

  // Repeat 不会调这两个，BasicPrefetcher 会——理由见 listeners 上面那段。
  // 形状照抄官方 Prefetcher 文档里的 MyDataSource 示例（listeners 数组 +
  // indexOf 去重），只是按本仓的不可变约定换成 concat / filter。
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners = this.listeners.concat([listener]);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter(
      (registered: DataChangeListener): boolean => registered !== listener);
  }
}
