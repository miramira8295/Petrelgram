import { router, promptAction } from '@kit.ArkUI';
import { getTdClient, getCallSession } from '../../tdkit/Globals';
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
import { materialModifier } from '../../util/materialModifier';
import { AvatarView } from '../chatlist/AvatarView';
import { QrDialog } from '../common/QrDialog';
import { AvatarViewer } from '../common/AvatarViewer';
import { TgsStickerView } from '../chat/TgsStickerView';
import { WebmStickerView } from '../chat/WebmStickerView';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY,
  COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_TAB_PILL_BG
} from '../../util/theme';
import { ExpandableText } from './ExpandableText';
import { openUrl } from '../../util/openUrl';
import { common } from '@kit.AbilityKit';
import { publicLink } from '../../util/telegramLink';
import { MUTE_LONG, setMute } from '../../store/ChatActions';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { logE } from '../../util/log';
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
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State profTab: number = 0;
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
  @State groups: CommonGroup[] = [];
  @State stories: StoryItem[] = [];
  @State gifts: GiftItem[] = [];
  @State sharedTabKeys: string[] = [];
  @State sharedTabsState: string = 'loading';
  @State sharedItems: ProfileContentItem[] = [];
  @State sharedState: string = 'idle';
  @State sharedErrorText: string = '';
  @State sharedHasMore: boolean = false;
  @State sharedPaging: boolean = false;
  @State sharedPagingError: boolean = false;
  @State tabIndicatorX: number = 8;
  @State tabIndicatorW: number = 0;
  @State availGifts: AvailGift[] = [];
  @State showGiftPicker: boolean = false;
  private userId: number = 0;
  private privateChatId: number = 0;
  private pendingDraftText: string = '';
  private pendingStartParam: string = '';
  private pendingJumpTo: number = 0;
  private store: ProfileStore | null = null;
  private unsub: (() => void) | null = null;
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
    const store = new ProfileStore(getTdClient(), this.userId);
    this.store = store;
    this.unsub = store.subscribe(() => { this.refresh(); });
    store.open();
  }

  // 返回上一层。迁成 NavDestination 前这里是 router.back()。
  private goBack(): void {
    const stack = this.navStack;
    if (stack !== undefined) {
      stack.pop();
      return;
    }
    router.back();
  }

  aboutToDisappear(): void {
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
    const found = preferredKey !== ''
      ? tabs.findIndex((tab: UserProfileTab): boolean => tab.key === preferredKey) : -1;
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
    navigateToChat(params).catch(logChatNavFailure);
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
      navigateToChat(params).catch(logChatNavFailure);
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

  // 和群组简介页同一套玻璃面，见 ProfileGlass。两页必须看起来是同一个页面。
  @Styles
  glassCard() {
    .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
    .backdropBlur(overlayBackdropBlur('card'))
    .borderRadius(GLASS_RADIUS_CARD)
    .border({ width: 0.7, color: $r('app.color.divider') })
    .shadow({ radius: GLASS_SHADOW_RADIUS, color: GLASS_SHADOW_COLOR, offsetX: 0, offsetY: GLASS_SHADOW_Y })
    .attributeModifier(materialModifier('card'))
  }

  @Styles
  glassTile() {
    .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
    .backdropBlur(overlayBackdropBlur('card'))
    .borderRadius(GLASS_RADIUS_TILE)
    .border({ width: 0.7, color: $r('app.color.divider') })
    .shadow({ radius: GLASS_SHADOW_RADIUS, color: GLASS_SHADOW_COLOR, offsetX: 0, offsetY: GLASS_SHADOW_Y })
    .attributeModifier(materialModifier('card'))
  }

  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Row() {
      SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
    }
    .width(44).height(44).borderRadius(22)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
    .backdropBlur(overlayBackdropBlur('card'))
    .border({ width: 0.7, color: $r('app.color.divider') })
    .shadow({ radius: GLASS_SHADOW_RADIUS, color: GLASS_SHADOW_COLOR, offsetX: 0, offsetY: GLASS_SHADOW_Y })
    .attributeModifier(materialModifier('card'))
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
        this.circleButton('sys.symbol.more', () => {});
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
      .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
      .backdropBlur(overlayBackdropBlur('card'))
      .border({ width: 0.7, color: $r('app.color.divider') })
      .shadow({ radius: GLASS_SHADOW_RADIUS, color: GLASS_SHADOW_COLOR, offsetX: 0, offsetY: GLASS_SHADOW_Y })
      .attributeModifier(materialModifier('card'))
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
            SymbolGlyph($r('sys.symbol.qrcode')).fontSize(22).fontColor([COLOR_TEXT_SECONDARY])
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
      navigateToChat(params).catch(logChatNavFailure);
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
    .backgroundColor(overlayGlassFill('card', $r('app.color.surface')))
    .backdropBlur(overlayBackdropBlur('card'))
    .borderRadius(PROFILE_TAB_BAR_HEIGHT / 2)
    .border({ width: 0.7, color: $r('app.color.divider') })
    .shadow({ radius: GLASS_SHADOW_RADIUS, color: GLASS_SHADOW_COLOR, offsetX: 0, offsetY: GLASS_SHADOW_Y })
    .attributeModifier(materialModifier('card'))
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

  @Builder
  giftsGrid() {
    if (this.gifts.length === 0) {
      this.emptyHint(str('pp_no_gifts'));
    } else {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.gifts, (g: GiftItem) => {
          if (g.stickerPath !== '') {
            Image(g.stickerPath.startsWith('/') ? `file://${g.stickerPath}` : g.stickerPath).draggable(false)
              .width(this.storyCell()).height(this.storyCell()).objectFit(ImageFit.Contain)
              .padding(10);
          } else {
            // Animated (TGS/WEBM) stickers without a raster thumbnail can't be
            // rendered by Image — show a gift glyph instead of a blank cell.
            Text('🎁').fontSize(40)
              .width(this.storyCell()).height(this.storyCell())
              .textAlign(TextAlign.Center);
          }
        }, (g: GiftItem) => `gift_${g.id}_${g.stickerPath}`);
      }.width('100%');
    }
  }

  @Builder
  groupsList() {
    Column() {
      if (this.groups.length === 0) {
        this.emptyHint(str('pp_no_common_groups'));
      } else {
        Column() {
          ForEach(this.groups, (g: CommonGroup, index: number) => {
            if (index > 0) {
              // Row separator, indented past the avatar (Telegram-style).
              Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 68 });
            }
            Row({ space: 12 }) {
              AvatarView({ avatarPath: g.avatarPath, initials: g.initials, colorSeed: g.id, avatarSize: 42 });
              Text(g.title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
            }
            .width('100%').padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .onClick(() => { this.openChat(g.id); });
          }, (g: CommonGroup) => `grp_${g.id}_${g.avatarPath}`);
        }
        .width('100%').glassCard()
        .padding({ top: 4, bottom: 4 });
      }
    }
    .margin({ left: 12, right: 12 });
  }

  private sharedMediaCell(): number {
    return Math.max(92, (this.screenW - 30) / 3);
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
          .fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
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
        SymbolGlyph($r('sys.symbol.message')).fontSize(27).fontColor([COLOR_TEXT_SECONDARY]);
        Text($r('app.string.pp_no_shared')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('calc(100% - 24vp)').height(178)
    .margin({ left: 12, right: 12, bottom: 18 })
    .padding({ left: 24, right: 24 }).justifyContent(FlexAlign.Center)
    .glassCard();
  }

  @Builder
  sharedMediaGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
      ForEach(this.sharedItems, (item: ProfileContentItem) => {
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (item.thumbPath !== '') {
            Image(`file://${item.thumbPath}`).draggable(false).width('100%').height('100%')
              .objectFit(ImageFit.Cover);
          } else {
            Column() {
              SymbolGlyph($r(item.isVideo ? 'sys.symbol.video_fill' : 'sys.symbol.photo_fill'))
                .fontSize(26).fontColor([COLOR_TEXT_SECONDARY]);
            }
            .width('100%').height('100%').justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.surface_alt'));
          }
          if (item.isVideo) {
            Row({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.play_fill')).fontSize(10).fontColor([Color.White]);
              if (item.duration !== '') {
                Text(item.duration).fontSize(11).fontColor(Color.White);
              }
            }
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .margin({ right: 5, bottom: 5 })
            .backgroundColor('#70000000').borderRadius(8);
          }
        }
        .width(this.sharedMediaCell()).height(this.sharedMediaCell())
        .margin({ right: 2, bottom: 2 })
        .stateStyles({ normal: this.tabNormalStyle, pressed: this.tabPressedStyle })
        .onClick((): void => { this.openSharedMessage(item.messageId); });
      }, (item: ProfileContentItem) => `${item.messageId}_${item.thumbPath}`);
    }
    .width('calc(100% - 24vp)')
    .margin({ left: 12, right: 12 })
    .glassCard().clip(true);
    this.sharedPaginationFooter();
  }

  @Builder
  sharedContentList() {
    Column() {
      ForEach(this.sharedItems, (item: ProfileContentItem, index: number) => {
        Column() {
          Row({ space: 11 }) {
            Stack() {
              if (item.thumbPath !== '') {
                Image(`file://${item.thumbPath}`).draggable(false).width(46).height(46)
                  .objectFit(ImageFit.Cover).borderRadius(10);
              } else {
                SymbolGlyph($r(this.sharedContentIcon(item)))
                  .fontSize(22).fontColor([COLOR_PRIMARY]);
              }
            }
            .width(46).height(46).borderRadius(10)
            .backgroundColor($r('app.color.surface_alt'));
            Column({ space: 3 }) {
              Text(item.title).fontSize(15).fontWeight(FontWeight.Medium)
                .fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
              if (item.preview !== '') {
                Text(item.preview).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              }
              if (item.meta !== '') {
                Text(item.meta).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              }
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(13).fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width('100%').constraintSize({ minHeight: 64 })
          .padding({ left: 12, right: 10, top: 9, bottom: 9 })
          .stateStyles({ normal: this.sharedRowNormalStyle, pressed: this.sharedRowPressedStyle })
          .onClick((): void => { this.openSharedMessage(item.messageId); });
          if (index < this.sharedItems.length - 1) {
            Divider().color($r('app.color.divider')).strokeWidth(0.7).margin({ left: 69 });
          }
        }.width('100%');
      }, (item: ProfileContentItem) => `${item.messageId}_${item.thumbPath}`);
    }
    .width('calc(100% - 24vp)').margin({ left: 12, right: 12 })
    .glassCard().clip(true);
    this.sharedPaginationFooter();
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

  @Builder
  profileTabContent() {
    if (this.currentProfileTabKey() === PROFILE_TAB_STORIES) {
      this.storiesGrid();
    } else if (this.currentProfileTabKey() === PROFILE_TAB_RECEIVED_GIFTS) {
      this.giftsGrid();
    } else if (this.currentProfileTabKey() === PROFILE_TAB_GROUPS) {
      this.groupsList();
    } else if (this.sharedState === 'loading' || this.sharedState === 'idle' ||
      this.sharedState === 'error' || this.sharedItems.length === 0) {
      this.sharedPlaceholder();
    } else if (this.currentProfileTabKey() === PROFILE_TAB_MEDIA) {
      this.sharedMediaGrid();
    } else {
      this.sharedContentList();
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

  build() {
    HdsNavDestination() {
    Stack() {
      Scroll() {
        Column() {
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
          if (this.visibleProfileTabs().length > 0) {
            Column() {
              this.tabsBar();
              Column() {
                this.profileTabContent();
              }
              .width('100%')
              .priorityGesture(
                PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
                  .onActionEnd((event: GestureEvent): void => {
                    this.handleProfileTabPan(event.offsetX);
                  })
              );
            }
            .width('100%');
          }
        }
        .width('100%')
        .padding({ bottom: 24 })
      }
      .width('100%').height('100%')
      .backgroundColor(PAGE_BG)
      .align(Alignment.Top)
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
    .width('100%').height('100%');
  }
}
