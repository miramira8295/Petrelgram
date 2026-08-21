import { router, promptAction } from '@kit.ArkUI';
import {
  HdsNavigation, HdsNavigationIconOptions, HdsNavigationMenuItemOptions,
  HdsNavigationTitleMode, TitleBarContentOptions
} from '@kit.UIDesignKit';
import { titleBarStyle } from '../../util/hdsTitleBar';
import {
  addTdAccount, getActiveTdAccountSlot, getTdAccounts, getTdClient,
  logoutCurrentTdAccount, removeDuplicateTdAccountsForActive,
  switchTdAccount, updateActiveTdAccountProfile
} from '../../tdkit/Globals';
import { TD_ACCOUNT_REGISTRY_EPOCH, TdAccountSummary, accountRegistry } from '../../tdkit/AccountRegistry';
import { ProfileStore } from '../../store/ProfileStore';
import { AvatarView } from '../chatlist/AvatarView';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { floatingLiveWindow } from '../chat/LiveFloatingWindow';
import { STORAGE_UPDATE_AVAILABLE } from '../../services/UpdateChecker';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { str } from '../../util/strings';
import { logE } from '../../util/log';
import { MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { readableContentWidth } from '../../util/contentWidth';
import { registerStack, NavStackLike } from '../../util/navStacks';
import { navigateToSetting } from '../../util/settingsNav';
import { splitContentMinWidth, splitNavMaxWidth, splitNavMinWidth } from '../../util/splitMetrics';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const TOP_BAR_HEIGHT: number = 56;
const TOP_ACTION_SIZE: number = 44;
const PROFILE_LOAD_TIMEOUT_MS: number = 8000;

// 设置页签分栏时左栏的实际宽度，vp。与聊天页签的 NAV_BAR_WIDTH_KEY 同一个用途、
// **另一个键**：两个页签各有一个 HdsNavigation、各自 enableDragBar(true)，用户
// 把其中一条分割线拖开之后两边的左栏宽度就不再相等，共用一个键会让 dock 在其中
// 一个页签上与左栏错开。
export const SETTINGS_NAV_BAR_WIDTH_KEY: string = 'settingsNavBarWidth';

// 设置页签的 navBar 此刻是否可见。**等价于「不是（单栏且设置栈非空）」**，
// 与 CHAT_NAV_BAR_VISIBLE_KEY 同构：分栏（平板）下左栏常驻，恒为 true；单栏
// （手机）下推入任何设置子页后 navBar 被系统隐藏，false。
// MainScreen 靠它决定悬浮 dock 藏不藏——子页迁成 NavDestination 之后不再是盖住
// 整个 MainScreen 的整页 router 页，dock 会浮在子页上，必须显式藏。
export const SETTINGS_NAV_BAR_VISIBLE_KEY: string = 'settingsNavBarVisible';

interface SettingItem {
  icon: string;
  bg: string;
  title: string;
  subtitle: string;
  page: string; // route to open ('' = not implemented yet)
  // 路由表（router_map.json）里的 NavDestination 名。有值的条目走设置页签自己的
  // NavPathStack（平板上落在右栏），没值的继续走 router.pushUrl 整页跳转。
  // 十六个子页是一页一页迁的，这个字段就是迁与没迁的分界——迁完之后它会变成
  // 必填、page 随之消失。
  dest?: string;
}

interface SettingGroup {
  title: string;
  items: SettingItem[];
}

// 账号 opens the same editor as 个人资料 → 编辑信息 (name, bio, username,
// birthday) — one page, two entry points, as in the official clients.
// A function, not a const: the labels come from str(), which resolves when it
// is called. A module-level array would be built the first time this module is
// imported — before the string source is installed — and would then keep that
// language forever. They are plain strings rather than $r() because the search
// box below filters on them, and a Resource cannot be compared or lowercased.
function settingGroups(): SettingGroup[] {
  return [
  {
    title: str('settings_group_account'),
    items: [
      { icon: 'sys.symbol.person_fill', bg: '#3478F6', title: str('settings_account'), subtitle: str('settings_account_sub'),
        page: 'pages/main/AccountEditPage',
        dest: 'AccountEditPage' },
      { icon: 'sys.symbol.message_fill', bg: '#FF9500', title: str('settings_chat'),
        subtitle: str('settings_chat_sub'), page: 'pages/main/ChatSettingsPage',
        dest: 'ChatSettingsPage' },
      { icon: 'sys.symbol.hand_thumbsup', bg: '#5856D6', title: str('settings_interaction'),
        subtitle: str('settings_interaction_sub'), page: 'pages/main/InteractionSettingsPage',
        dest: 'InteractionSettingsPage' },
      { icon: 'sys.symbol.paintpalette', bg: '#FF2D55', title: str('settings_accent'),
        subtitle: str('settings_accent_sub'), page: 'pages/main/AccentColorPage',
        dest: 'AccentColorPage' },
      { icon: 'sys.symbol.face_smiling', bg: '#AF52DE', title: str('settings_stickers'),
        subtitle: str('settings_stickers_sub'), page: 'pages/main/StickerSetsPage',
        dest: 'StickerSetsPage' },
      { icon: 'sys.symbol.star', bg: '#FFCC00', title: str('settings_emoji_status'),
        subtitle: str('settings_emoji_status_sub'), page: 'pages/main/EmojiStatusPage',
        dest: 'EmojiStatusPage' },
      { icon: 'sys.symbol.folder_fill', bg: '#34AADC', title: str('settings_folders'),
        subtitle: str('settings_folders_sub'), page: 'pages/main/ChatFoldersPage',
        dest: 'ChatFoldersPage' },
      { icon: 'sys.symbol.bell_fill', bg: '#FF3B30', title: str('settings_notifications'),
        subtitle: str('settings_notifications_sub'), page: 'pages/main/NotificationSettingsPage',
        dest: 'NotificationSettingsPage' },
      { icon: 'sys.symbol.translate', bg: '#5856D6', title: str('language_title'),
        subtitle: str('settings_language_sub'), page: 'pages/main/LanguagePage',
        dest: 'LanguagePage' }
    ]
  },
  {
    title: str('settings_group_privacy'),
    items: [
      { icon: 'sys.symbol.lock_fill', bg: '#34C759', title: str('settings_privacy'),
        subtitle: str('settings_privacy_sub'), page: 'pages/main/PrivacySecurityPage',
        dest: 'PrivacySecurityPage' },
      { icon: 'sys.symbol.computer', bg: '#5AC8FA', title: str('settings_devices'),
        subtitle: str('settings_devices_sub'), page: 'pages/main/ActiveSessionsPage',
        dest: 'ActiveSessionsPage' }
    ]
  },
  {
    title: str('settings_group_storage'),
    items: [
      { icon: 'sys.symbol.data_proportion', bg: '#007AFF', title: str('settings_data'),
        subtitle: str('settings_data_sub'), page: 'pages/main/DataStoragePage',
        dest: 'DataStoragePage' },
      { icon: 'sys.symbol.link', bg: '#5856D6', title: str('settings_proxy'),
        subtitle: str('settings_proxy_sub'), page: 'pages/main/ProxyPage',
        dest: 'ProxyPage' },
      { icon: 'sys.symbol.battery_100percent', bg: '#FF9500', title: str('settings_power'),
        subtitle: str('settings_power_sub'), page: 'pages/main/PowerUsagePage',
        dest: 'PowerUsagePage' },
      { icon: 'sys.symbol.play_fill', bg: '#30B0C7', title: str('settings_media'),
        subtitle: str('settings_media_sub'), page: 'pages/main/MediaSettingsPage',
        dest: 'MediaSettingsPage' }
    ]
  },
  {
    title: str('settings_about'),
    items: [
      { icon: 'sys.symbol.doc_text', bg: '#636366', title: str('diag_title'),
        subtitle: str('diag_sub'), page: 'pages/main/DiagnosticsPage',
        dest: 'DiagnosticsPage' },
      { icon: 'sys.symbol.info_circle', bg: '#8E8E93', title: str('settings_about'),
        subtitle: str('settings_about_sub'), page: 'pages/main/AboutPage',
        dest: 'AboutPage' }
    ]
  }
  ];
}

// The settings tab: user header (avatar with camera badge, name, phone·username)
// followed by the grouped list of setting entries.
@Preview
// 组件冻结：这四个页签由 MainScreen 的 Tabs 保活，同一时刻只有一个在屏上，
// 其余三棵树却照样响应各自 store 的状态更新、照样重跑 build。冻结之后非
// 激活的页签不再刷新，切回来时框架补上延后的那次更新。
@Component({ freezeWhenInactive: true })
export struct SettingsPage {
  // HdsNavigation 靠 bindToScrollable 拿到滚动量，才能驱动标题栏的收缩与
  // 动态模糊；没有这个绑定，标题栏就是一块静态的板子。
  private settingsScroller: Scroller = new Scroller();
  // 设置页签的路由栈。已迁成 HdsNavDestination 的子页推进这里；平板上它就是
  // 右栏，手机上它盖住整个页签（HdsNavigation 默认 Auto，<600vp 单栏）。
  private settingsStack: NavPathStack = new NavPathStack();
  // 标题栏的材质档位来自设置里的「光感等级」，改了要重绘。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp(STORAGE_UPDATE_AVAILABLE) updateAvailable: boolean = false;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 平板上不把一列内容拉满整屏——见 util/contentWidth。窗口宽（不是屏幕宽），
  // 分屏 / 悬浮窗 / 折叠屏改变窗口时 EntryAbility 的 windowSizeChange 会刷新它。
  @StorageProp('screenWidthVp') screenW: number = 360;
  // The setting titles come from str() rather than $r() so the search box can
  // filter on them, which means they do not re-resolve by themselves. Observing
  // the epoch is what rebuilds this list when the language changes.
  @StorageProp(LANGUAGE_EPOCH) languageEpoch: number = 0;
  @StorageLink('tdAccountRegistryEpoch') @Watch('onAccountRegistryEpoch')
  accountRegistryEpoch: number = 0;
  @State myId: number = 0;
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  @State avatarAnimPath: string = '';
  @State statusEmojiPath: string = '';
  @State statusEmojiFormat: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State accounts: TdAccountSummary[] = [];
  @State activeSlotId: string = '';
  @State switchingSlotId: string = '';
  @State profileLoading: boolean = true;
  @State profileError: string = '';
  @State profileSkeletonBright: boolean = false;
  @State accountActionError: string = '';
  @State accountActionRetry: string = '';
  @State accountActionTarget: string = '';
  @State settingsSearchOpen: boolean = false;
  @State settingsQuery: string = '';
  @State accountNavigationLocked: boolean = false;
  // Keyed by route, not by title: the title is display text, and display text
  // is not an identity — it changes with the language.
  @State pressedSettingPage: string = '';
  @State openingSettingPage: string = '';
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;
  private profileLoadSequence: number = 0;
  private profileLoadTimer: number = -1;
  private accountNavigationTimer: number = -1;
  private settingNavigationTimer: number = -1;
  private profileSkeletonTimer: number = -1;

  aboutToAppear(): void {
    // 全局注册表取栈：设置子页的跳转不止本页这一个入口——tg://settings/... 深链
    // 在页面之外触发，拿不到组件上下文（openTelegramLink.openSettingsSection）。
    // 见 util/navStacks.ets 的说明。
    registerStack('settings', this.settingsStack as NavStackLike);
    // 复位一次再挂树：本页刚建好时栈必然是空的，navBar 一定可见。不复位的话，
    // 上一轮（退登/换账号）留在 AppStorage 里的 false 会让 dock 一直藏着——
    // onNavBarStateChange 只在**变化**时触发，不会替我们补一发 true。
    AppStorage.setOrCreate<boolean>(SETTINGS_NAV_BAR_VISIBLE_KEY, true);
    this.reloadAccounts();
    this.loadProfile();
  }

  aboutToDisappear(): void {
    this.profileLoadSequence++;
    this.clearProfileLoadTimer();
    this.closeProfileStore();
    this.releaseAccountNavigation();
    this.releaseSettingNavigation();
    this.pressedSettingPage = '';
    this.settingsSearchOpen = false;
    this.settingsQuery = '';
    this.stopProfileSkeletonPulse();
    this.accountActionError = '';
    this.accountActionRetry = '';
    this.accountActionTarget = '';
  }

  private loadProfile(): void {
    const sequence = ++this.profileLoadSequence;
    this.clearProfileLoadTimer();
    this.closeProfileStore();
    this.profileLoading = true;
    this.profileError = '';
    this.startProfileSkeletonPulse();
    const req: TdRequest = { '@type': 'getMe' };
    getTdClient().send(req, PROFILE_LOAD_TIMEOUT_MS).then((me: TdObject): void => {
      if (sequence !== this.profileLoadSequence) {
        return;
      }
      this.myId = (me['id'] as number | undefined) ?? 0;
      if (this.myId === 0) {
        this.profileLoading = false;
        this.profileError = str('settings_account_unreadable');
        this.stopProfileSkeletonPulse();
        return;
      }
      const store = new ProfileStore(getTdClient(), this.myId);
      this.store = store;
      this.unsub = store.subscribe(() => { this.refresh(); });
      store.open();
      this.profileLoadTimer = setTimeout((): void => {
        this.profileLoadTimer = -1;
        if (sequence === this.profileLoadSequence && this.profileLoading) {
          this.profileLoading = false;
          this.profileError = str('settings_profile_timeout');
          this.stopProfileSkeletonPulse();
        }
      }, PROFILE_LOAD_TIMEOUT_MS);
    }).catch((e: TdError): void => {
      if (sequence !== this.profileLoadSequence) {
        return;
      }
      this.clearProfileLoadTimer();
      this.profileLoading = false;
      this.profileError = str('settings_profile_failed');
      this.stopProfileSkeletonPulse();
      logE(`SettingsPage.getMe failed: ${e.message}`);
    });
  }

  private startProfileSkeletonPulse(): void {
    if (this.profileSkeletonTimer !== -1 ||
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 1) === 0) {
      return;
    }
    this.profileSkeletonTimer = setInterval((): void => {
      this.profileSkeletonBright = !this.profileSkeletonBright;
    }, 680);
  }

  private stopProfileSkeletonPulse(): void {
    if (this.profileSkeletonTimer !== -1) {
      clearInterval(this.profileSkeletonTimer);
      this.profileSkeletonTimer = -1;
    }
    this.profileSkeletonBright = false;
  }

  private closeProfileStore(): void {
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  private clearProfileLoadTimer(): void {
    if (this.profileLoadTimer !== -1) {
      clearTimeout(this.profileLoadTimer);
      this.profileLoadTimer = -1;
    }
  }

  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    this.name = s.name;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.avatarAnimPath = s.avatarAnimPath;
    this.statusEmojiPath = s.statusEmojiPath;
    this.statusEmojiFormat = s.statusEmojiFormat;
    this.phone = s.phone;
    this.usernames = s.usernames;
    if (this.name !== '') {
      this.clearProfileLoadTimer();
      this.profileLoading = false;
      this.profileError = '';
      this.stopProfileSkeletonPulse();
    }
    updateActiveTdAccountProfile(
      this.myId,
      this.name,
      this.phone,
      this.usernames.length > 0 ? this.usernames[0] : '',
      this.avatarPath
    );
  }

  private onAccountRegistryEpoch(): void {
    this.reloadAccounts();
  }

  private reloadAccounts(): void {
    removeDuplicateTdAccountsForActive();
    this.accounts = getTdAccounts();
    this.activeSlotId = getActiveTdAccountSlot();
  }

  private accountInitials(account: TdAccountSummary): string {
    const trimmed = account.name.trim();
    if (trimmed === '') { return '?'; }
    const parts = trimmed.split(' ').filter((part: string): boolean => part !== '');
    if (parts.length >= 2) {
      return `${parts[0].substring(0, 1)}${parts[parts.length - 1].substring(0, 1)}`.toUpperCase();
    }
    return trimmed.substring(0, Math.min(2, trimmed.length)).toUpperCase();
  }

  private accountSubtitle(account: TdAccountSummary): string {
    if (account.pendingLogin) { return str('settings_tap_to_sign_in'); }
    const parts: string[] = [];
    if (account.phone !== '') { parts.push(`+${account.phone}`); }
    if (account.username !== '') { parts.push(`@${account.username}`); }
    return parts.length > 0 ? parts.join('  ·  ') : str('settings_telegram_account');
  }

  private otherAccounts(): TdAccountSummary[] {
    return this.accounts.filter(
      (account: TdAccountSummary): boolean =>
        account.slotId !== this.activeSlotId && !account.pendingLogin
    );
  }

  private filteredSettingGroups(): SettingGroup[] {
    const query = this.settingsQuery.trim().toLowerCase();
    if (query === '') {
      return settingGroups();
    }
    const groups: SettingGroup[] = [];
    for (const group of settingGroups()) {
      const items = group.items.filter((item: SettingItem): boolean =>
        item.title.toLowerCase().includes(query) ||
        item.subtitle.toLowerCase().includes(query) ||
        group.title.toLowerCase().includes(query)
      );
      if (items.length > 0) {
        groups.push({ title: group.title, items });
      }
    }
    return groups;
  }

  private closeSettingsSearch(): void {
    this.settingsSearchOpen = false;
    this.settingsQuery = '';
  }

  private openAccountEditor(): void {
    if (this.profileError !== '') {
      this.loadProfile();
      return;
    }
    if (this.profileLoading || this.switchingSlotId !== '' ||
      this.accountNavigationLocked || this.openingSettingPage !== '') {
      return;
    }
    this.accountNavigationLocked = true;
    this.accountNavigationTimer = setTimeout((): void => {
      this.accountNavigationTimer = -1;
      this.accountNavigationLocked = false;
    }, 600);
    // 头像这条入口和列表里那条「账号」是同一个页面，AccountEditPage 已经迁成
    // NavDestination、从 main_pages.json 摘掉，router.pushUrl 对它必然失败，
    // 所以这里也改走 navigateToSetting——和 pushSettingDestination 同一个漏斗。
    // 搜索态下 HdsNavigation 整个不在树上，推栈没有容器渲染，推之前先关搜索
    //（理由见 pushSettingDestination 里那段注释）。
    if (this.settingsSearchOpen) {
      this.settingsSearchOpen = false;
      this.settingsQuery = '';
    }
    if (navigateToSetting('AccountEditPage')) {
      return;
    }
    logE('SettingsPage.openAccountEditor failed: settings stack missing');
    promptAction.showToast({ message: $r('app.string.settings_open_profile_failed'), duration: 1800 });
    this.releaseAccountNavigation();
  }

  private releaseAccountNavigation(): void {
    if (this.accountNavigationTimer !== -1) {
      clearTimeout(this.accountNavigationTimer);
      this.accountNavigationTimer = -1;
    }
    this.accountNavigationLocked = false;
  }

  // 分栏的三个宽度。算法在 util/splitMetrics.ets（含 40% 上限、拖拽行程、
  // 与 minContentWidth 不打架三条约束的推导），这里只把当前窗口宽喂进去。
  // 与 ChatListPage 用的是同一组函数：两个页签的左栏静息宽度因此一致，dock
  // 在页签之间切换时不会跳一下。
  private navBarMinWidth(): number {
    return splitNavMinWidth(this.screenW);
  }

  private navBarMaxWidth(): number {
    return splitNavMaxWidth(this.screenW);
  }

  private contentMinWidth(): number {
    return splitContentMinWidth(this.screenW);
  }

  private openSetting(item: SettingItem): void {
    if (this.switchingSlotId !== '' || this.openingSettingPage !== '' ||
      this.accountNavigationLocked) {
      return;
    }
    if (item.page === '') {
      promptAction.showToast({ message: str('settings_not_supported', item.title), duration: 1500 });
      return;
    }
    this.openingSettingPage = item.title;
    this.settingNavigationTimer = setTimeout((): void => {
      this.settingNavigationTimer = -1;
      this.openingSettingPage = '';
    }, 800);
    // 800ms 连点锁在两条分支上都照常上：它不只防连点，还是全页十来处 .enabled()
    // 的依据（开着子页的这一瞬间，账号切换、搜索、退登都该是灰的）。分流只换
    // 「怎么推」，不换「推的时候页面处于什么态」。
    const dest: string | undefined = item.dest;
    if (dest !== undefined) {
      this.pushSettingDestination(item, dest);
      return;
    }
    router.pushUrl({ url: item.page }).catch((error: Error): void => {
      logE(`SettingsPage.openSetting(${item.title}) failed: ${error.message}`);
      promptAction.showToast({ message: str('settings_open_failed', item.title), duration: 1800 });
      this.releaseSettingNavigation();
    });
  }

  // 已迁到 NavDestination 的子页走这条：推进设置页签自己的 NavPathStack。规则
  // 在 util/settingsNav.ets——深链（tg://settings/...）走的是同一个函数。
  //
  // 返回 false 只可能是"栈没注册"，而本页 aboutToAppear 里刚注册过、此刻必然
  // 在树上，所以这一支不该发生。仍然接住：它和 router.pushUrl 失败是同一类
  // "页面没打开"，给用户的反馈也该一样，否则 800ms 连点锁会一直锁着。
  private pushSettingDestination(item: SettingItem, dest: string): void {
    // 先关搜索。**必须的一步，不是顺手清理**：build() 有两条分支，搜索态走的是
    // Column + topBar() 那条，HdsNavigation 整个不在树上，栈里推了东西也没有
    // 容器去渲染——从搜索结果里点一条已迁的子页会变成"点了没反应"。
    // 迁移前不会：那时是 router.pushUrl，整页盖在搜索态之上。
    // 代价：从子页返回后搜索态不再保留（迁移前保留）。这是十六个页面迁完之后
    // 才好彻底解决的问题（把搜索框搬进 HDS 标题栏的 stackBuilder，见 build()
    // 里那段注释说明为什么当时没搬）。
    if (this.settingsSearchOpen) {
      this.settingsSearchOpen = false;
      this.settingsQuery = '';
    }
    if (navigateToSetting(dest)) {
      return;
    }
    logE(`SettingsPage.openSetting(${item.title}) failed: settings stack missing`);
    promptAction.showToast({ message: str('settings_open_failed', item.title), duration: 1800 });
    this.releaseSettingNavigation();
  }

  private releaseSettingNavigation(): void {
    if (this.settingNavigationTimer !== -1) {
      clearTimeout(this.settingNavigationTimer);
      this.settingNavigationTimer = -1;
    }
    this.openingSettingPage = '';
  }

  @Styles
  topActionNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  topActionPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.72)
    .scale({ x: 0.92, y: 0.92 })
  }

  @Styles
  accountRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  accountRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.8)
    .scale({ x: 0.985, y: 0.985 })
  }

  @Styles
  retryActionNormalStyle() {
    .backgroundColor('#143478F6')
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  retryActionPressedStyle() {
    .backgroundColor('#243478F6')
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  @Styles
  settingRowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  settingRowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.78)
    .scale({ x: 0.985, y: 0.985 })
  }

  @Styles
  dangerActionNormalStyle() {
    .backgroundColor('#14E64646')
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  dangerActionPressedStyle() {
    .backgroundColor('#24E64646')
    .opacity(0.72)
    .scale({ x: 0.98, y: 0.98 })
  }

  private switchAccount(slotId: string): void {
    if (this.switchingSlotId !== '' || slotId === this.activeSlotId ||
      this.accountNavigationLocked || this.openingSettingPage !== '') { return; }
    this.clearAccountActionError();
    this.switchingSlotId = slotId;
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => switchTdAccount(slotId))
      .catch((caught: Error): void => {
        logE(`SettingsPage.switchAccount failed: ${caught.message}`);
        promptAction.showToast({ message: str('settings_switch_failed'), duration: 1800 });
        this.switchingSlotId = '';
        this.accountActionError = str('settings_switch_failed_network');
        this.accountActionRetry = 'switch';
        this.accountActionTarget = slotId;
      });
  }

  private addAccount(): void {
    if (this.switchingSlotId !== '' || this.accountNavigationLocked ||
      this.openingSettingPage !== '') { return; }
    this.clearAccountActionError();
    this.switchingSlotId = 'new';
    floatingLiveWindow.closeForAccountSwitch()
      .then((): Promise<void> => addTdAccount())
      .catch((caught: Error): void => {
        logE(`SettingsPage.addAccount failed: ${caught.message}`);
        promptAction.showToast({ message: str('settings_add_account_failed'), duration: 1800 });
        this.switchingSlotId = '';
        this.accountActionError = str('settings_start_login_failed');
        this.accountActionRetry = 'add';
        this.accountActionTarget = '';
      });
  }

  private clearAccountActionError(): void {
    this.accountActionError = '';
    this.accountActionRetry = '';
    this.accountActionTarget = '';
  }

  private retryAccountAction(): void {
    if (this.switchingSlotId !== '') {
      return;
    }
    const action = this.accountActionRetry;
    const target = this.accountActionTarget;
    this.clearAccountActionError();
    if (action === 'switch' && target !== '') {
      this.switchAccount(target);
    } else if (action === 'add') {
      this.addAccount();
    }
  }





  private subtitleLine(): string {
    const parts: string[] = [];
    if (this.phone !== '') {
      parts.push(`+${this.phone}`);
    }
    if (this.usernames.length > 0) {
      parts.push(`@${this.usernames[0]}`);
    }
    return parts.join('  ·  ');
  }

  @Builder
  topBar() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.settingsSearchOpen) {
        Row({ space: 8 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(23)
              .fontColor([COLOR_TEXT_PRIMARY]);
          }
          .width(TOP_ACTION_SIZE)
          .height(TOP_ACTION_SIZE)
          .borderRadius(TOP_ACTION_SIZE / 2)
          .justifyContent(FlexAlign.Center)
          .stateStyles({
            normal: this.topActionNormalStyle,
            pressed: this.topActionPressedStyle
          })
          .accessibilityText($r('app.string.settings_search_close'))
          .onClick((): void => { this.closeSettingsSearch(); });

          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(17)
              .fontColor([COLOR_TEXT_SECONDARY]);
            TextInput({ text: this.settingsQuery, placeholder: $r('app.string.settings_search') })
              .layoutWeight(1)
              .height(44)
              .fontSize(16)
              .fontColor(COLOR_TEXT_PRIMARY)
              .placeholderColor(COLOR_TEXT_SECONDARY)
              .caretColor(COLOR_PRIMARY)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .enterKeyType(EnterKeyType.Search)
              .onChange((value: string): void => { this.settingsQuery = value; });
            if (this.settingsQuery !== '') {
              Row() {
                SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                  .fontSize(17)
                  .fontColor([COLOR_TEXT_SECONDARY]);
              }
              .width(32)
              .height(36)
              .justifyContent(FlexAlign.Center)
              .accessibilityText($r('app.string.settings_search_clear'))
              .onClick((): void => { this.settingsQuery = ''; });
            }
          }
          .height(44)
          .layoutWeight(1)
          .padding({ left: 14, right: 8 })
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(14);
        }
        .width('100%')
        .height(TOP_BAR_HEIGHT)
        .padding({ left: 8, right: 12 })
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: 12 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          }));
      } else {
        Row({ space: 4 }) {
          Text($r('app.string.settings_title'))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .layoutWeight(1);
          Row() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(21)
              .fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width(TOP_ACTION_SIZE)
          .height(TOP_ACTION_SIZE)
          .borderRadius(TOP_ACTION_SIZE / 2)
          .justifyContent(FlexAlign.Center)
          .stateStyles({
            normal: this.topActionNormalStyle,
            pressed: this.topActionPressedStyle
          })
          .enabled(this.switchingSlotId === '' &&
            !this.accountNavigationLocked && this.openingSettingPage === '')
          .accessibilityText($r('app.string.settings_search'))
          .onClick((): void => {
            if (this.switchingSlotId === '') {
              this.settingsSearchOpen = true;
              this.settingsQuery = '';
            }
          });
        }
        .width('100%')
        .height(TOP_BAR_HEIGHT)
        .padding({ left: 16, right: 8 })
        .alignItems(VerticalAlign.Center)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.translate({ x: -8 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          }));
      }
    }
    .width('100%')
    .height(TOP_BAR_HEIGHT)
    .backgroundColor(PAGE_BG);
  }

  @Builder
  profileLoadingCard() {
    Row({ space: 14 }) {
      Circle({ width: 72, height: 72 })
        .fill($r('app.color.surface_alt'));
      Column({ space: 9 }) {
        Rect({ width: 132, height: 16, radius: 8 })
          .fill($r('app.color.surface_alt'));
        Rect({ width: 188, height: 10, radius: 5 })
          .fill($r('app.color.surface_alt'));
        Rect({ width: 92, height: 9, radius: 4.5 })
          .fill($r('app.color.surface_alt'));
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      LoadingProgress()
        .width(22)
        .height(22)
        .color(COLOR_PRIMARY);
    }
    .width('calc(100% - 24vp)')
    .height(108)
    .margin({ left: 12, right: 12 })
    .padding({ left: 16, right: 14 })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .opacity(this.profileSkeletonBright ? 0.56 : 0.92)
    .animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 640),
      curve: Curve.EaseInOut
    })
    .accessibilityText($r('app.string.settings_profile_loading'))
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  @Builder
  profileErrorCard() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle({ width: 58, height: 58 }).fill('#18E64646');
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28)
          .fontColor(['#E64646']);
      }
      Column({ space: 3 }) {
        Text($r('app.string.settings_profile_failed'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.profileError)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Row({ space: 5 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(14)
            .fontColor([COLOR_PRIMARY]);
          Text($r('app.string.settings_reload'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY);
        }
        .height(34)
        .padding({ left: 12, right: 12 })
        .margin({ top: 2 })
        .borderRadius(17)
        .stateStyles({
          normal: this.retryActionNormalStyle,
          pressed: this.retryActionPressedStyle
        });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
    }
    .width('calc(100% - 24vp)')
    .height(118)
    .margin({ left: 12, right: 12 })
    .padding({ left: 16, right: 14 })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.accountRowNormalStyle,
      pressed: this.accountRowPressedStyle
    })
    .enabled(this.switchingSlotId === '' &&
      !this.accountNavigationLocked && this.openingSettingPage === '')
    .accessibilityText($r('app.string.settings_profile_failed_reload'))
    .onClick((): void => { this.loadProfile(); })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  activeAccountRow() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        AvatarView({
          avatarPath: this.avatarPath, initials: this.initials,
          colorSeed: this.myId, avatarSize: 72,
          animPath: this.avatarAnimPath
        });
        Row() {
          SymbolGlyph($r('sys.symbol.pencil_line'))
            .fontSize(13)
            .fontColor([Color.White]);
        }
        .width(26).height(26).borderRadius(13)
        .backgroundColor(COLOR_PRIMARY)
        .border({ width: 2.5, color: CARD_BG })
        .justifyContent(FlexAlign.Center);
      }

      Column({ space: 4 }) {
        Row({ space: 5 }) {
          Text(this.name !== '' ? this.name : (this.profileLoading ? $r('app.string.settings_account_loading') : $r('app.string.settings_current_account')))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLOR_TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1);
          if (!this.profileLoading && this.statusEmojiPath !== '') {
            if (this.statusEmojiFormat === 'tgs') {
              TgsStickerView({
                tgsPath: this.statusEmojiPath, boxWidth: 22, boxHeight: 22, powerCategory: 'emojiStatus'
              });
            } else if (this.statusEmojiFormat === 'webm') {
              WebmStickerView({
                webmPath: this.statusEmojiPath, boxWidth: 22, boxHeight: 22, powerCategory: 'emojiStatus'
              });
            } else {
              Image(`file://${this.statusEmojiPath}`).draggable(false).width(22).height(22).objectFit(ImageFit.Contain);
            }
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);
        Text(this.profileError !== ''
          ? this.profileError
          : (this.subtitleLine() !== '' ? this.subtitleLine() : str('settings_telegram_account')))
          .fontSize(13)
          .fontColor(this.profileError !== '' ? '#E64646' : COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.profileError !== '' ? $r('app.string.settings_tap_reload') : $r('app.string.settings_edit_profile'))
          .fontSize(12)
          .fontColor(COLOR_PRIMARY);
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);

      if (this.profileLoading) {
        LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph(this.profileError !== ''
          ? $r('sys.symbol.arrow_clockwise')
          : $r('sys.symbol.chevron_right'))
          .fontSize(17)
          .fontColor([this.profileError !== '' ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY]);
      }
    }
    .width('calc(100% - 24vp)')
    .height(108)
    .margin({ left: 12, right: 12 })
    .padding({ left: 16, right: 14 })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.accountRowNormalStyle,
      pressed: this.accountRowPressedStyle
    })
    .enabled(this.switchingSlotId === '' &&
      !this.accountNavigationLocked && this.openingSettingPage === '')
    .accessibilityText(this.profileError !== ''
      ? str('settings_profile_failed_tap')
      : str('a11y_edit_profile', this.name !== '' ? this.name : str('settings_current_account')))
    .onClick((): void => { this.openAccountEditor(); });
  }

  @Builder
  accountRow(account: TdAccountSummary) {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: account.avatarPath,
        initials: this.accountInitials(account),
        colorSeed: account.userId !== 0 ? account.userId : account.slotId.length,
        avatarSize: 40
      });
      Column({ space: 2 }) {
        Text(account.name !== '' ? account.name : str('settings_telegram_account'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.accountSubtitle(account))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      if (this.switchingSlotId === account.slotId) {
        LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.accountRowNormalStyle,
      pressed: this.accountRowPressedStyle
    })
    .enabled(this.switchingSlotId === '' &&
      !this.accountNavigationLocked && this.openingSettingPage === '')
    .accessibilityText(str('a11y_switch_account', account.name !== '' ? account.name : str('settings_telegram_account')))
    .onClick((): void => this.switchAccount(account.slotId))
    // 长按移除。列表里之所以会出现同一个账号的两条，是因为自动去重现在只清
    // 空壳、不动有数据的槽位（删条目留几百 MB 的库，等于账号进不去又占空间）。
    // 哪一份该留不是代码能判断的，所以交给用户在这里选。
    .gesture(LongPressGesture().onAction((): void => { this.confirmRemoveAccount(account); }));
  }

  // 移除一个账号：条目和它在本机的数据一起删。删数据是必须的——只删条目的话
  // 下次启动的自愈扫描会按磁盘把它捡回来。
  private confirmRemoveAccount(account: TdAccountSummary): void {
    const name: string = account.name !== '' ? account.name : str('settings_telegram_account');
    promptAction.showDialog({
      title: str('ar_remove_account'),
      message: `${name}\n\n${str('ar_remove_account_sub')}`,
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.delete'), color: '#E64646' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      if (accountRegistry.removeAccountAndData(account.slotId)) {
        this.accountRegistryEpoch = AppStorage.get<number>(TD_ACCOUNT_REGISTRY_EPOCH) ?? 0;
      }
    }).catch((caught: Error): void => {
      logE(`SettingsPage.confirmRemoveAccount failed: ${caught.message}`);
    });
  }

  @Builder
  accountActionErrorBanner() {
    Row({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(21)
        .fontColor(['#E64646']);
      Column({ space: 2 }) {
        Text($r('app.string.settings_account_action_incomplete'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY);
        Text(this.accountActionError)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(13)
          .fontColor([COLOR_PRIMARY]);
        Text($r('app.string.settings_retry'))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_PRIMARY);
      }
      .height(34)
      .padding({ left: 10, right: 10 })
      .borderRadius(17)
      .stateStyles({
        normal: this.retryActionNormalStyle,
        pressed: this.retryActionPressedStyle
      })
      .enabled(this.switchingSlotId === '')
      .accessibilityText($r('app.string.settings_retry_account_action'))
      .onClick((): void => { this.retryAccountAction(); });
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .stateStyles({
        normal: this.topActionNormalStyle,
        pressed: this.topActionPressedStyle
      })
      .accessibilityText($r('app.string.settings_dismiss_error'))
      .onClick((): void => { this.clearAccountActionError(); });
    }
    .width('calc(100% - 24vp)')
    .height(66)
    .margin({ left: 12, right: 12 })
    .padding({ left: 12, right: 8 })
    .backgroundColor('#10E64646')
    .border({ width: 0.7, color: '#30E64646' })
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  accountsCard() {
    Column({ space: 10 }) {
      if (this.profileLoading) {
        this.profileLoadingCard();
      } else if (this.profileError !== '') {
        this.profileErrorCard();
      } else {
        this.activeAccountRow();
      }

      Column() {
        if (this.otherAccounts().length > 0) {
          Text($r('app.string.settings_switch_account'))
            .width('100%')
            .height(34)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_PRIMARY)
            .padding({ left: 14, right: 14, top: 10 });
          ForEach(this.otherAccounts(), (account: TdAccountSummary, index: number): void => {
            if (index > 0) {
              Divider()
                .color(COLOR_DIVIDER)
                .strokeWidth(0.7)
                .margin({ left: 66, right: 14 });
            }
            this.accountRow(account);
          }, (account: TdAccountSummary): string =>
            `${account.slotId}_${account.userId}_${account.name}_${account.phone}_${account.username}_${account.avatarPath}`);
          Divider()
            .color(COLOR_DIVIDER)
            .strokeWidth(0.7)
            .margin({ left: 14, right: 14 });
        }

        Row({ space: 12 }) {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.plus')).fontSize(19).fontColor([Color.White]);
          }
          .width(40).height(40).borderRadius(20).backgroundColor(COLOR_PRIMARY);
          Column({ space: 2 }) {
            Text($r('app.string.settings_add_account')).fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
            Text($r('app.string.settings_add_account_sub')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
          if (this.switchingSlotId === 'new') {
            LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
          } else {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 12 })
        .alignItems(VerticalAlign.Center)
        .stateStyles({
          normal: this.accountRowNormalStyle,
          pressed: this.accountRowPressedStyle
        })
        .enabled(this.switchingSlotId === '' &&
          !this.accountNavigationLocked && this.openingSettingPage === '')
        .accessibilityText($r('app.string.settings_add_account'))
        .onClick((): void => this.addAccount());
      }
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12 })
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .clip(true);

      if (this.accountActionError !== '') {
        this.accountActionErrorBanner();
      }
    }
    .width('100%')
    .margin({ top: 8, bottom: 12 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
        curve: Curve.EaseOut
      }));
  }


  @Builder
  settingRow(item: SettingItem) {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r(item.icon))
          .fontSize(18)
          .fontColor([Color.White])
          .scale({
            x: this.pressedSettingPage === item.page ? 0.88 : 1,
            y: this.pressedSettingPage === item.page ? 0.88 : 1
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          });
      }
      .width(34).height(34).borderRadius(9).backgroundColor(item.bg);
      Column({ space: 3 }) {
        Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(item.subtitle)
          .fontSize(12)
          .fontColor(COLOR_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      // 有新版本时在「关于」这一行打红点，作为唯一的更新引导 —— 不弹窗、
      // 不打断，用户什么时候想看什么时候点。
      if (item.page === 'pages/main/AboutPage' && this.updateAvailable) {
        Circle({ width: 8, height: 8 }).fill('#FF3B30').margin({ right: 6 });
      }
      if (this.openingSettingPage === item.title) {
        LoadingProgress().width(19).height(19).color(COLOR_PRIMARY);
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([COLOR_TEXT_SECONDARY])
          .translate({ x: this.pressedSettingPage === item.page ? 2 : 0 })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          });
      }
    }
    .width('100%')
    .height(64)
    .padding({ left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.settingRowNormalStyle,
      pressed: this.settingRowPressedStyle
    })
    .enabled(this.switchingSlotId === '' && this.openingSettingPage === '' &&
      !this.accountNavigationLocked)
    .accessibilityText(`${item.title}，${item.subtitle}`)
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down && this.openingSettingPage === '') {
        this.pressedSettingPage = item.page;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        if (this.pressedSettingPage === item.page) {
          this.pressedSettingPage = '';
        }
      }
    })
    .onClick((): void => {
      this.pressedSettingPage = '';
      this.openSetting(item);
    });
  }

  @Builder
  settingGroupCard(group: SettingGroup) {
    Column() {
      Text(group.title)
        .width('100%')
        .height(32)
        .padding({ left: 4, top: 8 })
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_SECONDARY);
      Column() {
        ForEach(group.items, (item: SettingItem, index: number): void => {
          if (index > 0) {
            Divider()
              .color(COLOR_DIVIDER)
              .strokeWidth(0.7)
              .margin({ left: 62, right: 14 });
          }
          this.settingRow(item);
        }, (item: SettingItem): string => `${group.title}_${item.title}`);
      }
      .width('100%')
      .backgroundColor(CARD_BG)
      .borderRadius(CARD_RADIUS)
      .clip(true);
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12, bottom: 6 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 6 }))
      .animation({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }));
  }

  @Builder
  settingsCard() {
    Column() {
      if (this.filteredSettingGroups().length === 0) {
        Column({ space: 8 }) {
          Stack({ alignContent: Alignment.Center }) {
            Circle({ width: 52, height: 52 }).fill($r('app.color.surface_alt'));
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(25)
              .fontColor([COLOR_TEXT_SECONDARY]);
          }
          Text(str('settings_no_match', this.settingsQuery.trim()))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLOR_TEXT_PRIMARY);
          Text($r('app.string.settings_search_hint'))
            .fontSize(12)
            .fontColor(COLOR_TEXT_SECONDARY);
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.xmark_circle'))
              .fontSize(14)
              .fontColor([COLOR_PRIMARY]);
            Text($r('app.string.settings_clear_query'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLOR_PRIMARY);
          }
          .height(34)
          .padding({ left: 13, right: 13 })
          .margin({ top: 3 })
          .borderRadius(17)
          .stateStyles({
            normal: this.retryActionNormalStyle,
            pressed: this.retryActionPressedStyle
          })
          .accessibilityText($r('app.string.settings_clear_query_a11y'))
          .onClick((): void => { this.settingsQuery = ''; });
        }
        .width('calc(100% - 24vp)')
        .height(194)
        .margin({ left: 12, right: 12, top: 12 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(CARD_BG)
        .borderRadius(CARD_RADIUS)
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
            curve: Curve.EaseOut
          }));
      } else {
        ForEach(this.filteredSettingGroups(), (group: SettingGroup): void => {
          this.settingGroupCard(group);
        }, (group: SettingGroup): string =>
          `${group.title}_${this.settingsQuery.trim().toLowerCase()}`);
      }
    }
    .width('100%');
  }

  // 标题栏内容：大标题 + 右上角搜索入口。搜索**打开后**不走这里，见 build()。
  private titleBarContent(): TitleBarContentOptions {
    // 菜单项是 { content, badge } 两层，图标和动作都在 content 里
    // （HdsNavigationMenuItemOptions = HdsNavigationBadgeIconOptions）。
    const searchIcon: HdsNavigationIconOptions = {
      icon: $r('sys.symbol.magnifyingglass'),
      label: $r('app.string.settings_search'),
      isEnabled: this.switchingSlotId === '' &&
        !this.accountNavigationLocked && this.openingSettingPage === '',
      action: (): void => {
        if (this.switchingSlotId === '') {
          this.settingsSearchOpen = true;
          this.settingsQuery = '';
        }
      }
    };
    const searchItem: HdsNavigationMenuItemOptions = { content: searchIcon };
    return {
      title: { mainTitle: $r('app.string.settings_title') },
      menu: { value: [searchItem] }
    };
  }

  @Builder
  settingsBody() {
    // 两层 Column 是故意的：外层铺满、负责居中，内层才是被限宽的内容。
    // 限宽如果加在外面的 Scroll 上，滚动条和边缘回弹会跟着一起缩进来。
    // 搜索态和常态两条分支都走这个 Builder，限宽因此只写一处。
    Column() {
      Column() {
        if (!this.settingsSearchOpen) {
          this.accountsCard();
        }
        this.settingsCard();
      }
      .width('100%')
      .constraintSize({ maxWidth: readableContentWidth(this.screenW) });
    }
    .width('100%')
    // Column 默认左对齐：限了宽不居中就是把内容全堆在屏幕左边，比不限还难看。
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: this.bottomSafe + 88 });
  }

  build() {
    // 两条分支，不是一条。
    //
    // 常态走 HdsNavigation：大标题随滚动收缩、内容从标题栏底下穿过并渐变模糊
    // （issue #44 要的就是这个）。搜索态仍走原来那套 Column + topBar()——那里
    // 是一个 TextInput 加清除按钮，HDS 标题栏的 stackBuilder 能不能原样承载
    // 我没有真机可验，把一个能用的搜索框押在未经验证的槽位上不值得。
    //
    // 代价是开关搜索时 Scroll 会重挂、滚动位置归零；而搜索本来就会把列表换成
    // 过滤结果、并收起账号卡片，位置本就不连续，这个代价是可接受的。
    if (this.settingsSearchOpen) {
      Column() {
        this.topBar();
        Scroll() {
          this.settingsBody();
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off);
      }
      .width('100%').height('100%')
      .backgroundColor(PAGE_BG)
      .padding({ top: this.topSafe });
    } else {
      HdsNavigation(this.settingsStack) {
        Scroll(this.settingsScroller) {
          this.settingsBody();
        }
        .width('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)
        // navBar 的实际宽度：分栏时它就是左栏宽，拖分割线会变，MainScreen 的
        // dock 要跟着走。这个 Scroll 是 navBar 内容的根节点、width('100%')，
        // 它的宽度就是 navBar 宽度——HdsNavigation 没有回调宽度的接口，只能这么
        // 量（与 ChatListPage 靠 Tabs 的 onAreaChange 量同一个办法）。
        // 同值不写：onAreaChange 在滚动/键盘/单双栏切换时会连着来几次，而
        // setOrCreate 即便同值也会惊动订阅方。
        .onAreaChange((_old: Area, area: Area): void => {
          const w: number = area.width as number;
          if (AppStorage.get<number>(SETTINGS_NAV_BAR_WIDTH_KEY) !== w) {
            AppStorage.setOrCreate<number>(SETTINGS_NAV_BAR_WIDTH_KEY, w);
          }
        })
        // 不裁剪超出自身范围的子组件，内容才能穿透到标题栏下方——渐变模糊
        // 模糊的正是穿过去的这部分。官方示例同样这么写。
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
        enableComponentSafeArea: true,
        style: titleBarStyle(PAGE_BG),
        content: this.titleBarContent()
      })
      // 设置是从主界面进来的一级页面，顶部没有返回箭头。
      .hideBackButton(true)
      // FREE：初始大标题，随内容上滚收缩成 mini 标题栏。
      //
      // 【这里曾经是 .mode(NavigationMode.Stack)】原注释（保留在下面）说的是：
      // 「强制单栏：HdsNavigation 在宽屏（平板/横屏）会自动进分栏模式，我们只拿
      // 它当标题栏容器、不用 NavDestination——分栏的结果是整页内容挤进左列、
      // 右边一片空白（平板用户报"没法用了"）。」那条止血的前提是"不用
      // NavDestination"，本次改动起设置子页开始迁成 HdsNavDestination（首个是
      // PowerUsagePage），前提不再成立，止血可以拆。ChatListPage 上一轮拆的是
      // 同一条。
      // 不显式设 mode：HdsNavigation 默认就是 Auto——窗口 <600vp 走单栏（手机，
      // 观感与 router.pushUrl 一致），≥600vp 自动分栏（平板，左设置列表右子页）。
      .navBarWidthRange({ minWidth: this.navBarMinWidth(), maxWidth: this.navBarMaxWidth() })
      .minContentWidth(this.contentMinWidth())
      .enableDragBar(true)
      // navBar 显隐 = 「单栏且栈非空」。dock 要藏在这种时候，见
      // SETTINGS_NAV_BAR_VISIBLE_KEY 的说明。写入前先比一次：同值 setOrCreate 也会
      // 惊动订阅方，而这个回调在单双栏切换时会连着来几次。
      .onNavBarStateChange((isVisible: boolean): void => {
        if (AppStorage.get<boolean>(SETTINGS_NAV_BAR_VISIBLE_KEY) !== isVisible) {
          AppStorage.setOrCreate<boolean>(SETTINGS_NAV_BAR_VISIBLE_KEY, isVisible);
        }
      })
      // 关掉全模态联动：默认 true 时，bindSheet 一拉起就会触发栈顶
      // HdsNavDestination 的 onHidden。**本轮它是个空操作**——迁过来的
      // PowerUsagePage 既没有 bindSheet 也没有 onShown/onHidden。之所以现在就写上：
      // 待迁的十五个里有八个带 bindSheet（ProxyPage / ChatFoldersPage /
      // ActiveSessionsPage / BlockedUsersPage / PrivacyExceptionsPage /
      // FolderEditPage / FolderInviteLinksPage / WebPushPage），它们把 onPageHide
      // 映射成 .onHidden() 的那一刻，默认值就会让"一拉起面板页面就以为自己隐藏了"
      // ——ChatPage 上一轮正是踩了这个（一开转发面板音视频就停）。取值与聊天页签
      // 一致，两个页签没有理由不同。
      .enableVisibilityLifecycleWithContentCover(false)
      .titleMode(HdsNavigationTitleMode.FREE)
      .bindToScrollable([this.settingsScroller])
      .width('100%').height('100%')
      .backgroundColor(PAGE_BG)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    }
  }
}
