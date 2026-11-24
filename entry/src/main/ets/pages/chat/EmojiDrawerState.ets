import { EMOJI_DRAWER_HEIGHT, drawerBottomInset } from '../../util/drawerMetrics';

// 抽屉给输入栏预留的高度上限。**不能直接扣实测的 composer**：草稿行数越多输入栏
// 越高，扣掉它面板就一路变矮——表现就是「输入框里面写得越多，打开表情面板看到的
// 内容越少」。面板一旦打开，多出来的行高应该由上方聊天视口承担，而不是把网格挤小。
// 76 是单行输入栏（含底部留白）的常见高度，也是 EmojiDrawerState.composer 的初值。
export const COMPOSER_BASE_HEIGHT: number = 76;

export function emojiDrawerHeight(viewport: number, header: number, composer: number,
  bottomSafe: number, expanded: boolean, imeHeight: number = 0): number {
  const inset: number = drawerBottomInset(bottomSafe);
  const measured: number = Number.isFinite(composer) && composer > 0 ? composer : COMPOSER_BASE_HEIGHT;
  // 展开态本来就是「把剩下的地方全给它」，行数变化理应反映进去。
  if (expanded) {
    return Math.max(0, viewport - header - measured - inset - 8);
  }
  const base: number = Math.min(measured, COMPOSER_BASE_HEIGHT);
  const byBase: number = viewport - header - base - inset - 8;
  // 硬约束：输入栏本身（哪怕已经涨到十几行）必须还能完整放进上方视口，否则输入框
  // 会被 Stack 裁掉。只有这一条能把紧凑态面板压回去，草稿行数本身不再影响它。
  const byComposer: number = viewport - measured - inset - 8;
  // 低键盘不缩小默认网格；较高键盘则跟随它。两种入口的紧凑态使用同一预算，
  // 仍由当前窗口/输入栏可用空间限制，不能为保默认高度而撑出小窗口。
  const keyboardTotal: number = Number.isFinite(imeHeight) && imeHeight > 0 ? imeHeight : 0;
  const wanted: number = Math.max(EMOJI_DRAWER_HEIGHT, keyboardTotal - inset);
  return Math.max(0, Math.min(wanted, byBase, byComposer));
}

// Keyboard and drawer share COMPOSER_GAP_TIGHT. No extra overlap is needed;
// shell displacement equals its height throughout opening and closing.
export function drawerTopOverlap(_bottomSafe: number, _closingToIme: boolean = false): number {
  return 0;
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
  @Trace closingToIme: boolean = false;
  @Trace closingExpanded: boolean = false;
  @Trace imeOverlapRatio: number = 0;
  @Trace imeBridgeSlot: string = '';
  // 系统键盘占用高度（含安全区）。较高键盘用于抬高紧凑面板，较矮键盘保留默认网格。
  @Trace imeHeight: number = 0;
  setImeHeight(height: number): void {
    const next: number = Number.isFinite(height) && height > 0 ? Math.round(height) : 0;
    if (next !== this.imeHeight) { this.imeHeight = next; }
  }
  measureViewport(height: number): void {
    if (Number.isFinite(height) && height > 0 && Math.abs(height - this.viewport) > 0.5) { this.viewport = height; }
  }
  measureComposer(height: number): void {
    if (Number.isFinite(height) && height > 0 && Math.abs(height - this.composer) > 0.5) { this.composer = height; }
  }
  height(header: number, bottomSafe: number): number {
    // publishComposerViewport feeds the current full page height, never the
    // keyboard-compressed area or a historical maximum from another window.
    // Before measurement, use the same compact minimum as the measured path.
    if (this.viewport > 0) {
      return emojiDrawerHeight(this.viewport, header, this.composer, bottomSafe, this.expanded, this.imeHeight);
    }
    return this.imeHeight > 0
      ? Math.max(EMOJI_DRAWER_HEIGHT, this.imeHeight - drawerBottomInset(bottomSafe))
      : EMOJI_DRAWER_HEIGHT;
  }
  totalHeight(header: number, bottomSafe: number): number {
    return this.height(header, bottomSafe) + drawerBottomInset(bottomSafe);
  }
  topOverlap(bottomSafe: number): number {
    return drawerTopOverlap(bottomSafe, this.closingToIme);
  }
  liftHeight(header: number, bottomSafe: number): number {
    return Math.max(0, this.totalHeight(header, bottomSafe) - drawerTopOverlap(bottomSafe, false));
  }
  cardHeight(header: number, bottomSafe: number): number {
    if (this.closingExpanded && this.viewport > 0) {
      return emojiDrawerHeight(this.viewport, header, this.composer, bottomSafe, true, this.imeHeight);
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
