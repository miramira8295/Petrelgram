// 与平台解码解耦：同键只准备一次，串行准备，引用保护，空闲LRU与解码预留预算。
export interface AvatarFrameAsset<T> { frames: T[]; durationsMs: number[]; size: number; bytes: number; }
export interface AvatarFrameLease<T> { ready: Promise<AvatarFrameAsset<T> | null>; release: () => void; }
interface Entry<T> {
  key: string;
  refs: number;
  used: number;
  pending: boolean;
  asset: AvatarFrameAsset<T> | null;
  ready: Promise<AvatarFrameAsset<T> | null>;
}
export class AvatarFramePool<T> {
  private entries: Map<string, Entry<T>> = new Map();
  private tail: Promise<void> = Promise.resolve();
  private clock: number = 0;
  private bytes: number = 0;
  private limit: number;
  private reserve: number;
  private dispose: (asset: AvatarFrameAsset<T>) => void;
  constructor(limit: number, reserve: number, dispose: (asset: AvatarFrameAsset<T>) => void) {
    this.limit = limit; this.reserve = reserve; this.dispose = dispose;
  }

  acquire(key: string, load: (cancelled: () => boolean) => Promise<AvatarFrameAsset<T> | null>): AvatarFrameLease<T> {
    let entry = this.entries.get(key);
    if (entry === undefined) {
      this.trim(0, 31);
      // 拒绝无限增长的正在用/排队条目，不为每个头像都建解码任务。
      if (this.entries.size >= 32) { return { ready: Promise.resolve(null), release: (): void => {} }; }
      const created: Entry<T> = { key: key, refs: 0, used: ++this.clock, pending: true,
        asset: null, ready: Promise.resolve(null) };
      this.entries.set(key, created);
      created.ready = this.tail.then(async (): Promise<AvatarFrameAsset<T> | null> => {
        this.trim(this.reserve, 32);
        if (created.refs === 0 || this.bytes + this.reserve > this.limit) { return null; }
        let asset: AvatarFrameAsset<T> | null = null;
        try { asset = await load((): boolean => created.refs === 0); } catch (_) { return null; }
        if (asset === null) { return null; }
        if (created.refs === 0 || asset.bytes <= 0 || asset.bytes > this.reserve) {
          this.dispose(asset);
          return null;
        }
        created.asset = asset;
        this.bytes += asset.bytes;
        return asset;
      }).then((asset: AvatarFrameAsset<T> | null): AvatarFrameAsset<T> | null => {
        created.pending = false;
        if (created.refs === 0) { this.remove(created); }
        return asset;
      });
      this.tail = created.ready.then((): void => {}, (): void => {});
      entry = created;
    }
    const held = entry;
    held.refs++;
    held.used = ++this.clock;
    let released = false;
    return { ready: held.ready, release: (): void => {
      if (released) { return; }
      released = true;
      held.refs--;
      held.used = ++this.clock;
      if (held.refs === 0 && !held.pending && held.asset === null) { this.remove(held); }
    } };
  }

  private remove(entry: Entry<T>): void {
    if (this.entries.get(entry.key) !== entry || entry.refs > 0 || entry.pending) { return; }
    this.entries.delete(entry.key);
    if (entry.asset !== null) {
      this.bytes -= entry.asset.bytes;
      this.dispose(entry.asset);
      entry.asset = null;
    }
  }
  private trim(extra: number, count: number): void {
    const idle: Entry<T>[] = [];
    this.entries.forEach((e: Entry<T>): void => { if (e.refs === 0 && !e.pending) { idle.push(e); } });
    idle.sort((a: Entry<T>, b: Entry<T>): number => a.used - b.used);
    for (const e of idle) {
      if (this.bytes + extra <= this.limit && this.entries.size <= count) { break; }
      this.remove(e);
    }
  }
  clearIdle(): void { this.trim(this.limit, 0); }
  retainedBytes(): number { return this.bytes; }
}
