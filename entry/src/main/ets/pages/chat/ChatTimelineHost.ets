import { MessageListStateCard } from './MessageListState';
import { InitialLoadingHint } from './InitialLoadingHint';
import { showInitialLoadingHint } from '../../util/initialLoadingHint';
import { FloatingDateOverlay, TimelineStatePillSlot } from './FloatingDateOverlay';
import { TL_NONE, timelineStateMode, timelineStateText } from '../../util/timelineState';
import { ROW_TEMPLATE_DEFERRED, ROW_TEMPLATE_PLAIN, ROW_TEMPLATE_PLAIN_GUTTER, ROW_TEMPLATE_RICH, ROW_TEMPLATE_RICH_GUTTER, rowTemplateId } from '../../util/rowTemplateId';
import { MessageRowHost } from './MessageRowHost';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { stackFromEndWanted } from '../../util/stackFromEnd';
import { MESSAGE_SELECTION_GUTTER_VP, rowSelectable } from '../../util/messageSelection';
import { AlbumGroup } from '../../util/collapseAlbums';
import { COLOR_PRIMARY } from '../../util/theme';
import { SelectionSession } from './SelectionSession';
import { RowPageInputs } from '../../util/rowPageInputs';
import { canRenderLightweightPlainTextRow } from '../../util/messageBubbleReuse';
import { ChatTimelineSession } from './ChatTimelineSession';
import { BLUR_MAX_VP, edgeBlurStops } from '../../util/scrollEdgeBlur';

// 完整消息流渲染宿主：List、Repeat、行与覆盖层都归同一组件。
// 数据发布与视口状态由 ChatTimelineSession 持有。
// Repeat 自身的外壳复用开关。
//
// **必须是 false。2026-09-10 三轮真机，官方处方的完整形态也没治好。**
//
// 试过并排除的（按顺序，别再重走）：
//   1. 修 rowReuseId 的结构分桶 —— reusable:true 下内层 reuseId 池根本不被用
//   2. 补 6 处「只有 aboutToReuse、没有等效 @Monitor」的组件 —— 是真缺口，
//      已修保留，但补完开 true 仍然重复
//   3. **官方处方的完整形态**：垫一层普通 V2 组件（MessageRowHost）+ 可枚举的
//      templateId 分外壳池（五档全注册）—— **仍然重复**
//
// 也就是说，Repeat 自身的外壳复用与本项目这种「每行结构差异极大的消息流」
// 存在一个尚未定位的不兼容点，官方文档给的两条处置都盖不住。
// 开着的那几版手感确实更好（外壳不再每帧重建、震颤明显减轻），但正确性优先。
//
// 薄壳与 templateId 都留着：它们本身符合官方对结构的要求，无害；真要再试第四
// 次时省掉重新搭台的功夫。
const REPEAT_ROW_REUSE: boolean = false;

const CHAT_TIMELINE_FLING_SPEED_LIMIT_VP_S: number = 4200;

// 锚点补偿：量不到锚点行时下一帧再量，最多几次、每次隔多久（见 restoreScrollAnchor）。

@ComponentV2
export struct ChatTimelineHost {
  @Require @Param session: ChatTimelineSession;
  @Require @Param selection: SelectionSession;
  @Require @Param rowPageInputs: RowPageInputs;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param reusePageScope: number;
  @Param nowSec: number = 0;
  @Param listCachedCount: number = 8;
  @Param appearanceEpoch: number = 0;
  @Param headerStartOffset: number = 0;
  @Param bottomChromeH: number = 0;
  @Param threadRootId: number = 0;
  @Param membershipState: string = '';
  @Param screenW: number = 360;
  @Param langEpoch: number = 0;
  @Param materialEpoch: number = 0;
  @Param timelineTopMargin: number = 0;

  // 列表实测高度（vp）：linearGradientBlur 的 fractionStops 按实际高度归一化。
  @Local private timelineViewH: number = 0;

  // 滑动中把上下两端渐隐模糊关掉（用户 2026-11-05）。
  //
  // linearGradientBlur 是离屏渲染：整条列表先进离屏层、再按渐变合成，滑动时
  // 每一帧都要重做一次。会话页行高、图片、视频都在动，这一层叠上去会直接掉帧。
  // onScrollStart/Stop 正好包住"手指按住 + 惯性滑动"整段，停稳后（含惯性结束）
  // 自动恢复，不需要额外定时器。
  @Local private scrollActive: boolean = false;

  @Event onEmptyRetry: () => void = (): void => {};
  // 【第二轮第 12 项】签名从 `() => void` 改成带 mode。
  // 原来页面收到这个事件之后**自己重算一遍** timelinePillMode()，但它读的是
  // 页面的活字段，而用户看到的这枚 pill 是本组件按 @Param 进来的 timeline
  // 快照渲染的——两者会分叉（onMessagesSnapshot 在 historyState===loading
  // 那条早退路径上写了 loadState 却不 commit 快照）。分叉时用户点"重试"，
  // 页面算出来已经不是 error，三个分支一个都不进，按钮点了没反应。
  // 现在由本组件把**它显示时算出的那个 mode** 一起传上去，页面直接用。
  @Event onTimelinePillRetry: (mode: string) => void = (): void => {};

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // 入参是**整个 RepeatItem**，不是从它里面取出来的值。官方《Repeat》使用限制：
  // 「当 Repeat 与自定义组件或 @Builder 函数混用时，必须将 RepeatItem 类型整体
  // 进行传参，组件才能监听到数据变化」，反例正是按值传 ri.item —— 那样 Repeat
  // 更新这一行时（它只换 RepeatItem 里的 item，不重跑 .each()）这个 @Builder
  // 里的 UI 不会刷新。所以 ri 一路传到这里，group/data 都在本作用域内现取。
  // 气泡外面垫一层普通 V2 组件（MessageRowHost）：官方明写 V2 复用组件不支持
  // 直接用于 Repeat 的 template 中，只能放在 template 里的普通 V2 组件之下。
  // 薄壳透传已准备的参数，reuseId 在里面用当前行计算并挂给内层气泡。
  @Builder
  private preparedMessageBubble(ri: RepeatItem<AlbumGroup>) {
    // 每次参数绑定只准备一次；宿主用同一份 data 与当前 group 现算复用桶。
    MessageRowHost({
      group: ri.item,
      nowSec: this.nowSec,
      data: this.session.prepareMessageBubble(ri.item, this.rowPageInputs).data,
      actions: this.actions,
      reusePageScope: this.reusePageScope
    });
  }

  // Repeat 的模板名。分的是**外壳**的池，必须可枚举（见 util/rowTemplateId）。
  private rowTemplateIdOf(group: AlbumGroup): string {
    // 【不要在这里调 prepareMessageBubble】它为了查缓存要先拼一条 25 段的
    // cacheKey，而 Repeat 每决定一次模板都会调这里。首屏 JS profile 里
    // prepareMessageBubble 的 605.8ms 有 284.9ms 是从这条路进来的，换回来的只是
    // 一个布尔——而那个布尔只依赖行对象本身（见 canRenderLightweightPlainTextRow）。
    const lightweight: boolean = canRenderLightweightPlainTextRow(
      group.head, group.memberIds.length, group.photoPaths.length) &&
      group.head.translatedText === '';
    // 【只看内容类型，不看多选开没开】进出多选若换模板，Repeat 会销毁重建整行，
    // SelectionSession 那 150ms 的 animateTo 就没有东西可插值（见 rowTemplateId）。
    const gutter: boolean = rowSelectable(group.head.contentType);
    return rowTemplateId(group, lightweight, gutter);
  }

  // List 与所有行在同一宿主创建，保留完整的组件所有权边界。
  @LocalBuilder
  timelineList() {
    List({ scroller: this.session.scroller }) {
      Repeat<AlbumGroup>(this.session.timelineRows)
        .each((ri: RepeatItem<AlbumGroup>) => {
          this.timelineRow(ri);
        })
        // 五个模板**共用同一个 builder**：templateId 只负责把外壳的缓存池按结构
        // 分开，渲染逻辑一份就够。少注册一个，那一档就退回 .each 的默认池，
        // 等于没分——所以遍历 ROW_TEMPLATE_IDS 注册，不手写五遍。
        .templateId((group: AlbumGroup, _index: number): string =>
          this.rowTemplateIdOf(group))
        .template(ROW_TEMPLATE_DEFERRED, (ri: RepeatItem<AlbumGroup>) => {
          this.timelineRow(ri);
        }, { cachedCount: 8 })
        .template(ROW_TEMPLATE_PLAIN, (ri: RepeatItem<AlbumGroup>) => {
          this.timelineRow(ri);
        }, { cachedCount: 10 })
        .template(ROW_TEMPLATE_PLAIN_GUTTER, (ri: RepeatItem<AlbumGroup>) => {
          this.timelineRow(ri);
        }, { cachedCount: 8 })
        .template(ROW_TEMPLATE_RICH, (ri: RepeatItem<AlbumGroup>) => {
          this.timelineRow(ri);
        }, { cachedCount: 10 })
        .template(ROW_TEMPLATE_RICH_GUTTER, (ri: RepeatItem<AlbumGroup>) => {
          this.timelineRow(ri);
        }, { cachedCount: 8 })
        .key((group: AlbumGroup): string => this.session.rowKeyOf(group))
        // Repeat owns the ListItem root, so let it reuse that complete subtree.
        // Forcing reusable=false delegates scrolling reuse to the nested
        // @ReusableV2 bubble. During a history prepend that bubble is then
        // detached from one Repeat node and attached to another, which ArkUI
        // reports as setChild/changing-parent and renders as a row flash.
        // Repeat reuse updates the complete RepeatItem binding; the bubble's
        // @Monitor('group') reattaches its presentation subscription.
        // ⚠️ **reusable 必须是 false，别再改回 true。** 2026-09-10 两轮真机定案。
        //
        // 第二轮（补齐 6 处「只有 aboutToReuse、没有等效 @Monitor」的组件之后
        // 再开 true）**重复依然复现**——所以那 6 处不是根因，已从嫌疑里排除。
        // 那一版的手感确实变好（外壳不再每次重建、震颤明显减轻），但正确性
        // 压过流畅度。
        //
        // 【症状】往上翻历史时，每隔一个复用池容量就出现一条"比上下都新"的
        // 消息——同一条消息在列表里重复出现，相册的位置画成文本、不该有图的
        // 气泡长出图、滑动中显示 a 停稳后变 b，全是这一个 bug 的不同切面。
        //
        // 【数据侧全部清白】[OrderGuard] 窗口严格升序 0 告警；[Visible] 打出的
        // 可见区 id 严格递增且相邻（差恒为 1048576）；[MergeGuard] 两页合并的
        // 边界假设成立。**模型从头到尾是对的，错的只有屏幕。**
        //
        // 【怎么锁定到复用池】重复的周期跟着 List 的 cachedCount 走：
        // cachedCount=4 时每 21 条重复一次，改成 8 之后变成 27
        // （周期 ≈ 可视行数 + 2×cachedCount，正是一次最坏回收潮的池子容量）。
        // 这个判据来自设备本身，不依赖任何探针参照物。
        //
        // 【为什么是这一层】这里叠了两层复用：Repeat 复用整个 ListItem 子树，
        // 气泡又有自己的 @ReusableV2 池（.reuse({reuseId})）。把本行改成 false
        // 之后重复完全消失（用户实测长时间翻阅无一例），说明壳没更新发生在
        // Repeat 这一层。
        //
        // 【代价，已知并接受】false **不等于不复用**——滚动复用交回给内层的
        // @ReusableV2 气泡，贵的那部分子树照常复用。原注释记录的代价是：前插时
        // 气泡会在两个 Repeat 节点之间搬家，ArkUI 报 setChild/changing-parent，
        // 表现为行闪一下。拿"偶尔闪一下"换"消息不再重复"，值。
        .virtualScroll({ totalCount: this.session.timelineRows.length, reusable: REPEAT_ROW_REUSE });
    }
    .width('100%').height('100%')
    .opacity(this.session.initialTimelineMasked ? 0 : 1)
    .contentStartOffset(this.headerStartOffset)
    // 【PR 那笔补偿只留一半】List 和输入框在同一个 Stack 里，List 本来就铺满整屏，
    // 负 margin 没有"下边界可延伸"、不起作用，而 contentEndOffset 是实打实生效的。
    // PR 写的是 `chrome * 2 + 8`（比上游的 `chrome + 8` 多了一整个输入框高度），
    // 实测最后一条消息被抬得偏高；用户 2026-11-05 要求"距离缩回一半"，即只保留
    // 多出来那一半。
    .contentEndOffset(this.bottomChromeH * 1.5 + 8)
    .cachedCount(this.listCachedCount)
    // Media-heavy frames can make a short release look like an 8-9k vp/s
    // fling. Cap only the inertial phase; direct finger tracking is unchanged.
    .flingSpeedLimit(CHAT_TIMELINE_FLING_SPEED_LIMIT_VP_S)
    // maintainVisibleContentPosition only protects insertions above the visible
    // area. stackFromEndWanted separately disables end anchoring once the list
    // is scrollable, so tail appends cannot move a parked viewport.
    .maintainVisibleContentPosition(true)
    .stackFromEnd(this.session.stackFromEndWanted())
    .onReachStart((): void => {
      if (!this.session.jumpLandingHolding()) {
        this.session.maybeLoadOlder();
      }
    })
    .onTouch((event: TouchEvent): void => { this.session.handleTimelineTouch(event); })
    .onScrollIndex((start: number, end: number): void => {
      this.session.handleTimelineScrollIndex(start, end);
    })
    .onWillScroll((offset: number, state: ScrollState, source: ScrollSource): void => {
      this.session.handleTimelineWillScroll(offset, state, source);
    })
    .onDidScroll((offset: number, state: ScrollState): void => {
      this.session.handleTimelineDidScroll(offset, state);
    })
    .onScrollStart((): void => {
      this.scrollActive = true;
      this.session.handleTimelineScrollStart();
    })
    .onScrollStop((): void => {
      this.scrollActive = false;
      this.session.handleTimelineScrollStop();
    })
    // 顶部/底部边缘渐变虚化：与首页会话列表同一套参数（顶/底 118vp、峰 22px）。
    // 消息 List 的上沿就是屏幕顶（标题栏 enableComponentSafeArea: false、会话头由
    // 主题栏悬浮在内容之上），所以渐变原点天然对齐，无需再上顶。
    // 半径传 0 = 完全不糊（stops 仍然有效，只是没有模糊半径）。
    .linearGradientBlur(this.scrollActive ? 0 : BLUR_MAX_VP, {
      fractionStops: edgeBlurStops(this.timelineViewH),
      direction: GradientDirection.Bottom
    })
    .onAreaChange((_old: Area, area: Area): void => {
      const h: number = Number(area.height);
      if (h > 0 && Math.abs(h - this.timelineViewH) > 0.5) {
        this.timelineViewH = h;
      }
      this.session.handleTimelineAreaChange(area);
    });
  }

  // Repeat supplies the complete item metadata here. Keeping the row builder
  // on the page preserves the existing message-bubble/reuse and selection
  // behavior.
  @Builder
  timelineRow(ri: RepeatItem<AlbumGroup>) {
    ListItem() {
      if (ri.item.initialDeferred === true) {
        Column()
          .width('100%')
          .height(this.session.viewportGeometry.rowHeight(ri.item))
          .hitTestBehavior(HitTestMode.None);
      } else {
        // 这里原来还套着一层 Stack({ alignContent: Start })：单子节点、零属性，每行白付
        // 一个节点和一层测量，已去掉（2026-09-14）。
        // Selection mode shifts the row right into a left check gutter.
        Row() {
          // 【让位栏必须是常驻节点，不能是结构 if】
          // 结构 if 是凭空插入/移除节点，插值不出来——所以进出多选是"闪过去"
          // 的，哪怕 SelectionSession.animateSelection 早就用 animateTo 包着
          // active 的翻转。改成常驻、宽度 0↔34，那 150ms 才有东西可插。
          // 条件换成 rowSelectable（内容类型决定，不随多选翻转），这个节点在
          // 与不在于是变成**静态**的，模板池也就不必再按多选分档。
          // 里面的勾选图标仍按 active 条件建：不在多选态时不付图标的钱，常驻
          // 的只是一个零宽空 Column。
          if (rowSelectable(ri.item.head.contentType)) {
            Column() {
              // 相册行也画这个勾：它是**整组**的开关（沾上就算选中，点它整组
              // 清空），而每一格右上角那个是**单张**的（见 AlbumCellView）。
              // 两者分工清楚，缺了整组开关的话，长按进多选默认整组选中之后
              // 用户只能一张一张取消。
              if (this.selection.active) {
                if (this.selection.isRowSelected(ri.item)) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .fontSize(22).fontColor([this.accent()]);
                } else {
                  Row()
                    .width(20).height(20).borderRadius(10)
                    .border({ width: 1.5, color: '#8E8E93' });
                }
              }
            }
            .width(this.selection.active ? MESSAGE_SELECTION_GUTTER_VP : 0)
            .opacity(this.selection.active ? 1 : 0)
            // 宽度收到 0 的过程中图标会溢出压到气泡上，必须裁掉。
            .clip(true)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            // 相册行的**行点击**不再切整行（见下方 onClick），所以整组开关要有
            // 自己的点击。非相册行由行点击兜住，这里重复触发也无妨：ArkUI 的
            // onClick 会冒泡，但相册行那边的行点击已经早退。
            .onClick((): void => {
              if (this.selection.active) {
                this.selection.toggleRow(ri.item);
              }
            });
          }
          Column() {
            this.preparedMessageBubble(ri);
          }
          .layoutWeight(1)
          // BLOCK_DESCENDANTS keeps the outer List draggable in selection mode.
          //
          // **相册行例外（2026-09-11）**：屏蔽后代的话相册格子在多选态下根本
          // 收不到触摸，每一格自己的 onClick 永远不跑，所有点击都落到行的
          // toggleRow 上——用户看到的就是"取消一张，整组全没了"。
          // 格子上只有 onClick（拖动不会触发），所以放开它不影响列表拖动。
          .hitTestBehavior(this.selection.active &&
            rowSelectable(ri.item.head.contentType) && ri.item.memberIds.length <= 1
            ? HitTestMode.BLOCK_DESCENDANTS : HitTestMode.Default);
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.selection.active && this.selection.isRowSelected(ri.item)
          ? $r('app.color.select_highlight') : Color.Transparent)
        .onClick((): void => {
          if (!this.selection.active) {
            return;
          }
          // 相册行早退：整组开关在让位栏上，单张开关在每个格子上。这里再切一次
          // 会把格子刚做的单张切换整行撤销（onClick 会冒泡到这里）。
          if (ri.item.memberIds.length > 1) {
            return;
          }
          this.selection.toggleRow(ri.item);
        });
      }
    }
    .visibility(this.session.initialTimelineMasked || ri.item.initialDeferred === true
      ? Visibility.Hidden : Visibility.Visible)
    .transition(this.session.initialRowFadeTransition(
      ri.index, ri.item.initialDeferred === true))
    // 【为什么是 onSizeChange 不是 onAreaChange】(2026-09-11 帧 trace)
    // onAreaChange 的「area」含**位置**：滚动中每一行每一帧位置都在变，于是每行
    // 每帧都回调一次。trace 实测 HandleOnAreaChangeEvent 每帧派发 ~48 次 JS 回
    // 调、合计 1.20ms——而一个正常帧总共才 4.16ms（29%）。可这里要的只有高度，
    // 那 48 次里绝大多数报的是同一个高度。
    // onSizeChange（API 12，远低于底线 20）只在尺寸真的变了才回调，滚动稳态下
    // 基本不触发。
    // SizeOptions.height 的静态类型是 Length（number|string|Resource），运行时
    // ArkUI 给的是 vp 数值；非数值一律丢弃，record 本身也再挡一道有限性检查。
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const raw: Length | undefined = size.height;
      if (typeof raw !== 'number') {
        return;
      }
      this.session.viewportGeometry.record(
        ri.index,
        ri.item,
        raw as number,
        ri.item.initialDeferred !== true && !this.selection.active
      );
    });
  }

  private effectivelyHasVisibleRows(): boolean {
    return this.session.timelineSnapshot.hasVisibleRows && !this.session.initialTimelineMasked;
  }

  private timelinePillMode(): string {
    return timelineStateMode(
      this.effectivelyHasVisibleRows() ? 1 : 0,
      this.session.timelineSnapshot.messageLoadState,
      this.session.timelineSnapshot.olderLoadState,
      this.session.timelineSnapshot.newerLoadState
    );
  }

  private timelinePillLabel(): string {
    return this.langEpoch < 0 ? '' : timelineStateText(this.timelinePillMode());
  }

  build() {
    // Date and paging overlays use top-relative margins. Stack defaults to
    // Center, so preserve the TopStart alignment of their former ChatPage host.
    Stack({ alignContent: Alignment.TopStart }) {
      this.timelineList();

      if (!this.session.initialTimelineMasked && !this.session.timelineSnapshot.hasVisibleRows &&
        this.session.timelineSnapshot.messageLoadState !== 'loading') {
        Column() {
          MessageListStateCard({
            loadState: this.session.timelineSnapshot.messageLoadState,
            loadError: this.session.timelineSnapshot.messageLoadError,
            threadRootId: this.threadRootId,
            membershipState: this.membershipState,
            isChannel: this.session.timelineSnapshot.isChannel,
            isGroup: this.session.timelineSnapshot.isGroup,
            screenW: this.screenW,
            onRetry: (): void => { this.onEmptyRetry(); }
          });
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: this.bottomChromeH + 28 })
        .hitTestBehavior(HitTestMode.Transparent);
      } else if (this.timelinePillMode() !== TL_NONE) {
        TimelineStatePillSlot({
          state: this.session.floatDateState,
          topInset: this.headerStartOffset,
          mode: this.timelinePillMode(),
          label: this.timelinePillLabel(),
          onRetry: (): void => { this.onTimelinePillRetry(this.timelinePillMode()); }
        });
      }

      // 0 行（或首屏仍被遮罩）+ 正在首次加载：以 Telegram 风格的气泡骨架占位。
      if (showInitialLoadingHint(
        this.effectivelyHasVisibleRows(),
        this.session.initialTimelineMasked ? 'loading' : this.session.timelineSnapshot.messageLoadState
      )) {
        InitialLoadingHint({
          immediate: this.session.timelineSnapshot.messageLoadState === 'loading',
          isGroup: this.session.timelineSnapshot.isGroup,
          isChannel: this.session.timelineSnapshot.isChannel,
          screenW: this.screenW,
          topInset: this.headerStartOffset,
          bottomInset: this.bottomChromeH,
          materialEpoch: this.materialEpoch
        });
      }

      FloatingDateOverlay({
        state: this.session.floatDateState,
        materialEpoch: this.materialEpoch,
        topMargin: this.timelineTopMargin
      });
    }
    .width('100%').height('100%');
  }
}
