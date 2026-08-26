import { HdsNavDestination } from '@kit.UIDesignKit';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';

// ┌──────────────────────────────────────────────────────────────────────────┐
// │ 临时调试页 —— **验完删除**（P4 / 风险清单 R1）                              │
// └──────────────────────────────────────────────────────────────────────────┘
//
// 删除清单（一次删干净，不留悬挂引用）：
//   1. 本文件
//   2. entry/src/main/resources/base/profile/router_map.json 里的 RepeatSpikePage 条目
//   3. pages/main/DiagnosticsPage.ets 底部那一行入口（连同它的两个 i18n 键
//      diag_repeat_spike / diag_repeat_spike_sub，20 个 locale 各一条）
//
// ── 这个页面要回答什么 ──────────────────────────────────────────────────────
//
// 聊天详情页的首屏分级渲染建立在 LazyForEach 的一条语义上：占位符与真身**共用
// 同一个 key**，数据源发一条**不带 key 的 CHANGE** 就地把占位换成真身，从而保住
// 行身份、避免在滚动锚点附近删+插（见 AlbumGroupDataSource.sameRenderSnapshot
// 的注释）。
//
// Repeat 没有「不带 key 的 CHANGE」这个概念，只有 key 相同=更新 / key 不同=删插。
// 官方《Repeat：可复用的循环渲染》「节点更新/复用能力说明」写的是：
//   「Repeat 数据更新触发重新渲染的逻辑是比较当前索引处节点数据 item 是否变化，
//     以此判断是否进行 UI 刷新，仅改变键值不改变 item 的情况不会触发刷新。」
// 按字面读，key 不变 + item 换了新对象 ⇒ 就地刷新，正是我们要的。但这是**读文档
// 推的**，设备一直不可用，没有任何运行时证据。这个页面就是那份证据。
//
// 三件事，每件在界面上都有肉眼可判的指示，不需要连线拉日志：
//
//   1. 同 key 内容变 —— 一行的 key 不变、内容从「占位」变成「真身」，节点是被
//      就地更新还是删+插。判据：每个 cell 在 aboutToAppear 里领一个全局自增的
//      实例序号并显示出来（build#N）。序号没变 = 就地更新；序号变了 = 重建。
//      第三种结局也要能看出来：序号没变、内容也没跟着变 = 压根没刷新。
//   2. 前插 —— 在可视区上方插入若干行，配合 maintainVisibleContentPosition(true)，
//      可见内容位置保不保得住。判据：点按钮前记下"当前第一可见行的 id"，前插后
//      再按 onScrollIndex 报的下标去数组里取一次 id，两者相同 = 位置守住了。
//   3. 两者混合 —— 同一次数据更新里既有前插又有同 key 内容变。这正是
//      ChatPage.finishInitialMessageStage 的形状，也是最容易出事的形状。
//
// 数据全是本页现造的，不碰任何真实会话。

// 一行的数据。key **故意不含 real** —— 与 ChatPage 的 rowKeyOf 一样，占位与真身
// 共用同一个 key，这正是被测的那条语义。
interface SpikeRow {
  id: number;
  real: boolean;
}

const SEED_ROW_COUNT: number = 200;
const SEED_FIRST_ID: number = 1000;
const ROW_HEIGHT: number = 64;
const PREPEND_COUNT: number = 5;
// 点完按钮到取判据之间留几帧。列表要走完一次布局，onScrollIndex 也要回来。
const VERDICT_DELAY_MS: number = 400;

// 每个 cell 的实例序号与最后一次看到的内容，由 cell 自己上报。
//
// 放在模块级而不是页面状态里：写它的是 cell 的 aboutToAppear / @Monitor，那两个
// 时机在页面的 build 之中，回写页面状态会变成"在 build 里改状态"。页面只在
// 按钮的延时回调里读它。
class SpikeProbe {
  private nextSeq: number = 0;
  private readonly seqOf: Map<number, number> = new Map<number, number>();
  private readonly realOf: Map<number, boolean> = new Map<number, boolean>();

  allocSeq(id: number): number {
    this.nextSeq++;
    this.seqOf.set(id, this.nextSeq);
    return this.nextSeq;
  }

  noteReal(id: number, real: boolean): void {
    this.realOf.set(id, real);
  }

  seqFor(id: number): number {
    return this.seqOf.get(id) ?? 0;
  }

  realFor(id: number): boolean | undefined {
    return this.realOf.get(id);
  }

  reset(): void {
    this.nextSeq = 0;
    this.seqOf.clear();
    this.realOf.clear();
  }
}

const spikeProbe: SpikeProbe = new SpikeProbe();

// 判据的三种结局，配色也按这个来：绿=想要的，红=不想要的，灰=还没测。
const VERDICT_IDLE: string = 'idle';
const VERDICT_PASS: string = 'pass';
const VERDICT_FAIL: string = 'fail';

interface SpikeVerdict {
  state: string;
  headline: string;
  detail: string;
}

function idleVerdict(): SpikeVerdict {
  return { state: VERDICT_IDLE, headline: 'not run yet', detail: '' };
}

// 路由表（router_map.json）的 buildFunction 指向这里。
@Builder
export function RepeatSpikePageBuilder(): void {
  RepeatSpikePage();
}

// 一行。**必须是 @ComponentV2**：Repeat 懒加载不支持与状态管理 V1 配合使用。
//
// 入参用 @Param row 而不是整个 RepeatItem：ChatPage 迁移后给 ReusableMessageBubble
// 传的也是 `group: ri.item`，被测的正是这条通道。若上机发现内容不刷新（判据落到
// STALE），第一个要试的就是改成整体传 RepeatItem。
@ComponentV2
struct SpikeCell {
  @Require @Param row: SpikeRow;
  // 只在 aboutToAppear 里赋值一次。序号变了 = 这一行是新建的节点。
  @Local seq: number = 0;

  aboutToAppear(): void {
    this.seq = spikeProbe.allocSeq(this.row.id);
    spikeProbe.noteReal(this.row.id, this.row.real);
  }

  @Monitor('row')
  onRowChanged(): void {
    spikeProbe.noteReal(this.row.id, this.row.real);
  }

  build() {
    Row({ space: 10 }) {
      Text(`id ${this.row.id}`)
        .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).width(96);
      Text(this.row.real ? 'REAL' : 'PLACEHOLDER')
        .fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(this.row.real ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
        .layoutWeight(1);
      // 这就是「就地更新还是重建」的肉眼判据。
      Text(`build#${this.seq}`)
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%').height(ROW_HEIGHT)
    .padding({ left: 14, right: 14 })
    .backgroundColor(this.row.real ? COLOR_SURFACE : $r('app.color.surface_alt'));
  }
}

@ComponentV2
export struct RepeatSpikePage {
  private navStack: NavPathStack | null = null;
  private scroller: Scroller = new Scroller();
  // 唯一真相，整体赋值（与迁移后的 ChatPage.groups 同形）。
  @Local rows: SpikeRow[] = [];
  // onScrollIndex 报回来的可见区间。
  @Local visibleStart: number = 0;
  @Local visibleEnd: number = 0;
  @Local flipVerdict: SpikeVerdict = idleVerdict();
  @Local prependVerdict: SpikeVerdict = idleVerdict();
  @Local mixedVerdict: SpikeVerdict = idleVerdict();
  private nextId: number = SEED_FIRST_ID + SEED_ROW_COUNT;
  private pendingTimer: number = -1;

  aboutToAppear(): void {
    this.seed();
  }

  aboutToDisappear(): void {
    if (this.pendingTimer !== -1) {
      clearTimeout(this.pendingTimer);
      this.pendingTimer = -1;
    }
  }

  private seed(): void {
    spikeProbe.reset();
    const next: SpikeRow[] = [];
    for (let i = 0; i < SEED_ROW_COUNT; i++) {
      next.push({ id: SEED_FIRST_ID + i, real: true });
    }
    this.rows = next;
    this.nextId = SEED_FIRST_ID + SEED_ROW_COUNT;
    this.flipVerdict = idleVerdict();
    this.prependVerdict = idleVerdict();
    this.mixedVerdict = idleVerdict();
  }

  private visibleIds(): number[] {
    const ids: number[] = [];
    const last: number = Math.min(this.visibleEnd, this.rows.length - 1);
    for (let i = Math.max(0, this.visibleStart); i <= last; i++) {
      ids.push(this.rows[i].id);
    }
    return ids;
  }

  private firstVisibleId(): number {
    const index: number = Math.max(0, Math.min(this.visibleStart, this.rows.length - 1));
    return this.rows.length === 0 ? 0 : this.rows[index].id;
  }

  // 同 key 内容变：不改数组长度、不改任何 key，只把可见行的 real 翻个面，
  // 并且**造新对象**（项目的不可变约定，也是 Repeat 判"item 变没变"的输入）。
  private flippedRows(ids: number[]): SpikeRow[] {
    const flip: Set<number> = new Set<number>(ids);
    const next: SpikeRow[] = [];
    for (const row of this.rows) {
      next.push(flip.has(row.id) ? { id: row.id, real: !row.real } : row);
    }
    return next;
  }

  private prependedRows(base: SpikeRow[]): SpikeRow[] {
    const head: SpikeRow[] = [];
    for (let i = 0; i < PREPEND_COUNT; i++) {
      head.push({ id: this.nextId + i, real: true });
    }
    this.nextId += PREPEND_COUNT;
    return head.concat(base);
  }

  private schedule(action: () => void): void {
    if (this.pendingTimer !== -1) {
      clearTimeout(this.pendingTimer);
    }
    this.pendingTimer = setTimeout((): void => {
      this.pendingTimer = -1;
      action();
    }, VERDICT_DELAY_MS);
  }

  // 判据 1：序号没变 + 内容跟着变 = 就地更新（想要的）。
  private judgeFlip(ids: number[], seqBefore: number[], expectReal: boolean[]): SpikeVerdict {
    let rebuilt: number = 0;
    let stale: number = 0;
    for (let i = 0; i < ids.length; i++) {
      if (spikeProbe.seqFor(ids[i]) !== seqBefore[i]) {
        rebuilt++;
      }
      if (spikeProbe.realFor(ids[i]) !== expectReal[i]) {
        stale++;
      }
    }
    if (ids.length === 0) {
      return { state: VERDICT_FAIL, headline: 'no visible rows', detail: 'scroll first' };
    }
    if (rebuilt > 0) {
      return {
        state: VERDICT_FAIL,
        headline: 'REBUILT (delete + insert)',
        detail: `${rebuilt}/${ids.length} rows got a new build# — same key did NOT keep the node`
      };
    }
    if (stale > 0) {
      return {
        state: VERDICT_FAIL,
        headline: 'STALE (no refresh at all)',
        detail: `${stale}/${ids.length} rows kept the old content — @Param never saw the new item`
      };
    }
    return {
      state: VERDICT_PASS,
      headline: 'IN-PLACE UPDATE',
      detail: `${ids.length} rows kept their build# and took the new content`
    };
  }

  // 判据 2：前插之后，按新的 onScrollIndex 起始下标取回来的 id 还是原来那一条，
  // 就说明显示区域的内容没有被推走。
  private judgePrepend(beforeId: number, beforeStart: number): SpikeVerdict {
    const afterId: number = this.firstVisibleId();
    if (afterId === beforeId) {
      return {
        state: VERDICT_PASS,
        headline: 'ANCHOR HELD',
        detail: `first visible id ${beforeId} stayed put; index ${beforeStart} -> ${this.visibleStart}`
      };
    }
    return {
      state: VERDICT_FAIL,
      headline: 'JUMPED',
      detail: `first visible id ${beforeId} -> ${afterId}; index ${beforeStart} -> ${this.visibleStart}`
    };
  }

  private runFlip(): void {
    const ids: number[] = this.visibleIds();
    const seqBefore: number[] = [];
    const expectReal: boolean[] = [];
    for (const id of ids) {
      seqBefore.push(spikeProbe.seqFor(id));
      expectReal.push(spikeProbe.realFor(id) !== true);
    }
    this.rows = this.flippedRows(ids);
    this.schedule((): void => {
      this.flipVerdict = this.judgeFlip(ids, seqBefore, expectReal);
    });
  }

  private runPrepend(): void {
    const beforeId: number = this.firstVisibleId();
    const beforeStart: number = this.visibleStart;
    this.rows = this.prependedRows(this.rows);
    this.schedule((): void => {
      this.prependVerdict = this.judgePrepend(beforeId, beforeStart);
    });
  }

  // 判据 3：一次赋值里同时做两件事。两个结论都要过才算过。
  private runMixed(): void {
    const ids: number[] = this.visibleIds();
    const seqBefore: number[] = [];
    const expectReal: boolean[] = [];
    for (const id of ids) {
      seqBefore.push(spikeProbe.seqFor(id));
      expectReal.push(spikeProbe.realFor(id) !== true);
    }
    const beforeId: number = this.firstVisibleId();
    const beforeStart: number = this.visibleStart;
    this.rows = this.prependedRows(this.flippedRows(ids));
    this.schedule((): void => {
      const flip: SpikeVerdict = this.judgeFlip(ids, seqBefore, expectReal);
      const anchor: SpikeVerdict = this.judgePrepend(beforeId, beforeStart);
      const pass: boolean = flip.state === VERDICT_PASS && anchor.state === VERDICT_PASS;
      this.mixedVerdict = {
        state: pass ? VERDICT_PASS : VERDICT_FAIL,
        headline: `${flip.headline} / ${anchor.headline}`,
        detail: `${flip.detail} — ${anchor.detail}`
      };
    });
  }

  private verdictColor(state: string): ResourceColor {
    if (state === VERDICT_PASS) {
      return '#34C759';
    }
    return state === VERDICT_FAIL ? '#FF3B30' : COLOR_TEXT_SECONDARY;
  }

  @Builder
  verdictCard(label: string, verdict: SpikeVerdict) {
    Column({ space: 3 }) {
      Row({ space: 8 }) {
        Text(label).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width(64);
        Text(verdict.headline)
          .fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.verdictColor(verdict.state))
          .layoutWeight(1);
      }.width('100%');
      if (verdict.detail !== '') {
        Text(verdict.detail)
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  actionButton(label: string, action: () => void) {
    Text(label)
      .fontSize(13).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor(COLOR_SURFACE).borderRadius(9)
      .onClick(action);
  }

  build() {
    HdsNavDestination() {
      Column() {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(22).fontColor([COLOR_PRIMARY])
            .onClick((): void => { this.navStack?.pop(); });
          Text($r('app.string.diag_repeat_spike'))
            .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
            .layoutWeight(1);
        }
        .width('100%').height(52).padding({ left: 12, right: 14 })
        .alignItems(VerticalAlign.Center);

        Column({ space: 8 }) {
          Text(`rows ${this.rows.length} · visible ${this.visibleStart}..${this.visibleEnd}` +
            ` · first id ${this.firstVisibleId()}`)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
          this.verdictCard('1 flip', this.flipVerdict);
          this.verdictCard('2 prepend', this.prependVerdict);
          this.verdictCard('3 mixed', this.mixedVerdict);
          Row({ space: 8 }) {
            this.actionButton('1 flip visible', (): void => { this.runFlip(); });
            this.actionButton(`2 prepend ${PREPEND_COUNT}`, (): void => { this.runPrepend(); });
            this.actionButton('3 mixed', (): void => { this.runMixed(); });
            this.actionButton('reset', (): void => { this.seed(); });
          }.width('100%');
        }
        .width('100%').padding({ left: 14, right: 14, top: 4, bottom: 10 })
        .alignItems(HorizontalAlign.Start);

        Divider().strokeWidth(0.5).color(COLOR_DIVIDER);

        // 与 ChatPage 迁移后同形：List 里只有一个 Repeat，懒加载 + 关掉 Repeat
        // 自身复用（保住 @ReusableV2 的语义）+ 前插保持。
        List({ scroller: this.scroller }) {
          Repeat<SpikeRow>(this.rows)
            .each((ri: RepeatItem<SpikeRow>) => {
              ListItem() {
                SpikeCell({ row: ri.item });
              }
            })
            .key((row: SpikeRow): string => `spike_${row.id}`)
            .virtualScroll({ totalCount: this.rows.length, reusable: false });
        }
        .width('100%').layoutWeight(1)
        .cachedCount(3)
        .maintainVisibleContentPosition(true)
        .stackFromEnd(true)
        .divider({ strokeWidth: 0.5, color: COLOR_DIVIDER })
        .onScrollIndex((start: number, end: number): void => {
          this.visibleStart = start;
          this.visibleEnd = end;
        });
      }
      .width('100%').height('100%')
      .backgroundColor(COLOR_PAGE_BG);
    }
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
    })
    .width('100%').height('100%');
  }
}
