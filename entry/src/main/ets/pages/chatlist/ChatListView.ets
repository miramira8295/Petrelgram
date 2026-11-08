import { ChatListRowState, ChatRowFlags } from './ChatListRowState';
import { FOLDER_TAGS_ENABLED, FolderInfo } from '../../store/FolderStore';
import { ChatListSubscription } from '../../store/ChatListSubscription';
import { homeCardMarginVp } from '../../util/pageMargin';
import {
  HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WINDOW_PORTRAIT, KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM, isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { getChatStore, getFolderStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { KEY_FORCE_SINGLE_COLUMN } from '../../store/AppSettings';
import { ChatListDataSource } from './ChatListDataSource';
import { ChatListRowKeyCache } from './chatListRowKeys';
import { guardKey } from '../../util/keyGuard';
import { CHAT_LIST_TOUCH_HOLD, CHAT_MENU_OPEN, chatListInForeground, chatListPublicationMode, ChatListFreeze, chatOrderUnchanged, chatRevisionsUnchanged, contentOnlyUpdate, updateTouchHold } from './ChatListFreeze';
import { CHAT_LIST_FLUSH_EPOCH, CHAT_LIST_RENDER_ACTIVE_KEY } from '../../util/chatListRenderGate';
import { rememberListPosition, recallListPosition } from '../../util/chatListPosition';
import { BLUR_MAX_VP, EDGE_OVERLAY_VP, edgeBlurStops } from '../../util/scrollEdgeBlur';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, KEY_ROW_SWIPE_ACTIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { SCOPE_MUTE_EPOCH } from '../../store/ScopeMuteStore';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { APPEARANCE_EPOCH } from '../../util/appearance';
import {
  isPriorityUnread, TAB_RETAP_EPOCH, TAB_RETAP_INDEX, nextUnreadIndex, reTapAction,
  RETAP_SMOOTH_SPAN, smoothJumpStage
} from '../../util/tabReTap';
import { markAsRead, markUnread, setArchived, setMute, MUTE_LONG } from '../../store/ChatActions';
import { effectiveMuted } from '../../store/ChatEntry';
import { scopeMutedForKind } from '../../store/ScopeMuteStore';
import {
  CHAT_SWIPE_ACTION_HEIGHT, CHAT_SWIPE_BUTTON_VP, CHAT_SWIPE_COMMIT_DELAY_MS, CHAT_SWIPE_EDGE_EFFECT,
  CHAT_SWIPE_RADIUS_VP, CHAT_SWIPE_TRIGGER_VP, CHAT_SWIPE_VERTICAL_GUTTER_VP,
  ChatSwipeActionVisual,
  archiveSwipeVisual, muteSwipeVisual, readSwipeVisual
} from '../../util/chatListSwipe';

const EMPTY_FOLDER_IDS: number[] = [];
const FLUSH_BYPASS_DEFER_MS: number = 32;

@Component
export struct ChatListView {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 会话行档位，判据与 MainTabBody 一致（见 util/chatRowMetrics）。
  @StorageProp('screenWidthVp') private screenW: number = 360;
  @StorageProp('screenHeightVp') private screenH: number = 780;
  // 系统断点（util/layoutBreakpoint）：分栏判据读它，不再按窗口宽高自己算。
  @StorageProp(KEY_WIDTH_BREAKPOINT) widthBp: number = WIDTH_BP_SM;
  @StorageProp(KEY_HEIGHT_BREAKPOINT) heightBp: number = HEIGHT_BP_LG;
  @StorageProp(KEY_WINDOW_PORTRAIT) windowPortrait: boolean = true;
  @StorageProp(KEY_FORCE_SINGLE_COLUMN) private forceSingleColumn: boolean = false;
  // 行滑动操作的开关（交互设置）。关着时不挂 swipeAction，横向手势留给切文件夹。
  @StorageProp(KEY_ROW_SWIPE_ACTIONS) rowSwipeEnabled: boolean = false;
  @Prop effectsActive: boolean = true;
  @Prop imagesActive: boolean = true;
  @Prop @Watch('onUpdatesActiveChanged') updatesActive: boolean = true;
  // 底栏点「聊天」页签（已选中）时递增，见 util/tabReTap。
  @StorageProp(TAB_RETAP_EPOCH) @Watch('onTabReTap') tabReTapEpoch: number = 0;
  // 列表首行是否可见：没有未静音未读时，决定是否需要回顶。
  private topVisible: boolean = true;
  private firstVisibleIndex: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  // 底栏点了已选中的「聊天」页签（issue #35）：优先跳到下一个未静音未读；
  // 没有这种会话才回顶。归档页等复用本组件的地方也生效。
  private onTabReTap(): void {
    if ((AppStorage.get<number>(TAB_RETAP_INDEX) ?? 0) !== 0) {
      return;
    }
    const unread: boolean[] = this.chats.map((c: ChatEntry): boolean =>
      isPriorityUnread(c.unreadCount, c.isMarkedUnread, this.rowMuted(c)));
    const action: string = reTapAction(this.topVisible,
      unread.some((u: boolean): boolean => u));
    if (action === 'top') {
      this.jumpToRow(0);
      return;
    }
    if (action === 'none') {
      return;
    }
    const target: number = nextUnreadIndex(unread, this.firstVisibleIndex);
    this.jumpToRow(target >= 0 ? target : 0);
  }

  // 远距离先无动画跳到目标近旁再平滑（见 util/tabReTap.smoothJumpStage：
  // 平滑滚动逐行构建沿途内容，实测跳 169 行 = 单帧 618ms）。
  private jumpToRow(index: number): void {
    const stage = smoothJumpStage(this.firstVisibleIndex, index, RETAP_SMOOTH_SPAN);
    if (stage >= 0) {
      this.listScroller.scrollToIndex(stage, false, ScrollAlign.START);
    }
    this.listScroller.scrollToIndex(index, true, ScrollAlign.START);
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

  private commitSwipeAction(action: () => void): void {
    setTimeout((): void => {
      action();
      this.listScroller.closeAllSwipeActions();
    }, CHAT_SWIPE_COMMIT_DELAY_MS);
  }

  // 右滑（从左边拉出）：已读 / 标记未读。
  @Builder
  readSwipe(row: ChatListRowState) {
    Row() {
      this.swipeButton(
        this.rowUnread(row.snapshot.chat) ? $r('app.string.cl_mark_read') : $r('app.string.cl_mark_unread'),
        readSwipeVisual(this.rowUnread(row.snapshot.chat)),
        (): void => this.toggleRead(row.snapshot.chat));
    }
    // ChatRow 是左右 12vp、上下 3vp 的真卡片；滑动动作也必须落在同一轮廓里，
    // 否则卡片滑走后会露出一块贴屏边的整行矩形。
    .height(CHAT_SWIPE_ACTION_HEIGHT)
    .margin({
      left: this.cardGutter(),
      top: CHAT_SWIPE_VERTICAL_GUTTER_VP,
      bottom: CHAT_SWIPE_VERTICAL_GUTTER_VP
    })
    // ACTIONING 会强制扩宽 builder 顶层；底色和圆角必须在同一节点。
    .backgroundColor(readSwipeVisual(this.rowUnread(row.snapshot.chat)).background)
    .borderRadius(CHAT_SWIPE_RADIUS_VP)
    .clip(true);
  }

  // 左滑（从右边拉出）：展示静音开关 + 归档 / 取消归档，点击相应按钮执行。
  @Builder
  endSwipe(row: ChatListRowState) {
    Row() {
      this.swipeButton(
        this.rowMuted(row.snapshot.chat) ? $r('app.string.cp_unmute') : $r('app.string.cp_mute'),
        muteSwipeVisual(this.rowMuted(row.snapshot.chat)),
        (): void => this.toggleMute(row.snapshot.chat));
      this.swipeButton(
        this.rowArchived() ? $r('app.string.cl_unarchive') : $r('app.string.cl_archive'),
        archiveSwipeVisual(this.rowArchived()),
        (): void => this.toggleArchive(row.snapshot.chat));
    }
    .height(CHAT_SWIPE_ACTION_HEIGHT)
    .margin({
      right: this.cardGutter(),
      top: CHAT_SWIPE_VERTICAL_GUTTER_VP,
      bottom: CHAT_SWIPE_VERTICAL_GUTTER_VP
    })
    // 长滑的主动作是最外侧归档，因此扩出的整块区域使用归档色。
    .backgroundColor(archiveSwipeVisual(this.rowArchived()).background)
    .borderRadius(CHAT_SWIPE_RADIUS_VP)
    .clip(true);
  }

  @Builder
  swipeButton(label: ResourceStr, visual: ChatSwipeActionVisual, action: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph($r(visual.symbol)).fontSize(20).fontColor([Color.White]);
      Text(label)
        .width('100%')
        .fontSize(11).fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width(CHAT_SWIPE_BUTTON_VP).height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(visual.background)
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
  // 每帧滚动量往上抱给 ChatListPage，文件夹条据此收起/展开（util/folderBarCollapse）。
  // **普通成员，不能用 @Prop**：@Prop 跨组件边界是深拷贝，函数会被丢掉，症状是
  // 回调永远不触发而编译、单测都看不出来（见 memory arkui-prop-deepcopy-drops-closures）。
  // 没接线时整条路径零开销——守卫在 reportFolderBarScroll 里，连 currentOffset() 都不取。
  onScrollForFolderBar?: (delta: number, atTop: boolean) => void;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  // 手指按在列表上时同样缓冲发布（长按跑行的根修，见 ChatListFreeze）。
  @StorageProp(CHAT_LIST_TOUCH_HOLD) @Watch('onTouchHoldToggle') touchHold: boolean = false;
  @StorageProp(CHAT_LIST_RENDER_ACTIVE_KEY) @Watch('onRenderGateChanged')
  private renderActive: boolean = true;
  // 本列表跟不跟**全局**那道发布闸（CHAT_LIST_RENDER_ACTIVE_KEY）。
  //
  // 那道闸是给**首页导航栏底下那几份列表**用的：手机上导航栏在
  // HdsNavDestination 底下一直挂着，navigateToChat 关闸，等导航栏重新露出来时
  // ChatListPage.applyNavBarVisible(true) 再开。
  //
  // 归档页是**独立的 destination**，这套时序对它是错的：从首页推开归档页时导航栏
  // 就已经隐藏、闸被关上，之后进出会话导航栏自始至终盖着，
  // applyNavBarVisible(true) 一次都不会来 ⇒ **闸永远开不回来**。归档列表因此停在
  // 打开那一刻的快照上：进去看完消息退回来，未读角标还挂着，怎么点都不消
  //（2026-09-18 用户实报）。初次那份能出来只是因为 forceInitial 绕过了闸。
  //
  // 所以这类页面传 false，改由页面自己的 onShown/onHidden 驱动 pageVisible。
  @Prop obeyGlobalGate: boolean = true;
  // 分组标签开关：关着就不必为每行算分组归属（第二层 B3）。
  @StorageProp(FOLDER_TAGS_ENABLED) folderTagsEnabled: boolean = false;
  // 承载本列表的页面在不在眼前。obeyGlobalGate 为 false 时才用得上。
  @Prop @Watch('onPageVisibleChanged') pageVisible: boolean = true;
  @StorageProp(CHAT_LIST_FLUSH_EPOCH) @Watch('onFlushRequested')
  private flushEpoch: number = 0;
  // Store publishes immutable snapshots. Keep the full array out of ArkUI's
  // observed state; LazyForEach receives changes through chatsData.
  private chats: ChatEntry[] = [];
  // 列表实测高度（vp）：linearGradientBlur 的 fractionStops 按实际高度归一化。
  @State private listViewH: number = 0;
  @State private chatsEmpty: boolean = true;
  @State loading: boolean = true;
  @State loadFailed: boolean = false;
  @State paging: boolean = false;
  @State pagingFailed: boolean = false;
  @StorageProp('appIsForeground') @Watch('onForegroundChanged')
  private appIsForeground: boolean = true;
  private rowReloadPending: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  // 返回转场那扇窗是否开着（issue #159）。由 onFlushRequested 开、闸开时关。
  private flushBypass: boolean = false;
  private chatsData: ChatListDataSource = new ChatListDataSource();
  private rowKeyCache: ChatListRowKeyCache = new ChatListRowKeyCache();
  private listSubscription: ChatListSubscription | null = null;
  private active: boolean = false;
  // 纯发布闸，不参与绘制：滚动期间只缓存最新会话快照，停下后一次性发布。
  private listMoving: boolean = false;
  private scrollSettleTimer: number = -1;
  private flushBypassTimer: number = -1;

  // 文件夹条的收起/展开只关心"这一帧滚了多少"和"是不是已经在顶上"，两样都在
  // 这一个回调里拿得到。先判空再取 currentOffset()：这个回调每帧都跑，没接线
  // 的页签（归档页等）不该为它多付一次取值。
  private reportFolderBarScroll(delta: number): void {
    const report: ((delta: number, atTop: boolean) => void) | undefined = this.onScrollForFolderBar;
    if (report !== undefined) {
      report(delta, this.listScroller.currentOffset().yOffset <= 0);
    }
  }

  private updateScrollActivity(state: ScrollState): void {
    if (state !== ScrollState.Idle) {
      if (this.scrollSettleTimer !== -1) {
        clearTimeout(this.scrollSettleTimer);
        this.scrollSettleTimer = -1;
      }
      this.listMoving = true;
      this.listSubscription?.refresh();
      return;
    }
    if (!this.listMoving || this.scrollSettleTimer !== -1) {
      return;
    }
    this.scrollSettleTimer = setTimeout((): void => {
      this.scrollSettleTimer = -1;
      this.listMoving = false;
      this.listSubscription?.refresh();
      if (this.flushBypass && !this.renderActive) {
        this.drainContentOnly();
      } else {
        this.flushBufferedChats();
      }
    }, 120);
  }

  private liveEffects(): boolean {
    // 滚动薄纱降级暂时停用；listMoving 现在只冻结数据发布。
    return this.effectsActive;
  }

  // 这一份列表的发布闸：跟全局的，还是跟承载页面自己的可见性。见 obeyGlobalGate。
  private gateOpen(): boolean {
    return this.obeyGlobalGate ? this.renderActive : this.pageVisible;
  }

  private publishingActive(): boolean {
    return chatListInForeground() && this.gateOpen() && this.updatesActive && !this.listMoving;
  }

  private onUpdatesActiveChanged(): void {
    this.flushBufferedChats();
  }

  // 行 key 里带着 langEpoch。ForEach 时它一变就等于所有行改名、整表重建；
  // 换成 LazyForEach 之后没人会替我们做这件事，得显式告诉数据源。
  // 与 MainTabBody.onLanguageEpochChanged 同理。
  private onLanguageEpochChanged(): void {
    if (!chatListInForeground()) {
      this.rowReloadPending = true;
      return;
    }
    this.rowReloadPending = false;
    this.chatsData.reload(this.keysFor(this.chats), this.flagsFor(this.chats));
  }

  private onForegroundChanged(): void {
    if (!chatListInForeground()) {
      this.flushBypass = false;
      this.listSubscription?.refresh();
      return;
    }
    this.flushBufferedChats();
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
    this.listSubscription = store.subscribeList((list: ChatEntry[]) => {
      // A preloaded hidden tab needs one complete initial snapshot before it
      // becomes static. It may be constructed while the global finger-down
      // gate is closed, so the first non-empty snapshot explicitly bypasses
      // that gate; all later updates remain frozen as before.
      const forceInitial: boolean = this.chats.length === 0 && list.length > 0;
      const next = this.updateGate.accept(list,
        this.publishingActive() || this.loading, forceInitial);
      if (next !== null) {
        this.applyChats(next);
      } else if (this.updatesActive && this.flushBypass && !this.menuOpen && !this.touchHold &&
        !this.listMoving) {
        // 转场窗口里到货的内容变更：accept 已经把它收进缓冲了，这里立刻取出来发。
        this.drainContentOnly();
      }
    }, this.listKey, () => chatListPublicationMode(this.updatesActive, this.gateOpen(),
      this.listMoving, this.flushBypass, this.chats.length === 0 && store.hasChats(this.listKey)));
    this.loadInitial();
  }

  private loadInitial(): void {
    this.loading = true;
    this.loadFailed = false;
    const store = getChatStore();
    store.ensureLoaded(this.listKey).then((success: boolean): void => {
      if (!this.active) { return; }
      // Read once after loading, but only when the view can use the snapshot.
      this.listSubscription?.refresh(true);
      this.loading = false;
      this.loadFailed = !success;
    });
  }

  private applyChats(next: ChatEntry[]): void {
    if (!chatListInForeground()) {
      this.updateGate.accept(next, false);
      return;
    }
    const structureChanged: boolean = !chatOrderUnchanged(this.chats, next);
    if (structureChanged && this.chats.length > 0) {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }, (): void => { this.publishChats(next); });
    } else {
      this.publishChats(next);
    }
  }

  // Only the empty/non-empty boundary needs parent state; row changes use the data source.
  private publishChats(next: ChatEntry[]): void {
    this.chats = next;
    this.chatsData.update(next, this.keysFor(next), this.flagsFor(next));
    this.chatsEmpty = next.length === 0;
  }

  // 第二层 B3：行渲染要的置顶/归档/分组归属，发布时算好随快照下发。
  // 行组件因此不再在 build 里查 store（那是 store 搬进 worker 的硬阻塞）。
  private flagsFor(items: ChatEntry[]): ChatRowFlags[] {
    const store = getChatStore();
    const listKey: string = this.listKey;
    const folderIds: number[] = this.folderTagsEnabled
      ? getFolderStore().getFolders().map((f: FolderInfo): number => f.id) : EMPTY_FOLDER_IDS;
    const chatIds: number[] = items.map((item: ChatEntry): number => item.id);
    const memberships: Map<number, number[]> = store.folderIdsForChats(folderIds, chatIds);
    const flags: ChatRowFlags[] = [];
    for (const item of items) {
      const inFolders: number[] = memberships.get(item.id) ?? EMPTY_FOLDER_IDS;
      flags.push({
        pinned: store.isPinned(listKey, item.id),
        archived: store.isArchived(item.id),
        folderIds: inFolders
      });
    }
    return flags;
  }

  private keysFor(items: ChatEntry[]): string[] {
    // Snapshot reactive key context once per publication, not once per row.
    const languageEpoch: number = this.langEpoch;
    const muteEpoch: number = this.scopeMuteEpoch;
    const listKey: string = this.listKey;
    const store = getChatStore();
    return this.rowKeyCache.keys(items, listKey, languageEpoch, muteEpoch, store.pinEpoch(listKey),
      (id: number): boolean => store.isPinned(listKey, id));
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
    // dock 恒在底部（手机的 HdsTabs 胶囊 / 平板分栏左栏底部的自绘胶囊），侧边竖排已删。
    return this.bottomSafe + (this.reserveDockSpace ? 88 : 16);
  }

  private flushBufferedChats(): void {
    this.listSubscription?.refresh();
    if (!chatListInForeground() || this.menuOpen || this.touchHold || this.listMoving || !this.gateOpen() || !this.updatesActive) {
      return;
    }
    const next = this.updateGate.flush();
    if (next !== null) {
      this.applyChats(next);
    }
    if (this.rowReloadPending) { this.onLanguageEpochChanged(); }
  }

  private onMenuToggle(): void {
    this.flushBufferedChats();
  }

  private onTouchHoldToggle(): void {
    this.flushBufferedChats();
  }

  private onRenderGateChanged(): void {
    // 闸开了就关窗：往后走正常路（含重排动画），不再需要旁路。
    if (this.gateOpen()) {
      if (this.flushBypassTimer !== -1) {
        clearTimeout(this.flushBypassTimer);
        this.flushBypassTimer = -1;
      }
      this.flushBypass = false;
    }
    this.flushBufferedChats();
  }

  // 承载页面重新露出来（归档页从会话退回来）：和开闸走同一条路。
  private onPageVisibleChanged(): void {
    this.onRenderGateChanged();
  }

  // 闸还关着时的旁路（issue #159，见 util/chatListRenderGate）：只发内容变更
  // （身份顺序没变），顺序变了的放回缓冲等闸开。闸开着时走正常路。
  //
  // 【为什么是"一段窗口"而不是"一次刷新"】第一版只在纪元 bump 的那一刻刷一次。
  // 但返回转场有 ~640ms，而群未读清零真正到账靠的是 TDLib 回来的
  // updateChatReadInbox——它多半**晚于**那一下 bump。那份快照被 accept 收进
  // 缓冲，照旧要等闸开才出来，"慢半拍"于是只修掉了运气好的一半。
  // 所以 bump 改成开一扇窗：窗开着的期间内容变更随到随发，闸开时关窗。
  private onFlushRequested(): void {
    if (!this.obeyGlobalGate || !chatListInForeground() || this.menuOpen || this.gateOpen()) {
      return;
    }
    this.flushBypass = true;
    if (!this.updatesActive) {
      return;
    }
    if (AppStorage.get<boolean>('chatDetailHiding') === true) {
      if (this.flushBypassTimer !== -1) {
        clearTimeout(this.flushBypassTimer);
      }
      this.flushBypassTimer = setTimeout((): void => {
        this.flushBypassTimer = -1;
        if (!this.obeyGlobalGate || !chatListInForeground() || this.menuOpen || this.gateOpen() || !this.flushBypass) {
          return;
        }
        this.listSubscription?.refresh();
        if (!this.listMoving) {
          this.drainContentOnly();
        }
      }, FLUSH_BYPASS_DEFER_MS);
      return;
    }
    this.listSubscription?.refresh();
    if (!this.listMoving) {
      this.drainContentOnly();
    }
  }

  // 把缓冲里那份快照发出去，但只发内容变更。
  //
  // 顺序变了时**不再整份扣住**：先把新内容贴到当前顺序上发出去（角标就在内容
  // 里，用户等的就是它），再把原快照放回缓冲，等闸开了做真正的重排——那一下
  // 要带 180ms 动画，"别在转场里重排"正是这道闸存在的理由。
  //
  // 拆开之前，只要退出会话这期间**任何一个别的会话**来了条新消息，列表顺序
  // 就变了，你刚读完那个群的角标也跟着一起等 640ms。用户报的"有时候快有时候
  // 要等一会"就是这个分岔。
  private drainContentOnly(): void {
    if (!chatListInForeground() || this.menuOpen || this.touchHold ||
      this.listMoving || !this.updatesActive) { return; }
    const next = this.updateGate.flush();
    if (next === null) {
      return;
    }
    if (chatOrderUnchanged(this.chats, next)) {
      if (!chatRevisionsUnchanged(this.chats, next)) {
        this.publishChats(next);
      }
      return;
    }
    const merged: ChatEntry[] | null = contentOnlyUpdate(this.chats, next);
    if (merged !== null) {
      this.publishChats(merged);
    }
    this.updateGate.accept(next, false);
  }

  aboutToDisappear(): void {
    this.rowKeyCache.clear();
    this.active = false;
    if (this.scrollSettleTimer !== -1) {
      clearTimeout(this.scrollSettleTimer);
      this.scrollSettleTimer = -1;
    }
    if (this.flushBypassTimer !== -1) {
      clearTimeout(this.flushBypassTimer);
      this.flushBypassTimer = -1;
    }
    this.listMoving = false;
    this.listSubscription?.close();
    this.listSubscription = null;
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

  // 首页会话卡片外沿（util/pageMargin）：手机 6，折叠屏 10，平板 14。
  private cardGutter(): number {
    return homeCardMarginVp(this.widthBp);
  }

  build() {
    if (this.chatsEmpty) {
      this.emptyState();
    } else {
      // 外面套一层 Stack：linearGradientBlur 是**容器级**属性，挂在这层容器上，
      // 让整棵列表（含溢出到标题栏底下的那一截）一起参与边缘渐变虚化。
      // 之前挂在 List 上时 22 与 60 两版截图一模一样——不是属性无效，是挂错了对象。
      Stack() {
      // initialIndex：本页签若曾被 Tabs.cachedMaxCount 释放过，重建时回到
      // 原来的行（归档页不参与，见 util/chatListPosition）。
      List({
        scroller: this.listScroller,
        initialIndex: this.listKey === 'archive' ? 0 : recallListPosition(this.listKey)
      }) {
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
        LazyForEach(this.chatsData, (item: ChatListRowState) => {
          ListItem() {
            ChatRow({
              compact: !isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait),
              row: item,
              listKey: this.listKey,
              liveEffects: this.liveEffects(),
              loadImages: this.imagesActive
            });
          }
          // 左右滑快捷操作（issue #96/#132）。动作都是聊天菜单里现成的那几个，
          // 不放删除：滑动误触的代价太大，删除留在长按菜单里。
          .swipeAction(this.rowSwipeEnabled ? {
            start: {
              builder: (): void => { this.readSwipe(item); },
              actionAreaDistance: CHAT_SWIPE_TRIGGER_VP,
              onAction: (): void => {
                this.commitSwipeAction((): void => this.toggleRead(item.snapshot.chat));
              }
            },
            end: {
              builder: (): void => { this.endSwipe(item); },
              actionAreaDistance: CHAT_SWIPE_TRIGGER_VP,
              onAction: (): void => {
                this.commitSwipeAction((): void => this.toggleArchive(item.snapshot.chat));
              }
            },
            edgeEffect: CHAT_SWIPE_EDGE_EFFECT
          } as SwipeActionOptions : {} as SwipeActionOptions)
          .transition(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 12 })).animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseOut
            })
          )
        }, (_item: ChatListRowState, index: number) =>
          guardKey(this.chatsData.keyTableId, index, this.chatsData.getKey(index)));
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
      .width('100%').height('100%')
      // Keep enough painted cache for the floating title blur without asking
      // every hidden/adjacent tab to prepare a full extra screen of ChatRows.
      .cachedCount(2, true)
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
      // 容器上顶了 EDGE_OVERLAY_VP，内容起点跟着上移，这里补回来，首行才不会被切。
      // 上顶量随「状态栏 + 标题栏 + 文件夹条」实时变：文件夹条展开时列表区整体下移，
      // 这里不减掉那截，拉开的那条带就没有虚化（下拉出现文件夹时最明显）。
      .contentStartOffset(EDGE_OVERLAY_VP + this.contentTopInset)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onDidScroll((offset: number, state: ScrollState): void => {
        this.updateScrollActivity(state);
        this.reportFolderBarScroll(offset);
      })
      // 指尖按下就关发布闸（抬手/被抢手势即开）：长按窗口里来更新不再挪行，
      // 重排动画顺延到抬手后。数据订阅照常流动。
      .onTouch((event: TouchEvent): void => { updateTouchHold(event.type); })
      .onReachEnd(() => { this.loadMore(); })
      // 首行是否可见：没有未静音未读时，据此决定是否需要回顶（issue #35）。
      .onScrollIndex((start: number): void => {
        this.firstVisibleIndex = start;
        this.topVisible = start <= 0;
        if (this.listKey !== 'archive') {
          rememberListPosition(this.listKey, start);
        }
      })
      }
      .layoutWeight(1).width('100%')
      // 上顶 EDGE_OVERLAY_VP（标题栏 56 + 状态栏 39），让渐变原点回到屏幕最上沿。
      .margin({ top: -EDGE_OVERLAY_VP });
    }
  }
}
