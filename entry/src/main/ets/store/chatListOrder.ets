// 会话列表的「位置索引」：哪些会话在哪个列表里、排第几、置顶没有。
//
// 【为什么单独成一个类】第二层（数据面继续下移）的第一步：把 store 里的
// **索引维护与排序**从 ChatStore 里剥出来，变成一个不碰 UI、不碰 AppStorage、
// 只吃 TdObject 派生的纯结构。剥出来之后它才能在 worker 里跑同一套实现——
// 这一步不动任何行为，ChatStore 只是把内部字段换成委托。
//
// 【谁负责什么】
//   · 本类：positions（列表 → 会话 → PositionInfo）、按位置排好的 id 序列、
//     置顶纪元。全部是**纯数据 + 纯计算**。
//   · ChatStore：会话实体（ChatEntry）、未读角标缓存、订阅与发布。
//     位置变化带来什么副作用（角标失效、置顶纪元广播）由它根据 apply() 的
//     返回值决定——本类不回头调用 store。
//
// 【排序规则】同 TDLib：先按 is_pinned 分两段，段内按 order 字符串降序
// （compareOrderDesc）。order 为 '0' 表示「不在这个列表里」，走删除分支。

import { PositionInfo, compareOrderDesc } from './ChatEntry';

// apply() 的副作用清单：调用方据此决定要不要失效角标缓存 / 广播置顶纪元。
export interface PositionChange {
  added: boolean;
  removed: boolean;
  pinChanged: boolean;
}

// worker → UI 的排序快照（第二层 B2）。只带 id，不带实体。
export interface OrderSnapshot {
  key: string;
  ids: number[];
}

function noChange(): PositionChange {
  return { added: false, removed: false, pinChanged: false };
}

export class ChatListOrder {
  private positions: Map<string, Map<number, PositionInfo>> = new Map<string, Map<number, PositionInfo>>();
  // 排好序的 id 序列，按 listKey 懒建。任何位置变化就地维护它（二分插入），
  // 避免每次发布都重排几百条。
  private ordered: Map<string, number[]> = new Map<string, number[]>();
  private pinEpochs: Map<string, number> = new Map<string, number>();
  // 会话实体是否存在由 ChatStore 说了算：位置表里可能留着还没实体的 id。
  private exists: (chatId: number) => boolean;

  constructor(exists: (chatId: number) => boolean) {
    this.exists = exists;
  }

  bucket(listKey: string): Map<number, PositionInfo> | undefined {
    return this.positions.get(listKey);
  }

  keys(): string[] {
    return Array.from(this.positions.keys());
  }

  forEach(cb: (bucket: Map<number, PositionInfo>, listKey: string) => void): void {
    this.positions.forEach(cb);
  }

  sizeOf(listKey: string): number {
    return this.positions.get(listKey)?.size ?? 0;
  }

  contains(listKey: string, chatId: number): boolean {
    return this.positions.get(listKey)?.has(chatId) === true;
  }

  positionOf(listKey: string, chatId: number): PositionInfo | undefined {
    return this.positions.get(listKey)?.get(chatId);
  }

  isPinned(listKey: string, chatId: number): boolean {
    return this.positions.get(listKey)?.get(chatId)?.isPinned === true;
  }

  pinEpoch(listKey: string): number {
    return this.pinEpochs.get(listKey) ?? 0;
  }

  // 取（必要时建）某个列表的位置表。发布端只在 own 的列表上调用。
  ensure(listKey: string): Map<number, PositionInfo> {
    let bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      bucket = new Map<number, PositionInfo>();
      this.positions.set(listKey, bucket);
    }
    return bucket;
  }

  // 一条位置更新。order === '0' 表示移出该列表。
  // 返回值是调用方要处理的副作用，语义与原来的 setPosition 逐条对齐：
  //   · 移出：删成功才 removed（角标失效）；原本置顶则 pinChanged
  //   · 加入：此前没有这条位置才 added（角标失效）；置顶位变了则 pinChanged
  apply(listKey: string, chatId: number, order: string, isPinned: boolean): PositionChange {
    if (listKey === '') {
      return noChange();
    }
    if (order === '0') {
      const bucket = this.positions.get(listKey);
      const previous = bucket?.get(chatId);
      const deleted: boolean = bucket !== undefined && bucket.delete(chatId);
      const wasPinned: boolean = previous?.isPinned === true;
      if (wasPinned) {
        this.bumpPinEpoch(listKey);
      }
      this.removeOrdered(listKey, chatId);
      return { added: false, removed: deleted, pinChanged: wasPinned };
    }
    const bucket = this.ensure(listKey);
    const previous = bucket.get(chatId);
    const added: boolean = previous === undefined;
    const pinChanged: boolean = (previous?.isPinned ?? false) !== isPinned;
    if (pinChanged) {
      this.bumpPinEpoch(listKey);
    }
    bucket.set(chatId, { order, isPinned });
    this.insertOrdered(listKey, chatId);
    return { added, removed: false, pinChanged };
  }

  // 按当前位置排序的会话 id。懒建一次，之后由 apply 就地维护。
  orderedIds(listKey: string): number[] {
    const cached = this.ordered.get(listKey);
    if (cached !== undefined) {
      return cached;
    }
    const bucket = this.positions.get(listKey);
    if (bucket === undefined) {
      return [];
    }
    const ids: number[] = [];
    bucket.forEach((_pos: PositionInfo, id: number): void => {
      if (this.exists(id)) {
        ids.push(id);
      }
    });
    ids.sort((a: number, b: number): number => this.compare(listKey, a, b));
    this.ordered.set(listKey, ids);
    return ids;
  }

  // 分组定义变了 / 列表重载：丢掉排序缓存，下次现排。
  dropOrdered(listKey: string): void {
    this.ordered.delete(listKey);
  }

  // 账号切换/重建运行时：这一份索引整体作废。
  clear(): void {
    this.positions.clear();
    this.ordered.clear();
    this.pinEpochs.clear();
  }

  private compare(listKey: string, a: number, b: number): number {
    const bucket = this.positions.get(listKey);
    const pa = bucket?.get(a);
    const pb = bucket?.get(b);
    if (pa === undefined) { return pb === undefined ? 0 : 1; }
    if (pb === undefined) { return -1; }
    if (pa.isPinned !== pb.isPinned) {
      return pa.isPinned ? -1 : 1;
    }
    return compareOrderDesc(pa.order, pb.order);
  }

  private removeOrdered(listKey: string, chatId: number): void {
    const ids = this.ordered.get(listKey);
    if (ids === undefined) {
      return;
    }
    const index = ids.indexOf(chatId);
    if (index >= 0) {
      ids.splice(index, 1);
    }
  }

  private insertOrdered(listKey: string, chatId: number): void {
    const ids = this.ordered.get(listKey);
    if (ids === undefined || !this.exists(chatId)) {
      return;
    }
    // 先删再加：同一条位置被重复推过来时不能在同一序列里出现两次。
    const previous = ids.indexOf(chatId);
    if (previous >= 0) {
      ids.splice(previous, 1);
    }
    let lo = 0;
    let hi = ids.length;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (this.compare(listKey, chatId, ids[mid]) < 0) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    ids.splice(lo, 0, chatId);
  }

  private bumpPinEpoch(listKey: string): void {
    this.pinEpochs.set(listKey, this.pinEpoch(listKey) + 1);
  }
}

// 第二层 B2 的对账判据。
//
// 【为什么要区分"两份看到的集合不同"和"排序不同"】影子索引和 UI 各自消化同一
// 条更新流，但 UI 是异步的：快照到达时它可能还没处理完同一批更新，于是本地
// 序列更短、或缺少某个列表。那是**时差**，不是排序错。真正的错只有一种：
// 两边都知道的会话，相对顺序不一样。
//
// 所以：先在交集上比相对顺序，再报覆盖率。覆盖率 100% 且顺序一致才算通过。
export interface OrderDiff {
  text: string;
  common: number;
  localLen: number;
  remoteLen: number;
}

export function compareOrderIds(local: number[], remote: number[]): OrderDiff {
  const remoteRank: Map<number, number> = new Map<number, number>();
  for (let i = 0; i < remote.length; i++) {
    remoteRank.set(remote[i], i);
  }
  // 只保留两边都有的 id，按各自序列的顺序取出来比。
  const localCommon: number[] = local.filter((id: number): boolean => remoteRank.has(id));
  const localSet: Set<number> = new Set<number>(local);
  const remoteCommon: number[] = remote.filter((id: number): boolean => localSet.has(id));
  let text: string = '';
  for (let i = 0; i < localCommon.length; i++) {
    if (localCommon[i] !== remoteCommon[i]) {
      text = `rel=${i} local=${localCommon[i]} worker=${remoteCommon[i]}`;
      break;
    }
  }
  return { text, common: localCommon.length, localLen: local.length, remoteLen: remote.length };
}
