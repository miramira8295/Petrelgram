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
  // 底部抽屉（表情/附件）当前实际展示高度与卡片过渡态。
  // 放在 ObservedV2 控制器内，VSync 动画帧只驱动 ChatPageSurface 视口与 BottomDrawerShell。
  @Trace shellHeight: number = 0;
  @Trace cardOffsetY: number = 0;
  @Trace cardOpacity: number = 1;
  @Trace activeSlot: string = '';
  @Trace fullViewportH: number = 0;
  @Trace curResizeH: number = 0;
  @Trace closingImeToDrawer: boolean = false;
  @Trace closingExpanded: boolean = false;
  @Trace imeOverlapRatio: number = 0;
  @Trace imeBridgeSlot: string = '';
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
  totalHeight(header: number, bottomSafe: number): number {
    return this.height(header, bottomSafe) + drawerBottomInset(bottomSafe);
  }
  cardHeight(header: number, bottomSafe: number): number {
    if (this.closingExpanded && this.viewport > 0) {
      return emojiDrawerHeight(this.viewport, header, this.composer, bottomSafe, true);
    }
    return this.height(header, bottomSafe);
  }
  topViewportHeight(): Length {
    if (this.shellHeight <= 0 || this.fullViewportH <= 0) {
      return '100%';
    }
    const desired: number = Math.max(0, this.fullViewportH - this.shellHeight);
    if (this.curResizeH > 0 && this.curResizeH < desired && !this.closingImeToDrawer) {
      return this.curResizeH;
    }
    return desired;
  }
  setImeOverlapRatio(ratio: number): void {
    const clamped: number = Math.min(1, Math.max(0, Number.isFinite(ratio) ? ratio : 0));
    if (Math.abs(clamped - this.imeOverlapRatio) > 0.002) {
      this.imeOverlapRatio = clamped;
    } else if (clamped === 0 && this.imeOverlapRatio !== 0) {
      this.imeOverlapRatio = 0;
    } else if (clamped === 1 && this.imeOverlapRatio !== 1) {
      this.imeOverlapRatio = 1;
    }
  }
  collapse(): boolean {
    if (!this.expanded) { return false; }
    this.expanded = false; return true;
  }
}
