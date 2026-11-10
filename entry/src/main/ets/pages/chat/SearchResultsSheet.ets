import { curves } from '@kit.ArkUI';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { SearchSession } from './SearchSession';
import { getChatStore, getTdClient, getUserStore } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { formatPreview } from '../../util/formatPreview';
import { monthDayTime } from '../../util/intlFormat';
import { searchCounterText } from '../../util/searchPaging';
import { SearchHitText } from '../search/SearchHitText';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { pushSheetDismiss } from '../../util/sheetDismissStack';

// Presentation only: search owns filtering/paging, and its existing host owns
// message jumps. Opening or paging this sheet never touches the chat timeline.
@ComponentV2
export struct SearchResultsSheet {
  @Require @Param search: SearchSession;
  @Local private names: Map<number, string> = new Map();
  private requested: Set<number> = new Set();
  private active: boolean = false;
  @Local private panelH: number = 320;
  @Local private shown: boolean = false;
  @Local private dragY: number = 0;
  private entered: boolean = false;
  private closing: boolean = false;
  private scroller: Scroller = new Scroller();
  private positioned: boolean = false;
  private unregisterBack: (() => void) | null = null;

  aboutToAppear(): void {
    this.active = true;
    this.unregisterBack = pushSheetDismiss((): void => { this.close(); });
    this.resolveNames();
  }

  aboutToDisappear(): void {
    this.active = false;
    this.unregisterBack?.();
    this.unregisterBack = null;
  }

  private enter(): void {
    if (this.entered) { return; }
    this.entered = true;
    const duration = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240);
    if (duration <= 0) { this.shown = true; return; }
    this.getUIContext().animateTo({ duration, curve: Curve.Friction }, (): void => { this.shown = true; });
  }

  private close(messageId: number = 0): void {
    if (this.closing) { return; }
    this.closing = true;
    const finish = (): void => {
      if (!this.active) { return; }
      if (messageId > 0) { this.search.chooseResult(messageId); }
      else { this.search.closeResults(); }
    };
    const duration = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180);
    if (duration <= 0) { finish(); return; }
    this.getUIContext().animateTo({ duration, curve: Curve.Friction, onFinish: finish }, (): void => { this.shown = false; });
  }

  private updateDrag(offsetY: number): void {
    if (!this.shown || this.closing) { return; }
    this.dragY = offsetY < 0 ? -20 * (-offsetY) / (100 - offsetY) : Math.min(this.panelH, offsetY);
  }

  private restoreDrag(): void {
    if (this.closing) { return; }
    const duration = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 240);
    if (duration <= 0) { this.dragY = 0; return; }
    this.getUIContext().animateTo({ duration, curve: curves.springMotion(0.32, 0.82) }, (): void => { this.dragY = 0; });
  }

  private finishDrag(velocityY: number): void {
    if (this.closing) { return; }
    const distance = Math.max(48, Math.min(96, this.panelH * 0.25));
    if (this.dragY >= distance || (this.dragY >= 16 && velocityY > 900)) { this.close(); }
    else { this.restoreDrag(); }
  }

  @Monitor('search.resultMessages')
  onMessagesChanged(): void { if (this.active) { this.resolveNames(); } }

  private userId(messageId: number): number {
    const sender = this.search.resultMessages.get(messageId)?.['sender_id'] as TdObject | undefined;
    return (sender?.['user_id'] as number | undefined) ?? 0;
  }

  private resolveNames(): void {
    const names = new Map(this.names);
    for (const id of this.search.results) {
      const userId = this.userId(id);
      if (userId <= 0 || this.requested.has(userId)) { continue; }
      this.requested.add(userId);
      const cached = getUserStore().displayName(userId);
      if (cached !== '') { names.set(userId, cached); continue; }
      const request: TdRequest = { '@type': 'getUser' };
      request['user_id'] = userId;
      getTdClient().send(request).then((user: TdObject): void => {
        if (!this.active) { return; }
        const first = (user['first_name'] as string | undefined) ?? '';
        const last = (user['last_name'] as string | undefined) ?? '';
        const updated = new Map(this.names);
        updated.set(userId, `${first} ${last}`.trim());
        this.names = updated;
      }).catch((): void => {});
    }
    this.names = names;
  }

  @Builder
  private panelBackdrop() {
    Column() {}
      .width('100%').height(this.panelH + 20)
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 16, topRight: 16 })
      .hitTestBehavior(HitTestMode.None);
  }

  build() {
    Column() {
      Column().width('100%').layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Block)
        .onClick((): void => { this.close(); });
      Column({ space: 10 }) {
        Column({ space: 10 }) {
          Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
          Row({ space: 6 }) {
            Text($r('app.string.cp_search_results')).fontSize(17).fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_PRIMARY);
            Text(searchCounterText(this.search.idx, this.search.total))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
        }
        .width('100%').padding({ top: 10 })
        .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 8 })
          .onActionUpdate((event: GestureEvent): void => { this.updateDrag(event.offsetY); })
          .onActionEnd((event: GestureEvent): void => { this.finishDrag(event.velocityY); })
          .onActionCancel((): void => { this.restoreDrag(); }));
        List({ scroller: this.scroller, space: 2 }) {
          Repeat<number>(this.search.results)
            .each((row: RepeatItem<number>) => {
              ListItem() {
                ChatSearchResultRow({ search: this.search, messageId: row.item, names: this.names,
                  onPick: (id: number): void => { this.close(id); } });
              }
            })
            .key((id: number): string => `${id}`)
            .virtualScroll();
          if (this.search.loading || this.search.canLoadMoreResults()) {
            ListItem() {
              Row() {
                if (this.search.loading) {
                  LoadingProgress().width(24).height(24).color(COLOR_PRIMARY);
                } else if (this.search.canLoadMoreResults()) {
                  Button(this.search.loadFailed ? $r('app.string.tap_to_retry') : $r('app.string.load_more'))
                    .fontColor(COLOR_PRIMARY).backgroundColor(Color.Transparent)
                    .onClick((): void => { this.search.loadMoreResults(); });
                }
              }.width('100%').height(44).justifyContent(FlexAlign.Center);
            }
          }
        }
        .width('100%').constraintSize({ maxHeight: 360 })
        .onAreaChange((_old: Area, area: Area): void => {
          if (!this.positioned && Number(area.height) > 0) {
            this.positioned = true;
            this.scroller.scrollToIndex(this.search.idx, false, ScrollAlign.CENTER);
          }
        })
        .onReachEnd((): void => {
          if (!this.search.loadFailed) { this.search.loadMoreResults(); }
        });
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 24 })
      .background(this.panelBackdrop(), { align: Alignment.TopStart })
      .borderRadius({ topLeft: 16, topRight: 16 })
      .translate({ y: this.shown ? this.dragY : this.panelH })
      .onAreaChange((_old: Area, area: Area): void => {
        const height = Number(area.height);
        if (height > 0 && Math.abs(height - this.panelH) > 0.5) { this.panelH = height; }
        this.enter();
      });
    }
    .width('100%').height('100%')
    .backgroundColor(this.shown ? '#66000000' : '#00000000');
  }
}

// A virtual row reads the current Repeat item through @Param, including after reuse.
@ComponentV2
struct ChatSearchResultRow {
  @Require @Param search: SearchSession;
  @Param messageId: number = 0;
  @Require @Param names: Map<number, string>;
  @Event onPick: (messageId: number) => void = (_messageId: number): void => {};
  private userId(messageId: number): number {
    const sender = this.search.resultMessages.get(messageId)?.['sender_id'] as TdObject | undefined;
    return (sender?.['user_id'] as number | undefined) ?? 0;
  }

  private senderName(): string {
    const userId = this.userId(this.messageId);
    if (userId > 0) { return this.names.get(userId) ?? '…'; }
    const sender = this.search.resultMessages.get(this.messageId)?.['sender_id'] as TdObject | undefined;
    const chatId = (sender?.['chat_id'] as number | undefined) ?? 0;
    return getChatStore().entryOf(chatId)?.title ?? '…';
  }

  private timeLabel(): string {
    const date = (this.search.resultMessages.get(this.messageId)?.['date'] as number | undefined) ?? 0;
    return date > 0 ? monthDayTime(new Date(date * 1000)) : '';
  }

  build() {
    Column({ space: 3 }) {
      Row({ space: 8 }) {
        Text(this.senderName()).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.timeLabel()).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        if (this.search.results[this.search.idx] === this.messageId) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([COLOR_PRIMARY]);
        }
      }.width('100%');
      SearchHitText({
        text: formatPreview(this.search.resultMessages.get(this.messageId) ?? null) || '…',
        query: this.search.keywords(), textSize: 14, lines: 2, color: COLOR_TEXT_PRIMARY
      });
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 8, top: 9, bottom: 9 })
    .borderRadius(10)
    .backgroundColor($r('app.color.surface_alt'))
    .onClick((): void => { this.onPick(this.messageId); });
  }

}
