import { keyTableReload, newKeyTableId } from '../../util/keyGuard';

// 新出现的身份在这段时间内算「新到」（见 isFresh）。
const FRESH_WINDOW_MS: number = 600;

// 通用的 LazyForEach 数据源：按身份（id）比较前后两份，只通知真正变了的那几行。
//
// 为什么不用 ForEach：ForEach 一次性把每一行都建出来。几千个联系人就是几千棵行组件
// 同时活着，首次布局、内存、每次更新都按全量付（2026-09-14 用户：「翻联系人列表也很卡，
// 几千个联系人太多了」）。LazyForEach 只建可视区 + cachedCount 那几行，其余滚动时逐帧
// 补建，配合 @Reusable 行组件复用节点——与首页会话列表同一套做法。
//
// 算法与 pages/chatlist/ChatListDataSource 一致（那边逐条写了理由），这里只是把
// 「身份」从会话 id 泛化成调用方给的字符串：
//   · 前后缀按 id 对齐，中间那截才是真正的变动；
//   · 身份处处未变、只有内容签名（key）变 → 逐行 CHANGE；
//   · 纯插入（翻页、前插）→ ADD（带 key）+ 幸存行的 CHANGE；
//   · 纯删除 → DELETE + 幸存行的 CHANGE；
//   · 其余（重排）→ RELOAD。重排后同一下标坐的是另一项，报 CHANGE 会让框架以为身份没变。
export class KeyedListDataSource<T> implements IDataSource {
  private items: T[] = [];
  private ids: string[] = [];
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];
  // 诊断用：每个列表实例一张 key 表（见 util/keyGuard）。
  readonly keyTableId: string;
  // 最近一次带新身份的 update 里新出现的 id，和它们算「新到」的截止时刻（见 isFresh）。
  private freshIds: Set<string> = new Set<string>();
  private freshUntil: number = 0;
  private readonly now: () => number;

  // now 只给单测注入假时钟用。
  constructor(tablePrefix: string, now: () => number = (): number => Date.now()) {
    this.keyTableId = newKeyTableId(tablePrefix);
    this.now = now;
  }

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener): boolean => l !== listener);
  }

  // 行 key 里含语言/外观纪元时，纪元一变整表改名、数据本身没变——用它整表重来。
  reload(): void {
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  // 这一行是不是刚到的数据：行上带入场转场的，只给它播。LazyForEach 滑动时按需创建的节点
  // 同样是新插入的，带自身动画参数的 transition 会跟着播，得靠它把「新数据」和「滑进来」分开。
  isFresh(id: string): boolean {
    return this.freshIds.has(id) && this.now() <= this.freshUntil;
  }

  // 三个数组等长：id 是身份，key 是内容签名（同时就是 LazyForEach 的 key）。
  update(next: T[], nextIds: string[], nextKeys: string[]): void {
    const prevIds: string[] = this.ids;
    const prevKeys: string[] = this.keys;
    this.items = next;
    this.ids = nextIds;
    this.keys = nextKeys;

    const minLen: number = Math.min(prevIds.length, nextIds.length);
    let p: number = 0;
    while (p < minLen && prevIds[p] === nextIds[p]) {
      p++;
    }
    let s: number = 0;
    while (s < minLen - p && prevIds[prevIds.length - 1 - s] === nextIds[nextIds.length - 1 - s]) {
      s++;
    }
    const oldMid: number = prevIds.length - p - s;
    const newMid: number = nextIds.length - p - s;
    this.noteFreshIds(prevIds.slice(p, p + oldMid), nextIds.slice(p, p + newMid));

    if (oldMid === 0 && newMid === 0) {
      const ops: DataOperation[] = [];
      for (let i = 0; i < nextKeys.length; i++) {
        if (prevKeys[i] !== nextKeys[i]) {
          ops.push({ type: DataOperationType.CHANGE, index: i } as DataChangeOperation);
        }
      }
      this.notify(ops);
      return;
    }
    if (oldMid === 0) {
      const added: string[] = nextKeys.slice(p, p + newMid);
      this.notify([{
        type: DataOperationType.ADD, index: p, count: newMid, key: added
      } as DataAddOperation]);
      this.notifySurvivorChanges(prevKeys, nextKeys, p, s);
      return;
    }
    if (newMid === 0) {
      this.notify([{
        type: DataOperationType.DELETE, index: p, count: oldMid
      } as DataDeleteOperation]);
      this.notifySurvivorChanges(prevKeys, nextKeys, p, s);
      return;
    }
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  // 新身份只可能出现在前后缀之间那一截；重排、删除、只改内容都不产生新到，也不续旧的窗口。
  private noteFreshIds(prevMid: string[], nextMid: string[]): void {
    if (nextMid.length === 0) {
      return;
    }
    const known: Set<string> = new Set<string>(prevMid);
    const fresh: string[] = nextMid.filter((id: string): boolean => !known.has(id));
    if (fresh.length === 0) {
      return;
    }
    this.freshIds = new Set<string>(fresh);
    this.freshUntil = this.now() + FRESH_WINDOW_MS;
  }

  // 结构通知与内容通知分两批发，内容通知用结构变化之后的下标（理由同 ChatListDataSource）。
  private notifySurvivorChanges(prevKeys: string[], nextKeys: string[], p: number, s: number): void {
    const ops: DataOperation[] = [];
    for (let i = 0; i < p; i++) {
      if (prevKeys[i] !== nextKeys[i]) {
        ops.push({ type: DataOperationType.CHANGE, index: i } as DataChangeOperation);
      }
    }
    for (let i = 0; i < s; i++) {
      const prevIndex: number = prevKeys.length - 1 - i;
      const nextIndex: number = nextKeys.length - 1 - i;
      if (prevKeys[prevIndex] !== nextKeys[nextIndex]) {
        ops.push({ type: DataOperationType.CHANGE, index: nextIndex } as DataChangeOperation);
      }
    }
    this.notify(ops);
  }

  private notify(ops: DataOperation[]): void {
    if (ops.length === 0) {
      return;
    }
    for (const op of ops) {
      if (op.type === DataOperationType.RELOAD) {
        keyTableReload(this.keyTableId);
      }
    }
    for (const l of this.listeners) {
      l.onDatasetChange(ops);
    }
  }
}
