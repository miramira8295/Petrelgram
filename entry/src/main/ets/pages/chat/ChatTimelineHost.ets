import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageListStateCard } from './MessageListState';
import {
  FloatingDateOverlay, FloatingDateState, TimelineStatePillSlot
} from './FloatingDateOverlay';
import {
  ChatTimelineSnapshot, emptyChatTimelineSnapshot
} from '../../util/chatTimelineSnapshot';
import { TL_NONE, timelineStateMode, timelineStateText } from '../../util/timelineState';
import { JumpFlashState } from './JumpFlashState';

const CHAT_TIMELINE_FLING_SPEED_LIMIT_VP_S: number = 4200;

// Timeline presentation host. ChatPage owns the scroller, row data, paging,
// media/translation work, and every scroll-side effect; this component only
// renders the list and forwards its events.
@ComponentV2
export struct ChatTimelineHost {
  @Param timeline: ChatTimelineSnapshot = emptyChatTimelineSnapshot();
  @Param scroller: Scroller = new Scroller();
  @Param initialTimelineMasked: boolean = false;
  @Param headerStartOffset: number = 0;
  @Param bottomChromeH: number = 0;
  @Param listCachedCount: number = 0;
  @Param stackFromEnd: boolean = false;
  @Param threadRootId: number = 0;
  @Param membershipState: string = '';
  @Param screenW: number = 360;
  @Param langEpoch: number = 0;
  @Param floatDateState: FloatingDateState = new FloatingDateState();
  @Param materialEpoch: number = 0;
  @Require @Param flash: JumpFlashState;
  @Param timelineTopMargin: number = 0;

  @BuilderParam timelineRow: (ri: RepeatItem<AlbumGroup>) => void;

  @Event rowKey: (group: AlbumGroup) => string = (): string => '';
  @Event onTimelineReachStart: () => void = (): void => {};
  @Event onTimelineTouch: (event: TouchEvent) => void = (): void => {};
  @Event onTimelineScrollIndex: (start: number, end: number) => void = (): void => {};
  @Event onTimelineWillScroll: (
    offset: number, state: ScrollState, source: ScrollSource
  ) => void = (): void => {};
  @Event onTimelineDidScroll: (offset: number, state: ScrollState) => void = (): void => {};
  @Event onTimelineScrollStart: () => void = (): void => {};
  @Event onTimelineScrollStop: () => void = (): void => {};
  @Event onTimelineAreaChange: (area: Area) => void = (): void => {};
  @Event onEmptyRetry: () => void = (): void => {};
  // 【第二轮第 12 项】签名从 `() => void` 改成带 mode。
  // 原来页面收到这个事件之后**自己重算一遍** timelinePillMode()，但它读的是
  // 页面的活字段，而用户看到的这枚 pill 是本组件按 @Param 进来的 timeline
  // 快照渲染的——两者会分叉（onMessagesSnapshot 在 historyState===loading
  // 那条早退路径上写了 loadState 却不 commit 快照）。分叉时用户点"重试"，
  // 页面算出来已经不是 error，三个分支一个都不进，按钮点了没反应。
  // 现在由本组件把**它显示时算出的那个 mode** 一起传上去，页面直接用。
  @Event onTimelinePillRetry: (mode: string) => void = (): void => {};

  private timelinePillMode(): string {
    return timelineStateMode(
      this.timeline.visibleGroupCount,
      this.timeline.messageLoadState,
      this.timeline.olderLoadState,
      this.timeline.newerLoadState
    );
  }

  private timelinePillLabel(): string {
    return this.langEpoch < 0 ? '' : timelineStateText(this.timelinePillMode());
  }

  build() {
    // Date and paging overlays use top-relative margins. Stack defaults to
    // Center, so preserve the TopStart alignment of their former ChatPage host.
    Stack({ alignContent: Alignment.TopStart }) {
      List({ scroller: this.scroller }) {
        Repeat<AlbumGroup>(this.timeline.groups)
          .each((ri: RepeatItem<AlbumGroup>) => {
            this.timelineRow(ri);
          })
          .key((group: AlbumGroup): string => this.rowKey(group))
          .virtualScroll({ totalCount: this.timeline.groups.length, reusable: false });
      }
      .width('100%').height('100%')
      .opacity(this.initialTimelineMasked ? 0 : 1)
      .contentStartOffset(this.headerStartOffset)
      .contentEndOffset(this.bottomChromeH + 8)
      .cachedCount(this.listCachedCount)
      // Media-heavy frames can make a short release look like an 8-9k vp/s
      // fling. Cap only the inertial phase; direct finger tracking is unchanged.
      .flingSpeedLimit(CHAT_TIMELINE_FLING_SPEED_LIMIT_VP_S)
      // Media rows can change height as metadata and grouped content resolve.
      // Feeding every visible measurement back through childrenMainSize makes
      // List rebuild its complete position map during a drag, which turns a
      // short gesture into a multi-screen jump. Keep geometry caching for
      // initial placeholders, but let List own live row measurement.
      .maintainVisibleContentPosition(true)
      .stackFromEnd(this.stackFromEnd)
      .onReachStart((): void => { this.onTimelineReachStart(); })
      .onTouch((event: TouchEvent): void => { this.onTimelineTouch(event); })
      .onScrollIndex((start: number, end: number): void => {
        this.onTimelineScrollIndex(start, end);
      })
      .onWillScroll((offset: number, state: ScrollState, source: ScrollSource): void => {
        this.onTimelineWillScroll(offset, state, source);
      })
      .onDidScroll((offset: number, state: ScrollState): void => {
        this.onTimelineDidScroll(offset, state);
      })
      .onScrollStart((): void => { this.onTimelineScrollStart(); })
      .onScrollStop((): void => { this.onTimelineScrollStop(); })
      .onAreaChange((_old: Area, area: Area): void => {
        this.onTimelineAreaChange(area);
      });

      if (!this.initialTimelineMasked && this.timeline.visibleGroupCount === 0 &&
        this.timeline.messageLoadState !== 'loading') {
        Column() {
          MessageListStateCard({
            loadState: this.timeline.messageLoadState,
            loadError: this.timeline.messageLoadError,
            threadRootId: this.threadRootId,
            membershipState: this.membershipState,
            isChannel: this.timeline.isChannel,
            isGroup: this.timeline.isGroup,
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
          state: this.floatDateState,
          topInset: this.headerStartOffset,
          mode: this.timelinePillMode(),
          label: this.timelinePillLabel(),
          onRetry: (): void => { this.onTimelinePillRetry(this.timelinePillMode()); }
        });
      }

      if (this.flash.shown) {
        Column()
          .width('100%').height(this.flash.height)
          .backgroundColor('#4D67A0DC')
          .borderRadius(8)
          .opacity(this.flash.alpha)
          .position({ x: 0, y: this.flash.top })
          .hitTestBehavior(HitTestMode.None);
      }

      FloatingDateOverlay({
        state: this.floatDateState,
        materialEpoch: this.materialEpoch,
        topMargin: this.timelineTopMargin
      });
    }
    .width('100%').height('100%');
  }
}
