import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { ChatListDataSource } from './ChatListDataSource';
import { guardKey } from '../../util/keyGuard';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { CHAT_LIST_FLUSH_EPOCH, CHAT_LIST_RENDER_ACTIVE_KEY } from '../../util/chatListRenderGate';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, KEY_ROW_SWIPE_ACTIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { SCOPE_MUTE_EPOCH } from '../../store/ScopeMuteStore';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { APPEARANCE_EPOCH } from '../../util/appearance';
import { TAB_RETAP_EPOCH, TAB_RETAP_INDEX, nextUnreadIndex, reTapAction } from '../../util/tabReTap';
import { markAsRead, markUnread, setArchived, setMute, MUTE_LONG } from '../../store/ChatActions';
import { effectiveMuted } from '../../store/ChatEntry';
import { scopeMutedForKind } from '../../store/ScopeMuteStore';

// 滑动操作的按钮宽度与触发距离（vp），以及三个动作的底色。
const SWIPE_BUTTON_VP: number = 76;
const SWIPE_TRIGGER_VP: number = 76;
const SWIPE_READ_BG: string = '#3390EC';
const SWIPE_MUTE_BG: string = '#8E8E93';
const SWIPE_ARCHIVE_BG: string = '#F09A37';

@Component
export struct ChatListView {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 行滑动操作的开关（交互设置）。关着时不挂 swipeAction，横向手势留给切文件夹。
  @StorageProp(KEY_ROW_SWIPE_ACTIONS) rowSwipeEnabled: boolean = false;
  // 底栏点「聊天」页签（已选中）时递增，见 util/tabReTap。
  @StorageProp(TAB_RETAP_EPOCH) @Watch('onTabReTap') tabReTapEpoch: number = 0;
  // 列表首行是否可见：决定这一下是回顶还是跳未读。
  private topVisible: boolean = true;
  private firstVisibleIndex: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  // 底栏点了已选中的「聊天」页签（issue #35）：不在顶就回顶，已经在顶就跳到
  // 下一个未读会话，绕一圈找不到就什么都不做。归档页等复用本组件的地方也生效，
  // 它们同样是聊天页签下的列表。
  private onTabReTap(): void {
    if ((AppStorage.get<number>(TAB_RETAP_INDEX) ?? 0) !== 0) {
      return;
    }
    const unread: boolean[] = this.chats.map((c: ChatEntry): boolean =>
      c.unreadCount > 0 || c.isMarkedUnread);
    const action: string = reTapAction(this.topVisible,
      unread.some((u: boolean): boolean => u));
    if (action === 'top') {
      this.listScroller.scrollToIndex(0, true, ScrollAlign.START);
      return;
    }
    if (action === 'none') {
      return;
    }
    const target: number = nextUnreadIndex(unread, this.firstVisibleIndex);
    if (target >= 0) {
      this.listScroller.scrollToIndex(target, true, ScrollAlign.START);
    }
  }

  private rowUnread(chat: ChatEntry): boolean {
    return chat.unreadCount > 0 || chat.isMarkedUnread;
  }

  private rowMuted(chat: ChatEntry): boolean {
    return effectiveMuted(chat, scopeMutedForKind(chat.kind));
  }

  private rowArchived(): boolean {
    return this.listKey === 'archive';
  }

  private toggleRead(chat: ChatEntry): void {
    if (this.rowUnread(chat)) {
      markAsRead(chat.id, chat.lastMessageId);
    } else {
      markUnread(chat.id, true);
    }
  }

  private toggleArchive(chat: ChatEntry): void {
    setArchived(chat.id, !this.rowArchived());
  }

  private toggleMute(chat: ChatEntry): void {
    setMute(chat.id, this.rowMuted(chat) ? 0 : MUTE_LONG);
  }

  // 右滑（从左边拉出）：已读 / 标记未读。
  @Builder
  readSwipe(chat: ChatEntry) {
    Row() {
      this.swipeButton(
        this.rowUnread(chat) ? $r('app.string.cl_mark_read') : $r('app.string.cl_mark_unread'),
        this.rowUnread(chat) ? 'sys.symbol.checkmark_circle' : 'sys.symbol.circle_badge',
        SWIPE_READ_BG,
        (): void => this.toggleRead(chat));
    }
    // ChatRow 是左右 12vp、上下 3vp 的真卡片；滑动动作也必须落在同一轮廓里，
    // 否则卡片滑走后会露出一块贴屏边的整行矩形。
    .height('calc(100% - 6vp)')
    .margin({ left: 12, top: 3, bottom: 3 })
    .borderRadius(16)
    .clip(true);
  }

  // 左滑（从右边拉出）：静音开关 + 归档 / 取消归档。滑到底触发的是归档那一个。
  @Builder
  endSwipe(chat: ChatEntry) {
    Row() {
      this.swipeButton(
        this.rowMuted(chat) ? $r('app.string.cp_unmute') : $r('app.string.cp_mute'),
        this.rowMuted(chat) ? 'sys.symbol.bell' : 'sys.symbol.bell_slash',
        SWIPE_MUTE_BG,
        (): void => this.toggleMute(chat));
      this.swipeButton(
        this.rowArchived() ? $r('app.string.cl_unarchive') : $r('app.string.cl_archive'),
        'sys.symbol.archivebox',
        SWIPE_ARCHIVE_BG,
        (): void => this.toggleArchive(chat));
    }
    .height('calc(100% - 6vp)')
    .margin({ right: 12, top: 3, bottom: 3 })
    .borderRadius(16)
    .clip(true);
  }

  @Builder
  swipeButton(label: ResourceStr, icon: string, background: ResourceColor, action: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph($r(icon)).fontSize(20).fontColor([Color.White]);
      Text(label).fontSize(11).fontColor(Color.White).maxLines(1);
    }
    .width(SWIPE_BUTTON_VP).height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(background)
    .onClick((): void => {
      this.listScroller.closeAllSwipeActions();
      action();
    });
  }

  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  @StorageProp(LANGUAGE_EPOCH) @Watch('onLanguageEpochChanged') langEpoch: number = 0;
  // 分类默认静音一改，每一行的铃铛和角标颜色都可能翻转（见 ChatRow.muted）。
  // 和 langEpoch 同一套办法：进 key 就是整表改名，@Watch 负责把重建踢起来。
  @StorageProp(SCOPE_MUTE_EPOCH) @Watch('onLanguageEpochChanged') scopeMuteEpoch: number = 0;
  @Prop listKey: string;
  // Folder tabs sit behind MainScreen's floating dock; ArchivePage does not.
  @Prop reserveDockSpace: boolean = true;
  // Floating frosted folder bar overlays the list top — start content below
  // it while still letting rows scroll (blurred) underneath.
  // 顶部悬浮 chrome（顶栏 + 文件夹条）的总高度。改成数值是因为顶栏也浮起来
  // 了：列表从它底下穿过去，才有玻璃透隐可看。原来是个布尔，只够表达"有没有
  // 文件夹条"。
  @Prop contentTopInset: number = 0;
  // 由 ChatListPage 传进来，每个文件夹页签一个。HdsNavigation 靠它拿到滚动量
  // 才能驱动标题栏收缩与渐变模糊；页签里的列表在子组件内部，父层拿不到，
  // 只能这样把控制器递下来。
  // ListScroller（不是 Scroller）：滑动操作要用 closeAllSwipeActions。
  listScroller: ListScroller = new ListScroller();
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  @StorageProp(CHAT_LIST_RENDER_ACTIVE_KEY) @Watch('onRenderGateChanged')
  private renderActive: boolean = true;
  @StorageProp(CHAT_LIST_FLUSH_EPOCH) @Watch('onFlushRequested')
  private flushEpoch: number = 0;
  @State chats: ChatEntry[] = [];
  @State loading: boolean = true;
  @State loadFailed: boolean = false;
  @State paging: boolean = false;
  @State pagingFailed: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  private chatsData: ChatListDataSource = new ChatListDataSource();
  private unsubscribe: (() => void) | null = null;
  private active: boolean = false;

  // 行 key 里带着 langEpoch。ForEach 时它一变就等于所有行改名、整表重建；
  // 换成 LazyForEach 之后没人会替我们做这件事，得显式告诉数据源。
  // 与 MainTabBody.onLanguageEpochChanged 同理。
  private onLanguageEpochChanged(): void {
    this.chatsData.reload();
  }

  @Styles
  actionNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  aboutToAppear(): void {
    this.active = true;
    const store = getChatStore();
    this.unsubscribe = store.subscribe((list: ChatEntry[]) => {
      const next = this.updateGate.accept(list, this.renderActive);
      if (next !== null) {
        this.applyChats(next);
      }
    }, this.listKey);
    this.loadInitial();
  }

  private loadInitial(): void {
    this.loading = true;
    this.loadFailed = false;
    const store = getChatStore();
    store.ensureLoaded(this.listKey).then((success: boolean): void => {
      if (!this.active) { return; }
      // TDLib normally emits the positions before resolving loadChats. Read
      // the bucket once here as well so the empty state can't flash while the
      // coalesced store notification is still waiting for the next frame.
    const next = this.updateGate.accept(store.getChats(this.listKey), this.renderActive);
      if (next !== null) { this.applyChats(next); }
      this.loading = false;
      this.loadFailed = !success;
    });
  }

  private applyChats(next: ChatEntry[]): void {
    const structureChanged = this.chats.length !== next.length ||
      this.chats.some((item: ChatEntry, index: number): boolean => item.id !== next[index]?.id);
    if (structureChanged && this.chats.length > 0) {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }, (): void => { this.publishChats(next); });
    } else {
      this.publishChats(next);
    }
  }

  // this.chats 仍然留着：空态判断和上面的 structureChanged 比较都要读它。
  // 真正驱动列表的是 chatsData。
  private publishChats(next: ChatEntry[]): void {
    this.chats = next;
    this.chatsData.update(next, next.map((item: ChatEntry): string => this.rowKey(item)));
  }

  // langEpoch in the key: see MainTabBody.rowKey.
  private rowKey(item: ChatEntry): string {
    const pinned = getChatStore().isPinned(this.listKey, item.id) ? 1 : 0;
    return `${item.id}_${item.revision}_${pinned}_${this.langEpoch}_${this.scopeMuteEpoch}`;
  }

  private loadMore(): void {
    const store = getChatStore();
    if (this.paging || store.isListExhausted(this.listKey)) {
      return;
    }
    this.paging = true;
    this.pagingFailed = false;
    store.loadMore(this.listKey).then((success: boolean): void => {
      if (!this.active) { return; }
      this.paging = false;
      this.pagingFailed = !success;
    });
  }

  private endInset(): number {
    return this.bottomSafe + (this.reserveDockSpace ? 88 : 16);
  }

  private flushBufferedChats(): void {
    if (this.menuOpen || !this.renderActive) {
      return;
    }
    const next = this.updateGate.flush();
    if (next !== null) {
      this.applyChats(next);
    }
  }

  private onMenuToggle(): void {
    this.flushBufferedChats();
  }

  private onRenderGateChanged(): void {
    this.flushBufferedChats();
  }

  // 闸还关着时的一次性刷新（issue #159，见 util/chatListRenderGate）：只发内容
  // 变更（身份顺序没变），顺序变了的放回缓冲等闸开。闸开着时走正常路。
  private onFlushRequested(): void {
    if (this.menuOpen || this.renderActive) {
      return;
    }
    const next = this.updateGate.flush();
    if (next === null) {
      return;
    }
    const sameOrder: boolean = this.chats.length === next.length &&
      this.chats.every((item: ChatEntry, index: number): boolean => item.id === next[index].id);
    if (sameOrder) {
      this.publishChats(next);
    } else {
      this.updateGate.accept(next, false);
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  @Builder
  emptyState() {
    Column({ space: 10 }) {
      if (this.loading) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 58, height: 58 }).fill($r('app.color.surface_alt'));
          LoadingProgress().width(28).height(28).color(this.accent());
        }
        Text(this.listKey === 'archive' ? $r('app.string.cl_syncing_archive') : $r('app.string.cl_loading_chats'))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cl_content_appears'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.loadFailed) {
        Row() {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(28).fontColor([this.accent()]);
        }
        .width(58).height(58).borderRadius(29)
        .backgroundColor($r('app.color.surface_alt'))
        .justifyContent(FlexAlign.Center);
        Text(this.listKey === 'archive' ? $r('app.string.cl_archive_failed') : $r('app.string.cl_chats_failed'))
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cl_check_network'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
          Text($r('app.string.settings_reload')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
        .height(38).padding({ left: 15, right: 16 }).borderRadius(19)
        .backgroundColor(this.accent())
        .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
        .onClick((): void => this.loadInitial());
      } else {
        Row() {
          SymbolGlyph(this.listKey === 'archive'
            ? $r('sys.symbol.archivebox') : $r('sys.symbol.message'))
            .fontSize(27).fontColor([COLOR_ICON_SECONDARY]);
        }
        .width(56).height(56).borderRadius(28)
        .backgroundColor($r('app.color.surface_alt'))
        .justifyContent(FlexAlign.Center);
        Text(this.listKey === 'archive' ? $r('app.string.cl_no_archived') : $r('app.string.cl_folder_empty'))
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        if (this.listKey === 'archive') {
          Text($r('app.string.cl_archive_hint'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        } else {
          Text($r('app.string.cl_add_hint'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
      }
    }
    .layoutWeight(1).width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: this.endInset() })
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  build() {
    if (this.chats.length === 0) {
      this.emptyState();
    } else {
      List({ scroller: this.listScroller }) {
        if (this.loadFailed) {
          ListItem() {
            Row({ space: 7 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(14).fontColor([this.accent()]);
              Text($r('app.string.cl_archive_sync_failed'))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
              Text($r('app.string.settings_retry')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.accent());
            }
            .height(40).padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.surface_alt'))
            .onClick((): void => this.loadInitial());
          }
        }
        // LazyForEach 而不是 ForEach：ForEach 会把每一行都提前建出来，
        // 归档和文件夹页签在会话多的账号上一样长（主列表 MainTabBody 早就
        // 迁过去了，:128 的注释记着当时实测 Ids.size[424]）。
        // 上面那个 .cachedCount(8) 配 ForEach 本来是空转的，现在才真正生效。
        LazyForEach(this.chatsData, (item: ChatEntry) => {
          ListItem() {
            ChatRow({ chat: item, listKey: this.listKey });
          }
          // 左右滑快捷操作（issue #96/#132）。动作都是聊天菜单里现成的那几个，
          // 不放删除：滑动误触的代价太大，删除留在长按菜单里。
          .swipeAction(this.rowSwipeEnabled ? {
            start: {
              builder: (): void => { this.readSwipe(item); },
              actionAreaDistance: SWIPE_TRIGGER_VP,
              onAction: (): void => { this.toggleRead(item); }
            },
            end: {
              builder: (): void => { this.endSwipe(item); },
              actionAreaDistance: SWIPE_TRIGGER_VP,
              onAction: (): void => { this.toggleArchive(item); }
            }
          } as SwipeActionOptions : {} as SwipeActionOptions)
          .transition(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 12 })).animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseOut
            })
          )
        }, (item: ChatEntry, index: number) =>
          guardKey(this.chatsData.keyTableId, index, this.rowKey(item)));
        if (this.paging) {
          ListItem() {
            Row() {
              LoadingProgress().width(22).height(22).color(this.accent());
            }.width('100%').height(44).justifyContent(FlexAlign.Center);
          }
        } else if (this.pagingFailed) {
          ListItem() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([this.accent()]);
              Text($r('app.string.load_more_failed')).fontSize(12).fontColor(this.accent());
            }
            .width('100%').height(44).justifyContent(FlexAlign.Center)
            .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
            .onClick((): void => this.loadMore());
          }
        }
      }
      .layoutWeight(1).width('100%')
      // Keep enough painted cache for the floating title blur without asking
      // every hidden/adjacent tab to prepare a full extra screen of ChatRows.
      .cachedCount(4, true)
      // cachedCount 的第二个参数 true 与这里的 clip(false) 是一对：前者让滚出
      // 视口的行不被回收，后者让它画得出来。官方《设置动态模糊样式》点名过——
      // 列表穿透到标题栏下方时缺了任一个，标题栏底下就是空的，渐变模糊没有
      // 东西可糊。
      .clip(false)
      .edgeEffect(EdgeEffect.Spring)
      // Stop touch scrolling as soon as the long-press menu begins to appear.
      // This prevents residual spring/inertia from shifting the source row
      // while ArkUI captures its floating preview.
      .enableScrollInteraction(!this.menuOpen)
      .scrollBar(BarState.Off)
      .contentEndOffset(this.endInset())
      .contentStartOffset(this.contentTopInset)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onReachEnd(() => { this.loadMore(); })
      // 首行是否可见：底栏再点一次「聊天」时据此决定回顶还是跳未读（issue #35）。
      .onScrollIndex((start: number): void => {
        this.firstVisibleIndex = start;
        this.topVisible = start <= 0;
      });
    }
  }
}
