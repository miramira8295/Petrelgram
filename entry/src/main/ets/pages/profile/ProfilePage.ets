import {
  HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM, isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { router, promptAction } from '@kit.ArkUI';
import { profileMenuItems } from '../../util/profileMenu';
import { showProfileMoreMenu } from './ProfileMoreMenu';
import {
  KEY_SURFACE_GLASS_ON, SURFACE_GLASS_EPOCH, SURFACE_GLASS_ON_DEFAULT,
  surfaceGlassBlurStyle, surfaceGlassFill
} from '../../util/surfaceGlass';
import { getChatStore, getTdClient, getCallSession } from '../../tdkit/Globals';
import { ProfileStore, CommonGroup, StoryItem, GiftItem, AvailGift } from '../../store/ProfileStore';
import {
  ChatProfileStore, ProfileContentItem,
  PROFILE_TAB_MEMBERS, PROFILE_TAB_MEDIA, PROFILE_TAB_FILES, PROFILE_TAB_LINKS,
  PROFILE_TAB_MUSIC, PROFILE_TAB_POLLS, PROFILE_TAB_VOICE,
  PROFILE_TAB_VIDEO_NOTES, PROFILE_TAB_GIFS, PROFILE_TAB_GIFTS
} from '../../store/ChatProfileStore';
import {
  GLASS_GAP, GLASS_PAGE_PAD, GLASS_RADIUS_CARD, GLASS_RADIUS_CHIP,
  GLASS_RADIUS_TILE, GLASS_SHADOW_COLOR, GLASS_SHADOW_RADIUS, GLASS_SHADOW_Y
} from './ProfileGlass';
import {
  overlayBackdropBlur, overlayGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';
import { AvatarView } from '../chatlist/AvatarView';
import { ProfileMediaRow } from './ProfileMediaRow';
import { ProfileContentRow, profileContentKey } from './ProfileContentRow';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { guardKey } from '../../util/keyGuard';
import { chunkRows } from '../../util/gridRows';
import { QrDialog } from '../common/QrDialog';
import { AvatarViewer } from '../common/AvatarViewer';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY,
  COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_TAB_PILL_BG
} from '../../util/theme';
import { AppBackdrop } from '../common/AppBackdrop';
import { KEY_APP_BG_ON, KEY_FORCE_SINGLE_COLUMN
} from '../../store/AppSettings';
import { ExpandableText } from './ExpandableText';
import { openUrl } from '../../util/openUrl';
import { common } from '@kit.AbilityKit';
import { publicLink } from '../../util/telegramLink';
import { MUTE_LONG, setMute } from '../../store/ChatActions';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { logE } from '../../util/log';
import { MEDIA_GRID_COLS, mediaCellSize as mediaGridCellSize, mediaFallbackContentWidth } from '../../util/mediaGrid';
import { HdsNavDestination } from '@kit.UIDesignKit';

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const PAGE_BG: ResourceColor = $r('app.color.page_bg');
const PROFILE_TAB_STORIES: string = 'profileStories';
const PROFILE_TAB_RECEIVED_GIFTS: string = 'profileGifts';
const PROFILE_TAB_GROUPS: string = 'commonGroups';
const PROFILE_TAB_BAR_HEIGHT: number = 44;
const PROFILE_TAB_INDICATOR_HEIGHT: number = 32;

interface UserProfileTab {
  key: string;
  label: string;
}

const USER_PROFILE_TABS: UserProfileTab[] = [
  { key: PROFILE_TAB_STORIES, label: str('mp_stories') },
  { key: PROFILE_TAB_MEDIA, label: str('cpp_media') },
  { key: PROFILE_TAB_FILES, label: str('storage_file') },
  { key: PROFILE_TAB_LINKS, label: str('cpp_links') },
  { key: PROFILE_TAB_MUSIC, label: str('storage_audio') },
  { key: PROFILE_TAB_POLLS, label: str('poll_word') },
  { key: PROFILE_TAB_VOICE, label: str('storage_voice') },
  { key: PROFILE_TAB_VIDEO_NOTES, label: str('cp_video_message') },
  { key: PROFILE_TAB_GIFS, label: 'GIF' },
  { key: PROFILE_TAB_RECEIVED_GIFTS, label: str('cpp_gifts') },
  { key: PROFILE_TAB_GROUPS, label: str('gn_group') }
];

// User profile page (Telegram-style): avatar header, quick actions, personal
// channel card, info card (phone/bio/usernames/business), add-contact, and
// 动态/礼物/群组 tabs. Store data is MIRRORED into @State fields — ArkUI's
// minimal-update re-renders only nodes that read changed state, so reading
// plain store fields from build() would never refresh.
// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载
// 本模块并调用它，页面因此不再需要进 main_pages.json。
@Builder
export function ProfilePageBuilder(): void {
  ProfilePage();
}

const PROFILE_REFRESH_COALESCE_MS: number = 12;
const PROFILE_EFFECTS_AFTER_SHOWN_MS: number = 72;
const PROFILE_TRANSITION_ACTIONS: number[] = [0, 1, 2, 3, 4];
// 资料页 List 在可视区外多备的行数。
const PROFILE_LIST_CACHED_COUNT: number = 4;
// 礼物网格一行几格（与 storyCell 的三等分一致）。
const PROFILE_GIFT_COLS: number = 3;

@Preview
@Component
export struct ProfilePage {
  // 本页所在的 Navigation 栈，onReady 时拿到。返回按钮靠它出栈——本页已不是
  // router 页，router.back() 弹不到自己。
  private navStack: NavPathStack | undefined = undefined;
  // 路由参数。router 时代靠 router.getParams() 现取，NavDestination 要在
  // onReady 里从 NavDestinationContext 拿，而 onReady 实测晚于 aboutToAppear
  // （平板 API 26，见 ChatPage 的同名注释），所以吃参数的那一段整体挪进了
  // applyRouteParams()。
  private navParams: Record<string, Object> | undefined = undefined;
  // applyRouteParams() 的一次性守卫：那段里建了 ProfileStore 并订阅了它，句柄
  // 存在 this.store / this.unsub 上，重入会把旧句柄覆盖掉，旧订阅就再也退不掉。
  private paramsApplied: boolean = false;
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // 整体玻璃开关与档位（联系人页 / 群组简介页同一套）。
  @StorageProp(KEY_SURFACE_GLASS_ON) private surfaceGlassOn: boolean = SURFACE_GLASS_ON_DEFAULT;
  @StorageProp(SURFACE_GLASS_EPOCH) private surfaceGlassEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 设置里的「强制单栏」（宽屏也当手机用）。
  @StorageProp(KEY_FORCE_SINGLE_COLUMN) forceSingleColumn: boolean = false;
  @StorageProp('screenHeightVp') screenH: number = 780;
  // 系统断点（util/layoutBreakpoint）：分栏判据读它，不再按窗口宽高自己算。
  @StorageProp(KEY_WIDTH_BREAKPOINT) widthBp: number = WIDTH_BP_SM;
  @StorageProp(KEY_HEIGHT_BREAKPOINT) heightBp: number = HEIGHT_BP_LG;
  // APP 壁纸此刻生不生效。本页是压在主界面之上的 NavDestination，**下面那层壁纸
  // 透不过来**（HdsNavDestination 自带不透明底，Scroll 又铺了一层 page_bg），
  // 所以和 ChatPage 一样自己画一层——用户实报"点频道/群组/其他人详情看不到壁纸"。
  @StorageProp(KEY_APP_BG_ON) appWallpaperOn: boolean = false;
  @State profTab: number = 0;
  private pendingTabKey: string = '';
  @State name: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  // 头像点击放大（'' = 未打开）。
  @State viewerAvatarPath: string = '';
  @State avatarTapX: number = 0;
  @State avatarTapY: number = 0;
  @State avatarAnimPath: string = '';
  @State statusEmojiPath: string = '';
  @State statusEmojiFormat: string = '';
  @State statusText: string = '';
  @State phone: string = '';
  @State usernames: string[] = [];
  @State isContact: boolean = false;
  // 对方是否已被我屏蔽，决定「⋯」菜单显示屏蔽还是解除屏蔽。
  @State isBlocked: boolean = false;
  @State bio: string = '';
  @State bioEntities: TdObject[] = [];
  @State personalChatId: number = 0;
  @State bizOpen: boolean = false;
  @State bizHoursText: string = '';
  @State bizAddress: string = '';
  @State bizLat: number = 0;
  @State bizLng: number = 0;
  @State chTitle: string = '';
  @State chInitials: string = '?';
  @State chAvatarPath: string = '';
  @State chSubs: string = '';
  @State chPreview: string = '';
  @State @Watch('syncGroupsData') groups: CommonGroup[] = [];
  @State stories: StoryItem[] = [];
  @State @Watch('syncGiftsData') gifts: GiftItem[] = [];
  @State sharedTabKeys: string[] = [];
  @State sharedTabsState: string = 'loading';
  @State @Watch('syncSharedData') sharedItems: ProfileContentItem[] = [];
  // 共享媒体网格那张玻璃卡的内容宽，由 onAreaChange 量得；0 = 还没量到。
  @State private sharedRowW: number = 0;
  // 共同群组、礼物行、共享内容、共享媒体行各自的 LazyForEach 数据源。
  private groupsData: KeyedListDataSource<CommonGroup> = new KeyedListDataSource<CommonGroup>('profile-groups');
  private giftRowsData: KeyedListDataSource<GiftItem[]> = new KeyedListDataSource<GiftItem[]>('profile-gift-rows');
  private sharedData: KeyedListDataSource<ProfileContentItem> =
    new KeyedListDataSource<ProfileContentItem>('profile-shared');
  private sharedRowsData: KeyedListDataSource<ProfileContentItem[]> =
    new KeyedListDataSource<ProfileContentItem[]>('profile-shared-rows');
  @State sharedState: string = 'idle';
  @State sharedErrorText: string = '';
  @State sharedHasMore: boolean = false;
  @State sharedPaging: boolean = false;
  @State sharedPagingError: boolean = false;
  @State tabIndicatorX: number = 8;
  @State tabIndicatorW: number = 0;
  @State availGifts: AvailGift[] = [];
  @State showGiftPicker: boolean = false;
  @State private profileContentReady: boolean = false;
  // Build the destination's moving first frame without 13+ independent
  // material/shadow layers. onShown enables the visual effects after data has
  // been mirrored once outside the system transition.
  @State private profileEffectsReady: boolean = false;
  private userId: number = 0;
  private privateChatId: number = 0;
  private pendingDraftText: string = '';
  private pendingStartParam: string = '';
  private pendingJumpTo: number = 0;
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;
  private profileShown: boolean = false;
  private profileRefreshPending: boolean = false;
  private profileRefreshTimer: number = -1;
  private profileEffectsTimer: number = -1;
  private sharedStore: ChatProfileStore | null = null;
  private sharedUnsub: (() => void) | null = null;
  private tabScroller: Scroller = new Scroller();
  private tabXs: number[] = [];
  private tabWs: number[] = [];
  private tabViewW: number = 0;

  @Styles
  tabNormalStyle() {
    .opacity(1)
  }

  @Styles
  tabPressedStyle() {
    .opacity(0.62)
  }

  @Styles
  // 行的常态必须透明：刷成 CARD_BG 会把底下整块卡片的玻璃盖住，列表看起来
  // 就是一块实心板。按压态用半透明高光，压在玻璃上仍然看得见。
  sharedRowNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  sharedRowPressedStyle() {
    .backgroundColor($r('app.color.press_overlay'))
  }

  // 迁移前 aboutToAppear 的**全部**内容都吃路由参数（userId 一路渗透到建
  // ProfileStore），所以整段搬进了 applyRouteParams()，这里没有留下任何一行。
  // 保留空方法是为了让这条注释有地方待着：读代码的人会先来找 aboutToAppear。
  aboutToAppear(): void {
  }

  // 路由参数就绪后的初始化。就是迁移前 aboutToAppear 的全部内容，顺序一字未改，
  // 只是改由 onReady 触发——onReady 才是拿得到 pathInfo.param 的第一个时机。
  private applyRouteParams(): void {
    if (this.paramsApplied) {
      return;
    }
    this.paramsApplied = true;
    const params = this.navParams;
    this.userId = params !== undefined
      ? ((params['userId'] as number | undefined) ?? 0) : 0;
    this.pendingDraftText = params !== undefined
      ? ((params['draftText'] as string | undefined) ?? '') : '';
    this.pendingStartParam = params !== undefined
      ? ((params['startParam'] as string | undefined) ?? '') : '';
    this.pendingJumpTo = params !== undefined
      ? ((params['jumpTo'] as number | undefined) ?? 0) : 0;
    // 首次进来要落到哪个页签（issue #166 的「显示所有图片」），用一次即清。
    this.pendingTabKey = params !== undefined
      ? ((params['tab'] as string | undefined) ?? '') : '';
    const store = new ProfileStore(getTdClient(), this.userId);
    this.store = store;
    this.unsub = store.subscribe((): void => { this.onProfileStoreChanged(); });
    store.open();
  }

  private onProfileStoreChanged(): void {
    this.profileRefreshPending = true;
    this.scheduleProfileRefresh();
  }

  private scheduleProfileRefresh(): void {
    if (!this.profileShown || !this.profileRefreshPending || this.profileRefreshTimer !== -1) {
      return;
    }
    this.profileRefreshTimer = setTimeout((): void => {
      this.profileRefreshTimer = -1;
      if (!this.profileShown || !this.profileRefreshPending) {
        return;
      }
      this.profileRefreshPending = false;
      this.refresh();
      this.profileContentReady = true;
    }, PROFILE_REFRESH_COALESCE_MS);
  }

  private handleShown(): void {
    this.profileShown = true;
    this.scheduleProfileRefresh();
    if (!this.profileEffectsReady && this.profileEffectsTimer === -1) {
      this.profileEffectsTimer = setTimeout((): void => {
        this.profileEffectsTimer = -1;
        if (this.profileShown) {
          this.profileEffectsReady = true;
        }
      }, PROFILE_EFFECTS_AFTER_SHOWN_MS);
    }
  }

  private handleWillHide(): void {
    // Stop consuming store publications before the destination starts moving
    // underneath the next page. The newest snapshot is applied once on return.
    this.profileShown = false;
    if (this.profileRefreshTimer !== -1) {
      clearTimeout(this.profileRefreshTimer);
      this.profileRefreshTimer = -1;
    }
    if (this.profileEffectsTimer !== -1) {
      clearTimeout(this.profileEffectsTimer);
      this.profileEffectsTimer = -1;
    }
  }

  // 返回上一层。**不能用 router.back()**：本页是 HdsNavDestination，router 页栈里
  // 只剩 Index 一层，router.back() 弹掉的是 Index——平板模拟器实测（Task 7 修复轮 1）
  // 的现象是「点返回箭头直接退到桌面」。要出的是 Navigation 栈。
  private moreMenuItems(): string[] {
    const self: number = getChatStore().selfUserId();
    return profileMenuItems({
      isSelf: self !== 0 && self === this.userId,
      isBlocked: this.isBlocked,
      isContact: this.isContact
    });
  }

  private openMoreMenu(): void {
    showProfileMoreMenu(this.moreMenuItems(),
      { userId: this.userId, name: this.name, ui: this.getUIContext() });
  }

  private goBack(): void {
    const stack = this.navStack;
    if (stack === undefined) {
      // navStack 由 onReady(ctx.pathStack) 填，而 onReady 必先于本页可见，所以
      // 这一支不该发生。这里**故意不回退到 router.back()**：那正是会退出应用的
      // 那条路，把返回键做成"什么都不做 + 一条日志"远比把应用关掉好。
      logE('ProfilePage.goBack: navStack missing, back ignored');
      return;
    }
    // pop() 弹的就是本页这一层。栈空时它返回 undefined，但那意味着"本页正显示
    // 却不在栈里"，不可能发生，故不另做处理。
    stack.pop();
  }

  aboutToDisappear(): void {
    if (this.profileRefreshTimer !== -1) {
      clearTimeout(this.profileRefreshTimer);
      this.profileRefreshTimer = -1;
    }
    if (this.profileEffectsTimer !== -1) {
      clearTimeout(this.profileEffectsTimer);
      this.profileEffectsTimer = -1;
    }
    this.profileShown = false;
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
    if (this.sharedUnsub !== null) { this.sharedUnsub(); this.sharedUnsub = null; }
    if (this.sharedStore !== null) { this.sharedStore.close(); this.sharedStore = null; }
  }

  @State qrLink: string = '';
  private qrCtrl: CustomDialogController = new CustomDialogController({
    builder: QrDialog({ link: this.qrLink, title: this.name }),
    alignment: DialogAlignment.Center,
    autoCancel: true
  });

  private openQr(username: string): void {
    if (username === '') {
      return;
    }
    this.qrLink = publicLink(username);
    this.qrCtrl.open();
  }

  private visibleProfileTabs(): UserProfileTab[] {
    return USER_PROFILE_TABS.filter((tab: UserProfileTab): boolean => {
      if (tab.key === PROFILE_TAB_STORIES) {
        return this.stories.length > 0;
      }
      if (tab.key === PROFILE_TAB_RECEIVED_GIFTS) {
        return this.gifts.length > 0;
      }
      if (tab.key === PROFILE_TAB_GROUPS) {
        return this.groups.length > 0;
      }
      return this.sharedTabsState === 'ready' &&
        tab.key !== PROFILE_TAB_MEMBERS && tab.key !== PROFILE_TAB_GIFTS &&
        this.sharedTabKeys.indexOf(tab.key) >= 0;
    });
  }

  private currentProfileTabKey(): string {
    const tabs = this.visibleProfileTabs();
    return tabs.length > 0 && this.profTab < tabs.length ? tabs[this.profTab].key : '';
  }

  private isSharedProfileTab(key: string): boolean {
    return key !== '' && key !== PROFILE_TAB_STORIES &&
      key !== PROFILE_TAB_RECEIVED_GIFTS && key !== PROFILE_TAB_GROUPS;
  }

  private reconcileProfileTab(preferredKey: string): void {
    const tabs = this.visibleProfileTabs();
    if (tabs.length === 0) {
      this.profTab = 0;
      return;
    }
    const wantedKey: string = this.pendingTabKey !== '' ? this.pendingTabKey : preferredKey;
    const found = wantedKey !== ''
      ? tabs.findIndex((tab: UserProfileTab): boolean => tab.key === wantedKey) : -1;
    if (this.pendingTabKey !== '' && found >= 0) {
      this.pendingTabKey = '';
    }
    this.profTab = found >= 0 ? found : 0;
    const selectedKey = tabs[this.profTab].key;
    if (this.isSharedProfileTab(selectedKey) && this.sharedStore !== null &&
      this.sharedStore.contentTab !== selectedKey) {
      this.sharedStore.selectContentTab(selectedKey);
    }
    this.moveProfileTabIndicator(this.profTab);
  }

  private startSharedStore(chatId: number): void {
    if (chatId <= 0 || (chatId === this.privateChatId && this.sharedStore !== null)) {
      return;
    }
    if (this.sharedUnsub !== null) {
      this.sharedUnsub();
      this.sharedUnsub = null;
    }
    if (this.sharedStore !== null) {
      this.sharedStore.close();
    }
    this.privateChatId = chatId;
    const store = new ChatProfileStore(getTdClient(), chatId);
    this.sharedStore = store;
    this.sharedUnsub = store.subscribe((): void => { this.refreshSharedContent(); });
    store.open();
  }

  private refreshSharedContent(): void {
    const store = this.sharedStore;
    if (store === null) {
      return;
    }
    const beforeKey = this.currentProfileTabKey();
    this.sharedTabKeys = store.availableTabs;
    this.sharedTabsState = store.tabsState;
    this.sharedItems = store.contentItems;
    this.sharedState = store.contentState;
    this.sharedErrorText = store.contentErrorText;
    this.sharedHasMore = store.contentHasMore;
    this.sharedPaging = store.contentPaging;
    this.sharedPagingError = store.contentPagingError;
    this.reconcileProfileTab(beforeKey);
  }

  // Copy the store snapshot into @State so every card re-renders on updates.
  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    const beforeKey = this.currentProfileTabKey();
    this.name = s.name;
    this.initials = s.initials;
    this.avatarPath = s.avatarPath;
    this.avatarAnimPath = s.avatarAnimPath;
    this.statusEmojiPath = s.statusEmojiPath;
    this.statusEmojiFormat = s.statusEmojiFormat;
    this.statusText = s.statusText;
    this.phone = s.phone;
    this.usernames = s.usernames;
    this.isContact = s.isContact;
    this.isBlocked = s.isBlocked;
    this.bio = s.bio;
    this.bioEntities = s.bioEntities;
    this.personalChatId = s.personalChatId;
    this.bizOpen = s.bizOpen;
    this.bizHoursText = s.bizHoursText;
    this.bizAddress = s.bizAddress;
    this.bizLat = s.bizLat;
    this.bizLng = s.bizLng;
    this.chTitle = s.chTitle;
    this.chInitials = s.chInitials;
    this.chAvatarPath = s.chAvatarPath;
    this.chSubs = s.chSubs;
    this.chPreview = s.chPreview;
    this.groups = s.groups;
    this.stories = s.stories;
    this.gifts = s.gifts;
    this.availGifts = s.availableGifts;
    if (s.privateChatId > 0) {
      this.startSharedStore(s.privateChatId);
    }
    this.reconcileProfileTab(beforeKey);
  }

  private sendGift(g: AvailGift): void {
    if (this.store === null) {
      return;
    }
    this.store.sendGift(g.id, (error: string) => {
      if (error === '') {
        this.showGiftPicker = false;
        promptAction.showToast({ message: $r('app.string.pp_gift_sent') });
      } else if (error.indexOf('BALANCE') >= 0) {
        promptAction.showToast({ message: $r('app.string.pp_not_enough_stars') });
      } else {
        promptAction.showToast({ message: str('pp_send_failed_msg', error) });
      }
    });
  }

  private openChat(chatId: number): void {
    const params: Record<string, Object> = { 'chatId': chatId };
    if (this.pendingDraftText !== '') {
      params['draftText'] = this.pendingDraftText;
    }
    if (this.pendingJumpTo > 0) {
      params['jumpTo'] = this.pendingJumpTo;
    }
    navigateToChat(params, 'content').catch(logChatNavFailure);
  }

  private startCall(isVideo: boolean): void {
    if (this.userId <= 0) {
      return;
    }
    getCallSession().startCall(this.userId, isVideo);
    router.pushUrl({ url: 'pages/call/CallPage' }).catch((error: Error): void => {
      logE(`ProfilePage.startCall navigation failed: ${error.message}`);
    });
  }

  private sendMessage(): void {
    // Ensure the private chat exists before navigating into it.
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = this.userId;
    req['force'] = false;
    getTdClient().send(req).then((chat: TdObject) => {
      const id = chat['id'] as number | undefined;
      if (id !== undefined) {
        this.openChat(id);
        if (this.pendingStartParam !== '') {
          const start: TdRequest = { '@type': 'sendBotStartMessage' };
          start['bot_user_id'] = this.userId;
          start['chat_id'] = id;
          start['parameter'] = this.pendingStartParam;
          this.pendingStartParam = '';
          getTdClient().send(start).catch((e: TdError): void => {
            logE(`ProfilePage.sendBotStartMessage failed: ${e.message}`);
            promptAction.showToast({ message: $r('app.string.pp_start_failed'), duration: 1500 });
          });
        }
      }
    }).catch((e: TdError) => {
      logE(`ProfilePage.createPrivateChat failed: ${e.message}`);
    });
  }

  private addContact(): void {
    this.sendAddContact().then(() => {
      this.isContact = true;
      promptAction.showToast({ message: $r('app.string.pp_added_contact'), duration: 1500 });
    }).catch((e: TdError) => {
      // min user：本地没有对方的 access hash（只在群消息里见过对方时的常态），
      // addContact 按 id 直发会报 400 User not found。电话可见时按 TDLib 推荐
      // 路径先 searchUserByPhoneNumber 取回完整用户，再重试一次。
      if (e.code === 400 && this.phone !== '') {
        const lookup: TdRequest = { '@type': 'searchUserByPhoneNumber' };
        lookup['phone_number'] = this.phone;
        getTdClient().send(lookup)
          .then(() => this.sendAddContact())
          .then(() => {
            this.isContact = true;
            promptAction.showToast({ message: $r('app.string.pp_added_contact'), duration: 1500 });
          })
          .catch((retryError: TdError) => {
            logE(`ProfilePage.addContact retry failed(code=${retryError.code}): ` +
              `${retryError.message} userId=${this.userId}`);
            this.importContactFallback();
          });
        return;
      }
      // 手机号和姓名是对方的个人信息，不进日志——userId 已经足够把这条
      // 失败对上号了。
      logE(`ProfilePage.addContact failed(code=${e.code}): ${e.message} ` +
        `userId=${this.userId} hasPhone=${this.phone !== ''}`);
      promptAction.showToast({
        message: e.code === 400 ? $r('app.string.pp_add_incomplete') : $r('app.string.pp_add_failed'),
        duration: 1700
      });
    });
  }

  // 最后一层回退：按手机号导入通讯录（官方客户端处理分享名片同款路径）。
  // 服务器能解析该号码时对方直接成为联系人；解析不到（对方隐私限制）则
  // user_ids 返回 0 —— 平台层面无法添加，只能如实提示。
  private importContactFallback(): void {
    const contact: TdObject = { '@type': 'contact' };
    contact['phone_number'] = this.phone;
    contact['first_name'] = this.name !== '' ? this.name : $r('app.string.tab_contacts');
    contact['last_name'] = '';
    contact['user_id'] = 0;
    const req: TdRequest = { '@type': 'importContacts' };
    req['contacts'] = [contact];
    getTdClient().send(req).then((res: TdObject) => {
      const userIds: number[] = (res['user_ids'] as number[] | undefined) ?? [];
      if (userIds.length > 0 && userIds[0] > 0) {
        this.isContact = true;
        promptAction.showToast({ message: $r('app.string.pp_added_contact'), duration: 1500 });
        return;
      }
      promptAction.showToast({
        message: $r('app.string.pp_privacy_blocks_add'), duration: 2000
      });
    }).catch((e: TdError) => {
      logE(`ProfilePage.importContacts failed(code=${e.code}): ${e.message}`);
      promptAction.showToast({ message: $r('app.string.pp_add_failed'), duration: 1700 });
    });
  }

  private sendAddContact(): Promise<TdObject> {
    const contact: TdObject = { '@type': 'contact' };
    contact['phone_number'] = this.phone;
    contact['first_name'] = this.name !== '' ? this.name : $r('app.string.tab_contacts');
    contact['last_name'] = '';
    contact['user_id'] = this.userId;
    const req: TdRequest = { '@type': 'addContact' };
    req['contact'] = contact;
    req['share_phone_number'] = false;
    return getTdClient().send(req);
  }

  private toggleMute(): void {
    setMute(this.userId, MUTE_LONG);
  }

  // 位置 tap → system map app via geo: URI (coordinates when TDLib provides
  // them, otherwise an address query).
  private openMap(): void {
    const hasCoords = this.bizLat !== 0 || this.bizLng !== 0;
    const q = encodeURIComponent(this.bizAddress);
    const uri = hasCoords ? `geo:${this.bizLat},${this.bizLng}?q=${q}` : `geo:0,0?q=${q}`;
    openUrl(getContext(this) as common.UIAbilityContext, uri);
  }

  private moveProfileTabIndicator(index: number): void {
    const tabs = this.visibleProfileTabs();
    if (index < 0 || index >= tabs.length) {
      return;
    }
    const width = this.tabWs[index] ?? 0;
    if (width <= 0) {
      return;
    }
    this.tabIndicatorX = this.tabXs[index] ?? 8;
    this.tabIndicatorW = width;
  }

  private ensureProfileTabVisible(index: number): void {
    const x = this.tabXs[index] ?? 0;
    const width = this.tabWs[index] ?? 0;
    if (width <= 0 || this.tabViewW <= 0) {
      return;
    }
    const offset = this.tabScroller.currentOffset().xOffset;
    let target = -1;
    if (x < offset + 8) {
      target = Math.max(0, x - 8);
    } else if (x + width > offset + this.tabViewW - 8) {
      target = x + width - this.tabViewW + 8;
    }
    if (target >= 0) {
      this.tabScroller.scrollTo({
        xOffset: target,
        yOffset: 0,
        animation: { duration: 200, curve: Curve.EaseOut }
      });
    }
  }

  private selectProfileTab(index: number): void {
    const tabs = this.visibleProfileTabs();
    if (index < 0 || index >= tabs.length || index === this.profTab) {
      return;
    }
    const key = tabs[index].key;
    animateTo({ duration: 220, curve: Curve.EaseOut }, (): void => {
      this.profTab = index;
      this.moveProfileTabIndicator(index);
    });
    this.ensureProfileTabVisible(index);
    if (this.isSharedProfileTab(key) && this.sharedStore !== null) {
      this.sharedStore.selectContentTab(key);
    }
  }

  private handleProfileTabPan(offsetX: number): void {
    if (Math.abs(offsetX) < 42) {
      return;
    }
    if (offsetX < 0) {
      this.selectProfileTab(this.profTab + 1);
    } else {
      this.selectProfileTab(this.profTab - 1);
    }
  }

  private openSharedMessage(messageId: number): void {
    if (this.privateChatId > 0 && messageId > 0) {
      // 曾经是 router.pushUrl('pages/chat/ChatPage')——ChatPage 迁成
      // HdsNavDestination 后已从 main_pages.json 摘掉，直连 router 会跳不动。
      // 走 navigateToChat 这个唯一漏斗，由它决定推栈还是回退整页路由。
      const params: Record<string, Object> = {
        'chatId': this.privateChatId, 'jumpTo': messageId
      };
      navigateToChat(params, 'content').catch(logChatNavFailure);
    }
  }

  private syncGroupsData(): void {
    this.groupsData.update(this.groups,
      this.groups.map((g: CommonGroup): string => `${g.id}`),
      this.groups.map((g: CommonGroup): string => `${g.id}_${g.title}_${g.avatarPath}`));
  }

  // 网格行以位置为身份：追加只会让最后一个不满的行变内容、后面加新行（CHANGE + ADD）。
  private giftRowKey(row: GiftItem[], index: number): string {
    return `gifts_${index}_` + row.map((g: GiftItem): string => `${g.id}_${g.stickerPath}`).join('|');
  }

  private syncGiftsData(): void {
    const rows: GiftItem[][] = chunkRows(this.gifts, PROFILE_GIFT_COLS);
    this.giftRowsData.update(rows,
      rows.map((_row: GiftItem[], index: number): string => `gifts_${index}`),
      rows.map((row: GiftItem[], index: number): string => this.giftRowKey(row, index)));
  }

  private sharedRowKey(row: ProfileContentItem[], index: number): string {
    return `row_${index}_` + row.map((it: ProfileContentItem): string =>
      `${it.messageId}_${it.thumbPath}_${it.duration}`).join('|');
  }

  private syncSharedData(): void {
    const items: ProfileContentItem[] = this.sharedItems;
    this.sharedData.update(items,
      items.map((it: ProfileContentItem): string => `${it.messageId}`),
      items.map((it: ProfileContentItem): string => profileContentKey(it)));
    const rows: ProfileContentItem[][] = chunkRows(items, MEDIA_GRID_COLS);
    this.sharedRowsData.update(rows,
      rows.map((_row: ProfileContentItem[], index: number): string => `row_${index}`),
      rows.map((row: ProfileContentItem[], index: number): string => this.sharedRowKey(row, index)));
  }

  // 共享媒体网格的行宽（= 玻璃卡内容宽），格子边长按它算。没真的变就不写回状态。
  private noteSharedRowWidth(width: number): void {
    if (width > 0 && Math.abs(width - this.sharedRowW) > 0.5) {
      this.sharedRowW = width;
    }
  }

  private storyCell(): number {
    return (this.screenW - 4) / 3;
  }

  private formatDuration(totalSeconds: number): string {
    const m = Math.floor(totalSeconds / 60);
    const s = totalSeconds % 60;
    return `${m}:${`${s}`.padStart(2, '0')}`;
  }

  // 和群组简介页同一套玻璃面。**两页必须看起来是同一个页面**，所以 ChatProfilePage
  // 2026-09-18 改走联系人页那套（util/surfaceGlass）时，这里必须一起改——否则
  // 一页是实色卡片、另一页是透明框。
  // 原来那套（overlayGlassFill + 组件级材质）在这台设备上就是一个个透明框：
  // 材质"可用"→ 底色返回透明 → 把观感让给早已被系统收回的组件级 systemMaterial。
  private glassOn(): boolean {
    return this.profileEffectsReady && this.surfaceGlassOn && this.surfaceGlassEpoch >= 0;
  }

  private profileGlassFill(): ResourceColor {
    return this.glassOn() ? surfaceGlassFill($r('app.color.surface')) : $r('app.color.surface');
  }

  // 框架容器材质，不是 backdropBlur——后者在节点边缘有采样衰减，四角最明显。
  private profileGlassBlurStyle(): BlurStyle | undefined {
    return this.glassOn() ? surfaceGlassBlurStyle() : undefined;
  }

  private profileGlassShadowRadius(): number {
    return this.profileEffectsReady ? GLASS_SHADOW_RADIUS : 0;
  }

  private profileGlassShadowY(): number {
    return this.profileEffectsReady ? GLASS_SHADOW_Y : 0;
  }

  @Styles
  glassCard() {
    .backgroundColor(this.profileGlassFill())
    .backgroundBlurStyle(this.profileGlassBlurStyle())
    .borderRadius(GLASS_RADIUS_CARD)
    .border({ width: 0.7, color: $r('app.color.divider') })
    .shadow({ radius: this.profileGlassShadowRadius(), color: GLASS_SHADOW_COLOR,
      offsetX: 0, offsetY: this.profileGlassShadowY() })
    .attributeModifier(materialModifierWhen('card', this.profileEffectsReady))
  }

  @Styles
  glassTile() {
    .backgroundColor(this.profileGlassFill())
    .backgroundBlurStyle(this.profileGlassBlurStyle())
    .borderRadius(GLASS_RADIUS_TILE)
    .border({ width: 0.7, color: $r('app.color.divider') })
    .shadow({ radius: this.profileGlassShadowRadius(), color: GLASS_SHADOW_COLOR,
      offsetX: 0, offsetY: this.profileGlassShadowY() })
    .attributeModifier(materialModifierWhen('card', this.profileEffectsReady))
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(44).height(44).borderRadius(22)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.profileGlassFill())
    .backgroundBlurStyle(this.profileGlassBlurStyle())
    .border({ width: 0.7, color: $r('app.color.divider') })
    .shadow({ radius: this.profileGlassShadowRadius(), color: GLASS_SHADOW_COLOR,
      offsetX: 0, offsetY: this.profileGlassShadowY() })
    .attributeModifier(materialModifierWhen('card', this.profileEffectsReady))
    .onClick(onTap);
  }

  @Builder
  actionButton(symbol: string, label: string, onTap: () => void) {
    Column({ space: 7 }) {
      SymbolGlyph($r(symbol)).fontSize(24).fontColor([COLOR_PRIMARY]);
      Text(label).fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .layoutWeight(1).height(86)
    .justifyContent(FlexAlign.Center)
    .glassTile()
    .onClick(onTap);
  }

  @Builder
  infoRow(value: string, label: string, valueColor: ResourceColor) {
    Column({ space: 2 }) {
      Text(value).fontSize(15).fontColor(valueColor).copyOption(CopyOptions.LocalDevice);
      Text(label).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 8, bottom: 8 });
  }

  @Builder
  header() {
    Column({ space: 8 }) {
      Row() {
        this.circleButton('sys.symbol.chevron_left', () => { this.goBack(); });
        Blank().layoutWeight(1);
        // 原来回调是空函数（#219-2：点了没反应）。菜单内容与动作见 ProfileMoreMenu。
        if (this.moreMenuItems().length > 0) {
          this.circleButton('sys.symbol.more', () => { this.openMoreMenu(); });
        }
      }.width('100%').padding({ left: GLASS_PAGE_PAD, right: GLASS_PAGE_PAD });
      Column() {
        AvatarView({
          avatarPath: this.avatarPath, initials: this.initials,
          colorSeed: this.userId, avatarSize: 116,
          animPath: this.avatarAnimPath
        });
      }
      .width(130).height(130).padding(7).borderRadius(65)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.profileGlassFill())
      .backgroundBlurStyle(this.profileGlassBlurStyle())
      .border({ width: 0.7, color: $r('app.color.divider') })
      .shadow({ radius: this.profileGlassShadowRadius(), color: GLASS_SHADOW_COLOR,
        offsetX: 0, offsetY: this.profileGlassShadowY() })
      .attributeModifier(materialModifierWhen('card', this.profileEffectsReady))
        // 没有头像文件时（仅首字母占位）点击无意义，不给反馈。
        // 记下点击处的屏幕坐标，查看器据此决定放大/缩回的中心点。
        .onClick((event: ClickEvent): void => {
          if (this.avatarPath !== '') {
            this.avatarTapX = event.windowX;
            this.avatarTapY = event.windowY;
            this.viewerAvatarPath = this.avatarPath;
          }
        });
      Row({ space: 5 }) {
        Text(this.name)
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1);
        if (this.statusEmojiPath !== '') {
          this.statusEmoji();
        }
      }
      .alignItems(VerticalAlign.Center)
      .constraintSize({ maxWidth: '86%' });
      Text(this.statusText).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 });
  }

  @Builder
  actionsRow() {
    Row({ space: 8 }) {
      this.actionButton('sys.symbol.message', str('cps_messages'), () => { this.sendMessage(); });
      this.actionButton('sys.symbol.bell', str('cp_mute'), () => { this.toggleMute(); });
      this.actionButton('sys.symbol.phone', str('pp_call'), () => { this.startCall(false); });
      this.actionButton('sys.symbol.video', str('storage_video'), () => { this.startCall(true); });
      this.actionButton('sys.symbol.gift', str('cpp_gifts'), () => {
        if (this.store !== null) {
          this.store.loadAvailableGifts();
        }
        this.showGiftPicker = true;
      });
    }
    .width('100%').padding({ left: 12, right: 12, top: 14 });
  }

  @Builder
  channelCard() {
    // Outer wrapper carries the margins — width('100%') and horizontal margin
    // on the same node conflict in ArkUI (the margin is swallowed).
    Column() {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text($r('app.string.gn_channel')).fontSize(14).fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Bold);
          Text(this.chSubs).fontSize(13).fontColor(COLOR_PRIMARY);
          Blank().layoutWeight(1);
        }.width('100%');
        Row({ space: 10 }) {
          AvatarView({
            avatarPath: this.chAvatarPath, initials: this.chInitials,
            colorSeed: this.personalChatId, avatarSize: 46
          });
          Column({ space: 2 }) {
            Text(this.chTitle).fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(this.chPreview).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }.width('100%');
      }
      .width('100%').padding(12)
      .glassCard()
      .alignItems(HorizontalAlign.Start)
      .onClick(() => { this.openChat(this.personalChatId); });
    }
    .margin({ left: GLASS_PAGE_PAD, right: GLASS_PAGE_PAD, top: GLASS_GAP });
  }

  @Builder
  sectionDivider() {
    Divider().color($r('app.color.divider')).strokeWidth(0.7);
  }

  @Builder
  infoCard() {
    Column() {
      Column() {
        if (this.phone !== '') {
          this.infoRow(`+${this.phone}`, this.phone.startsWith('888') ? str('pp_anonymous_number') : str('ct_phone'), COLOR_TEXT_PRIMARY);
        }
        if (this.bio !== '') {
          if (this.phone !== '') {
            this.sectionDivider();
          }
          Column({ space: 2 }) {
            ExpandableText({ content: this.bio, entities: this.bioEntities });
            Text($r('app.string.ae_bio')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ top: 8, bottom: 8 });
        }
        if (this.usernames.length > 0) {
          if (this.phone !== '' || this.bio !== '') {
            this.sectionDivider();
          }
          Row() {
            Column({ space: 2 }) {
              Text(`@${this.usernames[0]}`).fontSize(15).fontColor(COLOR_PRIMARY).copyOption(CopyOptions.LocalDevice);
              if (this.usernames.length > 1) {
                Text(str('pp_also_usernames', this.usernames.slice(1).map((u: string) => `@${u}`).join(', ')))
                  .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
              } else {
                Text($r('app.string.ae_username')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.qrcode')).fontSize(22).fontColor([COLOR_ICON_SECONDARY])
              .onClick(() => { this.openQr(this.usernames.length > 0 ? this.usernames[0] : ''); });
          }
          .width('100%').padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center);
        }
        if (this.bizHoursText !== '') {
          if (this.phone !== '' || this.bio !== '' || this.usernames.length > 0) {
            this.sectionDivider();
          }
          Row() {
            Column({ space: 2 }) {
              Text(this.bizOpen ? $r('app.string.pp_open_now') : $r('app.string.pp_closed_now'))
                .fontSize(15).fontColor(this.bizOpen ? '#34C759' : '#FF3B30');
              Text($r('app.string.pp_opening_hours')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Text(this.bizHoursText).fontSize(14).fontColor(COLOR_TEXT_PRIMARY);
          }
          .width('100%').padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center);
        }
        if (this.bizAddress !== '') {
          if (this.phone !== '' || this.bio !== '' || this.usernames.length > 0 || this.bizHoursText !== '') {
            this.sectionDivider();
          }
          Column({ space: 2 }) {
            Text(this.bizAddress).fontSize(15).fontColor(COLOR_PRIMARY)
              .copyOption(CopyOptions.LocalDevice);
            Text($r('app.string.pp_location_tap')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => { this.openMap(); });
        }
        if (this.phone === '' && this.bio === '' && this.usernames.length === 0
          && this.bizHoursText === '' && this.bizAddress === '') {
          Text($r('app.string.cpp_no_profile')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .padding({ top: 10, bottom: 10 });
        }
      }
      .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .glassCard()
      .alignItems(HorizontalAlign.Start);
    }
    .margin({ left: GLASS_PAGE_PAD, right: GLASS_PAGE_PAD, top: GLASS_GAP });
  }

  private creatingSecretChat: boolean = false;

  // 端到端加密会话：createNewSecretChat 返回新的 secret chat 会话。
  private startSecretChat(): void {
    if (this.userId <= 0 || this.creatingSecretChat) {
      return;
    }
    this.creatingSecretChat = true;
    const req: TdRequest = { '@type': 'createNewSecretChat' };
    req['user_id'] = this.userId;
    getTdClient().send(req).then((chat: TdObject): void => {
      this.creatingSecretChat = false;
      const chatId: number = (chat['id'] as number | undefined) ?? 0;
      if (chatId === 0) {
        promptAction.showToast({ message: $r('app.string.pp_secret_failed'), duration: 1700 });
        return;
      }
      const params: Record<string, Object> = { 'chatId': chatId };
      navigateToChat(params, 'content').catch(logChatNavFailure);
    }).catch((e: TdError): void => {
      this.creatingSecretChat = false;
      logE(`ProfilePage.createNewSecretChat failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.pp_secret_failed_retry'), duration: 1700 });
    });
  }

  @Builder
  secretChatCard() {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(22)
          .fontColor(['#31C48D']);
        Text($r('app.string.pp_start_secret'))
          .fontSize(15)
          .fontColor('#31C48D');
      }
      .width('100%')
      .padding(14)
      .glassCard()
      .onClick((): void => { this.startSecretChat(); });
    }
    .margin({ left: GLASS_PAGE_PAD, right: GLASS_PAGE_PAD, top: GLASS_GAP });
  }

  @Builder
  addContactCard() {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.person_badge_plus'))
          .fontSize(22)
          .fontColor([COLOR_TEXT_PRIMARY]);
        Text($r('app.string.pp_add_contact'))
          .fontSize(15)
          .fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%')
      .padding(14)
      .glassCard()
      .onClick((): void => { this.addContact(); });
    }
    .margin({ left: GLASS_PAGE_PAD, right: GLASS_PAGE_PAD, top: GLASS_GAP });
  }

  @Builder
  tabsBar() {
    Column() {
      Scroll(this.tabScroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          Row()
            .width(this.tabIndicatorW).height(PROFILE_TAB_INDICATOR_HEIGHT)
            .borderRadius(PROFILE_TAB_INDICATOR_HEIGHT / 2)
            .backgroundColor(COLOR_TAB_PILL_BG)
            .position({
              x: this.tabIndicatorX,
              y: (PROFILE_TAB_BAR_HEIGHT - PROFILE_TAB_INDICATOR_HEIGHT) / 2
            });
          Row() {
            ForEach(this.visibleProfileTabs(), (tab: UserProfileTab, index: number) => {
              Row() {
                Text(tab.label).fontSize(14)
                  .fontWeight(this.profTab === index ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.profTab === index ? COLOR_TAB_SELECTED : COLOR_TAB_UNSELECTED)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              .height(PROFILE_TAB_BAR_HEIGHT)
              .padding({ left: 12, right: 12 }).margin({ right: 2 })
              .borderRadius(PROFILE_TAB_BAR_HEIGHT / 2)
              .stateStyles({ normal: this.tabNormalStyle, pressed: this.tabPressedStyle })
              .onAreaChange((_old: Area, area: Area): void => {
                this.tabXs[index] = area.position.x as number;
                this.tabWs[index] = area.width as number;
                if (index === this.profTab) {
                  this.moveProfileTabIndicator(index);
                  this.ensureProfileTabVisible(index);
                }
              })
              .onClick((): void => { this.selectProfileTab(index); });
            }, (tab: UserProfileTab) => tab.key);
          }
          .height(PROFILE_TAB_BAR_HEIGHT).padding({ left: 8, right: 8 });
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start).width('100%')
      .onAreaChange((_old: Area, area: Area): void => {
        this.tabViewW = area.width as number;
        this.ensureProfileTabVisible(this.profTab);
      });
    }
    .height(PROFILE_TAB_BAR_HEIGHT)
    .backgroundColor(this.profileGlassFill())
    .backgroundBlurStyle(this.profileGlassBlurStyle())
    .borderRadius(PROFILE_TAB_BAR_HEIGHT / 2)
    .border({ width: 0.7, color: $r('app.color.divider') })
    .shadow({ radius: this.profileGlassShadowRadius(), color: GLASS_SHADOW_COLOR,
      offsetX: 0, offsetY: this.profileGlassShadowY() })
    .attributeModifier(materialModifierWhen('card', this.profileEffectsReady))
    .clip(true)
    .margin({ left: 8, right: 8, top: 14, bottom: 8 });
  }

  @Builder
  emptyHint(text: string) {
    Text(text).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').textAlign(TextAlign.Center)
      .padding({ top: 30, bottom: 30 });
  }

  @Builder
  storiesGrid() {
    if (this.stories.length === 0) {
      this.emptyHint(str('mp_no_stories'));
    } else {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.stories, (it: StoryItem) => {
          Stack({ alignContent: Alignment.BottomStart }) {
            if (it.thumbPath !== '') {
              Image(it.thumbPath.startsWith('/') ? `file://${it.thumbPath}` : it.thumbPath).draggable(false)
                .width(this.storyCell()).height(this.storyCell() * 1.33).objectFit(ImageFit.Cover);
            } else {
              Column().width(this.storyCell()).height(this.storyCell() * 1.33).backgroundColor('#D8D8D8');
            }
            if (it.isVideo) {
              Text(`▶ ${this.formatDuration(it.duration)}`)
                .fontSize(11).fontColor(Color.White)
                .backgroundColor('#00000066').borderRadius(4)
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .margin({ left: 6, bottom: 6 });
            }
          }
          .width(this.storyCell()).height(this.storyCell() * 1.33)
          .margin({ right: 1, bottom: 1 });
        }, (it: StoryItem) => `story_${it.id}_${it.thumbPath}`);
      }.width('100%');
    }
  }

  // 收到的礼物：原来是 Flex 折行 + ForEach，一次建全部格子；现在按三格一行走 LazyForEach。
  @Builder
  giftsItems() {
    if (this.gifts.length === 0) {
      ListItem() {
        this.emptyHint(str('pp_no_gifts'));
      }
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent): void => {
            this.handleProfileTabPan(event.offsetX);
          })
      )
    } else {
      ListItemGroup() {
        LazyForEach(this.giftRowsData, (row: GiftItem[], index: number) => {
          ListItem() {
            ProfileGiftRow({ gifts: row, cellSize: this.storyCell() });
          }
        }, (row: GiftItem[], index: number): string =>
          guardKey(this.giftRowsData.keyTableId, index, this.giftRowKey(row, index)));
      }
      .width('100%')
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent): void => {
            this.handleProfileTabPan(event.offsetX);
          })
      );
    }
  }

  // 共同群组：玻璃卡（ListItemGroup）+ LazyForEach + 复用行 CommonGroupRow。分隔线交给 group 的
  // divider（原来按 index > 0 在行前插 Divider）。
  @Builder
  groupsItems() {
    if (this.groups.length === 0) {
      ListItem() {
        Column() {
          this.emptyHint(str('pp_no_common_groups'));
        }
        .margin({ left: 12, right: 12 });
      }
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent): void => {
            this.handleProfileTabPan(event.offsetX);
          })
      )
    } else {
      ListItemGroup() {
        LazyForEach(this.groupsData, (g: CommonGroup) => {
          ListItem() {
            CommonGroupRow({ group: g });
          }
          .onClick(() => { this.openChat(g.id); });
        }, (g: CommonGroup, index: number): string =>
          guardKey(this.groupsData.keyTableId, index, `${g.id}_${g.title}_${g.avatarPath}`));
      }
      .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 68 })
      .width('calc(100% - 24vp)')
      .margin({ left: 12, right: 12 })
      .glassCard()
      .padding({ top: 4, bottom: 4 })
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent): void => {
            this.handleProfileTabPan(event.offsetX);
          })
      );
    }
  }

  private sharedMediaCell(): number {
    // 按量到的内容宽算，不是按窗口宽——描边不算在父容器内容区里，按
    // screenW 算出来的三格会比内容区宽 1.4vp，第三格永远掉行。见 util/mediaGrid。
    return mediaGridCellSize(this.sharedRowW > 0
      ? this.sharedRowW : mediaFallbackContentWidth(this.screenW));
  }

  private sharedContentIcon(item: ProfileContentItem): string {
    if (item.contentType === 'messageDocument') {
      return 'sys.symbol.doc_text';
    }
    if (item.contentType === 'messageAudio') {
      return 'sys.symbol.play_fill';
    }
    if (item.contentType === 'messageVoiceNote') {
      return 'sys.symbol.mic';
    }
    if (item.contentType === 'messagePoll') {
      return 'sys.symbol.checkmark_circle';
    }
    if (item.contentType === 'messageAnimation' || item.contentType === 'messageVideoNote') {
      return 'sys.symbol.video';
    }
    if (this.currentProfileTabKey() === PROFILE_TAB_LINKS) {
      return 'sys.symbol.link';
    }
    return 'sys.symbol.message';
  }

  @Builder
  sharedPlaceholder() {
    Column({ space: 10 }) {
      if (this.sharedState === 'loading' || this.sharedState === 'idle') {
        LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        Text($r('app.string.pp_loading_shared')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.sharedState === 'error') {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28).fontColor([COLOR_ICON_SECONDARY]);
        Text(this.sharedErrorText !== '' ? this.sharedErrorText : $r('app.string.load_failed'))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        Text($r('app.string.settings_retry')).fontSize(14).fontColor(COLOR_PRIMARY)
          .height(34).padding({ left: 16, right: 16 }).textAlign(TextAlign.Center)
          .backgroundColor('#123390EC').borderRadius(17)
          .onClick((): void => {
            if (this.sharedStore !== null) {
              this.sharedStore.retryContent();
            }
          });
      } else {
        SymbolGlyph($r('sys.symbol.message')).fontSize(27).fontColor([COLOR_ICON_SECONDARY]);
        Text($r('app.string.pp_no_shared')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('calc(100% - 24vp)').height(178)
    .margin({ left: 12, right: 12, bottom: 18 })
    .padding({ left: 24, right: 24 }).justifyContent(FlexAlign.Center)
    .glassCard();
  }

  // 共享媒体网格：玻璃卡（ListItemGroup），按三格一行走 LazyForEach（ProfileMediaRow，与群资料页
  // 共用）。格子边长按行的实际宽算（onSizeChange 量行宽，理由见 util/mediaGrid）。
  @Builder
  sharedMediaItems() {
    ListItemGroup() {
      LazyForEach(this.sharedRowsData, (row: ProfileContentItem[], index: number) => {
        ListItem() {
          ProfileMediaRow({
            items: row,
            cellSize: this.sharedMediaCell(),
            pressedOpacity: 0.62,
            onOpen: (messageId: number): void => { this.openSharedMessage(messageId); }
          });
        }
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
          this.noteSharedRowWidth(Number(size.width));
        });
      }, (row: ProfileContentItem[], index: number): string =>
        guardKey(this.sharedRowsData.keyTableId, index, this.sharedRowKey(row, index)));
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12 })
    .glassCard().clip(true)
    .priorityGesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
        .onActionEnd((event: GestureEvent): void => {
          this.handleProfileTabPan(event.offsetX);
        })
    );
    ListItem() {
      this.sharedPaginationFooter();
    }
    .priorityGesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
        .onActionEnd((event: GestureEvent): void => {
          this.handleProfileTabPan(event.offsetX);
        })
    )
  }

  // 共享内容列表：玻璃卡（ListItemGroup）+ LazyForEach（ProfileContentRow，与群资料页共用；
  // 这一页没有就地下载按钮）。
  @Builder
  sharedContentItems() {
    ListItemGroup() {
      LazyForEach(this.sharedData, (item: ProfileContentItem, index: number) => {
        ListItem() {
          ProfileContentRow({
            item: item,
            icon: this.sharedContentIcon(item),
            fileActions: false,
            onOpen: (messageId: number): void => { this.openSharedMessage(messageId); }
          });
        }
      }, (item: ProfileContentItem, index: number): string =>
        guardKey(this.sharedData.keyTableId, index, profileContentKey(item)));
    }
    .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 69 })
    .width('calc(100% - 24vp)').margin({ left: 12, right: 12 })
    .glassCard().clip(true)
    .priorityGesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
        .onActionEnd((event: GestureEvent): void => {
          this.handleProfileTabPan(event.offsetX);
        })
    );
    ListItem() {
      this.sharedPaginationFooter();
    }
    .priorityGesture(
      PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
        .onActionEnd((event: GestureEvent): void => {
          this.handleProfileTabPan(event.offsetX);
        })
    )
  }

  @Builder
  sharedPaginationFooter() {
    Row({ space: 8 }) {
      if (this.sharedPaging) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        Text($r('app.string.cpp_loading_more')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.sharedPagingError) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(16).fontColor([COLOR_PRIMARY]);
        Text($r('app.string.load_failed_tap')).fontSize(13).fontColor(COLOR_PRIMARY);
      } else if (!this.sharedHasMore && this.sharedItems.length > 0) {
        Text($r('app.string.cpp_end_of_list')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('100%').height(this.sharedItems.length > 0 ? 52 : 0)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (this.sharedPagingError && this.sharedStore !== null) {
        this.sharedStore.loadMoreContent();
      }
    });
  }

  // 页签内容，全部是 List 的直接子项。左右滑切页签的手势挂在这些项上，不挂整个 List——
  // 那会抢走页签条自己的横向滚动。
  @Builder
  profileTabItems() {
    if (this.currentProfileTabKey() === PROFILE_TAB_STORIES) {
      // 动态一般不多，整块留在一项里。
      ListItem() {
        this.storiesGrid();
      }
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent): void => {
            this.handleProfileTabPan(event.offsetX);
          })
      )
    } else if (this.currentProfileTabKey() === PROFILE_TAB_RECEIVED_GIFTS) {
      this.giftsItems();
    } else if (this.currentProfileTabKey() === PROFILE_TAB_GROUPS) {
      this.groupsItems();
    } else if (this.sharedState === 'loading' || this.sharedState === 'idle' ||
      this.sharedState === 'error' || this.sharedItems.length === 0) {
      ListItem() {
        this.sharedPlaceholder();
      }
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionEnd((event: GestureEvent): void => {
            this.handleProfileTabPan(event.offsetX);
          })
      )
    } else if (this.currentProfileTabKey() === PROFILE_TAB_MEDIA) {
      this.sharedMediaItems();
    } else {
      this.sharedContentItems();
    }
  }

  // Bottom sheet with the sendable gift catalog (paid with Telegram Stars).
  @Builder
  giftPicker() {
    Column() {
      // Dim area above the sheet — tap to dismiss.
      Column().width('100%').layoutWeight(1)
        .onClick(() => { this.showGiftPicker = false; });
      Column({ space: 10 }) {
        Text($r('app.string.pp_send_gift')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.pp_pay_with_stars')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.availGifts, (g: AvailGift) => {
              Column({ space: 4 }) {
                if (g.stickerPath !== '') {
                  Image(g.stickerPath.startsWith('/') ? `file://${g.stickerPath}` : g.stickerPath).draggable(false)
                    .width(56).height(56).objectFit(ImageFit.Contain);
                } else {
                  Text('🎁').fontSize(40).width(56).height(56).textAlign(TextAlign.Center);
                }
                Text(`⭐ ${g.stars}`).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
              }
              .width((this.screenW - 48) / 4)
              .padding({ top: 8, bottom: 8 })
              .onClick(() => { this.sendGift(g); });
            }, (g: AvailGift) => `avail_${g.id}_${g.stickerPath}`);
          }.width('100%');
        }.constraintSize({ maxHeight: 360 }).scrollBar(BarState.Off);
        if (this.availGifts.length === 0) {
          Text($r('app.string.pp_loading_gifts')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).padding(16);
        }
      }
      .width('100%').padding({ left: 12, right: 12, top: 14, bottom: 24 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius({ topLeft: 18, topRight: 18 });
    }
    .width('100%').height('100%')
    .backgroundColor('#00000066');
  }

  // Premium emoji status beside the name (animated custom emoji).
  @Builder
  statusEmoji() {
    if (this.statusEmojiFormat === 'tgs') {
      TgsStickerView({
        tgsPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24, powerCategory: 'emojiStatus'
      });
    } else if (this.statusEmojiFormat === 'webm') {
      WebmStickerView({
        webmPath: this.statusEmojiPath, boxWidth: 24, boxHeight: 24, powerCategory: 'emojiStatus'
      });
    } else {
      Image(`file://${this.statusEmojiPath}`).draggable(false).width(24).height(24).objectFit(ImageFit.Contain);
    }
  }

  @Builder
  profileTransitionShell() {
    Column({ space: 10 }) {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.surface'))
        .onClick((): void => { this.goBack(); });
        Blank().layoutWeight(1);
        Row() {
          SymbolGlyph($r('sys.symbol.more')).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.surface'));
      }
      .width('100%').padding({ left: GLASS_PAGE_PAD, right: GLASS_PAGE_PAD });
      Circle({ width: 116, height: 116 }).fill($r('app.color.surface_alt'));
      Rect({ width: 132, height: 20, radius: 10 }).fill($r('app.color.surface_alt'));
      Rect({ width: 86, height: 12, radius: 6 }).fill($r('app.color.surface_alt'));
      Row({ space: 8 }) {
        ForEach(PROFILE_TRANSITION_ACTIONS, (index: number): void => {
          Rect({ width: (this.screenW - 64) / 5, height: 72, radius: GLASS_RADIUS_TILE })
            .fill($r('app.color.surface'));
        }, (index: number): string => `${index}`);
      }
      .width('100%').padding({ left: 12, right: 12, top: 12 });
    }
    .width('100%')
    .padding({ top: this.topSafe + 8 });
  }

  build() {
    HdsNavDestination() {
    Stack() {
      // 壁纸在最底，其余内容画在它之上。分栏下 AppBackdrop 自己什么都不画
      // （见 util/localWallpaper.appWallpaperActive），与主界面同一条规则。
      AppBackdrop({ split: isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn) });
      // 整页是一个 List（原来是 Scroll > Column）：资料部分在第一项、页签条一项，页签内容按行放进
      // List——共同群组、礼物、共享内容/媒体都走 LazyForEach（见 profileTabItems）。
      List() {
        ListItem() {
          Column() {
            if (!this.profileContentReady) {
              this.profileTransitionShell();
            } else {
              this.header();
              this.actionsRow();
              if (this.personalChatId !== 0 && this.chTitle !== '') {
                this.channelCard();
              }
              this.infoCard();
              if (!this.isContact) {
                this.addContactCard();
              }
              this.secretChatCard();
            }
          }
          .width('100%');
        }
        if (this.profileContentReady && this.visibleProfileTabs().length > 0) {
          ListItem() {
            Column() {
              this.tabsBar();
            }
            .width('100%');
          }
          this.profileTabItems();
        }
      }
      .width('100%').height('100%')
      .cachedCount(PROFILE_LIST_CACHED_COUNT)
      .contentEndOffset(24)
      // 壁纸生效时整页底必须透明，否则壁纸被这一层盖死（同 util/theme.mainPageFill 的理由）。
      // 卡片自己是毛玻璃（profileGlassFill），压在壁纸上仍然读得清。
      .backgroundColor(this.appWallpaperOn ? Color.Transparent : PAGE_BG)
      .onReachEnd((): void => {
        if (this.isSharedProfileTab(this.currentProfileTabKey()) && this.sharedStore !== null) {
          this.sharedStore.loadMoreContent();
        }
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

      if (this.viewerAvatarPath !== '') {
        AvatarViewer({
          imagePath: this.viewerAvatarPath,
          originX: this.avatarTapX,
          originY: this.avatarTapY,
          onClose: (): void => { this.viewerAvatarPath = ''; }
        });
      }
      if (this.showGiftPicker) {
        this.giftPicker();
      }
    }.width('100%').height('100%');
    }
    // 本页自绘标题栏（头图上那一行返回/更多），不要 HDS 的。
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
      this.navParams = ctx.pathInfo.param as Record<string, Object> | undefined;
      // 必须在这里调而不是等 aboutToAppear：实测 onReady 晚于 aboutToAppear。
      this.applyRouteParams();
    })
    .onShown((): void => { this.handleShown(); })
    .onWillHide((): void => { this.handleWillHide(); })
    .width('100%').height('100%');
  }
}

// 共同群组的一行（原 groupsList 里 ForEach 的行）。复用组件；点击在页面的 ListItem 上。
@Reusable
@Component
struct CommonGroupRow {
  @Prop group: CommonGroup;

  build() {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: this.group.avatarPath, initials: this.group.initials,
        colorSeed: this.group.id, avatarSize: 42
      });
      Text(this.group.title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
    }
    .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 });
  }
}

// 收到的礼物网格的一行（三格）。复用组件。
@Reusable
@Component
struct ProfileGiftRow {
  @Prop gifts: GiftItem[] = [];
  @Prop cellSize: number = 100;

  build() {
    Row() {
      ForEach(this.gifts, (g: GiftItem) => {
        if (g.stickerPath !== '') {
          Image(g.stickerPath.startsWith('/') ? `file://${g.stickerPath}` : g.stickerPath).draggable(false)
            .width(this.cellSize).height(this.cellSize).objectFit(ImageFit.Contain)
            .padding(10);
        } else {
          // 没有位图缩略图的动态贴纸（TGS/WEBM）Image 画不出来，给一个礼物符号而不是空格子。
          Text('🎁').fontSize(40)
            .width(this.cellSize).height(this.cellSize)
            .textAlign(TextAlign.Center);
        }
      }, (g: GiftItem): string => `gift_${g.id}_${g.stickerPath}`);
    }
    .width('100%')
    .justifyContent(FlexAlign.Start);
  }
}
