import { MessageListStateCard } from './MessageListState';
import {
  FloatingDateOverlay, FloatingDateState, TimelineStatePillSlot
} from './FloatingDateOverlay';
import {
  ChatTimelineSnapshot, emptyChatTimelineSnapshot
} from '../../util/chatTimelineSnapshot';
import { TL_NONE, timelineStateMode, timelineStateText } from '../../util/timelineState';

// Timeline presentation host. ChatPage owns the scroller, row data, paging,
// media/translation work, and every scroll-side effect. The List itself is a
// page-owned @LocalBuilder so Repeat and its reusable rows share one component
// owner; this host only layers the list with timeline overlays.
@ComponentV2
export struct ChatTimelineHost {
  @Param timeline: ChatTimelineSnapshot = emptyChatTimelineSnapshot();
  @Param initialTimelineMasked: boolean = false;
  @Param headerStartOffset: number = 0;
  @Param bottomChromeH: number = 0;
  @Param threadRootId: number = 0;
  @Param membershipState: string = '';
  @Param screenW: number = 360;
  @Param langEpoch: number = 0;
  @Param floatDateState: FloatingDateState = new FloatingDateState();
  @Param materialEpoch: number = 0;
  @Param timelineTopMargin: number = 0;

  @BuilderParam timelineList: () => void;

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
      this.timeline.hasVisibleRows ? 1 : 0,
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
      this.timelineList();

      if (!this.initialTimelineMasked && !this.timeline.hasVisibleRows &&
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

      FloatingDateOverlay({
        state: this.floatDateState,
        materialEpoch: this.materialEpoch,
        topMargin: this.timelineTopMargin
      });
    }
    .width('100%').height('100%');
  }
}
