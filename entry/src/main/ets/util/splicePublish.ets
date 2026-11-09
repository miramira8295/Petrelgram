// 让 Repeat 走「同一可观察数组上 splice」而不是「整份换数组」的判定与补丁。
//
// 【为什么】MVCP 最小对照页（2026-09-11 临时页，判读后已删；结论在记忆
// mvcp-splice-publish-root-cause）在
// stackFromEnd=false（真实消息列表可滚动之后的常态）下：
//   · 整份换数组（我们现在的发布形状）：LOST 12/12——视口停在旧下标，内容换成新页
//   · 同一 @Local 数组 splice：KEPT 8/8——下标正好 +N，内容与 y 纹丝不动
// 交替行高下结论相同。也就是说 List.maintainVisibleContentPosition 的"显示区外
// 前插保位"从来没有被我们触发过——才需要 prime 去救，prime 又掐断惯性
// （三档固定行高实验：prime 之后下一次滚动事件 47/49 是手指，不是惯性延续）。
//
// 【做什么】给定发布前后的行身份序列，判断这次发布是不是**纯前插**：新序列
// = 若干新行 + 原序列原样。是，就返回前插行数，让调用方 splice 进常驻数组、
// 对内容变了的旧行按下标原地替换；不是（跳转落地、重建、裁剪、删除、追加、
// 编辑）就照旧整份替换——那些路径本来就不指望 MVCP。
//
// 这里只比**身份**（rowIdentity），不比内容：内容变了的行由调用方按对象引用
// 是否相同来打补丁（reuseUnchangedRows 已保证未变行是同一对象）。

// 总开关。false = 回到整份换数组（那时前插锚点必须同步打开，见
// util/anchorRestore 的 PREPEND_ANCHOR_ENABLED）。
export const SPLICE_PUBLISH_ENABLED: boolean = true;

// 'patch' / 'append' 两种形状的独立开关（前插与裁剪不受它影响）。
//
// 单独拎出来是因为它们的失败模式和前插不一样：前插万一没保住位，用户看到的是
// 跳一下；而等长原地补丁若 Repeat 没认出「同 key 不同对象」要重绘，用户看到的
// 是**占位行永远不变成真行**——首屏一片空白。真机验过之前留一个能一键退回的
// 常量，别把它和总开关合并。
export const SPLICE_PATCH_PUBLISH_ENABLED: boolean = true;

export interface PrependSplicePlan {
  // 前插的行数（新序列开头有多少行是新的）。
  head: number;
}

export function planPrependSplice(prevIds: string[], nextIds: string[]): PrependSplicePlan | null {
  const head: number = nextIds.length - prevIds.length;
  if (prevIds.length === 0 || head <= 0) {
    return null;
  }
  for (let i = 0; i < prevIds.length; i++) {
    if (nextIds[head + i] !== prevIds[i]) {
      return null;
    }
  }
  return { head };
}

// 前插之后，原有区段里哪些下标的对象换了（内容变了）。返回的是 next 里的下标。
export function patchIndicesAfterPrepend(prev: Object[], next: Object[], head: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < prev.length; i++) {
    if (next[head + i] !== prev[i]) {
      out.push(head + i);
    }
  }
  return out;
}

// 边缘 splice：除纯前插外，再认两种**窗口裁剪**的形状——从头砍掉若干行、从尾
// 砍掉若干行。真机日志（2026-09-11）：30 次 [Trim] 里 12 次 `top … MOVED`，全部
// 走的是整份换数组；官方 MVCP 的承诺是"显示区外**插入或删除**"，删除同样要在
// 同一个可观察数组上 splice 才会被认成删除。
export interface EdgeSplicePlan {
  kind: string;   // 'prepend' | 'append' | 'patch' | 'dropHead' | 'dropTail'
  count: number;  // prepend/append: 新行数；dropHead/dropTail: 砍掉的行数；patch: 0
}

// 一次 splice 最多带多少个新行。超过就走整份替换：`splice(i, 0, ...arr)` 是把
// 数组摊成实参，量大时会撑爆调用栈。真实路径上 prepend 是一页（~30 行）、
// append 是一两条新消息，这个上限只是兜底，不是策略。
export const MAX_SPLICE_INSERT: number = 2000;

// 形状判定的**对象优先**版本，给热路径用。
//
// 【为什么不直接喂两个身份数组】那要对每一行都拼一次 rowIdentity（模板串），
// 一次发布就是 2N 个字符串；而首屏分帧揭示每帧发布一次、列表可以上千行。
// reuseUnchangedRows 已经保证"内容没变的行还是同一个对象"，所以对象相同时
// 身份必然相同——只有对象不同的那几个位置才值得去算身份。揭示一帧只换一行，
// 于是每帧只算一对。
function sameRow(a: Object, b: Object, identity: (row: Object) => string): boolean {
  return a === b || identity(a) === identity(b);
}

export function planEdgeSpliceRows(
  prev: Object[], next: Object[], identity: (row: Object) => string
): EdgeSplicePlan | null {
  if (prev.length === 0) {
    return null;
  }
  // 【等长原地补丁】首屏分帧揭示走的就是这条路：stageInitialMessageGroups 返回
  // 的是**等长**数组——未揭示的行换成 deferredCopy 占位，而占位行的 key/head 与
  // 真行逐字节相同 ⇒ rowIdentity 不变。旧代码在这里两个分支全落空，退回整份
  // 替换，于是每揭示一行就换一次 @Local 数组引用，把 ChatPage.build() 整个拖着
  // 重跑一遍（首屏 trace：CustomNodeUpdate[ChatPage] 11 次 / 62.1ms）。
  // 身份序列一致时只按下标原地换对象，数组引用不动，build() 不再被牵连。
  if (prev.length === next.length) {
    for (let i = 0; i < prev.length; i++) {
      if (!sameRow(prev[i], next[i], identity)) {
        return null;
      }
    }
    return { kind: 'patch', count: 0 };
  }
  const grow: number = next.length - prev.length;
  if (grow > 0) {
    // 纯前插：新序列 = 若干新行 + 原序列原样。MVCP 只认这一种。
    let suffixMatch: boolean = true;
    for (let i = 0; i < prev.length; i++) {
      if (!sameRow(prev[i], next[grow + i], identity)) { suffixMatch = false; break; }
    }
    if (suffixMatch) {
      return grow <= MAX_SPLICE_INSERT ? { kind: 'prepend', count: grow } : null;
    }
    // 【尾部追加】新消息到达走这条。它与 MVCP 无关（保位说的是显示区**上方**
    // 的增删），纯粹是为了不换数组引用。
    let prefixMatch: boolean = true;
    for (let i = 0; i < prev.length; i++) {
      if (!sameRow(prev[i], next[i], identity)) { prefixMatch = false; break; }
    }
    if (prefixMatch) {
      return grow <= MAX_SPLICE_INSERT ? { kind: 'append', count: grow } : null;
    }
    return null;
  }
  const drop: number = prev.length - next.length;
  if (next.length === 0) {
    return null;
  }
  let headMatch: boolean = true;
  for (let i = 0; i < next.length; i++) {
    if (!sameRow(prev[drop + i], next[i], identity)) { headMatch = false; break; }
  }
  if (headMatch) {
    return { kind: 'dropHead', count: drop };
  }
  let tailMatch: boolean = true;
  for (let i = 0; i < next.length; i++) {
    if (!sameRow(prev[i], next[i], identity)) { tailMatch = false; break; }
  }
  return tailMatch ? { kind: 'dropTail', count: drop } : null;
}

// 身份数组版。单测与非热路径用它；语义与上面完全一致（字符串的 === 就是身份比较）。
export function planEdgeSplice(prevIds: string[], nextIds: string[]): EdgeSplicePlan | null {
  return planEdgeSpliceRows(prevIds, nextIds, (row: Object): string => row as string);
}

// ── 临时探针（2026-09-11）。查清 Repeat 的 duplicate key 来自哪一侧后删掉 ──
//
// 真机日志（13:06:45.858–.902）里连续 14 条：
//   AceStateMgmt: __RepeatVirtualScroll2Impl: Detected duplicate key for index 43!
// 落在一次 29 行前插之后 8ms，而同一段里另外三次同样的前插一条都没有。
//
// 行 key 是 `message_group_${rowIdentity}_${langEpoch}_${rebuildEpoch}`，后两个
// 分量全表一致 ⇒ key 重复 ⟺ rowIdentity 重复。发布那一刻扫一遍就能判：
//   · 扫到  → 数据真有两行同身份（看两行的 id/rowId 能进一步分清是 rowId
//            继承出岔子，还是相册身份撞了）
//   · 扫不到 → 是 Repeat 在 splice 之后重整内部 key→index 表的误报
export const PUBLISH_DUPLICATE_SCAN: boolean = true;

export interface DuplicateRowReport {
  identity: string;
  firstIndex: number;
  secondIndex: number;
}

// 只扫表头这么多行。
//
// 【为什么要有上限】这个探针做的正是本轮刚从发布热路径上删掉的那件事——给每
// 一行拼一次 rowIdentity。列表能到上千行，全扫一遍是 ~0.2-0.3ms，而它恰好落在
// 前插那一帧上（那是本来就重的一帧）。观测到的重复在下标 43–56、前插是 29 行，
// 全在表头附近，512 行的窗口留了十几倍余量，代价压到 ~0.1ms 以内。
export const DUPLICATE_SCAN_MAX_ROWS: number = 512;

// 最多报前 limit 组，够定性即可。返回空数组 = 扫过的窗口里没有同身份行。
export function findDuplicateIdentities(
  rows: Object[], identity: (row: Object) => string, limit: number = 3,
  maxRows: number = DUPLICATE_SCAN_MAX_ROWS
): DuplicateRowReport[] {
  const seen: Map<string, number> = new Map<string, number>();
  const out: DuplicateRowReport[] = [];
  const end: number = Math.min(rows.length, Math.max(0, maxRows));
  for (let i = 0; i < end; i++) {
    const id: string = identity(rows[i]);
    const first: number | undefined = seen.get(id);
    if (first === undefined) {
      seen.set(id, i);
      continue;
    }
    out.push({ identity: id, firstIndex: first, secondIndex: i });
    if (out.length >= limit) {
      return out;
    }
  }
  return out;
}
