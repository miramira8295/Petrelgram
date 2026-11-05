import { ContactAlphabetIndex } from '../../services/ContactAlphabetIndex';
import { homeCardMarginVp } from '../../util/pageMargin';
import { BLUR_MAX_VP, EDGE_OVERLAY_VP, edgeBlurStops } from '../../util/scrollEdgeBlur';
import {
  HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WINDOW_PORTRAIT, KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM, isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { getTdClient } from '../../tdkit/Globals';
import { flushPendingNavs } from '../../util/pendingNavFlush';
import {
  KEY_SURFACE_GLASS_ON, SURFACE_GLASS_EPOCH, SURFACE_GLASS_ON_DEFAULT,
  surfaceGlassBlurStyle, surfaceGlassFill
} from '../../util/surfaceGlass';
import { ContactsStore, ContactItem } from '../../store/ContactsStore';
import {
  cardDividerStartVp, HOME_CARD_INSET_VP, LIST_CARD_INSET_VP, LIST_CARD_TRAIL_VP
} from '../../util/listCardGeometry';
import { ContactRowView } from './ContactRowView';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { guardKey } from '../../util/keyGuard';
import {
  COLOR_DIVIDER, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY,
  ROW_PAD_H
} from '../../util/theme';
import { GLASS_OUTLINE_COLOR } from '../../util/bubbleTail';
import { TdRequest, TdObject, TdError } from '../../tdkit/TdTypes';
import {
  CONTACT_ERR_BAD_PHONE, CONTACT_ERR_NETWORK, CONTACT_ERR_NO_USER,
  contactAddErrorKind, contactErrorRecoverable
} from '../../util/contactAddError';
import { ComponentContent, promptAction, router, SymbolGlyphModifier } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationIconOptions, HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import { searchPublicUsers } from '../../store/PublicUserSearch';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration, KEY_SPLIT_NAV_WIDTH, KEY_FORCE_SINGLE_COLUMN,
  KEY_POWER_ACTIVE, KEY_POWER_PARTICLES
} from '../../store/AppSettings';
import { ConfirmedChatRemoval } from '../../util/confirmedChatRemoval';
import { DissolveDeleteEffect } from '../common/DissolveDeleteEffect';
import { showMenuDialog } from '../common/menuDialog';
import {
  addContactRequest, importContactsRequest, searchUserByPhoneNumberRequest
} from '../../util/contactAddRequest';
import { plural, str } from '../../util/strings';
import { containerBlur, overlayMaterial, MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { logE, logW } from '../../util/log';
import { readableContentWidth } from '../../util/contentWidth';
import { registerStack, NavStackLike } from '../../util/navStacks';
import { navigateToProfile } from '../../util/profileNav';
import { splitContentMinWidth, splitNavMaxWidth, splitNavMinWidth } from '../../util/splitMetrics';
import { SHEET_LIFECYCLE_MODIFIER } from '../../util/navSheetLifecycle';
import { SplitPlaceholderHolder } from '../../util/splitPlaceholderHolder';
import { KEY_APP_DARK } from '../../util/theme';
import { navBarVisibleOnAppear, navBarVisibleOnChange } from '../../util/navBarReset';
import { rememberSplitNavWidth, resolveSplitNavWidth } from '../../util/splitNavWidth';
import { APPEARANCE_EPOCH } from '../../util/appearance';
import { mainPageFill } from '../../util/theme';
import { KEY_APP_BG_ON } from '../../store/AppSettings';

// 卡片底色 + 毛玻璃。开关关着时 surfaceGlassFill 原样返回实色、
// cardBlurStyle 返回 undefined，和改动前逐字节等价（见 util/surfaceGlass）。
const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
// 联系人行是**一行一张卡片**（2026-10-29 用户要求与首页同款）：圆角 16、
// 相邻两张之间 3+3 = 6vp，都与首页会话卡片对齐（见 pages/chatlist/ChatRow）。
const CONTACT_CARD_RADIUS: number = 16;
const CONTACT_CARD_GAP_VP: number = 3;
const SEARCH_BAR_HEIGHT: number = 46;
const SEARCH_DELAY_MS: number = 350;
const CONTACT_LONG_PRESS_MS: number = 500;
// 可视区外多备的行数。联系人行没有逐行玻璃，建一行很便宜（首页会话行有玻璃，只备 2 行）。
const CONTACT_LIST_CACHED_COUNT: number = 4;
const SKELETON_ROWS: number[] = [0, 1, 2, 3, 4];

// 联系人页签分栏时左栏的实际宽度，vp。与聊天页签的 NAV_BAR_WIDTH_KEY、设置
// 页签的 SETTINGS_NAV_BAR_WIDTH_KEY 同一个用途、**第三个键**：三个页签各有一个
// HdsNavigation、各自 enableDragBar(true)，用户把其中一条分割线拖开之后左栏
// 宽度就不再相等，共用一个键会让 dock 在另外两个页签上与左栏错开。
export const CONTACTS_NAV_BAR_WIDTH_KEY: string = 'contactsNavBarWidth';

// 联系人页签的 navBar 此刻是否可见。**等价于「不是（单栏且联系人栈非空）」**，
// 与 CHAT_NAV_BAR_VISIBLE_KEY / SETTINGS_NAV_BAR_VISIBLE_KEY 同构：分栏（平板）
// 下左栏常驻，恒为 true；单栏（手机）下推入 NavDestination 后 navBar 被系统隐藏，
// false。
// MainScreen 靠它决定悬浮 dock 藏不藏——NavDestination 不是盖住整个 MainScreen
// 的整页 router 页，dock 会浮在它上面，必须显式藏。
// 手机上本页**不推任何目的地**（见 openContact 的断点分流），所以这个键在手机
// 上恒为 true，dock 行为与改造前逐字相同。
export const CONTACTS_NAV_BAR_VISIBLE_KEY: string = 'contactsNavBarVisible';

// 分栏且右栏栈空时的占位。官方明确它仅在分栏模式下展示、不受路由栈管理、
// 不可获焦、不响应事件，是纯展示层；单栏模式（手机）下永远不出现。
//
// 写成模块级函数而不是 struct 里的 @Builder 成员：splitPlaceholder 收的是
// ComponentContent，要 wrapBuilder() 包一层，而 wrapBuilder 只接全局 @Builder。
// 与 ChatListPage 的 splitPanePlaceholder 同一个形状，只是文案不同。
@Builder
function contactsSplitPlaceholder(): void {
  Column({ space: 12 }) {
    Image($r('app.media.foreground'))
      .width(64).height(64).opacity(0.45)
      .draggable(false);
    Text($r('app.string.split_pick_a_contact'))
      .fontSize(14)
      .fontColor(COLOR_TEXT_SECONDARY);
  }
  .width('100%').height('100%')
  .justifyContent(FlexAlign.Center)
  .backgroundColor($r('app.color.page_bg'));
}

// The contacts tab: search box, recent-calls shortcut, and the contact
// list sorted by name. Title shows 正在刷新... until getContacts resolves.
@Preview
// 组件冻结：这四个页签由 MainScreen 的 Tabs 保活，同一时刻只有一个在屏上，
// 其余三棵树却照样响应各自 store 的状态更新、照样重跑 build。冻结之后非
// 激活的页签不再刷新，切回来时框架补上延后的那次更新。
@Component({ freezeWhenInactive: true })
export struct ContactsPage {
  // 由 MainScreen 算好写进来的「APP 壁纸生效中」，见 store/AppSettings。
  @StorageProp(KEY_APP_BG_ON) private appWallpaperOn: boolean = false;
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  // 全局界面模糊：开关和档位都要能立刻重绘。开关本身是 AppStorage 键，
  // 档位走 epoch（surfaceGlass 是 util，订阅不了 AppStorage，同 MATERIAL_EPOCH 的做法）。
  @StorageProp(KEY_SURFACE_GLASS_ON) private surfaceGlassOn: boolean = SURFACE_GLASS_ON_DEFAULT;
  @StorageProp(SURFACE_GLASS_EPOCH) private surfaceGlassEpoch: number = 0;

  // `this.surfaceGlassEpoch >= 0` 恒真，**但不能删**：@StorageProp 只有在 build
  // 链路里被真正读到才建立依赖，光声明不读，改设置时页面不会重绘。
  private glassOn(): boolean {
    return this.surfaceGlassOn && this.surfaceGlassEpoch >= 0;
  }

  private cardFill(): ResourceColor {
    return this.glassOn() ? surfaceGlassFill(CARD_BG) : CARD_BG;
  }

  // 框架容器材质，不是 backdropBlur——后者在节点边缘有采样衰减，四角最明显
  // （见 util/surfaceGlass.surfaceGlassBlurStyle）。
  private cardBlurStyle(): BlurStyle | undefined {
    return this.glassOn() ? surfaceGlassBlurStyle() : undefined;
  }

  private contactsScroller: ListScroller = new ListScroller();
  // 列表实测高度（vp）：linearGradientBlur 的 fractionStops 要按实际高度归一化。
  @State private contactsViewH: number = 0;
  private alphabet: ContactAlphabetIndex = new ContactAlphabetIndex();
  private orderedContacts: ContactItem[] = [];
  // 联系人卡片的 LazyForEach 数据源，喂的是 filtered() 那一份（见 onContactListInputChanged）。
  private contactsData: KeyedListDataSource<ContactItem> = new KeyedListDataSource<ContactItem>('contacts');
  // 联系人页签的路由栈。平板（分栏）上点一个联系人会把 ProfilePage 推进这里，
  // 它就是右栏；手机（单栏）上这个栈恒为空——见 openContact 的断点分流。
  private contactsStack: NavPathStack = new NavPathStack();
  // 右栏空态。ComponentContent 是节点实体，建一次留着——每次 build 都 new 一个
  // 等于每帧重建一棵子树。
  private splitPlaceholder: SplitPlaceholderHolder = new SplitPlaceholderHolder();
  // 右栏空态是一棵脱离主树的 ComponentContent，深浅色切换不会重解析它的资源
  // ——必须自己丢掉重建，否则夜间模式下左栏和会话页都变深、只有右栏空态还是
  // 浅色（平板实测）。详见 util/splitPlaceholderHolder。
  @StorageProp(KEY_APP_DARK) @Watch('onAppDarkChanged') private appDark: boolean = false;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 平板上不把一列内容拉满整屏——见 util/contentWidth。窗口宽（不是屏幕宽），
  // 分屏 / 悬浮窗 / 折叠屏改变窗口时 EntryAbility 的 windowSizeChange 会刷新它。
  @StorageProp('screenWidthVp') @Watch('onWindowResized') screenW: number = 360;
  // 设置里的「强制单栏」（宽屏也当手机用）。
  @StorageProp(KEY_FORCE_SINGLE_COLUMN) forceSingleColumn: boolean = false;
  // 分栏判据读系统横向 + 纵向断点（util/layoutBreakpoint.isSplitByBreakpoint）——只看宽的话
  // 手机一转横屏就被当成平板（#125）。
  @StorageProp('screenHeightVp') @Watch('onWindowResized') screenH: number = 780;
  // 系统断点（util/layoutBreakpoint）：分栏判据读它，不再按窗口宽高自己算。
  @StorageProp(KEY_WIDTH_BREAKPOINT) widthBp: number = WIDTH_BP_SM;
  @StorageProp(KEY_HEIGHT_BREAKPOINT) heightBp: number = HEIGHT_BP_LG;
  @StorageProp(KEY_WINDOW_PORTRAIT) windowPortrait: boolean = true;
  // 平板分栏下记住的左栏宽度（issue #106），见 util/splitNavWidth。
  @StorageProp(KEY_SPLIT_NAV_WIDTH) private savedNavW: number = 0;
  @State @Watch('onContactListInputChanged') contacts: ContactItem[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State @Watch('onContactListInputChanged') query: string = '';
  @State @Watch('onContactListInputChanged') remoteUsers: ContactItem[] = [];
  @State remoteLoading: boolean = false;
  @State searchFocused: boolean = false;
  @State pressedContactId: number = 0;
  @State openingContactId: number = 0;
  @State deletingContactId: number = 0;
  // 正在消散的那一行：id + 强度。DissolveDeleteEffect 只认「这一行」，所以强度
  // 单独放一份，没被删的行拿到 0（见 listCard 里的接线）。
  @State private deleteLeavingId: number = 0;
  @State private deleteLeavingStrength: number = 0;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_PARTICLES) particlesEnabled: boolean = true;
  @State contextMenuShown: boolean = false;
  @State menuContactId: number = 0;
  @State menuContactName: string = '';
  @State skeletonBright: boolean = false;
  @State addContactSheetOpen: boolean = false;
  @State addFirstName: string = '';
  @State addLastName: string = '';
  @State addPhone: string = '';
  @State addContactError: string = '';
  @State addContactSaving: boolean = false;
  private store: ContactsStore | null = null;
  private unsub: (() => void) | null = null;
  private searchTimer: number = -1;
  private searchSequence: number = 0;
  private actionUnlockTimer: number = -1;
  private actionNavigationLocked: boolean = false;
  private chatOpenSequence: number = 0;
  private deleteSequence: number = 0;
  // 删除走的是会话列表那套「先等消散、再提交请求、失败复原」的通道
  // （util/confirmedChatRemoval + DissolveDeleteEffect），联系人页自己不再写一份。
  private contactRemoval: ConfirmedChatRemoval = new ConfirmedChatRemoval();
  private contactLeaveUnsub: (() => void) | null = null;
  // 对话框弹着 / 消散进行中的同步闸。deletingContactId 是给行看的状态，晚一步再置。
  private deleteInFlight: boolean = false;
  private addContactSequence: number = 0;
  private skeletonTimer: number = -1;
  private contactPressActive: boolean = false;
  // 按住 / 菜单期间被推迟的列表输入变化（见 onContactListInputChanged）。
  private listInputDirty: boolean = false;
  // 长按菜单对应的联系人，开菜单时记下、菜单收起时**不清**（见 confirmDeleteContact）。
  private deleteTargetId: number = 0;
  private deleteTargetName: string = '';
  private contactPressId: number = 0;
  private contactPressIndex: number = -1;
  private contactPressVersion: string = '';
  private contactPressConsumedByMenu: boolean = false;
  private pendingContacts: ContactItem[] | null = null;
  private pendingLoading: boolean = false;
  private pendingLoadError: string = '';

  // **常态不设 backgroundColor**：底色由上面的 overlayGlassFill 决定，
  // 这里再刷一次透明就把那层玻璃盖掉了（和首页 actionNormalStyle 一致）。
  @Styles
  topActionNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  retryNormalStyle() {
    .backgroundColor($r('app.color.selected_pill'))
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  retryPressedStyle() {
    .backgroundColor($r('app.color.selected_pill'))
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  // 窗口尺寸一变，分栏与否可能跟着翻（平板分屏、悬浮窗、旋转、折叠屏都会），
  // navBar 的真实显隐也跟着翻——而此前**没有任何东西会重算那个标志**：它只由
  // onNavBarStateChange 写。那是框架给的回调，既保证不了它在每一次 mode 翻转时
  // 都来，回调里那道兜底闸读的 screenW/screenH 又是 AppStorage 里由 EntryAbility
  // 的 windowSizeChange 另行刷新的值，两者先后无定。任何一边落空，标志就停在
  // true，dock 于是浮在详情页上不收（用户实报「Pad 版 dock 偶尔不回收」，
  // 聊天页签那处有完整推导）。
  //
  // 这里按标志的**定义**重算：分栏 → 恒可见；单栏 → 栈空才可见。与
  // aboutToAppear 的复位同一个判据（util/navBarReset），值没变时不写。
  private onWindowResized(): void {
    const isVisible: boolean = navBarVisibleOnAppear(
      isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait), this.contactsStack.size());
    if (AppStorage.get<boolean>(CONTACTS_NAV_BAR_VISIBLE_KEY) !== isVisible) {
      AppStorage.setOrCreate<boolean>(CONTACTS_NAV_BAR_VISIBLE_KEY, isVisible);
    }
  }

  aboutToAppear(): void {
    // 全局注册表取栈：与聊天/设置两个页签同构。本页目前只有一个入口
    // （openContact），但注册进去之后 profileNav 才能按 tab 参数推进来，
    // 也才有可能在页面之外触发（将来的「联系人」深链）。
    registerStack('contacts', this.contactsStack as NavStackLike);
    // 栈没注册时被挂起的跳转（冷启动点通知、登录前的深链）在这里放出去。
    // **延一拍**：官方明确"不建议在 aboutToAppear 中操作栈，此时页面还未构建
    // 完成"，而这里正是 aboutToAppear。见 util/pendingNav 的事故说明。
    setTimeout((): void => { flushPendingNavs('contacts'); }, 0);
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
    AppStorage.setOrCreate<boolean>(CONTACTS_NAV_BAR_VISIBLE_KEY,
      navBarVisibleOnAppear(isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait), this.contactsStack.size()));
    this.releaseActionLock();
    const store = new ContactsStore(getTdClient());
    this.store = store;
    this.unsub = store.subscribe(() => {
      this.applyContacts(store.contacts, store.loading, store.errorMessage);
    });
    store.open();
    this.onContactListInputChanged();
  }

  // 夜间模式切换：右栏空态要整棵重建，见字段处的说明。
  private onAppDarkChanged(): void {
    this.splitPlaceholder.invalidate();
  }

  aboutToDisappear(): void {
    this.alphabet.clear();
    this.orderedContacts = [];
    // ComponentContent 是脱离组件树管理的节点实体，得自己释放。
    this.splitPlaceholder.dispose();
    this.stopSkeletonPulse();
    this.releaseActionLock();
    this.pressedContactId = 0;
    this.openingContactId = 0;
    this.deletingContactId = 0;
    this.addContactSheetOpen = false;
    this.addContactSaving = false;
    this.contextMenuShown = false;
    this.menuContactId = 0;
    this.contactPressActive = false;
    this.pendingContacts = null;
    this.listInputDirty = false;
    this.chatOpenSequence++;
    this.deleteSequence++;
    this.deleteInFlight = false;
    this.detachContactLeaving();
    this.addContactSequence++;
    this.searchSequence++;
    this.remoteLoading = false;
    this.searchFocused = false;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private onQueryChanged(value: string): void {
    this.query = value;
    this.scheduleRemoteSearch(value, SEARCH_DELAY_MS);
  }

  private scheduleRemoteSearch(value: string, delayMs: number): void {
    const sequence = ++this.searchSequence;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    const normalized = value.trim().replace(/^@/, '');
    if (normalized.length < 2) {
      this.remoteUsers = [];
      this.remoteLoading = false;
      return;
    }
    this.remoteLoading = true;
    const run = (): void => {
      this.searchTimer = -1;
      searchPublicUsers(getTdClient(), value).then((users: ContactItem[]): void => {
        if (sequence !== this.searchSequence) {
          return;
        }
        this.remoteUsers = users;
        this.remoteLoading = false;
      }).catch((error: TdError): void => {
        if (sequence !== this.searchSequence) {
          return;
        }
        logW(`ContactsPage.searchPublicUsers failed: ${error.message}`);
        this.remoteUsers = [];
        this.remoteLoading = false;
      });
    };
    if (delayMs <= 0) {
      run();
    } else {
      this.searchTimer = setTimeout(run, delayMs);
    }
  }

  private submitSearch(): void {
    if (this.query.trim().replace(/^@/, '').length < 2) {
      return;
    }
    this.scheduleRemoteSearch(this.query, 0);
  }

  private clearSearch(): void {
    this.onQueryChanged('');
  }

  private startSkeletonPulse(): void {
    if (this.skeletonTimer !== -1 ||
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1) === 0) {
      return;
    }
    this.skeletonTimer = setInterval((): void => {
      this.skeletonBright = !this.skeletonBright;
    }, 680);
  }

  private stopSkeletonPulse(): void {
    if (this.skeletonTimer !== -1) {
      clearInterval(this.skeletonTimer);
      this.skeletonTimer = -1;
    }
    this.skeletonBright = false;
  }

  private applyContacts(next: ContactItem[], nextLoading: boolean, nextError: string): void {
    // 手指按在行上时也先攒着：在线状态每 500ms 合批刷新一次、会整表按最近上线重排，
    // 而长按判定也是 500ms——按住期间有人上线，被按的行就挪位 / 重建，长按校验失败
    // 直接丢掉（「长按不好使」）。抬手（endContactPress）或菜单关掉时再一次性落地。
    if (this.contextMenuShown || this.contactPressActive) {
      this.pendingContacts = next;
      this.pendingLoading = nextLoading;
      this.pendingLoadError = nextError;
      return;
    }
    if (nextLoading && next.length === 0) {
      this.startSkeletonPulse();
    } else {
      this.stopSkeletonPulse();
    }
    // 换数据不再包进 animateTo：列表走 LazyForEach 之后，一次重排（有人上线挪到最前）
    // 在动画上下文里做，等于让整张列表的可视行一起进动画布局。几张状态卡片之间的切换
    // 各自带着 transition，淡入淡出不受影响。
    this.contacts = next;
    this.loading = nextLoading;
    this.loadError = nextError;
  }

  private flushPendingContacts(): void {
    const pending = this.pendingContacts;
    if (pending === null) {
      return;
    }
    const loading = this.pendingLoading;
    const error = this.pendingLoadError;
    this.pendingContacts = null;
    this.applyContacts(pending, loading, error);
  }

  private retryContacts(): void {
    if (this.store !== null && !this.loading) {
      this.store.reload();
    }
  }

  private openAddContactSheet(): void {
    if (this.contextMenuShown || this.addContactSaving) {
      return;
    }
    this.addFirstName = '';
    this.addLastName = '';
    this.addPhone = '';
    this.addContactError = '';
    this.addContactSheetOpen = true;
  }

  private phoneDigits(value: string): string {
    let digits = '';
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code >= 48 && code <= 57) {
        digits += value.charAt(index);
      }
    }
    return digits;
  }

  // 归类在 util/contactAddError（纯函数，带单测），这里只负责翻成文案。
  private contactErrorText(kind: string): string {
    if (kind === CONTACT_ERR_BAD_PHONE) {
      return str('ct_bad_phone');
    }
    if (kind === CONTACT_ERR_NO_USER) {
      return str('ct_no_user');
    }
    if (kind === CONTACT_ERR_NETWORK) {
      return str('network_failed_retry');
    }
    return str('ct_add_failed');
  }

  private finishContactAdded(sequence: number, name: string): void {
    if (sequence !== this.addContactSequence) {
      return;
    }
    this.addContactSaving = false;
    this.addContactSheetOpen = false;
    promptAction.showToast({ message: str('ct_added', name), duration: 1800 });
    if (this.store !== null) {
      this.store.reload();
    }
  }

  private failContactAdd(sequence: number, kind: string): void {
    if (sequence !== this.addContactSequence) {
      return;
    }
    this.addContactSaving = false;
    this.addContactError = this.contactErrorText(kind);
  }

  // 每一步失败的统一出口：能换条路就换，不能就报错收工。
  //
  // 日志带上 code——原来只记 message，2026-10-30 查「无法添加联系人，请重试」
  // 时手上什么错误码都没有，只能回头改代码加日志。
  private nextContactStep(error: TdError, step: string, sequence: number, next: () => void): void {
    if (sequence !== this.addContactSequence) {
      return;
    }
    const kind: string = contactAddErrorKind(error.message);
    logE(`ContactsPage.${step} failed(code=${error.code}) kind=${kind}`);
    if (contactErrorRecoverable(kind)) {
      next();
      return;
    }
    this.failContactAdd(sequence, kind);
  }

  private submitNewContact(): void {
    if (this.addContactSaving) {
      return;
    }
    const firstName: string = this.addFirstName.trim();
    const lastName: string = this.addLastName.trim();
    const phone: string = this.phoneDigits(this.addPhone);
    if (firstName === '') {
      this.addContactError = str('ct_enter_first_name');
      return;
    }
    if (phone.length < 6 || phone.length > 15) {
      this.addContactError = str('ct_enter_phone');
      return;
    }
    this.addContactError = '';
    this.addContactSaving = true;
    const sequence: number = ++this.addContactSequence;
    const name: string = firstName + (lastName !== '' ? ' ' + lastName : '');
    this.stepSearchUser(phone, firstName, lastName, name, sequence);
  }

  // 加号码到联系人：三步，一步比一步兜底。
  //
  //   1. searchUserByPhoneNumber  —— 按号码把人找回来
  //   2. addContact(user_id)      —— 拿着找到的 id 再加
  //   3. importContacts           —— 交给服务器按号码导入（官方客户端同款路径）
  //
  // 【为什么不是原来那一步】原来直接 addContact(user_id=0, phone)，等于把"按号码
  // 解析用户"整个甩给 TDLib；解析不到就报 400 User not found，而这条路一层兜底
  // 都没有。ProfilePage 早就踩过同一个坑（那边注释写着），这里照那边的做法补齐。
  // 第 3 步返回的 user_ids[0] > 0 才算真的加上了——为 0 表示服务器解析不到这个人
  // （对方隐私设置或号码没注册），此时该说"未找到使用此号码的用户"。
  private stepSearchUser(phone: string, first: string, last: string, name: string,
    sequence: number): void {
    const lookup: TdRequest = searchUserByPhoneNumberRequest(phone);
    getTdClient().send(lookup, 10000).then((user: TdObject): void => {
      if (sequence !== this.addContactSequence) {
        return;
      }
      const foundId: number | undefined = user['id'] as number | undefined;
      if (foundId === undefined || foundId <= 0) {
        this.stepImportContacts(phone, first, last, name, sequence);
        return;
      }
      this.stepAddKnownUser(phone, first, last, name, sequence, foundId);
    }).catch((error: TdError): void => {
      this.nextContactStep(error, 'searchUserByPhoneNumber', sequence,
        (): void => this.stepImportContacts(phone, first, last, name, sequence));
    });
  }

  private stepAddKnownUser(phone: string, first: string, last: string, name: string,
    sequence: number, userId: number): void {
    const request: TdRequest = addContactRequest(userId, phone, first, last);
    getTdClient().send(request, 10000).then((): void => {
      this.finishContactAdded(sequence, name);
    }).catch((error: TdError): void => {
      this.nextContactStep(error, 'addContact', sequence,
        (): void => this.stepImportContacts(phone, first, last, name, sequence));
    });
  }

  private stepImportContacts(phone: string, first: string, last: string, name: string,
    sequence: number): void {
    const request: TdRequest = importContactsRequest(phone, first, last);
    getTdClient().send(request, 15000).then((result: TdObject): void => {
      if (sequence !== this.addContactSequence) {
        return;
      }
      const userIds: number[] = (result['user_ids'] as number[] | undefined) ?? [];
      if (userIds.length > 0 && userIds[0] > 0) {
        this.finishContactAdded(sequence, name);
        return;
      }
      this.failContactAdd(sequence, CONTACT_ERR_NO_USER);
    }).catch((error: TdError): void => {
      if (sequence !== this.addContactSequence) {
        return;
      }
      logE(`ContactsPage.importContacts failed(code=${error.code}): ${error.message}`);
      this.failContactAdd(sequence, contactAddErrorKind(error.message));
    });
  }

  private releaseActionLock(): void {
    if (this.actionUnlockTimer !== -1) {
      clearTimeout(this.actionUnlockTimer);
      this.actionUnlockTimer = -1;
    }
    this.actionNavigationLocked = false;
  }

  private openRecentCalls(): void {
    if (this.actionNavigationLocked) {
      return;
    }
    this.actionNavigationLocked = true;
    // Guard the current page against a rapid double tap. The lock is also
    // released when this page disappears, so returning never leaves it stuck.
    this.actionUnlockTimer = setTimeout((): void => {
      this.actionUnlockTimer = -1;
      this.actionNavigationLocked = false;
    }, 500);
    router.pushUrl({ url: 'pages/main/CallsPage' }).catch((error: Error): void => {
      logE(`ContactsPage.openRecentCalls failed: ${error.message}`);
      this.releaseActionLock();
    });
  }

  // 分栏的三个宽度。算法在 util/splitMetrics.ets（含 40% 上限、拖拽行程、
  // 与 minContentWidth 不打架三条约束的推导），这里只把当前窗口宽喂进去。
  // 与聊天/设置两个页签用的是同一组函数：三个页签的左栏静息宽度因此一致，
  // dock 在页签之间切换时不会跳一下。
  private navBarMinWidth(): number {
    return splitNavMinWidth(this.screenW);
  }

  private navBarMaxWidth(): number {
    return splitNavMaxWidth(this.screenW);
  }

  private contentMinWidth(): number {
    return splitContentMinWidth(this.screenW);
  }

  // splitPlaceholder 收的是 ComponentContent，不是 @Builder 引用——直接传
  // this.xxx 那种写法编译不过。懒建一次：build 每帧都跑，在这里 new 就是
  // 每帧重建一棵子树。
  private placeholderContent(): ComponentContent<Object> {
    return this.splitPlaceholder.content(this.getUIContext(), wrapBuilder(contactsSplitPlaceholder));
  }

  // 点一个联系人。**按断点分流**，这是本页在平板上的核心行为差异：
  //
  //   单栏（手机、手机横屏）→ openChatWith()，直接开会话。
  //     与改造前**逐字相同**——它调的就是那个一个字没动的 openChatWith()。
  //   分栏（平板、折叠屏展开）→ 右栏开 ProfilePage，页内「发消息」再开会话。
  //     右栏放资料页符合官方《多设备即时通讯界面》范例（通讯录页 lg 断点的
  //     右栏就是联系人主页）。
  //
  // 为什么不统一成「都开资料页」：手机是单栏、右栏根本不存在，推 ProfilePage
  // 就是整页替换——用户点联系人会看到资料页而不是会话，要多点一次才能发消息。
  // 那是手机端的行为变更。官方《一次开发多端部署》4.2.1 明确认可按断点做差异化
  // 交互，所以这里是分流而不是取其一。
  //
  // 判据见 util/layoutBreakpoint.isSplitByBreakpoint（系统横向 + 纵向断点）。
  //
  // 【这里原先写的是"和 HdsNavigation 内部 NavigationMode.Auto 用的是同一条线"，
  // 那句话是错的，2026-08-22 手机模拟器上被推翻】440vp 的窗口 Auto 照样进分栏。
  // 现在 build() 里显式给了 .mode()，两边真的同源了——但同源的原因是我们自己
  // 把它钉死，不是 Auto 恰好也这么想。
  //
  // screenW 是**窗口宽**
  // 不是屏幕宽（AppStorage 'screenWidthVp'，见字段处的注释），分屏/悬浮窗下才不会
  // 与组件实际的单双栏状态相反。
  private openContact(contact: ContactItem): void {
    if (!isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait)) {
      this.openChatWith(contact.id);
      return;
    }
    // 与 openChatWith 同一道闸：正在开会话或正在删联系人时不接受新的点击。
    // 复制而不是共用，是因为 openChatWith 的函数体必须保持一个字不动。
    if (this.openingContactId !== 0 || this.deletingContactId !== 0) {
      return;
    }
    // 资料页只吃 userId，没有 createPrivateChat 那一步异步——所以既不需要
    // openingContactId 的 spinner，也不需要 chatOpenSequence 的乱序保护。
    const params: Record<string, Object> = { 'userId': contact.id };
    // 'contacts' 让 profileNav 推进本页签自己的栈（默认仍是 'chat'，聊天线的
    // 八个调用点不受影响），并按 'navbar' 语义清栈——连点两个联系人是替换右栏，
    // 不是叠第二层。
    navigateToProfile(params, 'contacts');
  }

  // Ensure the private chat exists (TDLib may not have it loaded yet), then
  // navigate into it — same pattern as ProfilePage.sendMessage.
  private openChatWith(userId: number): void {
    if (this.openingContactId !== 0 || this.deletingContactId !== 0) {
      return;
    }
    const sequence = ++this.chatOpenSequence;
    this.openingContactId = userId;
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = userId;
    req['force'] = false;
    getTdClient().send(req, 8000).then((chat: TdObject): void => {
      if (sequence !== this.chatOpenSequence) {
        return;
      }
      this.openingContactId = 0;
      const id = chat['id'] as number | undefined;
      if (id !== undefined) {
        const params: Record<string, Object> = { 'chatId': id };
        navigateToChat(params).catch(logChatNavFailure);
      }
    }).catch((e: TdError): void => {
      if (sequence !== this.chatOpenSequence) {
        return;
      }
      this.openingContactId = 0;
      logE(`ContactsPage.createPrivateChat failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.open_chat_failed'), duration: 1800 });
    });
  }

  private contactVersion(contact: ContactItem): string {
    return `${contact.id}_${contact.avatarPath}_${contact.name}_${contact.statusText}_${contact.online ? 1 : 0}`;
  }

  private contactListVersion(contact: ContactItem): string {
    return `${this.contactVersion(contact)}_${this.query.trim() === '' ? this.alphabet.heading(contact.id) : ''}`;
  }

  private visibleContactIndex(userId: number): number {
    return this.filtered().findIndex((contact: ContactItem): boolean => contact.id === userId);
  }

  private beginContactPress(contact: ContactItem): void {
    // 菜单真开着时有模态遮罩，手指碰不到行。能在这里收到按下，说明菜单早就不在了，
    // 只是 onDisappear 没来（宿主行在菜单开着时被重建等），标记卡成 true 会把行点击、
    // 添加按钮和列表滚动一起锁死（「按钮不好使」）。就地复位。
    if (this.contextMenuShown) {
      this.onContactMenuDisappear();
    }
    const local = this.contacts.find((item: ContactItem): boolean => item.id === contact.id);
    this.contactPressConsumedByMenu = false;
    this.contactPressActive = local !== undefined && this.deletingContactId === 0;
    this.contactPressId = contact.id;
    this.contactPressIndex = this.visibleContactIndex(contact.id);
    this.contactPressVersion = local !== undefined ? this.contactVersion(local) : '';
  }

  private endContactPress(): void {
    if (!this.contactPressActive) {
      return;
    }
    this.contactPressActive = false;
    this.flushDeferredListUpdates();
  }

  // 按住 / 菜单期间攒下的联系人数据与列表输入，在松手或菜单关掉后一次落地。
  private flushDeferredListUpdates(): void {
    if (this.contextMenuShown || this.contactPressActive) {
      return;
    }
    this.flushPendingContacts();
    if (this.listInputDirty) {
      this.listInputDirty = false;
      this.onContactListInputChanged();
    }
  }

  // 按压态的 110ms 过渡。原来是行上常驻的 .animation()；行抽成复用组件后不再挂它
  // （复用时每换一次数据都会被同步冲刷，见 ContactRowView 的说明），改在按压态真正
  // 变化的那一刻驱动一次。
  private setPressedContact(id: number): void {
    if (this.pressedContactId === id) {
      return;
    }
    this.getUIContext().animateTo({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
      curve: Curve.EaseOut
    }, (): void => {
      this.pressedContactId = id;
    });
  }

  private openContactMenuIfCurrent(contact: ContactItem): void {
    const current = this.contacts.find((item: ContactItem): boolean => item.id === contact.id);
    const unchanged = this.contactPressActive
      && this.contactPressId === contact.id
      && current !== undefined
      && this.contactVersion(current) === this.contactPressVersion
      && this.visibleContactIndex(contact.id) === this.contactPressIndex;
    this.contactPressActive = false;
    this.pressedContactId = 0;
    if (!unchanged) {
      // A status/avatar/search refresh moved or rebuilt the row while the
      // recognizer was waiting. Ignore this hold instead of lifting stale UI.
      this.flushDeferredListUpdates();
      return;
    }
    this.contactPressConsumedByMenu = true;
    this.menuContactId = contact.id;
    this.menuContactName = current !== undefined ? current.name : contact.name;
    this.deleteTargetId = this.menuContactId;
    this.deleteTargetName = this.menuContactName;
    this.contextMenuShown = true;
  }

  private onContactMenuDisappear(): void {
    this.contextMenuShown = false;
    this.menuContactId = 0;
    this.menuContactName = '';
    this.pressedContactId = 0;
    this.contactPressActive = false;
    this.flushDeferredListUpdates();
  }

  private confirmDeleteContact(): void {
    // 读开菜单时另存的那一份，不读 menuContactId：点菜单项时菜单同时收起，
    // onDisappear 可能先于这里的 onClick 跑完并把 menuContactId 清零，删除就静默没了。
    const userId = this.deleteTargetId;
    const name = this.deleteTargetName;
    if (userId <= 0 || name === '') {
      return;
    }
    // 走 showMenuDialog：菜单收起过程中直接调全局 promptAction.showDialog 会静默
    // 挂死（详见面数见 pages/common/menuDialog），界面上连确认框都不会出现。
    showMenuDialog(this.getUIContext(), {
      title: $r('app.string.ct_delete'),
      message: str('ct_delete_confirm', name),
      buttons: [
        { text: $r('app.string.cancel'), color: COLOR_TEXT_SECONDARY as string },
        { text: $r('app.string.delete'), color: '#E64646' }
      ]
    }, 'ContactsPage.deleteContact', (index: number): void => {
      if (index === 1) {
        this.deleteContact(userId, name);
      }
    });
  }

  // 确认删除：先让这一行消散（与会话列表同一套粒子），动画结束再提交请求；
  // 请求失败把行复原并提示，不留一个已经"看上去没了"却还在的联系人。
  private deleteContact(userId: number, name: string): void {
    if (this.store === null || this.deleteInFlight) {
      return;
    }
    const store = this.store;
    const sequence = this.deleteSequence;
    this.deleteInFlight = true;
    this.attachContactLeaving(userId);
    const animate: boolean = !this.powerSaving && this.particlesEnabled &&
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 550) > 0;
    this.contactRemoval.perform(userId, animate,
      (): boolean => this.store === store && this.deleteSequence === sequence,
      (): Promise<boolean> => {
        this.deletingContactId = userId;
        return store.removeContact(userId).then((): boolean => true).catch((error: TdError): boolean => {
          logE(`ContactsPage.removeContact failed(code=${error.code}): ${error.message}`);
          return false;
        });
      })
      .then((success: boolean): void => {
        if (sequence !== this.deleteSequence) {
          return;
        }
        this.finishContactDelete(userId, name, success);
      })
      .catch((error: Object): void => {
        if (sequence !== this.deleteSequence) {
          return;
        }
        logE(`ContactsPage.deleteContact failed: ${JSON.stringify(error)}`);
        this.finishContactDelete(userId, name, false);
      });
  }

  private finishContactDelete(userId: number, name: string, success: boolean): void {
    this.deleteInFlight = false;
    this.deletingContactId = 0;
    // 失败时通道已经把 leaving 撤掉（行复原），这里只需断开订阅。
    this.detachContactLeaving();
    promptAction.showToast({
      message: success ? str('ct_deleted', name) : $r('app.string.ct_delete_failed'),
      duration: success ? 1600 : 1800
    });
  }

  // 订阅这一行的消散强度。必须在 perform 之前挂上：通道只等「有订阅者」的行，
  // 没订阅等于没挂载，play() 会直接返回、动画一步都不走。
  private attachContactLeaving(userId: number): void {
    this.detachContactLeaving();
    this.deleteLeavingId = userId;
    this.contactLeaveUnsub = this.contactRemoval.channel.subscribe(userId,
      (strength: number): void => { this.deleteLeavingStrength = strength; });
  }

  private detachContactLeaving(): void {
    if (this.contactLeaveUnsub !== null) {
      this.contactLeaveUnsub();
      this.contactLeaveUnsub = null;
    }
    this.deleteLeavingStrength = 0;
    this.deleteLeavingId = 0;
  }

  private filtered(): ContactItem[] {
    const q = this.query.trim().toLowerCase();
    if (q === '') {
      return this.orderedContacts;
    }
    const localQuery = q.replace(/^@/, '');
    const result = this.orderedContacts.filter((c: ContactItem): boolean =>
      c.name.toLowerCase().includes(localQuery) ||
        c.statusText.toLowerCase().includes(q)
    );
    for (const user of this.remoteUsers) {
      if (!result.some((item: ContactItem): boolean => item.id === user.id)) {
        result.push(user);
      }
    }
    return result;
  }

  // 联系人 / 搜索词 / 全网搜索结果任一变化：把「当下要显示的那一份」交给 LazyForEach。
  // key 用 contactVersion——与长按菜单的版本校验同一份签名，内容变了才会发 CHANGE。
  private onContactListInputChanged(): void {
    // 全网搜索结果可能在按住 / 菜单开着时到达：此刻换数据源会重建被按的行（菜单的
    // 宿主），onDisappear 就可能不来。记一笔，松手 / 关菜单后再换。
    if (this.contextMenuShown || this.contactPressActive) {
      this.listInputDirty = true;
      return;
    }
    this.orderedContacts = this.alphabet.sort(this.contacts);
    const list: ContactItem[] = this.filtered();
    this.contactsData.update(list,
      list.map((c: ContactItem): string => `${c.id}`),
      list.map((c: ContactItem): string => this.contactListVersion(c)));
  }

  @Builder
  searchBox() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([this.searchFocused ? this.accent() : COLOR_ICON_SECONDARY])
        .animation({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
          curve: Curve.EaseOut
        });
      TextInput({ text: this.query, placeholder: $r('app.string.ct_search_hint') })
        .layoutWeight(1).height(38).fontSize(16)
        .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
        .placeholderColor(COLOR_TEXT_SECONDARY)
        .caretColor(this.accent())
        .enterKeyType(EnterKeyType.Search)
        .onFocus((): void => { this.searchFocused = true; })
        .onBlur((): void => { this.searchFocused = false; })
        .onSubmit((): void => { this.submitSearch(); })
        .onChange((v: string): void => { this.onQueryChanged(v); });
      if (this.remoteLoading) {
        LoadingProgress()
          .width(18).height(18)
          .color(this.accent())
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
              curve: Curve.EaseOut
            }));
      } else if (this.query !== '') {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(19).fontColor([COLOR_ICON_SECONDARY]);
        }
        .width(32).height(32)
        .borderRadius(16)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.topActionNormalStyle,
          pressed: this.topActionPressedStyle
        })
        .accessibilityText($r('app.string.clear_search'))
        .onClick((): void => { this.clearSearch(); })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.72, y: 0.72 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
            curve: Curve.EaseOut
          }));
      }
    }
    .width(`calc(100% - ${this.cardGutter() * 2}vp)`)
    .height(SEARCH_BAR_HEIGHT)
    .padding({ left: 13, right: 9 })
    .backgroundColor(this.cardFill())
    .backgroundBlurStyle(this.cardBlurStyle())
    .borderRadius(SEARCH_BAR_HEIGHT / 2)
    .border({
      width: this.searchFocused ? 1.5 : 0.5,
      color: this.searchFocused ? this.accent() : COLOR_DIVIDER
    })
    .alignItems(VerticalAlign.Center)
    // 与下方联系人卡片同一条外沿。
    .margin({ left: this.cardGutter(), right: this.cardGutter(), top: 4 })
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    });
  }

  @Builder
  contactContextMenu() {
    Menu() {
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([Color.Red]),
        content: $r('app.string.ct_delete')
      })
        .onClick((): void => { this.confirmDeleteContact(); });
    }
  }

  @Builder
  skeletonRow(index: number) {
    Row({ space: 12 }) {
      Circle({ width: 46, height: 46 })
        .fill($r('app.color.surface_alt'));
      Column({ space: 8 }) {
        Rect({ width: index % 2 === 0 ? 142 : 108, height: 12, radius: 6 })
          .fill($r('app.color.surface_alt'));
        Rect({ width: index % 3 === 0 ? 196 : 158, height: 9, radius: 4.5 })
          .fill($r('app.color.surface_alt'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('100%')
    .height(60)
    .padding({ left: LIST_CARD_INSET_VP, right: LIST_CARD_TRAIL_VP });
  }

  @Builder
  loadingCard() {
    Column() {
      Row({ space: 6 }) {
        Circle({ width: 13, height: 13 }).fill($r('app.color.surface_alt'));
        Rect({ width: 118, height: 10, radius: 5 }).fill($r('app.color.surface_alt'));
      }
      .width('100%')
      .height(36)
      .padding({ left: LIST_CARD_INSET_VP, right: LIST_CARD_TRAIL_VP });
      Divider().color(COLOR_DIVIDER).strokeWidth(0.7).margin({ left: LIST_CARD_INSET_VP, right: LIST_CARD_TRAIL_VP });
      ForEach(SKELETON_ROWS, (index: number): void => {
        if (index > 0) {
          Divider().color(COLOR_DIVIDER).strokeWidth(0.7)
            .margin({ left: cardDividerStartVp(46, 12), right: LIST_CARD_TRAIL_VP });
        }
        this.skeletonRow(index);
      }, (index: number): string => `${index}`);
    }
    .width(`calc(100% - ${this.cardGutter() * 2}vp)`)
    .margin({ left: this.cardGutter(), right: this.cardGutter(), top: 12 })
    .padding({ bottom: 4 })
    .backgroundColor(this.cardFill())
    .backgroundBlurStyle(this.cardBlurStyle())
    .borderRadius(CARD_RADIUS)
    .opacity(this.skeletonBright ? 0.56 : 0.92)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 640),
      curve: Curve.EaseInOut
    })
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  @Builder
  emptyContactsCard() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill($r('app.color.surface_alt'));
        SymbolGlyph($r('sys.symbol.person_2'))
          .fontSize(28)
          .fontColor([COLOR_ICON_SECONDARY]);
      }
      Text($r('app.string.ct_empty'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ct_empty_sub'))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center);
    }
    .width(`calc(100% - ${this.cardGutter() * 2}vp)`)
    .height(190)
    .margin({ left: this.cardGutter(), right: this.cardGutter(), top: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.cardFill())
    .backgroundBlurStyle(this.cardBlurStyle())
    .borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  errorContactsCard() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28)
          .fontColor(['#E64646']);
      }
      Text(this.loadError !== '' ? this.loadError : $r('app.string.contacts_load_failed'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ct_service_unavailable'))
        .fontSize(13)
        .fontColor(COLOR_TEXT_SECONDARY);
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(15)
          .fontColor([this.accent()]);
        Text($r('app.string.settings_reload'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accent());
      }
      .height(38)
      .padding({ left: 16, right: 16 })
      .margin({ top: 4 })
      .borderRadius(19)
      .stateStyles({
        normal: this.retryNormalStyle,
        pressed: this.retryPressedStyle
      })
      .accessibilityText($r('app.string.ct_reload_contacts'))
      .onClick((): void => { this.retryContacts(); });
    }
    .width(`calc(100% - ${this.cardGutter() * 2}vp)`)
    .height(220)
    .margin({ left: this.cardGutter(), right: this.cardGutter(), top: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.cardFill())
    .backgroundBlurStyle(this.cardBlurStyle())
    .borderRadius(CARD_RADIUS)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  searchEmptyState() {
    Column({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(26)
        .fontColor([COLOR_ICON_SECONDARY]);
      Text($r('app.string.ct_no_results'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY);
      Text($r('app.string.ct_no_results_sub'))
        .fontSize(12)
        .fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .height(116)
    .justifyContent(FlexAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
        curve: Curve.EaseOut
      }));
  }

  // 联系人卡片的标题行（排序说明 + 结果数），ListItemGroup 的 header。
  @Builder
  listCardHeader() {
    Column() {
      // 说明行是静态文案（不可点），所以整行走次要色：强调色留给「在线」、FAB 那些
      // 真能点的东西。原来这一行是蓝色 13sp，和下面的字母分组撞成同一个层级，
      // 卡片里三项蓝色抢眼（2026-10-29）。
      //
      // 底下那条分隔线也拆了：它从卡片内缩起、行分隔线却从名字列起，同一张卡里两套
      // 缩进；而且紧接着就是分组字母，多一条线只会把头和身切得更碎。头与身靠留白分。
      Row({ space: 6 }) {
        SymbolGlyph(this.query.trim() === ''
          ? $r('sys.symbol.clock')
          : $r('sys.symbol.magnifyingglass'))
          .fontSize(12)
          .fontColor([COLOR_TEXT_SECONDARY]);
        Text(this.query.trim() === '' ? $r('app.string.ct_sort_by_last_seen') : $r('app.string.ct_contacts_and_global'))
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1);
        Text(this.remoteLoading
          ? $r('app.string.searching')
          : plural('ct_result_count', this.filtered().length, this.filtered().length))
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY);
      }
      .width('100%')
      .height(34)
      // 与联系人卡片里的文字列对齐：卡片外边距 + 卡片内缩（左），行尾内距（右）。
      .padding({ left: this.cardGutter() + HOME_CARD_INSET_VP, right: this.cardGutter() + ROW_PAD_H })
      .alignItems(VerticalAlign.Center);
    }
    .width('100%');
  }

  // 联系人列表：一行一张卡片，与首页会话列表同款（2026-10-29 用户要求）。
  //
  // 原来是 Scroll 里的 Column + ForEach：几千个联系人一次性全建、全排版，每次上下线
  // 更新都整表比对（2026-09-14 用户：「翻联系人列表也很卡，点资料直接去卡死了」）。
  // 现在只建可视区和 cachedCount 那几行，其余滚动时逐帧补建，滚出去的行进复用池。
  //
  // 卡片几何全部照抄首页（pages/chatlist/ChatRow）：外边距 homeCardMarginVp、上下
  // 间距 3+3、圆角 16、行内边距左 8 / 右 14 / 上下 8（在 ContactRowView 里）。
  // 底色与玻璃铺在**每行一个的卡片容器**上，行本身透明（见 ContactRowView.rowFill）：
  // 行再各铺一块就是两层模糊叠加，又重又灰。
  // 点击、按压、长按菜单挂在 ListItem 上（理由见 ContactRowView）。
  @Builder
  listCard() {
    // 标题行（排序说明 + 结果数）。它自己也占一行 ListItem，缩进对齐卡片内的文字列。
    ListItem() {
      this.listCardHeader();
    }
    .width('100%')
    .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
    LazyForEach(this.contactsData, (c: ContactItem) => {
      ListItem() {
        Column() {
          // 字母分组：卡片**外面**的一行路标，缩进 = 卡片外边距 + 卡片内缩，
          // 与卡片里的头像同一条线。11sp 次要色——分组是「路标」不是内容。
          if (this.query.trim() === '' && this.alphabet.heading(c.id) !== '') {
            Text(this.alphabet.heading(c.id)).fontSize(11).fontWeight(FontWeight.Medium)
              .fontColor(COLOR_TEXT_SECONDARY).width('100%').height(26)
              .padding({ left: this.cardGutter() + HOME_CARD_INSET_VP, top: 4 })
              .textAlign(TextAlign.Start);
          }
          // 删除时这一张卡片整体消散：与会话列表同一套（DissolveDeleteEffect +
          // 页面上的 RowLeaveChannel）。包的是卡片这一层，不是外面的 Column——
          // 字母分组标题是路标，不该跟着一起碎。
          DissolveDeleteEffect({
            instanceKey: 'contacts',
            rowId: c.id,
            leaving: this.deleteLeavingId === c.id ? this.deleteLeavingStrength : 0,
            channel: this.contactRemoval.channel
          }) {
            Column() {
              ContactRowView({
                contact: c,
                pressed: this.pressedContactId === c.id,
                busy: this.openingContactId === c.id || this.deletingContactId === c.id
              });
            }
            .width(`calc(100% - ${this.cardGutter() * 2}vp)`)
            .margin({
              left: this.cardGutter(), right: this.cardGutter(),
              top: CONTACT_CARD_GAP_VP, bottom: CONTACT_CARD_GAP_VP
            })
            .borderRadius(CONTACT_CARD_RADIUS)
            // 描边跟着玻璃走：玻璃档用 GLASS_OUTLINE_COLOR（30% 白）——用 divider
            // 会在壁纸上围一圈发暗的框，圆角处四条边叠起来最明显（首页同类问题的结论）。
            // 非玻璃档一律不描边（理由见 ChatRow）：`appWallpaperOn` 对纯色背景也
            // 成立，白色背景下这条灰线会变成整页唯一看得见的卡片轮廓。
            .border({
              width: this.glassOn() ? 0.5 : 0,
              color: GLASS_OUTLINE_COLOR
            })
            .backgroundColor(this.cardFill())
            .backgroundBlurStyle(this.cardBlurStyle())
            .clip(true);
          }
        }
        .width('100%');
      }
      .width('100%')
      .constraintSize({ maxWidth: readableContentWidth(this.screenW) })
      .accessibilityText(`${c.name}，${c.statusText}`)
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.setPressedContact(c.id);
          this.beginContactPress(c);
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          if (this.pressedContactId === c.id) {
            this.setPressedContact(0);
          }
          this.endContactPress();
        }
      })
      .onClick((): void => {
        this.setPressedContact(0);
        if (this.contactPressConsumedByMenu || this.contextMenuShown) {
          this.contactPressConsumedByMenu = false;
          return;
        }
        this.openContact(c);
      })
      .parallelGesture(
        LongPressGesture({ fingers: 1, repeat: false, duration: CONTACT_LONG_PRESS_MS })
          .onAction((): void => { this.openContactMenuIfCurrent(c); })
          .onActionCancel((): void => { this.endContactPress(); })
      )
      .bindContextMenu(
        this.contextMenuShown && this.menuContactId === c.id,
        this.contactContextMenu,
        {
          preview: MenuPreviewMode.IMAGE,
          previewBorderRadius: CONTACT_CARD_RADIUS - 2,
          previewAnimationOptions: {
            scale: [0.98, 1.035],
            transition: TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
                curve: Curve.FastOutSlowIn
              })
          },
          borderRadius: 16,
          backgroundColor: Color.Transparent,
          backgroundBlurStyle: containerBlur('menu'),
          systemMaterial: overlayMaterial('menu'),
          transition: TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.FastOutSlowIn
            }),
          mask: {
            color: '#52000000',
            backgroundBlurStyle: BlurStyle.BACKGROUND_THIN
          },
          modalMode: ModalMode.TARGET_WINDOW,
          hapticFeedbackMode: HapticFeedbackMode.AUTO,
          onDisappear: (): void => { this.onContactMenuDisappear(); }
        }
      );
    }, (c: ContactItem, index: number): string =>
      guardKey(this.contactsData.keyTableId, index, this.contactListVersion(c)));
    // 全局搜索中 / 搜不到：也各占一行卡片，与联系人卡片同宽同圆角。
    if (this.remoteLoading) {
      ListItem() {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color(this.accent());
          Text($r('app.string.ct_searching_global')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
        .width(`calc(100% - ${this.cardGutter() * 2}vp)`)
        .height(48)
        .margin({
          left: this.cardGutter(), right: this.cardGutter(),
          top: CONTACT_CARD_GAP_VP, bottom: CONTACT_CARD_GAP_VP
        })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.cardFill())
        .backgroundBlurStyle(this.cardBlurStyle())
        .borderRadius(CONTACT_CARD_RADIUS);
      }
      .width('100%')
      .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
    } else if (this.query.trim() !== '' && this.filtered().length === 0) {
      ListItem() {
        Column() {
          this.searchEmptyState();
        }
        .width(`calc(100% - ${this.cardGutter() * 2}vp)`)
        .margin({
          left: this.cardGutter(), right: this.cardGutter(),
          top: CONTACT_CARD_GAP_VP, bottom: CONTACT_CARD_GAP_VP
        })
        .backgroundColor(this.cardFill())
        .backgroundBlurStyle(this.cardBlurStyle())
        .borderRadius(CONTACT_CARD_RADIUS)
        .clip(true);
      }
      .width('100%')
      .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
    }
  }

  @Builder
  addContactSheet() {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 2 }) {
          Text($r('app.string.ct_new_contact'))
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.ct_new_contact_sub'))
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY);
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([COLOR_ICON_SECONDARY]);
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.topActionNormalStyle,
          pressed: this.topActionPressedStyle
        })
        .enabled(!this.addContactSaving)
        .accessibilityText($r('app.string.ct_close_new_contact'))
        .onClick((): void => { this.addContactSheetOpen = false; });
      }
      .width('100%')
      .height(54)
      .alignItems(VerticalAlign.Center);

      Column({ space: 6 }) {
        Text($r('app.string.ct_name'))
          .width('100%')
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 4 });
        TextInput({ text: this.addFirstName, placeholder: $r('app.string.ct_first_name') })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .caretColor(this.accent())
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .maxLength(64)
          .enabled(!this.addContactSaving)
          .enterKeyType(EnterKeyType.Next)
          .onChange((value: string): void => {
            this.addFirstName = value;
            this.addContactError = '';
          });
        TextInput({ text: this.addLastName, placeholder: $r('app.string.ct_last_name') })
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .caretColor(this.accent())
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(12)
          .padding({ left: 14, right: 14 })
          .maxLength(64)
          .enabled(!this.addContactSaving)
          .enterKeyType(EnterKeyType.Next)
          .onChange((value: string): void => {
            this.addLastName = value;
            this.addContactError = '';
          });
      }
      .width('100%')
      .margin({ top: 12 });

      Column({ space: 6 }) {
        Text($r('app.string.ct_phone'))
          .width('100%')
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .padding({ left: 4 });
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.phone_fill'))
            .fontSize(17)
            .fontColor([this.accent()]);
          TextInput({ text: this.addPhone, placeholder: '+86 138 0000 0000' })
            .layoutWeight(1)
            .height(46)
            .fontSize(16)
            .fontColor(COLOR_TEXT_PRIMARY)
            .placeholderColor(COLOR_TEXT_SECONDARY)
            .caretColor(this.accent())
            .backgroundColor(Color.Transparent)
            .padding(0)
            .type(InputType.PhoneNumber)
            .maxLength(24)
            .enabled(!this.addContactSaving)
            .enterKeyType(EnterKeyType.Done)
            .onSubmit((): void => { this.submitNewContact(); })
            .onChange((value: string): void => {
              this.addPhone = value;
              this.addContactError = '';
            });
        }
        .width('100%')
        .height(48)
        .padding({ left: 14, right: 12 })
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(12)
        .border({
          width: this.addContactError !== '' ? 1 : 0,
          color: this.addContactError !== '' ? '#E64646' : Color.Transparent
        });
      }
      .width('100%')
      .margin({ top: 12 });

      if (this.addContactError !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(13)
            .fontColor(['#E64646']);
          Text(this.addContactError)
            .fontSize(12)
            .fontColor('#E64646')
            .layoutWeight(1);
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 8 })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ y: -4 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 150),
            curve: Curve.EaseOut
          }));
      }

      Button() {
        Row({ space: 8 }) {
          if (this.addContactSaving) {
            LoadingProgress().width(18).height(18).color(Color.White);
          } else {
            SymbolGlyph($r('sys.symbol.person_badge_plus'))
              .fontSize(18)
              .fontColor([Color.White]);
          }
          Text(this.addContactSaving ? $r('app.string.adding') : $r('app.string.ct_add_contact'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White);
        }
      }
      .width('100%')
      .height(50)
      .margin({ top: 18 })
      .backgroundColor(this.accent())
      .borderRadius(14)
      .enabled(!this.addContactSaving)
      .onClick((): void => { this.submitNewContact(); });
    }
    .width('100%')
    .padding({
      left: 20,
      right: 20,
      top: 6,
      bottom: Math.max(18, this.bottomSafe + 10)
    })
    .backgroundColor(this.cardFill())
    .backgroundBlurStyle(this.cardBlurStyle());
  }

  // 标题栏内容：大标题 + 右上角两个图标——[新建联系人][最近通话]。
  //
  // 2026-10-29 用户定：原来右上角是 ⋮ 菜单（新建群组 / 最近通话），新建联系人靠
  // 右下角 FAB；现在 FAB 和「最近通话」入口卡片都去掉了，两个入口并排挪到顶上。
  // 新建群组随之不再从这里进（用户要求删掉，别再往这个菜单里加别的项）。
  private titleBarContent(): TitleBarContentOptions {
    const addIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.person_badge_plus'),
      label: $r('app.string.ct_new_contact'),
      action: (): void => { this.openAddContactSheet(); }
    };
    const recentsIcon: HdsNavigationIconOptions = {
      // 听筒 + 去电箭头：系统符号里没有「听筒 + 一来一去两箭头」的合成图标，
      // 这一枚是与「最近通话」最贴的（同族还有 phone_arrow_down_left_fill）。
      icon: $r('sys.symbol.phone_arrow_up_right_fill'),
      label: $r('app.string.ct_recent_calls'),
      action: (): void => { this.openRecentCalls(); }
    };
    return {
      title: {
        mainTitle: $r('app.string.tab_contacts'),
        // 加载中才有副标题。原来那一版是两行文字各自做位移动画来"挤"出副标题，
        // HDS 的标题栏自己管这个位置，交给它即可。
        subTitle: this.loading ? $r('app.string.refreshing') : ''
      },
      menu: { value: [{ content: addIcon }, { content: recentsIcon }] }
    };
  }

  // 联系人卡片离内容区边缘的横向留白。从 2026-10-29 起跟首页会话卡片走
  // （homeCardMarginVp，手机 6），不再是 pageMarginVp 的 12——用户要求
  // 「下方列表和首页样式一样」，两页的卡片外沿现在逐像素重合。
  private cardGutter(): number {
    return homeCardMarginVp(this.widthBp);
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      HdsNavigation(this.contactsStack) {
        // 这一层 Stack 是本次修复加的：FAB 必须住在 **navBar 内容**里，才会被
        // 左栏框住。原来它挂在最外层 Stack 上（HdsNavigation 的兄弟节点），那
        // 在单栏时无所谓——整屏就是一栏——分栏之后它罩着整个 HdsNavigation、
        // 连右栏一起罩，FAB 于是飘进右栏压着资料页。
        //
        // clip 默认就是 false（Stack 不裁子节点，只有 Scroll/List/Grid 这类默认
        // 裁），但这里**显式写出来**：本页的渐变模糊靠的是内容穿透到标题栏底下
        // 再被合成，整条链上任何一层开始裁剪，模糊就没了内容可透。链上新插一层
        // 就得跟着表态一次，别让下一个人去猜默认值。
        Stack({ alignContent: Alignment.BottomEnd }) {
          // 整页是一个 List（原来是 Scroll > Column > 各卡片）：搜索框占一个
          // ListItem，联系人是 LazyForEach 逐行的独立卡片（见 listCard）。
          // 限宽改由每一项自己的 constraintSize + alignListItem 居中；List 本身仍铺满窗口，
          // 两侧留白还在它的命中区里，按在留白上照样拖得动。
          List({ scroller: this.contactsScroller }) {
            ListItem() {
              this.searchBox();
            }
            .width('100%')
            .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
            if (this.query.trim() === '' && this.loading && this.contacts.length === 0) {
              ListItem() {
                this.loadingCard();
              }
              .width('100%')
              .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
            } else if (this.query.trim() === '' && this.loadError !== '' && this.contacts.length === 0) {
              ListItem() {
                this.errorContactsCard();
              }
              .width('100%')
              .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
            } else if (this.query.trim() === '' && !this.loading && this.contacts.length === 0) {
              ListItem() {
                this.emptyContactsCard();
              }
              .width('100%')
              .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
            } else {
              this.listCard();
            }
          }
          .width('100%')
          // **高度必须显式铺满。** 这个滚动容器住在一个 alignContent: BottomEnd 的 Stack 里
          // （FAB 那次修复加的一层），不给高度就按内容量高——于是内容少的时候整个滚动区被
          // Stack 按到底部，观感是"联系人列表整体沉在屏幕下半截"（issue #118）。
          .height('100%')
          .alignListItem(ListItemAlign.Center)
          // 第二个参数 true：滚出视口的备用行也画出来——标题栏的渐变模糊糊的正是穿到它底下
          // 的这部分（同首页会话列表，与下面的 clip(false) 是一对）。
          .cachedCount(CONTACT_LIST_CACHED_COUNT, true)
          .contentEndOffset(this.bottomSafe + 88)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .scrollBar(BarState.Off)
          .enableScrollInteraction(!this.contextMenuShown)
          // navBar 的实际宽度：分栏时它就是左栏宽，拖分割线会变，MainScreen 的
          // dock 要跟着走。这个 List 是 navBar 内容的根节点、width('100%')，
          // 它的宽度就是 navBar 宽度——HdsNavigation 没有回调宽度的接口，只能这么
          // 量（与 SettingsPage 同一个办法）。
          // 同值不写：onAreaChange 在滚动/键盘/单双栏切换时会连着来几次，而
          // setOrCreate 即便同值也会惊动订阅方。
          .onAreaChange((_old: Area, area: Area): void => {
            const h: number = Number(area.height);
            if (h > 0 && Math.abs(h - this.contactsViewH) > 0.5) {
              this.contactsViewH = h;
            }
            const w: number = area.width as number;
            if (AppStorage.get<number>(CONTACTS_NAV_BAR_WIDTH_KEY) !== w) {
              AppStorage.setOrCreate<number>(CONTACTS_NAV_BAR_WIDTH_KEY, w);
              // 三个页签共用一个记忆值，哪个页签拖的都算（issue #106）。
              rememberSplitNavWidth(w, isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait));
            }
          })
          // 不裁剪，内容才能穿透到标题栏下方——渐变模糊模糊的正是穿过去的这部分。
          .contentStartOffset(EDGE_OVERLAY_VP)
          // 顶部/底部边缘渐变虚化（与首页会话列表同一套参数）。
          .linearGradientBlur(BLUR_MAX_VP, {
            fractionStops: edgeBlurStops(this.contactsViewH),
            direction: GradientDirection.Bottom
          })
          .clip(false);
        }
        .width('100%').height('100%')
        .clip(false);
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
        // 内容区不再避让标题栏：List 上沿直接贴屏幕顶，linearGradientBlur 的渐变
        // 原点才落在屏幕最上沿。标题自己仍靠 avoidLayoutSafeArea 避让系统安全区。
        enableComponentSafeArea: false,
        // 顶栏去雾：背板全透明 + 关掉 HDS 滚动渐变模糊，理由见 ChatListPage。
        style: titleBarStyle(Color.Transparent, $r('app.color.text_primary'), false, false),
        content: this.titleBarContent()
      })
      .hideBackButton(true)
      //
      // 【这里曾经是 .mode(NavigationMode.Stack)】原注释（保留在下面）说的是：
      // 「强制单栏：HdsNavigation 在宽屏（平板/横屏）会自动进分栏模式，我们只拿
      // 它当标题栏容器、不用 NavDestination——分栏的结果是整页内容挤进左列、
      // 右边一片空白（平板用户报"没法用了"）。」那条止血的前提是"不用
      // NavDestination"，本次改动起联系人页签在平板上会把 ProfilePage 推进右栏
      // （见 openContact），前提不再成立，止血可以拆。聊天/设置两个页签拆的是
      // 同一条。
      // 不显式设 mode：HdsNavigation 默认就是 Auto——窗口 < 600vp 走单栏（手机，
      // 观感与改造前一致，而且手机上本页压根不推目的地），≥600vp 自动分栏
      // （平板，左联系人列表右资料页）。
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
      .navBarWidthRange({ minWidth: this.navBarMinWidth(), maxWidth: this.navBarMaxWidth() })
      // 启动时复原上次拖出来的宽度；没记过就是 min（HDS 的静息值）。
      .navBarWidth(resolveSplitNavWidth(this.savedNavW, this.navBarMinWidth(), this.navBarMaxWidth()))
      // 右栏栈空时的占位。仅分栏模式展示，手机单栏下永不出现。
      .splitPlaceholder(this.placeholderContent())
      .minContentWidth(this.contentMinWidth())
      // navBar 显隐 = 「单栏且栈非空」。dock 要藏在这种时候，见
      // CONTACTS_NAV_BAR_VISIBLE_KEY 的说明。写入前先比一次：同值 setOrCreate 也会
      // 惊动订阅方，而这个回调在单双栏切换时会连着来几次。
      .onNavBarStateChange((reported: boolean): void => {
        // 整页 router 页退掉时会补发 visible=true，按栈兜底。见 navBarReset。
        const isVisible: boolean = navBarVisibleOnChange(reported,
          isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait), this.contactsStack.size());
        if (AppStorage.get<boolean>(CONTACTS_NAV_BAR_VISIBLE_KEY) !== isVisible) {
          AppStorage.setOrCreate<boolean>(CONTACTS_NAV_BAR_VISIBLE_KEY, isVisible);
        }
      })
      .enableDragBar(true)
      // 关掉全模态联动：默认 true 时，bindSheet 一拉起就会触发栈顶
      // HdsNavDestination 的 onHidden。**本页确实有 bindSheet**（build() 末尾那个
      // 「添加联系人」面板，绑在最外层 Stack 上），而右栏此刻很可能正站着
      // ProfilePage——它有 store 订阅和头像放大态，不该因为在左栏拉起一个面板
      // 就以为自己隐藏了。取值与聊天/设置两个页签一致。
      .attributeModifier(SHEET_LIFECYCLE_MODIFIER)
      // MINI 而不是 FREE：四个页签的标题栏现在是同一档窄栏，标题与右上角图标
      // 同一行。FREE 的大标题会先占掉一整行，把标题压到图标下面一截——用户拿
      // 四个页签并排对比过，聊天页（本来就是 MINI）的标题明显更高（issue #111）。
      // 这四处必须一起改：只要有一个还是 FREE，切页签时标题就会跳一下。
      .titleMode(HdsNavigationTitleMode.MINI)
      .bindToScrollable([this.contactsScroller])
      .width('100%').height('100%');
    }
    .width('100%').height('100%')
    .backgroundColor(mainPageFill(this.appWallpaperOn))
    .bindSheet($$this.addContactSheetOpen, this.addContactSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: CARD_BG,
      dragBar: true,
      // 同 BlockedUsersPage：面板自绘的 × 会被系统的那个盖住。
      showClose: false,
      blurStyle: containerBlur('dialog'), systemMaterial: overlayMaterial('dialog')
    });
  }
}
