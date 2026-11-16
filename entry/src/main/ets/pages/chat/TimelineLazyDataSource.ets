import { drawnStageMetrics, DrawnStage, DrawnRowChangeSource } from '../../util/drawnStageMetrics';
import { AlbumGroup } from '../../util/collapseAlbums';

// Stable identity holder. Content updates notify only readers of this row;
// they do not rename a LazyForEach item or rebuild its ListItem.
@ObservedV2
export class TimelineLazyEntry {
  readonly key: string;
  @Trace item: AlbumGroup;
  // Index is callback metadata, not visual state. Head insertion must not dirty
  // every retained row. Size callbacks read the current index; -1 means removed.
  index: number;

  constructor(key: string, item: AlbumGroup, index: number) {
    this.key = key;
    this.item = item;
    this.index = index;
  }
}

// Separate from AlbumGroupDataSource (BasicPrefetcher). A structural update uses
// only onDatasetChange; content/placeholder changes use the stable @Trace item.
// O(N) time and O(N) space per changed window, O(1) getData. No per-row searches,
// no content hashing, no retained entries outside the current window.
export class TimelineLazyDataSource implements IDataSource {
  private rows: TimelineLazyEntry[] = [];
  private byKey: Map<string, TimelineLazyEntry> = new Map<string, TimelineLazyEntry>();
  private byRow: Map<AlbumGroup, TimelineLazyEntry> = new Map<AlbumGroup, TimelineLazyEntry>();
  private listeners: DataChangeListener[] = [];
  private languageEpoch: number = -1;
  private rebuildEpoch: number = -1;

  totalCount(): number { return this.rows.length; }
  getData(index: number): TimelineLazyEntry { return this.rows[index]; }

  setRows(next: AlbumGroup[], keyOf: (row: AlbumGroup) => string,
    languageEpoch: number, rebuildEpoch: number): void {
    const traced = drawnStageMetrics.begin(DrawnStage.LazySetRows);
    try {
      const prev: TimelineLazyEntry[] = this.rows;
      const sameEpoch: boolean = languageEpoch === this.languageEpoch && rebuildEpoch === this.rebuildEpoch;
      const rows: TimelineLazyEntry[] = [];
      const byKey: Map<string, TimelineLazyEntry> = new Map<string, TimelineLazyEntry>();
      const byRow: Map<AlbumGroup, TimelineLazyEntry> = new Map<AlbumGroup, TimelineLazyEntry>();
      for (let i = 0; i < next.length; i++) {
        const group: AlbumGroup = next[i];
        const exact: TimelineLazyEntry | undefined = sameEpoch ? this.byRow.get(group) : undefined;
        const key: string = exact !== undefined ? exact.key : keyOf(group);
        const retained: TimelineLazyEntry | undefined = exact ?? this.byKey.get(key);
        const row: TimelineLazyEntry = retained ?? new TimelineLazyEntry(key, group, i);
        rows.push(row);
        byKey.set(key, row);
        byRow.set(group, row);
      }

      const min: number = Math.min(prev.length, rows.length);
      let prefix: number = 0;
      while (prefix < min && prev[prefix] === rows[prefix]) { prefix++; }
      let suffix: number = 0;
      while (suffix < min - prefix && prev[prev.length - 1 - suffix] === rows[rows.length - 1 - suffix]) { suffix++; }
      const removed: number = prev.length - prefix - suffix;
      const added: number = rows.length - prefix - suffix;

      // Publish all callback-visible data before notifying the framework. Removed
      // rows may still deliver a delayed size event; mark them inert first.
      this.rows = rows;
      this.byKey = byKey;
      this.byRow = byRow;
      this.languageEpoch = languageEpoch;
      this.rebuildEpoch = rebuildEpoch;
      for (const row of prev) {
        if (!byKey.has(row.key)) { row.index = -1; }
      }
      for (let i = 0; i < rows.length; i++) { rows[i].index = i; }
      for (let i = 0; i < rows.length; i++) {
        if (rows[i].item !== next[i]) {
          drawnStageMetrics.rowChanged(DrawnRowChangeSource.List, rows[i].item, next[i]);
          rows[i].item = next[i];
        }
      }

      if (removed === 0 && added === 0) { return; }
      let operation: DataOperation;
      if (removed === 0) {
        // Let LazyForEach's keyGenerator own keys, including its framework prefix.
        // Supplying raw application keys also seeds a separate native cache path.
        operation = { type: DataOperationType.ADD, index: prefix, count: added } as DataAddOperation;
      } else if (added === 0) {
        operation = { type: DataOperationType.DELETE, index: prefix, count: removed } as DataDeleteOperation;
      } else {
        // Reorder/disjoint windows: stable keys still retain surviving entries.
        operation = { type: DataOperationType.RELOAD } as DataReloadOperation;
      }
      const listeners: DataChangeListener[] = this.listeners;
      for (const listener of listeners) { listener.onDatasetChange([operation]); }
    } finally { drawnStageMetrics.end(traced); }
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners = this.listeners.concat([listener]); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((registered: DataChangeListener): boolean => registered !== listener);
  }
}
