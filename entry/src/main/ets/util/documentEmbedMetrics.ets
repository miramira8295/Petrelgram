import { DrawnDocumentWidget } from './drawnDocumentWidget';
interface EmbedSize { width: number; height: number; }
// Weak ownership, one width/height per immutable source widget. No global LRU
// walk, no history of viewport sizes, and no references keeping messages alive.
const sizes: WeakMap<DrawnDocumentWidget, EmbedSize> = new WeakMap<DrawnDocumentWidget, EmbedSize>();
export function documentEmbedHeight(widget: DrawnDocumentWidget, width: number): number {
  const cached = sizes.get(widget);
  if (cached !== undefined && cached.width === width) { return cached.height; }
  const height = widget.width > 0 ? width * widget.height / widget.width : widget.height;
  return Math.max(10, Math.min(640, height));
}
export function setDocumentEmbedHeight(widget: DrawnDocumentWidget, width: number, height: number): boolean {
  if (!Number.isFinite(width) || width <= 0 || !Number.isFinite(height) || height <= 0) { return false; }
  const next = Math.max(10, Math.min(640, Math.round(height)));
  if (documentEmbedHeight(widget, width) === next) { return false; }
  sizes.set(widget, { width, height: next }); return true;
}
export function parseDocumentEmbedHeight(name: string, raw: string): number {
  if (name !== 'resize_frame' || raw.length > 1024) { return 0; }
  try {
    const data = JSON.parse(raw) as Record<string, Object>;
    const value = data['height'];
    if (typeof value !== 'string' && typeof value !== 'number') { return 0; }
    const height = Number(value);
    return Number.isFinite(height) && height > 0 ? Math.max(10, Math.min(640, Math.round(height))) : 0;
  } catch (_) { return 0; }
}
// Only a bounded size event is exposed; no MiniApp methods/auth/TDLib access.
export class DocumentEmbedResizeBridge {
  private receive: (height: number) => void;
  constructor(receive: (height: number) => void) { this.receive = receive; }
  postEvent(name: string, raw: string): void {
    const height = parseDocumentEmbedHeight(name, raw);
    if (height > 0) { this.receive(height); }
  }
  dispose(): void { this.receive = (_height: number): void => {}; }
}
