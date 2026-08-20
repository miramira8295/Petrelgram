import { getFolderStore, getUnreadCountStore, getChatStore, getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { FolderInfo } from '../../store/FolderStore';
import { ChatListView } from './ChatListView';
import { MainTabBody } from './MainTabBody';
import { CHAT_LIST_NOW } from './ChatListFreeze';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_BADGE_BG, COLOR_TAB_PILL_BG } from '../../util/theme';
import { router } from '@kit.ArkUI';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import {
  overlayBackdropBlur, overlayMaterial, overlayGlassFill, plainBackdropBlur, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { navigateToChat } from '../../util/chatNav';

interface TabSpec {
  key: string;
  // 文件夹名来自服务器（不翻译），只有「全部」是本地文案。它用 ResourceStr：
  // $r() 由框架在渲染时解析，切语言立刻生效；原来存 str() 出来的普通字符串，
  // 要重启才更新。
  title: ResourceStr;
  // 无障碍文本要的是普通字符串，单独留一份。
  plainTitle: string;
}

const TOP_BAR_HEIGHT: number = 56;
const TOP_ACTION_SIZE: number = 44;
const TAB_BADGE_MAX: number = 99;
const FOLDER_BAR_HEIGHT: number = 44;
// 文件夹条连同它自己的上下留白占的高度（列表让位用）。
const FOLDER_BAR_SPACE: number = 54;
const FOLDER_INDICATOR_HEIGHT: number = 32;
const FOLDER_SWITCH_DURATION: number = 250;

@Preview
// 组件冻结：这四个页签由 MainScreen 的 Tabs 保活，同一时刻只有一个在屏上，
// 其余三棵树却照样响应各自 store 的状态更新、照样重跑 build。冻结之后非
// 激活的页签不再刷新，切回来时框架补上延后的那次更新。
@Component({ freezeWhenInactive: true })
export struct ChatListPage {
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @State folders: FolderInfo[] = [];
  @State unreadMap: Map<string, number> = new Map();
  @State selectedIndex: number = 0;
  // TDLib connection state as a small status hint beside the title
  // ('' when connectionStateReady — nothing shown).
  // The connection state itself, not its label. Keeping the token rather than
  // the rendered text lets the Text below hold a Resource, so the label follows
  // a language switch without waiting for the next connection update.
  @State syncState: string = '';
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  // Sliding selection pill: position/size interpolated between tab frames so it
  // follows the finger during content swipes (Telegram-style).
  @State indicatorX: number = 8;
  @State indicatorW: number = 0;
  private tabXs: number[] = [];
  private tabWs: number[] = [];
  private tabsWidth: number = 0; // Tabs (content) width, for swipe-progress ratio
  private tabViewW: number = 0;  // tab strip viewport width, for keep-visible scrolling
  private tabScroller: Scroller = new Scroller();
  private controller: TabsController = new TabsController();
  private unsubFolders: (() => void) | null = null;
  private unsubUnread: (() => void) | null = null;
  private unsubChats: (() => void) | null = null;
  private unsubConn: (() => void) | null = null;
  @State searchOpening: boolean = false;
  private savedMessagesOpening: boolean = false;
  private folderLayoutPending: boolean = false;
  // Keep the SDK-provided position locally so a position-only update can be
  // reconciled just like a folder reorder. Reading the store directly from
  // tabs() made both the "before" and "after" snapshots use the new value.
  private mainListPosition: number = 0;
  private clockTimer: number = -1;
  private searchOpeningTimer: number = -1;

  @Styles
  actionNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  actionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  @Styles
  tabNormalStyle() {
    .opacity(1)
  }

  @Styles
  tabPressedStyle() {
    .opacity(0.62)
  }

  // Place the pill at a (possibly fractional) tab position: 1.4 = 40% of the
  // way between tab 1 and tab 2, interpolating both position and width.
  private moveIndicatorTo(pos: number): void {
    const n = this.tabs().length;
    if (n === 0 || this.tabWs.length === 0) {
      return;
    }
    const p = Math.max(0, Math.min(n - 1, pos));
    const i0 = Math.floor(p);
    const i1 = Math.min(n - 1, i0 + 1);
    const f = p - i0;
    const x0 = this.tabXs[i0] ?? 8;
    const x1 = this.tabXs[i1] ?? x0;
    const w0 = this.tabWs[i0] ?? 0;
    const w1 = this.tabWs[i1] ?? w0;
    this.indicatorX = x0 + (x1 - x0) * f;
    this.indicatorW = w0 + (w1 - w0) * f;
  }

  // Scroll the tab strip so the selected tab is fully visible.
  private ensureTabVisible(index: number): void {
    const x = this.tabXs[index] ?? 0;
    const w = this.tabWs[index] ?? 0;
    if (w === 0 || this.tabViewW === 0) {
      return;
    }
    const off = this.tabScroller.currentOffset().xOffset;
    let target = -1;
    if (x < off + 8) {
      target = Math.max(0, x - 8);
    } else if (x + w > off + this.tabViewW - 8) {
      target = x + w - this.tabViewW + 8;
    }
    if (target >= 0) {
      this.tabScroller.scrollTo({
        xOffset: target,
        yOffset: 0,
        animation: {
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
          curve: Curve.EaseOut
        }
      });
    }
  }

  aboutToAppear(): void {
    // 预热聊天详情页的模块图。首次 router.pushUrl 要现场加载并执行 ChatPage
    // 及其依赖链（近万行的页面 + MessageBubble + lottie 等），这笔一次性成本
    // 正是"第一次进聊天卡、之后都不卡"的来源。首页落地后空闲时提前把模块
    // 拉起来，首次导航就只剩建页本身。
    setTimeout((): void => {
      import('../chat/ChatPage').catch((): void => { /* 预热失败无碍，首次导航照常加载 */ });
    }, 1200);
    this.startClock();
    if (this.searchOpeningTimer !== -1) {
      clearTimeout(this.searchOpeningTimer);
      this.searchOpeningTimer = -1;
    }
    this.searchOpening = false;
    this.savedMessagesOpening = false;
    this.folders = getFolderStore().getFolders();
    this.mainListPosition = getFolderStore().getMainChatListPosition();
    this.ensureFolderLoads(this.folders);
    this.refreshUnread();
    this.unsubFolders = getFolderStore().subscribe((f: FolderInfo[]) => {
      const previousTabs = this.tabs();
      const selectedKey = previousTabs[this.selectedIndex]?.key ?? 'main';
      const nextMainListPosition = getFolderStore().getMainChatListPosition();
      const foldersChanged = this.folderSignature(this.folders) !== this.folderSignature(f)
        || this.mainListPosition !== nextMainListPosition;
      this.folders = f;
      this.mainListPosition = nextMainListPosition;
      if (foldersChanged) {
        this.reconcileSelectedFolder(selectedKey, previousTabs);
        this.reloadFolderLists(f);
      } else {
        this.ensureFolderLoads(f);
      }
      this.refreshUnread();
    });
    this.unsubUnread = getUnreadCountStore().subscribe(() => { this.refreshUnread(); });
    // Folder unread is derived from cached chats. Listen to lightweight store
    // invalidations rather than rebuilding/sorting the main list a second time.
    this.unsubChats = getChatStore().subscribeChanges(() => { this.refreshUnread(); });
    this.unsubConn = getTdClient().onUpdate('updateConnectionState', (u: TdObject) => {
      const st = u['state'] as TdObject | undefined;
      const t = st !== undefined ? ((st['@type'] as string | undefined) ?? '') : '';
      this.syncState = t === 'connectionStateUpdating' || t === 'connectionStateConnecting'
        || t === 'connectionStateConnectingToProxy' || t === 'connectionStateWaitingForNetwork' ? t : '';
    });
  }

  // Folder edits can arrive while this keep-alive page is behind Settings.
  // Preserve the selected folder by id when folders are reordered, and fall
  // back to "所有" if the selected folder was deleted.
  private reconcileSelectedFolder(selectedKey: string, previousTabs: TabSpec[]): void {
    const previousXs = this.tabXs;
    const previousWs = this.tabWs;
    const xByKey: Map<string, number> = new Map();
    const wByKey: Map<string, number> = new Map();
    previousTabs.forEach((spec: TabSpec, index: number): void => {
      xByKey.set(spec.key, previousXs[index] ?? 0);
      wByKey.set(spec.key, previousWs[index] ?? 0);
    });
    const specs = this.tabs();
    const matchedIndex = specs.findIndex((spec: TabSpec): boolean => spec.key === selectedKey);
    const mainIndex = specs.findIndex((spec: TabSpec): boolean => spec.key === 'main');
    const nextIndex = matchedIndex >= 0 ? matchedIndex : Math.max(0, mainIndex);
    // Preserve known frames by stable folder id. Tabs whose geometry did not
    // change may not emit onAreaChange again after an item is appended.
    this.tabXs = specs.map((spec: TabSpec): number => xByKey.get(spec.key) ?? 0);
    this.tabWs = specs.map((spec: TabSpec): number => wByKey.get(spec.key) ?? 0);
    // Keep the old pill visible until the new frames arrive, then glide it to
    // the preserved folder instead of flashing out and rebuilding at width 0.
    this.folderLayoutPending = this.indicatorW > 0;
    if (nextIndex !== this.selectedIndex) {
      this.selectedIndex = nextIndex;
      this.controller.changeIndex(nextIndex);
    }
  }

  private folderSignature(fs: FolderInfo[]): string {
    return fs.map((f: FolderInfo): string => `${f.id}:${f.title}`).join('|');
  }

  private startClock(): void {
    AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    if (this.clockTimer !== -1) {
      return;
    }
    this.clockTimer = setInterval((): void => {
      AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    }, 60000);
  }

  // TDLib does not emit updateUnreadChatCount for chat folders, so load each
  // folder once to populate its chats; the badge is then derived from them.
  // 分组列表要**翻到底**，不能只预取一页：分组的角标和列表都按本地已加载的
  // 会话算，而「所有」的角标是 TDLib 的服务端真值。只取一页就会出现 issue #43
  // 描述的对不上——「所有」说 5 个群有新消息，分组里只看得见 3 个。
  private ensureFolderLoads(fs: FolderInfo[]): void {
    for (const f of fs) {
      const key = `folder:${f.id}`;
      getChatStore().ensureFullyLoaded(key).then((): void => { this.refreshUnread(); });
    }
  }

  // 分组定义变了：把"已翻到底"的结论作废后再翻一遍，否则新符合规则的会话
  // 进不来（exhaustedLists 是粘性的）。
  private reloadFolderLists(fs: FolderInfo[]): void {
    for (const f of fs) {
      getChatStore().invalidateList(`folder:${f.id}`);
    }
    this.ensureFolderLoads(fs);
  }

  // Main uses TDLib's authoritative unread count; folders derive it from loaded chats.
  private computeUnread(key: string): number {
    if (key === 'main') {
      return getUnreadCountStore().getUnread('main');
    }
    return getChatStore().unreadChatCount(key);
  }

  // Rebuild the whole badge map (new Map identity) so the tab bar re-renders.
  private refreshUnread(): void {
    const next: Map<string, number> = new Map();
    for (const spec of this.tabs()) {
      next.set(spec.key, this.computeUnread(spec.key));
    }
    this.unreadMap = next;
  }

  aboutToDisappear(): void {
    if (this.unsubFolders !== null) { this.unsubFolders(); this.unsubFolders = null; }
    if (this.unsubUnread !== null) { this.unsubUnread(); this.unsubUnread = null; }
    if (this.unsubChats !== null) { this.unsubChats(); this.unsubChats = null; }
    if (this.unsubConn !== null) { this.unsubConn(); this.unsubConn = null; }
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
    if (this.searchOpeningTimer !== -1) {
      clearTimeout(this.searchOpeningTimer);
      this.searchOpeningTimer = -1;
    }
    this.searchOpening = false;
  }

  private tabs(): TabSpec[] {
    const specs: TabSpec[] = [];
    for (const f of this.folders) {
      // 服务器给的文件夹名本就不翻译，两个字段同值。
      specs.push({ key: `folder:${f.id}`, title: f.title, plainTitle: f.title });
    }
    const position = Math.max(0, Math.min(specs.length, this.mainListPosition));
    specs.splice(position, 0, {
      key: 'main', title: $r('app.string.cl_all'), plainTitle: str('cl_all')
    });
    return specs;
  }

  private openSavedMessages(): void {
    if (this.savedMessagesOpening) {
      return;
    }
    this.savedMessagesOpening = true;
    const meRequest: TdRequest = { '@type': 'getMe' };
    getTdClient().send(meRequest).then((me: TdObject): Promise<TdObject> => {
      const userId = (me['id'] as number | undefined) ?? 0;
      if (userId <= 0) {
        return Promise.reject(new Error(str('cl_account_unavailable')));
      }
      const chatRequest: TdRequest = { '@type': 'createPrivateChat' };
      chatRequest['user_id'] = userId;
      chatRequest['force'] = false;
      return getTdClient().send(chatRequest);
    }).then((chat: TdObject): Promise<void> => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      if (chatId <= 0) {
        return Promise.reject(new Error(str('cl_saved_unavailable')));
      }
      const params: Record<string, Object> = { 'chatId': chatId };
      return navigateToChat(params);
    }).then((): void => {
      // pushUrl resolves once the route request is accepted, while this
      // keep-alive home component can stay mounted behind the new page.
      this.savedMessagesOpening = false;
    }).catch((error: Error): void => {
      this.savedMessagesOpening = false;
      console.error(`ChatListPage.openSavedMessages failed: ${error.message}`);
    });
  }

  private openGlobalSearch(): void {
    if (this.searchOpening) {
      return;
    }
    this.searchOpening = true;
    router.pushUrl({ url: 'pages/search/GlobalSearchPage' })
      .then((): void => {
        // Keep a short guard after the route request is accepted so a rapid
        // double tap cannot enqueue a second search page.
        this.searchOpeningTimer = setTimeout((): void => {
          this.searchOpeningTimer = -1;
          this.searchOpening = false;
        }, 520);
      })
      .catch((error: Error): void => {
        if (this.searchOpeningTimer !== -1) {
          clearTimeout(this.searchOpeningTimer);
          this.searchOpeningTimer = -1;
        }
        this.searchOpening = false;
        console.error(`ChatListPage.openGlobalSearch failed: ${error.message}`);
      });
  }

  private tabBadgeText(spec: TabSpec): string {
    const unread = this.unreadMap.get(spec.key) ?? 0;
    return unread > TAB_BADGE_MAX ? `${TAB_BADGE_MAX}+` : `${unread}`;
  }

  private horizontalPadding(): number {
    return this.screenW >= 600 ? 24 : 12;
  }

  private folderTitleMaxWidth(): number {
    return this.screenW >= 600 ? 180 : 132;
  }

  @Builder
  moreMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.ct_new_group') })
        .onClick((): void => {
          router.pushUrl({ url: 'pages/main/NewGroupPage' });
        });
      MenuItem({ content: $r('app.string.cl_saved_messages') })
        .onClick((): void => {
          this.openSavedMessages();
        });
    }
  }

  @Builder
  topAction(icon: string, label: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(icon)).fontSize(23).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width(TOP_ACTION_SIZE).height(TOP_ACTION_SIZE)
    .borderRadius(TOP_ACTION_SIZE / 2)
    .justifyContent(FlexAlign.Center)
    .stateStyles({
      normal: this.actionNormalStyle,
      pressed: this.actionPressedStyle
    })
    .accessibilityText(label)
    .onClick((): void => { onTap(); });
  }

  @Builder
  searchAction() {
    Row() {
      if (this.searchOpening) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(COLOR_PRIMARY)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
              curve: Curve.EaseOut
            }));
      } else {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(23)
          .fontColor([COLOR_TEXT_SECONDARY])
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.84, y: 0.84 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
              curve: Curve.EaseOut
            }));
      }
    }
    .width(TOP_ACTION_SIZE)
    .height(TOP_ACTION_SIZE)
    .borderRadius(TOP_ACTION_SIZE / 2)
    .justifyContent(FlexAlign.Center)
    .stateStyles({
      normal: this.actionNormalStyle,
      pressed: this.actionPressedStyle
    })
    .enabled(!this.searchOpening)
    .accessibilityText(this.searchOpening ? $r('app.string.cl_opening_search') : $r('app.string.cl_global_search'))
    .onClick((): void => {
      this.openGlobalSearch();
    });
  }

  syncLabel(): ResourceStr {
    if (this.syncState === 'connectionStateUpdating') { return $r('app.string.cl_refreshing'); }
    if (this.syncState === 'connectionStateWaitingForNetwork') { return $r('app.string.cl_waiting_network'); }
    if (this.syncState === '') { return ''; }
    return $r('app.string.cl_connecting');
  }

  // 悬浮 chrome 的总高度 = 顶栏 + （有文件夹时）文件夹条。列表按这个值让出
  // 起始位置，滚动时内容从玻璃底下穿过去。
  private chromeInset(): number {
    return this.topSafe + TOP_BAR_HEIGHT +
      (this.folders.length > 0 ? FOLDER_BAR_SPACE : 0);
  }

  @Builder
  topBar() {
    Row({ space: 2 }) {
      Column() {
        // The app's own name, from the resource rather than a literal — a
        // rename should not mean hunting through the UI. It is also the one
        // place users read the product name, so it must not say "Telegram":
        // that is a trademark, and this is an unofficial client.
        Text($r('app.string.app_name'))
          .fontSize(25).fontWeight(FontWeight.Bold).fontColor(COLOR_PRIMARY)
          .maxLines(1)
          .translate({ y: this.syncState === '' ? 7 : 0 })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          });
        Text(this.syncLabel())
          .height(14).fontSize(11).lineHeight(14)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .opacity(this.syncState === '' ? 0 : 1)
          .translate({ y: this.syncState === '' ? -3 : 0 })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          });
      }
      .height(TOP_BAR_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      this.searchAction();

      Row() {
        SymbolGlyph($r('sys.symbol.more')).fontSize(23).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(TOP_ACTION_SIZE).height(TOP_ACTION_SIZE)
      .borderRadius(TOP_ACTION_SIZE / 2)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.actionNormalStyle,
        pressed: this.actionPressedStyle
      })
      .accessibilityText($r('app.string.cl_more_actions'))
      .bindMenu(this.moreMenu(), { systemMaterial: overlayMaterial('menu') });
    }
    .width('100%').height(TOP_BAR_HEIGHT)
    .padding({ left: this.horizontalPadding() + 4, right: this.horizontalPadding() })
    .alignItems(VerticalAlign.Center)
    // 自己不画玻璃：顶栏和文件夹条合成一整块，材质挂在外层那个容器上。
    // 各画各的时，两块玻璃叠在一起会在交界处显出一条边。
    .backgroundColor(Color.Transparent);
  }

  @Builder
  pill(spec: TabSpec, index: number) {
    Row({ space: 5 }) {
      Text(spec.title).fontSize(14)
        .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selectedIndex === index ? COLOR_TAB_SELECTED : COLOR_TAB_UNSELECTED)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: this.folderTitleMaxWidth() });
      if ((this.unreadMap.get(spec.key) ?? 0) > 0) {
        Row() {
          Text(this.tabBadgeText(spec))
            .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
        }
          .constraintSize({ minWidth: 18 })
          .height(18).padding({ left: 5, right: 5 })
          .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
          .backgroundColor(this.selectedIndex === index ? COLOR_TAB_SELECTED : COLOR_BADGE_BG)
          .borderRadius(9);
      }
    }
    .height(FOLDER_BAR_HEIGHT)
    .padding({ left: 12, right: 12 })
    .margin({ right: 2 })
    .borderRadius(FOLDER_BAR_HEIGHT / 2)
    .stateStyles({
      normal: this.tabNormalStyle,
      pressed: this.tabPressedStyle
    })
    .onAreaChange((_old: Area, area: Area) => {
      // Record each pill's frame for the sliding indicator + keep-visible math.
      this.tabXs[index] = area.position.x as number;
      this.tabWs[index] = area.width as number;
      if (index === this.selectedIndex) {
        if (this.folderLayoutPending) {
          this.folderLayoutPending = false;
          animateTo({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220),
            curve: Curve.EaseOut
          }, () => { this.moveIndicatorTo(index); });
          this.ensureTabVisible(index);
        } else {
          this.moveIndicatorTo(index);
        }
      }
    })
    .accessibilityText(
      (this.unreadMap.get(spec.key) ?? 0) > 0
        ? str('cl_tab_unread_a11y', spec.plainTitle, this.tabBadgeText(spec))
        : spec.plainTitle
    )
    .onClick(() => { this.controller.changeIndex(index); });
  }

  @Builder
  tabBar() {
    Column() {
      Scroll(this.tabScroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          // Sliding selection pill behind the labels — driven by indicatorX/W,
          // which follow the finger during Tabs content swipes.
          Row()
            .width(this.indicatorW).height(FOLDER_INDICATOR_HEIGHT)
            .borderRadius(FOLDER_INDICATOR_HEIGHT / 2)
            .backgroundColor(COLOR_TAB_PILL_BG)
            .position({
              x: this.indicatorX,
              y: (FOLDER_BAR_HEIGHT - FOLDER_INDICATOR_HEIGHT) / 2
            });
          Row() {
            ForEach(this.tabs(), (spec: TabSpec, index: number) => {
              this.pill(spec, index);
            }, (spec: TabSpec) => spec.key);
          }.padding({ left: 8, right: 8 }).height(FOLDER_BAR_HEIGHT);
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .width('100%')
      .onAreaChange((_old: Area, area: Area) => {
        this.tabViewW = area.width as number;
        this.ensureTabVisible(this.selectedIndex);
      });
    }
    // 只有这条保留沉浸光感：外面那块顶栏走的是高斯模糊，两种质感叠在一起，
    // 胶囊才像是浮在模糊层之上的一块玻璃。
    .backgroundColor(overlayGlassFill('bar', $r('app.color.dock_glass')))
    .backdropBlur(overlayBackdropBlur('bar'))
    .borderRadius(FOLDER_BAR_HEIGHT / 2)
    .clip(true)
    .border({ width: 0.5, color: $r('app.color.divider') })
    .shadow({ radius: 10, color: '#1F000000', offsetX: 0, offsetY: 3 })
    .systemMaterial(overlayMaterial('bar'))
    .margin({ left: 8, right: 8, bottom: 6 })
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: -4 }))
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
          curve: Curve.EaseOut
        })
    );
  }

  build() {
    Column() {
      // 顶栏和文件夹条一起浮在列表上层，列表靠 contentStartOffset 让出等高的
      // 起始位置。放在 Column 里上下排时列表不从顶栏底下过，玻璃背后没有东西
      // 可透，材质就只剩纹理没有穿透。
      Stack({ alignContent: Alignment.Top }) {
        Tabs({ controller: this.controller }) {
        ForEach(this.tabs(), (spec: TabSpec) => {
          TabContent() {
            // TabContent centers a content-sized child, so a short chat list
            // (few chats / a small folder) would float in the vertical middle.
            // A definite full-height Column pins the list to the top and lets
            // the body's layoutWeight(1) actually stretch.
            Column() {
              if (spec.key === 'main') {
                MainTabBody({ contentTopInset: this.chromeInset() });
              } else {
                ChatListView({
                  listKey: spec.key, contentTopInset: this.chromeInset()
                });
              }
            }.width('100%').height('100%')
          }
        }, (spec: TabSpec) => spec.key);
      }
      .barHeight(0)
      .animationDuration(powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION))
      .onAreaChange((_old: Area, area: Area) => { this.tabsWidth = area.width as number; })
      // Content swipe in progress: convert the swipe offset into a fractional
      // tab position so the selection pill tracks the finger continuously.
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        if (this.tabsWidth > 0) {
          this.moveIndicatorTo(index - event.currentOffset / this.tabsWidth);
        }
      })
      // Finger released / tab tapped: settle the pill on the target tab and
      // scroll the strip if that tab sits outside the visible range.
      .onAnimationStart((_index: number, targetIndex: number) => {
        this.folderLayoutPending = false;
        this.selectedIndex = targetIndex;
        animateTo({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION),
          curve: Curve.EaseOut
        }, () => { this.moveIndicatorTo(targetIndex); });
        this.ensureTabVisible(targetIndex);
      })
      .onChange((index: number) => {
        // onAnimationStart already drives animated changes. Avoid starting the
        // same settle animation twice when onChange fires at the end.
        if (this.selectedIndex !== index) {
          this.selectedIndex = index;
          animateTo({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION),
            curve: Curve.EaseOut
          }, () => { this.moveIndicatorTo(index); });
        } else {
          this.moveIndicatorTo(index);
        }
        this.ensureTabVisible(index);
      })
      .width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);

        // 顶栏和文件夹条同在一块模糊层里，下沿一起收圆角。
        // 代价记在这儿：胶囊那层材质采样到的是父层已经模糊过的均匀底子，
        // 等于玻璃背后是一块平板，悬浮感会弱于它单独浮在列表上时。
        Column() {
          Column() {
            this.topBar();
            if (this.folders.length > 0) {
              this.tabBar();
            }
          }
          .width('100%')
          // 状态栏那段高度由这块自己吃掉，而不是根容器往下推。根容器推的话，
          // 状态栏底下留的是一条实色，和模糊块之间断一层——沉浸就没了。
          .padding({ top: this.topSafe })
          // 这一层走高斯模糊，不挂材质：沉浸光感只留给下面那条文件夹胶囊。
          .backgroundColor($r('app.color.dock_glass'))
          .backdropBlur(plainBackdropBlur())
          // 四个角必须都写：只给 bottomLeft/bottomRight 时整条下沿是直的
          // （实测量过左边缘和正中的下沿在同一 y），漏写的两个角会把整组吃掉。
          .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 18, bottomRight: 18 })
          .clip(true)
          // 下沿什么都不画：边框和投影都去掉了。投影虽然不是线，但 offsetY 4
          // 让它整条压在下沿，在浅色底上看起来就是一条暗带，和边线没区别。
          // 分界完全交给模糊本身——内容滑过去时糊掉，就是分界。
          ;
        }
        .width('100%');
      }
      .layoutWeight(1).width('100%');
    }
    .width('100%').height('100%')
    // 背景色是 expandSafeArea 真正延伸出去的东西——只写 expandSafeArea 而不画
    // 背景，延伸的是"什么都没有"，状态栏底下露的就是窗口底色（实测深色模式
    // 下那是一条纯黑）。官方把这称作"组件安全区方案"：布局仍在安全区内，
    // 绘制延伸到状态栏和导航区。
    // 取 surface 是因为顶栏和列表行用的就是它，延伸出去才连成一片。
    .backgroundColor($r('app.color.surface'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
