import { getTdClient } from '../../tdkit/Globals';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleRenderData } from './ReusableMessageBubble';
import { DrawnRowLayoutEngine } from './DrawnLayoutWarmCache';

interface DrawnRecycledLayoutEntry {
  engine: DrawnRowLayoutEngine;
  kind: string;
  until: number;
}

// Exclusive leases, never shared mutable plans. A recycled owner relinquishes
// its engine; the next owner still calls prepare with ALL current inputs.
// O(1) lookup/removal/oldest eviction, at most eight engines, ten-second TTL.
export class DrawnRecycledLayouts {
  private owner: Object | undefined;
  private entries: Map<string, DrawnRecycledLayoutEntry> = new Map();
  private albums: Map<string, DrawnRecycledLayoutEntry> = new Map();
  private texts: Map<string, DrawnRecycledLayoutEntry> = new Map();
  private singles: Map<string, DrawnRecycledLayoutEntry> = new Map();
  private expiry: number = -1;
  private clock: () => number;
  private hits: number = 0;
  private misses: number = 0;
  private reused: number = 0;
  constructor(clock: () => number = (): number => Date.now()) { this.clock = clock; }
  private context(owner: Object): void {
    if (owner !== this.owner) { this.clear(); this.owner = owner; }
  }
  private lane(kind: string): Map<string, DrawnRecycledLayoutEntry> {
    return kind === 'album' ? this.albums : kind === 'text' ? this.texts : this.singles;
  }
  private remove(key: string): DrawnRecycledLayoutEntry | undefined {
    const entry = this.entries.get(key);
    if (entry !== undefined) { this.entries.delete(key); this.lane(entry.kind).delete(key); }
    return entry;
  }
  put(owner: Object, key: string, kind: string, engine: DrawnRowLayoutEngine): void {
    this.context(owner);
    this.remove(key);
    if (this.entries.size >= 8) {
      const oldest = this.entries.keys().next();
      if (!oldest.done) { this.remove(oldest.value); }
    }
    const entry: DrawnRecycledLayoutEntry = { engine, kind, until: this.clock() + 10000 };
    this.entries.set(key, entry); this.lane(kind).set(key, entry);
    // One cleanup timer for the whole window, not one allocation per reuse.
    // A recent entry may be evicted early; no entry survives beyond its TTL.
    if (this.expiry === -1) { this.expiry = setTimeout((): void => { this.clear(); }, 10000); }
  }
  take(owner: Object, key: string, kind: string): DrawnRowLayoutEngine | undefined {
    this.context(owner);
    const entry = this.remove(key);
    if (entry !== undefined && this.clock() < entry.until) { this.hits++; return entry.engine; }
    this.misses++;
    // A miss must not turn each physical-row reuse into an engine allocation.
    // Rebind an available old engine; prepare validates all inputs as before.
    const oldest = this.lane(kind).keys().next();
    if (!oldest.done) {
      const fallback = this.remove(oldest.value);
      if (fallback !== undefined && this.clock() < fallback.until) { this.reused++; return fallback.engine; }
    }
    return undefined;
  }
  clear(): void {
    this.entries.clear(); this.albums.clear(); this.texts.clear(); this.singles.clear(); this.owner = undefined;
    if (this.expiry !== -1) { clearTimeout(this.expiry); this.expiry = -1; }
  }
  summary(): string { return `\nrecycled layouts: held=${this.entries.size} hits=${this.hits} misses=${this.misses} rebind=${this.reused}`; }
}
export const drawnRecycledLayouts: DrawnRecycledLayouts = new DrawnRecycledLayouts();

export function takeDrawnRecycledLayout(chatId: number, rowId: number, kind: string): DrawnRowLayoutEngine | undefined {
  // UIContext wrappers differ between physical rows. The adopted engine must
  // validate density/fonts/resources in prepare; never return a raw old plan.
  return drawnRecycledLayouts.take(getTdClient(), `${chatId}:${rowId}:${kind}`, kind);
}

// Plain fields survive V2 resets. Capture account/context when preparing, not
// during recycle (which may happen after an account switch). Oversize input
// permanently disqualifies this lease because inner caches retain old inputs.
export class DrawnLayoutRetention {
  private owner: Object | undefined;
  private kind: string = '';
  private key: string = '';
  private engine: DrawnRowLayoutEngine | null = null;
  private allowed: boolean = true;
  remember(group: AlbumGroup, data: MessageBubbleRenderData, kind: string, engine: DrawnRowLayoutEngine): void {
    if (this.engine !== engine) { this.allowed = true; }
    this.owner = getTdClient(); this.kind = kind; this.key = `${data.chatId}:${group.head.rowId}:${kind}`; this.engine = engine;
    const m = group.head;
    if ((kind === 'album' ? group.caption : m.text).length > 8192 || m.replyText.length > 2048 ||
      m.senderName.length > 512 || m.forwardFrom.length > 2048 || group.memberIds.length > 10) { this.allowed = false; }
  }
  release(): void {
    if (this.allowed && this.owner !== undefined && this.owner === getTdClient() && this.engine !== null) {
      drawnRecycledLayouts.put(this.owner, this.key, this.kind, this.engine);
    }
    this.owner = undefined; this.kind = ''; this.key = ''; this.engine = null; this.allowed = true;
  }
}
