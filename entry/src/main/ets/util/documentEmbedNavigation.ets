// Navigation decisions happen on browser events, never during paint. URL input
// is bounded, and redirect state is fixed-size; no history/set grows per embed.
export function documentEmbedUrl(url: string): boolean {
  return url.length <= 8192 && /^https?:\/\/[^\s/?#@]+(?:[/?#][^\s]*)?$/i.test(url);
}
export type DocumentEmbedDecision = 'allow' | 'open' | 'block';
export class DocumentEmbedNavigation {
  private initial: string = '';
  private loading: boolean = true;
  private redirects: number = 0;
  reset(url: string): void { this.initial = url; this.loading = true; this.redirects = 0; }
  loaded(): void { this.loading = false; }
  decide(url: string, main: boolean, gesture: boolean, redirect: boolean): DocumentEmbedDecision {
    if (!main) { return 'allow'; }
    if (gesture) { return documentEmbedUrl(url) ? 'open' : 'block'; }
    if (url === 'about:blank') { return 'allow'; }
    if (!documentEmbedUrl(url)) { return 'block'; }
    if (this.loading && url === this.initial) { return 'allow'; }
    if (this.loading && redirect && this.redirects < 8) { this.redirects++; return 'allow'; }
    return 'block';
  }
}

export function documentEmbedBridgePermission(url: string): string {
  const match = /^(https?):\/\/(\[[^\]]+\]|[^/:?#@]+)(?::([0-9]+))?(?:[/?#]|$)/i.exec(url);
  const rule: Record<string, string> = { 'scheme': match?.[1]?.toLowerCase() ?? 'https',
    'host': match?.[2] ?? 'invalid.invalid', 'port': match?.[3] ?? '', 'path': '' };
  const permission: Record<string, Object> = { 'urlPermissionList': [rule] };
  const root: Record<string, Object> = { 'javascriptProxyPermission': permission };
  return JSON.stringify(root);
}

// Android WebPlayerView recognizes direct MP4 before provider-specific parsing.
// Also retain signed query strings; matching the path costs O(U), bounded by
// documentEmbedUrl. HTML content still takes precedence over a video URL.
export function documentEmbedDirectVideo(url: string, html: string): boolean {
  return html === '' && documentEmbedUrl(url) && /^https?:\/\/[^/?#]+\/[^?#]*\.mp4(?:[?#]|$)/i.test(url);
}
