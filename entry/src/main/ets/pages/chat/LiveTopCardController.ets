// 顶栏下挂那张浮卡（置顶消息条 + 直播/群通话条）的状态机。
// 从 ChatPage 整体搬出（B5 批）。
//
// 【为什么要搬】
// 这一簇的心跳是 livePulseTimer：直播条只要亮着，就每 780ms 翻一次
// livePulseExpanded。搬之前那是 ChatPage 的 @Local，于是每 780ms 都要重跑一遍
// 页面的 chatTitleBarBottom 闭包、再逐个比较 TopBanners 的 13 个 @Param——
// 一次呼吸动画，代价是整页的一轮依赖重算。搬进 @ObservedV2 之后，TopBanners
// 直接持有本控制器的引用、在自己的 build() 里读 @Trace，翻转只刷新读到它的那
// 几个节点，ChatPage 一个字都不读。
//
// 只把字段搬走、读点留在页面，收益就只有行数——所以 TopBanners 必须改成直读
// 本对象，这是 B5 唯一真正缩小重渲染半径的地方。
//
// 【为什么仍有几个字段收窄不了】
// pinnedPreview / liveGroupCallId / liveCallIsActive / topCardLoadingVisible
// 这 4 个决定顶栏高度（chromeGeometryInput → headerChromeHeight/topBannerHeight），
// 几何链贯穿整页；shouldShow() 也是页面级 build 的判定。页面读它们时走
// this.topCard.xxx，依赖粒度仍是该字段本身，与搬之前一一对应。
// liveLoadState 是全簇唯一 build 链完全不读的显示态，但它仍是 @Trace：与同组
// 字段保持一致的语义，且多一个无人订阅的 @Trace 只是一次空通知。
//
// 【为什么是 per-ChatPage 实例，不是模块级单例】
// 平板分栏、导航栈多层时同时活着多个 ChatPage，每个都有自己的 chatId、自己的
// group call、自己的置顶轮转位置。做成单例会让两页互相改对方的横幅。页面用
// 字段初始化器 new 一个：首帧前就已存在、引用全生命周期稳定、类型非空。
//
// 【为什么 dispose() 里 seq 先自增、再清定时器】
// liveChatResolveSeq / liveGroupResolveSeq 是 getChat / getGroupCall 的在途响应
// 守卫：响应回来时先比 seq，对不上就整个丢掉。先 ++seq 再 clearTimeout /
// clearInterval，是为了让「已经发出、还没回来」的那一趟 TDLib 请求在 then/catch
// 里被判成过期，而不是回来往一个已经 dispose 的对象上写字段。反过来先清定时器
// 再 ++seq，中间那一小段窗口里回来的响应就会漏进来。这个顺序与搬之前
// aboutToDisappear 的 disposeTimersAndSeqGuards 一致。
//
// 【不在本类里声明 @Monitor】
// 官方规则：类中 @Monitor 的解注册依赖 GC，销毁时机不可靠。本簇的所有联动都用
// 显式方法调用表达。

import { router, promptAction } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { MessageStore } from '../../store/MessageStore';
import { ChatEntry } from '../../store/ChatEntry';
import {
  KEY_POWER_PARTICLES, KEY_POWER_SMOOTH_TRANSITIONS,
  powerAnimationDuration, powerFeatureEnabled
} from '../../store/AppSettings';
import { AlbumGroup, groupIndexOf } from '../../util/collapseAlbums';
import {
  PINNED_EMPTY, PINNED_IGNORE, PINNED_JUMP, PINNED_LATEST, PINNED_RETRY,
  PinnedTap, pinnedTapAction
} from '../../util/pinnedJump';
import { pinnedShownIndex } from '../../util/pinnedSegments';
import { TOP_CARD_ACTION_GUARD_MS, TOP_CARD_LOADING_DELAY_MS } from '../../util/chatPageTuning';
import { plural, str } from '../../util/strings';
import { logE } from '../../util/log';
import { floatingLiveWindow } from './LiveFloatingWindow';

// 宿主（ChatPage）暴露给控制器的那一小片接口，全是箭头函数字段——取值器读页面
// 当下的真值，动作回调把副作用交回页面执行。仿 util/chatPageLifecycle.ets 的
// ChatPageHiddenHooks。
//
// 两条纪律：
// 1. 这里只放**取值器**，不放页面的 @Local 引用。控制器不缓存页面的值，每次要
//    用就现取——否则页面改了字段、控制器手里还是旧的。
// 2. 共享的滚动/跳转真源（curStartIdx、pendingJumpId、scroller）留在页面：控制器
//    只读地看 curStartIdx，要改就走显式动作回调。
export interface LiveTopCardHost {
  // 当前会话 id。0 表示路由还没落地。
  chatId: () => number;
  // >0 表示这是评论区/话题视图——决定置顶条的初始加载态（评论区没有置顶条，
  // 直接算 'ready'，不必先转一圈同步态）。
  threadRootId: () => number;
  // 会话标题，进直播页时作为初始标题带过去。
  title: () => string;
  // 当前 MessageStore；路由切换途中可能为 null。
  store: () => MessageStore | null;
  // 时间线当前的行分组（置顶条要拿视口顶部那一行的消息 id）。
  groups: () => AlbumGroup[];
  // 视口最上面那一行的行号，取不到时为 -1。
  curStartIdx: () => number;
  // 用户主动跳转前的清场：清浮动日期、stayAtUnread=false、jumpLayoutSeq++、
  // 取消高亮闪烁。留在页面，因为它碰的全是页面自己的跳转状态。
  prepareUserJump: () => void;
  // 回到最新消息。
  scrollToLatest: () => void;
  // 目标已在已加载列表里，直接滚过去（页面侧是 scroller.scrollToIndex(index,
  // false, ScrollAlign.START)）。
  scrollToIndex: (index: number) => void;
  // 落点高亮闪烁两下。
  flashAtIndex: (index: number) => void;
  // 目标不在当前窗口内，要先去取。**所有权裁决（B5）**：pendingJumpId 是整个
  // 跳转系统的共享字段（landPendingJump / openStoreForRoute /
  // resetOrPreserveScrollSession 都读写它），留在页面。页面侧在这里做
  // pendingJumpId = messageId + store.loadAround(...)，取不到时复位
  // pendingJumpId、调本控制器的 finishPinnedJump()、refreshPinned() 并弹提示。
  jumpToPinned: (messageId: number) => void;
}

@ObservedV2
export class LiveTopCardController {
  // ——— 显示态：TopBanners 直接读这些 @Trace ———

  @Trace pinnedPreview: string = '';
  @Trace pinnedCount: number = 0;
  @Trace pinnedLoadState: string = 'loading'; // loading | ready | error
  @Trace pinnedJumpBusy: boolean = false;
  // B5 更正：搬进来之前这条注释写的是「@Local: the segment indicator renders
  // from this — a plain field wouldn't trigger a re-render when
  // scrolling/tapping moves the shown pinned index.」。装饰器换成 @Trace，理由
  // 不变：分段指示器就是从它渲染的，普通字段在滚动/点击换页时不会触发重绘。
  // （搬之前它孤零零声明在页面的另一处、与其余 pinned 字段隔了 170 行，这里
  // 归位到同一块。）
  @Trace pinnedCycle: number = 0;
  // 正在直播入口条:chat.video_chat.group_call_id > 0 时显示("正在直播").
  @Trace liveGroupCallId: number = 0;
  @Trace liveCallIsActive: boolean = false;
  @Trace liveCallIsRtmp: boolean = false;
  @Trace liveParticipantCount: number = 0;
  @Trace livePulseExpanded: boolean = false;
  @Trace liveLoadState: string = 'loading'; // loading | ready | error
  @Trace liveDialogOpening: boolean = false;
  @Trace liveNavigationBusy: boolean = false;
  @Trace topCardLoadingVisible: boolean = false;

  // ——— 内部机件：一律**不加 @Trace** ———
  // 定时器句柄、在途标志、序号守卫都不驱动任何 UI，加了 @Trace 只会在每次
  // setInterval/清标志时白发一轮通知。这与 FloatingDateState 里 hideTimer /
  // armedAt 用普通字段是同一条惯例。

  private livePulseTimer: number = -1;
  private liveStateRefreshTimer: number = -1;
  private liveChatRefreshInFlight: boolean = false;
  private liveGroupRefreshInFlight: boolean = false;
  private liveChatResolveSeq: number = 0;
  private liveGroupResolveSeq: number = 0;
  private liveGroupRequestId: number = 0;
  private topCardLoadingTimer: number = -1;
  private topCardActionTimer: number = -1;

  // 未 bind 时的空宿主：字段类型非空，且控制器在 aboutToAppear 之前就已经被
  // 构造出来（页面的字段初始化器 new）。取值器返回的都是「什么都还没有」的值，
  // 与页面同名字段的初值一致。
  private host: LiveTopCardHost = {
    chatId: (): number => 0,
    threadRootId: (): number => 0,
    title: (): string => '',
    store: (): MessageStore | null => null,
    groups: (): AlbumGroup[] => [],
    curStartIdx: (): number => -1,
    prepareUserJump: (): void => {},
    scrollToLatest: (): void => {},
    scrollToIndex: (_index: number): void => {},
    flashAtIndex: (_index: number): void => {},
    jumpToPinned: (_messageId: number): void => {}
  };

  // ChatPage.aboutToAppear 里调一次。
  bind(host: LiveTopCardHost): void {
    this.host = host;
  }

  // ——— 生命周期 ———

  // 两个 setInterval 的注册点。搬之前它们在 applyRouteParams 阶段 A 的
  // subscribeLiveCallUpdatesAndTimers() 末尾，紧跟在 'videoChat' / 'groupCall'
  // 两个 TDLib 订阅之后；页面在原位置调 open()，注册时机不变。
  // 两个订阅本身留在页面：它们要 set 进页面的 subscriptions 表，由
  // disposeSubscriptionsInOrder 按既定顺序摘除。
  //
  // 与 applyRouteParams 一样，本方法依赖 beginRouteApply() 的一次性守卫——每个
  // ChatPage 实例只会走到这里一次。句柄不做重入保护是搬之前的原样。
  open(): void {
    this.livePulseTimer = setInterval((): void => {
      if (!this.liveCallIsActive || !powerFeatureEnabled(KEY_POWER_PARTICLES)) {
        this.livePulseExpanded = false;
        return;
      }
      this.livePulseExpanded = !this.livePulseExpanded;
    }, 780);
    // Updates remain the fast path. Polling is a small safety net for devices
    // that resume this cached page after an update was delivered while its
    // subscriptions were inactive.
    this.liveStateRefreshTimer = setInterval((): void => {
      this.refreshVideoChat();
    }, 2000);
  }

  // 页面从后台/被遮挡回到前台。搬之前这是 handleShown 交给
  // coordinateChatPageShown 的 clearLiveNavigationBusy 钩子（在 util 里它是倒数
  // 第二步，之后才是 chatId>0 时的 refreshVideoChat；那个 chatId 判定留在 util，
  // 不属于本簇）。
  // 路由忙标志必须在这里清：进直播页再返回时，busy 是在离开前置上的，回来时那
  // 次导航早已结束，不清就会把横幅永久钉成「不可点」。
  // 注意：handleHidden / handleWillHide 一个字都不碰本簇，所以这里没有对应的
  // onPageHidden()。
  onPageShown(): void {
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
  }

  // ChatPage.aboutToDisappear 调用，放在原来清 live*/topCard* 字段的位置
  // （disposeTimersAndSeqGuards）。
  //
  // 顺序照搬 aboutToDisappear：两个 seq++ 在最前（作废在途的 getChat /
  // getGroupCall），再清在途标志与忙标志，最后才清定时器句柄。
  // 唯一的合并：两个 setInterval 搬之前是在 teardown 最后一步 closeStores 里清
  // 的，现在提前到这里一并清。中间隔着的 stopVoicePlaybackKeepingMusic 与
  // disposeSubscriptionsInOrder 都不 await，定时器插不进去，时序等价。
  dispose(): void {
    this.liveChatResolveSeq++;
    this.liveGroupResolveSeq++;
    this.liveChatRefreshInFlight = false;
    this.liveGroupRefreshInFlight = false;
    this.liveGroupRequestId = 0;
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
    this.pinnedJumpBusy = false;
    this.topCardLoadingVisible = false;
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
      this.topCardLoadingTimer = -1;
    }
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
      this.topCardActionTimer = -1;
    }
    if (this.livePulseTimer !== -1) { clearInterval(this.livePulseTimer); this.livePulseTimer = -1; }
    if (this.liveStateRefreshTimer !== -1) {
      clearInterval(this.liveStateRefreshTimer);
      this.liveStateRefreshTimer = -1;
    }
  }

  // ——— 卡片整体 ———

  resetTopCardState(): void {
    this.liveChatResolveSeq++;
    this.liveGroupResolveSeq++;
    this.pinnedPreview = '';
    this.pinnedCount = 0;
    this.pinnedCycle = 0;
    this.pinnedLoadState = this.host.threadRootId() > 0 ? 'ready' : 'loading';
    this.pinnedJumpBusy = false;
    this.liveGroupCallId = 0;
    this.liveCallIsActive = false;
    this.liveCallIsRtmp = false;
    this.liveParticipantCount = 0;
    this.livePulseExpanded = false;
    this.liveLoadState = 'loading';
    this.liveDialogOpening = false;
    this.liveNavigationBusy = false;
    this.liveChatRefreshInFlight = false;
    this.liveGroupRefreshInFlight = false;
    this.liveGroupRequestId = 0;
    this.topCardLoadingVisible = false;
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
    }
    this.topCardLoadingTimer = setTimeout((): void => {
      this.topCardLoadingTimer = -1;
      this.topCardLoadingVisible =
        this.pinnedLoadState === 'loading' || this.liveLoadState === 'loading';
    }, powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, TOP_CARD_LOADING_DELAY_MS));
  }

  settleTopCardLoading(): void {
    if (this.pinnedLoadState === 'loading' || this.liveLoadState === 'loading') {
      return;
    }
    if (this.topCardLoadingTimer !== -1) {
      clearTimeout(this.topCardLoadingTimer);
      this.topCardLoadingTimer = -1;
    }
    this.topCardLoadingVisible = false;
  }

  // 搬之前叫 topCardShouldShow()。名字里的 topCard 前缀在控制器上是重复的，
  // 按 B5 约定改叫 shouldShow()；判据一字未动。
  shouldShow(): boolean {
    // Pinned/live information is optional chrome. If its background probe
    // fails while TDLib is reconnecting and there is no confirmed content,
    // don't turn that transient transport problem into a persistent banner.
    return this.pinnedPreview !== '' ||
      (this.liveGroupCallId > 0 && this.liveCallIsActive) ||
      this.topCardLoadingVisible;
  }

  // ——— 置顶条：订阅入口 ———

  // 搬之前是 registerHeaderDerivedSubscriptions 里 store.subscribePinned 的回调体。
  // 三个值由页面在回调里从**那个具体的 MessageStore 实例**（订阅时的形参 store，
  // 不是 this.store）现取后传进来——控制器不去猜数据源是谁。
  applyPinned(preview: string, count: number, loadState: string): void {
    this.pinnedPreview = preview;
    this.pinnedCount = count;
    this.pinnedLoadState = loadState;
    this.pinnedCycle = Math.min(this.pinnedCycle, Math.max(0, this.pinnedCount - 1));
    if (this.pinnedCount === 0) {
      this.pinnedCycle = 0;
      this.finishPinnedJump();
    }
    this.settleTopCardLoading();
  }

  // ——— 直播条：拉取与身份守卫 ———

  // Resolve chat.video_chat first, then the referenced group call. Sequence
  // guards make a late response from a previous call/chat unable to restore a
  // banner that has already ended or changed identity.
  refreshVideoChat(showLoading: boolean = false): void {
    if (this.host.chatId() === 0) {
      this.liveLoadState = 'error';
      this.settleTopCardLoading();
      return;
    }
    if (this.liveChatRefreshInFlight) {
      return;
    }
    this.liveChatRefreshInFlight = true;
    const seq: number = ++this.liveChatResolveSeq;
    if (showLoading && !this.liveCallIsActive) {
      this.liveLoadState = 'loading';
    }
    const req: TdRequest = { '@type': 'getChat' };
    req['chat_id'] = this.host.chatId();
    getTdClient().send(req).then((chat: TdObject): void => {
      if (seq !== this.liveChatResolveSeq) {
        return;
      }
      this.liveChatRefreshInFlight = false;
      this.liveLoadState = 'ready';
      const vc = chat['video_chat'] as TdObject | undefined;
      this.setLiveGroupCallId(vc !== undefined ? ((vc['group_call_id'] as number | undefined) ?? 0) : 0);
      this.settleTopCardLoading();
    }).catch((e: TdError): void => {
      if (seq !== this.liveChatResolveSeq) {
        return;
      }
      this.liveChatRefreshInFlight = false;
      // A transient refresh failure must not invalidate an active call already
      // confirmed by ChatStore/updateGroupCall.
      if (!this.liveCallIsActive) {
        this.liveLoadState = 'error';
      }
      this.settleTopCardLoading();
      logE(`ChatPage.refreshVideoChat getChat failed: ${e.message}`);
    });
  }

  setLiveGroupCallId(groupCallId: number): void {
    const changed = groupCallId !== this.liveGroupCallId;
    if (changed) {
      this.liveGroupResolveSeq++;
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      this.liveGroupCallId = groupCallId;
      this.liveCallIsActive = false;
      this.liveCallIsRtmp = false;
      this.liveParticipantCount = 0;
      this.livePulseExpanded = false;
    }
    if (groupCallId <= 0) {
      this.liveLoadState = 'ready';
      this.settleTopCardLoading();
      return;
    }
    // An unchanged id still needs refreshing because a scheduled call may
    // become active (or an active call end) without changing its identifier.
    if (this.liveGroupRefreshInFlight && this.liveGroupRequestId === groupCallId) {
      return;
    }
    const seq: number = ++this.liveGroupResolveSeq;
    this.liveGroupRefreshInFlight = true;
    this.liveGroupRequestId = groupCallId;
    if (!this.liveCallIsActive) {
      this.liveLoadState = 'loading';
    }
    const request: TdRequest = { '@type': 'getGroupCall' };
    request['group_call_id'] = groupCallId;
    getTdClient().send(request).then((groupCall: TdObject): void => {
      if (seq !== this.liveGroupResolveSeq || this.liveGroupCallId !== groupCallId) {
        return;
      }
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      this.applyLiveGroupCall(groupCall);
    }).catch((error: TdError): void => {
      if (seq !== this.liveGroupResolveSeq || this.liveGroupCallId !== groupCallId) {
        return;
      }
      this.liveGroupRefreshInFlight = false;
      this.liveGroupRequestId = 0;
      if (!this.liveCallIsActive) {
        this.liveLoadState = 'error';
      }
      this.settleTopCardLoading();
      logE(`ChatPage.getGroupCall failed: ${error.message}`);
    });
  }

  // ── 推送到达时的两个入口：先作废在途请求，再应用推送内容 ──────────────
  //
  // 【为什么必须由控制器提供入口，而不是让页面直接写字段】
  // 这两组 seq/in-flight 是**并发守卫**：横幅的状态有两条来源——TDLib 主动推送
  // （快）与我们自己发出的 getChat/getGroupCall（慢）。推送先到时，那趟还没回来的
  // 请求带的是**更旧**的快照；不把 seq 自增作废掉，它回来时 seq 仍然匹配，就会把
  // 刚被推送更新的横幅**覆盖回旧值**；in-flight 标志不复位还会短暂挡掉下一次
  // refresh。seq 与 in-flight 都是本类 private，所以只能由本类提供入口——页面
  // 直接写字段的写法在搬进控制器之后已经不成立了。
  applyVideoChatUpdate(groupCallId: number): void {
    this.liveChatResolveSeq++;
    this.liveChatRefreshInFlight = false;
    this.liveLoadState = 'ready';
    this.setLiveGroupCallId(groupCallId);
    this.settleTopCardLoading();
  }

  applyGroupCallUpdate(groupCall: TdObject): void {
    this.liveGroupResolveSeq++;
    this.liveGroupRefreshInFlight = false;
    this.liveGroupRequestId = 0;
    this.applyLiveGroupCall(groupCall);
  }

  applyLiveGroupCall(groupCall: TdObject): void {
    this.liveCallIsActive = (groupCall['is_active'] as boolean | undefined) ?? false;
    this.liveCallIsRtmp = (groupCall['is_rtmp_stream'] as boolean | undefined) ?? false;
    this.liveParticipantCount = (groupCall['participant_count'] as number | undefined) ?? 0;
    this.liveLoadState = 'ready';
    if (!this.liveCallIsActive) {
      this.livePulseExpanded = false;
      this.liveDialogOpening = false;
    }
    this.settleTopCardLoading();
  }

  // ChatStore already resolves updateChatVideoChat + updateGroupCall for the
  // chat list. Reuse that confirmed state as the fast path when entering or
  // resuming a chat instead of hiding the live banner until a second
  // getChat/getGroupCall round trip finishes. The direct probe below remains
  // authoritative and will still remove a call once TDLib confirms it ended.
  syncLiveFromChatEntry(entry: ChatEntry): void {
    if (entry.liveGroupCallId <= 0) {
      // A cache miss is not proof that a call ended: getChat may already have
      // found a newer call which hasn't reached ChatStore yet.
      return;
    }
    if (entry.liveGroupCallId !== this.liveGroupCallId) {
      this.setLiveGroupCallId(entry.liveGroupCallId);
    }
    if (!entry.isLive || entry.liveGroupCallId !== this.liveGroupCallId) {
      return;
    }
    this.liveCallIsActive = true;
    this.liveCallIsRtmp = entry.isRtmpLive;
    this.liveLoadState = 'ready';
    this.settleTopCardLoading();
  }

  // ——— 直播条：进入 ———

  private enterLiveStream(groupCallId: number): void {
    if (this.liveNavigationBusy) {
      return;
    }
    if (groupCallId <= 0 || groupCallId !== this.liveGroupCallId ||
      !this.liveCallIsActive || this.liveLoadState === 'error') {
      promptAction.showToast({ message: $r('app.string.cp_live_ended'), duration: 1500 });
      return;
    }
    const isRtmp: boolean = this.liveCallIsRtmp;
    const params: Record<string, Object> = {
      'groupCallId': groupCallId,
      'chatId': this.host.chatId(),
      'initialTitle': this.host.title(),
      'initialParticipantCount': this.liveParticipantCount
    };
    this.liveNavigationBusy = true;
    // Returning to the live stream that is already floating must hand the
    // existing Session back to the viewer. Closing it here would briefly leave
    // the call and force the page to join again.
    if (floatingLiveWindow.isShowing(groupCallId, isRtmp)) {
      floatingLiveWindow.restoreFullPage().finally((): void => {
        this.liveNavigationBusy = false;
      });
      return;
    }
    floatingLiveWindow.prepareForOpeningFullPage().finally((): void => {
      if (groupCallId !== this.liveGroupCallId || !this.liveCallIsActive) {
        this.liveNavigationBusy = false;
        promptAction.showToast({ message: $r('app.string.cp_live_ended'), duration: 1500 });
        return;
      }
      router.pushUrl({
        url: isRtmp
          ? 'pages/chat/RtmpLiveStreamViewerPage' : 'pages/chat/LiveStreamViewerPage',
        params: params
      }).then((): void => {
        // Busy only represents the route transition. Joining/recovery status
        // belongs to the viewer and must not leak into the chat banner.
        this.liveNavigationBusy = false;
      }).catch((error: Error): void => {
        this.liveNavigationBusy = false;
        logE(`ChatPage.enterLiveStream failed: ${error.message}`);
        promptAction.showToast({ message: $r('app.string.cp_live_join_failed'), duration: 1600 });
      });
    });
  }

  // All live entry points confirm before joining. The viewer itself joins
  // muted, so the dialog can state the privacy behavior precisely.
  onLiveStreamTap(): void {
    if (this.liveDialogOpening || this.liveNavigationBusy) {
      return;
    }
    if (this.liveLoadState === 'loading') {
      promptAction.showToast({ message: $r('app.string.cp_live_syncing'), duration: 1200 });
      return;
    }
    if (this.liveLoadState === 'error') {
      this.refreshVideoChat(true);
      promptAction.showToast({ message: $r('app.string.cp_live_refetching'), duration: 1200 });
      return;
    }
    if (this.liveGroupCallId <= 0 || !this.liveCallIsActive) {
      promptAction.showToast({ message: $r('app.string.cp_live_ended'), duration: 1500 });
      return;
    }
    const groupCallId = this.liveGroupCallId;
    const onlineText = this.liveParticipantCount > 0 ? plural('cp_live_online_now', this.liveParticipantCount, this.liveParticipantCount) : '';
    // str(), not $r(): this is concatenated into the dialog's message below, and
    // a Resource in a template literal stringifies to "[object Object]".
    const privacyText: string = this.liveCallIsRtmp
      ? str('cp_live_one_way_body')
      : str('cp_live_two_way_body');
    this.liveDialogOpening = true;
    promptAction.showDialog({
      title: $r('app.string.cp_live_join_title'),
      message: `${onlineText}${privacyText}`,
      buttons: [
        { text: $r('app.string.cancel'), color: '#8E8E93' },
        { text: $r('app.string.cp_live_join'), color: '#FF405C' }
      ]
    }).then((result): void => {
      this.liveDialogOpening = false;
      if (result.index === 1) { this.enterLiveStream(groupCallId); }
    }).catch((error: Object): void => {
      this.liveDialogOpening = false;
      logE(`ChatPage live confirmation failed: ${JSON.stringify(error)}`);
    });
  }

  // ——— 置顶条：跟随滚动 / 点击 ———

  // The banner tracks the scroll position: it shows the newest pinned message
  // strictly ABOVE the viewport top (the one a tap would jump to). Scrolling
  // past a pinned message therefore switches the banner to its neighbor, and
  // after a tap-jump lands this naturally advances to the next older one.
  updatePinnedFromScroll(start: number): void {
    const store: MessageStore | null = this.host.store();
    const groups: AlbumGroup[] = this.host.groups();
    if (store === null || this.pinnedCount === 0 || start < 0 || start >= groups.length) {
      return;
    }
    const ids: number[] = store.getPinnedIds(); // newest → oldest
    const previews: string[] = store.getPinnedPreviews();
    const topId: number = groups[start].head.id;
    let idx = -1;
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] < topId) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      idx = ids.length - 1; // viewport is above every pinned message → nearest is the oldest
    }
    if (idx !== pinnedShownIndex(this.pinnedCycle, this.pinnedCount)) {
      this.pinnedCycle = idx;
      if (idx < previews.length) {
        this.pinnedPreview = previews[idx];
      }
    }
  }

  // Tap the pinned banner: jump to the pinned message it currently shows.
  // Once at/above the oldest pinned message, tapping wraps back to the bottom.
  onPinnedTap(): void {
    const store = this.host.store();
    if (store === null) {
      return;
    }
    // groups / curStartIdx 一次取出：搬之前它们是 this.groups / this.curStartIdx，
    // 同一次点击里读几次都是同一个值，这里保持同样的读取次数语义。
    const groups: AlbumGroup[] = this.host.groups();
    const curStartIdx: number = this.host.curStartIdx();
    // 这一下该做什么，判定在 util/pinnedJump（10 条测）——尤其是"转到最后
    // 一条且已经滚过它就循环回最新"那条规则。
    const action: PinnedTap = pinnedTapAction({
      busy: this.pinnedJumpBusy,
      loadState: this.pinnedLoadState,
      pinnedIds: store.getPinnedIds(),
      cycle: this.pinnedCycle,
      topVisibleId: curStartIdx >= 0 && curStartIdx < groups.length
        ? groups[curStartIdx].head.id : 0
    }, (messageId: number): number => groupIndexOf(groups, messageId));

    if (action.kind === PINNED_IGNORE) {
      return;
    }
    if (action.kind === PINNED_RETRY) {
      store.refreshPinned();
      promptAction.showToast({ message: $r('app.string.cp_resyncing_pinned'), duration: 1200 });
      return;
    }
    if (action.kind === PINNED_EMPTY) {
      this.pinnedPreview = '';
      this.pinnedCount = 0;
      return;
    }
    this.startPinnedJumpGuard(2500);
    this.host.prepareUserJump();
    if (action.kind === PINNED_LATEST) {
      this.host.scrollToLatest();
      this.startPinnedJumpGuard(TOP_CARD_ACTION_GUARD_MS);
      return;
    }
    if (action.kind === PINNED_JUMP) {
      this.host.scrollToIndex(action.index);
      this.host.flashAtIndex(action.index);
      this.startPinnedJumpGuard(TOP_CARD_ACTION_GUARD_MS);
      return;
    }
    // PINNED_LOAD 兜底分支。B5 所有权裁决：pendingJumpId + store.loadAround 那
    // 一段留在页面（pendingJumpId 是跳转系统的共享字段），控制器只发出请求。
    // 上面那道 2500ms 的 busy 守卫比另两支的 TOP_CARD_ACTION_GUARD_MS 长，就是
    // 为了等这趟异步 loadAround。
    const targetId: number = action.targetId;
    this.host.jumpToPinned(targetId);
  }

  private startPinnedJumpGuard(duration: number): void {
    this.pinnedJumpBusy = true;
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
    }
    this.topCardActionTimer = setTimeout((): void => {
      this.topCardActionTimer = -1;
      this.pinnedJumpBusy = false;
    }, duration);
  }

  // 与 startPinnedJumpGuard 共用 topCardActionTimer，所以两个方法必须一起搬——
  // 定时器留在页面而方法搬走就会出现悬空清理。
  // 簇外还有两个调用者：landPendingJump（跳转落地）与 subscribePinned 回调
  // （置顶清空时，现在走 applyPinned），页面侧改调 this.topCard.finishPinnedJump()。
  //
  // 注意 resetTopCardState **不**清 topCardActionTimer（它只清
  // topCardLoadingTimer）——这是搬之前就有的语义差异，两条定时器互不交叉，
  // 原样保留。
  finishPinnedJump(): void {
    this.pinnedJumpBusy = false;
    if (this.topCardActionTimer !== -1) {
      clearTimeout(this.topCardActionTimer);
      this.topCardActionTimer = -1;
    }
  }
}
