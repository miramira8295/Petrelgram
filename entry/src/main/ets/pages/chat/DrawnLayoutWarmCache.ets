import { DrawnRouteReason } from '../../util/drawnRouteMetrics';
import { UIContext } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleRenderData } from './ReusableMessageBubble';
import { DrawnBubblePlan, DrawnBubbleStyle } from './DrawnBubblePlan';

export interface DrawnRowLayoutEngine {
  // Non-observed result of the latest prepare, including negative cache hits.
  readonly failureReason: DrawnRouteReason;
  prepare(ui: UIContext, group: AlbumGroup, data: MessageBubbleRenderData, style: DrawnBubbleStyle): DrawnBubblePlan | null;
}

// Transfer an exclusively owned cache, NOT a trusted finished plan. The row
// MUST call prepare with its current message/width/environment. Existing engines
// validate their complete inputs and reuse only matching inner paragraphs.
export class DrawnLayoutWarmCache {
  private owner: Object | undefined;
  private entries: Map<string, DrawnRowLayoutEngine> = new Map();
  private expiry: number = -1;
  private expiresAt: number = 0;
  private prepared: number = 0;
  private claimed: number = 0;
  private expired: number = 0;
  hasEntries(): boolean { return this.entries.size > 0; }

  put(owner: Object, chatId: number, id: number, kind: string, engine: DrawnRowLayoutEngine): void {
    if (owner !== this.owner) { this.clear(); this.owner = owner; }
    if (this.entries.size >= 2) { return; }
    this.entries.set(`${chatId}:${id}:${kind}`, engine); this.prepared++;
    this.expiresAt = Date.now() + 10000;
    if (this.expiry !== -1) { clearTimeout(this.expiry); }
    this.expiry = setTimeout((): void => { this.expired += this.entries.size; this.clear(); }, 10000);
  }
  take(owner: Object, chatId: number, id: number, kind: string): DrawnRowLayoutEngine | undefined {
    if (owner !== this.owner || Date.now() >= this.expiresAt) { this.clear(); return undefined; }
    const key = `${chatId}:${id}:${kind}`;
    const engine = this.entries.get(key);
    if (engine !== undefined) { this.entries.delete(key); this.claimed++; }
    if (this.entries.size === 0) { this.clear(); }
    return engine;
  }
  clear(): void {
    this.entries.clear(); this.owner = undefined; this.expiresAt = 0;
    if (this.expiry !== -1) { clearTimeout(this.expiry); this.expiry = -1; }
  }
  summary(): string {
    return `\nhome layouts: prepared=${this.prepared} claimed=${this.claimed} unused=${this.entries.size} expired=${this.expired}`;
  }
}
export const drawnLayoutWarmCache: DrawnLayoutWarmCache = new DrawnLayoutWarmCache();
export function takeDrawnWarmLayout(chatId: number, id: number, kind: string): DrawnRowLayoutEngine | undefined {
  if (!drawnLayoutWarmCache.hasEntries()) { return undefined; }
  return drawnLayoutWarmCache.take(getTdClient(), chatId, id, kind);
}
