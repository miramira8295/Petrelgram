import { navigateToSetting } from '../../util/settingsNav';
import { NewSessionBanner, NEW_SESSION_BAR_HEIGHT } from './NewSessionBanner';
import { common } from '@kit.AbilityKit';
import { TelegramQrScanner } from '../../services/TelegramQrScanner';
import { SCOPE_MUTE_EPOCH } from '../../store/ScopeMuteStore';
import { chatListInForeground, chatListPageCanRun } from './ChatListFreeze';
import { KEY_IMMERSIVE_BARS_HIDDEN } from '../../util/immersiveBars';
import { effectiveChatDepth, KEY_CHAT_DETAIL_SHOWN } from '../../util/navBarReset';
import {
  BreakpointType, HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WINDOW_PORTRAIT, KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM,
  isSmallSquare, isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { UnreadBadgeCounts } from '../../util/unreadBadgeRule';
import { chatListSyncState } from '../../util/syncState';
import { flushPendingNavs } from '../../util/pendingNavFlush';
import { getSessionSecurityStore, getFolderStore, getUnreadCountStore, getChatStore, getConnectionState, getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { FolderInfo } from '../../store/FolderStore';
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
import { ComponentContent, FrameCallback, LengthMetrics, componentUtils } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { homeCardMarginVp } from '../../util/pageMargin';
import { APPEARANCE_EPOCH, KEY_STATUS_FOLLOW_TITLE } from '../../util/appearance';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_BADGE_BG, COLOR_TAB_PILL_BG } from '../../util/theme';
import { router } from '@kit.ArkUI';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration, KEY_SPLIT_NAV_WIDTH, KEY_FORCE_SINGLE_COLUMN,
  KEY_FOLDER_BAR_SCROLL_HIDE
} from '../../store/AppSettings';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import {
  overlayBackdropBlur, overlayGlassFill, overlayMaterial, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';
import { navigateToChat } from '../../util/chatNav';
import { logE } from '../../util/log';
import { nextTabPreloadIndex, pruneBuiltKeys } from '../../util/tabPreload';
import { FolderBadge, badgeLabel, folderBadge, setFolderBadge } from '../../util/folderBadges';
import {
  FolderBarCollapseState, expandedFolderBar, folderBarForceExpand, folderDragReveals, nextFolderBarCollapse
} from '../../util/folderBarCollapse';
import { registerStack, NavStackLike } from '../../util/navStacks';
import { splitNavMinWidth, splitNavMaxWidth, splitContentMinWidth } from '../../util/splitMetrics';
import { mainBarFill, mainPageFill } from '../../util/theme';
import { KEY_APP_BG_ON } from '../../store/AppSettings';
import { SHEET_LIFECYCLE_MODIFIER } from '../../util/navSheetLifecycle';
import { SplitPlaceholderHolder } from '../../util/splitPlaceholderHolder';
import { KEY_APP_DARK } from '../../util/theme';
import { navBarVisibleOnAppear, navBarVisibleOnChange } from '../../util/navBarReset';
import { KEY_CHAT_VIEWER_COVERS_WINDOW } from '../../util/viewerWindowCover';
import { navigateToSearch } from '../../util/searchNav';
import {
  requestChatListFlush, setChatListRenderActive
} from '../../util/chatListRenderGate';
import { rememberSplitNavWidth, resolveSplitNavWidth } from '../../util/splitNavWidth';

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
const TOP_ACTION_SIZE: number = 40;
const TAB_BADGE_MAX: number = 99;
const FOLDER_BAR_HEIGHT: number = 36;
// 文件夹条连同它自己的上下留白占的高度（列表让位用）。
const FOLDER_BAR_SPACE: number = 42;
// 文件夹项与选中指示器共用这一个高度。未选项不再各画一块玻璃，只让滑动
// 指示器托住当前项，避免“外层横条 + 一排胶囊 + 会话卡片”叠出三层容器。
const FOLDER_CHIP_HEIGHT: number = 28;
const FOLDER_SWITCH_DURATION: number = 250;
// 收起态（见 util/folderBarCollapse）：整条横条缩成标题底下的一小块，只留当前
// 文件夹。高度比展开态小一圈，配合 bottomBuilder 的高度动画就是"落下来放大 /
// 收上去缩小"那一下。缩略块本身比展开态的 chip 再矮一点，免得看着像没动。
// 2026-10-30 用户要求再缩一点（22 → 20，字号 12 → 11、左右内边距 6 → 5）。
const FOLDER_COLLAPSED_CHIP_HEIGHT: number = 20;
// 连同上下的留白，供 bottomBuilder 高度与列表让位使用。展开态 36+6=42，这里
// 同样留 6 的余量。
// 收起态横条整条让出去（缩略块画在标题栏外面，见 collapsedFolderChip），
// 列表因此多出这一整段。展开态还是 42。
const FOLDER_COLLAPSED_SPACE: number = 0;
// 收起态缩略块贴住主标题右下角的间距（vp）：横向离标题文字末端多远、纵向
// 从文字底部往下压多少——压一点才会看着是"挂在字母右下边"而不是另起一行。
// 横向几乎不留缝：量到的是标题**文本框**，本身就比字形宽一截（字距、行尾），
// 再额外加就会离得太远。
const FOLDER_CHIP_GAP_X: number = 2;
// 缩略块按**底边**对齐主标题文字的底边。量到的是文本框，它的底边比字形底部
// 多出这一段 descent，不减掉胶囊就会整个往下坠一截。数值由真机截图反推
// （文本框底 91vp、字形底 85vp）。这是字体盒子的**事实**，别拿它当设计参数调。
const FOLDER_CHIP_TEXT_DESCENT: number = 6;
// 缩略块相对"按文本框底边推算的位置"再往下沉多少。和上面的 descent 分开写：
// 一个是从截图量出来的、不会变的量，一个是纯观感，要挪只动这一个数。
// 【2026-10-30 收尾：按字形底边对齐】药丸撤掉之后参照物只剩字形，于是对着当前
// 装机版本重新逐像素量了一遍：「Petrel」的 P 底边在 y=263px，「所有」底边在
// y=279px，差 16px≈5.4vp。9 − 5.4 ≈ 3.6，取 4（残留 1px，肉眼看就是齐平）。
// 之前那些档（10 / 7 / 8 / 9）都是在还有药丸底色的版本上调的，那一版比的是
// 块的边而不是字形，所以这些数**不能直接沿用**，只能作为"曾经调到过哪"的记录。
const FOLDER_CHIP_DROP_Y: number = 4;
// 收起态缩略块与主标题之间的那条竖线（2026-10-30 用户要求"用竖线分割开"）。
// 竖线画在**胶囊外面**，不借胶囊的实色底板，所以颜色要自己给。**不能用
// `app.color.divider`**：它在深色下是 #101921，压在同为深色的标题栏上等于没有
// （用户当场指出深色下颜色不对）。改用自带明暗两档的半透明线，写法和
// ChatHeader 那几处分隔线一致。
const FOLDER_CHIP_DIVIDER_WIDTH: number = 1;
// 16 = 比胶囊(20)略矮，两头各留 2，跟着胶囊中线居中。12 那档用户嫌太短。
const FOLDER_CHIP_DIVIDER_HEIGHT: number = 16;
const FOLDER_CHIP_DIVIDER_LIGHT: string = '#26000000';
const FOLDER_CHIP_DIVIDER_DARK: string = '#33FFFFFF';
// 竖线两侧各自的留白，同时也是收起态那层 Row 的 spacing。去掉药丸之前这里还有
// 一层 5vp 的内边距叠着（实际 10），撤掉药丸后就是这一个数说了算，2026-10-30 用户定的 7。
const FOLDER_CHIP_DIVIDER_GAP: number = 7;
// 主标题的组件 ID。HDS 的标题栏没有"标题右侧"槽位（stackBuilder / bottomBuilder
// 都是标题**下方**的一整条），收起态那块缩略只能画在标题栏外面，靠这个 ID 把
// 主标题的实际矩形量出来定位——见 ChatListPage.measureFolderChipAnchor。
const TITLE_MAIN_ID: string = 'homeMainTitle';
const FOLDER_BAR_COLLAPSE_DURATION: number = 220;
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
const CHAT_LIST_RETURN_SETTLE_MS: number = 640;

// The route table loads ChatPage dynamically. Queue its module graph immediately
// after the chat list's first frame instead of waiting a fixed 1200 ms: a quick
// tap could beat that timer and pay module evaluation inside the navigation
// frame. ChatPage statically imports ChatHeader, so resolving this import warms
// both modules. The process-wide guard also covers tab/page recreation.
let chatModuleWarmupStarted: boolean = false;

// 窗口尺寸/分栏宽度变了之后，等下一帧布局落定再重新量一次缩略块的锚点。
// 在 onWindowResized 里当场量会拿到变化前的矩形——那一次布局还没跑。
class FolderChipAnchorFrameCallback extends FrameCallback {
  // 拿组件本身而不是回调：缩略块的位置是页面自己的 @State，量完直接就是重绘。
  private owner: ChatListPage;

  constructor(owner: ChatListPage) {
    super();
    this.owner = owner;
  }

  onFrame(_frameTimeInNano: number): void {
    this.owner.measureFolderChipAnchor();
  }
}

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
// 框架自己上报的 navBar 可见性（未经我们按栈深修正）。整页 router 页退出来之后，
// 栈里会留下幽灵目的地，而这份上报反映的是 Navigation 此刻到底在铺 navBar 还是
// 铺目的地——dock 判据需要它当地面真值。
export const CHAT_NAV_BAR_REPORTED_KEY: string = 'chatNavBarReported';

// 分栏且右栏栈空时的占位。官方明确它仅在分栏模式下展示、不受路由栈管理、
// 不可获焦、不响应事件，是纯展示层；单栏模式（手机）下永远不出现。
//
// 写成模块级函数而不是 struct 里的 @Builder 成员：splitPlaceholder 收的是
// ComponentContent，要 wrapBuilder() 包一层，而 wrapBuilder 只接全局 @Builder。
@Builder
function splitPanePlaceholder(): void {
  Column({ space: 12 }) {
    // 用开屏页那架**蓝色**飞机，不是启动图标的前景层（issue #113）。前景层是
    // 白色的，压在 45% 透明度下几乎看不见——报告人说的就是这个。
    // ic_split_placeholder 是从 start_splash.png 居中裁出来的那一块，同一架飞机。
    Image($r('app.media.ic_split_placeholder'))
      .width(72).height(72).opacity(0.9)
      .draggable(false);
    Text($r('app.string.split_pick_a_chat'))
      .fontSize(14)
      .fontColor(COLOR_TEXT_SECONDARY);
  }
  .width('100%').height('100%')
  .justifyContent(FlexAlign.Center)
  .backgroundColor($r('app.color.page_bg'));
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
  // TDLib connection state as a small status hint beside the title
  // ('' when connectionStateReady — nothing shown).
  // The connection state itself, not its label. Keeping the token rather than
  // the rendered text lets the Text below hold a Resource, so the label follows
  // a language switch without waiting for the next connection update.
  @State syncState: string = '';
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // navBar 的实际宽度（onAreaChange 里写进 AppStorage 的那个值）。⋮ 菜单的锚点
  // 要按它定位：分栏时外层 Stack 横跨两栏，按 TopEnd 对齐会把菜单弹到右栏
  // 聊天页的右上角去（issue #146）。
  @StorageProp(NAV_BAR_WIDTH_KEY) private navBarW: number = 0;
  @StorageProp('screenWidthVp') @Watch('onWindowResized') screenW: number = 360;
  // 设置里的「强制单栏」（宽屏也当手机用）。
  @StorageProp(KEY_FORCE_SINGLE_COLUMN) forceSingleColumn: boolean = false;
  // 分栏下会话页的媒体查看器开着：收左栏，让右栏里的查看器盖满窗口（见 util/viewerWindowCover）。
  // 复用 onWindowResized：它按定义重算 navBar 可见性，这里只是多了一个输入。
  @StorageProp(KEY_CHAT_VIEWER_COVERS_WINDOW) @Watch('onWindowResized') viewerCoversWindow: boolean = false;
  // 分栏判据读系统横向 + 纵向断点（util/layoutBreakpoint.isSplitByBreakpoint）——只看宽的话
  // 手机一转横屏就被当成平板（#125）。
  @StorageProp('screenHeightVp') @Watch('onWindowResized') screenH: number = 780;
  // 系统断点（util/layoutBreakpoint）：分栏判据读它，不再按窗口宽高自己算。
  @StorageProp(KEY_WIDTH_BREAKPOINT) widthBp: number = WIDTH_BP_SM;
  @StorageProp(KEY_HEIGHT_BREAKPOINT) heightBp: number = HEIGHT_BP_LG;
  @StorageProp(KEY_WINDOW_PORTRAIT) windowPortrait: boolean = true;
  // 小方形屏上滑时隐藏标题栏（SPEC-04，写入方是 MainTabBody 的滚动回调）。
  @StorageProp(KEY_IMMERSIVE_BARS_HIDDEN) immersiveHidden: boolean = false;
  // 文件夹条是否收成了标题底下那一小块（util/folderBarCollapse，2026-10-30）。
  // 参与渲染（bottomBuilder 高度 + 横条/缩略块的切换），所以是 @State。
  @State private folderBarCollapsed: boolean = false;
  // 「列表滑动隐藏文件夹」开关（设置 → 交互设置，默认开）。订阅放这里而不是
  // 滚动回调里每次现读：用户可能正收着横条去改设置，回到首页不该还得先滚一下
  // 才展开。@Watch 见 onFolderBarScrollHideChanged。
  @StorageProp(KEY_FOLDER_BAR_SCROLL_HIDE) @Watch('onFolderBarScrollHideChanged')
  private folderBarScrollHide: boolean = true;
  // 状态机本体。累计量每帧都在变，做成 @State 就是每帧一次整页重绘——它不参与
  // 渲染，普通字段即可；真正要重绘的只有 collapsed 翻面那一次。
  private folderBarState: FolderBarCollapseState = expandedFolderBar();
  // 收起态横拖切换文件夹：拖动期间整条展开（让用户看见自己在切哪一项），
  // 松手回缩。**单独一个字段而不是直接改状态机**：拖动不属于"滚动"，一旦把它
  // 揉进累计量，松手后的回缩就得再伪造一次滚动。
  private folderBarDragReveal: boolean = false;
  // 收起态缩略块的绝对位置（vp，相对外层 Stack）。
  @State private folderChipX: number = 0;
  @State private folderChipY: number = 0;
  // 量到过一次就不再量：主标题的矩形只在窗口尺寸变化时才会变（见 onWindowResized）。
  private folderChipAnchored: boolean = false;
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
  private navBarVisible: boolean = true;
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
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;

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
    if (this.selectedIndex !== this.appliedFolder) {
      this.appliedFolder = this.selectedIndex;
      this.controller.changeIndex(this.selectedIndex);
    }
  }

  // 横条手动滑过的位置。用户的反馈：手指滑到一半，列表一有更新（未读数变、标题栏
  // 重建、横条短暂离树再回来）横条就被拽回「选中的那个可见」的位置——期望手指
  // 滑到哪就停在哪。所以：手指碰过横条之后，布局变化一律原地恢复到用户的位置；
  // 只有真正切换了分组，才自动滚到新选中的那个（revealTab）。
  private stripUserMoved: boolean = false;
  private stripOffsetX: number = 0;

  // 切换了分组：滚到新选中的那个，忘掉用户之前滑到的位置。
  private revealTab(index: number): void {
    this.stripUserMoved = false;
    this.ensureTabVisible(index);
  }

  // 布局变了（不是换分组）：用户滑过就原地恢复，没滑过照旧让选中的可见。
  private keepOrRevealStrip(): void {
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
  private applyNavBarVisible(isVisible: boolean): void {
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
    // 窗口/分栏变了，主标题的位置也变了，缩略块的锚点得重量。缩略块正显示着
    // 的时候必须马上补量，否则它会停在上一个窗口的位置上，直到下次收起。
    this.folderChipAnchored = false;
    if (this.folderBarCollapsed) {
      this.getUIContext().postFrameCallback(new FolderChipAnchorFrameCallback(this));
    }
    this.applyNavBarVisible(navBarVisibleOnAppear(
      isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait),
      effectiveChatDepth(this.chatStack.size(), this.chatDetailShown())) &&
      !this.viewerHidesNavBar());
  }

  // 会话详情页是否真的在屏上（由 ChatPage 的 onShown/onHidden 写）。栈里留着
  // 一条记录但详情页已经不在屏上时，栈深不可信，见 util/navBarReset。
  private chatDetailShown(): boolean {
    return AppStorage.get<boolean>(KEY_CHAT_DETAIL_SHOWN) ?? true;
  }

  // 只在分栏时生效：单栏（手机）下 navBar 本来就被会话页整页盖住，不需要这一手。
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
    // 栈没注册时被挂起的跳转（冷启动点通知、登录前的深链）在这里放出去。
    // **延一拍**：官方明确"不建议在 aboutToAppear 中操作栈，此时页面还未构建
    // 完成"，而这里正是 aboutToAppear。见 util/pendingNav 的事故说明。
    setTimeout((): void => { flushPendingNavs('chat'); }, 0);
    // 复位一次再挂树。**复位值取自栈的真实状态，不能一律写 true。**
    //
    // 需要复位是因为 onNavBarStateChange 只在**变化**时触发，不会在页面重建时
    // 补一发——上一轮（退登/换账号）留下的 false 会让 dock 永久藏着。
    //
    // 但原来那句「本页刚建好时栈必然是空的」在整页 router 跳转下不成立：应用内
    // 浏览器（pages/web/InAppBrowserPage）是整页 router 页，从聊天详情里打开再
    // 返回时这棵树会重建、aboutToAppear 再跑一次，而页签栈还压着详情页。无条件
    // 写 true 就把 dock 放了出来，和输入框叠在一起（用户报的正是这个）。
    // 判据见 util/navBarReset。
    this.navBarVisible = navBarVisibleOnAppear(
      isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait),
      effectiveChatDepth(this.chatStack.size(), this.chatDetailShown()));
    AppStorage.setOrCreate<boolean>(CHAT_NAV_BAR_VISIBLE_KEY, this.navBarVisible);
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

  private startClock(): void {
    if (!chatListPageCanRun(this.pageActive, this.navBarVisible) || !this.listRenderActive) { return; }
    AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    if (this.clockTimer !== -1) {
      return;
    }
    this.clockTimer = setInterval((): void => {
      if (chatListPageCanRun(this.pageActive, this.navBarVisible) && this.listRenderActive) {
        AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
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
      specs.push({ key: `folder:${f.id}`, title: f.title, plainTitle: f.title });
    }
    const position = Math.max(0, Math.min(specs.length, this.mainListPosition));
    specs.splice(position, 0, {
      key: 'main', title: $r('app.string.cl_all'), plainTitle: str('cl_all')
    });
    return specs;
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
        .onClick((): void => { this.qrScanner.start(getContext(this) as common.UIAbilityContext); });
      MenuItem({ content: $r('app.string.settings_proxy') })
        .onClick((): void => { navigateToSetting('ProxyPage'); });
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
  topAction(icon: string, label: Resource, onTap: () => void) {
    Row() {
      SymbolGlyph($r(icon)).fontSize(23).fontColor([COLOR_ICON_SECONDARY]);
    }
    .width(TOP_ACTION_SIZE).height(TOP_ACTION_SIZE)
    .borderRadius(TOP_ACTION_SIZE / 2)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(overlayGlassFill('control', $r('app.color.surface_alt')))
    .backdropBlur(overlayBackdropBlur('control'))
    .attributeModifier(materialModifierWhen('control', this.materialEpoch >= 0))
    .clip(true)
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
          .color(this.accent())
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
              curve: Curve.EaseOut
            }));
      } else {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(23)
          .fontColor([COLOR_ICON_SECONDARY])
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
    .backgroundColor(overlayGlassFill('control', $r('app.color.surface_alt')))
    .backdropBlur(overlayBackdropBlur('control'))
    .attributeModifier(materialModifierWhen('control', this.materialEpoch >= 0))
    .clip(true)
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

  // HDS's built-in menu node composites each icon independently. With the
  // adaptive material level, the sparse search glyph and dense more glyph can
  // therefore look like two different material strengths even though the same
  // options were supplied. Draw both actions through one project material
  // pipeline so size, tint, blur, light level and interaction stay identical.
  @Builder
  homeTopBarContent() {
    Row({ space: 8 }) {
      Column() {
        Text($r('app.string.app_name'))
          .id(TITLE_MAIN_ID)
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

  // 悬浮 chrome 的总高度 = 顶栏 + （有文件夹时）文件夹条。列表按这个值让出
  // 起始位置，滚动时内容从玻璃底下穿过去。
  private scrollerFor(key: string): ListScroller {
    const hit = this.tabScrollers.get(key);
    if (hit !== undefined) {
      return hit;
    }
    const made = new ListScroller();
    this.tabScrollers.set(key, made);
    return made;
  }

  // 交给 bindToScrollable 的那一批。页签是动态的（文件夹可增删），所以按当前
  // tabs() 现取，顺带把已经不存在的页签的控制器留在 Map 里——它们不占什么，
  // 而删掉会在文件夹顺序变动时把正在用的那个也误删。
  private allTabScrollers(): Scroller[] {
    return this.tabs().map((spec: TabSpec): ListScroller => this.scrollerFor(spec.key));
  }

  private titleBarContentCache: TitleBarContentOptions | null = null;
  private titleBarBottomHeightCache: number = -1;
  private titleBarOptionsCache: HdsNavigationTitleBarOptions | null = null;
  private titleBarWallpaperCache: boolean = false;
  private titleBarAppearanceCache: number = -1;
  private titleBarMaterialCache: number = -1;

  // 标题栏内容：应用名 + 同步状态副标题 + 搜索/⋮ 两个动作 + 超级群组顶栏抽屉 + 底部的文件夹条。
  // 引用保持稳定（同 ChatPage.chatTitleBarOptions），避免 HDS 因对象重建销毁重画整条标题栏而闪白。
  private titleBarContent(): TitleBarContentOptions {
    const bottomHeight: number = this.folderBarSpace()
      + (this.newSessionCount > 0 ? NEW_SESSION_BAR_HEIGHT : 0);
    if (this.titleBarContentCache !== null && this.titleBarBottomHeightCache === bottomHeight) {
      return this.titleBarContentCache;
    }
    const content: TitleBarContentOptions = {
      stackBuilder: (): void => { this.titleBarActions(); }
    };
    if (bottomHeight > 0) {
      content.bottomBuilder = {
        builder: (): void => { this.titleBarBottom(); },
        height: bottomHeight
      };
    }
    this.titleBarContentCache = content;
    this.titleBarBottomHeightCache = bottomHeight;
    return content;
  }

  private mainTitleBarOptions(): HdsNavigationTitleBarOptions {
    const content: TitleBarContentOptions = this.titleBarContent();
    if (this.titleBarOptionsCache !== null &&
      this.titleBarOptionsCache.content === content &&
      this.titleBarWallpaperCache === this.appWallpaperOn &&
      this.titleBarAppearanceCache === this.appearanceEpoch &&
      this.titleBarMaterialCache === this.materialEpoch) {
      return this.titleBarOptionsCache;
    }
    const options: HdsNavigationTitleBarOptions = {
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      style: titleBarStyle(mainBarFill(this.appWallpaperOn), this.accent()),
      content: content
    };
    this.titleBarOptionsCache = options;
    this.titleBarWallpaperCache = this.appWallpaperOn;
    this.titleBarAppearanceCache = this.appearanceEpoch;
    this.titleBarMaterialCache = this.materialEpoch;
    return options;
  }

  // 左栏宽度按窗口宽度取比例。**minWidth 才是真正决定观感的那个数**：
  // HdsNavigation 没有开放 navBarWidth 设置项，内部默认 240vp，被 range 一夹就
  // 落在 minWidth 上——这正是上一版在 1440vp 屏上稳稳停在 320（22%）的原因。
  // maxWidth 只是 enableDragBar 拖分割线时的上限。
  // 算法搬到 util/splitMetrics.ets，理由见那里的文件头。这三个方法只剩把
  // 当前窗口宽度喂进去。
  private navBarMinWidth(): number {
    return splitNavMinWidth(this.screenW);
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

  private chromeInset(): number {
    return this.topSafe + TOP_BAR_HEIGHT + this.folderBarSpace();
  }

  // 文件夹条当前该占多高（不含新建会话横幅）。展开/收起两档，收起态见
  // util/folderBarCollapse。bottomBuilder 的高度和 chromeInset 都读它，
  // 两处必须同源，否则列表让位的总量和标题栏实际高度会各说各话。
  private folderBarSpace(): number {
    if (this.folders.length === 0) {
      return 0;
    }
    return this.folderBarCollapsed ? FOLDER_COLLAPSED_SPACE : FOLDER_BAR_SPACE;
  }

  // 量出主标题的实际矩形，把缩略块贴到它右下角（TITLE_MAIN_ID）。
  //
  // **为什么是量而不是算**：标题的字号、字重、左内边距、以及它在分栏左栏里的
  // 起点都由 HDS 自己决定，官方文档只给了标题栏总高（MINI 56vp），没有给这些；
  // 自己估一个 x 会在换语言、改系统字号、拖分割线之后全部错位。量出来的矩形
  // 是 px，转 vp 再摆。
  //
  // 量不到（还没布局、或 API 不可用）时保持上一次的值；一次都没量到就由
  // collapsedFolderChip 退回"标题栏左下角"（见那里的三元），难看但不会盖住标题。
  // 不是 private：FolderChipAnchorFrameCallback 要回调它（窗口尺寸变化后重量）。
  measureFolderChipAnchor(): void {
    if (this.folderChipAnchored) {
      return;
    }
    try {
      const rect: componentUtils.ComponentInfo =
        this.getUIContext().getComponentUtils().getRectangleById(TITLE_MAIN_ID);
      const w: number = px2vp(rect.size.width);
      const h: number = px2vp(rect.size.height);
      if (!(w > 0) || !(h > 0)) {
        return;
      }
      this.folderChipX = px2vp(rect.windowOffset.x) + w + FOLDER_CHIP_GAP_X;
      // 纵向按底边对齐：胶囊底边 = 字形底边，于是它整个骑在标题那一行上，
      // 而不是吊在标题下面。
      this.folderChipY = px2vp(rect.windowOffset.y) + h - FOLDER_CHIP_TEXT_DESCENT -
        FOLDER_COLLAPSED_CHIP_HEIGHT + FOLDER_CHIP_DROP_Y;
      this.folderChipAnchored = true;
    } catch (_error) {
      // 取不到就继续用旧值，下一条路径会再试（每次收起都会调一次）。
    }
  }

  // 收起态缩略块显示哪一项 = 当前文件夹。tabs() 每次都重建数组，这里只在构建
  // 时读，不在滚动路径上。
  private currentTabSpec(): TabSpec | undefined {
    return this.tabs()[this.selectedIndex];
  }

  // 子列表每帧报上来的滚动量（见 ChatListView / MainTabBody 的
  // reportFolderBarScroll），文件夹条据此收起/展开。
  private noteFolderBarScroll(key: string, delta: number, atTop: boolean): void {
    // 只认当前页签的列表：别的页签在布局、预载、复原位置时也会滚一下，那些
    // 不该让横条动。
    if (key !== (this.tabs()[this.selectedIndex]?.key ?? '')) {
      return;
    }
    const forceExpand: boolean = folderBarForceExpand(atTop, this.folderBarDragReveal,
      this.folders.length > 0, this.folderBarScrollHide);
    this.folderBarState = nextFolderBarCollapse(this.folderBarState, delta, forceExpand);
    this.applyFolderBarState(true);
  }

  // 关掉「列表滑动隐藏文件夹」时立刻把横条放回来，不等下一次滚动。
  // 打开时什么都不做：状态从下一帧滚动开始累计，和加开关之前一样。
  private onFolderBarScrollHideChanged(): void {
    if (!this.folderBarScrollHide) {
      this.expandFolderBarNow();
    }
  }

  // 切到另一个文件夹之后，按**新列表**的位置补一次「到顶就展开」的判定。
  //
  // 没有这一下，"所有"里滚到很下面把横条收起、再横滑到一个停在顶部的文件夹，
  // 横条会一直缩着——因为状态机只在滚动回调里推进，而新列表一动不动就没人叫它。
  // 用 delta=0 借同一个入口：forceExpand 为真时它只做展开 + 清零，为假时什么都不改。
  private syncFolderBarWithActiveList(): void {
    const spec: TabSpec | undefined = this.tabs()[this.selectedIndex];
    if (spec === undefined) {
      return;
    }
    // 没建过的页签这里会拿到一个新建的控制器，currentOffset() 为 0——那本来也是
    // 顶上的位置。所以不需要先判存在。
    this.noteFolderBarScroll(spec.key, 0, this.scrollerFor(spec.key).currentOffset().yOffset <= 0);
  }

  // 收起态横拖切换文件夹：拖过阈值就把整条展开——用户得看见自己在切哪一项。
  private noteFolderBarDrag(offset: number): void {
    if (!this.folderBarDragReveal && this.folderBarCollapsed && folderDragReveals(offset)) {
      this.folderBarDragReveal = true;
      this.applyFolderBarState(true);
    }
  }

  // 松手（或切页动画落定）：拖动期间的强制展开撤回，回缩到状态机认定的那一档。
  private settleFolderBarDrag(): void {
    if (!this.folderBarDragReveal) {
      return;
    }
    this.folderBarDragReveal = false;
    this.applyFolderBarState(true);
  }

  // 点收缩态的缩略块 = 用户明确要求展开，不看累计量。**必须同时复位状态机**，
  // 否则松手后下一帧同向滚动会立刻把它收回去。
  private expandFolderBarNow(): void {
    this.folderBarState = expandedFolderBar();
    this.folderBarDragReveal = false;
    this.applyFolderBarState(true);
  }

  // 把状态机的判定落到渲染上。只有翻面那一次才起动画——每帧都 animateTo 等于
  // 把动画时长当帧间隔用，反而卡。
  //
  // 高度收放和内容切换必须在**同一个** animateTo 里：bottomBuilder 的高度是
  // HDS 自己量的，晚一帧就跟内容对不上。
  private applyFolderBarState(animate: boolean): void {
    const collapsed: boolean = this.folderBarState.collapsed && !this.folderBarDragReveal;
    if (collapsed === this.folderBarCollapsed) {
      return;
    }
    if (collapsed) {
      // 缩略块要在收起的同时出现在标题右下角，锚点得先量好。
      this.measureFolderChipAnchor();
    }
    if (!animate) {
      this.folderBarCollapsed = collapsed;
      return;
    }
    animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_BAR_COLLAPSE_DURATION),
      curve: Curve.EaseOut
    }, (): void => { this.folderBarCollapsed = collapsed; });
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
    .backgroundColor(this.selectedIndex === index
      ? Color.Transparent : $r('app.color.material_tint'))
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
    .onClick(() => {
      if (AppStorage.get<boolean>(KEY_ACTIVE_FORUM_OPEN) === true) {
        closeForumDrawer();
      }
      this.controller.changeIndex(index);
    });
  }

  @Builder
  titleBarBottom() {
    Column() {
      if (this.newSessionCount > 0) {
        NewSessionBanner({ count: this.newSessionCount });
      }
      // 收起态整个让出去：缩略块不在这一条里，它画在标题栏外面、贴着主标题
      // （见 build 里的 collapsedFolderChip）。**不能**让横条以透明身份留着，
      // 它是全宽可点的，留着会吃掉那一带的触摸，列表就滑不动了。
      // 过渡感由横条自己的 transition 和 bottomBuilder 的高度动画接着。
      if (this.folders.length > 0 && !this.folderBarCollapsed) {
        this.tabBar();
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  // 收起态的缩略块：只有当前文件夹那一颗，字号和高度都比展开态的 chip 小一圈。
  // 点它直接展开（2026-10-30 用户明确要求）。
  //
  // **它不挂在 bottomBuilder 里，而是画在标题栏外面**（见 build 的 Stack）：
  // 用户要的位置是"主标题字母的右下边"，而 HDS 的两个自定义槽位都在标题
  // **下方**一整条，没有"标题右侧"这种位置。所以改为按主标题的实际矩形绝对
  // 定位（measureFolderChipAnchor），列表此时正好也收回了标题栏底下那一整条。
  @Builder
  collapsedFolderChip() {
    // 整块**不上一底色**（2026-10-30 用户："顶部的时候去掉胶囊"）：就是
    // 「Petrel │ 所有 88」，文字和角标直接压在标题栏的玻璃上。之前那层实色药丸
    // 是为了"离了标题栏还能读清"，现在外面有竖线做分隔、字又是强调色，药丸就多余了。
    // 外层这圈只负责横向排布和绝对定位，高度取 FOLDER_COLLAPSED_CHIP_HEIGHT，
    // 竖线因此天然对齐整块的中线。
    Row({ space: FOLDER_CHIP_DIVIDER_GAP }) {
      // 标题与文件夹名之间的竖线（2026-10-30 用户要求）。用明暗两档半透明色，
      // 理由见 FOLDER_CHIP_DIVIDER_LIGHT 那段的说明。
      Divider()
        .vertical(true)
        .height(FOLDER_CHIP_DIVIDER_HEIGHT)
        .strokeWidth(FOLDER_CHIP_DIVIDER_WIDTH)
        .color(this.appDark ? FOLDER_CHIP_DIVIDER_DARK : FOLDER_CHIP_DIVIDER_LIGHT);
      // 文件夹名 + 未读角标。
      Row({ space: 3 }) {
        Text(this.currentTabSpec()?.title ?? '')
          .fontSize(11).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TAB_SELECTED)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: this.folderTitleMaxWidth() });
        FolderChipBadge({
          badge: folderBadge(this.currentTabSpec()?.key ?? 'main'),
          selected: true,
          plainTitle: this.currentTabSpec()?.plainTitle ?? ''
        });
      }
      // 只留高度给竖线对齐用；没有底色了，padding / borderRadius 一并去掉，
      // 左侧那 5vp 的留白改由外层 Row 的 spacing（FOLDER_CHIP_DIVIDER_GAP）给。
      .height(FOLDER_COLLAPSED_CHIP_HEIGHT);
    }
    .height(FOLDER_COLLAPSED_CHIP_HEIGHT)
    .alignItems(VerticalAlign.Center)
    // 位置来自量出来的主标题矩形（见 measureFolderChipAnchor）。还没量到时退回
    // 标题栏左下角——难看，但至少不会压住标题，而且下一次收起会重新量。
    .position({
      x: this.folderChipAnchored ? this.folderChipX : homeCardMarginVp(this.widthBp),
      y: this.folderChipAnchored ? this.folderChipY
        : this.topSafe + TOP_BAR_HEIGHT - FOLDER_COLLAPSED_CHIP_HEIGHT
    })
    .onClick((): void => { this.expandFolderBarNow(); })
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: -4 }))
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_BAR_COLLAPSE_DURATION),
          curve: Curve.EaseOut
        })
    );
  }

  @Builder
  tabBar() {
    Column() {
      Scroll(this.tabScroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          // Sliding selection pill behind the labels — follows the finger
          // during Tabs content swipes. 独立组件 + AppStorage 旁路，拖动每帧
          // 只脏它自己（见 FOLDER_PILL_X 的说明）。
          FolderPill();
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
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.stripUserMoved = true;
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
    // 横条无独立外框，直接融入标题栏的统一玻璃背板；只有当前项保留胶囊。
    // 满宽外层用对称内边距约束 Scroll 视口，避免满宽内容叠加外边距挤出右侧。
    // 两侧留白沿用首页卡片规则：手机 6vp、折叠屏 10vp、平板 14vp。
    //
    // **2026-10-30 试过给整条挂一层 'bar' 玻璃（外框胶囊 + 材质三件套），用户看过
    // 真机后让改回去。** 那条路本身是通的（材质可用时整条会透出下面的列表），问题
    // 在观感：文件夹条和它上面那块 HDS 标题栏成了两截玻璃，加上大标题底下的空白，
    // 首页顶部被切成了三段。维持「无独立外框、只留选中胶囊」这一版，别再给这里加底。
    .width('100%')
    .padding({ left: homeCardMarginVp(this.widthBp), right: homeCardMarginVp(this.widthBp) })
    .margin({ bottom: 2 })
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: -4 }))
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
          curve: Curve.EaseOut
        })
    );
  }

  private pinnedSystemBar(): SystemBarStyle | undefined {
    if (this.statusFollowTitle) {
      return undefined;
    }
    return { statusBarContentColor: this.appDark ? '#FFFFFF' : '#000000' } as SystemBarStyle;
  }

  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // ⋮ 菜单锚点距 Stack 右缘的距离：单栏下 navBar 就是整个窗口，得 8；分栏下
  // 要跨过右栏，落在 navBar 右缘往里 8。navBar 宽度还没量到（0）时按单栏处理。
  private moreMenuRightInset(): number {
    if (this.navBarW <= 0 || this.navBarW >= this.screenW) {
      return 8;
    }
    return this.screenW - this.navBarW + 8;
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      HdsNavigation(this.chatStack) {
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
                  // 让位整个交给标题栏的 enableComponentSafeArea——横条现在挂在
                  // bottomBuilder 上，也算标题栏的一部分，这里再算一次就是重复。
                  contentTopInset: 0,
                  listScroller: this.scrollerFor(spec.key),
                  effectsActive: this.tabVisualsActive(spec.key),
                  imagesActive: this.tabVisualsActive(spec.key),
                  updatesActive: this.tabUpdatesActive(spec.key),
                  // 文件夹条收起/展开的输入（util/folderBarCollapse）。普通成员而非
                  // @Prop：@Prop 跨边界深拷贝会把函数丢掉。
                  onScrollForFolderBar: (delta: number, atTop: boolean): void => {
                    this.noteFolderBarScroll(spec.key, delta, atTop);
                  }
                }).layoutWeight(1);
              } else {
                ChatListView({
                  listKey: spec.key,
                  contentTopInset: 0,
                  listScroller: this.scrollerFor(spec.key),
                  effectsActive: this.tabVisualsActive(spec.key),
                  imagesActive: this.tabVisualsActive(spec.key),
                  updatesActive: this.tabUpdatesActive(spec.key),
                  onScrollForFolderBar: (delta: number, atTop: boolean): void => {
                    this.noteFolderBarScroll(spec.key, delta, atTop);
                  }
                }).layoutWeight(1);
              }
            }
            .width('100%').height('100%')
            // 这一路每一层都要放开裁剪，列表才画得到标题栏底下去。中间任何
            // 一层裁剪，穿过去的那部分就被切掉，渐变模糊没有东西可糊。
            .clip(false)
          }
          .clip(false)
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
        // navBar 的实际宽度：分栏时它就是左栏宽，拖分割线会变，MainScreen 的
        // dock 要跟着走。Tabs 是 navBar 内容的根节点、width('100%')，它的宽度
        // 就是 navBar 宽度——所以复用这一个已有的布局回调，不另挂一个：
        // HdsNavigation 没有回调宽度的接口，而多一个 onAreaChange 就是每次
        // 布局多跑一遍回调。
        if (AppStorage.get<number>(NAV_BAR_WIDTH_KEY) !== this.tabsWidth) {
          AppStorage.setOrCreate<number>(NAV_BAR_WIDTH_KEY, this.tabsWidth);
          // 拖过分割线就记下来，下次启动复原（issue #106）。
          rememberSplitNavWidth(this.tabsWidth, isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait));
        }
      })
      // Content swipe in progress: convert the swipe offset into a fractional
      // tab position so the selection pill tracks the finger continuously.
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        // 手指还在页签上拖：这一帧本来就紧，别让排好的预载凑热闹。
        this.cancelTabPreload();
        this.tabAnimationActive = true;
        const companionIndex: number = event.currentOffset > 0 ? index - 1 : index + 1;
        if (companionIndex >= 0 && companionIndex < this.tabs().length &&
          this.companionImageTabIndex !== companionIndex) {
          this.companionImageTabIndex = companionIndex;
        }
        if (this.tabsWidth > 0) {
          // 拖动期间关掉胶囊的隐式动画：每帧一个新目标再配 250ms 缓动，胶囊会
          // 一直追着手指屁股后面跑，而不是贴着手指走。
          this.setPillAnimate(false);
          this.moveIndicatorTo(index - event.currentOffset / this.tabsWidth);
        }
        // 收起态横拖也要能看见整条（2026-10-30 用户要求：滑的过程中走一遍完整
        // 动画，松手回去）。拖过阈值才展开，轻点时的微小位移不算。
        this.noteFolderBarDrag(event.currentOffset);
      })
      // Finger released / tab tapped: settle the pill on the target tab and
      // scroll the strip if that tab sits outside the visible range.
      .onAnimationStart((_index: number, targetIndex: number) => {
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
        // 手指已经松开，切页动画开始：横拖期间的强制展开到此为止，横条回缩。
        // 顺序不能反——先回缩、再按**新列表**的位置补一次到顶判定，否则切到
        // 一个停在顶部的文件夹时，横条会一直缩着直到用户去滚一下。
        this.settleFolderBarDrag();
        this.syncFolderBarWithActiveList();
        // 松手落定：胶囊从拖动最后的那个分数位置滑到目标 chip。先把拖动期间关掉的
        // 滑过去动画打开（见 FOLDER_PILL_ANIMATE）。
        this.setPillAnimate(true);
        this.moveIndicatorTo(targetIndex);
        this.revealTab(targetIndex);
      })
      .onAnimationEnd((_index: number) => {
        // 兜底：拖了不到一页又回弹这种情况，不一定会走 onAnimationStart。
        this.settleFolderBarDrag();
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
          this.settleFolderBarDrag();
          this.syncFolderBarWithActiveList();
          this.companionImageTabIndex = -1;
          if (this.unreadRefreshPending) {
            this.refreshUnread([]);
          }
          this.scheduleTabPreload(TAB_PRELOAD_AFTER_SETTLE_MS);
        }
      })
      .width('100%').height('100%')
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);

        ForumSplitView({
          navBarVisible: this.navBarVisible
        });
        }
        .width('100%')
        .height('100%')
      }
      .titleBar(this.mainTitleBarOptions())
      // 状态栏图标色钉死在深浅色上。不设 systemBarStyle 时 HDS 会按标题栏的
      // 内容色自己推——应用名染了强调色，状态栏的时钟和图标跟着变色（用户报的）。
      // 两个态给同一份：滚动进玻璃态时状态栏也不该跟着换。
      // 传 undefined 就是不覆盖，HDS 照旧按标题栏内容色自己推（开关打开时要的
      // 正是这个联动）；关闭时钉死在深浅色上，和 EntryAbility 那套一致。
      .systemBarStyle(this.pinnedSystemBar(), this.pinnedSystemBar())
      // 一级页签，没有返回键。
      .hideBackButton(true)
      // MINI 而不是 FREE：首页要的是"应用名和搜索键在同一行"的一条窄栏，
      // FREE 的大标题会先占掉一整行、把列表整体压下去，在这个每天开几十次的
      // 页面上尤其显得高。其余页面仍用 FREE——那里大标题是想要的效果。
      // 不显式设 mode：HdsNavigation 默认就是 Auto——窗口 <600vp 走单栏（手机，
      // 观感与 router.pushUrl 一致），≥600vp 自动分栏（平板，左会话列表右详情）。
      // 一行断点代码都不用写。
      //
      // 这里曾经是 .mode(NavigationMode.Stack)（commit 0d81e2e）：当时没有任何
      // HdsNavDestination，分栏的结果是整页内容挤进左列、右边一片空白，只能强制
      // 单栏止血。本次改动起 ChatPage 迁为 HdsNavDestination，止血可以拆了。
      //
      // 【下面这段是被比例式取代的旧结论，留作记录】侧边栏宽度上限 440 是官方
      // 大屏 UX 标准 3.2.2.4 定的：不超过窗口宽度 40%，内容区至少 60%。平板
      // 1137vp 下 420/717 ≈ 37%/63%。——标准这一条仍然成立，错的是"按 1137vp
      // 反推一组定值"：同一组数放到 1440vp 的屏上，左栏卡在下限 320 只占 22%。
      // 现在改成按窗口宽度取比例，见 navBarMinWidth() / navBarMaxWidth()。
      // 字段名是 minWidth / maxWidth——官方文档写的 min / max 编译不过，
      // 声明在 @hms.hds.hdsBaseComponent.d.ets:2048。
      // **不能靠 NavigationMode.Auto 自己判断。** 拆掉 .mode(Stack) 那几个 commit
      // 的前提是"Auto 的断点就是 600vp"，2026-08-22 手机模拟器实测推翻了它：
      // 窗口 1320px / density 3 = **440vp**（启动日志 [Layout] 那一行有据），远在
      // 600vp 之下，Auto 照样进了分栏——左栏挤成一条、会话名全没了、dock 揉成
      // 一团压在左下角。手机端被这条默认行为整个毁掉，而平板那台是 API 26、
      // 宽得多，整轮平板验证一次都没暴露。
      //
      // 所以分栏由我们自己说了算：isSplitByBreakpoint 读系统横向 + 纵向断点，
      // 手机横屏（md 宽 + 横向窗口）也判单栏（util/layoutBreakpoint）。
      // 显式给 mode 还有一个好处——分栏与否不再依赖某个 SDK 版本的内部阈值。
      .mode(isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait) ? NavigationMode.Split : NavigationMode.Stack)
      // 分栏下查看器开着：Split + hideNavBar(true) 的实际效果是单栏，右栏会话页铺满窗口（#201）。
      .hideNavBar(this.viewerHidesNavBar())
      .navBarWidthRange({ minWidth: this.navBarMinWidth(), maxWidth: this.navBarMaxWidth() })
      // 启动时复原上次拖出来的宽度；没记过就是 min（HDS 的静息值）。
      .navBarWidth(resolveSplitNavWidth(this.savedNavW, this.navBarMinWidth(), this.navBarMaxWidth()))
      // 右栏栈空时的占位。仅分栏模式展示，手机单栏下永不出现。
      .splitPlaceholder(this.placeholderContent())
      .minContentWidth(this.contentMinWidth())
      // navBar 显隐 = 「单栏且栈非空」。dock 要藏在这种时候，见
      // CHAT_NAV_BAR_VISIBLE_KEY 的说明。写入前先比一次：同值 setOrCreate 也会
      // 惊动订阅方，而这个回调在单双栏切换时会连着来几次。
      .onNavBarStateChange((reported: boolean): void => {
        AppStorage.setOrCreate<boolean>(CHAT_NAV_BAR_REPORTED_KEY, reported);
        // 应用内浏览器退掉时会补发 visible=true 而栈里还有详情页，按栈兜底。见 navBarReset。
        this.applyNavBarVisible(navBarVisibleOnChange(reported,
          isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait),
          effectiveChatDepth(this.chatStack.size(), this.chatDetailShown())) &&
          !this.viewerHidesNavBar());
      })
      .enableDragBar(true)
      // 关掉全模态联动：默认 true 时，bindSheet 一拉起就会触发栈顶
      // HdsNavDestination 的 onHidden。ChatPage 的 onPageHide 挂着「立刻停播放位」，
      // 而它自己就有 showForwardSheet / showReactionSheet 两个全模态——联动打开
      // 的话，一开转发面板音视频就停了，这是迁移前没有的行为。
      .attributeModifier(SHEET_LIFECYCLE_MODIFIER)
      .titleMode(HdsNavigationTitleMode.MINI)
      // 小方形屏沉浸式浏览（SPEC-04）：上滑收起标题栏，带动画。
      .hideTitleBar(this.immersiveHidden && isSmallSquare(this.widthBp, this.heightBp), true)
      // 每个文件夹页签的列表控制器都交进去——哪一个在滚，标题栏就跟着哪一个。
      .bindToScrollable(this.allTabScrollers())
      .width('100%').height('100%')
      // 背景色是 expandSafeArea 真正延伸出去的东西——只写 expandSafeArea 而不画
      // 背景，延伸的是"什么都没有"，状态栏底下露的就是窗口底色（实测深色模式
      // 下那是一条纯黑）。
      // 壁纸生效时整页底必须透明，否则壁纸被这一层盖死（见 util/theme.mainPageFill）。
      .backgroundColor(mainPageFill(this.appWallpaperOn));

      // 收起态的缩略块。挂在这里而不是标题栏里，理由见 collapsedFolderChip；
      // 推页时它必须跟着 navBar 一起消失，理由见 FolderChipSlot。
      // **箭头函数不能省**：直接写 `content: this.collapsedFolderChip` 的话，
      // @Builder 里的 this 会变成子组件，这里读的 @State 全都落空、还不报错。
      if (this.folderBarCollapsed && this.folders.length > 0) {
        FolderChipSlot({ content: (): void => { this.collapsedFolderChip(); } });
      }

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
  @StorageProp(FOLDER_PILL_X) pillX: number = 0;
  @StorageProp(FOLDER_PILL_W) pillW: number = 0;
  // 这一帧要不要"滑过去"（见 FOLDER_PILL_ANIMATE）。
  @StorageProp(FOLDER_PILL_ANIMATE) private pillAnimate: boolean = false;
  // 材质档位（厚度/光感）变了要重绘，材质对象才会按新档位重建。订阅放在这里而
  // 不是 ChatListPage：胶囊有自己的旁路脏区（见 FOLDER_PILL_X），别为了它把整页
  // 拉进重绘。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;

  build() {
    Row()
      .width(this.pillW).height(FOLDER_CHIP_HEIGHT)
      .borderRadius(FOLDER_CHIP_HEIGHT / 2)
      .position({
        x: this.pillX,
        y: (FOLDER_BAR_HEIGHT - FOLDER_CHIP_HEIGHT) / 2
      })
      // **位置/宽度的动画挂在胶囊自己身上。** 隐式动画认的是属性变化，跟位置从
      // 哪条路送进来无关——onAnimationStart、onChange、首次布点都会改 pillX，挂在
      // 这里一律管住，不用每个调用点各包一层 animateTo。真机截图验证过：点一个
      // 远处的文件夹，中途那一帧拍到的胶囊确实横在两个 chip 之间。
      // 拖页签时 setPillAnimate(false) 把它关掉，胶囊才会老老实实贴着手指走。
      //
      // `.animation()` 只作用于**它前面**的属性，所以材质三件套必须留在它后面，
      // 否则换主题、调材质厚度时底色和模糊也会被拖着淡入淡出。
      .animation(this.pillAnimate
        ? {
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION),
          curve: Curve.EaseOut
        }
        : { duration: 0 })
      // 选中胶囊挂 'control' 材质三件套，和顶栏搜索/⋮ 同一套（2026-10-30 用户选定）。
      // 三档退路和别处一致：材质可用 → 底色透明、观感整个交给材质；设备不支持 →
      // dock_glass + backdropBlur 自绘玻璃；用户把厚度调到「关闭」→ 强调色实底，
      // 也就是今天这个样子。
      //
      // 注意第一档的副作用：材质在时底色是**透明**的，选中态不再有那层强调色药丸，
      // 只剩玻璃块 + 强调色文字。这是官方 FAQ「材质的视觉层级在 backgroundColor
      // 之下」的必然结果——想在材质上保住蓝色，只能在玻璃**上面**再盖一层半透明
      // 强调色，官方把那种叠法列为「发实」的典型，别这么干。
      .backgroundColor(overlayGlassFill('control', COLOR_TAB_PILL_BG))
      .backdropBlur(overlayBackdropBlur('control'))
      .attributeModifier(materialModifierWhen('control', this.materialEpoch >= 0));
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

// 收起态缩略块的"位置归属"闸门：navBar 不在（单栏推了页、会话页盖上来）时整块
// 不画。
//
// 【为什么需要】缩略块是画在标题栏**外面**的——它是 HdsNavigation 的兄弟节点
// （见 ChatListPage.build 里的 Stack），推页时 Navigation 盖不住它，于是它会浮
// 在会话页顶上，还点不掉（2026-10-30 用户报的「其他页面也会存在消不掉」）。
// 判据直接借 navBar 的显隐：单栏时栈空才可见，分栏恒可见（那时左栏还在，缩略块
// 本来就该跟着它），正好就是"这块地方此刻归会话列表"。
//
// 【为什么是独立组件】订阅要落在订阅者自己身上。若把 CHAT_NAV_BAR_VISIBLE_KEY
// 读进 ChatListPage 的 @State，推页转场里就会重建整页——正是 navBarVisible
// 上方那段事故记录在躲的事。这里只重建一个空壳。
@Component
struct FolderChipSlot {
  @StorageProp(CHAT_NAV_BAR_VISIBLE_KEY) private navBarVisible: boolean = true;
  @StorageProp(KEY_ACTIVE_FORUM_OPEN) private forumDrawerOpen: boolean = false;
  @BuilderParam content: () => void;

  build() {
    if (this.navBarVisible && !this.forumDrawerOpen) {
      this.content();
    }
  }
}
