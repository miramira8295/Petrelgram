import { showToast } from '../../util/toast';
import { avatarInitialOf } from '../../util/avatarInitial';
import { collapseFloatingVideo } from '../../util/floatingVideoRuntime';
import { QrDialog } from '../common/QrDialog';
import { edgeBlurRadiusWhileMorphing } from '../../util/scrollEdgeBlur';
import { ScrollEdgeBlurBinder } from '../../util/scrollEdgeBlurModifier';
import {
  EDGE_BLUR_BOTTOM_ON_DEFAULT, EDGE_BLUR_FOLLOW, EDGE_BLUR_ON_DEFAULT, EDGE_BLUR_TOP_ON_DEFAULT,
  KEY_EDGE_BLUR_BOTTOM_ON, KEY_EDGE_BLUR_ON, KEY_EDGE_BLUR_OTHER_BOTTOM, KEY_EDGE_BLUR_OTHER_TOP,
  KEY_EDGE_BLUR_TOP_ON, edgeBlurOtherBottomOn, edgeBlurOtherTopOn
} from '../../util/edgeBlurSetting';
import { TelegramQrScanner } from '../../services/TelegramQrScanner';
import { InviteJoinResolver } from '../../util/inviteJoinResolver';
import { joinChat as submitChatJoin, ChatJoinOutcome } from '../../util/chatJoin';
import { pageMarginVp } from '../../util/pageMargin';
import {
  AVATAR_PROFILE_BASE, AVATAR_PROFILE_RING, AVATAR_TOP_LIFT, AVATAR_EXPAND_AT, AVATAR_COLLAPSE_AT, AVATAR_SNAP_MS,
  AVATAR_TEXT_INSET, AVATAR_TEXT_BOTTOM, AVATAR_TEXT_H, AVATAR_HEAD_ROW, AVATAR_HEAD_GAP,
  AVATAR_BUTTON_INSET, AVATAR_CARD_RADIUS,
  canExpandAvatar, avatarUsesCardLayout, avatarRatioOf, avatarWidthOf, avatarHeightOf,
  avatarRadiusOf, avatarRingOf, avatarOffsetYOf, avatarDecodeWidthOf, avatarDecodeHeightOf
} from '../../util/avatarMorph';
import {
  HEIGHT_BP_LG, KEY_HEIGHT_BREAKPOINT, KEY_WINDOW_PORTRAIT, KEY_WIDTH_BREAKPOINT, WIDTH_BP_SM, WIDTH_BP_MD, isSplitByBreakpoint
} from '../../util/layoutBreakpoint';
import { ReportTarget, runReportFlow } from '../../util/reportFlow';
import { reportFlowUiFor } from '../common/ReportPrompts';
import { PromptAction, router, promptAction, curves, RectShape } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { banMember, deleteMessagesFromSender, removeMember, setMemberTag } from '../../store/ChatAdminApi';
import {
  MEMBER_ACTION_BAN, MEMBER_ACTION_DELETE_MESSAGES, MEMBER_ACTION_PROMOTE,
  MEMBER_ACTION_REMOVE, MEMBER_ACTION_RESTRICT, MemberMenuOptions,
  memberMenuOptions, memberMenuSignature, MEMBER_ACTION_TITLE
} from '../../util/memberMenu';
import { MemberRow } from './MemberRow';
import { ProfileMediaRow } from './ProfileMediaRow';
import { ProfileContentRow, profileContentKey } from './ProfileContentRow';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { guardKey } from '../../util/keyGuard';
import { chunkRows } from '../../util/gridRows';
import {
  MEDIA_KINDS, MEDIA_KIND_ALL, MEDIA_KIND_PHOTO, MEDIA_KIND_VIDEO
} from '../../util/mediaKindFilter';
import { MemberTitleDialog } from './MemberTitleDialog';
import { getTdClient } from '../../tdkit/Globals';
import {
  ChatProfileStore, MemberItem, ProfileContentItem,
  PROFILE_TAB_MEMBERS, PROFILE_TAB_MEDIA, PROFILE_TAB_FILES, PROFILE_TAB_LINKS,
  PROFILE_TAB_MUSIC, PROFILE_TAB_POLLS, PROFILE_TAB_VOICE,
  PROFILE_TAB_VIDEO_NOTES, PROFILE_TAB_GIFS, PROFILE_TAB_GIFTS
} from '../../store/ChatProfileStore';
import {
  GLASS_GAP, GLASS_RADIUS_CARD, GLASS_RADIUS_CHIP,
  GLASS_RADIUS_TILE
} from './ProfileGlass';
import {
  overlayBackdropBlur, overlayGlassFill, MATERIAL_EPOCH
} from '../../util/overlayMaterial';
import {
  KEY_SURFACE_GLASS_ON, SURFACE_GLASS_EPOCH, SURFACE_GLASS_ON_DEFAULT,
  surfaceGlassFill
} from '../../util/surfaceGlass';
import { AvatarView } from '../chatlist/AvatarView';
import { NativeGlassHost } from '../chat/NativeGlassHost';
import { AvatarViewer } from '../common/AvatarViewer';
import { getMessageFilterStore, MESSAGE_FILTER_EPOCH } from '../../store/MessageFilterStore';
import { MessageFilterRouteParam } from '../main/MessageFilterPage';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY,
  COLOR_TAB_SELECTED, COLOR_TAB_UNSELECTED, COLOR_TAB_PILL_BG, KEY_APP_DARK
} from '../../util/theme';
import { ExpandableText } from './ExpandableText';
import {
  createVideoChat, endGroupCall, getGroupCall, startScheduledVideoChat
} from '../../tdkit/GroupCallApi';
import {
  KEY_APP_BG_ON, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration, KEY_FORCE_SINGLE_COLUMN
} from '../../store/AppSettings';
import { AppBackdrop } from '../common/AppBackdrop';
import { MUTE_LONG, leaveChatFully, setMute } from '../../store/ChatActions';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { CHAT_DEST_NAME, logChatNavFailure, navigateToChat } from '../../util/chatNav';
import { profileSitsOnOwnChat } from '../../util/splitRouting';
import { logE, logI } from '../../util/log';
import { common } from '@kit.AbilityKit';
import { openLocalFile } from '../../util/openLocalFile';
import { fileOpenMimeType } from '../../util/fileMessage';
import { navigateToProfile } from '../../util/profileNav';
import { allocChatDestToken, markChatDestHidden, markChatDestShown } from '../../util/chatDestTracker';
import { MEDIA_GRID_COLS, mediaCellSize as mediaGridCellSize, mediaFallbackContentWidth } from '../../util/mediaGrid';
import { HdsNavDestination } from '@kit.UIDesignKit';

// 等上下文菜单收起再弹确认框。菜单是独立子窗口，收起过程中弹出的
// 对话框会挂死（Promise 既不 resolve 也不 reject）。同 ChatRow。
const MENU_DISMISS_MS: number = 150;

const CARD_BG: ResourceColor = $r('app.color.surface');
const CARD_RADIUS: number = 14;
const DETAIL_TAB_BAR_HEIGHT: number = 44;
const DETAIL_TAB_INDICATOR_HEIGHT: number = 32;
// 输入到真正下发搜索之间的防抖窗口。
const CONTENT_QUERY_DEBOUNCE_MS: number = 250;
// 资料页 List 在可视区外多备的行数（成员行、文件行、媒体行都不贵）。
const PROFILE_LIST_CACHED_COUNT: number = 4;
// HdsNavDestination 的 onShown() 实测在推页动画中段（~270ms）即触发，而整段弹簧推页
// 持续约 590ms；等动画真正落地（600ms）后再卸载 renderGroup 并挂载下半屏页签/搜索框。
const TRANSITION_SETTLE_MS: number = 600;

interface ProfileTabItem {
  key: string;
  label: string;
}

const PROFILE_TABS: ProfileTabItem[] = [
  { key: PROFILE_TAB_MEMBERS, label: str('ng_members') },
  { key: PROFILE_TAB_MEDIA, label: str('cpp_media') },
  { key: PROFILE_TAB_FILES, label: str('storage_file') },
  { key: PROFILE_TAB_LINKS, label: str('cpp_links') },
  { key: PROFILE_TAB_MUSIC, label: str('storage_audio') },
  { key: PROFILE_TAB_POLLS, label: str('poll_word') },
  { key: PROFILE_TAB_VOICE, label: str('storage_voice') },
  { key: PROFILE_TAB_VIDEO_NOTES, label: str('cp_video_message') },
  { key: PROFILE_TAB_GIFS, label: 'GIF' },
  { key: PROFILE_TAB_GIFTS, label: str('cpp_gifts') }
];

// Group / channel detail page — visually mirrors ProfilePage (header, action
// row, info card) with a member list instead of the personal tabs.
// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载
// 本模块并调用它，页面因此不再需要进 main_pages.json。
@Builder
export function ChatProfilePageBuilder(): void {
  ChatProfilePage();
}

@Component
export struct ChatProfilePage {
  @StorageProp(KEY_EDGE_BLUR_ON) private edgeBlurOn: boolean = EDGE_BLUR_ON_DEFAULT;
  @StorageProp(KEY_EDGE_BLUR_TOP_ON) private edgeBlurTopOn: boolean = EDGE_BLUR_TOP_ON_DEFAULT;
  @StorageProp(KEY_EDGE_BLUR_BOTTOM_ON) private edgeBlurBottomOn: boolean = EDGE_BLUR_BOTTOM_ON_DEFAULT;
  @StorageProp(KEY_EDGE_BLUR_OTHER_TOP) private edgeBlurOtherTop: string = EDGE_BLUR_FOLLOW;
  @StorageProp(KEY_EDGE_BLUR_OTHER_BOTTOM) private edgeBlurOtherBottom: string = EDGE_BLUR_FOLLOW;
  // 本页所在的 Navigation 栈，onReady 时拿到。返回按钮靠它出栈——本页已不是
  // router 页，this.getUIContext().getRouter().back() 弹不到自己。
  private navStack: NavPathStack | undefined = undefined;
  private readonly chatDestToken: number = allocChatDestToken();
  // 顶/底虚化四件套：半径由开关算，只有头像形变期间例外（见 edgeBlurRadiusWhileMorphing）。
  @State private listViewH: number = 0;
  private edgeBlur: ScrollEdgeBlurBinder = new ScrollEdgeBlurBinder();
  // 路由参数。router 时代靠 this.getUIContext().getRouter().getParams() 现取，NavDestination 要在
  // onReady 里从 NavDestinationContext 拿，而 onReady 实测晚于 aboutToAppear
  // （平板 API 26，见 ChatPage 的同名注释），所以吃参数的那一段整体挪进了
  // applyRouteParams()。
  private navParams: Record<string, Object> | undefined = undefined;
  // applyRouteParams() 的一次性守卫：那段里建了 ChatProfileStore 并订阅了它
  // （经 startStore()），重入会覆盖 this.store / this.unsub，旧订阅退不掉。
  private paramsApplied: boolean = false;
  // 推页转场是否已落地。过渡期间只画轻量上半屏并把整页缓存为 renderGroup，
  // 下半屏页签条/成员搜索框（原生 TextInput）和后台 store 刷新等 onShown() 落地后一次补齐。
  @State private transitionSettled: boolean = false;
  private hasPrefill: boolean = false;
  private pendingStoreRefresh: boolean = false;
  private transitionSettleTimer: number = -1;
  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(MESSAGE_FILTER_EPOCH) private filterEpoch: number = 0;
  // 整体玻璃开关与档位（联系人页同一套）。开关变一次所有读它的面都要重算。
  @StorageProp(KEY_SURFACE_GLASS_ON) private surfaceGlassOn: boolean = SURFACE_GLASS_ON_DEFAULT;
  @StorageProp(SURFACE_GLASS_EPOCH) private surfaceGlassEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 顶栏圆钮的系统材质要按深浅色换染色，不订阅它切主题后不会重绘。
  @StorageProp(KEY_APP_DARK) private appDark: boolean = false;
  // 设置里的「强制单栏」（宽屏也当手机用）。
  @StorageProp(KEY_FORCE_SINGLE_COLUMN) forceSingleColumn: boolean = false;
  @StorageProp('screenHeightVp') screenH: number = 780;
  // 系统断点（util/layoutBreakpoint）：分栏判据读它，不再按窗口宽高自己算。
  @StorageProp(KEY_WIDTH_BREAKPOINT) widthBp: number = WIDTH_BP_SM;
  @StorageProp(KEY_HEIGHT_BREAKPOINT) heightBp: number = HEIGHT_BP_LG;
  @StorageProp(KEY_WINDOW_PORTRAIT) windowPortrait: boolean = true;
  // APP 壁纸此刻生不生效。本页是压在主界面之上的 NavDestination，**下面那层壁纸
  // 透不过来**（HdsNavDestination 自带不透明底，Scroll 又铺了一层 page_bg），
  // 所以和 ChatPage 一样自己画一层——用户实报"点频道/群组/其他人详情看不到壁纸"。
  @StorageProp(KEY_APP_BG_ON) appWallpaperOn: boolean = false;
  @State title: string = '';
  @State initials: string = '?';
  @State avatarPath: string = '';
  // 头像点击放大（'' = 未打开）。
  @State viewerAvatarPath: string = '';
  @State avatarTapX: number = 0;
  @State avatarTapY: number = 0;
  @State avatarAnimPath: string = '';
  @State subtitle: string = '';
  @State description: string = '';
  @State chatUsername: string = '';
  @State @Watch('syncMembersData') isChannel: boolean = false;
  // 本页是不是直接叠在同一个会话的会话页上面（onReady 时定）。
  @State overOwnChat: boolean = false;
  @State isMuted: boolean = false;
  @State canManageVideoChats: boolean = false;
  @State canManageChat: boolean = false;
  @State canInviteMembers: boolean = false;
  // 逐项管理权限。长按菜单按这几项出条目，不用 canManageChat 一刀切。
  @State @Watch('syncMembersData') viewerIsCreator: boolean = false;
  @State @Watch('syncMembersData') canPromoteMembers: boolean = false;
  @State @Watch('syncMembersData') canManageTags: boolean = false;
  @State @Watch('syncMembersData') canRestrictMembers: boolean = false;
  @State @Watch('syncMembersData') canDeleteMessages: boolean = false;
  @State @Watch('syncMembersData') selfUserId: number = 0;
  @State liveGroupCallId: number = 0;
  @State creatingLive: boolean = false;
  @State @Watch('syncMembersData') members: MemberItem[] = [];
  @State membersState: string = 'loading';
  @State selectedTab: number = 0;
  private pendingTabKey: string = '';
  @State @Watch('syncContentData') contentItems: ProfileContentItem[] = [];
  // 媒体网格那张玻璃卡的内容宽，由 onAreaChange 量得；0 = 还没量到。
  @State private mediaRowW: number = 0;
  // 成员、共享内容、媒体网格行各自的 LazyForEach 数据源（见 syncMembersData / syncContentData）。
  private membersData: KeyedListDataSource<MemberItem> = new KeyedListDataSource<MemberItem>('profile-members');
  private contentData: KeyedListDataSource<ProfileContentItem> = new KeyedListDataSource<ProfileContentItem>('profile-content');
  private mediaRowsData: KeyedListDataSource<ProfileContentItem[]> =
    new KeyedListDataSource<ProfileContentItem[]>('profile-media-rows');
  @State contentState: string = 'idle';
  // 媒体页的「全部 / 图片 / 视频」子筛选（issue #214）。真源在 store 上，这里是
  // 渲染用的镜像，和 contentItems 一样由 syncFromStore 回灌。
  @State mediaKind: string = MEDIA_KIND_ALL;
  @State contentErrorText: string = '';
  @State contentHasMore: boolean = false;
  @State contentPaging: boolean = false;
  @State contentPagingError: boolean = false;
  @State contentTotalCount: number = 0;
  @State availableTabKeys: string[] = [];
  @State tabsState: string = 'loading';
  @State detailIndicatorX: number = 8;
  @State detailIndicatorW: number = 0;
  @State pageState: string = 'loading'; // loading | ready | error
  @State errorText: string = '';
  @State membershipState: string = 'checking';
  @State joinByRequest: boolean = false;
  @State joining: boolean = false;
  @State joinRequestSent: boolean = false;
  private chatId: number = 0;
  private inviteLink: string = '';
  private inviteNeedsApproval: boolean = false;
  private joinSeq: number = 0;
  private inviteJoinResolver: InviteJoinResolver | null = null;
  private pendingDraftText: string = '';
  private pendingJumpTo: number = 0;
  private justJoined: boolean = false;
  private pendingMemberReload: boolean = false;
  private store: ChatProfileStore | null = null;
  // 页签内搜索（issue #102）。输入框的字在本地，真正下发给 store 的动作防抖
  // 250ms——每敲一个字就重拉一页会把 searchChatMessages 打满，也会让列表闪。
  @State private contentQuery: string = '';
  private contentQueryTimer: number = -1;
  @State private memberQuery: string = '';
  private memberQueryTimer: number = -1;
  @State private tabSearchOpen: boolean = false;
  @State private tabsPinned: boolean = false;
  @State private pinnedHeaderH: number = DETAIL_TAB_BAR_HEIGHT;
  @State private pinnedIndicatorX: number = 8;
  @State private pinnedIndicatorW: number = 0;
  @State private tabSlideX: number = 0;
  @State private tabSlideOpacity: number = 1;
  private profileHeadH: number = 0;
  private pinLockUntil: number = 0;
  private tabScrollRestoreTimer: number = -1;
  private unsub: (() => void) | null = null;
  private tabScroller: Scroller = new Scroller();
  private pinnedTabScroller: Scroller = new Scroller();
  // 下拉放大头像：整页 List 的滚动器（越界值驱动形变）、形变进度与展开态。
  private pageScroller: Scroller = new Scroller();
  @State avatarPull: number = 0;
  @State avatarExpanded: boolean = false;
  @State avatarAvailW: number = 0;
  private avatarSnapAt: number = 0;
  private detailTabXs: number[] = [];
  private detailTabWs: number[] = [];
  private detailTabViewW: number = 0;
  private pinnedTabXs: number[] = [];
  private pinnedTabWs: number[] = [];
  private pinnedTabViewW: number = 0;

  @Styles
  tabNormalStyle() {
    .opacity(1)
  }

  @Styles
  tabPressedStyle() {
    .opacity(0.58)
  }

  @Styles
  // 行的常态必须透明：刷成 CARD_BG 会把底下整块卡片的玻璃盖住，列表看起来
  // 就是一块实心板。按压态用半透明高光，压在玻璃上仍然看得见。
  contentRowNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  contentRowPressedStyle() {
    .backgroundColor($r('app.color.press_overlay'))
  }

  // 迁移前 aboutToAppear 的**全部**内容都吃路由参数（chatId/inviteLink 决定
  // 走 startStore 还是 loadInvitePreview 还是 error 态），所以整段搬进了
  // applyRouteParams()，这里没有留下任何一行。保留空方法是为了让这条注释有
  // 地方待着：读代码的人会先来找 aboutToAppear。
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
    this.chatId = params !== undefined
      ? ((params['chatId'] as number | undefined) ?? 0) : 0;
    this.inviteLink = params !== undefined
      ? ((params['inviteLink'] as string | undefined) ?? '') : '';
    this.pendingDraftText = params !== undefined
      ? ((params['draftText'] as string | undefined) ?? '') : '';
    this.pendingJumpTo = params !== undefined
      ? ((params['jumpTo'] as number | undefined) ?? 0) : 0;
    // 首次进来要落到哪个页签（issue #166 的「显示所有图片」）。用一次即清，
    // 之后由用户自己切。
    this.pendingTabKey = params !== undefined
      ? ((params['tab'] as string | undefined) ?? '') : '';
    if (this.navStack !== undefined) {
      this.overOwnChat = this.computeOverOwnChat(this.navStack);
    }
    const prefillTitle: string = params !== undefined
      ? ((params['prefillTitle'] as string | undefined) ?? '') : '';
    if (this.chatId !== 0 && prefillTitle !== '') {
      this.hasPrefill = true;
      this.title = prefillTitle;
      const prefillInitials: string = (params?.['prefillInitials'] as string | undefined) ?? '';
      this.initials = prefillInitials !== '' ? prefillInitials : avatarInitialOf(prefillTitle);
      this.avatarPath = (params?.['prefillAvatarPath'] as string | undefined) ?? '';
      this.avatarAnimPath = (params?.['prefillAvatarAnimPath'] as string | undefined) ?? '';
      this.subtitle = (params?.['prefillSubtitle'] as string | undefined) ?? '';
      this.isChannel = (params?.['prefillIsChannel'] as boolean | undefined) ?? false;
      this.isMuted = (params?.['prefillIsMuted'] as boolean | undefined) ?? false;
      if (this.overOwnChat) {
        this.membershipState = 'writable';
      }
      this.pageState = 'ready';
    }
    this.armTransitionSettle();
    if (this.chatId !== 0) {
      this.startStore();
    } else if (this.inviteLink !== '') {
      this.loadInvitePreview();
    } else {
      this.pageState = 'error';
      this.errorText = str('cpp_link_no_chat');
    }
  }

  private armTransitionSettle(): void {
    if (this.transitionSettled) {
      return;
    }
    this.clearTransitionSettleTimer();
    const delayMs: number = isSplitByBreakpoint(
      this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait)
      ? 0 : powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, TRANSITION_SETTLE_MS);
    if (delayMs <= 0) {
      this.settleTransition();
      return;
    }
    this.transitionSettleTimer = setTimeout((): void => {
      this.transitionSettleTimer = -1;
      this.settleTransition();
    }, delayMs);
  }

  private clearTransitionSettleTimer(): void {
    if (this.transitionSettleTimer !== -1) {
      clearTimeout(this.transitionSettleTimer);
      this.transitionSettleTimer = -1;
    }
  }

  private settleTransition(): void {
    this.clearTransitionSettleTimer();
    if (this.transitionSettled) {
      return;
    }
    this.transitionSettled = true;
    if (this.pendingStoreRefresh) {
      this.pendingStoreRefresh = false;
      this.store?.flushPending();
      this.refresh();
    }
  }

  private sameStringList(a: string[], b: string[]): boolean {
    if (a === b) {
      return true;
    }
    if (a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false;
      }
    }
    return true;
  }

  // 返回上一层。**不能用 this.getUIContext().getRouter().back()**：本页是 HdsNavDestination，router 页栈里
  // 只剩 Index 一层，this.getUIContext().getRouter().back() 弹掉的是 Index——平板模拟器实测（Task 7 修复轮 1）
  // 的现象是「点返回箭头直接退到桌面」。要出的是 Navigation 栈。
  private goBack(): void {
    if (this.viewerAvatarPath !== '') { this.viewerAvatarPath = ''; return; }
    const stack = this.navStack;
    if (stack === undefined) {
      // navStack 由 onReady(ctx.pathStack) 填，而 onReady 必先于本页可见，所以
      // 这一支不该发生。这里**故意不回退到 this.getUIContext().getRouter().back()**：那正是会退出应用的
      // 那条路，把返回键做成"什么都不做 + 一条日志"远比把应用关掉好。
      logE('ChatProfilePage.goBack: navStack missing, back ignored');
      return;
    }
    // pop() 弹的就是本页这一层。栈空时它返回 undefined，但那意味着"本页正显示
    // 却不在栈里"，不可能发生，故不另做处理。
    stack.pop();
  }

  private startStore(): void {
    if (this.chatId === 0) {
      return;
    }
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
    if (this.store !== null) {
      this.store.close();
    }
    if (!this.hasPrefill) {
      this.pageState = 'loading';
    }
    const store = new ChatProfileStore(getTdClient(), this.chatId);
    this.store = store;
    this.unsub = store.subscribe(() => { this.refresh(); });
    store.open();
  }

  // 从提权/限制面板返回时重拉成员：身份标签和受限状态都可能变了。
  // 迁移前是 onPageShow，方法体一字未动，改由 HdsNavDestination.onShown() 触发。
  private handleShown(): void {
    if (!this.transitionSettled && this.transitionSettleTimer === -1) {
      this.armTransitionSettle();
    }
    markChatDestShown(this.chatDestToken);
    this.inviteJoinResolver?.refresh();
    if (this.pendingMemberReload) {
      this.pendingMemberReload = false;
      this.store?.reloadMembers();
    }
  }

  private qrOpen: boolean = false;
  private qrCtrl: CustomDialogController = new CustomDialogController({
    builder: QrDialog({ chatId: this.chatId, title: this.title,
      onScan: (): void => { this.qrScanner.start(this.getUIContext().getHostContext() as common.UIAbilityContext); },
      onClosed: (): void => { this.qrOpen = false; } }),
    customStyle: true,
    alignment: DialogAlignment.Center, autoCancel: true
  });

  private openQr(): void {
    if (this.qrOpen || this.chatId === 0 || this.chatUsername === '') { return; }
    this.qrOpen = true;
    this.qrCtrl.open();
  }

  private closeQr(): void {
    if (this.qrOpen) { this.qrCtrl.close(); this.qrOpen = false; }
  }

  private qrScanner: TelegramQrScanner = new TelegramQrScanner();

  aboutToDisappear(): void {
    this.clearTransitionSettleTimer();
    if (this.contentQueryTimer !== -1) {
      clearTimeout(this.contentQueryTimer);
      this.contentQueryTimer = -1;
    }
    if (this.memberQueryTimer !== -1) {
      clearTimeout(this.memberQueryTimer);
      this.memberQueryTimer = -1;
    }
    if (this.tabScrollRestoreTimer !== -1) {
      clearTimeout(this.tabScrollRestoreTimer);
      this.tabScrollRestoreTimer = -1;
    }
    markChatDestHidden(this.chatDestToken, true);
    this.qrScanner.cancel();
    this.closeQr();
    this.joinSeq++;
    this.inviteJoinResolver?.dispose();
    this.inviteJoinResolver = null;
    if (this.unsub !== null) { this.unsub(); this.unsub = null; }
    if (this.store !== null) { this.store.close(); this.store = null; }
  }

  // Mirror the store snapshot into @State (plain-field reads don't re-render).
  private refresh(): void {
    const s = this.store;
    if (s === null) {
      return;
    }
    // 已有预填首帧时，推页 585ms 过渡期内不往 @State 刷后台回包，让 renderGroup 纹理保持干净、
    // 避免转场中途爆发整页重绘；onShown() 落地后一次同步完整快照。
    if (!this.transitionSettled && this.hasPrefill) {
      this.pendingStoreRefresh = true;
      return;
    }
    const beforeTabs = this.visibleTabs();
    const beforeKey = beforeTabs.length > 0 && this.selectedTab < beforeTabs.length
      ? beforeTabs[this.selectedTab].key : '';
    if (this.pageState !== s.loadState) { this.pageState = s.loadState; }
    if (this.errorText !== s.errorText) { this.errorText = s.errorText; }
    if (this.membershipState !== s.membershipState) { this.membershipState = s.membershipState; }
    const nextJoinByRequest = this.inviteNeedsApproval || s.joinByRequest;
    if (this.joinByRequest !== nextJoinByRequest) { this.joinByRequest = nextJoinByRequest; }
    if ((this.membershipState === 'writable' || this.membershipState === 'blocked') && this.joinRequestSent) {
      this.joinRequestSent = false;
    }
    if (this.membersState !== s.membersState) { this.membersState = s.membersState; }
    if (this.contentItems !== s.contentItems) { this.contentItems = s.contentItems; }
    if (this.contentState !== s.contentState) { this.contentState = s.contentState; }
    if (this.mediaKind !== s.mediaKind) { this.mediaKind = s.mediaKind; }
    if (this.contentErrorText !== s.contentErrorText) { this.contentErrorText = s.contentErrorText; }
    if (this.contentHasMore !== s.contentHasMore) { this.contentHasMore = s.contentHasMore; }
    if (this.contentPaging !== s.contentPaging) { this.contentPaging = s.contentPaging; }
    if (this.contentPagingError !== s.contentPagingError) { this.contentPagingError = s.contentPagingError; }
    if (this.contentTotalCount !== s.contentTotalCount) { this.contentTotalCount = s.contentTotalCount; }
    if (!this.sameStringList(this.availableTabKeys, s.availableTabs)) {
      this.availableTabKeys = s.availableTabs;
    }
    if (this.tabsState !== s.tabsState) { this.tabsState = s.tabsState; }
    const nextTabs = this.visibleTabs();
    if (nextTabs.length > 0) {
      const wantedKey: string = this.pendingTabKey !== '' ? this.pendingTabKey : beforeKey;
      const nextIndex = wantedKey !== ''
        ? nextTabs.findIndex((tab: ProfileTabItem): boolean => tab.key === wantedKey) : -1;
      if (this.pendingTabKey !== '' && nextIndex >= 0) {
        this.pendingTabKey = '';
      }
      const resolvedTab = nextIndex >= 0 ? nextIndex : 0;
      if (this.selectedTab !== resolvedTab) { this.selectedTab = resolvedTab; }
      const selectedKey = nextTabs[this.selectedTab].key;
      if (s.contentTab !== selectedKey) {
        s.selectContentTab(selectedKey);
      }
      this.moveDetailIndicator(this.selectedTab);
    } else if (this.selectedTab !== 0) {
      this.selectedTab = 0;
    }
    if (s.loadState !== 'ready') {
      return;
    }
    if (this.title !== s.title) { this.title = s.title; }
    if (this.initials !== s.initials) { this.initials = s.initials; }
    if (this.avatarPath !== s.avatarPath) { this.avatarPath = s.avatarPath; }
    if (this.avatarAnimPath !== s.avatarAnimPath) { this.avatarAnimPath = s.avatarAnimPath; }
    if (this.subtitle !== s.subtitle) { this.subtitle = s.subtitle; }
    if (this.description !== s.description) { this.description = s.description; }
    if (this.chatUsername !== s.username) { this.chatUsername = s.username; }
    if (this.isChannel !== s.isChannel) { this.isChannel = s.isChannel; }
    if (this.isMuted !== s.isMuted) { this.isMuted = s.isMuted; }
    if (this.canManageVideoChats !== s.canManageVideoChats) { this.canManageVideoChats = s.canManageVideoChats; }
    if (this.canManageChat !== s.canManageChat) { this.canManageChat = s.canManageChat; }
    if (this.canInviteMembers !== s.canInviteMembers) { this.canInviteMembers = s.canInviteMembers; }
    if (this.viewerIsCreator !== s.isCreator) { this.viewerIsCreator = s.isCreator; }
    if (this.canPromoteMembers !== s.canPromoteMembers) { this.canPromoteMembers = s.canPromoteMembers; }
    if (this.canRestrictMembers !== s.canRestrictMembers) { this.canRestrictMembers = s.canRestrictMembers; }
    if (this.canDeleteMessages !== s.canDeleteMessages) { this.canDeleteMessages = s.canDeleteMessages; }
    const nextManageTags = this.store?.canManageTags ?? false;
    if (this.canManageTags !== nextManageTags) { this.canManageTags = nextManageTags; }
    if (this.selfUserId !== s.selfUserId) { this.selfUserId = s.selfUserId; }
    if (this.liveGroupCallId !== s.liveGroupCallId) { this.liveGroupCallId = s.liveGroupCallId; }
    if (this.members !== s.members) { this.members = s.members; }
  }

  // onReady 时本页在栈顶，正下方那层是不是同一个会话（见 util/splitRouting.profileSitsOnOwnChat）。
  private computeOverOwnChat(stack: NavPathStack): boolean {
    try {
      const names: string[] = stack.getAllPathName();
      const ids: number[] = names.map((_name: string, index: number): number => {
        const param = stack.getParamByIndex(index) as Record<string, Object> | undefined;
        return param !== undefined && param !== null ? ((param['chatId'] as number | undefined) ?? 0) : 0;
      });
      return profileSitsOnOwnChat(names, ids, names.length - 1, CHAT_DEST_NAME, this.chatId);
    } catch (error) {
      logE(`ChatProfilePage.computeOverOwnChat failed: ${error}`);
      return false;
    }
  }

  private openChat(): void {
    if (this.chatId === 0 || this.membershipState !== 'writable') {
      return;
    }
    const params: Record<string, Object> = { 'chatId': this.chatId };
    if (this.pendingDraftText !== '') {
      params['draftText'] = this.pendingDraftText;
    }
    if (this.pendingJumpTo > 0) {
      params['jumpTo'] = this.pendingJumpTo;
    }
    if (this.justJoined) {
      params['showJoinedNotice'] = true;
      params['joinedNoticeIsChannel'] = this.isChannel;
      this.justJoined = false;
    }
    navigateToChat(params, 'content').catch(logChatNavFailure);
  }

  private openSearchInChat(): void {
    if (this.chatId === 0) { return; }
    const params: Record<string, Object> = { 'chatId': this.chatId, 'startSearch': true };
    navigateToChat(params, 'content').catch(logChatNavFailure);
  }


  private leaveCurrentChat(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: this.isChannel ? $r('app.string.cp_leave_channel') : $r('app.string.cp_leave_group'),
      message: str('cp_leave_confirm', this.title),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.cp_leave'), color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) { return; }
      leaveChatFully(this.chatId).then((): void => {
        showToast($r('app.string.cpp_left'), 1500);
        this.goBack();
      }).catch((error: TdError): void => {
        logE(`ChatProfilePage.leave failed: ${error.message}`);
        showToast($r('app.string.cpp_leave_failed'), 1800);
      });
    }).catch((): void => {});
  }

  private boostChat(): void {
    const req: TdRequest = { '@type': 'getChatBoostStatus' };
    req['chat_id'] = this.chatId;
    getTdClient().send(req).then((status: TdObject): void => {
      const level = (status['level'] as number | undefined) ?? 0;
      const count = (status['boost_count'] as number | undefined) ?? 0;
      const next = (status['next_level_boost_count'] as number | undefined) ?? 0;
      this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.cpp_boost_channel'),
        message: str('cpp_boost_level', level, count) +
          (next > 0 ? str('cpp_boost_needed', Math.max(0, next - count)) : ''),
        buttons: [
          { text: $r('app.string.cancel'), color: '#8E8E93' },
          { text: $r('app.string.cpp_boost'), color: $r('app.color.primary') }
        ]
      }).then((result): void => {
        if (result.index !== 1) { return; }
        this.performBoost();
      }).catch((): void => {});
    }).catch((error: TdError): void => {
      logE(`ChatProfilePage.boostStatus failed: ${error.message}`);
      showToast($r('app.string.cpp_boost_info_failed'), 1700);
    });
  }

  private performBoost(): void {
    getTdClient().send({ '@type': 'getAvailableChatBoostSlots' } as TdRequest)
      .then((slots: TdObject): void => {
        const list = (slots['slots'] as TdObject[] | undefined) ?? [];
        const usable = list.find((slot: TdObject): boolean =>
          ((slot['currently_boosted_chat_id'] as number | undefined) ?? 0) !== this.chatId);
        if (usable === undefined) {
          showToast($r('app.string.cpp_no_boost_slots'), 2200);
          return;
        }
        const req: TdRequest = { '@type': 'boostChat' };
        req['chat_id'] = this.chatId;
        req['slot_ids'] = [(usable['slot_id'] as number | undefined) ?? 0];
        getTdClient().send(req).then((): void => {
          showToast($r('app.string.cpp_boosted'), 1600);
        }).catch((error: TdError): void => {
          logE(`ChatProfilePage.boost failed: ${error.message}`);
          showToast($r('app.string.cpp_boost_failed'), 1800);
        });
      }).catch((error: TdError): void => {
        logE(`ChatProfilePage.boostSlots failed: ${error.message}`);
        showToast($r('app.string.cpp_boost_slots_failed'), 1700);
      });
  }

  // TDLib's report flow is iterative: an empty option first, then the server
  // returns the reason list; picking one either finishes or asks for text.
  // 举报流程与消息菜单共用（util/reportFlow），这里只接 UI。
  private reportChat(): void {
    runReportFlow((req: TdRequest): Promise<TdObject> => getTdClient().send(req, 15000),
      { chatId: this.chatId, messageIds: [] } as ReportTarget,
      reportFlowUiFor(this.getUIContext()));
  }

  private loadInvitePreview(): void {
    if (this.inviteLink === '') {
      return;
    }
    this.pageState = 'loading';
    this.errorText = '';
    this.membershipState = 'checking';
    const req: TdRequest = { '@type': 'checkChatInviteLink' };
    req['invite_link'] = this.inviteLink;
    getTdClient().send(req).then((info: TdObject): void => {
      this.inviteNeedsApproval = (info['creates_join_request'] as boolean | undefined) ?? false;
      this.joinByRequest = this.inviteNeedsApproval;
      const resolvedChatId = (info['chat_id'] as number | undefined) ?? 0;
      if (resolvedChatId !== 0) {
        this.chatId = resolvedChatId;
        this.startStore();
        return;
      }
      this.title = (info['title'] as string | undefined) ?? str('cpp_telegram_group');
      this.initials = avatarInitialOf(this.title);
      this.description = (info['description'] as string | undefined) ?? '';
      const count = (info['member_count'] as number | undefined) ?? 0;
      const inviteType = (info['type'] as TdObject | undefined)
        ?? (info['chat_type'] as TdObject | undefined);
      const inviteTypeName = (inviteType?.['@type'] as string | undefined) ?? '';
      this.isChannel = ((info['is_channel'] as boolean | undefined) ?? false)
        || inviteTypeName.indexOf('Channel') >= 0
        || inviteTypeName.indexOf('channel') >= 0;
      this.subtitle = count > 0
        ? str('subtitle_member_count', count, this.isChannel ? str('subscribers_word') : str('members_word'))
        : (this.isChannel ? str('gn_channel') : str('gn_group'));
      this.joinByRequest =
        (info['creates_join_request'] as boolean | undefined) ?? false;
      this.membershipState = 'joinable';
      this.membersState = 'restricted';
      this.availableTabKeys = [];
      this.tabsState = 'ready';
      this.pageState = 'ready';
    }).catch((e: TdError): void => {
      logE(`ChatProfilePage.checkChatInviteLink failed: ${e.message}`);
      this.pageState = 'error';
      this.errorText = str('cpp_invite_invalid');
      this.membershipState = 'blocked';
    });
  }

  private joinChat(): void {
    if (this.joining || this.membershipState !== 'joinable' || this.joinRequestSent) {
      return;
    }
    this.joining = true;
    const seq: number = ++this.joinSeq;
    submitChatJoin(getTdClient(), this.chatId, this.inviteLink).then((result: ChatJoinOutcome): void => {
      if (seq !== this.joinSeq) { return; }
      this.joining = false;
      if (result.requested) {
        // A fast approval update may have reached the store before the reply.
        if (this.membershipState !== 'writable' && this.membershipState !== 'blocked') {
          this.joinRequestSent = true;
          if (this.chatId === 0 && this.inviteLink !== '') {
            this.inviteJoinResolver?.dispose();
            this.inviteJoinResolver = new InviteJoinResolver(getTdClient(), this.inviteLink,
              (chatId: number): void => { this.chatId = chatId; this.startStore(); });
            this.inviteJoinResolver.start();
          }
          showToast($r('app.string.cpp_join_requested'), 1800);
        }
        return;
      }
      this.chatId = result.chatId;
      this.joinRequestSent = false;
      this.membershipState = 'writable';
      this.justJoined = true;
      showToast(this.isChannel ? $r('app.string.cpp_joined_channel') : $r('app.string.cpp_joined_group'), 1500);
      if (this.chatId !== 0 && this.store === null) {
        this.startStore();
      }
    }).catch((e: TdError): void => {
      if (seq !== this.joinSeq) { return; }
      this.joining = false;
      logE(`ChatProfilePage.join failed: ${e.message}`);
      showToast($r('app.string.cpp_join_failed'), 1800);
    });
  }

  private primaryActionLabel(): string {
    if (this.joinRequestSent) {
      return str('cpp_requested');
    }
    if (this.membershipState === 'checking') {
      return str('loading_short');
    }
    if (this.membershipState === 'blocked') {
      return str('cpp_cannot_join');
    }
    if (this.membershipState === 'joinable') {
      if (this.joining) {
        return str('cpp_joining');
      }
      if (this.joinByRequest) {
        return str('cpp_request_join');
      }
      return this.isChannel ? str('cpp_join_channel') : str('cpp_join_group');
    }
    return str('cps_messages');
  }

  private toggleMute(): void {
    const willMute = !this.isMuted;
    // 统一走 ChatActions：那里用的是服务端会接受的静音时长，并且带
    // "会话未加载则先 getChat 再重试"的兜底。
    const pending = setMute(this.chatId, willMute ? MUTE_LONG : 0);
    // updateChatNotificationSettings 也会确认，但先本地翻转，按钮不必等往返。
    this.isMuted = willMute;
    pending.then((success: boolean): void => {
      if (success) {
        showToast(willMute ? $r('app.string.cl_muted') : $r('app.string.cpp_unmuted'), 1500);
      } else {
        this.isMuted = !willMute;
      }
    });
  }

  private openMemberProfile(userId: number): void {
    // fromChatId：机器人的主小程序要在「当前这个群」里打开（#201 第 2 条，util/botMainApp）。
    const params: Record<string, Object> = { 'userId': userId, 'fromChatId': this.chatId };
    // 曾经是 this.getUIContext().getRouter().pushUrl('pages/profile/ProfilePage')——ProfilePage 迁成
    // HdsNavDestination 并从 main_pages.json 摘出后，整页路由已经跳不动，统一
    // 走 navigateToProfile 这个唯一漏斗。
    navigateToProfile(params);
  }

  private moveDetailIndicator(index: number): void {
    const tabs = this.visibleTabs();
    if (index < 0 || index >= tabs.length) {
      return;
    }
    const width = this.detailTabWs[index] ?? 0;
    if (width <= 0) {
      return;
    }
    this.detailIndicatorX = this.detailTabXs[index] ?? 8;
    this.detailIndicatorW = width;
  }

  private ensureDetailTabVisible(index: number): void {
    const x = this.detailTabXs[index] ?? 0;
    const width = this.detailTabWs[index] ?? 0;
    if (width <= 0 || this.detailTabViewW <= 0) {
      return;
    }
    const cur = this.tabScroller.currentOffset();
    if (cur === undefined) {
      return;
    }
    const offset = cur.xOffset;
    let target = -1;
    if (x < offset + 8) {
      target = Math.max(0, x - 8);
    } else if (x + width > offset + this.detailTabViewW - 8) {
      target = x + width - this.detailTabViewW + 8;
    }
    if (target >= 0 && Math.abs(target - offset) > 1) {
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

  private movePinnedDetailIndicator(index: number): void {
    const width = this.pinnedTabWs[index] ?? 0;
    if (width <= 0) {
      return;
    }
    this.pinnedIndicatorX = this.pinnedTabXs[index] ?? 8;
    this.pinnedIndicatorW = width;
  }

  private ensurePinnedDetailTabVisible(index: number): void {
    if (!this.tabsPinned) {
      return;
    }
    const x = this.pinnedTabXs[index] ?? 0;
    const width = this.pinnedTabWs[index] ?? 0;
    if (width <= 0 || this.pinnedTabViewW <= 0) {
      return;
    }
    const cur = this.pinnedTabScroller.currentOffset();
    if (cur === undefined) {
      return;
    }
    const offset = cur.xOffset;
    let target = -1;
    if (x < offset + 8) {
      target = Math.max(0, x - 8);
    } else if (x + width > offset + this.pinnedTabViewW - 8) {
      target = x + width - this.pinnedTabViewW + 8;
    }
    if (target >= 0 && Math.abs(target - offset) > 1) {
      this.pinnedTabScroller.scrollTo({
        xOffset: target,
        yOffset: 0,
        animation: {
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
          curve: Curve.EaseOut
        }
      });
    }
  }

  private canSearchCurrentTab(): boolean {
    return this.currentTabKey() !== PROFILE_TAB_MEMBERS || this.membersState !== 'restricted';
  }

  private activeTabQuery(): string {
    return this.currentTabKey() === PROFILE_TAB_MEMBERS ? this.memberQuery : this.contentQuery;
  }

  private isTabSearchVisible(): boolean {
    return this.canSearchCurrentTab() && (this.tabSearchOpen || this.activeTabQuery() !== '');
  }

  private applyMemberQuery(next: string): void {
    this.memberQuery = next;
    if (this.memberQueryTimer !== -1) {
      clearTimeout(this.memberQueryTimer);
      this.memberQueryTimer = -1;
    }
    if (this.tabScrollRestoreTimer !== -1) {
      clearTimeout(this.tabScrollRestoreTimer);
      this.tabScrollRestoreTimer = -1;
    }
    if (next === '') {
      this.store?.searchMembers('');
      return;
    }
    this.memberQueryTimer = setTimeout((): void => {
      this.memberQueryTimer = -1;
      this.store?.searchMembers(next);
    }, 300);
  }

  private toggleTabSearch(): void {
    if (this.isTabSearchVisible()) {
      if (this.currentTabKey() === PROFILE_TAB_MEMBERS) {
        if (this.memberQuery !== '') {
          this.applyMemberQuery('');
        }
      } else if (this.contentQuery !== '') {
        this.applyContentQuery('');
      }
      this.tabSearchOpen = false;
    } else {
      this.tabSearchOpen = true;
    }
  }

  private pinThresholdY(): number {
    return Math.max(0, this.profileHeadH + GLASS_GAP - (this.topSafe + 4));
  }

  private pinnedClipTopY(): number {
    return this.topSafe + 4 + Math.max(DETAIL_TAB_BAR_HEIGHT, this.pinnedHeaderH);
  }

  private pinnedTailSpacerH(): number {
    if (!this.tabsPinned || this.listViewH <= 0) {
      return 0;
    }
    let estBodyH: number = 176;
    if (this.currentTabKey() === PROFILE_TAB_MEMBERS) {
      estBodyH = this.members.length > 0 ? this.members.length * 64 : 176;
    } else if (this.contentState === 'ready' && this.contentItems.length > 0) {
      estBodyH = (this.currentTabKey() === PROFILE_TAB_MEDIA || this.currentTabKey() === PROFILE_TAB_GIFS)
        ? Math.ceil(this.contentItems.length / 3) * this.mediaCellSize()
        : this.contentItems.length * 68;
    }
    const needed: number = this.listViewH - (this.topSafe + 4) - this.pinnedHeaderH;
    return Math.max(0, Math.ceil(needed - estBodyH));
  }

  private restoreScrollAfterTabSwitch(targetY: number): void {
    if (this.tabScrollRestoreTimer !== -1) {
      clearTimeout(this.tabScrollRestoreTimer);
    }
    this.tabScrollRestoreTimer = setTimeout((): void => {
      this.tabScrollRestoreTimer = -1;
      this.pageScroller.scrollTo({ xOffset: 0, yOffset: targetY, animation: false });
    }, 16);
  }

  private updateTabsPinned(y: number): void {
    const threshold: number = this.pinThresholdY();
    const shouldPin: boolean = this.profileHeadH > 0 &&
      this.transitionSettled && this.pageState === 'ready' &&
      this.tabsState !== 'loading' && this.visibleTabs().length > 0 &&
      y >= threshold;
    if (!shouldPin && Date.now() < this.pinLockUntil) {
      return;
    }
    if (this.tabsPinned !== shouldPin) {
      this.tabsPinned = shouldPin;
      if (!shouldPin) {
        this.pinnedTabViewW = 0;
      }
    }
  }

  private selectTab(index: number): void {
    const tabs = this.visibleTabs();
    if (index < 0 || index >= tabs.length || index === this.selectedTab) {
      this.resetTabSlide();
      return;
    }
    const prevY: number = this.pageScroller.currentOffset()?.yOffset ?? 0;
    const wasPinned: boolean = this.tabsPinned;
    if (wasPinned) {
      this.pinLockUntil = Date.now() + 260;
    }
    const dir: number = index > this.selectedTab ? 1 : -1;
    const dur: number = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 210);
    // 切换内容不参与布局补间，仅对指示器和列表内容做纯 GPU translate/opacity 滑入过渡。
    this.selectedTab = index;
    if (dur > 0) {
      this.tabSlideX = dir * 28;
      this.tabSlideOpacity = 0.35;
      this.getUIContext().animateTo({
        duration: dur,
        curve: Curve.EaseOut
      }, (): void => {
        this.tabSlideX = 0;
        this.tabSlideOpacity = 1;
        this.moveDetailIndicator(index);
        this.movePinnedDetailIndicator(index);
      });
    } else {
      this.tabSlideX = 0;
      this.tabSlideOpacity = 1;
      this.moveDetailIndicator(index);
      this.movePinnedDetailIndicator(index);
    }
    this.ensureDetailTabVisible(index);
    this.ensurePinnedDetailTabVisible(index);
    if (!this.canSearchCurrentTab()) {
      this.tabSearchOpen = false;
    }
    if (this.store !== null) {
      this.store.selectContentTab(tabs[index].key);
    } else if (index > 0) {
      this.contentItems = [];
      this.contentState = 'ready';
      this.contentHasMore = false;
    }
    const targetY: number = wasPinned ? this.pinThresholdY() : prevY;
    if (targetY > 0) {
      this.restoreScrollAfterTabSwitch(targetY);
    }
  }

  private handleDetailTabPanUpdate(offsetX: number): void {
    const tabs = this.visibleTabs();
    if (tabs.length <= 1) {
      return;
    }
    const atEdge: boolean = (offsetX > 0 && this.selectedTab <= 0) ||
      (offsetX < 0 && this.selectedTab >= tabs.length - 1);
    const clamped: number = Math.max(-44, Math.min(44, offsetX * (atEdge ? 0.12 : 0.28)));
    if (Math.abs(clamped - this.tabSlideX) > 0.5) {
      this.tabSlideX = clamped;
    }
  }

  private resetTabSlide(): void {
    if (this.tabSlideX === 0 && this.tabSlideOpacity === 1) {
      return;
    }
    const dur: number = powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180);
    if (dur <= 0) {
      this.tabSlideX = 0;
      this.tabSlideOpacity = 1;
      return;
    }
    this.getUIContext().animateTo({
      duration: dur,
      curve: curves.springMotion(0.32, 0.92)
    }, (): void => {
      this.tabSlideX = 0;
      this.tabSlideOpacity = 1;
    });
  }

  private handleDetailTabPan(offsetX: number): void {
    const tabs = this.visibleTabs();
    if (Math.abs(offsetX) < 42) {
      this.resetTabSlide();
      return;
    }
    const next: number = offsetX < 0 ? this.selectedTab + 1 : this.selectedTab - 1;
    if (next < 0 || next >= tabs.length) {
      this.resetTabSlide();
      return;
    }
    this.selectTab(next);
  }

  private applyContentQuery(next: string): void {
    this.contentQuery = next;
    if (this.contentQueryTimer !== -1) {
      clearTimeout(this.contentQueryTimer);
    }
    this.contentQueryTimer = setTimeout((): void => {
      this.contentQueryTimer = -1;
      if (this.store !== null) {
        this.store.setContentQuery(next);
      }
    }, CONTENT_QUERY_DEBOUNCE_MS);
  }

  // 列表里直接下载 / 打开，不用先跳回聊天记录（issue #102）。
  private onContentFileAction(item: ProfileContentItem): void {
    if (item.filePath !== '') {
      openLocalFile(this.getUIContext().getHostContext() as common.UIAbilityContext, item.filePath,
        fileOpenMimeType(item.title, item.mimeType))
        .then((ok: boolean): void => {
          if (!ok) {
            showToast($r('app.string.cp_file_open_failed'), 1800);
          }
        })
        .catch((e: Object): void => { logE(`ChatProfilePage.openLocalFile failed: ${e}`); });
      return;
    }
    if (this.store !== null) {
      this.store.downloadContentItem(item.messageId);
    }
  }

  private openContentMessage(messageId: number): void {
    if (this.chatId === 0 || messageId <= 0) {
      return;
    }
    const params: Record<string, Object> = {
      'chatId': this.chatId,
      'jumpTo': messageId
    };
    navigateToChat(params, 'content').catch(logChatNavFailure);
  }

  private currentTabLabel(): string {
    const tabs = this.visibleTabs();
    return tabs.length > 0 && this.selectedTab < tabs.length
      ? tabs[this.selectedTab].label : '';
  }

  private emptyStateText(): string {
    if (this.store === null && this.membershipState !== 'writable') {
      return str('cpp_join_to_view', this.currentTabLabel());
    }
    const label = this.currentTabLabel();
    if (this.currentTabKey() === PROFILE_TAB_GIFTS && this.contentHasMore) {
      return str('cpp_no_gifts');
    }
    return str('cpp_no_content', label);
  }

  private visibleTabs(): ProfileTabItem[] {
    if (this.tabsState !== 'ready') {
      return [];
    }
    return PROFILE_TABS.filter((tab: ProfileTabItem): boolean =>
      this.availableTabKeys.indexOf(tab.key) >= 0);
  }

  private currentTabKey(): string {
    const tabs = this.visibleTabs();
    return tabs.length > 0 && this.selectedTab < tabs.length
      ? tabs[this.selectedTab].key : '';
  }

  private openLiveViewer(groupCallId: number, isRtmpStream: boolean): void {
    const params: Record<string, Object> = {
      'groupCallId': groupCallId,
      'chatId': this.chatId
    };
    this.getUIContext().getRouter().pushUrl({
      url: isRtmpStream
        ? 'pages/chat/RtmpLiveStreamViewerPage'
        : 'pages/chat/LiveStreamViewerPage',
      params: params
    });
  }

  private async openExistingLive(): Promise<void> {
    if (this.liveGroupCallId <= 0 || this.creatingLive) { return; }
    this.creatingLive = true;
    const groupCallId = this.liveGroupCallId;
    try {
      let groupCall = await getGroupCall(getTdClient(), groupCallId);
      let active = (groupCall['is_active'] as boolean | undefined) ?? false;
      const scheduledStartDate =
        (groupCall['scheduled_start_date'] as number | undefined) ?? 0;
      if (!active && scheduledStartDate > 0 && this.canManageVideoChats) {
        await startScheduledVideoChat(getTdClient(), groupCallId);
        groupCall = await getGroupCall(getTdClient(), groupCallId);
        active = (groupCall['is_active'] as boolean | undefined) ?? false;
      }
      if (!active) {
        showToast($r('app.string.cpp_live_not_active'), 1600);
        return;
      }
      const isRtmp = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
      this.openLiveViewer(groupCallId, isRtmp);
    } catch (caught) {
      const error = caught as TdError;
      showToast(str('cpp_join_live_failed', error.message), 1800);
    } finally {
      this.creatingLive = false;
    }
  }

  private createLiveMenu(): void {
    if (!this.canManageVideoChats || this.creatingLive) { return; }
    // A live call already exists: admins can either join it or end it for
    // everyone (endGroupCall), which plain "leave" never does.
    if (this.liveGroupCallId > 0) {
      this.getUIContext().getPromptAction().showActionMenu({
        title: $r('app.string.cp_live_in_progress'),
        buttons: [
          { text: $r('app.string.cp_live_join'), color: '#3390EC' },
          { text: $r('app.string.cpp_end_live_all'), color: '#E5484D' }
        ]
      }).then((result): void => {
        if (result.index === 0) {
          this.openExistingLive();
        } else if (result.index === 1) {
          this.confirmEndLive();
        }
      }).catch((): void => {});
      return;
    }
    this.getUIContext().getPromptAction().showActionMenu({
      title: $r('app.string.cpp_start_live'),
      buttons: [
        { text: $r('app.string.cpp_group_live'), color: '#3390EC' },
        { text: $r('app.string.cpp_rtmp_live'), color: '#3390EC' }
      ]
    }).then((result): void => {
      if (result.index === 0) {
        this.createAndOpenLive(false);
      } else if (result.index === 1) {
        this.createAndOpenLive(true);
      }
    }).catch((): void => {});
  }

  private confirmEndLive(): void {
    const groupCallId = this.liveGroupCallId;
    if (groupCallId <= 0) { return; }
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.lv_end'),
      message: $r('app.string.cpp_end_live_body'),
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.cp_stop'), color: '#E5484D' }
      ]
    }).then((result): void => {
      if (result.index !== 1) { return; }
      endGroupCall(getTdClient(), groupCallId).then((): void => {
        this.liveGroupCallId = 0;
        showToast($r('app.string.lfw_ended'), 1500);
      }).catch((error: TdError): void => {
        logE(`ChatProfilePage.endLive failed: ${error.message}`);
        showToast($r('app.string.cpp_end_live_failed'), 1700);
      });
    }).catch((): void => {});
  }

  private async createAndOpenLive(isRtmpStream: boolean): Promise<void> {
    if (this.creatingLive || !this.canManageVideoChats) { return; }
    this.creatingLive = true;
    try {
      const groupCallId = await createVideoChat(getTdClient(), this.chatId, isRtmpStream);
      if (groupCallId <= 0) {
        throw new Error(str('cpp_no_group_call_id'));
      }
      this.liveGroupCallId = groupCallId;
      this.openLiveViewer(groupCallId, isRtmpStream);
    } catch (caught) {
      const error = caught as Error;
      showToast(str('cpp_start_live_failed', error.message), 2000);
    } finally {
      this.creatingLive = false;
    }
  }

  // 开关关着 = 不透明实色；开着才叠薄纱。和联系人页逐字同一套（见 util/surfaceGlass）。
  private glassOn(): boolean {
    return this.surfaceGlassOn && this.surfaceGlassEpoch >= 0;
  }

  private cardFill(): ResourceColor {
    return this.glassOn() ? surfaceGlassFill($r('app.color.surface')) : $r('app.color.surface');
  }

  // 卡片、网格和条目仅圆角不同；填充与气泡共用透明度档位，关闭时为实色。
  @Styles
  glassCard() {
    .backgroundColor(this.cardFill())
    .borderRadius(GLASS_RADIUS_CARD)
    .border({ width: 0.7, color: $r('app.color.divider') })
  }

  @Styles
  glassTile() {
    .backgroundColor(this.cardFill())
    .borderRadius(GLASS_RADIUS_TILE)
    .border({ width: 0.7, color: $r('app.color.divider') })
  }

  // 顶栏圆钮：玻璃交给系统沉浸材质（与聊天页顶栏那两颗同一副画法），
  // 原来那块自绘半透明底 + 0.7 描边在纯色底上只是灰白圆盘。
  @Builder
  circleButton(symbol: string, onTap: () => void) {
    Stack() {
      NativeGlassHost({
        hostWidth: 44,
        hostHeight: 44,
        hostRadius: 22,
        dark: this.appDark,
        surface: 'control'
      });
      Row() {
        SymbolGlyph($r(symbol)).fontSize(22).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(44).height(44)
      .justifyContent(FlexAlign.Center)
      .hitTestBehavior(HitTestMode.None);
      // 材质承载层是 enabled(false) 的 Toggle，收不到触摸：透明圆钮接管点击。
      Button({ type: ButtonType.Circle })
        .width(44).height(44)
        .backgroundColor(Color.Transparent)
        .stateEffect(false)
        .onClick(onTap);
    }
    .width(44).height(44);
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
  primaryActionButton() {
    Column({ space: 7 }) {
      if (this.joinRequestSent) {
        SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(24).fontColor([COLOR_PRIMARY]);
      } else if (this.membershipState === 'joinable') {
        SymbolGlyph($r('sys.symbol.person_badge_plus')).fontSize(24).fontColor([COLOR_PRIMARY]);
      } else {
        SymbolGlyph($r('sys.symbol.message')).fontSize(24).fontColor([COLOR_PRIMARY]);
      }
      Text(this.primaryActionLabel()).fontSize(13).fontWeight(FontWeight.Medium)
        .fontColor(COLOR_PRIMARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .layoutWeight(1).height(86)
    .justifyContent(FlexAlign.Center)
    .glassTile()
    .opacity(this.membershipState === 'blocked' || this.membershipState === 'checking' ? 0.55 : 1)
    .enabled(this.membershipState === 'writable' ||
      (this.membershipState === 'joinable' && !this.joining && !this.joinRequestSent))
    .onClick((): void => {
      if (this.membershipState === 'writable') {
        this.openChat();
      } else {
        this.joinChat();
      }
    });
  }

  // Dedicated builder (not the param-based actionButton): @Builder value
  // params don't re-evaluate on @State change, so the icon/label would stick.
  @Builder
  muteButton() {
    Column({ space: 7 }) {
      Stack() {
        if (this.isMuted) {
          SymbolGlyph($r('sys.symbol.bell')).fontSize(24).fontColor([COLOR_PRIMARY])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220), curve: Curve.EaseOut
              }));
        } else {
          SymbolGlyph($r('sys.symbol.bell_slash')).fontSize(24).fontColor([COLOR_PRIMARY])
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 220), curve: Curve.EaseOut
              }));
        }
      }.height(26);
      Text(this.isMuted ? $r('app.string.cp_unmute') : $r('app.string.cp_mute'))
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .layoutWeight(1).height(86)
    .justifyContent(FlexAlign.Center)
    .glassTile()
    .onClick(() => { this.toggleMute(); });
  }

  @Builder
  liveButton() {
    Column({ space: 7 }) {
      SymbolGlyph($r('sys.symbol.camera')).fontSize(24).fontColor([COLOR_PRIMARY]);
      Text(this.creatingLive ? $r('app.string.processing_short') : $r('app.string.lv_stream'))
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .layoutWeight(1).height(86)
    .justifyContent(FlexAlign.Center)
    .glassTile()
    .enabled(!this.creatingLive)
    .opacity(this.creatingLive ? 0.62 : 1)
    .onClick((): void => { this.createLiveMenu(); });
  }

  @Builder
  sectionDivider() {
    Divider().color($r('app.color.divider')).strokeWidth(0.7);
  }

  // ── 下拉放大头像（与「我的资料」「联系人资料」共用 util/avatarMorph）──────
  private canMorphAvatar(): boolean {
    return canExpandAvatar(this.avatarPath, this.avatarAnimPath);
  }

  private effectiveAvatarPull(): number {
    return this.canMorphAvatar() ? this.avatarPull : 0;
  }

  private isAvatarExpanded(): boolean {
    return this.avatarExpanded && this.canMorphAvatar();
  }

  private avatarMorphing(): boolean {
    return this.isAvatarExpanded() || this.effectiveAvatarPull() > 0.5;
  }

  private avatarRatio(): number {
    return avatarRatioOf(this.effectiveAvatarPull(), this.isAvatarExpanded());
  }

  private avatarMaxWidth(): number {
    return this.avatarAvailW > 0 ? this.avatarAvailW : this.screenW;
  }

  private avatarCardInset(): number {
    return avatarUsesCardLayout(this.widthBp, this.heightBp, this.forceSingleColumn)
      ? this.pageMargin() : 0;
  }

  private avatarTargetWidth(): number {
    return Math.max(AVATAR_PROFILE_BASE, this.avatarMaxWidth() - this.avatarCardInset() * 2);
  }

  private avatarPhotoW(): number {
    return avatarWidthOf(this.effectiveAvatarPull(), this.isAvatarExpanded(),
      this.avatarTargetWidth(), AVATAR_PROFILE_BASE);
  }

  private avatarPhotoH(): number {
    return avatarHeightOf(this.effectiveAvatarPull(), this.isAvatarExpanded(), AVATAR_PROFILE_BASE);
  }

  private avatarPhotoRadius(): number {
    return avatarRadiusOf(this.effectiveAvatarPull(), this.isAvatarExpanded(),
      this.avatarCardInset() > 0 ? AVATAR_CARD_RADIUS : 0, AVATAR_PROFILE_BASE);
  }

  private avatarRing(): number {
    return avatarRingOf(this.effectiveAvatarPull(), this.isAvatarExpanded(), AVATAR_PROFILE_RING);
  }

  private avatarBoxW(): number {
    return this.avatarPhotoW() + this.avatarRing() * 2;
  }

  private avatarBoxH(): number {
    return this.avatarPhotoH() + this.avatarRing() * 2;
  }

  private avatarBoxRadius(): number {
    return this.avatarPhotoRadius() + this.avatarRing();
  }

  private avatarTopPad(): number {
    return Math.max(0, this.topSafe + 8 - AVATAR_TOP_LIFT);
  }

  private avatarTopInset(): number {
    const align: number = this.avatarCardInset() > 0 ? this.topSafe : 0;
    return this.avatarTopPad() + AVATAR_HEAD_ROW + AVATAR_HEAD_GAP - align;
  }

  private avatarOffsetY(): number {
    return avatarOffsetYOf(this.effectiveAvatarPull(), this.isAvatarExpanded(), this.avatarTopInset());
  }

  private avatarTextTop(): number {
    if (this.isAvatarExpanded()) {
      return this.avatarBoxH() - AVATAR_TEXT_H - AVATAR_TEXT_BOTTOM;
    }
    return this.avatarBoxH() + 8;
  }

  private avatarBlockH(): number {
    const text: number = this.isAvatarExpanded() ? 0 : 8 + AVATAR_TEXT_H;
    return Math.max(0, this.avatarBoxH() + this.avatarOffsetY() + text);
  }

  private avatarDecodeW(): number {
    return avatarDecodeWidthOf(this.effectiveAvatarPull(), this.isAvatarExpanded(),
      this.avatarTargetWidth(), AVATAR_PROFILE_BASE);
  }

  private avatarDecodeH(): number {
    return avatarDecodeHeightOf(this.effectiveAvatarPull(), this.isAvatarExpanded(), AVATAR_PROFILE_BASE);
  }

  private handlePageScroll(): void {
    const y: number = this.pageScroller.currentOffset().yOffset;
    this.updateTabsPinned(y);
    if (!this.canMorphAvatar()) {
      if (this.avatarPull !== 0) { this.avatarPull = 0; }
      if (this.avatarExpanded) { this.avatarExpanded = false; }
      return;
    }
    if (y < 0) {
      const pull: number = Math.abs(y);
      if (this.avatarPull !== pull) {
        this.avatarPull = pull;
      }
      if (!this.avatarExpanded && pull > AVATAR_EXPAND_AT) {
        this.getUIContext().animateTo({
          duration: AVATAR_SNAP_MS,
          curve: curves.springMotion(0.36, 0.90)
        }, (): void => {
          this.avatarExpanded = true;
          this.avatarSnapAt = Date.now();
        });
      }
      return;
    }
    if (this.avatarPull !== 0) {
      this.avatarPull = 0;
    }
    if (this.avatarExpanded && y > AVATAR_COLLAPSE_AT &&
      Date.now() - this.avatarSnapAt > AVATAR_SNAP_MS + 120) {
      this.getUIContext().animateTo({
        duration: AVATAR_SNAP_MS + 60,
        curve: curves.springMotion(0.40, 0.78)
      }, (): void => {
        this.avatarExpanded = false;
      });
    }
  }

  @Builder
  header() {
    Column({ space: AVATAR_HEAD_GAP }) {
      Row() {
        this.circleButton('sys.symbol.chevron_left', () => { this.goBack(); });
        Blank().layoutWeight(1);
        // Top-right is the leave action; everything else lives in the
        // actions-row 更多 menu.
        this.circleButton('sys.symbol.arrow_right_and_square', () => {
          if (this.chatId !== 0) { this.leaveCurrentChat(); }
        });
      }
      .width('100%')
      .height(AVATAR_HEAD_ROW)
      // 展开态照片顶边在安全区下沿；这一行本身比它高 4vp，所以额外补 4vp，
      // 让两颗圆钮正好落在照片的两个上角里面、不超出（用户 2026-11-25）。
      .padding({
        left: this.pageMargin() + AVATAR_BUTTON_INSET * this.avatarRatio(),
        right: this.pageMargin() + AVATAR_BUTTON_INSET * this.avatarRatio()
      })
      .offset({ x: 0, y: (AVATAR_BUTTON_INSET + 4) * this.avatarRatio() })
      .zIndex(2);
      // 最外只挂尺寸与上移 —— 绝对不能加 .animation()，否则下拉会变成橡皮筋。
      Stack({ alignContent: Alignment.Top }) {
        Stack({ alignContent: Alignment.Center }) {
          Stack({ alignContent: Alignment.Center }) {
            AvatarView({
              avatarPath: this.avatarPath, initials: this.initials,
              colorSeed: this.chatId, avatarSize: 116,
              animPath: this.transitionSettled ? this.avatarAnimPath : '',
              animationPaused: this.viewerAvatarPath !== '',
              // 绘制尺寸逐帧跟手；解码尺寸只在收起/展开两个稳定态切换。
              boxWidth: this.avatarPhotoW(),
              boxHeight: this.avatarPhotoH(),
              boxRadius: this.avatarPhotoRadius(),
              decodeWidth: this.avatarDecodeW(),
              decodeHeight: this.avatarDecodeH()
            });
          }
          .width(this.avatarPhotoW())
          .height(this.avatarPhotoH())
          .borderRadius(this.avatarPhotoRadius())
          .clip(true);
        }
        .width('100%')
        .height('100%')
        .padding(this.avatarRing())
        .backgroundColor(this.cardFill())
        // 展开态环宽与圆角都收成 0 了，只剩这圈 0.7vp 描边压在照片四边——
        // 屏幕顶部与左右那条白线就是它。跟着环一起淡掉，别裁照片。
        .border({ width: 0.7 * (1 - this.avatarRatio()), color: $r('app.color.divider') })
        .borderRadius(this.avatarBoxRadius())
        // 记下点击处的屏幕坐标，查看器据此决定放大/缩回的中心点。
        .onClick((event: ClickEvent): void => {
          if (this.avatarPath !== '') {
            this.avatarTapX = event.windowX;
            this.avatarTapY = event.windowY;
            this.viewerAvatarPath = this.avatarPath;
          }
        })
        .width(this.avatarBoxW())
        .height(this.avatarBoxH())
        .offset({ x: 0, y: this.avatarOffsetY() });
        // 名字 / 副标题：展开态变白、压在照片左下。
        Column({ space: 8 }) {
          Text(this.title)
            .fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor(this.isAvatarExpanded() ? Color.White : COLOR_TEXT_PRIMARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '86%' });
          if (this.subtitle !== '') {
            Text(this.subtitle).fontSize(15)
              .fontColor(this.isAvatarExpanded() ? '#E6FFFFFF' : COLOR_TEXT_SECONDARY);
          }
        }
        .width('100%')
        .height(AVATAR_TEXT_H)
        .alignItems(this.isAvatarExpanded() ? HorizontalAlign.Start : HorizontalAlign.Center)
        .padding({
          left: this.isAvatarExpanded() ? AVATAR_TEXT_INSET + this.avatarCardInset() : 0,
          right: this.isAvatarExpanded() ? AVATAR_TEXT_INSET + this.avatarCardInset() : 0
        })
        .margin({ top: this.avatarTextTop() })
        .offset({ x: 0, y: this.avatarOffsetY() })
        .zIndex(1)
        .hitTestBehavior(HitTestMode.Transparent);
      }
      .width('100%')
      .height(this.avatarBlockH())
      .zIndex(1);
    }
    .width('100%')
    .padding({ top: this.avatarTopPad() });
  }

  @Builder
  // Two fixed rows of at most four buttons each: primary actions on top,
  // secondary/administrative ones below. Seven buttons never fit one row.
  actionsRow() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        // 从会话里点进来时「消息」多余——按返回就回到会话；从搜索、链接、转发来源等
        // 进来时下面不是这个会话，得留一个入口。加入前它是「加入」按钮。
        if (this.membershipState !== 'writable' || !this.overOwnChat) {
          this.primaryActionButton();
        }
        if (this.chatId !== 0) {
          this.muteButton();
          this.actionButton('sys.symbol.magnifyingglass', str('cp_search'), () => { this.openSearchInChat(); });
          if (this.canManageVideoChats) {
            this.liveButton();
          }
        }
      }.width('100%');
      if (this.chatId !== 0) {
        Row({ space: 10 }) {
          // Only creators / admins with real rights see the management entry.
          if (this.canManageChat) {
            this.actionButton('sys.symbol.gearshape', str('lv_manage_short'), () => {
              const params: Record<string, Object> = { 'chatId': this.chatId };
              this.getUIContext().getRouter().pushUrl({ url: 'pages/main/GroupAdminPage', params })
                .catch((error: Error): void => {
                  logE(`ChatProfilePage.openAdmin failed: ${error.message}`);
                });
            });
          }
          this.actionButton('sys.symbol.bolt', str('cpp_boost'), () => { this.boostChat(); });
          this.actionButton('sys.symbol.flag', str('mb_report'), () => { this.reportChat(); });
        }.width('100%');
      }
    }
    .width('100%').padding({ left: this.pageMargin(), right: this.pageMargin(), top: GLASS_GAP });
  }

  @Builder
  pageStateCard() {
    Column({ space: 10 }) {
      if (this.pageState === 'loading') {
        LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        Text($r('app.string.cpp_loading_details')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      } else {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28).fontColor([COLOR_ICON_SECONDARY]);
        Text(this.errorText !== '' ? this.errorText : $r('app.string.cpp_details_failed'))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(16).fontColor([COLOR_PRIMARY]);
          Text($r('app.string.settings_retry')).fontSize(14).fontColor(COLOR_PRIMARY);
        }
        .height(36).padding({ left: 14, right: 14 }).borderRadius(18)
        .backgroundColor('#123390EC')
        .onClick((): void => {
          if (this.inviteLink !== '') {
            this.loadInvitePreview();
          } else {
            this.startStore();
          }
        });
      }
    }
    // width('100%') 不能和横向 margin 同时用：百分比宽先按父宽定值，margin 再叠在
    // 外部，总宽 = 父宽 + left + right，右端会被裁掉。宽度改用 calc 扣掉左右 margin。
    .width('calc(100% - 24vp)').padding({ top: 28, bottom: 28, left: 16, right: 16 })
    .glassCard()
    .margin({ left: 12, right: 12, top: 16 });
  }

  @Builder
  infoCard() {
    Column() {
      Column() {
        if (this.description !== '') {
          Column({ space: 2 }) {
            ExpandableText({ content: this.description });
            Text($r('app.string.ps_bio')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%').padding({ top: 8, bottom: 8 });
        }
        if (this.chatUsername !== '') {
          if (this.description !== '') {
            this.sectionDivider();
          }
          Row({ space: 12 }) {
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(this.publicChatLink()).fontSize(15).fontWeight(FontWeight.Medium)
                  .fontColor(COLOR_PRIMARY).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 'calc(100% - 26vp)' })
                  .flexShrink(1)
                  .copyOption(CopyOptions.LocalDevice);
                SymbolGlyph($r('sys.symbol.plus_square_on_square'))
                  .fontSize(14).fontColor([COLOR_PRIMARY])
                  .width(20).height(24).flexShrink(0);
              }
              .width('100%').alignItems(VerticalAlign.Center);
              Text($r('app.string.cpp_links')).fontSize(12.5).fontColor(COLOR_TEXT_SECONDARY);
            }
            .alignItems(HorizontalAlign.Start).layoutWeight(1)
            .accessibilityText($r('app.string.fl_copy_link'))
            .onClick((): void => { this.copyPublicLink(); });
            if (this.chatId !== 0) {
              Row() {
                SymbolGlyph($r('sys.symbol.qrcode')).fontSize(21).fontColor([COLOR_PRIMARY]);
              }
              .width(42).height(42).borderRadius(GLASS_RADIUS_CHIP)
              .justifyContent(FlexAlign.Center).flexShrink(0)
              .backgroundColor($r('app.color.selected_pill'))
              .accessibilityText($r('app.string.mp_show_qr'))
              .onClick((): void => { this.openQr(); });
            }
          }
          .width('100%').padding({ top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center);
        }
        if (this.description === '' && this.chatUsername === '') {
          Text($r('app.string.cpp_no_profile')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
            .padding({ top: 10, bottom: 10 });
        }
        if (this.chatId !== 0) {
          this.sectionDivider();
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text($r('app.string.mf_chat_title')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY);
              Text($r('app.string.mf_chat_profile_sub')).fontSize(12.5).fontColor(COLOR_TEXT_SECONDARY);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Text(this.filterEpoch < 0 ? '' : (
              getMessageFilterStore().activeRuleCountForChat(this.chatId) > 0
                ? str('mf_rule_count', String(getMessageFilterStore().activeRuleCountForChat(this.chatId)))
                : str('mf_status_none')
            ))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(15).fontColor([COLOR_TEXT_SECONDARY]);
          }
          .width('100%').padding({ top: 10, bottom: 10 })
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            const param: MessageFilterRouteParam = {
              chatId: this.chatId,
              chatTitle: this.title
            };
            this.navStack?.pushPath({ name: 'MessageFilterPage', param });
          });
        }
      }
      .width('100%').padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .glassCard()
      .alignItems(HorizontalAlign.Start);
    }
    .margin({ left: this.pageMargin(), right: this.pageMargin(), top: GLASS_GAP });
  }

  // 长按成员时该出哪些菜单项。判定是纯函数，见 util/memberMenu。
  // 成员行（复用组件）只报 userId：回调跟着复用节点进出复用池，不能攥着建它时的那个成员。
  private handleMemberActionById(userId: number, action: string): void {
    const m: MemberItem | undefined = this.members.find((item: MemberItem): boolean => item.userId === userId);
    if (m !== undefined) {
      this.handleMemberAction(m, action);
    }
  }

  private onContentFileActionById(messageId: number): void {
    const item: ProfileContentItem | undefined =
      this.contentItems.find((it: ProfileContentItem): boolean => it.messageId === messageId);
    if (item !== undefined) {
      this.onContentFileAction(item);
    }
  }

  // 媒体网格的行宽（= 玻璃卡内容宽），格子边长按它算。没真的变就不写回状态。
  private noteMediaRowWidth(width: number): void {
    if (width > 0 && Math.abs(width - this.mediaRowW) > 0.5) {
      this.mediaRowW = width;
    }
  }

  private memberKey(m: MemberItem): string {
    // key 里带上菜单形态：权限是异步读回来的，只按 id 的话，先渲染出来的那批行会一直挂着
    // "什么都不能做"的旧菜单（原 ForEach 的注释）。权限状态变化时 syncMembersData 会重发。
    return `${m.userId}_${m.avatarPath}_${m.name}_${m.status}_${m.role}_${m.roleTitle}_${m.tag}_` +
      memberMenuSignature(this.menuOptionsFor(m));
  }

  private syncMembersData(): void {
    this.membersData.update(this.members,
      this.members.map((m: MemberItem): string => `${m.userId}`),
      this.members.map((m: MemberItem): string => this.memberKey(m)));
  }

  // 媒体行以位置为身份（row_0、row_1…）：翻页只会让最后一个不满的行变内容、后面追加新行，
  // 数据源因此发的是 CHANGE + ADD，而不是整表 RELOAD。
  private mediaRowKey(row: ProfileContentItem[], index: number): string {
    return `row_${index}_` + row.map((it: ProfileContentItem): string =>
      `${it.messageId}_${it.thumbPath}_${it.duration}`).join('|');
  }

  private syncContentData(): void {
    const items: ProfileContentItem[] = this.contentItems;
    this.contentData.update(items,
      items.map((it: ProfileContentItem): string => `${it.messageId}`),
      items.map((it: ProfileContentItem): string => profileContentKey(it)));
    const rows: ProfileContentItem[][] = chunkRows(items, MEDIA_GRID_COLS);
    this.mediaRowsData.update(rows,
      rows.map((_row: ProfileContentItem[], index: number): string => `row_${index}`),
      rows.map((row: ProfileContentItem[], index: number): string => this.mediaRowKey(row, index)));
  }

  private menuOptionsFor(m: MemberItem): MemberMenuOptions {
    return memberMenuOptions(
      {
        isCreator: this.viewerIsCreator,
        canPromoteMembers: this.canPromoteMembers,
        canRestrictMembers: this.canRestrictMembers,
        canDeleteMessages: this.canDeleteMessages,
        canManageTags: this.canManageTags
      },
      m.role,
      this.selfUserId !== 0 && m.userId === this.selfUserId,
      this.isChannel
    );
  }

  private handleMemberAction(m: MemberItem, action: string): void {
    // 走不下去必须留痕。这条守卫从前是静默 return，成员操作一旦被它拦下，
    // 界面上什么都不会发生，日志里也什么都没有——排查时无从下手。
    if (this.chatId === 0 || m.userId <= 0) {
      logE(`ChatProfilePage.handleMemberAction(${action}) skipped:` +
        ` chatId=${this.chatId} userId=${m.userId}`);
      return;
    }
    if (action === MEMBER_ACTION_TITLE) {
      this.openTitleDialog(m);
    } else if (action === MEMBER_ACTION_PROMOTE) {
      this.openMemberPanel('pages/profile/MemberPromotePage', m);
    } else if (action === MEMBER_ACTION_RESTRICT) {
      this.openMemberPanel('pages/profile/MemberRestrictPage', m);
    } else if (action === MEMBER_ACTION_BAN) {
      this.confirmMemberAction(str('ga_ban_short'), str('mm_ban_confirm'), str('ga_ban_short'),
        (): Promise<void> => banMember(this.chatId, m.userId, false));
    } else if (action === MEMBER_ACTION_REMOVE) {
      this.confirmMemberAction(str('ga_remove_member'), m.name, str('ga_remove_member'),
        (): Promise<void> => removeMember(this.chatId, m.userId));
    } else if (action === MEMBER_ACTION_DELETE_MESSAGES) {
      this.confirmMemberAction(str('ga_delete_all'), str('mm_delete_all_confirm'), str('delete'),
        (): Promise<void> => deleteMessagesFromSender(this.chatId, m.userId));
    }
  }

  // 「编辑标签」：群成员标签（chatMemberTag），任何成员都能打，全员可见。
  // 回显直接用 chatMember.tag——TDLib 把"成员标签或管理员头衔"合在这一个
  // 字段里，正好就是该预填的值。
  @State private titleTarget: MemberItem | null = null;
  private titleCtrl: CustomDialogController = new CustomDialogController({
    builder: MemberTitleDialog({
      memberName: '',
      title: '',
      onConfirm: (next: string): void => { this.applyMemberTitle(next); }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    // 弹窗自绘玻璃卡片，必须 customStyle——否则系统还会再包一层白色对话框
    // 底板，看着是"两层弹窗"。
    customStyle: true
  });

  // 同样从长按菜单里点出来，同样要等菜单收起再弹，否则对话框会挂在
  // 已经在消失的子窗口上。
  private openTitleDialog(m: MemberItem): void {
    setTimeout((): void => { this.showTitleDialog(m); }, MENU_DISMISS_MS);
  }

  private showTitleDialog(m: MemberItem): void {
    this.titleTarget = m;
    this.titleCtrl = new CustomDialogController({
      builder: MemberTitleDialog({
        memberName: m.name,
        title: m.tag,
        onConfirm: (next: string): void => { this.applyMemberTitle(next); }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true
    });
    this.titleCtrl.open();
  }

  private applyMemberTitle(next: string): void {
    const target: MemberItem | null = this.titleTarget;
    if (target === null || this.chatId === 0) {
      return;
    }
    setMemberTag(this.chatId, target.userId, next).then((): void => {
      showToast($r('app.string.ga_done'), 1400);
      this.store?.reloadMembers();
    }).catch((error: TdError): void => {
      logE(`ChatProfilePage.setMemberTag failed: ${error.message}`);
      showToast(str('ga_failed'), 1600);
    });
  }

  // 破坏性操作一律二次确认：封禁进黑名单、删消息不可撤销，误触的代价太高。
  //
  // 这些确认框全是从成员行的长按菜单里点出来的。上下文菜单是独立子窗口，
  // 在它收起的过程中调**全局** promptAction.showDialog 会静默挂死：弹出来的
  // 对话框没有可依附的 UI 上下文，Promise 既不 resolve 也不 reject，界面上
  // 一点反应都没有（"不提示、不确认、不消失"就是这么来的）。两处修正跟
  // ChatRow 一致：用 UIContext 作用域的 promptAction，并延后到菜单收起之后。
  private confirmMemberAction(
    title: string, message: string, confirmLabel: string, run: () => Promise<void>
  ): void {
    const prompt = this.getUIContext().getPromptAction();
    setTimeout((): void => {
      this.runConfirmDialog(prompt, title, message, confirmLabel, run);
    }, MENU_DISMISS_MS);
  }

  private runConfirmDialog(
    prompt: PromptAction, title: string, message: string, confirmLabel: string,
    run: () => Promise<void>
  ): void {
    prompt.showDialog({
      title,
      message,
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: confirmLabel, color: '#E5484D' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      run().then((): void => {
        prompt.showToast({ message: $r('app.string.ga_done'), duration: 1400 });
        this.store?.reloadMembers();
      }).catch((caught: TdError): void => {
        logE(`ChatProfilePage.memberAction failed: ${caught.message}`);
        prompt.showToast({
          message: caught.message.indexOf('rights') >= 0 ||
            caught.message.indexOf('ADMIN') >= 0
            ? str('ga_no_permission') : str('ga_failed'),
          duration: 1700
        });
      });
    }).catch((e: Object): void => {
      // 点遮罩关掉也走这里，属于正常取消，记一笔就够，不打扰用户。
      logI(`ChatProfilePage.confirmMemberAction dismissed: ${JSON.stringify(e)}`);
    });
  }

  // 两个面板都是独立页面：它们要先读成员当前状态再回填，逻辑量不小，塞进
  // 这个已经很大的文件只会更难改。
  private openMemberPanel(url: string, m: MemberItem): void {
    const params: Record<string, Object> = {
      'chatId': this.chatId,
      'userId': m.userId,
      'memberName': m.name,
      'memberInitials': m.initials,
      'memberAvatar': m.avatarPath,
      'memberStatus': m.status,
      'isChannel': this.isChannel
    };
    // 面板改完权限后成员的身份标签会变，回来必须重拉一次。
    this.pendingMemberReload = true;
    this.getUIContext().getRouter().pushUrl({ url, params }).catch((error: Error): void => {
      this.pendingMemberReload = false;
      logE(`ChatProfilePage.openMemberPanel failed: ${error.message}`);
    });
  }

  // 公开链接的完整形式。展示和复制用同一个值，免得看到的和粘出来的不一致。
  private publicChatLink(): string {
    return `t.me/${this.chatUsername}`;
  }

  private copyPublicLink(): void {
    if (this.chatUsername === '') {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN,
      `https://${this.publicChatLink()}`);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      showToast($r('app.string.link_copied'), 1200);
    }).catch((e: Object): void => {
      logE(`ChatProfilePage.copyPublicLink failed: ${JSON.stringify(e)}`);
      showToast($r('app.string.copy_failed'), 1500);
    });
  }

  @Builder
  detailTabStrip(pinned: boolean) {
    Scroll(pinned ? this.pinnedTabScroller : this.tabScroller) {
      Stack({ alignContent: Alignment.TopStart }) {
        Row()
          .width(pinned ? this.pinnedIndicatorW : this.detailIndicatorW)
          .height(DETAIL_TAB_INDICATOR_HEIGHT)
          .borderRadius(DETAIL_TAB_INDICATOR_HEIGHT / 2)
          .backgroundColor(COLOR_TAB_PILL_BG)
          .position({
            x: pinned ? this.pinnedIndicatorX : this.detailIndicatorX,
            y: (DETAIL_TAB_BAR_HEIGHT - DETAIL_TAB_INDICATOR_HEIGHT) / 2
          });
        Row() {
          ForEach(this.visibleTabs(), (tab: ProfileTabItem, index: number) => {
            Row() {
              Text(tab.label)
                .fontSize(14.5)
                .fontWeight(index === this.selectedTab ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(index === this.selectedTab
                  ? COLOR_TAB_SELECTED : COLOR_TAB_UNSELECTED)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            }
            .height(DETAIL_TAB_BAR_HEIGHT)
            .padding({ left: 12, right: 12 })
            .margin({ right: 2 })
            .borderRadius(DETAIL_TAB_BAR_HEIGHT / 2)
            .stateStyles({ normal: this.tabNormalStyle, pressed: this.tabPressedStyle })
            .onAreaChange((_old: Area, area: Area): void => {
              const nextX: number = area.position.x as number;
              const nextW: number = area.width as number;
              if (pinned) {
                const changed: boolean = Math.abs((this.pinnedTabXs[index] ?? -1) - nextX) > 0.5 ||
                  Math.abs((this.pinnedTabWs[index] ?? -1) - nextW) > 0.5;
                if (!changed) { return; }
                this.pinnedTabXs[index] = nextX;
                this.pinnedTabWs[index] = nextW;
                if (index === this.selectedTab) {
                  this.movePinnedDetailIndicator(index);
                  this.ensurePinnedDetailTabVisible(index);
                }
              } else {
                const changed: boolean = Math.abs((this.detailTabXs[index] ?? -1) - nextX) > 0.5 ||
                  Math.abs((this.detailTabWs[index] ?? -1) - nextW) > 0.5;
                if (!changed) { return; }
                this.detailTabXs[index] = nextX;
                this.detailTabWs[index] = nextW;
                if (index === this.selectedTab) {
                  this.moveDetailIndicator(index);
                  this.ensureDetailTabVisible(index);
                }
              }
            })
            .onClick((): void => { this.selectTab(index); });
          }, (tab: ProfileTabItem) => tab.key);
        }
        .padding({ left: 8, right: 8 })
        .height(DETAIL_TAB_BAR_HEIGHT);
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Start)
    .layoutWeight(1)
    .height(DETAIL_TAB_BAR_HEIGHT)
    .clip(true)
    .onAreaChange((_old: Area, area: Area): void => {
      const nextW: number = area.width as number;
      if (pinned) {
        if (Math.abs(this.pinnedTabViewW - nextW) <= 0.5) { return; }
        this.pinnedTabViewW = nextW;
        this.ensurePinnedDetailTabVisible(this.selectedTab);
      } else {
        if (Math.abs(this.detailTabViewW - nextW) <= 0.5) { return; }
        this.detailTabViewW = nextW;
        this.ensureDetailTabVisible(this.selectedTab);
      }
    });
  }

  @Builder
  inlineSearchBar() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
      if (this.currentTabKey() === PROFILE_TAB_MEMBERS) {
        TextInput({ text: this.memberQuery, placeholder: $r('app.string.cpp_search_members') })
          .layoutWeight(1).height(38).fontSize(15)
          .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
          .fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .caretColor(COLOR_PRIMARY)
          .enterKeyType(EnterKeyType.Search)
          .onChange((v: string): void => { this.applyMemberQuery(v); });
        if (this.memberQuery !== '') {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(16).fontColor([COLOR_ICON_SECONDARY])
            .onClick((): void => { this.applyMemberQuery(''); })
            .accessibilityText($r('app.string.clear_search'));
        }
      } else {
        TextInput({ text: this.contentQuery, placeholder: $r('app.string.cp_search') })
          .layoutWeight(1).height(38).fontSize(15)
          .backgroundColor(Color.Transparent).padding(0).borderRadius(0)
          .fontColor(COLOR_TEXT_PRIMARY)
          .placeholderColor(COLOR_TEXT_SECONDARY)
          .caretColor(COLOR_PRIMARY)
          .enterKeyType(EnterKeyType.Search)
          .onChange((v: string): void => { this.applyContentQuery(v); });
        if (this.contentQuery !== '') {
          SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
            .fontSize(16).fontColor([COLOR_ICON_SECONDARY])
            .onClick((): void => { this.applyContentQuery(''); })
            .accessibilityText($r('app.string.clear_search'));
        }
      }
    }
    .width('100%').height(38)
    .padding({ left: 12, right: 12 })
    .borderRadius(19)
    .backgroundColor($r('app.color.reaction_chip'))
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  inlineMediaKindBar() {
    Row({ space: 4 }) {
      ForEach(MEDIA_KINDS, (kind: string) => {
        Text(this.mediaKindLabel(kind))
          .fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.mediaKind === kind ? Color.White : COLOR_TEXT_SECONDARY)
          .layoutWeight(1).height(30).textAlign(TextAlign.Center)
          .backgroundColor(this.mediaKind === kind ? COLOR_PRIMARY : Color.Transparent)
          .borderRadius(15)
          .onClick((): void => { this.applyMediaKind(kind); });
      }, (kind: string): string => `mediaKind_${kind}_${this.mediaKind === kind}`);
    }
    .width('100%')
    .padding(3)
    .borderRadius(18)
    .backgroundColor($r('app.color.reaction_chip'));
  }

  @Builder
  detailTabHeader(pinned: boolean) {
    Column() {
      Row({ space: 4 }) {
        this.detailTabStrip(pinned);
        if (this.canSearchCurrentTab()) {
          Row() {
            SymbolGlyph($r(this.isTabSearchVisible()
              ? 'sys.symbol.xmark' : 'sys.symbol.magnifyingglass'))
              .fontSize(17)
              .fontColor([this.isTabSearchVisible() ? COLOR_PRIMARY : COLOR_ICON_SECONDARY]);
          }
          .width(36).height(36).borderRadius(18)
          .flexShrink(0)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.isTabSearchVisible() ? COLOR_TAB_PILL_BG : Color.Transparent)
          .onClick((): void => { this.toggleTabSearch(); })
          .accessibilityText($r('app.string.cp_search'));
        }
      }
      .width('100%')
      .height(DETAIL_TAB_BAR_HEIGHT)
      .padding({ left: 4, right: 8 })
      .alignItems(VerticalAlign.Center);
      if (this.isTabSearchVisible()) {
        Column() {
          this.inlineSearchBar();
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 8 });
      }
      if (this.currentTabKey() === PROFILE_TAB_MEDIA) {
        Column() {
          this.inlineMediaKindBar();
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 2, bottom: 8 });
      }
      Divider().strokeWidth(0.5).color($r('app.color.divider'));
    }
    .width('100%');
  }

  @Builder
  tabsLoadingCard() {
    Row({ space: 9 }) {
      LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
      Text($r('app.string.cpp_organising_shared')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
    }
    .width('calc(100% - 24vp)').height(52)
    .margin({ left: 12, right: 12, top: 12, bottom: 20 })
    .justifyContent(FlexAlign.Center)
    .glassCard();
  }

  // 成员页签：一整块玻璃卡（ListItemGroup），成员行走 LazyForEach + 复用组件 MemberRow。
  // 原来是 Column + ForEach，大群翻页加载后几百上千行一起活着。左右滑切页签的手势挂在卡片
  // 上（原来挂在内容 Column 上），不挂整个 List——那会抢走页签条自己的横向滚动。
  private openAddMembers(): void {
    if (!this.canInviteMembers || this.chatId === 0) { return; }
    this.pendingMemberReload = true;
    const params: Record<string, Object> = { 'addToChatId': this.chatId,
      'existingUserIds': this.members.map((member: MemberItem): number => member.userId) };
    this.getUIContext().getRouter().pushUrl({ url: 'pages/main/NewGroupPage', params }).catch((error: Error): void => {
      this.pendingMemberReload = false;
      logE(`ChatProfilePage.openAddMembers failed: ${error.message}`);
    });
  }

  @Builder
  membersBodyItems() {
    if (this.canInviteMembers && this.chatId !== 0) {
      ListItem() {
        Column() {
          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.person_badge_plus')).fontSize(24).fontColor([COLOR_PRIMARY]);
            Text($r('app.string.ng_add_members')).fontSize(16).fontColor(COLOR_PRIMARY).layoutWeight(1);
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([COLOR_ICON_SECONDARY]);
          }
          .width('100%').height(56).padding({ left: 16, right: 16 })
          .onClick((): void => this.openAddMembers());
          if (this.members.length > 0) {
            Divider().strokeWidth(0.5).color($r('app.color.divider')).margin({ left: 52 });
          }
        }
        .width('100%');
      }
      .translate({ x: this.tabSlideX })
      .opacity(this.tabSlideOpacity)
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionUpdate((event: GestureEvent): void => {
            this.handleDetailTabPanUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent): void => {
            this.handleDetailTabPan(event.offsetX);
          })
          .onActionCancel((): void => {
            this.resetTabSlide();
          })
      )
    }
    if (this.members.length > 0) {
      LazyForEach(this.membersData, (m: MemberItem, idx: number) => {
        ListItem() {
          MemberRow({
            member: m,
            options: this.menuOptionsFor(m),
            showDivider: idx < this.members.length - 1,
            onOpenProfile: (userId: number): void => { this.openMemberProfile(userId); },
            onAction: (userId: number, action: string): void => { this.handleMemberActionById(userId, action); }
          });
        }
        .translate({ x: this.tabSlideX })
        .opacity(this.tabSlideOpacity)
        .priorityGesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
            .onActionUpdate((event: GestureEvent): void => {
              this.handleDetailTabPanUpdate(event.offsetX);
            })
            .onActionEnd((event: GestureEvent): void => {
              this.handleDetailTabPan(event.offsetX);
            })
            .onActionCancel((): void => {
              this.resetTabSlide();
            })
        )
      }, (m: MemberItem, idx: number): string =>
        guardKey(this.membersData.keyTableId, idx, this.memberKey(m)));
      if (this.store !== null && this.store.hasMoreMembers) {
        ListItem() {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
            Text($r('app.string.cpp_loading_more_members')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }.height(52).justifyContent(FlexAlign.Center).width('100%');
        }
        .translate({ x: this.tabSlideX })
        .opacity(this.tabSlideOpacity)
        .priorityGesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
            .onActionUpdate((event: GestureEvent): void => {
              this.handleDetailTabPanUpdate(event.offsetX);
            })
            .onActionEnd((event: GestureEvent): void => {
              this.handleDetailTabPan(event.offsetX);
            })
            .onActionCancel((): void => {
              this.resetTabSlide();
            })
        )
      }
    } else if (this.membersState === 'loading') {
      ListItem() {
        this.inlineState('loading', str('cpp_loading_members'));
      }
      .translate({ x: this.tabSlideX })
      .opacity(this.tabSlideOpacity)
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionUpdate((event: GestureEvent): void => {
            this.handleDetailTabPanUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent): void => {
            this.handleDetailTabPan(event.offsetX);
          })
          .onActionCancel((): void => {
            this.resetTabSlide();
          })
      )
    } else if (this.membersState === 'restricted') {
      ListItem() {
        this.inlineState('restricted', this.isChannel
          ? str('cpp_no_full_subscribers')
          : str('cpp_no_member_access'));
      }
      .translate({ x: this.tabSlideX })
      .opacity(this.tabSlideOpacity)
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionUpdate((event: GestureEvent): void => {
            this.handleDetailTabPanUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent): void => {
            this.handleDetailTabPan(event.offsetX);
          })
          .onActionCancel((): void => {
            this.resetTabSlide();
          })
      )
    } else if (this.membersState === 'error') {
      ListItem() {
        this.inlineState('error', str('cpp_members_failed'));
      }
      .translate({ x: this.tabSlideX })
      .opacity(this.tabSlideOpacity)
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionUpdate((event: GestureEvent): void => {
            this.handleDetailTabPanUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent): void => {
            this.handleDetailTabPan(event.offsetX);
          })
          .onActionCancel((): void => {
            this.resetTabSlide();
          })
      )
    } else {
      ListItem() {
        // 搜索没结果和群本来就没人是两回事，别都说「没有成员」。
        this.inlineState('empty', (this.store?.memberQuery ?? '') !== ''
          ? str('ct_no_results') : str('cpp_no_members'));
      }
      .translate({ x: this.tabSlideX })
      .opacity(this.tabSlideOpacity)
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionUpdate((event: GestureEvent): void => {
            this.handleDetailTabPanUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent): void => {
            this.handleDetailTabPan(event.offsetX);
          })
          .onActionCancel((): void => {
            this.resetTabSlide();
          })
      )
    }
  }

  @Builder
  inlineState(kind: string, text: string) {
    Column({ space: 10 }) {
      if (kind === 'loading') {
        LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
      } else if (kind === 'error') {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(26).fontColor([COLOR_ICON_SECONDARY]);
      } else if (kind === 'restricted') {
        SymbolGlyph($r('sys.symbol.lock_fill'))
          .fontSize(24).fontColor([COLOR_ICON_SECONDARY]);
      } else {
        SymbolGlyph($r('sys.symbol.message'))
          .fontSize(25).fontColor([COLOR_ICON_SECONDARY]);
      }
      Text(text).fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
        .textAlign(TextAlign.Center).maxLines(2);
    }
    .width('100%').height(154).justifyContent(FlexAlign.Center)
    .padding({ left: 28, right: 28 });
  }

  @Builder
  contentPlaceholder() {
    Column({ space: 10 }) {
      if (this.contentState === 'loading') {
        LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        Text(str('cpp_loading_tab', this.currentTabLabel()))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.contentState === 'error') {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(28).fontColor([COLOR_ICON_SECONDARY]);
        Text(this.contentErrorText !== '' ? this.contentErrorText : $r('app.string.load_failed'))
          .fontSize(14).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        Text($r('app.string.settings_retry')).fontSize(14).fontColor(COLOR_PRIMARY)
          .height(34).padding({ left: 16, right: 16 }).textAlign(TextAlign.Center)
          .backgroundColor('#123390EC').borderRadius(17)
          .onClick((): void => { if (this.store !== null) { this.store.retryContent(); } });
      } else {
        SymbolGlyph($r(this.currentTabKey() === PROFILE_TAB_GIFTS
          ? 'sys.symbol.gift' : 'sys.symbol.message'))
          .fontSize(27).fontColor([COLOR_ICON_SECONDARY]);
        Text(this.emptyStateText()).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
        if (this.currentTabKey() === PROFILE_TAB_GIFTS && this.contentHasMore) {
          Text($r('app.string.cpp_search_older')).fontSize(14).fontColor(COLOR_PRIMARY)
            .height(34).padding({ left: 16, right: 16 }).textAlign(TextAlign.Center)
            .backgroundColor('#123390EC').borderRadius(17)
            .onClick((): void => { if (this.store !== null) { this.store.loadMoreContent(); } });
        }
      }
    }
    .width('100%').height(176)
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center);
  }

  private mediaCellSize(): number {
    // 按量到的内容宽算，不是按窗口宽——描边不算在父容器内容区里，按
    // screenW 算出来的三格会比内容区宽 1.4vp，第三格永远掉行。见 util/mediaGrid。
    return mediaGridCellSize(this.mediaRowW > 0
      ? this.mediaRowW : mediaFallbackContentWidth(this.screenW));
  }

  private contentIcon(item: ProfileContentItem): string {
    if (item.contentType === 'messageDocument') {
      return 'sys.symbol.doc_text';
    }
    if (item.contentType === 'messageVoiceNote') {
      return 'sys.symbol.mic';
    }
    if (item.contentType === 'messageAudio') {
      return 'sys.symbol.play_fill';
    }
    if (item.contentType === 'messagePoll') {
      return 'sys.symbol.checkmark_circle';
    }
    if (item.contentType === 'messageAnimation' || item.contentType === 'messageVideoNote') {
      return 'sys.symbol.video';
    }
    if (item.contentType.indexOf('Gift') >= 0 || item.contentType.indexOf('gift') >= 0) {
      return 'sys.symbol.gift';
    }
    if (this.currentTabKey() === PROFILE_TAB_LINKS) {
      return 'sys.symbol.link';
    }
    return 'sys.symbol.message';
  }

  // 页签内搜索条（issue #102）。TDLib 的 searchChatMessages 本来就同时收
  // query 和 filter，所以每个内容页签都能搜，不只是"文件"。
  private applyMediaKind(kind: string): void {
    this.store?.setMediaKind(kind);
  }

  private mediaKindLabel(kind: string): string {
    if (kind === MEDIA_KIND_PHOTO) { return str('cpp_media_photos'); }
    if (kind === MEDIA_KIND_VIDEO) { return str('cpp_media_videos'); }
    return str('cpp_media_all');
  }

  // 内容页签主体（媒体 / 文件 / 链接…），直接嵌在合并后的大玻璃卡 ListItemGroup 内。
  @Builder
  contentBodyItems() {
    if (this.contentState === 'loading' || this.contentState === 'error' ||
      (this.contentState === 'ready' && this.contentItems.length === 0)) {
      ListItem() {
        this.contentPlaceholder();
      }
      .translate({ x: this.tabSlideX })
      .opacity(this.tabSlideOpacity)
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionUpdate((event: GestureEvent): void => {
            this.handleDetailTabPanUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent): void => {
            this.handleDetailTabPan(event.offsetX);
          })
          .onActionCancel((): void => {
            this.resetTabSlide();
          })
      )
    } else if (this.currentTabKey() === PROFILE_TAB_MEDIA || this.currentTabKey() === PROFILE_TAB_GIFS) {
      // 格子边长按行的实际宽算（onSizeChange 量行宽，理由见 util/mediaGrid）。
      LazyForEach(this.mediaRowsData, (row: ProfileContentItem[], index: number) => {
        ListItem() {
          ProfileMediaRow({
            items: row,
            cellSize: this.mediaCellSize(),
            pressedOpacity: 0.58,
            onOpen: (messageId: number): void => { this.openContentMessage(messageId); }
          });
        }
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
          this.noteMediaRowWidth(Number(size.width));
        })
        .translate({ x: this.tabSlideX })
        .opacity(this.tabSlideOpacity)
        .priorityGesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
            .onActionUpdate((event: GestureEvent): void => {
              this.handleDetailTabPanUpdate(event.offsetX);
            })
            .onActionEnd((event: GestureEvent): void => {
              this.handleDetailTabPan(event.offsetX);
            })
            .onActionCancel((): void => {
              this.resetTabSlide();
            })
        );
      }, (row: ProfileContentItem[], index: number): string =>
        guardKey(this.mediaRowsData.keyTableId, index, this.mediaRowKey(row, index)));
    } else {
      LazyForEach(this.contentData, (item: ProfileContentItem, index: number) => {
        ListItem() {
          Column() {
            ProfileContentRow({
              item: item,
              icon: this.contentIcon(item),
              fileActions: true,
              onOpen: (messageId: number): void => { this.openContentMessage(messageId); },
              onFileAction: (messageId: number): void => { this.onContentFileActionById(messageId); }
            });
            if (index < this.contentItems.length - 1) {
              Divider().strokeWidth(0.7).color($r('app.color.divider')).margin({ left: 69 });
            }
          }
          .width('100%');
        }
        .translate({ x: this.tabSlideX })
        .opacity(this.tabSlideOpacity)
        .priorityGesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
            .onActionUpdate((event: GestureEvent): void => {
              this.handleDetailTabPanUpdate(event.offsetX);
            })
            .onActionEnd((event: GestureEvent): void => {
              this.handleDetailTabPan(event.offsetX);
            })
            .onActionCancel((): void => {
              this.resetTabSlide();
            })
        );
      }, (item: ProfileContentItem, index: number): string =>
        guardKey(this.contentData.keyTableId, index, profileContentKey(item)));
    }
  }

  // 页签横条 + 搜索/筛选 + 底下内容列表合并为同一张玻璃大卡（ListItemGroup），
  // 滚到顶部后由浮层 detailTabHeader(true) 无缝接管吸顶。
  @Builder
  unifiedTabSection() {
    ListItemGroup() {
      ListItem() {
        this.detailTabHeader(false);
      }
      .opacity(this.tabsPinned ? 0 : 1);
      if (this.currentTabKey() === PROFILE_TAB_MEMBERS) {
        this.membersBodyItems();
      } else {
        this.contentBodyItems();
      }
    }
    .width(`calc(100% - ${this.pageMargin() * 2}vp)`)
    .margin({
      left: this.pageMargin(),
      right: this.pageMargin(),
      top: GLASS_GAP,
      bottom: this.currentTabKey() !== PROFILE_TAB_MEMBERS && this.contentItems.length > 0 ? 4 : 24
    })
    .glassCard().clip(true);
    if (this.currentTabKey() !== PROFILE_TAB_MEMBERS && this.contentItems.length > 0) {
      ListItem() {
        this.paginationFooter();
      }
      .translate({ x: this.tabSlideX })
      .opacity(this.tabSlideOpacity)
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionUpdate((event: GestureEvent): void => {
            this.handleDetailTabPanUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent): void => {
            this.handleDetailTabPan(event.offsetX);
          })
          .onActionCancel((): void => {
            this.resetTabSlide();
          })
      )
    }
    if (this.pinnedTailSpacerH() > 0) {
      ListItem() {
        Column().width('100%').height(this.pinnedTailSpacerH());
      }
      .translate({ x: this.tabSlideX })
      .opacity(this.tabSlideOpacity)
      .priorityGesture(
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 12 })
          .onActionUpdate((event: GestureEvent): void => {
            this.handleDetailTabPanUpdate(event.offsetX);
          })
          .onActionEnd((event: GestureEvent): void => {
            this.handleDetailTabPan(event.offsetX);
          })
          .onActionCancel((): void => {
            this.resetTabSlide();
          })
      )
    }
  }

  @Builder
  paginationFooter() {
    Row({ space: 8 }) {
      if (this.contentPaging) {
        LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
        Text($r('app.string.cpp_loading_more')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.contentPagingError) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(16).fontColor([COLOR_PRIMARY]);
        Text($r('app.string.load_failed_tap')).fontSize(13).fontColor(COLOR_PRIMARY);
      } else if (!this.contentHasMore && this.contentItems.length > 0) {
        Text($r('app.string.cpp_end_of_list')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }
    }
    .width('100%').height(this.contentItems.length > 0 ? 54 : 0)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      if (this.contentPagingError && this.store !== null) {
        this.store.loadMoreContent();
      }
    });
  }

  // 页面边距（util/pageMargin，SPEC-07）：手机 12，折叠屏 16，平板 20。
  private pageMargin(): number {
    return pageMarginVp(this.widthBp);
  }

  build() {
    HdsNavDestination() {
    // 查看器需覆盖整页，故在滚动容器外再包一层 Stack。
    Stack({ alignContent: Alignment.TopStart }) {
    // 壁纸在最底，其余内容画在它之上。分栏下 AppBackdrop 自己什么都不画
    // （见 util/localWallpaper.appWallpaperActive），与主界面同一条规则。
    AppBackdrop({ split: isSplitByBreakpoint(this.widthBp, this.heightBp, this.forceSingleColumn, this.windowPortrait) });
    // 整页是一个 List（原来是 Scroll > Column）：头图、操作行、资料卡在第一项，页签条与页签内容
    // 合并进同一张玻璃大卡 ListItemGroup——成员、文件/链接走 LazyForEach，媒体网格按 3 格一行走 LazyForEach。
    // 大群的成员、翻了很多页的共享内容都只建可视区附近的行，其余滚动时逐帧补建。
    // 外层 Column 仅在吸顶态裁剪 List 顶边，避免列表内容穿过吸顶头栏或漏到状态栏区，
    // 同时不改动 List 自己的坐标系和壁纸透显。
    Column() {
    List({ scroller: this.pageScroller }) {
      ListItem() {
        Column() {
          this.header();
          if (this.pageState === 'ready') {
            this.actionsRow();
            if (this.transitionSettled || this.description !== '' || this.chatUsername !== '') {
              this.infoCard();
            }
            if (this.transitionSettled && this.tabsState === 'loading') {
              this.tabsLoadingCard();
            }
          } else {
            this.pageStateCard();
          }
        }
        .width('100%')
        .onAreaChange((_old: Area, area: Area): void => {
          const h: number = Number(area.height);
          if (h > 0 && Math.abs(h - this.profileHeadH) > 0.5) {
            this.profileHeadH = h;
            this.updateTabsPinned(this.pageScroller.currentOffset().yOffset);
          }
        });
      }
      if (this.transitionSettled && this.pageState === 'ready' && this.tabsState !== 'loading' &&
        this.visibleTabs().length > 0) {
        this.unifiedTabSection();
      }
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off)
    .cachedCount(PROFILE_LIST_CACHED_COUNT)
    // 与设置页等页面同一范式：半径只由开关决定，滚动中不降级；
    // 唯一的例外是头像下拉放大形变期间（整屏大图，糊它无意义），判断收在 edgeBlurRadiusWhileMorphing。
    .attributeModifier(this.edgeBlur.bind(
      edgeBlurRadiusWhileMorphing(this.avatarMorphing(),
        edgeBlurOtherTopOn(this.edgeBlurOn, this.edgeBlurTopOn, this.edgeBlurOtherTop),
        edgeBlurOtherBottomOn(this.edgeBlurOn, this.edgeBlurBottomOn, this.edgeBlurOtherBottom)),
      this.listViewH,
      edgeBlurOtherTopOn(this.edgeBlurOn, this.edgeBlurTopOn, this.edgeBlurOtherTop),
      edgeBlurOtherBottomOn(this.edgeBlurOn, this.edgeBlurBottomOn, this.edgeBlurOtherBottom)))
    .clip(false)
    // 下拉放大头像：越界回弹要开 Spring，越界值就是手指行程。
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onAreaChange((_o: Area, n: Area): void => {
      const h: number = n.height as number;
      if (h > 0 && Math.abs(h - this.listViewH) > 0.5) { this.listViewH = h; }
      const w: number = n.width as number;
      if (w > 0 && Math.abs(w - this.avatarAvailW) > 0.5) { this.avatarAvailW = w; }
    })
    .onDidScroll((_offset: number): void => {
      // 下拉放大头像：读越界值，不另挂一个 onDidScroll。
      this.handlePageScroll();
    })
    // 壁纸生效时整页底必须透明，否则壁纸被这一层盖死（同 util/theme.mainPageFill
    // 的理由）。卡片自己是毛玻璃（overlayGlassFill），压在壁纸上仍然读得清。
    .backgroundColor(this.appWallpaperOn ? Color.Transparent : $r('app.color.page_bg'))
    .onReachEnd((): void => {
      if (this.store === null) {
        return;
      }
      if (this.currentTabKey() === PROFILE_TAB_MEMBERS) {
        this.store.loadMoreMembers();
      } else {
        this.store.loadMoreContent();
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    }
    .width('100%').height('100%')
    .clipShape(this.tabsPinned && this.listViewH > 0
      ? new RectShape({
        width: '100%',
        height: Math.max(100, this.listViewH - this.pinnedClipTopY())
      }).position({ x: 0, y: this.pinnedClipTopY() })
      : undefined)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    if (this.tabsPinned) {
      Column() {
        this.detailTabHeader(true);
      }
      .width(`calc(100% - ${this.pageMargin() * 2}vp)`)
      .margin({ left: this.pageMargin(), right: this.pageMargin(), top: this.topSafe + 4 })
      .backgroundColor(this.cardFill())
      .borderRadius({ topLeft: GLASS_RADIUS_CARD, topRight: GLASS_RADIUS_CARD, bottomLeft: 0, bottomRight: 0 })
      .border({
        width: { top: 0.7, left: 0.7, right: 0.7, bottom: 0 },
        color: $r('app.color.divider')
      })
      .clip(true)
      .onAreaChange((_old: Area, area: Area): void => {
        const h: number = Number(area.height);
        if (h > 0 && Math.abs(h - this.pinnedHeaderH) > 0.5) {
          this.pinnedHeaderH = h;
        }
      })
      .zIndex(8);
    }
    if (this.viewerAvatarPath !== '') {
      AvatarViewer({
        imagePath: this.viewerAvatarPath,
        videoPath: this.avatarPath === this.viewerAvatarPath ? this.avatarAnimPath : '',
        imageFileId: this.store?.avatarFileId ?? 0,
        chatId: this.chatId,
        originX: this.avatarTapX,
        originY: this.avatarTapY,
        onClose: (): void => { this.viewerAvatarPath = ''; }
      }).zIndex(20);
    }
    }
    .width('100%').height('100%');
    }
    // 本页自绘标题栏（头图上那一行返回/退出），不要 HDS 的。
    .hideTitleBar(true)
    .onBackPressed((): boolean => {
      if (this.viewerAvatarPath !== '') { this.viewerAvatarPath = ''; return true; }
      return collapseFloatingVideo();
    })
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
      this.navParams = ctx.pathInfo.param as Record<string, Object> | undefined;
      // 必须在这里调而不是等 aboutToAppear：实测 onReady 晚于 aboutToAppear。
      this.applyRouteParams();
    })
    .onWillShow((): void => { markChatDestShown(this.chatDestToken); })
    .onShown((): void => { this.handleShown(); })
    .onHidden((): void => {
      this.viewerAvatarPath = '';
      markChatDestHidden(this.chatDestToken);
      this.closeQr();
    })
    .width('100%').height('100%');
  }
}
