import { RowLeaveChannel } from './rowLeaveChannel';

// 动画完成后再进入既有撤销窗口；离页或下一批操作会立即接续已确认的删除。
export class DownloadDeleteEffects {
  private channels: Map<number, RowLeaveChannel> = new Map();
  private keys: Map<string, number> = new Map();
  private nextKey: number = 1;
  private generation: number = 0;
  private pending: (() => void) | null = null;
  private pendingIds: Set<string> = new Set();

  rowKey(itemId: string): number {
    let key = this.keys.get(itemId);
    if (key === undefined) { key = this.nextKey++; this.keys.set(itemId, key); }
    return key;
  }

  channel(tab: number): RowLeaveChannel {
    let channel = this.channels.get(tab);
    if (channel === undefined) { channel = new RowLeaveChannel(); this.channels.set(tab, channel); }
    return channel;
  }

  isPending(itemId: string): boolean { return this.pendingIds.has(itemId); }

  start(tab: number, ids: string[], enabled: boolean, finish: () => void): void {
    this.flush();
    if (!enabled) { finish(); return; }
    const generation = ++this.generation;
    this.pending = finish;
    this.pendingIds = new Set(ids);
    this.channel(tab).play(ids.map((id: string): number => this.rowKey(id)), true).then((): void => {
      if (this.generation === generation) { this.flush(); }
    }).catch((): void => {
      if (this.generation === generation) { this.flush(); }
    });
  }

  flush(): void {
    const finish = this.pending;
    this.pending = null;
    this.pendingIds.clear();
    this.generation++;
    this.channels.forEach((channel: RowLeaveChannel): void => { channel.clear(); });
    finish?.();
  }
}
