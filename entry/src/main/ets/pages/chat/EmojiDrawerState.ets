import { EMOJI_DRAWER_HEIGHT, drawerBottomInset } from '../../util/drawerMetrics';
import { COMPOSER_GAP_MIN, COMPOSER_GAP_TIGHT } from '../../util/composerChrome';

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
  // 目标「总高」= max(固定面板高 + 安全区, 量到的键盘高)。
  //
  // 键盘更高时面板与键盘等高（切换时上沿对齐）；键盘不高于固定面板时**用固定值**，
  // 这样「直接点表情键」和「键盘→表情键」两条路径算出的是同一个数——真机上键盘是
  // 333.9vp，若直接沿用键盘高，面板会比固定档矮 6vp，两条路径就差出一次可见的位移，
  // 用户看到的就是「切一下表情框就沉下去一块」（2026-11-24 反馈）。
  const keyboardTotal: number = Number.isFinite(imeHeight) && imeHeight > 0 ? imeHeight : 0;
  const wantTotal: number = Math.max(EMOJI_DRAWER_HEIGHT + inset, keyboardTotal);
  return Math.max(0, Math.min(wantTotal - inset, byBase, byComposer));
}

// 抽屉外壳向上叠入输入栏的那一截。
//
// **恒为 0**（2026-11-23 用户反馈后改）。原来这里是 (max(8,bottomSafe) - 6)，
// 目的是让抽屉的外叠量去抵消「输入栏 bottomGap 从安全区切成 6」的那一跳。但它的
// 代价是：面板一打开，外壳就带着整个视口往上顶 topOverlap（平板上 bottomSafe 约
// 26，实测顶起 20vp），输入栏跟着上移——于是键盘↔面板来回切时，输入栏的上下位置
// 在两个不同的基准之间跳。用户的原话是「表情框与输入栏的间距和键盘与输入栏的
// 间距不一样」。
//
// 现在改成：不叠，面板卡片顶沿直接落在「屏底 - 抽屉总高」上，而抽屉总高等于键盘
// 高度，也就是卡片顶沿与键盘顶沿同一条线；输入栏到卡片的缝由 composerBottomGap
// 统一给（面板打开期间也用 COMPOSER_GAP_TIGHT，和键盘一致）。两边都对齐，切换不动。
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
  // 系统键盘占用的高度（含下方安全区）。抽屉总高对齐它：键盘↔表情切换时上沿不动。
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
    // **只能用整屏视口**。键盘起来时 onSizeChange 报的是被键盘压小的尺寸，拿它再减
    // header/composer 等于把键盘高度又扣一遍：真机实测键盘态 vp=509.9（整屏 843.9），
    // 面板被算成 262.4 而不是 312，于是「打开」时的动画目标（290.4）和随后按整屏重算的
    // 卡片高度（306.0）对不上，卡片比外壳高、被外壳 clip 掉一截——用户看到的就是
    // 「键盘切表情后表情框下沉、内容变少」（2026-11-24 真机日志证据）。
    // Until the first layout there is no viewport to clamp against; still follow the
    // measured keyboard so the very first open already matches the IME height.
    const vp: number = this.fullViewportH > 0 ? this.fullViewportH : this.viewport;
    if (vp > 0) {
      return emojiDrawerHeight(vp, header, this.composer, bottomSafe, this.expanded, this.imeHeight);
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
