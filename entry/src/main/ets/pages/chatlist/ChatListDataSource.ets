import { ChatEntry } from '../../store/ChatEntry';
import { ChatListRowState } from './ChatListRowState';
import { keyTableAdd, keyTableDelete, keyTableReload, newKeyTableId } from '../../util/keyGuard';

// LazyForEach owns membership/order. ObjectLink owns content: a new revision
// updates the existing row rather than renaming and rebuilding its subtree.
export class ChatListDataSource implements IDataSource {
  private items: ChatEntry[] = [];
  private rows: ChatListRowState[] = [];
  private byId: Map<number, ChatListRowState> = new Map();
  private listeners: DataChangeListener[] = [];
  private contentKeys: string[] = [];
  private reloadEpoch: number = 0;
  readonly keyTableId: string = newKeyTableId('chatlist');

  totalCount(): number { return this.rows.length; }

  getData(index: number): ChatListRowState { return this.rows[index]; }

  // This is identity, not the content signature. A deliberate context reload
  // (language/scope mute) still rebuilds rows; ordinary updates and reorders do not.
  getKey(index: number): string { return `${this.rows[index].id}_${this.reloadEpoch}`; }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener);
  }

  reload(nextContentKeys: string[]): void {
    this.reloadEpoch++;
    this.syncRows(this.items, nextContentKeys);
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  update(next: ChatEntry[], nextContentKeys: string[]): void {
    const previous = this.items;
    this.items = next;
    // Called only after the view's publication gates open. Hidden/menu/touch
    // freezes must not leak new snapshots through this observable side channel.
    this.syncRows(next, nextContentKeys);

    const minLen = Math.min(previous.length, next.length);
    let p = 0;
    while (p < minLen && previous[p].id === next[p].id) { p++; }
    let s = 0;
    while (s < minLen - p && previous[previous.length - 1 - s].id === next[next.length - 1 - s].id) { s++; }
    const oldMid = previous.length - p - s;
    const newMid = next.length - p - s;

    // No CHANGE notifications: they can rebuild ListItem even with a stable key.
    // Changed snapshots have already notified their ObjectLink subscribers.
    if (oldMid === 0 && newMid === 0) { return; }
    if (oldMid === 0) {
      const keys: string[] = [];
      for (let i = p; i < p + newMid; i++) { keys.push(this.getKey(i)); }
      this.notify([{ type: DataOperationType.ADD, index: p, count: newMid, key: keys } as DataAddOperation]);
      return;
    }
    if (newMid === 0) {
      this.notify([{ type: DataOperationType.DELETE, index: p, count: oldMid } as DataDeleteOperation]);
      return;
    }
    // Never label reordered identities as CHANGE. RELOAD compares stable keys,
    // retaining surviving cells; content is carried by those same row objects.
    this.notify([{ type: DataOperationType.RELOAD } as DataReloadOperation]);
  }

  private syncRows(next: ChatEntry[], contentKeys: string[]): void {
    const rows: ChatListRowState[] = [];
    const previousRows = this.rows;
    const previousKeys = this.contentKeys;
    for (let i = 0; i < next.length; i++) {
      const chat = next[i];
      const atIndex = previousRows[i];
      let row = atIndex !== undefined && atIndex.id === chat.id ? atIndex : this.byId.get(chat.id);
      if (row === undefined) {
        row = new ChatListRowState(chat, contentKeys[i]);
        this.byId.set(chat.id, row);
      } else if (row !== atIndex || previousKeys[i] !== contentKeys[i]) {
        row.update(chat, contentKeys[i]);
      }
      rows.push(row);

    }
    if (this.byId.size > rows.length) {
      const surviving: Set<number> = new Set();
      for (const row of rows) { surviving.add(row.id); }
      this.byId.forEach((_row: ChatListRowState, id: number): void => {
        if (!surviving.has(id)) { this.byId.delete(id); }
      });
    }
    this.rows = rows;
    this.contentKeys = contentKeys;
  }

  private notify(ops: DataOperation[]): void {
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
    for (const listener of this.listeners) { listener.onDatasetChange(ops); }
  }
}
