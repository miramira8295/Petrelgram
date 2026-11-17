import { TdObject } from '../../tdkit/TdTypes';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnRichLink } from '../../util/drawnRichTextPolicy';
import { setTableScrollTouch } from '../../util/tableTouchChannel';
import { DrawnTablePlacement } from './DrawnRichTextLayout';
import { DrawnRichTextView } from './DrawnRichTextView';

// One native scroll viewport per table, not Row/Flex/Text nodes per cell.
// Scrolling moves retained drawing commands; no reparsing or reshaping.
@ComponentV2
export struct DrawnTableIsland {
  @Require @Param msg: MessageEntry;
  @Require @Param placement: DrawnTablePlacement;
  @Event onMetricsChanged: () => void = (): void => {};
  @Event onLinkTap: (link: DrawnRichLink) => void = (_link: DrawnRichLink): void => {};
  @Event onClaimTouch: () => void = (): void => {};
  private ownerRow: number = 0;
  private ownerBlocks: TdObject[] | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private touching: boolean = false;
  aboutToAppear(): void { this.ownerRow = this.msg.rowId; this.ownerBlocks = this.msg.richBlocks; }
  @Monitor('msg')
  resetOwner(): void {
    if (this.ownerRow === this.msg.rowId && this.ownerBlocks === this.msg.richBlocks) { return; }
    this.ownerRow = this.msg.rowId; this.ownerBlocks = this.msg.richBlocks;
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.releaseTouch();
  }
  private releaseTouch(): void {
    if (this.touching) { this.touching = false; setTableScrollTouch(false); }
  }
  aboutToDisappear(): void { this.releaseTouch(); }
  build() {
    Scroll(this.scroller) {
      DrawnRichTextView({ msg: this.msg, plan: this.placement.layout, onMetricsChanged: (): void => this.onMetricsChanged(),
        onLinkTap: (link: DrawnRichLink): void => { this.onLinkTap(link); } });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.TopStart)
    .enableScrollInteraction(this.placement.layout.widthVp > this.placement.width)
    .width(this.placement.width).height(this.placement.height).clip(true)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.placement.layout.widthVp > this.placement.width) {
        this.touching = true; setTableScrollTouch(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.releaseTouch(); }
    })
    .onClick((): void => { this.onClaimTouch(); });
  }
}
