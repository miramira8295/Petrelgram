import { ChatEntry } from '../../store/ChatEntry';

// Content signature, independent of LazyForEach identity. Revision, per-list
// pin and context changes publish a new observable row snapshot.
export function chatListRowKeys(items: ChatEntry[], languageEpoch: number, muteEpoch: number,
  isPinned: (chatId: number) => boolean): string[] {
  return items.map((item: ChatEntry): string =>
    `${item.id}_${item.revision}_${isPinned(item.id) ? 1 : 0}_${languageEpoch}_${muteEpoch}`);
}

interface CachedRowKey {
  id: number;
  revision: number;
  pinned: boolean;
  key: string;
  seen: number;
}

// One cache per list view. Keys handed to the DataSource are immutable:
// later publications must not mutate its previous diff baseline.
export class ChatListRowKeyCache {
  private rows: CachedRowKey[] = [];
  private byId: Map<number, CachedRowKey> = new Map();
  private listKey: string = '';
  private languageEpoch: number = -1;
  private muteEpoch: number = -1;
  private pinEpoch: number = -1;
  private generation: number = 0;

  clear(): void {
    this.rows = [];
    this.byId.clear();
    this.listKey = '';
    this.languageEpoch = -1;
    this.muteEpoch = -1;
    this.pinEpoch = -1;
    this.generation = 0;
  }

  keys(items: ChatEntry[], listKey: string, languageEpoch: number, muteEpoch: number,
    pinEpoch: number, isPinned: (chatId: number) => boolean): string[] {
    if (listKey !== this.listKey) { this.clear(); }
    const contextChanged: boolean = languageEpoch !== this.languageEpoch || muteEpoch !== this.muteEpoch;
    const pinsChanged: boolean = pinEpoch !== this.pinEpoch;
    const generation: number = ++this.generation;
    const nextRows: CachedRowKey[] = [];
    const keys: string[] = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      // Content-only updates take the same-index path, avoiding even a Map lookup.
      const atIndex = this.rows[i];
      let cached: CachedRowKey | undefined = atIndex !== undefined && atIndex.id === item.id
        ? atIndex : this.byId.get(item.id);
      const pinned: boolean = cached === undefined || pinsChanged ? isPinned(item.id) : cached.pinned;
      if (cached === undefined) {
        cached = {
          id: item.id, revision: item.revision, pinned,
          key: `${item.id}_${item.revision}_${pinned ? 1 : 0}_${languageEpoch}_${muteEpoch}`,
          seen: generation
        };
        this.byId.set(item.id, cached);
      } else {
        // These records never leave the cache; only immutable key strings do.
        // Update in place to avoid allocating one record per changed row.
        if (cached.revision !== item.revision || cached.pinned !== pinned || contextChanged) {
          cached.revision = item.revision;
          cached.pinned = pinned;
          cached.key = `${item.id}_${item.revision}_${pinned ? 1 : 0}_${languageEpoch}_${muteEpoch}`;
        }
        cached.seen = generation;
      }
      nextRows.push(cached);
      keys.push(cached.key);
    }
    // Only membership removal needs a sweep; ordinary content/reorder updates
    // keep the map as-is. Do not retain every chat ever seen by this view.
    if (this.byId.size > items.length) {
      this.byId.forEach((row: CachedRowKey, id: number): void => {
        if (row.seen !== generation) { this.byId.delete(id); }
      });
    }
    this.rows = nextRows;
    this.listKey = listKey;
    this.languageEpoch = languageEpoch;
    this.muteEpoch = muteEpoch;
    this.pinEpoch = pinEpoch;
    return keys;
  }
}
