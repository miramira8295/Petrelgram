import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageListStateCard } from './MessageListState';
import {
  FloatingDateOverlay, FloatingDateState, TimelineStatePillSlot
} from './FloatingDateOverlay';

// Timeline presentation host. ChatPage owns the scroller, row data, paging,
// media/translation work, and every scroll-side effect; this component only
// renders the list and forwards its events.
@ComponentV2
export struct ChatTimelineHost {
  @Param groups: AlbumGroup[] = [];
  @Param scroller: Scroller = new Scroller();
  @Param initialTimelineMasked: boolean = false;
  @Param headerStartOffset: number = 0;
  @Param blurRadius: number = 0;
  @Param blurStops: [number, number][] = [];
  @Param bottomChromeH: number = 0;
  @Param listCachedCount: number = 0;
  @Param stackFromEnd: boolean = false;
  @Param visibleGroupCount: number = 0;
  @Param messageLoadState: string = 'loading';
  @Param messageLoadError: string = '';
  @Param threadRootId: number = 0;
  @Param membershipState: string = '';
  @Param isChannel: boolean = false;
  @Param isGroup: boolean = false;
  @Param screenW: number = 360;
  @Param floatDateState: FloatingDateState = new FloatingDateState();
  @Param materialEpoch: number = 0;
  @Param showTimelinePill: boolean = false;
  @Param timelinePillMode: string = '';
  @Param timelinePillLabel: string = '';
  @Param flashShown: boolean = false;
  @Param flashTop: number = 0;
  @Param flashHeight: number = 0;
  @Param flashAlpha: number = 0;
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
  @Event onTimelinePillRetry: () => void = (): void => {};

  build() {
    // Date and paging overlays use top-relative margins. Stack defaults to
    // Center, so preserve the TopStart alignment of their former ChatPage host.
    Stack({ alignContent: Alignment.TopStart }) {
      List({ scroller: this.scroller }) {
        Repeat<AlbumGroup>(this.groups)
          .each((ri: RepeatItem<AlbumGroup>) => {
            this.timelineRow(ri);
          })
          .key((group: AlbumGroup): string => this.rowKey(group))
          .virtualScroll({ totalCount: this.groups.length, reusable: false });
      }
      .width('100%').height('100%')
      .opacity(this.initialTimelineMasked ? 0 : 1)
      .contentStartOffset(this.headerStartOffset)
      .linearGradientBlur(this.blurRadius, {
        fractionStops: this.blurStops,
        direction: GradientDirection.Bottom
      })
      .contentEndOffset(this.bottomChromeH + 8)
      .cachedCount(this.listCachedCount)
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

      if (!this.initialTimelineMasked && this.visibleGroupCount === 0 &&
        this.messageLoadState !== 'loading') {
        Column() {
          MessageListStateCard({
            loadState: this.messageLoadState,
            loadError: this.messageLoadError,
            threadRootId: this.threadRootId,
            membershipState: this.membershipState,
            isChannel: this.isChannel,
            isGroup: this.isGroup,
            screenW: this.screenW,
            onRetry: (): void => { this.onEmptyRetry(); }
          });
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: this.bottomChromeH + 28 })
        .hitTestBehavior(HitTestMode.Transparent);
      } else if (this.showTimelinePill) {
        TimelineStatePillSlot({
          state: this.floatDateState,
          topInset: this.headerStartOffset,
          mode: this.timelinePillMode,
          label: this.timelinePillLabel,
          onRetry: (): void => { this.onTimelinePillRetry(); }
        });
      }

      if (this.flashShown) {
        Column()
          .width('100%').height(this.flashHeight)
          .backgroundColor('#4D67A0DC')
          .borderRadius(8)
          .opacity(this.flashAlpha)
          .position({ x: 0, y: this.flashTop })
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
