import { TdObject } from '../tdkit/TdTypes';
import { DeleteRowGroup, RowLeaveChannel, wholeDeleteRowIds } from './rowLeaveChannel';
import { logE } from './log';

// TDLib remains authoritative and removes data immediately. Only the page's
// presentation is held while mounted rows dissolve. Keep one latest publication,
// not a queue of history snapshots. A burst has one bounded deadline.
export class RemoteMessageDeleteEffects {
  private generation: number = 0;
  private batches: number = 0;
  private timer: number = -1;
  private rows: Set<number> = new Set<number>();
  private latest: (() => void) | null = null;
  private fallback: (() => void) | null = null;
  private channel: RowLeaveChannel;

  constructor(channel: RowLeaveChannel) { this.channel = channel; }

  active(): boolean { return this.batches > 0; }

  defer(publish: () => void): void { this.latest = publish; }

  begin(update: TdObject, chatId: number, visibleGroups: DeleteRowGroup[],
    enabled: boolean, refresh: () => void): void {
    if (!enabled || update['chat_id'] !== chatId ||
      (update['from_cache'] === true && update['is_permanent'] !== true)) { return; }
    const ids = (update['message_ids'] as number[] | undefined) ?? [];
    if (ids.length === 0) { return; }
    // O(deleted IDs + visible members). Local confirmation and repeated remote
    // notifications already marked the row: neither can start another capture.
    const rows = wholeDeleteRowIds(visibleGroups, ids).filter((id: number): boolean =>
      this.channel.value(id) === 0 && this.channel.mounted(id));
    if (rows.length === 0) { return; }
    for (const id of rows) { this.rows.add(id); }
    this.fallback = refresh;
    this.batches++;
    const generation: number = this.generation;
    if (this.timer === -1) {
      this.timer = setTimeout((): void => { this.finish(true); }, 2750);
    }
    this.channel.play(rows, true).then((): void => {
      if (generation !== this.generation) { return; }
      if (--this.batches === 0) { this.finish(true); }
    }).catch((error: Error): void => {
      logE(`RemoteMessageDeleteEffects: ${error.message}`);
      if (generation === this.generation) { this.finish(true); }
    });
  }

  // Hide/rebind/dispose drops the old page's publication. Completing owned rows
  // releases snapshot timers without cancelling an unrelated local deletion.
  cancel(): void { this.finish(false); }
  flush(): void { this.finish(true); }

  private finish(publish: boolean): void {
    if (this.rows.size === 0) { return; }
    this.generation++;
    this.batches = 0;
    if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; }
    const callback = this.latest ?? this.fallback;
    this.latest = null;
    this.fallback = null;
    const rows = this.rows;
    this.rows = new Set<number>();
    for (const id of rows) { this.channel.complete(id); }
    try {
      if (publish) { callback?.(); }
    } finally {
      for (const id of rows) { this.channel.restore(id); }
    }
  }
}
