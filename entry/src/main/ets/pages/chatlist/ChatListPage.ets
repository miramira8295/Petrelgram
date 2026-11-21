import { navigationHaptics } from '../../services/NavigationHaptics';
import { SplitPanePlaceholder } from '../common/SplitPanePlaceholder';
import { navigateToSetting } from '../../util/settingsNav';
import { NewSessionBanner } from './NewSessionBanner';
import { common } from '@kit.AbilityKit';
import { TelegramQrScanner } from '../../services/TelegramQrScanner';
import { SCOPE_MUTE_EPOCH } from '../../store/ScopeMuteStore';
import { chatListInForeground, chatListPageCanRun } from './ChatListFreeze';
import { clearChatDestShownIfStackEmpty, KEY_CHAT_DETAIL_SHOWN } from '../../util/chatDestTracker';
import {
  BreakpointType, HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WINDOW_PORTRAIT, KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM,
  isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { UnreadBadgeCounts } from '../../util/unreadBadgeRule';
import { chatListSyncState } from '../../util/syncState';
import { flushPendingNavs } from '../../util/pendingNavFlush';
import { getSessionSecurityStore, getFolderStore, getUnreadCountStore, getChatStore, getConnectionState, getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { FolderInfo } from '../../store/FolderStore';
import { folderSymbol } from '../../util/FolderVisuals';
import { GLASS_OUTLINE_COLOR } from '../../util/bubbleTail';
import { ChatListView } from './ChatListView';
import { MainTabBody } from './MainTabBody';
import { FORUM_LEFT_RAIL_WIDTH, ForumSplitView, ForumTopHeaderBar } from './ForumSplitView';
import {
  closeForumDrawer,
  FORUM_DRAWER_CLOSE_MS,
  FORUM_DRAWER_OPEN_MS,
  KEY_ACTIVE_FORUM_OPEN
} from '../../util/forumDrawerState';
import { CHAT_LIST_NOW } from './ChatListFreeze';
import { ComponentContent, FrameCallback, LengthMetrics } from '@kit.ArkUI';
import { HdsNavigation } from '@kit.UIDesignKit';
import { HomeConversationPanel } from './HomeConversationPanel';
import { KEY_SURFACE_GLASS_ON, SURFACE_GLASS_ON_DEFAULT, SURFACE_GLASS_EPOCH, surfaceGlassFill } from '../../util/surfaceGlass';
import { homeCardBottomMarginVp, homeCardMarginVp } from '../../util/pageMargin';
import { APPEARANCE_EPOCH, KEY_STATUS_FOLLOW_TITLE, currentAccentHex } from '../../util/appearance';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_BADGE_BG, COLOR_TAB_PILL_BG } from '../../util/theme';
import { router } from '@kit.ArkUI';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration, KEY_SPLIT_NAV_WIDTH, KEY_FORCE_SINGLE_COLUMN
} from '../../store/AppSettings';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { overlayMaterial } from '../../util/overlayMaterial';
import { TopGlassAction } from './TopGlassAction';
import { CHAT_DEST_NAME, navigateToChat } from '../../util/chatNav';
import { DIRECT_MESSAGES_TOPICS_DEST_NAME, FORUM_TOPICS_DEST_NAME, KEY_ARCHIVE_PANE_OPEN, navigateToArchive } from '../../util/profileNav';
import { logE } from '../../util/log';
import { nextTabPreloadIndex, pruneBuiltKeys } from '../../util/tabPreload';
import { FolderBadge, badgeLabel, folderBadge, setFolderBadge } from '../../util/folderBadges';
import { registerStack, NavStackLike } from '../../util/navStacks';
import { splitNavMinWidth, splitNavMaxWidth, splitContentMinWidth, showSplitFolderRail,
  FOLDER_RAIL_WIDTH, FOLDER_RAIL_GAP, FOLDER_RAIL_NAV_MIN, FOLDER_RAIL_INSET_KEY } from '../../util/splitMetrics';
import { mainPageFill } from '../../util/theme';
import { KEY_APP_BG_ON } from '../../store/AppSettings';
import { SHEET_LIFECYCLE_MODIFIER } from '../../util/navSheetLifecycle';
import { SplitPlaceholderHolder } from '../../util/splitPlaceholderHolder';
import { KEY_APP_DARK } from '../../util/theme';

import { KEY_CHAT_VIEWER_COVERS_WINDOW } from '../../util/viewerWindowCover';
import { navigateToSearch } from '../../util/searchNav';
import {
  requestChatListFlush, setChatListRenderActive
} from '../../util/chatListRenderGate';
import { rememberSplitNavWidth, resolveSplitNavWidth } from '../../util/splitNavWidth';

interface TabSpec {
  key: string;
  iconName: string;
  // 文件夹名来自服务器（不翻译），只有「全部」是本地文案。它用 ResourceStr：
  // $r() 由框架在渲染时解析，切语言立刻生效；原来存 str() 出来的普通字符串，
  // 要重启才更新。
  title: ResourceStr;
  // 无障碍文本要的是普通字符串，单独留一份。
  plainTitle: string;
}

const TOP_BAR_HEIGHT: number = 56;
const TOP_ACTION_SIZE: number = 40;
const TAB_BADGE_MAX: number = 99;
const FOLDER_BAR_HEIGHT: number = 36;
// 文件夹项与选中指示器共用这一个高度。未选项不再各画一块玻璃，只让滑动
// 指示器托住当前项，避免“外层横条 + 一排胶囊 + 会话卡片”叠出三层容器。
const FOLDER_CHIP_HEIGHT: number = 28;
const FOLDER_SWITCH_DURATION: number = 250;
// 邻居页签预载（见 util/tabPreload 的说明）的两个延时。preloadItems 是调用即
// 一次性构建（单个页签实测 ~60ms），时机全靠这里挑：
//   切页后：等 onAnimationEnd 确认动画落定，再留 120ms 给尾帧和图片交接；不能
//   把 ~60ms 的同步构建塞进 250ms 切页动画里。
//   空闲档：冷启动文件夹就绪、从会话页退回来这类时点，躲开首帧和转场余波，
//   800ms 后一般已静止而横滑还没开始。
const TAB_PRELOAD_AFTER_SETTLE_MS: number = 120;
const TAB_PRELOAD_IDLE_MS: number = 800;
// Tabs 默认建过的页签永久保活：连滑 9 个页签后 Swiper 里挂了 ~10 棵整页列表
// 树，横滑期间每帧 Measure[Swiper] 实测 ~5ms（160 次共 837ms），随保活数线性
// 涨。cachedMaxCount(2) 封顶为 当前±2（最多 5 棵）；预载在来路上永远领先一
// 步，缓存上限管住身后不堆树。账本要跟着失效，见 util/tabPreload.pruneBuiltKeys。
const TAB_KEEP_RANGE: number = 2;
// 指示器胶囊的位置/宽度走 AppStorage 旁路而不是页面 @State：moveIndicatorTo
// 在拖动时每帧更新，@State 的话每帧都是一次整页 ExecuteRerender（Frame 录制
// 实测 13 次 >1ms、最大 14.8ms）；旁路后脏区只剩 FolderPill 一个组件。
const FOLDER_PILL_X: string = 'folderPillX';
const FOLDER_PILL_W: string = 'folderPillW';
// 胶囊这一帧该不该"滑过去"。**必须是显式开关**：动画挂在 FolderPill 自己的
// 隐式 `.animation()` 上（见那里），时长由这个开关决定——拖动时必须关掉（每帧
// 一个新目标再配 250ms 缓动，胶囊会一直追在手指屁股后面），切页/松手落定时打开。
// 原来这里是靠页面两处 `animateTo` 包着 moveIndicatorTo 来"滑"的，用户看到的却是
// 瞬移（2026-10-30 报的「直接跳过去」）。
//
// 别拿 uitest dumpLayout 去验这个动画：它读的是**布局结果**，动画帧里量到的
// 仍然是终点坐标，会让人误判成"没动"。要看就看截图。
const FOLDER_PILL_ANIMATE: string = 'folderPillAnimate';
// HdsNavigation reports the nav bar visible near the beginning of a pop. Keep
// child list publications frozen until the measured ~590 ms transition ends,
// then apply the newest buffered snapshot once.
const CHAT_LIST_RETURN_SETTLE_MS: number = 720;

// The route table loads ChatPage dynamically. Queue its module graph immediately
// after the chat list's first frame instead of waiting a fixed 1200 ms: a quick
// tap could beat that timer and pay module evaluation inside the navigation
// frame. ChatPage statically imports ChatHeader, so resolving this import warms
// both modules. The process-wide guard also covers tab/page recreation.
let chatModuleWarmupStarted: boolean = false;

class ChatModuleWarmupFrameCallback extends FrameCallback {
  onFrame(_frameTimeInNano: number): void {
    if (chatModuleWarmupStarted) {
      return;
    }
    chatModuleWarmupStarted = true;
    import('../chat/ChatPage').catch((): void => {
      // A later ChatListPage appearance may retry. Navigation itself remains
      // the authoritative fallback and will still load the module on demand.
      chatModuleWarmupStarted = false;
    });
  }
}

// 分栏时左栏（navBar）占窗口宽度的比例。官方大屏 UX 标准 3.2.2.4 的硬约束是
// 侧边栏不超过窗口宽度 40%、内容区至少 60%；取 1/3 留一档余量，拖拽上限才顶到
// 40%（SPLIT_NAV_CAP_RATIO）。
//
// 为什么是比例而不是定值：写死 320–440 的那一版在 1440vp 的模拟器上左栏只占
// 22%，会话名被截成「TG资源搜索(全…」、时间和未读数挤成两行。那组数是按
// MatePad 的 1137vp 反推的，换一块屏就不成立。
//
// 【这几个常量已搬到 util/splitMetrics.ets】上面这段结论一字未改，仍然成立；
// 搬家的原因是它们在 600–800vp 上算出过两个错值（拖不动 + 和 minContentWidth
// 打架），而这个区间手上没有设备，只能靠宿主单测验算——见 SplitMetrics.test.ets。
// 两端的绝对兜底：下限取一个手机宽度（再窄会话行就没法看了），上限拦住超宽屏
// ——比例再乘下去左栏只是在拉白边，会话行本身早就够宽了。

// navBar（分栏时的左栏）的实际宽度，vp。由 ChatListPage 在布局回调里写入，
// MainScreen 订阅它给 dock 定宽。联系人/设置页签强制单栏，不参与这个键。
export const NAV_BAR_WIDTH_KEY: string = 'navBarWidth';

// 聊天页签的 navBar 此刻是否可见。**它等价于「不是（单栏且栈非空）」**：
//   分栏（平板）  navBar 常驻左栏，恒为 true；
//   单栏（手机）  栈空时 navBar 就是整个页面，true；推入任何 NavDestination
//                （会话/资料/群资料/话题列表/归档）后 navBar 被系统隐藏，false。
// MainScreen 靠它决定悬浮 dock 藏不藏——它自己对 chatStack 完全无感知，而
// NavPathStack 又没有变更通知，这个系统回调是唯一能同时捕获入栈和出栈
// （含系统返回手势）的信号。默认 true：回调没来（或本页尚未挂树）时退化成
// 「dock 照常显示」，也就是修复前的行为，不会把 dock 弄丢。
export const CHAT_NAV_BAR_VISIBLE_KEY: string = 'chatNavBarVisible';
// 分栏且右栏栈空时的占位。官方明确它仅在分栏模式下展示、不受路由栈管理、
// 不可获焦、不响应事件，是纯展示层；单栏模式（手机）下永远不出现。
//
// 写成模块级函数而不是 struct 里的 @Builder 成员：splitPlaceholder 收的是
// ComponentContent，要 wrapBuilder() 包一层，而 wrapBuilder 只接全局 @Builder。
@Builder
function splitPanePlaceholder(): void {
  SplitPanePlaceholder({ message: $r('app.string.split_pick_a_chat'), chatList: true });
}

// 标题区左右内边距与文件夹标题最大宽，按系统横向断点取值（原来写死 screenW >= 600）。
const HORIZONTAL_PADDING_BY_BP: BreakpointType<number> = new BreakpointType<number>(12, 24);
const FOLDER_TITLE_MAX_BY_BP: BreakpointType<number> = new BreakpointType<number>(132, 180);

@Preview
// 组件冻结：这四个页签由 MainScreen 的 Tabs 保活，同一时刻只有一个在屏上，
// 其余三棵树却照样响应各自 store 的状态更新、照样重跑 build。冻结之后非
// 激活的页签不再刷新，切回来时框架补上延后的那次更新。
@Component({ freezeWhenInactive: true })
export struct ChatListPage {
  @StorageProp('appIsForeground') @Watch('onForegroundChanged')
  private appIsForeground: boolean = true;
  private foldersRefreshPending: boolean = false;
  @StorageProp(SCOPE_MUTE_EPOCH) @Watch('onBadgeScopeMuteChanged')
  private badgeScopeMuteEpoch: number = 0;
  private pendingUnreadBadgeKeys: Set<string> = new Set();

  private onBadgeScopeMuteChanged(): void {
    this.refreshUnread();
  }

  private onForegroundChanged(): void {
    if (!chatListInForeground()) {
      this.suspendListRendering();
      return;
    }
    if (!this.pageActive) { return; }
    if (this.foldersRefreshPending) {
      this.foldersRefreshPending = false;
      this.applyFolders(getFolderStore().getFolders());
    }
    this.syncState = chatListSyncState(getConnectionState());
    if (this.navBarVisible) { this.resumeListRenderingAfterTransition(); }
  }

  private chatStack: NavPathStack = new NavPathStack();
  @State private openChatId: number = 0;
  @StorageLink(KEY_ARCHIVE_PANE_OPEN) private archivePaneOpen: boolean = false;
  // 右栏空态。ComponentContent 是节点实体，建一次留着——每次 build 都 new 一个
  // 等于每帧重建一棵子树。
  private splitPlaceholder: SplitPlaceholderHolder = new SplitPlaceholderHolder();
  // 右栏空态是一棵脱离主树的 ComponentContent，深浅色切换不会重解析它的资源
  // ——必须自己丢掉重建，否则夜间模式下左栏和会话页都变深、只有右栏空态还是
  // 浅色（平板实测）。详见 util/splitPlaceholderHolder。
  @StorageProp(KEY_APP_DARK) @Watch('onAppDarkChanged') private appDark: boolean = false;
  // 由 MainScreen 算好写进来的「APP 壁纸生效中」，见 store/AppSettings。
  @StorageProp(KEY_APP_BG_ON) private appWallpaperOn: boolean = false;
  // 大标题的强调色是活绑定，读一次 epoch 才会在用户改色后重绘。
  @StorageProp(APPEARANCE_EPOCH) private appearanceEpoch: number = 0;
  // 状态栏跟不跟标题变色，用户可开（设置 → 聊天 → 自定义强调色）。
  @StorageProp(KEY_STATUS_FOLLOW_TITLE) private statusFollowTitle: boolean = false;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @State folders: FolderInfo[] = [];
  // 镜像到 AppStorage：返回键递退要在非"所有"页签时先切回第 0 个文件夹。
  // 外部写入由 @Watch 落到 TabsController；内部每次写入前先记 appliedFolder，
  // 避免自己触发自己。
  @StorageLink('chatFolderIndex') @Watch('onFolderExternallyChanged') selectedIndex: number = 0;
  private appliedFolder: number = 0;
  // Only user gestures arm this marker; restoring/reordering folders stays silent.
  private hapticGestureStart: number = -1;
  private finishFolderHaptic(index: number): void {
    const start = this.hapticGestureStart;
    this.hapticGestureStart = -1;
    if (start >= 0 && start !== index) { navigationHaptics.play('folder'); }
  }
  // TDLib connection state as a small status hint beside the title
  // ('' when connectionStateReady — nothing shown).
  // The connection state itself, not its label. Keeping the token rather than
  // the rendered text lets the Text below hold a Resource, so the label follows
  // a language switch without waiting for the next connection update.
  @State syncState: string = '';
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') private bottomSafe: number = 0;
  @StorageProp(KEY_SURFACE_GLASS_ON) private surfaceGlass: boolean = SURFACE_GLASS_ON_DEFAULT;
  @StorageProp(SURFACE_GLASS_EPOCH) private surfaceGlassEpoch: number = 0;
  // navBar 的实际宽度（onAreaChange 里写进 AppStorage 的那个值）。⋮ 菜单的锚点
  // 要按它定位：分栏时外层 Stack 横跨两栏，按 TopEnd 对齐会把菜单弹到右栏
  // 聊天页的右上角去（issue #146）。
  @StorageProp(NAV_BAR_WIDTH_KEY) private navBarW: number = 0;
  @StorageProp('screenWidthVp') @Watch('onWindowResized') screenW: number = 360;
  // 设置里的「强制单栏」（宽屏也当手机用）。
  @StorageProp(KEY_FORCE_SINGLE_COLUMN) @Watch('onSplitModeChanged') forceSingleColumn: boolean = false;
  // 分栏下会话页的媒体查看器开着：收左栏，让右栏里的查看器盖满窗口（见 util/viewerWindowCover）。
  // 复用 onWindowResized：它按定义重算 navBar 可见性，这里只是多了一个输入。
  @StorageProp(KEY_CHAT_VIEWER_COVERS_WINDOW) viewerCoversWindow: boolean = false;
  @StorageProp(KEY_CHAT_DETAIL_SHOWN) @Watch('onChatDetailShownChanged') private chatDetailShown: boolean = false;
  private lastReportedNavBarVisible: boolean = false;
  // 分栏判据读系统横向 + 纵向断点（util/layoutBreakpoint.isSplitByBreakpoint）——只看宽的话
  // 手机一转横屏就被当成平板（#125）。
  @StorageProp('screenHeightVp') @Watch('onWindowResized') screenH: number = 780;
  // 系统断点（util/layoutBreakpoint）：分栏判据读它，不再按窗口宽高自己算。
  @StorageProp(KEY_WIDTH_BREAKPOINT) @Watch('onSplitModeChanged') widthBp: number = WIDTH_BP_SM;
  @StorageProp(KEY_HEIGHT_BREAKPOINT) @Watch('onSplitModeChanged') heightBp: number = HEIGHT_BP_LG;
  @StorageProp(KEY_WINDOW_PORTRAIT) @Watch('onSplitModeChanged') windowPortrait: boolean = true;
  // 平板分栏下记住的左栏宽度（issue #106），见 util/splitNavWidth。
  @StorageProp(KEY_SPLIT_NAV_WIDTH) private savedNavW: number = 0;
  // Sliding selection pill: position/size interpolated between tab frames so it
  // follows the finger during content swipes (Telegram-style).
  // 不是 @State：真正画胶囊的 FolderPill 走 FOLDER_PILL_X/W 旁路，这两份
  // 留作页面逻辑自己的读值（folderLayoutPending 的判据等）。
  private indicatorX: number = 0;
  private indicatorW: number = 0;
  // 胶囊当前是不是"滑过去"模式（见 FOLDER_PILL_ANIMATE）。页面这一份只是用来
  // 去重：拖动时每帧都会调 setPillAnimate(false)，不比对就会每帧写一次 AppStorage。
  private pillAnimateOn: boolean = false;
  private tabXs: number[] = [];
  private tabWs: number[] = [];
  private tabsWidth: number = 0; // Tabs (content) width, for swipe-progress ratio
  private tabViewW: number = 0;  // tab strip viewport width, for keep-visible scrolling
  private tabScroller: Scroller = new Scroller();
  private folderRailScroller: ListScroller = new ListScroller();
  private controller: TabsController = new TabsController();
  private unsubFolders: (() => void) | null = null;
  private unsubUnread: (() => void) | null = null;
  private unsubChats: (() => void) | null = null;
  private unsubConn: (() => void) | null = null;
  @State searchOpening: boolean = false;
  private savedMessagesOpening: boolean = false;
  // 每个文件夹页签一个滚动控制器。HdsNavigation 靠它们驱动标题栏的收缩与
  // 渐变模糊，而列表在子组件内部，只能由这里建好递下去。按 key 存：文件夹
  // 增删时页签数会变，按下标存会错位。
  // ListScroller 而不是 Scroller：会话行的左右滑操作要用 closeAllSwipeActions。
  private tabScrollers: Map<string, ListScroller> = new Map<string, ListScroller>();
  // ⋮ 菜单。HDS 标题栏的菜单项只给 action 回调、挂不了 bindMenu，由它翻开关，
  // 菜单本体绑在右上角一个零尺寸锚点上（见 build）。
  @State private moreMenuShown: boolean = false;
  private folderLayoutPending: boolean = false;
  // Keep the SDK-provided position locally so a position-only update can be
  // reconciled just like a folder reorder. Reading the store directly from
  // tabs() made both the "before" and "after" snapshots use the new value.
  private mainListPosition: number = 0;
  private clockTimer: number = -1;
  private searchOpeningTimer: number = -1;
  // HdsNavigation keeps the nav bar component alive while a ChatPage slides
  // over it. Store callbacks must not publish new @State snapshots into that
  // moving, covered page: the frame trace showed six full ChatListPage builds
  // alongside repeated store notifications. Keep only a dirty bit and mirror the
  // newest badge snapshot once the nav bar is visible again.
  private navBarVisible: boolean = false;
  private unreadRefreshPending: boolean = false;
  private listRenderActive: boolean = true;
  private listRenderResumeTimer: number = -1;
  // 构建过内容的页签（访问过或预载过），按 key 记账：文件夹增删/重排时下标
  // 会漂移，子树却跟着 ForEach 的 key 走。见 util/tabPreload。
  private builtTabKeys: Set<string> = new Set<string>();
  private tabPreloadTimer: number = -1;
  // onGestureSwipe 到 onAnimationEnd 之间不允许 preloadItems 同步构建页签内容。
  // 同一个标志同时覆盖手势跟手、松手回弹和点按切换动画。
  private tabAnimationActive: boolean = false;
  private pageActive: boolean = false;
  // 空闲时预热相邻页的头像与玻璃；若用户早于预热开始横滑，companion 兜底让
  // 已经进入视口的页面立刻补齐视觉。横滑结束后由 warmedVisualTabKeys 接管。
  @State private companionImageTabIndex: number = -1;
  @State private warmedVisualTabKeys: string[] = [];
  @Styles
  actionNormalStyle() {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  actionPressedStyle() {
    .scale({ x: 0.92, y: 0.92 })
    .opacity(0.75)
  }

  @Styles
  tabNormalStyle() {
    .opacity(1)
  }

  @Styles
  tabPressedStyle() {
    .opacity(0.62)
  }

  // 打开/关闭胶囊的「滑过去」模式（见 FOLDER_PILL_ANIMATE）。只在真的翻面时写
  // AppStorage：拖动时每帧都会调它。
  private setPillAnimate(on: boolean): void {
    if (this.pillAnimateOn === on) {
      return;
    }
    this.pillAnimateOn = on;
    AppStorage.setOrCreate(FOLDER_PILL_ANIMATE, on);
  }

  // Place the pill at a (possibly fractional) tab position: 1.4 = 40% of the
  // way between tab 1 and tab 2, interpolating both position and width.
  private moveIndicatorTo(pos: number): void {
    if (this.folderRailShown()) { return; }
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
    AppStorage.setOrCreate(FOLDER_PILL_X, this.indicatorX);
    AppStorage.setOrCreate(FOLDER_PILL_W, this.indicatorW);
  }

  // AppStorage 侧被外部改写（返回键递退回"所有"）时，真正把 Tabs 切过去。
  private onFolderExternallyChanged(): void {
    this.archivePaneOpen = false;
    if (this.selectedIndex !== this.appliedFolder) {
      this.hapticGestureStart = -1;
      this.appliedFolder = this.selectedIndex;
      this.controller.changeIndex(this.selectedIndex);
    }
  }

  // 横条手动滑过的位置。用户的反馈：手指滑到一半，列表一有更新（未读数变、标题栏
  // 重建、横条短暂离树再回来）横条就被拽回「选中的那个可见」的位置——期望手指
  // 滑到哪就停在哪。所以：手指碰过横条之后，布局变化一律原地恢复到用户的位置；
  // 只有真正切换了分组，才自动滚到新选中的那个（revealTab）。
  private stripUserMoved: boolean = false;
  // 按住文件夹轨道（含按住后滑动）时的轻微形变。底色由统一面板承载，
  // 只有把变换挂在包住它的那层 Stack 上，玻璃才会跟着一起动。
  @State private railPressed: boolean = false;
  private stripOffsetX: number = 0;

  // 切换了分组：滚到新选中的那个，忘掉用户之前滑到的位置。
  private revealTab(index: number): void {
    if (this.folderRailShown()) {
      this.folderRailScroller.scrollToIndex(index, false, ScrollAlign.AUTO);
      return;
    }
    this.stripUserMoved = false;
    this.ensureTabVisible(index);
  }

  // 布局变了（不是换分组）：用户滑过就原地恢复，没滑过照旧让选中的可见。
  private keepOrRevealStrip(): void {
    if (this.folderRailShown()) { return; }
    if (!this.stripUserMoved) {
      this.ensureTabVisible(this.selectedIndex);
      return;
    }
    const cur: OffsetResult | undefined = this.tabScroller.currentOffset();
    if (cur === undefined || Math.abs(cur.xOffset - this.stripOffsetX) < 0.5) {
      return;
    }
    this.tabScroller.scrollTo({ xOffset: this.stripOffsetX, yOffset: 0 });
  }

  // Scroll the tab strip so the selected tab is fully visible.
  private ensureTabVisible(index: number): void {
    const x = this.tabXs[index] ?? 0;
    const w = this.tabWs[index] ?? 0;
    if (w === 0 || this.tabViewW === 0) {
      return;
    }
    // currentOffset() 在控制器**没绑上滚动容器**时返回 undefined（文档如此，
    // 类型签名骗人）。tabScroller 绑的横条挂在标题栏 bottomBuilder 上，文件夹
    // 列表刷新时横条会短暂离树，这一瞬切页签就踩空——线上七连崩（v1.3.7
    // "Cannot read property xOffset of undefined"）全是它。
    const cur: OffsetResult | undefined = this.tabScroller.currentOffset();
    if (cur === undefined) {
      return;
    }
    const off = cur.xOffset;
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

  // navBar 显隐落地：写标志、开关列表渲染闸、同步给 dock。
  // **两条路共用**——框架的 onNavBarStateChange，以及下面按窗口尺寸自己重算的
  // onWindowResized。两处各写一遍必然跑偏。
  private applyNavBarVisible(reported: boolean): void {
    this.lastReportedNavBarVisible = reported;
    const isVisible: boolean = reported && !(this.singleColDetailCoversNavBar && this.singleColDetailCoversNavBar());
    const changed: boolean = this.navBarVisible !== isVisible;
    this.navBarVisible = isVisible;
    if (!isVisible || !chatListInForeground()) {
      this.suspendListRendering();
    } else if (changed || !this.listRenderActive) {
      // 先把缓冲里的内容变更刷出去（未读角标之类），再等过渡结束开闸
      // （issue #159）。见 util/chatListRenderGate.requestChatListFlush。
      requestChatListFlush();
      // 【issue #159 的第三条缺口】页签上的数字角标原来完全没接进这条旁路：
      // refreshUnread() 在闸关时只置 unreadRefreshPending 就 return，唯一的补刷
      // 在 640ms 定时器里。于是列表行的角标（走 requestChatListFlush）已经更新了，
      // 而文件夹页签上那个数字还挂着，慢半拍的观感只解决了一半。
      //
      // 在转场里刷它是安全的：角标走 util/folderBadges 的旁路模型
      // （setFolderBadge），只有值真的变了的那个 chip 自己重渲染，
      // 整页和标题栏都不牵动——这正是当初把它做成旁路的目的。
      this.flushFolderBadges();
      this.resumeListRenderingAfterTransition();
    }
    if (AppStorage.get<boolean>(CHAT_NAV_BAR_VISIBLE_KEY) !== isVisible) {
      AppStorage.setOrCreate<boolean>(CHAT_NAV_BAR_VISIBLE_KEY, isVisible);
    }
  }

  private singleColDetailCoversNavBar(): boolean {
    return !isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait)
      && this.chatStack.size() > 0
      && this.chatDetailShown
      && !(AppStorage.get<boolean>('chatDetailHiding') ?? false);
  }

  private onChatDetailShownChanged(): void {
    if (!this.chatDetailShown && (this.chatStack.size() === 0 || this.lastReportedNavBarVisible)) {
      this.applyNavBarVisible(!this.viewerHidesNavBar());
      return;
    }
    this.applyNavBarVisible(this.lastReportedNavBarVisible && !this.viewerHidesNavBar());
  }

  // 窗口尺寸一变，分栏与否可能跟着翻（平板分屏、悬浮窗、旋转、折叠屏都会），
  // navBar 的真实显隐也跟着翻——而此前**没有任何东西会重算那个标志**：它只由
  // onNavBarStateChange 写。那是框架给的回调，我们既保证不了它在每一次 mode
  // 翻转时都来，回调里那道兜底闸读的 screenW/screenH 又是 AppStorage 里由
  // EntryAbility 的 windowSizeChange 另行刷新的值，两者先后无定。任何一边落空，
  // 标志就停在 true，dock 于是浮在会话详情上不收——用户实报「Pad 版 dock 偶尔
  // 不回收」，"偶尔"正是竞态的形状。
  //
  // 这里不去猜框架的时序，直接按标志的**定义**重算：分栏 → 恒可见；单栏 →
  // 栈空才可见。与 aboutToAppear 的复位是同一个判据（util/navBarReset），
  // 不引入第二套语义，只是把「谁来通知」这件事从框架手里拿回来一份。
  // 值没变时 applyNavBarVisible 是幂等的，所以这条路平时什么都不做。
  private onWindowResized(): void {
    if (this.singleColDetailCoversNavBar()) {
      this.applyNavBarVisible(false);
    }

  // 只在分栏时生效：单栏（手机）下 navBar 本来就被会话页整页盖住，不需要这一手。
  }

  private viewerHidesNavBar(): boolean {
    return this.viewerCoversWindow && isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait);
  }

  @State private newSessionCount: number = 0;
  private unsubSessionSecurity: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubSessionSecurity = getSessionSecurityStore().subscribe((count: number): void => {
      this.newSessionCount = count;
    });
    this.pageActive = true;
    // 深链、通知点击、账号切换都在页面之外触发跳转，拿不到组件上下文，
    // 只能靠全局注册表取栈。见 util/navStacks.ets 的说明。
    registerStack('chat', this.chatStack as NavStackLike);
    this.chatStack.setInterception({
      didShow: (_from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar): void => {
        let chatId: number = 0;
        if (typeof to !== 'string') {
          const path = to.pathInfo;
          if (path.name === CHAT_DEST_NAME || path.name === FORUM_TOPICS_DEST_NAME ||
            path.name === DIRECT_MESSAGES_TOPICS_DEST_NAME) {
            const params = path.param as Record<string, Object> | undefined;
            chatId = (params?.['chatId'] as number | undefined) ?? 0;
          }
        }
        this.openChatId = chatId;
      }
    });
    // 栈没注册时被挂起的跳转（冷启动点通知、登录前的深链）在这里放出去。
    // **延一拍**：官方明确"不建议在 aboutToAppear 中操作栈，此时页面还未构建
    // 完成"，而这里正是 aboutToAppear。见 util/pendingNav 的事故说明。
    setTimeout((): void => { flushPendingNavs('chat'); }, 0);

    clearChatDestShownIfStackEmpty(this.chatStack.size());
    this.lastReportedNavBarVisible = false;
    this.navBarVisible = false;
    AppStorage.setOrCreate<boolean>(CHAT_NAV_BAR_VISIBLE_KEY, false);
    this.listRenderActive = chatListPageCanRun(this.pageActive, this.navBarVisible);
    setChatListRenderActive(this.listRenderActive);
    // 先让会话列表首帧落地，紧接着预热聊天详情页模块。固定等 1200ms 会让快速
    // 点击穿过预热窗口；帧回调既避开列表首帧，又保证正常的人手点击前已经开始。
    this.getUIContext().postFrameCallback(new ChatModuleWarmupFrameCallback());
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
      if (!chatListInForeground()) {
        this.foldersRefreshPending = true;
        return;
      }
      this.applyFolders(f);
    });
    this.unsubUnread = getUnreadCountStore().subscribe(() => { this.refreshUnread(['main']); });
    // Content/order changes do not affect folder unread-chat counts.
    this.unsubChats = getChatStore().subscribeUnreadBadges((keys: string[]): void => {
      this.refreshUnread(keys);
    });
    this.unsubConn = getTdClient().onUpdate('updateConnectionState', (u: TdObject) => {
      if (!chatListInForeground()) { return; }
      const st = u['state'] as TdObject | undefined;
      this.syncState = chatListSyncState(
        st !== undefined ? ((st['@type'] as string | undefined) ?? '') : '');
    });
    // 订阅晚了收不到当前值（#219-7：没网冷启动时标题什么都不显示），先读缓存补一次。
    this.syncState = chatListSyncState(getConnectionState());
    // 冷启动时文件夹多半已在本地缓存里（tabs() 立即非空），首个邻居页签趁
    // 启动静止期先建出来，用户第一次横滑就不用付那 74ms（Frame 录制实测）。
    // 文件夹还没到的话这次是空转，订阅回调里 foldersChanged 那一路会再排。
    this.scheduleTabPreload(TAB_PRELOAD_IDLE_MS);
  }

  private applyFolders(f: FolderInfo[]): void {
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
      // 页签集合变了，当前页签的邻居可能换人（或首次出现），重排一次预载。
      this.scheduleTabPreload(TAB_PRELOAD_IDLE_MS);
    } else {
      this.ensureFolderLoads(f);
    }
    this.refreshUnread();
  }

  // Folder edits can arrive while this keep-alive page is behind Settings.
  // Preserve the selected folder by id when folders are reordered, and fall
  // back to "所有" if the selected folder was deleted.
  private reconcileSelectedFolder(selectedKey: string, previousTabs: TabSpec[]): void {
    this.hapticGestureStart = -1;
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
      this.appliedFolder = nextIndex;
      this.selectedIndex = nextIndex;
      this.controller.changeIndex(nextIndex);
    }
  }

  private folderSignature(fs: FolderInfo[]): string {
    return fs.map((f: FolderInfo): string => `${f.id}:${f.title}`).join('|');
  }

  private syncClockMinute(): void {
    // 列表行时间（formatTime）只精确到分钟/天，不看秒；按整分钟量化并仅在跨分钟时写入，
    // 避免从会话退回列表（resumeListRenderingAfterTransition -> startClock）在转场刚结束
    // 的那一帧无条件改写秒级时间戳、触发全部可见与缓存 ChatRow 同步重绘掉帧。
    const nowMinSec: number = Math.floor(Date.now() / 60000) * 60;
    if ((AppStorage.get<number>(CHAT_LIST_NOW) ?? 0) !== nowMinSec) {
      AppStorage.setOrCreate(CHAT_LIST_NOW, nowMinSec);
    }
  }

  private startClock(): void {
    if (!chatListPageCanRun(this.pageActive, this.navBarVisible) || !this.listRenderActive) { return; }
    this.syncClockMinute();
    if (this.clockTimer !== -1) {
      return;
    }
    this.clockTimer = setInterval((): void => {
      if (chatListPageCanRun(this.pageActive, this.navBarVisible) && this.listRenderActive) {
        this.syncClockMinute();
      }
    }, 60000);
  }

  private cancelTabPreload(): void {
    if (this.tabPreloadTimer !== -1) {
      clearTimeout(this.tabPreloadTimer);
      this.tabPreloadTimer = -1;
    }
  }

  private scheduleTabPreload(delay: number): void {
    this.cancelTabPreload();
    if (!chatListPageCanRun(this.pageActive, this.navBarVisible) || this.tabAnimationActive || !this.listRenderActive) {
      return;
    }
    this.tabPreloadTimer = setTimeout((): void => {
      this.tabPreloadTimer = -1;
      if (!chatListPageCanRun(this.pageActive, this.navBarVisible) || this.tabAnimationActive || !this.listRenderActive) {
        return;
      }
      this.preloadNeighborTab();
    }, delay);
  }

  // 首次滑进一个文件夹页签要在手势首帧里同步构建整屏 ChatRow（Frame 录制实测
  // 74/81ms，120Hz 下丢 8-9 拍）。这里按官方推荐用 preloadItems 把这次构建挪到
  // 页签落定后的安静窗口，一次只预载一个邻居（时机与账本见 util/tabPreload
  // 和上面两个延时常量的说明）。
  private preloadNeighborTab(): void {
    // 被会话页盖住时不做：构建结果虽然照样有效，但那 60ms 会挤占转场和
    // 详情页的帧。退回来时 resumeListRenderingAfterTransition 会重新排。
    if (!chatListPageCanRun(this.pageActive, this.navBarVisible) || !this.listRenderActive || this.tabAnimationActive) {
      return;
    }
    const specs = this.tabs();
    const currentKey = specs[this.selectedIndex]?.key;
    if (currentKey === undefined) {
      return;
    }
    const keys = specs.map((spec: TabSpec): string => spec.key);
    // cachedMaxCount 已把 当前±TAB_KEEP_RANGE 之外的页签释放，账本同步失效，
    // 否则预载会跳过已释放的页签，滑回去又是首帧全量构建。
    this.builtTabKeys = pruneBuiltKeys(keys, this.selectedIndex, this.builtTabKeys, TAB_KEEP_RANGE);
    this.builtTabKeys.add(currentKey);
    const warmLo: number = Math.max(0, this.selectedIndex - 1);
    const warmHi: number = Math.min(keys.length - 1, this.selectedIndex + 1);
    const keptWarm: string[] = this.warmedVisualTabKeys.filter((key: string): boolean => {
      const index: number = keys.indexOf(key);
      return index >= warmLo && index <= warmHi;
    });
    if (keptWarm.length !== this.warmedVisualTabKeys.length) {
      this.warmedVisualTabKeys = keptWarm;
    }
    // 页签树先预载，头像解码和玻璃节点再隔一个静止窗口启动，避免两笔重活
    // 落在同一帧。一次只处理一个邻居，右侧优先，与页面预载顺序一致。
    const warmCandidates: number[] = [this.selectedIndex + 1, this.selectedIndex - 1];
    for (const warmIndex of warmCandidates) {
      const warmKey: string | undefined = keys[warmIndex];
      if (warmKey !== undefined && this.builtTabKeys.has(warmKey) &&
        this.warmedVisualTabKeys.indexOf(warmKey) < 0) {
        this.warmedVisualTabKeys = [...this.warmedVisualTabKeys, warmKey];
        this.scheduleTabPreload(TAB_PRELOAD_AFTER_SETTLE_MS);
        return;
      }
    }
    const index = nextTabPreloadIndex(keys, this.selectedIndex, this.builtTabKeys);
    if (index < 0) {
      return;
    }
    const key = specs[index].key;
    this.builtTabKeys.add(key);
    try {
      this.controller.preloadItems([index]).then((): void => {
        // 下一静止窗口先为刚建好的页签补头像和玻璃，再继续另一侧邻居。
        this.scheduleTabPreload(TAB_PRELOAD_AFTER_SETTLE_MS);
      }).catch((e: Error): void => {
        // 失败就把账抹掉，下一个窗口还有机会重试。
        this.builtTabKeys.delete(key);
        logE(`ChatListPage.preloadItems(${index}) rejected: ${e.message}`);
      });
    } catch (e) {
      // 控制器还没绑上 Tabs 时会同步抛异常（官方文档点名要 catch）。
      this.builtTabKeys.delete(key);
      const err = e as Error;
      logE(`ChatListPage.preloadItems(${index}) failed: ${err.message}`);
    }
  }

  private cancelListRenderResume(): void {
    if (this.listRenderResumeTimer !== -1) {
      clearTimeout(this.listRenderResumeTimer);
      this.listRenderResumeTimer = -1;
    }
  }

  private suspendListRendering(): void {
    this.cancelListRenderResume();
    this.cancelTabPreload();
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
    this.listRenderActive = false;
    setChatListRenderActive(false);
  }

  private resumeListRenderingAfterTransition(): void {
    this.cancelListRenderResume();
    if (!chatListPageCanRun(this.pageActive, this.navBarVisible)) { return; }
    this.listRenderResumeTimer = setTimeout((): void => {
      this.listRenderResumeTimer = -1;
      if (!chatListPageCanRun(this.pageActive, this.navBarVisible)) {
        return;
      }
      this.listRenderActive = true;
      setChatListRenderActive(true);
      // ChatRow time labels and folder badges were deliberately frozen while
      // covered. Refresh both after child data sources have flushed their one
      // coalesced snapshot, outside the pop transition.
      this.startClock();
      if (this.unreadRefreshPending) {
        this.refreshUnread([]);
      }
      // 盖住期间被跳过的邻居预载（preloadNeighborTab 的 listRenderActive 闸）
      // 在这里补排。走快档不走空闲档：本定时器已经等完了 ~590ms 转场，再叠
      // 800ms 就是 1.4s 无保护窗——Frame 录制 20260902T161959 里 206ms 的
      // tab 甩动卡顿（一帧测 3 棵列表树）正发生在 onBackPress 后的这个窗口。
      this.scheduleTabPreload(TAB_PRELOAD_AFTER_SETTLE_MS);
    }, CHAT_LIST_RETURN_SETTLE_MS);
  }

  // TDLib does not emit updateUnreadChatCount for chat folders, so load each
  // folder once to populate its chats; the badge is then derived from them.
  // 分组列表要**翻到底**，不能只预取一页：分组的角标和列表都按本地已加载的
  // 会话算，而「所有」的角标是 TDLib 的服务端真值。只取一页就会出现 issue #43
  // 描述的对不上——「所有」说 5 个群有新消息，分组里只看得见 3 个。
  private ensureFolderLoads(fs: FolderInfo[]): void {
    for (const f of fs) {
      const key = `folder:${f.id}`;
      getChatStore().ensureFullyLoaded(key).then((): void => { this.refreshUnread([key]); });
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
  // 数字 = 全部未读会话数（含静音），颜色看未静音数（issue #155，Telegram 同口径）。
  private computeBadge(key: string): UnreadBadgeCounts {
    if (key === 'main') {
      const store = getUnreadCountStore();
      return { total: store.getUnreadTotal('main'), unmuted: store.getUnread('main') };
    }
    return getChatStore().unreadChatBadge(key);
  }

  // 逐 chip 写入旁路模型（util/folderBadges），只有值变了的角标各自重渲染，
  // 整页和标题栏不再牵动。While a destination covers the nav bar, collapse any
  // number of notifications into one pending refresh（延后语义保持原样）。
  private refreshUnread(keys?: string[]): void {
    if (keys === undefined) {
      for (const spec of this.tabs()) { this.pendingUnreadBadgeKeys.add(spec.key); }
    } else {
      for (const key of keys) {
        if (key === 'main' || key.startsWith('folder:')) { this.pendingUnreadBadgeKeys.add(key); }
      }
    }
    if (this.pendingUnreadBadgeKeys.size === 0) { return; }
    if (!chatListPageCanRun(this.pageActive, this.navBarVisible) || !this.listRenderActive || this.tabAnimationActive) {
      this.unreadRefreshPending = true;
      return;
    }
    this.unreadRefreshPending = false;
    this.writeFolderBadges();
  }

  // 绕过 listRenderActive 闸直接写一次角标。**只给返回转场那条路用**
  // （见 onNavBarStateChange 里的说明）：闸关着的其余场景（被别的页面盖住）
  // 仍然走 refreshUnread 的延后语义，不在这里放行。
  private flushFolderBadges(): void {
    if (!chatListPageCanRun(this.pageActive, this.navBarVisible)) {
      this.unreadRefreshPending = true;
      return;
    }
    this.unreadRefreshPending = false;
    this.writeFolderBadges();
  }

  private writeFolderBadges(): void {
    const pending = this.pendingUnreadBadgeKeys;
    this.pendingUnreadBadgeKeys = new Set();
    for (const spec of this.tabs()) {
      if (!pending.has(spec.key)) { continue; }
      const counts: UnreadBadgeCounts = this.computeBadge(spec.key);
      setFolderBadge(spec.key, counts.total, counts.unmuted > 0);
    }
  }

  private qrScanner: TelegramQrScanner = new TelegramQrScanner();

  aboutToDisappear(): void {
    this.archivePaneOpen = false;
    this.chatStack.setInterception({});
    this.hapticGestureStart = -1;
    AppStorage.setOrCreate<boolean>(CHAT_NAV_BAR_VISIBLE_KEY, false);
    this.unsubSessionSecurity?.();
    this.unsubSessionSecurity = null;
    this.qrScanner.cancel();
    this.pageActive = false;
    this.cancelListRenderResume();
    this.cancelTabPreload();
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
    // ComponentContent 是脱离组件树管理的节点实体，得自己释放。
    this.splitPlaceholder.dispose();
  }

  private tabs(): TabSpec[] {
    const specs: TabSpec[] = [];
    for (const f of this.folders) {
      // 服务器给的文件夹名本就不翻译，两个字段同值。
      specs.push({ key: `folder:${f.id}`, title: f.title, plainTitle: f.title, iconName: f.iconName });
    }
    const position = Math.max(0, Math.min(specs.length, this.mainListPosition));
    specs.splice(position, 0, {
      key: 'main', title: $r('app.string.cl_all'), plainTitle: str('cl_all'), iconName: 'All'
    });
    return specs;
  }

  private tabEffectsActive(key: string): boolean {
    const specs = this.tabs();
    return specs[this.selectedIndex]?.key === key ||
      specs[this.companionImageTabIndex]?.key === key;
  }

  private tabVisualsActive(key: string): boolean {
    const specs = this.tabs();
    return specs[this.selectedIndex]?.key === key ||
      specs[this.companionImageTabIndex]?.key === key ||
      this.warmedVisualTabKeys.indexOf(key) >= 0;
  }

  private tabUpdatesActive(key: string): boolean {
    return !this.tabAnimationActive && this.tabs()[this.selectedIndex]?.key === key;
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
      logE(`ChatListPage.openSavedMessages failed: ${error.message}`);
    });
  }

  private openGlobalSearch(): void {
    if (this.searchOpening) {
      return;
    }
    this.searchOpening = true;
    // 推进聊天页签的栈（搜索页现在是栈里的一层，见 util/searchNav）。同步调用，
    // 防连点闸门照旧用定时器解开。
    navigateToSearch();
    this.searchOpeningTimer = setTimeout((): void => {
      this.searchOpeningTimer = -1;
      this.searchOpening = false;
    }, 520);
  }

  // 按系统横向断点取值（官方 BreakpointType）：sm 12，md 起 24。
  private horizontalPadding(): number {
    return HORIZONTAL_PADDING_BY_BP.getValue(this.widthBp);
  }

  private folderTitleMaxWidth(): number {
    return FOLDER_TITLE_MAX_BY_BP.getValue(this.widthBp);
  }

  @Builder
  moreMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.qr_scan') })
        .onClick((): void => { this.qrScanner.start(this.getUIContext().getHostContext() as common.UIAbilityContext); });
      MenuItem({ content: $r('app.string.settings_proxy') })
        .onClick((): void => { navigateToSetting('ProxyPage'); });
      MenuItem({ content: $r('app.string.ct_new_group') })
        .onClick((): void => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/main/NewGroupPage' });
        });
      MenuItem({ content: $r('app.string.cl_saved_messages') })
        .onClick((): void => {
          this.openSavedMessages();
        });
    }
  }

  @Builder
  topAction(icon: string, label: Resource, onTap: () => void) {
    // 圆钮与三套按压/跟手状态都收进 TopGlassAction：页面级 @State 每帧更新会
    // 触发整页重渲染（交接文档实测峰值 14.8ms），必须关在小里。
    TopGlassAction({
      actionSize: TOP_ACTION_SIZE,
      embedded: true,
      plainFill: this.homeChromeFill(this.surfaceGlassEpoch, this.appDark),
      icon: icon,
      dark: this.appDark,
      iconColor: COLOR_ICON_SECONDARY,
      accentColor: this.accent(),
      label: label,
      onTap: onTap
    })
  }

  @Builder
  searchAction() {
    TopGlassAction({
      actionSize: TOP_ACTION_SIZE,
      embedded: true,
      plainFill: this.homeChromeFill(this.surfaceGlassEpoch, this.appDark),
      icon: 'sys.symbol.magnifyingglass',
      busy: this.searchOpening,
      dark: this.appDark,
      interactive: !this.searchOpening,
      iconColor: COLOR_ICON_SECONDARY,
      accentColor: this.accent(),
      label: this.searchOpening ? $r('app.string.cl_opening_search') : $r('app.string.cl_global_search'),
      onTap: (): void => {
        this.openGlobalSearch();
      }
    })
  }

  @Builder
  homeTopBarContent() {
    Row({ space: 8 }) {
      Column() {
        Text($r('app.string.app_name'))
          .id('homeMainTitle')
          .fontSize(25)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.accent())
          .maxLines(1)
          .translate({ y: this.syncState === '' ? 7 : 0 })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          });
        Text(this.syncLabel())
          .height(14)
          .fontSize(11)
          .lineHeight(14)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
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

      Row({ space: 8 }) {
        this.searchAction();
        this.topAction('sys.symbol.more', $r('app.string.cl_more_actions'), (): void => {
          this.moreMenuShown = true;
        });
      }
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  titleBarActions() {
    Stack({ alignContent: Alignment.Center }) {
      TopBarSlideContainer({
        content: (): void => { this.homeTopBarContent(); }
      });
      ForumTopHeaderBar();
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .clip(true);
  }

  syncLabel(): ResourceStr {
    if (this.syncState === 'connectionStateUpdating') { return $r('app.string.cl_refreshing'); }
    if (this.syncState === 'connectionStateWaitingForNetwork') { return $r('app.string.cl_waiting_network'); }
    if (this.syncState === '') { return ''; }
    return $r('app.string.cl_connecting');
  }

  private scrollerFor(key: string): ListScroller {
    const hit = this.tabScrollers.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const made = new ListScroller();
    this.tabScrollers.set(key, made);
    return made;
  }

  private navBarMinWidth(): number {
    const min = splitNavMinWidth(this.screenW);
    return this.folderRailShown() ? Math.max(min, FOLDER_RAIL_NAV_MIN) : min;
  }

  private navBarMaxWidth(): number {
    return splitNavMaxWidth(this.screenW);
  }

  // 右栏最小宽度。原先写死 400：在 600–667vp 上它和左栏 40% 上限加起来超过
  // 窗口宽，两个约束打架、HdsNavigation 怎么裁决无文档。现在窄窗口下退成
  // 窗口的 60%，和 40% 上限正好拼满。
  private contentMinWidth(): number {
    return splitContentMinWidth(this.screenW);
  }

  // splitPlaceholder 收的是 ComponentContent，不是 @Builder 引用——直接传
  // this.xxx 那种写法编译不过（签名见 @hms.hds.hdsBaseComponent.d.ets:2485）。
  // 懒建一次：build 每帧都跑，在这里 new 就是每帧重建一棵子树。
  private placeholderContent(): ComponentContent<Object> {
    return this.splitPlaceholder.content(this.getUIContext(), wrapBuilder(splitPanePlaceholder));
  }

  // 夜间模式切换：右栏空态要整棵重建，见字段处的说明。
  private onAppDarkChanged(): void {
    this.splitPlaceholder.invalidate();
  }

  @Builder
  pill(spec: TabSpec, index: number) {
    Row({ space: 5 }) {
      Text(spec.title).fontSize(14)
        .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.selectedIndex === index ? COLOR_TAB_SELECTED : COLOR_TAB_UNSELECTED)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: this.folderTitleMaxWidth() });
      FolderChipBadge({
        badge: folderBadge(spec.key),
        selected: this.selectedIndex === index,
        plainTitle: spec.plainTitle
      });
    }
    .height(FOLDER_CHIP_HEIGHT)
    .padding({ left: 7, right: 7 })
    .borderRadius(FOLDER_CHIP_HEIGHT / 2)
    // 未选项只铺一层轻量 tint，不再各自叠模糊/材质；选中态由下层滑动胶囊表达。
    // 2026-10-30 试过摘掉这层底、让未选项直接压在玻璃条上：观感发空、可读性也差，
    // 用户当场让改回来。别再摘。
    // 2026-11-16 23:56：整排已经是一条轨道了，未选项不再各铺一层 25% 白底
    // （那层底正是"塑料感"的来源）。只留选中态由下层滑动胶囊表达。
    .backgroundColor(Color.Transparent)
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
          // 首次布点不滑：胶囊从 pillX=0 出发，动画的话会当着一屏人横穿过去。
          // 靠 pillAnimate 默认 false 保持不滑，这里什么也不用做（见
          // FOLDER_PILL_ANIMATE）。
          this.folderLayoutPending = false;
          this.moveIndicatorTo(index);
          this.keepOrRevealStrip();
        } else {
          this.moveIndicatorTo(index);
        }
      }
    })
    // 未读部分的读屏文案跟着角标子组件走（FolderChipBadge）：计数在旁路模型
    // 里，chip 这层的绑定读不到它的变化。
    .accessibilityText(spec.plainTitle)
    .onClick((): void => { this.selectFolder(index); });
  }

  private selectFolder(index: number): void {
    this.archivePaneOpen = false;
    this.hapticGestureStart = -1;
    if (index !== this.selectedIndex) { navigationHaptics.play('folder'); }
    if (AppStorage.get<boolean>(KEY_ACTIVE_FORUM_OPEN) === true) { closeForumDrawer(); }
    this.controller.changeIndex(index);
  }

  private folderRailShown(): boolean {
    return showSplitFolderRail(this.screenW, this.isSplitLayout(), this.folders.length);
  }

  @Builder
  verticalFolderRail() {
    List({ scroller: this.folderRailScroller, initialIndex: this.selectedIndex, space: 4 }) {
      ForEach(this.tabs(), (spec: TabSpec, index: number) => {
        ListItem() {
          Column({ space: 2 }) {
            Stack({ alignContent: Alignment.TopEnd }) {
              Row() {
                SymbolGlyph(folderSymbol(spec.iconName)).fontSize(22)
                  .fontColor([this.selectedIndex === index ? COLOR_TAB_SELECTED : COLOR_ICON_SECONDARY]);
              }.width('100%').height(30).justifyContent(FlexAlign.Center);
              FolderChipBadge({ badge: folderBadge(spec.key), selected: this.selectedIndex === index,
                plainTitle: spec.plainTitle });
            }.width('100%').height(30);
            Text(spec.title).fontSize(11).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center).fontColor(this.selectedIndex === index ? COLOR_TAB_SELECTED : COLOR_TAB_UNSELECTED);
          }
          .width('100%').height(66).justifyContent(FlexAlign.Center)
          .backgroundColor(this.selectedIndex === index ? COLOR_TAB_PILL_BG : Color.Transparent)
          .borderRadius(12)
          .id(`homeFolderRailItem-${spec.key}`)
          .accessibilityText(spec.plainTitle)
          .accessibilitySelected(this.selectedIndex === index)
          .onClick((): void => { this.selectFolder(index); });
        }
      }, (spec: TabSpec): string => JSON.stringify([spec.key, spec.iconName, spec.plainTitle]));
    }
    .id('homeFolderRail').width(FOLDER_RAIL_WIDTH).height('100%')
    .padding({ top: 6, bottom: 6, left: 4, right: 4 }).scrollBar(BarState.Off)
    .backgroundColor(this.homeChromeFill(this.surfaceGlassEpoch, this.appDark))
    .borderRadius(16).border({ width: this.surfaceGlass ? 0.5 : 0, color: GLASS_OUTLINE_COLOR }).clip(true)
    .onAppear((): void => { AppStorage.setOrCreate<number>(FOLDER_RAIL_INSET_KEY, FOLDER_RAIL_WIDTH + FOLDER_RAIL_GAP); })
    .onDisAppear((): void => { AppStorage.setOrCreate<number>(FOLDER_RAIL_INSET_KEY, 0); });
  }

  @Builder
  archivePaneHeader() {
    Row({ space: 8 }) {
      this.topAction('sys.symbol.chevron_left', $r('app.string.back'), (): void => { this.archivePaneOpen = false; });
      Text($r('app.string.ap_title')).fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }.id('archivePaneHeader').width('100%').height(TOP_BAR_HEIGHT).padding({ left: 8, right: 16 });
  }

  private onSplitModeChanged(): void {
    if (this.archivePaneOpen && !this.isSplitLayout()) { this.archivePaneOpen = false; }
  }

  private openArchive(): void {
    if (this.isSplitLayout()) {
      closeForumDrawer();
      this.archivePaneOpen = true;
    } else {
      navigateToArchive();
    }
  }

  @Builder
  conversationPanelHeader() {
    Column() {
      if (this.archivePaneOpen) {
        this.archivePaneHeader();
      } else if (this.isSplitLayout()) {
        this.titleBarActions();
      }
      if (this.newSessionCount > 0) {
        NewSessionBanner({ count: this.newSessionCount });
      }
      if (this.folders.length > 0 && !this.folderRailShown()) {
        this.tabBar();
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  tabBar() {
    Column() {
      // 文件夹与列表共用面板底色，选中项单独保留强调色。
      Stack() {
        Scroll(this.tabScroller) {
          Stack({ alignContent: Alignment.TopStart }) {
            // Sliding selection pill behind the labels — follows the finger
            // during Tabs content swipes. 独立组件 + AppStorage 旁路，拖动每帧
            // 只脏它自己（见 FOLDER_PILL_X 的说明）。
            FolderPill({ accent: this.accent() });
            // 间距只放在标签之间，末项不留尾部空白，居中与滚动终点才对称。
            Row({ space: 6 }) {
              ForEach(this.tabs(), (spec: TabSpec, index: number) => {
                this.pill(spec, index);
              }, (spec: TabSpec) => spec.key);
            }.padding({ left: 0, right: 0 }).height(FOLDER_BAR_HEIGHT);
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        // 装得下就居中（#156）；超宽时 Scroll 从左起排、照常横向滚动。指示胶囊
        // 与文字在同一个 Stack 里，坐标随内容一起平移，不用另算偏移。
        .align(Alignment.Top)
        .width('100%')
        .height('100%')
        .padding({ left: 6, right: 6 })
        .onTouch((event: TouchEvent): void => {
          if (event.type === TouchType.Down) {
            this.stripUserMoved = true;
            this.railPressed = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.railPressed = false;
          }
        })
        .onDidScroll((): void => {
          const cur: OffsetResult | undefined = this.tabScroller.currentOffset();
          if (cur !== undefined) {
            this.stripOffsetX = cur.xOffset;
          }
        })
        .onAreaChange((_old: Area, area: Area) => {
          this.tabViewW = area.width as number;
          this.keepOrRevealStrip();
        });
      }
      .width('100%')
      .height(FOLDER_BAR_HEIGHT)
      .clip(true)
      // 保留文件夹文字/指示器的按压反馈，不改变面板尺寸。
      .scale({ x: this.railPressed ? 0.985 : 1, y: this.railPressed ? 0.985 : 1 })
      .opacity(this.railPressed ? 0.92 : 1)
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
        curve: Curve.EaseOut
      });
    }
    .width('100%')
    .padding({ left: 1, right: 1 });
  }

  private homeChromeFill(_epoch: number, _dark: boolean): ResourceColor {
    return this.surfaceGlass ? surfaceGlassFill($r('app.color.surface')) : $r('app.color.surface');
  }

  private pinnedSystemBar(): SystemBarStyle | undefined {
    if (this.statusFollowTitle) {
      // No native title remains to supply its accent to HDS.
      return { statusBarContentColor: this.appearanceEpoch >= 0 ? currentAccentHex() : '#000000' } as SystemBarStyle;
    }
    return { statusBarContentColor: this.appDark ? '#FFFFFF' : '#000000' } as SystemBarStyle;
  }

  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private isSplitLayout(): boolean {
    return isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait);
  }

  // 分栏时按钮位于卡片内，菜单锚点也要算上卡片的右边距。
  private moreMenuRightInset(): number {
    if (this.navBarW <= 0 || this.navBarW >= this.screenW) {
      return 8;
    }
    return this.screenW - this.navBarW + 8 + (this.isSplitLayout() ? homeCardMarginVp(this.widthBp) : 0);
  }

  private splitOpenChatId(): number {
    return isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait)
      ? this.openChatId : 0;
  }

  @Builder
  conversationTabs() {
    Stack({ alignContent: Alignment.TopStart }) {
      Tabs({ controller: this.controller }) {
        ForEach(this.tabs(), (spec: TabSpec) => {
          TabContent() {
            // TabContent centers a content-sized child, so a short chat list
            // (few chats / a small folder) would float in the vertical middle.
            // A definite full-height Column pins the list to the top and lets
            // the body's layoutWeight(1) actually stretch.
            Column() {
              if (spec.key === 'main') {
                MainTabBody({
                  onOpenArchive: (): void => { this.openArchive(); },
                  openChatId: this.splitOpenChatId(),
                  contentTopInset: 0,
                  continuousPanel: true,
                  listScroller: this.scrollerFor(spec.key),
                  effectsActive: !this.archivePaneOpen && this.tabEffectsActive(spec.key),
                  imagesActive: !this.archivePaneOpen && this.tabVisualsActive(spec.key),
                  updatesActive: !this.archivePaneOpen && this.tabUpdatesActive(spec.key)
                }).layoutWeight(1).visibility(this.archivePaneOpen ? Visibility.None : Visibility.Visible);
                if (this.archivePaneOpen) {
                  ChatListView({
                    listKey: 'archive', continuousPanel: true, openChatId: this.splitOpenChatId(),
                    effectsActive: this.tabEffectsActive(spec.key), imagesActive: this.tabVisualsActive(spec.key),
                    updatesActive: this.tabUpdatesActive(spec.key)
                  }).layoutWeight(1);
                }
              } else {
                ChatListView({
                  openChatId: this.splitOpenChatId(),
                  listKey: spec.key,
                  contentTopInset: 0,
                  continuousPanel: true,
                  listScroller: this.scrollerFor(spec.key),
                  effectsActive: this.tabEffectsActive(spec.key),
                  imagesActive: this.tabVisualsActive(spec.key),
                  updatesActive: this.tabUpdatesActive(spec.key)
                }).layoutWeight(1);
              }
            }
            .width('100%').height('100%')
            .clip(true)
          }
          .clip(true)
        }, (spec: TabSpec) => spec.key);
      }
      .barHeight(0)
      // 保活封顶（见 TAB_KEEP_RANGE 的说明）。被释放页签的列表位置由
      // ChatListView/MainTabBody 记在 util/chatListPosition，重建时恢复。
      .cachedMaxCount(TAB_KEEP_RANGE, TabsCacheMode.CACHE_BOTH_SIDE)
      // 远距离 chip 点击/changeIndex 不再横扫中间页签：保活封顶后沿途页签是
      // 已释放的，默认动画会在首帧把它们全部重建（Frame 录制实测 9 个
      // TabContent 一帧 536ms）。WITH_JUMP 只建目标页，无动画跳到近旁后只播
      // 最后一小段。手势滑页不受影响（本来就只跨邻居）。
      .animationMode(AnimationMode.CONTENT_FIRST_WITH_JUMP)
      .animationDuration(powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION))
      .onAreaChange((_old: Area, area: Area) => {
        this.tabsWidth = area.width as number;
      })
      // Content swipe in progress: convert the swipe offset into a fractional
      // tab position so the selection pill tracks the finger continuously.
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        if (this.hapticGestureStart < 0) { this.hapticGestureStart = index; }
        // 手指还在页签上拖：这一帧本来就紧，别让排好的预载凑热闹。
        this.cancelTabPreload();
        this.tabAnimationActive = true;
        const companionIndex: number = event.currentOffset > 0 ? index - 1 : index + 1;
        if (companionIndex >= 0 && companionIndex < this.tabs().length &&
          this.companionImageTabIndex !== companionIndex) {
          this.companionImageTabIndex = companionIndex;
        }
        if (this.tabsWidth > 0 && !this.folderRailShown()) {
          // 拖动期间关掉胶囊的隐式动画：每帧一个新目标再配 250ms 缓动，胶囊会
          // 一直追着手指屁股后面跑，而不是贴着手指走。
          this.setPillAnimate(false);
          this.moveIndicatorTo(index - event.currentOffset / this.tabsWidth);
        }
      })
      // Finger released / tab tapped: settle the pill on the target tab and
      // scroll the strip if that tab sits outside the visible range.
      .onAnimationStart((_index: number, targetIndex: number) => {
        this.finishFolderHaptic(targetIndex);
        this.cancelTabPreload();
        if (_index !== targetIndex && AppStorage.get<boolean>(KEY_ACTIVE_FORUM_OPEN) === true) {
          closeForumDrawer();
        }
        // 省电设置可能把动画压到 0；这时 SDK 不触发 onAnimationEnd，onChange
        // 会直接走下面的无动画兜底。
        this.tabAnimationActive =
          powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION) > 0;
        this.companionImageTabIndex = this.tabAnimationActive ? _index : -1;
        this.folderLayoutPending = false;
        this.appliedFolder = targetIndex;
        this.selectedIndex = targetIndex;
        // 松手落定：胶囊从拖动最后的那个分数位置滑到目标 chip。先把拖动期间关掉的
        // 滑过去动画打开（见 FOLDER_PILL_ANIMATE）。
        this.setPillAnimate(true);
        this.moveIndicatorTo(targetIndex);
        this.revealTab(targetIndex);
      })
      .onAnimationEnd((_index: number) => {
        this.finishFolderHaptic(_index);
        this.tabAnimationActive = false;
        const companionKey: string | undefined = this.tabs()[this.companionImageTabIndex]?.key;
        if (companionKey !== undefined && this.warmedVisualTabKeys.indexOf(companionKey) < 0) {
          this.warmedVisualTabKeys = [...this.warmedVisualTabKeys, companionKey];
        }
        this.companionImageTabIndex = -1;
        if (this.unreadRefreshPending) {
          this.refreshUnread([]);
        }
        this.scheduleTabPreload(TAB_PRELOAD_AFTER_SETTLE_MS);
      })
      .onChange((index: number) => {
        this.finishFolderHaptic(index);
        // onAnimationStart already drives animated changes. Avoid starting the
        // same settle animation twice when onChange fires at the end.
        const switched: boolean = this.selectedIndex !== index;
        if (switched) {
          if (AppStorage.get<boolean>(KEY_ACTIVE_FORUM_OPEN) === true) {
            closeForumDrawer();
          }
          this.appliedFolder = index;
          this.selectedIndex = index;
          // 点 chip 切页（onAnimationStart 没跑到）时的同一条路：打开滑过去。
          this.setPillAnimate(true);
          this.moveIndicatorTo(index);
        } else {
          this.moveIndicatorTo(index);
        }
        // 下标没变的 onChange（列表刷新时 Tabs 可能补发一次）不能把横条拽回去。
        if (switched) {
          this.revealTab(index);
        } else {
          this.keepOrRevealStrip();
        }
        // 无动画 changeIndex / 省电关闭动画时没有 onAnimationEnd，在这里兜底。
        // 正常动画仍由 onAnimationEnd 排，避免重复改写计时器。
        if (!this.tabAnimationActive) {
          this.companionImageTabIndex = -1;
          if (this.unreadRefreshPending) {
            this.refreshUnread([]);
          }
          this.scheduleTabPreload(TAB_PRELOAD_AFTER_SETTLE_MS);
        }
      })
      .width('100%').height('100%')
      .clip(true);

      ForumSplitView({ navBarVisible: this.navBarVisible });
    }
    .width('100%')
    .height('100%')
    .clip(true);
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      HdsNavigation(this.chatStack) {
        Column() {
          if (!this.isSplitLayout()) {
            this.titleBarActions();
          }
          Row({ space: FOLDER_RAIL_GAP }) {
            if (this.folderRailShown()) {
              this.verticalFolderRail();
            }
            HomeConversationPanel({
              header: (): void => { this.conversationPanelHeader(); },
              content: (): void => { this.conversationTabs(); }
            }).layoutWeight(1);
          }
          .padding({ left: homeCardMarginVp(this.widthBp), right: homeCardMarginVp(this.widthBp) })
          .width('100%').layoutWeight(1);
        }
        .width('100%').height('100%')
        .padding({
          top: this.topSafe,
          bottom: homeCardBottomMarginVp(this.widthBp, this.bottomSafe)
        })
        .onAreaChange((_old: Area, area: Area): void => {
          // Measure the full navigation pane, not the inset Tabs viewport.
          const paneWidth: number = Number(area.width);
          if (paneWidth > 0 && AppStorage.get<number>(NAV_BAR_WIDTH_KEY) !== paneWidth) {
            AppStorage.setOrCreate<number>(NAV_BAR_WIDTH_KEY, paneWidth);
            rememberSplitNavWidth(paneWidth,
              isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait),
              this.navBarMinWidth(), this.navBarMaxWidth());
          }
        });
      }
      // Retain the independent status-bar color preference with the custom header.
      .systemBarStyle(this.pinnedSystemBar(), this.pinnedSystemBar())
      // 一级页签，没有返回键。
      .hideBackButton(true)
      // Explicit breakpoints keep landscape phones in one column.
      .mode(this.isSplitLayout() ? NavigationMode.Split : NavigationMode.Stack)
      // 分栏下查看器开着：Split + hideNavBar(true) 的实际效果是单栏，右栏会话页铺满窗口（#201）。
      .hideNavBar(this.viewerHidesNavBar())
      .navBarWidthRange({ minWidth: this.navBarMinWidth(), maxWidth: this.navBarMaxWidth() })
      // 启动时复原上次拖出来的宽度；首次进入时取窗口宽的 40%。
      .navBarWidth(resolveSplitNavWidth(this.savedNavW, this.navBarMinWidth(), this.navBarMaxWidth()))
      // 右栏栈空时的占位。仅分栏模式展示，手机单栏下永不出现。
      .splitPlaceholder(this.placeholderContent())
      .minContentWidth(this.contentMinWidth())

      .onNavBarStateChange((isVisible: boolean): void => {
        this.applyNavBarVisible(isVisible);
      })
      .enableDragBar(true)
      // 关掉全模态联动：默认 true 时，bindSheet 一拉起就会触发栈顶
      // HdsNavDestination 的 onHidden。ChatPage 的 onPageHide 挂着「立刻停播放位」，
      // 而它自己就有 showForwardSheet / showReactionSheet 两个全模态——联动打开
      // 的话，一开转发面板音视频就停了，这是迁移前没有的行为。
      .attributeModifier(SHEET_LIFECYCLE_MODIFIER)
      .hideTitleBar(true, false)
      // The header stays fixed; no HDS scroll filter or title collapse.
      .bindToScrollable([])
      .width('100%').height('100%')
      // 背景色是 expandSafeArea 真正延伸出去的东西——只写 expandSafeArea 而不画
      // 背景，延伸的是"什么都没有"，状态栏底下露的就是窗口底色（实测深色模式
      // 下那是一条纯黑）。
      // 壁纸生效时整页底必须透明，否则壁纸被这一层盖死（见 util/theme.mainPageFill）。
      .backgroundColor(mainPageFill(this.appWallpaperOn));

      // ⋮ 菜单的锚点：零尺寸，只为让菜单弹在右上角。HDS 的菜单项给不了
      // bindMenu，只能这样把两者接起来。
      Row()
        .width(1).height(1)
        .margin({ top: this.topSafe + 44, right: this.moreMenuRightInset() })
        .bindMenu(this.moreMenuShown, this.moreMenu, {
          systemMaterial: overlayMaterial('menu'),
          onDisappear: (): void => { this.moreMenuShown = false; }
        });
    }
    .width('100%').height('100%');
  }
}

@Component
struct TopBarSlideContainer {
  @BuilderParam content: () => void = this.emptyBuilder;
  @StorageProp(KEY_ACTIVE_FORUM_OPEN) private forumDrawerOpen: boolean = false;
  @StorageProp(NAV_BAR_WIDTH_KEY) private navBarW: number = 0;
  @StorageProp('screenWidthVp') private screenW: number = 360;

  @Builder
  emptyBuilder() {}

  private slideWidth(): number {
    return this.navBarW > 0 ? this.navBarW : this.screenW;
  }

  build() {
    Row() {
      this.content();
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .enabled(!this.forumDrawerOpen)
    .hitTestBehavior(this.forumDrawerOpen ? HitTestMode.None : HitTestMode.Default)
    .translate({ x: this.forumDrawerOpen ? -this.slideWidth() : 0 })
    .animation({
      duration: powerAnimationDuration(
        KEY_POWER_SMOOTH_TRANSITIONS,
        this.forumDrawerOpen ? FORUM_DRAWER_OPEN_MS : FORUM_DRAWER_CLOSE_MS
      ),
      curve: Curve.FastOutSlowIn
    });
  }
}

// 滑动选中胶囊。位置/宽度从 ChatListPage 的 @State 旁路成 AppStorage 通道
// （见 FOLDER_PILL_X 的说明）：拖动页签时 moveIndicatorTo 每帧更新，脏区
// 只有这一个组件，不再整页 ExecuteRerender。
@Component
struct FolderPill {
  // 选中胶囊的强调色（跟随「自定义强调色」）。2026-11-17 00:24 用户要求选中态
  // 必须能看见淡色底，而材质在本机会把底色吃掉，所以由这里传进来单独盖一层。
  @Prop accent: ResourceColor = COLOR_TAB_PILL_BG;
  @StorageProp(FOLDER_PILL_X) pillX: number = 0;
  @StorageProp(FOLDER_PILL_W) pillW: number = 0;
  // 这一帧要不要"滑过去"（见 FOLDER_PILL_ANIMATE）。
  @StorageProp(FOLDER_PILL_ANIMATE) private pillAnimate: boolean = false;
  build() {
    Row()
      .width(this.pillW).height(FOLDER_CHIP_HEIGHT)
      .borderRadius(FOLDER_CHIP_HEIGHT / 2)
      .backgroundColor(this.accent)
      .opacity(0.26)
      .hitTestBehavior(HitTestMode.None)
      .position({ x: this.pillX, y: (FOLDER_BAR_HEIGHT - FOLDER_CHIP_HEIGHT) / 2 })
      // Drag follows the finger immediately; tap/settle animates the same node.
      .animation(this.pillAnimate
        ? {
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION),
          curve: Curve.EaseOut
        }
        : { duration: 0 });
  }
}

// 单个页签的未读角标。@ObjectLink 订阅自己的计数模型（util/folderBadges），
// 计数变化只重渲染这一个角标；无未读时不渲染任何节点。未读的读屏文案也在
// 这层：chip 的绑定读不到旁路模型的变化。
@Component
struct FolderChipBadge {
  @ObjectLink badge: FolderBadge;
  @Prop selected: boolean = false;
  @Prop plainTitle: string = '';

  build() {
    if (this.badge.count > 0) {
      // 单 Text 画角标胶囊（同 ChatRow 的未读角标），不套无属性 Row。
      Text(badgeLabel(this.badge.count, TAB_BADGE_MAX))
        .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium)
        .constraintSize({ minWidth: 16 })
        .height(16).padding({ left: 4, right: 4 })
        .align(Alignment.Center).textAlign(TextAlign.Center)
        // 全静音的角标压暗一档（COLOR_BADGE_BG 本就是灰底，靠透明度区分）。
        .backgroundColor(this.selected ? COLOR_TAB_SELECTED : COLOR_BADGE_BG)
        .opacity(this.badge.hasUnmuted ? 1 : 0.55)
        .borderRadius(8)
        .accessibilityText(str('cl_tab_unread_a11y', this.plainTitle,
          badgeLabel(this.badge.count, TAB_BADGE_MAX)));
    }
  }
}
