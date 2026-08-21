import { promptAction, router } from '@kit.ArkUI';
import { getTdClient, getCallSession } from '../../tdkit/Globals';
import {
  CallItem, CallsLoadState, CallsMode, CallsPageState, CallsStore
} from '../../store/CallsStore';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { callClockLabel, callDayKey, callSectionLabel } from '../../util/CallHistoryPresentation';
import { AvatarView } from '../chatlist/AvatarView';
import {
  COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { plural, str } from '../../util/strings';
import { overlayBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { logE } from '../../util/log';

const CARD_RADIUS: number = 14;
const COLOR_MISSED: string = '#E64646';
const COLOR_WARNING: string = '#E68A00';
const COLOR_ANSWERED: string = '#28A878';
const SEGMENT_WIDTH: number = 196;
const SEGMENT_INSET: number = 3;
const SEGMENT_HEIGHT: number = 40;
const LONG_PRESS_MS: number = 500;

@Entry
@Component
struct CallsPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State calls: CallItem[] = [];
  @State mode: CallsMode = 'all';
  @State loadState: CallsLoadState = 'loading';
  @State pageState: CallsPageState = 'idle';
  @State refreshing: boolean = false;
  @State syncError: string = '';
  @State totalCount: number = 0;
  @State actionKey: string = '';
  @State nowSeconds: number = Math.floor(Date.now() / 1000);
  @State pressedKey: string = '';
  @State contextMenuShown: boolean = false;
  @State menuCallKey: string = '';
  private store: CallsStore | null = null;
  private unsubscribe: (() => void) | null = null;
  private clockTimer: number = -1;
  private pressActive: boolean = false;
  private pressConsumedByMenu: boolean = false;
  private pressKey: string = '';
  private pressIndex: number = -1;
  private pressVersion: string = '';
  private pendingCalls: CallItem[] | null = null;
  private menuCallSnapshot: CallItem | null = null;
  private active: boolean = false;
  private navigationLocked: boolean = false;
  private navigationTimer: number = -1;

  @Styles
  pressNormal() {
    .opacity(1).scale({ x: 1, y: 1 }).backgroundColor(Color.Transparent)
  }

  @Styles
  pressDown() {
    .opacity(0.7).scale({ x: 0.96, y: 0.96 }).backgroundColor($r('app.color.surface_alt'))
  }

  aboutToAppear(): void {
    this.active = true;
    this.navigationLocked = false;
    this.actionKey = '';
    const store = new CallsStore(getTdClient());
    this.store = store;
    this.unsubscribe = store.subscribe((): void => {
      if (this.contextMenuShown) { this.pendingCalls = store.calls.slice(); }
      else { this.calls = store.calls; }
      this.mode = store.mode;
      this.loadState = store.loadState;
      this.pageState = store.pageState;
      this.refreshing = store.refreshing;
      this.syncError = store.syncError;
      this.totalCount = store.totalCount;
    });
    store.open();
    this.clockTimer = setInterval((): void => {
      this.nowSeconds = Math.floor(Date.now() / 1000);
    }, 60000);
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
    if (this.clockTimer !== -1) { clearInterval(this.clockTimer); this.clockTimer = -1; }
    this.contextMenuShown = false;
    this.pendingCalls = null;
    this.menuCallSnapshot = null;
    if (this.navigationTimer !== -1) { clearTimeout(this.navigationTimer); this.navigationTimer = -1; }
  }

  private selectMode(mode: CallsMode): void {
    if (mode === this.mode || this.actionKey !== '') { return; }
    this.mode = mode;
    this.pressedKey = '';
    this.store?.setMode(mode);
  }

  private handleHorizontalSwipe(offsetX: number): void {
    if (Math.abs(offsetX) < 42) { return; }
    if (offsetX < 0 && this.mode === 'all') { this.selectMode('missed'); }
    else if (offsetX > 0 && this.mode === 'missed') { this.selectMode('all'); }
  }

  private openChat(call: CallItem): void {
    if (this.actionKey !== '' || this.navigationLocked || call.chatId === 0) { return; }
    this.navigationLocked = true;
    const params: Record<string, Object> = { 'chatId': call.chatId };
    navigateToChat(params).catch(logChatNavFailure);
    this.navigationTimer = setTimeout((): void => {
      this.navigationLocked = false;
      this.navigationTimer = -1;
    }, 800);
  }

  private refresh(): void {
    if (this.store === null) { this.refreshing = false; return; }
    this.store.refresh();
    if (!this.store.refreshing) { this.refreshing = false; }
  }

  private confirmClear(): void {
    if (this.calls.length === 0 || this.actionKey !== '' || this.store === null) { return; }
    promptAction.showDialog({
      title: $r('app.string.calls_clear_title'),
      message: $r('app.string.calls_clear_confirm'),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.clear_all'), color: COLOR_MISSED }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.store === null || this.actionKey !== '') { return; }
      this.actionKey = 'clear';
      this.store.clearAll().then((): void => {
        if (!this.active) { return; }
        this.actionKey = '';
        promptAction.showToast({ message: $r('app.string.calls_cleared'), duration: 1500 });
      }).catch((error: Error): void => {
        if (!this.active) { return; }
        this.actionKey = '';
        logE(`CallsPage.clearAll failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.calls_clear_failed'), duration: 1900 });
      });
    }).catch((): void => {});
  }

  private confirmDelete(call: CallItem): void {
    if (this.actionKey !== '' || this.store === null) { return; }
    promptAction.showDialog({
      title: $r('app.string.calls_delete_title'),
      message: str('calls_delete_confirm', call.name !== '' ? call.name : str('calls_this_contact')),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.delete'), color: COLOR_MISSED }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (!this.active || result.index !== 1 || this.store === null || this.actionKey !== '') { return; }
      this.actionKey = `delete_${call.key}`;
      this.store.deleteCall(call).then((): void => {
        if (!this.active) { return; }
        this.actionKey = '';
        promptAction.showToast({ message: $r('app.string.calls_deleted'), duration: 1400 });
      }).catch((error: Error): void => {
        if (!this.active) { return; }
        this.actionKey = '';
        logE(`CallsPage.deleteCall failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.calls_delete_failed'), duration: 1800 });
      });
    }).catch((): void => {});
  }

  private toneColor(call: CallItem): string | ResourceColor {
    if (call.tone === 'missed') { return COLOR_MISSED; }
    if (call.tone === 'warning') { return COLOR_WARNING; }
    if (call.tone === 'active') { return COLOR_PRIMARY; }
    return COLOR_ANSWERED;
  }

  private countLabel(): string {
    if (this.loadState === 'loading') { return str('syncing'); }
    if (this.totalCount > this.calls.length) { return plural('calls_about_count', this.totalCount, this.totalCount); }
    return plural('calls_count', this.calls.length, this.calls.length);
  }

  private isSectionStart(index: number): boolean {
    return index === 0 || callDayKey(this.calls[index - 1].date) !== callDayKey(this.calls[index].date);
  }

  private callVersion(call: CallItem): string {
    return [call.key, `${call.date}`, call.name, call.avatarPath, call.statusText,
      `${call.outgoing}`, `${call.missed}`, `${call.active}`].join('|');
  }

  private currentCallIndex(key: string): number {
    return this.calls.findIndex((call: CallItem): boolean => call.key === key);
  }

  private beginPress(call: CallItem): void {
    this.pressConsumedByMenu = false;
    this.pressActive = true;
    this.pressKey = call.key;
    this.pressIndex = this.currentCallIndex(call.key);
    this.pressVersion = this.callVersion(call);
    this.pressedKey = call.key;
  }

  private endPress(): void {
    this.pressActive = false;
    this.pressedKey = '';
  }

  private openMenuIfCurrent(call: CallItem): void {
    const index = this.currentCallIndex(call.key);
    const current = index >= 0 ? this.calls[index] : undefined;
    const unchanged = this.pressActive && this.pressKey === call.key && index === this.pressIndex
      && current !== undefined && this.callVersion(current) === this.pressVersion;
    this.pressActive = false;
    this.pressedKey = '';
    if (!unchanged) { return; }
    this.pressConsumedByMenu = true;
    this.menuCallKey = call.key;
    this.menuCallSnapshot = call;
    this.contextMenuShown = true;
  }

  private menuCall(): CallItem | undefined {
    return this.calls.find((call: CallItem): boolean => call.key === this.menuCallKey)
      ?? (this.menuCallSnapshot ?? undefined);
  }

  private closeContextMenu(): void {
    this.contextMenuShown = false;
    this.menuCallKey = '';
    this.pressActive = false;
    this.pressedKey = '';
    if (this.pendingCalls !== null) {
      this.calls = this.pendingCalls;
      this.pendingCalls = null;
    }
  }

  @Builder
  topMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.calls_refresh') }).enabled(!this.refreshing && this.actionKey === '')
        .onClick((): void => this.refresh());
      MenuItem({ content: $r('app.string.calls_clear_title') }).enabled(this.calls.length > 0 && this.actionKey === '')
        .onClick((): void => this.confirmClear());
    }
  }

  private redial(call: CallItem): void {
    // 私聊的 chatId 即对端 userId（TDLib 约定）；群组通话不走 1:1 回拨。
    if (call.isGroup || call.chatId <= 0) {
      return;
    }
    getCallSession().startCall(call.chatId, call.isVideo);
    router.pushUrl({ url: 'pages/call/CallPage' }).catch((error: Error): void => {
      logE(`CallsPage.redial failed: ${error.message}`);
    });
  }

  @Builder
  callContextMenu() {
    Menu() {
      if (!(this.menuCall()?.isGroup ?? true)) {
        MenuItem({ content: $r('app.string.calls_call_back') }).onClick((): void => {
          const call = this.menuCall();
          if (call !== undefined) { this.redial(call); }
        });
      }
      MenuItem({ content: $r('app.string.open_chat') }).onClick((): void => {
        const call = this.menuCall();
        if (call !== undefined) { this.openChat(call); }
      });
      MenuItem({ content: $r('app.string.calls_delete_this') }).onClick((): void => {
        const call = this.menuCall();
        if (call !== undefined) { this.confirmDelete(call); }
      });
    }
  }

  @Builder
  topBar() {
    Row({ space: 6 }) {
      Row() { SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(25).fontColor([COLOR_TEXT_PRIMARY]); }
        .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => router.back());
      Column({ space: 1 }) {
        Text($r('app.string.calls_title')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text(this.countLabel()).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      if (this.actionKey !== '' || this.refreshing) {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY).margin({ right: 13 });
      } else {
        Row() { SymbolGlyph($r('sys.symbol.more')).fontSize(23).fontColor([COLOR_TEXT_PRIMARY]); }
          .width(44).height(44).borderRadius(22).justifyContent(FlexAlign.Center)
          .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
          .bindMenu(this.topMenu(), { systemMaterial: overlayMaterial('menu') });
      }
    }.width('100%').height(56).padding({ left: 8, right: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  segmentItem(mode: CallsMode, title: ResourceStr) {
    Text(title).fontSize(14).fontWeight(this.mode === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.mode === mode ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
      .width((SEGMENT_WIDTH - SEGMENT_INSET * 2) / 2).height(SEGMENT_HEIGHT - SEGMENT_INSET * 2)
      .textAlign(TextAlign.Center)
      .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
      .onClick((): void => this.selectMode(mode));
  }

  @Builder
  segmentBar() {
    Row() {
      Stack({ alignContent: Alignment.TopStart }) {
        Row().width((SEGMENT_WIDTH - SEGMENT_INSET * 2) / 2).height(SEGMENT_HEIGHT - SEGMENT_INSET * 2)
          .borderRadius((SEGMENT_HEIGHT - SEGMENT_INSET * 2) / 2)
          .backgroundColor($r('app.color.surface'))
          .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
          .position({
            x: this.mode === 'all' ? SEGMENT_INSET : SEGMENT_WIDTH / 2,
            y: SEGMENT_INSET
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
            curve: Curve.EaseOut
          });
        Row() {
          this.segmentItem('all', $r('app.string.filter_all'));
          this.segmentItem('missed', $r('app.string.filter_missed'));
        }.width('100%').height('100%').padding(SEGMENT_INSET);
      }.width(SEGMENT_WIDTH).height(SEGMENT_HEIGHT)
        .backgroundColor($r('app.color.surface_alt')).borderRadius(SEGMENT_HEIGHT / 2);
    }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 2, bottom: 8 });
  }

  @Builder
  skeleton() {
    Column({ space: 9 }) {
      ForEach([0, 1, 2, 3, 4], (index: number) => {
        Row({ space: 12 }) {
          Circle({ width: 46, height: 46 }).fill($r('app.color.surface_alt'));
          Column({ space: 8 }) {
            Row().width(index % 2 === 0 ? '44%' : '58%').height(13).borderRadius(7)
              .backgroundColor($r('app.color.surface_alt'));
            Row().width(index % 2 === 0 ? '62%' : '48%').height(10).borderRadius(5)
              .backgroundColor($r('app.color.surface_alt'));
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        }.width('100%').height(66).padding({ left: 14, right: 14 })
          .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
      }, (index: number): string => `call_skeleton_${index}`);
    }.layoutWeight(1).width('100%').padding({ left: 12, right: 12, top: 4 });
  }

  @Builder
  errorState() {
    Column({ space: 12 }) {
      Text('📞').fontSize(44);
      Text($r('app.string.calls_load_failed')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.calls_load_failed_sub'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      Text($r('app.string.settings_reload')).fontSize(15).fontColor(Color.White).fontWeight(FontWeight.Medium)
        .padding({ left: 22, right: 22, top: 10, bottom: 10 })
        .backgroundColor(COLOR_PRIMARY).borderRadius(18)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => this.store?.retry());
    }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      .padding({ left: 28, right: 28, bottom: this.bottomSafe + 28 });
  }

  @Builder
  emptyState() {
    Column({ space: 9 }) {
      Text(this.mode === 'missed' ? '✓' : '📞').fontSize(44).fontColor(COLOR_PRIMARY);
      Text(this.mode === 'missed' ? $r('app.string.calls_no_missed') : $r('app.string.calls_empty'))
        .fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      Text(this.mode === 'missed' ? $r('app.string.calls_no_missed_sub') : $r('app.string.calls_empty_sub'))
        .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
      Text($r('app.string.calls_refresh_short')).fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium)
        .padding({ left: 18, right: 18, top: 9, bottom: 9 })
        .backgroundColor('#145B8FF9').borderRadius(17)
        .stateStyles({ normal: this.pressNormal, pressed: this.pressDown })
        .onClick((): void => this.refresh());
    }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center)
      .padding({ bottom: this.bottomSafe + 32 });
  }

  @Builder
  syncWarningBar() {
    if (this.syncError !== '') {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle')).fontSize(16).fontColor([COLOR_WARNING]);
        Text(this.syncError).fontSize(12).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
        Text($r('app.string.settings_retry')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
      }.width('100%').padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .margin({ left: 12, right: 12, bottom: 7 })
        .backgroundColor('#16E68A00').borderRadius(11)
        .onClick((): void => this.refresh())
        .transition(TransitionEffect.OPACITY.animation({ duration: 170, curve: Curve.EaseOut }));
    }
  }

  @Builder
  mediaBadge(call: CallItem) {
    Row() {
      SymbolGlyph($r(call.isVideo ? 'sys.symbol.video' : 'sys.symbol.phone'))
        .fontSize(13).fontColor([this.toneColor(call)]);
    }.width(25).height(25).borderRadius(9).justifyContent(FlexAlign.Center)
      .backgroundColor(call.tone === 'missed' ? '#14E64646' : '#1428A878');
  }

  @Builder
  callRow(call: CallItem) {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: call.avatarPath,
        initials: call.initials,
        colorSeed: call.colorSeed,
        avatarSize: 46
      });
      Column({ space: 5 }) {
        Row({ space: 7 }) {
          Text(call.name !== '' ? call.name : $r('app.string.opening_chat'))
            .fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(call.name !== '' ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          Text(callClockLabel(call.date)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        }.width('100%');
        Row({ space: 6 }) {
          this.mediaBadge(call);
          SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(13).fontColor([this.toneColor(call)])
            .rotate({ angle: call.outgoing ? 0 : 180 });
          Text(call.statusText).fontSize(12).fontColor(this.toneColor(call))
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          if (call.isGroup && call.participantCount > 0) {
            Text(plural('calls_participants', call.participantCount, call.participantCount)).fontSize(10).fontColor(COLOR_TEXT_SECONDARY);
          }
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
        }.width('100%').alignItems(VerticalAlign.Center);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').constraintSize({ minHeight: 68 })
    .padding({ left: 14, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.pressedKey === call.key ? $r('app.color.surface_alt') : COLOR_SURFACE)
    .borderRadius(CARD_RADIUS)
    .scale({ x: this.pressedKey === call.key ? 0.99 : 1, y: this.pressedKey === call.key ? 0.985 : 1 })
    .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
    .accessibilityText(`${call.name}，${call.statusText}，${callSectionLabel(call.date, this.nowSeconds)} ${callClockLabel(call.date)}`)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.beginPress(call); }
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.endPress(); }
    })
    .onClick((): void => {
      this.pressedKey = '';
      if (this.pressConsumedByMenu || this.contextMenuShown) {
        this.pressConsumedByMenu = false;
        return;
      }
      this.openChat(call);
    })
    .parallelGesture(
      LongPressGesture({ fingers: 1, repeat: false, duration: LONG_PRESS_MS })
        .onAction((): void => this.openMenuIfCurrent(call))
        .onActionCancel((): void => this.endPress())
    )
    .bindContextMenu(
      this.contextMenuShown && this.menuCallKey === call.key,
      this.callContextMenu,
      {
        preview: MenuPreviewMode.IMAGE,
        previewBorderRadius: CARD_RADIUS,
        previewAnimationOptions: {
          scale: [0.98, 1.03],
          transition: TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.FastOutSlowIn
            })
        },
        borderRadius: 16,
        backgroundColor: Color.Transparent,
        backgroundBlurStyle: overlayBlur('menu'),
        systemMaterial: overlayMaterial('menu'),
        mask: { color: '#52000000', backgroundBlurStyle: BlurStyle.BACKGROUND_THIN },
        modalMode: ModalMode.TARGET_WINDOW,
        hapticFeedbackMode: HapticFeedbackMode.AUTO,
        onDisappear: (): void => this.closeContextMenu()
      }
    );
  }

  @Builder
  callList() {
    List({ space: 7 }) {
      ForEach(this.calls, (call: CallItem, index: number) => {
        ListItem() {
          Column({ space: 6 }) {
            if (this.isSectionStart(index)) {
              Text(callSectionLabel(call.date, this.nowSeconds))
                .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_SECONDARY)
                .width('100%').padding({ left: 5, top: index === 0 ? 1 : 8, bottom: 1 });
            }
            this.callRow(call);
          }.width('100%');
        }.transition(
          TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -6 }))
            .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180), curve: Curve.EaseOut })
        );
      }, (call: CallItem): string => call.key);
      ListItem() {
        if (this.pageState === 'loading') {
          Row() { LoadingProgress().width(21).height(21).color(COLOR_PRIMARY); }
            .width('100%').justifyContent(FlexAlign.Center).padding({ top: 12, bottom: 12 });
        } else if (this.pageState === 'error') {
          Row({ space: 7 }) {
            Text($r('app.string.calls_load_more_failed')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            Text($r('app.string.settings_retry')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
          }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 12, bottom: 12 })
            .onClick((): void => this.store?.retry());
        } else if (this.pageState === 'end' && this.calls.length >= 20) {
          Text($r('app.string.calls_all_shown')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').textAlign(TextAlign.Center).padding({ top: 11, bottom: 11 });
        }
      }
    }
    .layoutWeight(1).width('100%').cachedCount(8)
    .padding({ left: 12, right: 12 })
    .contentEndOffset(this.bottomSafe + 18)
    .edgeEffect(EdgeEffect.Spring).scrollBar(BarState.Off)
    .onReachEnd((): void => this.store?.loadMore());
  }

  @Builder
  readyContent() {
    Column() {
      this.syncWarningBar();
      Refresh({ refreshing: $$this.refreshing }) {
        this.callList();
      }.layoutWeight(1).width('100%').onRefreshing((): void => this.refresh());
    }.layoutWeight(1).width('100%');
  }

  @Builder
  body() {
    Column() {
      if (this.loadState === 'loading') { this.skeleton(); }
      else if (this.loadState === 'error') { this.errorState(); }
      else if (this.loadState === 'empty') {
        Column() {
          this.syncWarningBar();
          Refresh({ refreshing: $$this.refreshing }) {
            this.emptyState();
          }.layoutWeight(1).width('100%').onRefreshing((): void => this.refresh());
        }.layoutWeight(1).width('100%');
      } else { this.readyContent(); }
    }.layoutWeight(1).width('100%')
      .parallelGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent): void => this.handleHorizontalSwipe(event.offsetX))
      );
  }

  build() {
    Column() {
      this.topBar();
      this.segmentBar();
      this.body();
    }.width('100%').height('100%').backgroundColor(COLOR_PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .padding({ top: this.topSafe });
  }
}
