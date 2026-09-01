import { getFolderStore, getUnreadCountStore, getChatStore, getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { FolderInfo } from '../../store/FolderStore';
import { ChatListView } from './ChatListView';
import { MainTabBody } from './MainTabBody';
import { CHAT_LIST_NOW } from './ChatListFreeze';
import { ComponentContent, FrameCallback, LengthMetrics } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationTitleMode, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { APPEARANCE_EPOCH, KEY_STATUS_FOLLOW_TITLE } from '../../util/appearance';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_BADGE_BG, COLOR_TAB_PILL_BG } from '../../util/theme';
import { router } from '@kit.ArkUI';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration, KEY_SPLIT_NAV_WIDTH
} from '../../store/AppSettings';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import {
  overlayBackdropBlur, overlayGlassFill, overlayMaterial, plainBackdropBlur, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';
import { navigateToChat } from '../../util/chatNav';
import { logE } from '../../util/log';
import { nextTabPreloadIndex, pruneBuiltKeys } from '../../util/tabPreload';
import { FolderBadge, badgeLabel, folderBadge, setFolderBadge } from '../../util/folderBadges';
import { registerStack, NavStackLike } from '../../util/navStacks';
import { splitNavMinWidth, splitNavMaxWidth, splitContentMinWidth, isSplitLayout } from '../../util/splitMetrics';
import { mainBarFill, mainPageFill } from '../../util/theme';
import { KEY_APP_BG_ON } from '../../store/AppSettings';
import { SHEET_LIFECYCLE_MODIFIER } from '../../util/navSheetLifecycle';
import { SplitPlaceholderHolder } from '../../util/splitPlaceholderHolder';
import { KEY_APP_DARK } from '../../util/theme';
import { navBarVisibleOnAppear, navBarVisibleOnChange } from '../../util/navBarReset';
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
const TOP_ACTION_SIZE: number = 44;
const TAB_BADGE_MAX: number = 99;
const FOLDER_BAR_HEIGHT: number = 36;
// 文件夹条连同它自己的上下留白占的高度（列表让位用）。
const FOLDER_BAR_SPACE: number = 42;
// 文件夹项与选中指示器共用这一个高度。未选项不再各画一块玻璃，只让滑动
// 指示器托住当前项，避免“外层横条 + 一排胶囊 + 会话卡片”叠出三层容器。
const FOLDER_CHIP_HEIGHT: number = 28;
const FOLDER_SWITCH_DURATION: number = 250;
// 邻居页签预载（见 util/tabPreload 的说明）的两个延时。preloadItems 是调用即
// 一次性构建（单个页签实测 ~60ms），时机全靠这里挑：
//   切页后：切页/回弹动画在 Render Service 侧独立播，UI 线程这 60ms 藏在动画
//   后面，用户抬手到下一次触摸的间隙（实测 ≥300ms）足够盖住它。
//   空闲档：冷启动文件夹就绪、从会话页退回来这类时点，躲开首帧和转场余波，
//   800ms 后一般已静止而横滑还没开始。
const TAB_PRELOAD_AFTER_SWITCH_MS: number = 120;
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

@Preview
// 组件冻结：这四个页签由 MainScreen 的 Tabs 保活，同一时刻只有一个在屏上，
// 其余三棵树却照样响应各自 store 的状态更新、照样重跑 build。冻结之后非
// 激活的页签不再刷新，切回来时框架补上延后的那次更新。
@Component({ freezeWhenInactive: true })
export struct ChatListPage {
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
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
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
  // 分栏判据要两条边都过线（见 util/splitMetrics.isSplitLayout）——只看宽的话
  // 手机一转横屏就被当成平板。
  @StorageProp('screenHeightVp') @Watch('onWindowResized') screenH: number = 780;
  // 平板分栏下记住的左栏宽度（issue #106），见 util/splitNavWidth。
  @StorageProp(KEY_SPLIT_NAV_WIDTH) private savedNavW: number = 0;
  // Sliding selection pill: position/size interpolated between tab frames so it
  // follows the finger during content swipes (Telegram-style).
  // 不是 @State：真正画胶囊的 FolderPill 走 FOLDER_PILL_X/W 旁路，这两份
  // 留作页面逻辑自己的读值（folderLayoutPending 的判据等）。
  private indicatorX: number = 0;
  private indicatorW: number = 0;
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

  @Styles
  actionNormalStyle() {
    .opacity(1)
  }

  @Styles
  actionPressedStyle() {
    .opacity(0.68)
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
    if (!isVisible) {
      this.suspendListRendering();
    } else if (changed || !this.listRenderActive) {
      // 先把缓冲里的内容变更刷出去（未读角标之类），再等过渡结束开闸
      // （issue #159）。见 util/chatListRenderGate.requestChatListFlush。
      requestChatListFlush();
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
    this.applyNavBarVisible(navBarVisibleOnAppear(
      isSplitLayout(this.screenW, this.screenH), this.chatStack.size()));
  }

  aboutToAppear(): void {
    // 深链、通知点击、账号切换都在页面之外触发跳转，拿不到组件上下文，
    // 只能靠全局注册表取栈。见 util/navStacks.ets 的说明。
    registerStack('chat', this.chatStack as NavStackLike);
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
      isSplitLayout(this.screenW, this.screenH), this.chatStack.size());
    AppStorage.setOrCreate<boolean>(CHAT_NAV_BAR_VISIBLE_KEY, this.navBarVisible);
    this.listRenderActive = this.navBarVisible;
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
    // 冷启动时文件夹多半已在本地缓存里（tabs() 立即非空），首个邻居页签趁
    // 启动静止期先建出来，用户第一次横滑就不用付那 74ms（Frame 录制实测）。
    // 文件夹还没到的话这次是空转，订阅回调里 foldersChanged 那一路会再排。
    this.scheduleTabPreload(TAB_PRELOAD_IDLE_MS);
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
    if (this.listRenderActive) {
      AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    }
    if (this.clockTimer !== -1) {
      return;
    }
    this.clockTimer = setInterval((): void => {
      if (this.listRenderActive) {
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
    this.tabPreloadTimer = setTimeout((): void => {
      this.tabPreloadTimer = -1;
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
    if (!this.listRenderActive) {
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
    const index = nextTabPreloadIndex(keys, this.selectedIndex, this.builtTabKeys);
    if (index < 0) {
      return;
    }
    const key = specs[index].key;
    this.builtTabKeys.add(key);
    try {
      this.controller.preloadItems([index]).then((): void => {
        // 另一侧邻居（如果也没建过）留给下一个空闲档，不连着吃两个 60ms。
        this.scheduleTabPreload(TAB_PRELOAD_IDLE_MS);
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
    this.listRenderActive = false;
    setChatListRenderActive(false);
  }

  private resumeListRenderingAfterTransition(): void {
    this.cancelListRenderResume();
    this.listRenderResumeTimer = setTimeout((): void => {
      this.listRenderResumeTimer = -1;
      if (!this.navBarVisible) {
        return;
      }
      this.listRenderActive = true;
      setChatListRenderActive(true);
      // ChatRow time labels and folder badges were deliberately frozen while
      // covered. Refresh both after child data sources have flushed their one
      // coalesced snapshot, outside the pop transition.
      AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
      if (this.unreadRefreshPending) {
        this.refreshUnread();
      }
      // 盖住期间被跳过的邻居预载（preloadNeighborTab 的 listRenderActive 闸）
      // 在这里补排；邻居都建过时空转，只费一个定时器。
      this.scheduleTabPreload(TAB_PRELOAD_IDLE_MS);
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

  // 逐 chip 写入旁路模型（util/folderBadges），只有值变了的角标各自重渲染，
  // 整页和标题栏不再牵动。While a destination covers the nav bar, collapse any
  // number of notifications into one pending refresh（延后语义保持原样）。
  private refreshUnread(): void {
    if (!this.listRenderActive) {
      this.unreadRefreshPending = true;
      return;
    }
    this.unreadRefreshPending = false;
    for (const spec of this.tabs()) {
      setFolderBadge(spec.key, this.computeUnread(spec.key));
    }
  }

  aboutToDisappear(): void {
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
  titleBarActions() {
    Row({ space: 8 }) {
      this.searchAction();
      this.topAction('sys.symbol.more', $r('app.string.cl_more_actions'), (): void => {
        this.moreMenuShown = true;
      });
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .padding({ right: 16 })
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center);
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

  // 标题栏内容：应用名 + 同步状态副标题 + 搜索/⋮ 两个动作 + 底部的文件夹条。
  //
  // 同步状态原来是顶栏里第二行文字、靠位移动画"挤"出来，现在交给标题栏的
  // subTitle —— 它自己管这个位置。
  private titleBarContent(): TitleBarContentOptions {
    const content: TitleBarContentOptions = {
      title: {
        mainTitle: $r('app.string.app_name'),
        subTitle: this.syncState === '' ? '' : this.syncLabel()
      },
      stackBuilder: (): void => { this.titleBarActions(); }
    };
    // 文件夹条挂在 bottomBuilder 上——这是 HDS 给"标题栏底下那一行"准备的槽位，
    // 横条和标题栏因此共用同一块背板与材质，看上去是一整块。
    //
    // 试过让它单独浮在内容区上层（Stack）：两者中间断开一道，观感割裂；而且
    // 标题栏那块玻璃背后只剩一小段列表，透不出东西来，看着几乎是实心的。
    // 合成一块之后列表从整块底下穿过去，玻璃才有内容可透。
    if (this.folders.length > 0) {
      content.bottomBuilder = {
        builder: (): void => { this.tabBar(); },
        height: FOLDER_BAR_SPACE
      };
    }
    return content;
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
          .fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.accent())
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
        SymbolGlyph($r('sys.symbol.more')).fontSize(23).fontColor([COLOR_ICON_SECONDARY]);
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
      FolderChipBadge({
        badge: folderBadge(spec.key),
        selected: this.selectedIndex === index,
        plainTitle: spec.plainTitle
      });
    }
    .height(FOLDER_CHIP_HEIGHT)
    .padding({ left: 7, right: 7 })
    .margin({ right: 6 })
    .borderRadius(FOLDER_CHIP_HEIGHT / 2)
    // 未选项只铺一层轻量 tint，不再各自叠模糊/材质；选中态由下层滑动胶囊表达。
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
    // 未读部分的读屏文案跟着角标子组件走（FolderChipBadge）：计数在旁路模型
    // 里，chip 这层的绑定读不到它的变化。
    .accessibilityText(spec.plainTitle)
    .onClick(() => { this.controller.changeIndex(index); });
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
          Row() {
            ForEach(this.tabs(), (spec: TabSpec, index: number) => {
              this.pill(spec, index);
            }, (spec: TabSpec) => spec.key);
          }.padding({ left: 0, right: 0 }).height(FOLDER_BAR_HEIGHT);
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      // 无论文件夹多少都从 12vp 网格线起排，与大标题和会话卡片的左外沿一致；
      // 内容超宽时照常横向滚动。
      .align(Alignment.TopStart)
      .width('100%')
      .onAreaChange((_old: Area, area: Area) => {
        this.tabViewW = area.width as number;
        this.ensureTabVisible(this.selectedIndex);
      });
    }
    // 横条无独立外框，直接融入标题栏的统一玻璃背板；只有当前项保留胶囊。
    // 12vp 起始线同时对齐大标题与会话卡片，底部只留轻微呼吸空间。
    .margin({ left: 12, right: 12, bottom: 2 })
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
                  listScroller: this.scrollerFor(spec.key)
                });
              } else {
                ChatListView({
                  listKey: spec.key,
                  contentTopInset: 0,
                  listScroller: this.scrollerFor(spec.key)
                });
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
          rememberSplitNavWidth(this.tabsWidth, isSplitLayout(this.screenW, this.screenH));
        }
      })
      // Content swipe in progress: convert the swipe offset into a fractional
      // tab position so the selection pill tracks the finger continuously.
      .onGestureSwipe((index: number, event: TabsAnimationEvent) => {
        // 手指还在页签上拖：这一帧本来就紧，别让排好的预载凑热闹。
        this.cancelTabPreload();
        if (this.tabsWidth > 0) {
          this.moveIndicatorTo(index - event.currentOffset / this.tabsWidth);
        }
      })
      // Finger released / tab tapped: settle the pill on the target tab and
      // scroll the strip if that tab sits outside the visible range.
      .onAnimationStart((_index: number, targetIndex: number) => {
        this.folderLayoutPending = false;
        this.appliedFolder = targetIndex;
        this.selectedIndex = targetIndex;
        animateTo({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION),
          curve: Curve.EaseOut
        }, () => { this.moveIndicatorTo(targetIndex); });
        this.ensureTabVisible(targetIndex);
        // selectedIndex 已指向目标页签：趁切页动画（RS 侧独立播）把它的邻居
        // 建出来，动画结束前就绪。
        this.scheduleTabPreload(TAB_PRELOAD_AFTER_SWITCH_MS);
      })
      .onChange((index: number) => {
        // onAnimationStart already drives animated changes. Avoid starting the
        // same settle animation twice when onChange fires at the end.
        if (this.selectedIndex !== index) {
          this.appliedFolder = index;
          this.selectedIndex = index;
          animateTo({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, FOLDER_SWITCH_DURATION),
            curve: Curve.EaseOut
          }, () => { this.moveIndicatorTo(index); });
        } else {
          this.moveIndicatorTo(index);
        }
        this.ensureTabVisible(index);
        // onAnimationStart 那次预载被中途手势取消掉的话，这里兜底再排一次；
        // 邻居都建过时是空转。
        this.scheduleTabPreload(TAB_PRELOAD_AFTER_SWITCH_MS);
      })
      .width('100%').height('100%')
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);

      }
      .titleBar({
        // 两个都要，各管一头：
        //
        //   avoidLayoutSafeArea     标题栏**自己**避让系统安全区
        //   enableComponentSafeArea 标题栏成为**内容区**的安全区，内容避让它
        //
        // 官方示例里只有后者，因为那是个普通非全屏窗口。**本应用整体是全屏沉浸
        // 布局**（EntryAbility 调了 setWindowLayoutFullScreen(true)），页面的布局区
        // 本来就覆盖状态栏——这也是全应用每个页面都要手动 padding(topSafe) 的原因。
        // 所以这里必须自己避让，少了它标题栏就顶进状态栏（真机两次实测）。
        //
        // 但**不要**再在 HdsNavigation 根上加 expandSafeArea：那会把标题栏往状态栏
        // 里推，和这一行正好对着干，两者抵消之后渐变模糊的合成也跟着废掉。状态栏
        // 那条的底色由 HdsNavigation 自己的 backgroundColor 铺——全屏布局下它本来
        // 就盖到那儿。
        avoidLayoutSafeArea: true,
        enableComponentSafeArea: true,
        // 标题栏也让位：它和列表同属一张"浮在壁纸上"的面，只有行卡片自己带底。
        // 两颗动作按钮由 stackBuilder 共用 control 材质；标题栏本身继续只负责
        // 滚动模糊，避免整栏与按钮材质叠加后发实。
        style: titleBarStyle(mainBarFill(this.appWallpaperOn), this.accent()),
        content: this.titleBarContent()
      })
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
      // 所以断点由我们自己说了算：isSplitLayout 用的是 splitMetrics 里的
      // SPLIT_BREAKPOINT_VP，与 navBarWidthRange / minContentWidth 那几个算式同源。
      // 显式给 mode 还有一个好处——分栏与否不再依赖某个 SDK 版本的内部阈值。
      .mode(isSplitLayout(this.screenW, this.screenH) ? NavigationMode.Split : NavigationMode.Stack)
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
        // 应用内浏览器退掉时会补发 visible=true 而栈里还有详情页，按栈兜底。见 navBarReset。
        this.applyNavBarVisible(navBarVisibleOnChange(reported,
          isSplitLayout(this.screenW, this.screenH), this.chatStack.size()));
      })
      .enableDragBar(true)
      // 关掉全模态联动：默认 true 时，bindSheet 一拉起就会触发栈顶
      // HdsNavDestination 的 onHidden。ChatPage 的 onPageHide 挂着「立刻停播放位」，
      // 而它自己就有 showForwardSheet / showReactionSheet 两个全模态——联动打开
      // 的话，一开转发面板音视频就停了，这是迁移前没有的行为。
      .attributeModifier(SHEET_LIFECYCLE_MODIFIER)
      .titleMode(HdsNavigationTitleMode.MINI)
      // 每个文件夹页签的列表控制器都交进去——哪一个在滚，标题栏就跟着哪一个。
      .bindToScrollable(this.allTabScrollers())
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

// 滑动选中胶囊。位置/宽度从 ChatListPage 的 @State 旁路成 AppStorage 通道
// （见 FOLDER_PILL_X 的说明）：拖动页签时 moveIndicatorTo 每帧更新，脏区
// 只有这一个组件，不再整页 ExecuteRerender。
@Component
struct FolderPill {
  @StorageProp(FOLDER_PILL_X) pillX: number = 0;
  @StorageProp(FOLDER_PILL_W) pillW: number = 0;

  build() {
    Row()
      .width(this.pillW).height(FOLDER_CHIP_HEIGHT)
      .borderRadius(FOLDER_CHIP_HEIGHT / 2)
      .backgroundColor(COLOR_TAB_PILL_BG)
      .position({
        x: this.pillX,
        y: (FOLDER_BAR_HEIGHT - FOLDER_CHIP_HEIGHT) / 2
      });
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
      Row() {
        Text(badgeLabel(this.badge.count, TAB_BADGE_MAX))
          .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
      }
      .constraintSize({ minWidth: 16 })
      .height(16).padding({ left: 4, right: 4 })
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .backgroundColor(this.selected ? COLOR_TAB_SELECTED : COLOR_BADGE_BG)
      .borderRadius(8)
      .accessibilityText(str('cl_tab_unread_a11y', this.plainTitle,
        badgeLabel(this.badge.count, TAB_BADGE_MAX)));
    }
  }
}
