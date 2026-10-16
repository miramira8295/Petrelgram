import { EMOJI_DRAWER_HEIGHT, drawerBottomInset } from '../../util/drawerMetrics';

export function emojiDrawerHeight(viewport: number, header: number, composer: number,
  bottomSafe: number, expanded: boolean): number {
  const available = Math.max(0, viewport - header - composer - drawerBottomInset(bottomSafe) - 8);
  return expanded ? available : Math.min(EMOJI_DRAWER_HEIGHT, available);
}

export function mediaPanelColumns(width: number, kind: string): number {
  const target = kind === 'emoji' ? 40 : (kind === 'gif' ? 150 : 66);
  return Math.max(1, Math.floor((Math.max(0, width) - 20 + 6) / (target + 6)));
}

export function mediaPanelTemplate(columns: number): string {
  return Array<string>(columns).fill('1fr').join(' ');
}

@ObservedV2
export class EmojiDrawerState {
  @Trace expanded: boolean = false;
  @Trace viewport: number = 0;
  @Trace composer: number = 76;
  measureViewport(height: number): void {
    if (Number.isFinite(height) && height > 0 && Math.abs(height - this.viewport) > 0.5) { this.viewport = height; }
  }
  measureComposer(height: number): void {
    if (Number.isFinite(height) && height > 0 && Math.abs(height - this.composer) > 0.5) { this.composer = height; }
  }
  height(header: number, bottomSafe: number): number {
    // Until the first layout, preserve the existing compact drawer.
    return this.viewport > 0 ? emojiDrawerHeight(this.viewport, header, this.composer, bottomSafe, this.expanded)
      : EMOJI_DRAWER_HEIGHT;
  }
  collapse(): boolean {
    if (!this.expanded) { return false; }
    this.expanded = false; return true;
  }
}
