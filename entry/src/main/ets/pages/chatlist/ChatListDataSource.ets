import { ChatEntry } from '../../store/ChatEntry';
import { keyTableReload, newKeyTableId } from '../../util/keyGuard';

// LazyForEach data source for the chat list.
//
// The list was a plain ForEach, and ForEach builds every child up front: a
// device log showed `Ids.size[424]`, i.e. 424 ChatRow components alive for a
// list that shows about eight. That is paid on the list's first layout, again
// in memory for as long as the screen exists, and again on every update that
// marks the ForEach dirty.
//
// The diff mirrors AlbumGroupDataSource: compare keys, notify only the rows
// that actually differ. Chat lists reorder constantly (a new message moves a
// chat to the top), so a blanket reload on every update would rebuild the
// visible rows several times a second.
export class ChatListDataSource implements IDataSource {
  private items: ChatEntry[] = [];
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];
  // Diagnostic only: one key table per instance, since each list body has its
  // own LazyForEach. See AlbumGroupDataSource.keyTableId.
  readonly keyTableId: string = newKeyTableId('chatlist');

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ChatEntry {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  // See AlbumGroupDataSource.reload: the row key embeds the language epoch, so
  // a bump renames every row without the data changing at all.
  reload(): void {
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  update(next: ChatEntry[], nextKeys: string[]): void {
    const prevKeys = this.keys;
    const prevIds = this.items.map((item: ChatEntry): number => item.id);
    const nextIds = next.map((item: ChatEntry): number => item.id);
    this.items = next;
    this.keys = nextKeys;

    // 按身份（chat id）算前后缀公共段，中间那截才是真正变动的部分。
    const minLen = Math.min(prevIds.length, nextIds.length);
    let p = 0;
    while (p < minLen && prevIds[p] === nextIds[p]) {
      p++;
    }
    let s = 0;
    while (s < minLen - p && prevIds[prevIds.length - 1 - s] === nextIds[nextIds.length - 1 - s]) {
      s++;
    }
    const oldMid = prevIds.length - p - s;
    const newMid = nextIds.length - p - s;

    // 身份处处未变，只可能是内容变了。
    if (oldMid === 0 && newMid === 0) {
      const ops: DataOperation[] = [];
      for (let i = 0; i < nextKeys.length; i++) {
        if (prevKeys[i] !== nextKeys[i]) {
          ops.push({ type: DataOperationType.CHANGE, index: i } as DataChangeOperation);
        }
      }
      if (ops.length === 0) {
        return;
      }
      this.notify(ops);
      return;
    }

    // keyGuard checks the rows LazyForEach actually materializes. Avoid a
    // second whole-list diagnostic Map on every incoming-message reorder.

    // 纯插入。翻页加载更多会话走的就是这条——原来只要长度一变就整表 RELOAD，
    // 而 RELOAD 会让 LazyForEach 把所有行作废重建。
    if (oldMid === 0) {
      this.notifyInsert(p, newMid, nextKeys);
      this.notifySurvivorChanges(prevKeys, nextKeys, p, s, newMid, 0);
      return;
    }
    // 纯删除（退出会话、归档、被移出文件夹）。
    if (newMid === 0) {
      this.notify([{
        type: DataOperationType.DELETE, index: p, count: oldMid
      } as DataDeleteOperation]);
      this.notifySurvivorChanges(prevKeys, nextKeys, p, s, 0, oldMid);
      return;
    }

    // 其余一律 RELOAD，重排是主要的一类：聊天列表随时重排（来新消息就置顶），
    // 而 CHANGE 的语义是"同一项换了内容"。重排之后每个下标坐着的是**另一个**
    // 会话，报成 CHANGE 等于告诉列表身份没变、而那个 key 已经注册在别的下标上
    // ——这正是"Use repeat key"告警和行渲染成别的会话的来源，之前踩过。
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  private notifyInsert(at: number, count: number, nextKeys: string[]): void {
    const keys: string[] = [];
    for (let i = at; i < at + count; i++) {
      keys.push(nextKeys[i]);
    }
    this.notify([{
      type: DataOperationType.ADD, index: at, count: count, key: keys
    } as DataAddOperation]);
  }

  // 结构通知与内容通知分开发，且内容通知的下标用的是**结构变化之后**的位置。
  // 混在一批里，ADD 会一边移动后续下标、CHANGE 又按原下标定位，落点对不对取决
  // 于框架的应用顺序——AlbumGroupDataSource 的注释记录过这么翻过车。
  private notifySurvivorChanges(prevKeys: string[], nextKeys: string[],
    p: number, s: number, added: number, removed: number): void {
    const ops: DataOperation[] = [];
    for (let i = 0; i < p; i++) {
      if (prevKeys[i] !== nextKeys[i]) {
        ops.push({ type: DataOperationType.CHANGE, index: i } as DataChangeOperation);
      }
    }
    for (let i = 0; i < s; i++) {
      const prevIndex = prevKeys.length - 1 - i;
      const nextIndex = nextKeys.length - 1 - i;
      if (prevKeys[prevIndex] !== nextKeys[nextIndex]) {
        ops.push({ type: DataOperationType.CHANGE, index: nextIndex } as DataChangeOperation);
      }
    }
    if (ops.length > 0) {
      this.notify(ops);
    }
  }

  private notify(ops: DataOperation[]): void {
    // This list only ever emits RELOAD or CHANGE; CHANGE keeps the row's
    // identity, so only RELOAD invalidates the diagnostic key table.
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
