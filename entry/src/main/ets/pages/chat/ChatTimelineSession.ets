import { PreparedMessageKeyCache } from '../../util/preparedMessageKeyCache';
import { OneShotFrameCallback as ChatPageFrameCallback } from '../../util/oneShotFrameCallback';
import { initialMessageViewportRows, nextInitialMessageRevealCount, stageInitialMessageGroups, initialTailRevealTarget } from '../../util/initialMessageStage';
import { ANCHOR_UNREAD, InitialAnchor, initialAnchorOf } from '../../util/initialAnchor';
import { ScrollAnchorController } from './ScrollAnchorController';
import { shouldFillViewport } from '../../util/viewportFill';
import { newerPageIsUserDriven } from '../../util/appendAnchor';
import { initialAvatarPaths, warmSenderAvatars } from '../../util/avatarWarm';
import { noteScrollPlaceholderMotion, setScrollActive } from '../../util/scrollEffects';
import { formatDateSeparator } from '../../util/formatDateSeparator';
import { MessageStore, MESSAGE_WINDOW_CAP } from '../../store/MessageStore';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleRenderData } from './ReusableMessageBubble';
import { PlaySlotDriver } from './PlaySlotDriver';
import { ChatBackgroundState } from '../../store/ChatBackgroundStore';
import { MusicQueue } from '../../services/MusicQueue';
import { AlbumGroupDataSource, clampPrefetchRange, PrefetchRange, rowIdentity, repeatRowKey, reuseUnchangedRows, sameRowArray } from './AlbumGroupDataSource';
import { BasicPrefetcher, UIContext } from '@kit.ArkUI';
import { HeaderIdentitySession } from './HeaderIdentitySession';
import { FloatingDateState } from './FloatingDateOverlay';
import { firstRowBelowChrome, floatDateNeedsRescan, floatDateScrollMovedEnough } from '../../util/floatDateGate';
import { isInteriorRowRemoval } from '../../util/rowRemoval';
import { AT_BOTTOM_KEEP, AT_BOTTOM_YES, atBottomVerdict } from '../../util/atBottom';
import { stackFromEndWanted } from '../../util/stackFromEnd';
import { messageSelectionContentWidth } from '../../util/messageSelection';
import { groupIndexOf, AlbumGroup, RunHeadHints } from '../../util/collapseAlbums';
import { planEdgeSpliceRows, EdgeSplicePlan, patchIndicesAfterPrepend, SPLICE_PUBLISH_ENABLED, SPLICE_PATCH_PUBLISH_ENABLED, PUBLISH_DUPLICATE_SCAN, DuplicateRowReport, findDuplicateIdentities } from '../../util/splicePublish';
import { PrependChunker, PREPEND_CHUNK_ENABLED } from '../../util/prependChunker';
import { RowFadeTransition, initialRowRevealDelay, rowFadeAnimationActive, rowFadeTransition } from '../../util/rowFadeGate';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { LiveTopCardController } from './LiveTopCardController';
import { SelectionSession } from './SelectionSession';
import { TranslationDriver } from './TranslationDriver';
import { JumpFlashState } from './JumpFlashState';
import { audioQueueApplies } from '../../util/audioQueueGate';
import { MediaWindow, VisibleRange, mediaWindowRange, visibleRangeOrFallback } from '../../util/visibleWindow';
import { albumReuseShape, rowPlaySlotKey } from '../../util/messageBubblePrepare';
import { RowPageInputs } from '../../util/rowPageInputs';
import { logE, logW } from '../../util/log';
import { reachedNewerPageTrigger, armedPageGate, canFirePageGate, draggedPageGate, firedPageGate, PageGate, pageGateShotIsUserDriven } from '../../util/pageGate';
import { conversationScopeId } from '../../util/messageTopicScope';
import { canRenderLightweightPlainTextRow } from '../../util/messageBubbleReuse';
import { ChatTimelineSnapshot, coalesceChatTimelineSnapshot, emptyChatTimelineSnapshot } from '../../util/chatTimelineSnapshot';
import { ChatViewportGeometry } from '../../util/chatViewportGeometry';
import { INITIAL_TIMELINE_REVEAL_ROW_LIMIT, INITIAL_TIMELINE_ROW_FADE_MS, INITIAL_TIMELINE_ROW_STAGGER_MS, PREPARED_MESSAGE_CACHE_LIMIT, INITIAL_BOTTOM_PRESENT_MIN_MS, INITIAL_MESSAGE_RELEASE_DELAY_MS, INITIAL_MESSAGE_TRANSITION_SETTLE_MS, INITIAL_TIMELINE_PRESENT_MIN_MS } from '../../util/chatPageTuning';
import { OLDER_TRIGGER_ROWS, olderTriggerHit } from '../../util/olderPaging';

export interface ChatTimelineBindings {
  scheduleComposerEditorMount: () => void;
  syncChatTgsGate: () => void;
  getUIContext: () => UIContext;
  screenH: () => number;
  bottomChromeH: () => number;
  store: () => MessageStore | null;
  isGroup: () => boolean;
  isChannel: () => boolean;
  chatId: () => number;
  threadRootId: () => number;
  forumTopicId: () => number;
  directMessagesTopicId: () => number;
  screenW: () => number;
  langEpoch: () => number;
  pendingJumpId: () => number;
  playSlotKey: () => string;
  playSlotStartMs: () => number;
  nowSec: () => number;
  chatBg: () => ChatBackgroundState;
  header: () => HeaderIdentitySession;
  translateChatsEnabled: () => boolean;
  listCachedCount: () => number;
  imeTailPinned: () => boolean;
  selection: SelectionSession;
  musicQueue: MusicQueue;
  playSlot: PlaySlotDriver;
  translation: TranslationDriver;
  topCard: LiveTopCardController;
  flash: JumpFlashState;
  headerChromeHeight: () => number;
  viewerOpen: () => boolean;
  jumpLandingHolding: () => boolean;
  syncReturnState: () => void;
  markVisibleRead: (end: number) => void;
  closeBottomPanels: () => void;
  dismissKeyboardOnUserScroll: () => void;
  capMessageReuseBuckets: () => void;
  cancelImeFollow: () => void;
}

export interface PreparedMessageBubble {
  group: AlbumGroup;
  data: MessageBubbleRenderData;
}

// 裁剪时可见区两侧至少保留的行数。必须远大于 List 的 cachedCount，否则会把
// 框架正预备的缓存行删掉，滑回去就是一片空白。
const TRIM_MIN_MARGIN_ROWS: number = 60;

// 攒到这个行数才动手裁剪，砍到 MESSAGE_WINDOW_CAP 为止。
//
// 【为什么需要滞后】第一版是"超过 400 就砍到可见区+两侧余量(~225)"，只剩
// 175 行余量。真机实测（2026-09-10）这会变成踏步：往下翻 54 秒里
// **14 次 onHistory kind=newer（每次 30 条）+ 2 次裁剪**——刚扔掉的历史立刻
// 又被一页页拉回来，每页都要重建实体 + 发布一次。用户报的"上翻结束后往下
// 翻时卡"就是它。
//
// 【触发线必须跟着上限一起降】决定卡顿的是**峰值**不是均值：触发线是多少，
// 一次发布最贵的时候就有多少行。第一版 800 触发 / 400 目标时，真机 avgRows
// 稳在 512、峰值 984，用户的观感是"根本没砍"——因为绝大多数时间窗口就是
// 四五百行。
//
// 500 触发 / 200 目标 = 300 行余量。峰值 500 行时一次发布约 6ms（1930 行时
// 是 57ms），余量仍是第一版"400 触发/砍到 225"那个踏步版本的近两倍。
const TRIM_TRIGGER_ROWS: number = 500;

// 消息流的数据发布、行准备和视口状态。List/Repeat 的 UI 归 ChatTimelineHost。
// 跨域操作只接已有控制器或固定接口，不保存 ChatPage 实例。
interface InitialMessageStageTarget {
  anchorIndex: number;
  alignFromStart: boolean;
  availableRows: number;
}

type InitialMessageReleaseResult = 'released' | 'waiting' | 'finished';

@ObservedV2
export class ChatTimelineSession {
  private bindings: ChatTimelineBindings | null = null;
  private scrollWorkTimers: Set<number> = new Set<number>();
  private scrollWorkEpoch: number = 0;

  jumpLandingHolding(): boolean { return this.bindings!.jumpLandingHolding(); }

  bind(bindings: ChatTimelineBindings): void { this.bindings = bindings; }

  invalidateScrollWork(): void {
    this.scrollWorkEpoch++;
    this.scrollWorkTimers.forEach((timer: number): void => { clearTimeout(timer); });
    this.scrollWorkTimers.clear();
  }

  private scheduleScrollWork(task: () => void): void {
    const epoch: number = this.scrollWorkEpoch;
    const timer: number = setTimeout((): void => {
      this.scrollWorkTimers.delete(timer);
      if (epoch === this.scrollWorkEpoch) { task(); }
    }, 0);
    this.scrollWorkTimers.add(timer);
  }

  @Trace messages: MessageEntry[] = [];

  messageLoadState: string = 'loading'; // loading | ready | error

  messageLoadError: string = '';

  olderLoadState: string = 'idle'; // idle | loading | error | end

  newerLoadState: string = 'idle'; // idle | loading | error | end

  // **完整快照**的行数，不是当前渲染的行数——首屏分级渲染期间 groups 里坐着
  // 占位副本，长度一样，所以两者此刻仍然相等；将来若有别的分级形状，这个计数
  // 要跟着"用户最终会看到多少行"走。它驱动的是空/加载中的时间线提示。
  visibleGroupCount: number = 0;

  // 消息列表的内部真相。Repeat 和 MediaViewerOverlay 不直接订阅这个普通字段；
  // publishGroupsNow 把它连同加载/分页状态一次性装进 timelineSnapshot 发布。
  groups: AlbumGroup[] = [];

  // Repeat 的数据源。**与 this.groups 逐项同对象**，区别只在更新方式：纯前插时
  // 在这同一个 @Trace 数组上 splice（让 MVCP 的"显示区外前插保位"真正触发），
  // 其余发布整份换引用。理由与真机对照见 util/splicePublish 文件头。
  @Trace timelineRows: AlbumGroup[] = [];

  @Trace timelineSnapshot: ChatTimelineSnapshot = emptyChatTimelineSnapshot();

  viewportGeometry: ChatViewportGeometry = new ChatViewportGeometry();

  // 只剩图片预取源，不再是列表的数据源（见 AlbumGroupDataSource 文件头）。
  groupsData: AlbumGroupDataSource = new AlbumGroupDataSource();

  // 强制整表重建用的纪元，进 rowKeyOf。Repeat 没有 LazyForEach 的 reload()——
  // 让每一行的 key 都改变就是它的等价物（官方：键值变化会触发页面刷新）。
  // 两个调用点：语言纪元变化、从后台回来的重新对齐。见 rebuildAllRows()。
  listRebuildEpoch: number = 0;

  // Repeat key identifies the logical row, not its current contents. Repeat
  // refreshes a stable-key node when its item object changes; using content or
  // album members here deletes the visible boundary row when an older page
  // completes an album, which makes List lose its position anchor.
  rowKeyOf: (g: AlbumGroup) => string = (g: AlbumGroup): string =>
    repeatRowKey(g, this.bindings!.langEpoch(), this.listRebuildEpoch);

  // 当过窗口首行的行。见 util/collapseAlbums 的 RunHeadHints——这是把「向上翻页」
  // 变成纯插入的另一半，另一半是首行日期胶囊按 hasMoreOlder 决定。
  //
  // 整表重建（rebuildAllRows）时清空：那时窗口本来就要全部删旧插新，没有
  // 「接缝」可言，留着只会让跳转落地后的中间行平白多一个昵称。
  stickyRunHeads: Set<number> = new Set<number>();

  // Whether this page is currently visible (between onPageShow and onPageHide),
  // and whether the list dataset changed while it was not.
  //
  // Notifications delivered while the page is hidden are the root of the
  // "messages scrambled after returning from the background" report. The store
  // keeps publishing while the app is backgrounded, so the data source keeps
  // emitting ADD/CHANGE — but a hidden List does not fully apply them: on the
  // device, "Use repeat key" warnings start the moment the page becomes visible
  // again, BEFORE any new notification, meaning the framework's key -> node
  // table came back from the hidden period already inconsistent. It then
  // re-associates recycled rows against that stale table: the newest rows are
  // freshly built and correct, the rows above them come back as some other
  // row's content. The data and the notifications are provably clean — the
  // snapshot duplicate scan and a mirrored key table both stayed silent while
  // the framework warned — so the fix is not to notify better but to stop
  // trusting the hidden-period bookkeeping: one RELOAD on return rebuilds the
  // framework's table from the (correct) dataset, and the viewport is restored
  // around the anchor row.
  pageVisible: boolean = true;

  // 头插分批（方案 A）：翻历史一次插 29 行会让 Repeat 把可视区整屏新建，这里把
  // 头插拆成每批不超过 List.cachedCount 行。逻辑全在 util/prependChunker。
  prependChunker: PrependChunker<AlbumGroup> = new PrependChunker<AlbumGroup>(
    (g: AlbumGroup): string => rowIdentity(g), PREPEND_CHUNK_ENABLED);

  hiddenListDirty: boolean = false;

  // ArkUI may ask the same visible/cache row to build again after unrelated
  // page state changes. Keep the immutable render bundle by row fingerprint
  // and the small set of dynamic inputs it actually consumes.
  private preparedKeyCache: PreparedMessageKeyCache = new PreparedMessageKeyCache();

  preparedMessageCache: Map<string, PreparedMessageBubble> =
    new Map<string, PreparedMessageBubble>();

  messageListRevision: number = 0;

  chatBackgroundRevision: number = 0;

  scroller: Scroller = new Scroller();

  didInitialScroll: boolean = false;

  // The initial LazyForEach still lays out while masked. Once a complete
  // viewport has real rows and its unread/bottom anchor has been applied, the
  // mask is removed in one frame. This prevents both row-by-row appearance and
  // a visible placeholder-height correction jump.
  @Trace initialTimelineMasked: boolean = false;

  // 首屏逐条淡入这条动画的时间戳闩，**故意不进状态**：它只被 build 读，
  // 自己变化不该引起重渲染（那正是要治的病）。见 util/rowFadeGate。
  initialRowFadeArmedAt: number = 0;

  chatTgsScrollActive: boolean = false;

  @Trace atBottom: boolean = true;

  firstUnreadId: number = 0;

  // Set once the initial scroll parks on the unread boundary; suppresses every
  // auto-scroll-to-bottom until the user first touches the list, so a short
  // unread run isn't glued past the divider by async in-place content growth.
  stayAtUnread: boolean = false;

  curStartIdx: number = -1; // topmost visible row index (from onScrollIndex)

  curEndIdx: number = -1;   // bottom visible row index (from onScrollIndex)

  // Cumulative signed sum of user-originated scroll frames. A history page can
  // land while the finger/fling is still moving; anchor restoration subtracts
  // the delta since capture so it fixes only data/layout movement and never
  // cancels the user's gesture. onWillScroll supplies the source, onDidScroll
  // supplies the actual applied offset.
  userScrollOffsetTotal: number = 0;

  nextDidScrollIsUserDriven: boolean = false;

  // A pending anchor correction yields while the list is still moving. This
  // keeps an in-flight page response from racing the active drag/fling.
  timelineScrollActive: boolean = false;

  // 新快照赋给父页面后，ChatTimelineHost/Repeat 要到后续布局帧才看见新长度。
  // 用代次合并贴底请求，避免每条更新都对旧 totalCount 执行 scrollEdge。
  bottomLayoutFollowSeq: number = 0;

  // 有一次贴底跟随排了还没点火。在途期间来的新消息要视为仍在底——那一刻
  // atBottom 是假的，是因为上一条还没贴过去，不是用户离开了底部
  //（判据与真机证据见 util/bottomFollow）。
  bottomFollowPending: boolean = false;

  // onScrollIndex 上报那一刻的 groups.length。行号只有配上它才有意义。
  indexGroupsLen: number = -1;

  // 视口最底下那条真实消息的 id。既是"当前位置"，也是跳走时要记下的返回点。
  curBottomId: number = 0;

  resumeDividerId: number = 0;

  // One-shot gate for loading older pages: a fast fling to the very top used to
  // chain-load page after page. A prepend itself moves start out of the trigger
  // zone, so re-arming there mistakes layout movement for user movement. Only a
  // new touch gesture (or the short-content fill path) re-arms this gate.
  olderArmed: boolean = true;

  // fillViewport 只解决首次内容短到无法滚动的场景。用户一旦实际碰过列表，后续
  // onScrollIndex 的瞬态全范围值不能再借它重新上膛，否则一次手势又会连灌多页。
  initialViewportFillEnabled: boolean = true;

  // Floating date chip: shows the topmost visible message's date while the
  // list scrolls, fades out shortly after scrolling stops (the in-list date
  // pills stay — this is the always-visible companion).
  //
  // 日期文字、显隐、820ms 隐藏定时器全部住在 FloatingDateOverlay 那边的
  // @ObservedV2 对象里。这里只留一个**普通私有字段**持有引用：ChatPage.build
  // 一个字都不读它，日期变化因此不再让整页重绘。
  floatDateState: FloatingDateState = new FloatingDateState();

  // 留在 ChatPage 的只有"顶行下标"——它是"要不要重新扫 groups 算日期"的判据，
  // 而 groups 是 ChatPage 的数据。同样是非响应式字段。
  floatDateIndex: number = -1;

  // 上一次 onScrollIndex 报的顶行下标（不是日期条认的那个）。日期条要量布局才
  // 知道哪一行真正露在标题栏下面，而 onDidScroll 每帧都来——下标没变就连量都
  // 不量，见 updateFloatDate。
  floatDateStartIdx: number = -1;

  // 上一次真正重算 chrome 跳过时的累计手势位移。与 floatDateStartIdx 一起
  // 构成那道早退闸的两个键（见 updateFloatDate）。
  floatDateScrollAt: number = 0;

  listTouchActive: boolean = false;

  listUserScrollActive: boolean = false;

  imagePrefetcher: BasicPrefetcher = new BasicPrefetcher(this.groupsData);

  runHeadHints(): RunHeadHints {
    const timelineStore: MessageStore | null = this.bindings!.store();
    const moreOlder: boolean = timelineStore !== null && timelineStore.getHasMoreOlder();
    return {
      moreOlderAbove: moreOlder,
      stickyRunHeads: this.stickyRunHeads,
      // 首屏还没落定、或者有待落地的跳转时不扣行——那两条路要按 groupIndexOf
      // 找目标，扣掉的成员会让它返回 -1。
      withholdPartialAlbum: moreOlder && this.didInitialScroll && this.bindings!.pendingJumpId() === 0
    };
  }

  // 发布之后记账：这一次的首行，下一次前插时就是接缝行。
  noteRunHead(groups: AlbumGroup[]): AlbumGroup[] {
    if (groups.length > 0) {
      this.stickyRunHeads.add(groups[0].head.rowId);
    }
    return groups;
  }

  timelineGeometryDividerId(): number {
    const timelineStore: MessageStore | null = this.bindings!.store();
    if (this.resumeDividerId > 0) {
      return this.resumeDividerId;
    }
    if (this.firstUnreadId > 0) {
      return this.firstUnreadId;
    }
    return timelineStore !== null ? timelineStore.getFirstUnreadId() : 0;
  }

  replaceTimelineGroups(groups: AlbumGroup[]): void {
    this.viewportGeometry.reconcile(
      this.bindings!.chatId(),
      conversationScopeId(this.bindings!.threadRootId(), this.bindings!.forumTopicId(), this.bindings!.directMessagesTopicId()),
      groups,
      this.bindings!.screenW(),
      this.bindings!.langEpoch(),
      this.timelineGeometryDividerId()
    );
    this.groups = groups;
    this.timelineRows = groups;
  }

  // 纯前插：在**同一个** @Local 数组上 splice，再把内容变了的旧行按下标原地换掉。
  // 之后 timelineRows 与 next 逐项同对象（不变量：与 this.groups 一致）。
  splicePrependGroups(next: AlbumGroup[], head: number): void {
    this.viewportGeometry.reconcile(
      this.bindings!.chatId(),
      conversationScopeId(this.bindings!.threadRootId(), this.bindings!.forumTopicId(), this.bindings!.directMessagesTopicId()),
      next,
      this.bindings!.screenW(),
      this.bindings!.langEpoch(),
      this.timelineGeometryDividerId()
    );
    const prev: AlbumGroup[] = this.groups;
    const patches: number[] = patchIndicesAfterPrepend(prev, next, head);
    this.timelineRows.splice(0, 0, ...next.slice(0, head));
    for (const i of patches) {
      this.timelineRows[i] = next[i];
    }
    this.groups = next;
    // 不变量：timelineRows 与 next **逐项同对象**。任何一处不同（漏行、重复行、
    // 旧对象残留）都退回整份替换——宁可丢一次保位，也不能让两份数组分叉。
    // O(n) 引用比较，和 reuseUnchangedRows 同量级。
    let mismatchAt: number = -1;
    if (this.timelineRows.length !== next.length) {
      mismatchAt = Math.min(this.timelineRows.length, next.length);
    } else {
      for (let i = 0; i < next.length; i++) {
        if (this.timelineRows[i] !== next[i]) {
          mismatchAt = i;
          break;
        }
      }
    }
    if (mismatchAt >= 0) {
      logW(`[SplicePublish] invariant broken at=${mismatchAt}` +
        ` rows=${this.timelineRows.length}/${next.length} head=${head}, fallback to replace`);
      this.timelineRows = next;
      return;
    }
  }

  // 等长原地补丁 / 尾部追加：数组引用**不动**，只按下标换对象、或在尾部 splice
  // 进新行。
  //
  // 【为什么这条路最值钱】首屏分帧揭示每帧只把一行从占位换成真行，行身份序列
  // 一个字都没变。旧代码认不出这个形状，退回 `this.timelineRows = groups`——换
  // 引用就等于给 @Local 发通知，ChatPage.build() 整个重跑（首屏 trace 抓到 11
  // 次 / 62.1ms，其中还连带 20+ 次 ResourceManager::GetXxxById）。换成原地赋值
  // 后，只有 Repeat 里那一个 RepeatItem 被通知。
  //
  // 不变量与 splicePrependGroups 相同：完事后 timelineRows 与 next 逐项同对象，
  // 不同就整份回退。
  spliceAppendGroups(next: AlbumGroup[], appended: number): void {
    this.viewportGeometry.reconcile(
      this.bindings!.chatId(),
      conversationScopeId(this.bindings!.threadRootId(), this.bindings!.forumTopicId(), this.bindings!.directMessagesTopicId()),
      next,
      this.bindings!.screenW(),
      this.bindings!.langEpoch(),
      this.timelineGeometryDividerId()
    );
    const prev: AlbumGroup[] = this.groups;
    for (let i = 0; i < prev.length; i++) {
      if (next[i] !== prev[i]) {
        this.timelineRows[i] = next[i];
      }
    }
    if (appended > 0) {
      this.timelineRows.splice(this.timelineRows.length, 0, ...next.slice(prev.length));
    }
    this.groups = next;
    let mismatchAt: number = -1;
    if (this.timelineRows.length !== next.length) {
      mismatchAt = Math.min(this.timelineRows.length, next.length);
    } else {
      for (let i = 0; i < next.length; i++) {
        if (this.timelineRows[i] !== next[i]) { mismatchAt = i; break; }
      }
    }
    if (mismatchAt >= 0) {
      logW(`[SplicePublish] ${appended > 0 ? 'append' : 'patch'} invariant broken` +
        ` at=${mismatchAt} rows=${this.timelineRows.length}/${next.length}` +
        ` appended=${appended}, fallback to replace`);
      this.timelineRows = next;
      return;
    }
  }

  // 窗口裁剪：从头或从尾砍掉若干行，同样在**同一个** @Local 数组上 splice，让
  // MVCP 的"显示区外删除保位"真正触发（整份换数组时它不认，12/30 次 Trim 顶行
  // MOVED 就是这么来的）。留下的行若内容变了（例如砍头后新首行拿到粘滞昵称），
  // 按下标原地换对象。不变量与 splicePrependGroups 相同：逐项同对象，否则回退。
  spliceDropGroups(next: AlbumGroup[], kind: string, count: number): void {
    this.viewportGeometry.reconcile(
      this.bindings!.chatId(),
      conversationScopeId(this.bindings!.threadRootId(), this.bindings!.forumTopicId(), this.bindings!.directMessagesTopicId()),
      next,
      this.bindings!.screenW(),
      this.bindings!.langEpoch(),
      this.timelineGeometryDividerId()
    );
    const prev: AlbumGroup[] = this.groups;
    if (kind === 'dropHead') {
      this.timelineRows.splice(0, count);
    } else {
      this.timelineRows.splice(this.timelineRows.length - count, count);
    }
    const offset: number = kind === 'dropHead' ? count : 0;
    let patched: number = 0;
    for (let i = 0; i < next.length; i++) {
      if (next[i] !== prev[offset + i]) {
        this.timelineRows[i] = next[i];
        patched++;
      }
    }
    this.groups = next;
    let mismatchAt: number = -1;
    if (this.timelineRows.length !== next.length) {
      mismatchAt = Math.min(this.timelineRows.length, next.length);
    } else {
      for (let i = 0; i < next.length; i++) {
        if (this.timelineRows[i] !== next[i]) { mismatchAt = i; break; }
      }
    }
    if (mismatchAt >= 0) {
      logW(`[SplicePublish] ${kind} invariant broken at=${mismatchAt}` +
        ` rows=${this.timelineRows.length}/${next.length} count=${count}, fallback to replace`);
      this.timelineRows = next;
      return;
    }
  }

  commitTimelineSnapshot(): void {
    const next: ChatTimelineSnapshot = coalesceChatTimelineSnapshot(this.timelineSnapshot, {
      hasVisibleRows: this.visibleGroupCount > 0,
      messageLoadState: this.messageLoadState, messageLoadError: this.messageLoadError,
      olderLoadState: this.olderLoadState, newerLoadState: this.newerLoadState,
      isChannel: this.bindings!.isChannel(), isGroup: this.bindings!.isGroup()
    });
    if (next !== this.timelineSnapshot) {
      this.timelineSnapshot = next;
    }
  }

  // 发布一份新的行快照。**唯一**给 this.groups 赋值的地方（rebuildAllRows 除外）。
  //
  // reuseUnchangedRows 是这里唯一的"聪明"步骤，理由写在它自己的注释里：
  // collapseAlbums 每次都产出全新对象，而 Repeat 按 item 引用判断要不要刷新，
  // 不还原没变过的行就等于每次发布都刷新整个可见窗口。
  publishGroupsNow(target: AlbumGroup[]): void {
    // 头插超过 List.cachedCount 行时只放出紧贴已显示内容的那一批，其余到点续发
    // （util/prependChunker）。下面整段拿到的就是这一批的快照，预取源与行数组同批推进。
    const groups: AlbumGroup[] = this.prependChunker.shape(this.groups, target);
    const next: AlbumGroup[] = reuseUnchangedRows(this.groups, groups);
    // 【顺序（2026-09-11，两次 jscrash 之后）】预取数据面**必须先于** UI 面更新。
    // splice 发布让 List 同步长行、同步回调 onScrollIndex；那时若 groupsData
    // 还是旧长度，BasicPrefetcher 内部的旧区间与新下标对不上，IndexRange 抛
    // "Invalid range"（jscrash 20260911100232 / 100238，均落在
    // handleTimelineScrollIndex 的 visibleAreaChanged）。新数组时代 Repeat 的更
    // 新经微任务延后，回调总在 setRows 之后到，所以从未撞上。
    //
    // ⚠️ 预取源拿的是 **groups（原始那份）**，不是 next（合并那份）——两者
    // 必须不同，这不是笔误。
    //
    // photoPaths / head.photoPath **刻意不进行 key**（collapseAlbums.ets 里
    // mutableSig 只带 photoFileId），因为缩略图落地要走 mediaThumbChannel 旁路
    // 直达气泡，不该拖着整行重建。代价是：缩略图/原图落地那一次发布里行 key
    // 一个字没变 ⇒ sameRenderSnapshot 为真 ⇒ reuseUnchangedRows 还回**上一份
    // 快照的对象** ⇒ 那一行的 photoPath 在 next 里**永远停在 ''**。
    //
    // 给 Repeat 用的 this.groups 必须是 next（对象身份不变才不会白刷新一整屏），
    // 但 AlbumGroupDataSource.imageRequestFor 是按 head.photoPath 决定预不预取的：
    // 喂它 next，它对这些行 `return null`，BasicPrefetcher 一次都不会预取——
    // 预取整条静默失效。所以数据面喂原始那份，UI 面喂合并那份。
    //
    // 这一行**在 changed 之外**，故意的：合并那份逐项相同（changed === false）
    // 恰恰是「只有旁路字段变了」的那次发布，而那正是预取源唯一需要的更新。
    this.groupsData.setRows(groups);
    const changed: boolean = !sameRowArray(this.groups, next);
    // 全等的一次发布不换数组引用：@Local 的通知是按引用发的，换一个逐项相同
    // 的新数组照样通知 ⇒ Repeat 照样跑一遍 diff。changed 本来就算好了，用上。
    if (changed) {
      // 删消息时让剩下的行平滑合拢（issue #149）。**只有这一种发布带动画**：
      // 判据见 util/rowRemoval —— 行变少、且少掉的那几行前后都还有行留着。
      // 往上翻页时从一头砍掉旧行同样是"行变少"，但那是滚动热路径，绝不能动画。
      // 判据只在行数变少时才跑，平时零成本。
      if (next.length < this.groups.length &&
        isInteriorRowRemoval(
          this.groups.map((g: AlbumGroup): number => g.head.id),
          next.map((g: AlbumGroup): number => g.head.id))) {
        animateTo({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
          curve: Curve.EaseOut
        }, (): void => {
          this.replaceTimelineGroups(next);
          this.commitTimelineSnapshot();
        });
      } else {
        // 对象优先的形状判定：只有对象不同的那几行才去算 rowIdentity
        // （原先每次发布都要拼 2N 个身份串，揭示期每帧一次）。
        const plan: EdgeSplicePlan | null = SPLICE_PUBLISH_ENABLED
          ? planEdgeSpliceRows(this.groups, next,
              (row: Object): string => rowIdentity(row as AlbumGroup))
          : null;
        const patchShape: boolean = plan !== null &&
          (plan.kind === 'patch' || plan.kind === 'append');
        // 临时探针：见 splicePublish 末尾。揭示期那种每帧一次的 patch 不扫。
        if (PUBLISH_DUPLICATE_SCAN && !(plan !== null && plan.kind === 'patch')) {
          this.reportDuplicateRows(next, plan === null ? 'replace' : plan.kind);
        }
        if (plan !== null && plan.kind === 'prepend') {
          this.splicePrependGroups(next, plan.count);
        } else if (patchShape && SPLICE_PATCH_PUBLISH_ENABLED) {
          this.spliceAppendGroups(next, plan!.count);
        } else if (plan !== null && !patchShape) {
          this.spliceDropGroups(next, plan.kind, plan.count);
        } else {
          this.replaceTimelineGroups(next);
        }
      }
    }
    if (!this.pageVisible && changed) {
      this.hiddenListDirty = true;
    }
    // Loading/paging flags and rows become visible to ChatTimelineHost through
    // one immutable publication, after this whole transaction is complete.
    this.commitTimelineSnapshot();
  }

  // 临时探针（2026-09-11）：发布的这一份里有没有两行同身份。见 splicePublish 末尾。
  reportDuplicateRows(rows: AlbumGroup[], kind: string): void {
    const dups: DuplicateRowReport[] = findDuplicateIdentities(
      rows, (row: Object): string => rowIdentity(row as AlbumGroup));
    for (const d of dups) {
      const a: AlbumGroup = rows[d.firstIndex];
      const b: AlbumGroup = rows[d.secondIndex];
      logW(`[DupRow] ${kind} rows=${rows.length} id=${d.identity}` +
        ` at=${d.firstIndex}/${d.secondIndex}` +
        ` msgIds=${a.head.id}/${b.head.id} rowIds=${a.head.rowId}/${b.head.rowId}` +
        ` albums=${a.head.albumId}/${b.head.albumId}` +
        ` members=${a.memberIds.length}/${b.memberIds.length}`);
    }
  }

  // 让 Repeat 整表重建：每一行的 key 都换掉。
  //
  // LazyForEach 时代这是 AlbumGroupDataSource.reload()（一条 RELOAD 通知）。
  // Repeat 没有对应的命令式接口，但官方写明「键值变化或数据变化均会触发页面
  // 刷新」，所以把纪元推进一格、再换一个新数组交出去，效果等价：所有 key 都变
  // 成新 key ⇒ 全部删旧插新。行对象本身原样复用，内容一个字都没动。
  rebuildAllRows(): void {
    this.listRebuildEpoch++;
    this.stickyRunHeads.clear();
    this.replaceTimelineGroups(this.groups.slice());
    this.commitTimelineSnapshot();
    // 这里**不碰** groupsData：它持有的是上一次发布的原始快照（见
    // publishGroupsNow 里那段注释），而 this.groups 是合并快照——photoPath 等
    // 旁路字段在它里面是陈旧的。整表重建只改 key 和数组身份、不改任何一行的
    // 内容，长度也不变，所以预取源保持指向那份更新的数据才是对的。
  }

  // 两个形状串的算法住在 util/messageBubblePrepare.ets（连同它们的【为什么】
  // 注释），由 entry/src/test/MessageBubblePrepare.test.ets 钉住。这里只剩最薄
  // 的一层：读 this.bindings!.playSlotKey() 传进去，不新建对象、不打日志——每行每帧各调
  // 一次，是消息行的热路径。
  albumReuseShape(g: AlbumGroup): string {
    return albumReuseShape(g, this.bindings!.playSlotKey());
  }

  rowPlaySlotKey(g: AlbumGroup): string {
    return rowPlaySlotKey(g, this.bindings!.playSlotKey());
  }

  // Prepare the row once for this build invocation. `data` used to repeat all
  // of these derived lookups independently for every visible row.
  prepareMessageBubble(g: AlbumGroup, pageInputs: RowPageInputs): PreparedMessageBubble {
    // 页面级输入一次读完（见 rowPageInputs：只收状态、且每行无条件读的那部分）。
    const page: RowPageInputs = pageInputs;
    // 行局部的播放位。起播位置同理：只有拥有播放位的那一行才谈得上续播位置，
    // 其余行给 0——否则它一变，整屏的缓存又一起作废。
    const rowSlot: string = rowPlaySlotKey(g, page.playSlotKey);
    const rowSlotStartMs: number = rowSlot === '' ? 0 : this.bindings!.playSlotStartMs();
    const paused: boolean = page.pausedIds.has(g.head.id);
    const forcePlay: boolean = page.forcedIds.has(g.head.id);
    const playbackFailed: boolean = page.failedIds.has(g.head.id);
    const audio: boolean = audioQueueApplies(g.head.contentType);
    const showUnreadDivider: boolean = this.firstUnreadId !== 0 &&
      g.memberIds.indexOf(this.firstUnreadId) >= 0;
    const showResumeDivider: boolean = this.resumeDividerId !== 0 &&
      g.memberIds.indexOf(this.resumeDividerId) >= 0;
    const showTimelineDivider: boolean = showUnreadDivider || showResumeDivider;
    const isPinnedMsg: boolean = (this.bindings!.store()?.getPinnedIds() ?? []).indexOf(g.head.id) >= 0;
    const paidMediaPending: boolean = page.paidMediaPendingIds.has(g.head.id);
    const editingActive: boolean = page.editingActive;
    const animateIn: boolean = page.freshSinceId !== 0 && g.head.id > page.freshSinceId;
    const liveGroupCallId: number = page.liveGroupCallId;
    const contentWidth: number = messageSelectionContentWidth(
      page.chatContentWidth, page.selectionActive, g.head.contentType);
    // 本行已选中的成员（相册逐格勾选用）。**只算本行**：把整个选择集放进 data
    // 会让每点一下就把所有行的 prepare 缓存键打翻。非多选态直接给空数组，
    // 平时零成本。
    const selectedMemberIds: number[] = page.selectionActive
      ? g.memberIds.filter((id: number): boolean => this.bindings!.selection.isMemberSelected(id))
      : [];
    // 【必须进 cacheKey】它决定 ReusableMessageBubble 派发到轻量气泡还是完整
    // 气泡，而**轻量那条不画表情行**。
    //
    // cacheKey 的其余部分全是「行身份 + 页面状态」——身份走 rowIdentity
    // （`message_${rowId}`），内容变化本来靠换 AlbumGroup 对象传递，不进键。
    // 可这一个是**从内容算出来的渲染决策**：不进键的话，给一条纯文本消息加上
    // 第一个表情时键一个字不变 ⇒ 命中缓存 ⇒ 派发冻在轻量那一支 ⇒ 表情要退出
    // 重进才出现（2026-09-11 真机定案：store / 旁路通道 / 气泡三处探针都显示
    // 数据已经到位，唯独派发走错了分支）。1→2 个表情不受影响，那时已在完整气泡里。
    //
    // 往这个键里加东西前先分清它属于哪一类：身份、页面状态、还是**从内容算出
    // 来的渲染决策**。第三类必须进。
    const lightweightRow: boolean = canRenderLightweightPlainTextRow(
      g.head, g.memberIds.length, g.photoPaths.length);
    // Read the same live decisions before the memo lookup. Only key assembly
    // is skipped; reuseId and the bounded prepared-result Map remain unchanged.
    const keyFlags: number = (lightweightRow ? 1 : 0) | (showUnreadDivider ? 2 : 0) |
      (showResumeDivider ? 4 : 0) |
      (isPinnedMsg ? 32 : 0) | (paidMediaPending ? 64 : 0) | (paused ? 128 : 0) |
      (forcePlay ? 256 : 0) | (playbackFailed ? 512 : 0) | (animateIn ? 1024 : 0);
    const cacheKey: string = this.preparedKeyCache.prepare(g, this.rowKeyOf(g),
      this.bindings!.chatId(), keyFlags, rowSlot, rowSlotStartMs,
      audio ? this.messageListRevision : 0, this.chatBackgroundRevision, contentWidth,
      selectedMemberIds, page.keyPart);
    const cached: PreparedMessageBubble | undefined = this.preparedMessageCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    // Queue lookup walks the loaded message list. It now runs only when an
    // audio row or the list revision genuinely changes, not on every page-wide
    // rerender of an otherwise stable cached row.
    const audioQueuePosition: number = audio
      ? this.bindings!.musicQueue.queuePosition(this.messages, g.head.id) : 0;
    const audioQueueLength: number = audio ? this.bindings!.musicQueue.queueLength(this.messages) : 0;
    const audioHasPrevious: boolean = audio
      ? this.bindings!.musicQueue.hasPrevious(this.messages, g.head.id) : false;
    const audioHasNext: boolean = audio
      ? this.bindings!.musicQueue.hasNext(this.messages, g.head.id) : false;
    // 与 cacheKey 里用的是同一个值（canRenderLightweightPlainText 只是把
    // context 的两个计数转发给 …Row，结果必然一致），别再算第二遍。
    const lightweightPlainText: boolean = lightweightRow;
    const data: MessageBubbleRenderData = {
      chatId: this.bindings!.chatId(), contentWidth, isGroup: page.isGroup, isChannel: page.isChannel,
      canReply: page.canReply,
      canReport: !this.bindings!.header().isSecretChat() && !this.bindings!.header().isSavedMessages(),
      selectionActive: page.selectionActive,
      selectedMemberIds,
      liveSharingId: page.liveLocationMessageId, themeBubbleOut: this.bindings!.chatBg().bubbleOutColor,
      showUnreadDivider: showTimelineDivider,
      dividerIsResume: showResumeDivider,
      paidMediaPending,
      audioQueuePosition,
      audioQueueLength,
      audioHasPrevious,
      audioHasNext,
      playSlotKey: rowSlot, autoplayMuted: page.autoplayMuted,
      playSlotStartMs: rowSlotStartMs,
      animationPaused: paused,
      animationForcePlay: forcePlay,
      animationPlaybackFailed: playbackFailed,
      editingActive,
      isPinnedMsg,
      liveGroupCallId,
      animateIn,
      lightweightPlainText
    };
    const prepared: PreparedMessageBubble = {
      group: g,
      data
    };
    if (this.preparedMessageCache.size >= PREPARED_MESSAGE_CACHE_LIMIT) {
      this.preparedMessageCache.clear();
      this.preparedKeyCache.clear();
    }
    this.preparedMessageCache.set(cacheKey, prepared);
    return prepared;
  }

  // masked / initialDeferred 期间持续续期，揭示之后再放行一个窗口。
  // 读的同时续期，所以每一次 build 都会把闩推到当前帧。
  initialRowFadeArmed(rowDeferred: boolean): boolean {
    const now: number = Date.now();
    if (this.initialTimelineMasked || rowDeferred) {
      this.initialRowFadeArmedAt = now;
      return true;
    }
    return rowFadeAnimationActive(false, now, this.initialRowFadeArmedAt);
  }

  // 首屏逐条淡入的**一次性**动画。
  //
  // 原来是一条常驻的 .animation()，窗口外把 duration / delay 给 0。真机 trace
  // 说那不够：修饰器常驻，普通 rerender 照样进 JSAnimation duration:0。现在改
  // 成 transition——官方只在"组件插入/删除"和"visibility 在可见与不可见之间
  // 改变"两种情形触发它（API 参考「组件内转场 (transition)」把触发条件穷举成
  // 了这两条），普通属性更新一概不建上下文。
  //
  // 两条触发条件在这里各管一段：
  //   · 遮罩掀开 = 行的 visibility 由 Hidden 翻 Visible ⇒ 首屏那一波逐条淡入，
  //     stagger 由下面的 delay 给；
  //   · 占位行换成真行 = key 变了、节点重插 ⇒ 同一套效果，同一条路。
  //
  // 关掉时必须整个换成 IDENTITY，不能靠把 duration 给 0：否则滚动中新建的每
  // 一行都会淡入一次（官方 FAQ faqs-arkui-1136 记的就是这个现象）。
  //
  // 出场一律 IDENTITY：虚拟滚动每帧都在拆行，给出场挂效果等于把节点的销毁往后
  // 拖，那是纯粹的负收益。
  initialRowFadeTransition(index: number, rowDeferred: boolean): TransitionEffect {
    // 先求闩（会续期 armedAt，有副作用，每行都得走），再看这一行在不在揭示窗口里：窗口外的行
    // 不做入场动画（见 util/rowFadeGate.ROW_OUTSIDE_REVEAL_WINDOW）。
    const armed: boolean = this.initialRowFadeArmed(rowDeferred);
    const delay: number = this.initialTimelineRowRevealDelay(index);
    const plan: RowFadeTransition = rowFadeTransition(
      this.chatTgsScrollActive,
      armed && delay >= 0,
      powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, INITIAL_TIMELINE_ROW_FADE_MS),
      Math.max(0, delay)
    );
    if (!plan.enabled) {
      return TransitionEffect.IDENTITY;
    }
    // animation() 挂在链首：官方原话"如果通过 combine 进行 TransitionEffect
    // 的组合，前一 TransitionEffect 的动画参数也可用于后一 TransitionEffect"，
    // 所以这一份 duration / delay / curve 覆盖后面两段。视觉与摘掉的那条
    // .animation() 逐条一致：opacity 0→1、y 2→0、scale 0.99→1，EaseOut。
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY
        .animation({ duration: plan.duration, delay: plan.delay, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ y: 2 }))
        .combine(TransitionEffect.scale({ x: 0.99, y: 0.99 })),
      TransitionEffect.IDENTITY
    );
  }

  // stagger 的算法在 util/rowFadeGate.initialRowRevealDelay（返回裸毫秒），
  // 「动效强度」换算读 AppStorage，所以留在这里外面套一层。
  //
  // ⚠️ anchorIndex 用负数当「本次不是锚点落点」的哨兵，**不是**「groupIndexOf
  // 没找到」：命中锚点分支时才传 Math.max(0, groupIndexOf(...))（找不到就夹到
  // 0，同原实现），否则传 -1。另外选分支用的判据带着 firstUnreadId > 0 那一半，
  // 而 stagger 方向用的没有——两者在原方法里就各管各的，不要合并。
  initialTimelineRowRevealDelay(index: number): number {
    // 只有窗口还没量出来时纯函数才会用到 anchorIndex，而 groupIndexOf 是一次
    // 线性扫描、这里每行每帧都会走一遍——所以这道 windowValid 闸必须留着，
    // 与原实现「groupIndexOf 只在 fallback 分支里跑」一致。窗口有效时传 -1，
    // 纯函数根本不看它。
    const windowValid: boolean = this.curStartIdx >= 0 && this.curEndIdx >= this.curStartIdx &&
      this.curEndIdx < this.groups.length;
    const anchored: boolean = (this.stayAtUnread && this.firstUnreadId > 0) ||
      this.resumeDividerId > 0;
    let anchorIndex: number = -1;
    if (!windowValid && anchored) {
      const startAnchorId: number = this.resumeDividerId > 0
        ? this.resumeDividerId : this.firstUnreadId;
      anchorIndex = Math.max(0, groupIndexOf(this.groups, startAnchorId));
    }
    const raw: number = initialRowRevealDelay(
      index, this.curStartIdx, this.curEndIdx, this.groups.length,
      anchorIndex, this.stayAtUnread || this.resumeDividerId > 0,
      INITIAL_TIMELINE_REVEAL_ROW_LIMIT, INITIAL_TIMELINE_ROW_STAGGER_MS);
    // 窗口外（负数）原样透传，由 initialRowFadeTransition 摘掉动画；不能进换算——关动效时它会被抹成 0。
    return raw < 0 ? raw : powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, raw);
  }

  handleTimelineTouch(e: TouchEvent): void {
    if (e.type === TouchType.Down) {
      this.bottomLayoutFollowSeq++;
      this.bottomFollowPending = false;
      this.initialViewportFillEnabled = false;
      this.finishInitialMessageStageForInteraction();
      this.bindings!.cancelImeFollow();
      this.listTouchActive = true;
      this.olderArmed = true;
      this.bindings!.flash.cancelFlash();
      this.bindings!.closeBottomPanels();
    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
      this.listTouchActive = false;
      // 按下又抬起、中间根本没滑（listUserScrollActive 没翻真）：不会有
      // onFloatDateHidden，按住那一会儿被翻译滑动闸攒下的状态得在这里放出。
      if (!this.listUserScrollActive) {
        this.bindings!.translation.onListSettled();
      }
      // 到达绝对顶部后的剩余 active 是边缘回弹。此时 shouldPrimePrependAnchor
      // 会在发布前按住首行，可立即消费已预取页，不必再等完整个回弹周期。
      this.scheduleScrollWork((): void => {
        this.flushQueuedOlderLoad();
        this.maybeTrimWindow();
      });
    }
  }

  handleTimelineScrollIndex(start: number, end: number): void {
    this.bindings!.playSlot.armSettle();
    this.curStartIdx = start;
    this.curEndIdx = end;
    this.indexGroupsLen = this.groups.length;
    this.refreshAtBottom();
    this.fillViewportIfNeeded();
    this.curBottomId = this.bottomVisibleId(end);
    this.bindings!.syncReturnState();
    this.bindings!.markVisibleRead(end);
    this.bindings!.topCard.updatePinnedFromScroll(start);
    const visible: PrefetchRange | null =
      clampPrefetchRange(start, end, this.groupsData.totalCount());
    if (visible !== null) {
      // 预取器的区间校验会抛（jscrash 20260911 ×2："Invalid range"）。预取只是
      // 锦上添花，任何一次失败都不该带走整个应用；打一行日志留证据即可。
      try {
        this.imagePrefetcher.visibleAreaChanged(visible.start, visible.end);
      } catch (e) {
        logE(`[Prefetch] visibleAreaChanged(${visible.start},${visible.end})` +
          ` total=${this.groupsData.totalCount()} rows=${this.groups.length} failed: ${e}`);
      }
    }
    if (!this.chatTgsScrollActive) {
      this.bindings!.translation.drive(this.bindings!.translateChatsEnabled(), start, end);
    }
    this.syncMediaWindow(start, end);
    if (olderTriggerHit(start, OLDER_TRIGGER_ROWS)) {
      // 落地后的 start 天然贴着触发线：loadAround 只在目标上方放 15 行，而
      // ScrollAlign.START 不算 contentStartOffset。这一页取回来就是一次前插。
      // olderArmed 不动，用户下一次滑动照样能取。
      if (!this.bindings!.jumpLandingHolding()) {
        this.maybeLoadOlder();
      }
    }
    if (reachedNewerPageTrigger(end, this.groups.length)) {
      this.maybeLoadNewer(end);
    }
  }

  handleTimelineWillScroll(_offset: number, _state: ScrollState, source: ScrollSource): void {
    this.nextDidScrollIsUserDriven = source !== ScrollSource.SCROLLER &&
      source !== ScrollSource.SCROLLER_ANIMATION;
  }

  handleTimelineDidScroll(offset: number, state: ScrollState): void {
    if (state !== ScrollState.Idle && offset !== 0) {
      noteScrollPlaceholderMotion();
    }
    if (this.nextDidScrollIsUserDriven && state !== ScrollState.Idle) {
      this.userScrollOffsetTotal += offset;
    }
    this.nextDidScrollIsUserDriven = false;
    this.refreshAtBottom();
    this.bindings!.flash.syncFlashRect();
    if (state === ScrollState.Scroll) {
      this.accumulateNewerDrag(offset);
    }
    if (this.listTouchActive) {
      if (this.stayAtUnread) {
        this.stayAtUnread = false;
      }
      if (!this.listUserScrollActive) {
        this.listUserScrollActive = true;
      }
    }
    if (this.listUserScrollActive) {
      this.updateFloatDate(this.curStartIdx);
    }
  }

  handleTimelineScrollStart(): void {
    this.timelineScrollActive = true;
    setScrollActive(true);
    this.finishInitialMessageStageForInteraction();
    this.pauseChatTgsForScroll();
    this.bindings!.dismissKeyboardOnUserScroll();
  }

  // 窗口裁剪：**只在这里调**。停稳 + 手指抬起是唯一允许改行数的时刻，
  // 滑动热路径里动行数等于在用户手底下抽地板。判据与实现见
  // MessageStore.trimWindowTo。
  maybeTrimWindow(): void {
    const store: MessageStore | null = this.bindings!.store();
    if (store === null || this.listTouchActive || this.timelineScrollActive) {
      return;
    }
    // 刚落地时 curStartIdx/curEndIdx 可能还是跳转前那一份，按它下刀会把目标
    // 行本身裁掉。等窗口放手再裁——裁剪本来就只在停稳时做，晚几百毫秒无损。
    if (this.bindings!.jumpLandingHolding()) {
      return;
    }
    const groups: AlbumGroup[] = this.groups;
    if (groups.length < TRIM_TRIGGER_ROWS) {
      return;
    }
    const start: number = this.curStartIdx;
    const end: number = this.curEndIdx;
    if (start < 0 || end < start || end >= groups.length) {
      return;
    }
    // **只砍掉超出上限的那部分**，不是砍到"可见区+余量"。后者会把窗口一路
    // 削到 225 行，余量太薄，往回翻立刻又要重取（见 TRIM_TRIGGER_ROWS 的注释）。
    //
    // 两侧都必须给可见区留够 TRIM_MIN_MARGIN_ROWS：那个下限远大于 List 的
    // cachedCount，否则会把框架正预备的缓存行删掉，滑回去就是一片空白。
    // 优先砍余量大的那一侧——它离视口更远，也更不容易马上被翻回来。
    let excess: number = groups.length - MESSAGE_WINDOW_CAP;
    const spareAbove: number = Math.max(0, start - TRIM_MIN_MARGIN_ROWS);
    const spareBelow: number = Math.max(0, (groups.length - 1 - end) - TRIM_MIN_MARGIN_ROWS);
    let cutAbove: number = 0;
    let cutBelow: number = 0;
    if (spareAbove >= spareBelow) {
      cutAbove = Math.min(excess, spareAbove);
      excess -= cutAbove;
      cutBelow = Math.min(excess, spareBelow);
    } else {
      cutBelow = Math.min(excess, spareBelow);
      excess -= cutBelow;
      cutAbove = Math.min(excess, spareAbove);
    }
    if (cutAbove === 0 && cutBelow === 0) {
      return;
    }
    const first: number = cutAbove;
    const last: number = groups.length - 1 - cutBelow;
    // 相册行代表多条消息：老端取该行最老的成员，新端取最新的。
    const lastMembers: number[] = groups[last].memberIds;
    const firstKeepId: number = groups[first].memberIds[0];
    const lastKeepId: number = lastMembers[lastMembers.length - 1];
    // 位置由 splice 发布 + maintainVisibleContentPosition 保住：裁剪走的是同一数组上的
    // 原地删除（util/splicePublish 的 dropHead / dropTail）。真机 2026-09-11：砍 891 行
    // 后顶行 SAME、y 不变。此前整份换数组时 12/30 次顶行 MOVED，那一版还有一发
    // scrollToIndex 补偿与漂移探针，都已随之删除。
    store.trimWindowTo(firstKeepId, lastKeepId);
  }

  handleTimelineScrollStop(): void {
    this.timelineScrollActive = false;
    this.nextDidScrollIsUserDriven = false;
    setScrollActive(false);
    // 滚动中冻结的 update 发布在这里冲刷（调度中枢批 1）。先于
    // driveVisibleWork：让本轮可见性工作拿到冲刷后的最新行。
    this.bindings!.store()?.flushScrollDeferredUpdate();
    this.maybeTrimWindow();
    this.resumeChatTgsAfterScroll();
    this.driveVisibleWork();
    this.bindings!.playSlot.armSettle();
    this.bindings!.capMessageReuseBuckets();
    // MessageStore may consume a ready prefetch synchronously. Do not publish
    // that snapshot from inside ArkUI's scroll callback/update pass.
    this.scheduleScrollWork((): void => { this.flushQueuedOlderLoad(); });
  }

  handleTimelineAreaChange(area: Area): void {
    const y: number = area.globalPosition.y as number;
    const height: number = area.height as number;
    this.bindings!.playSlot.setViewportCenter(y + height / 2);
  }

  // Refresh the floating date chip from the topmost visible row and (re)arm
  // its fade-out. This is called only for a touch-originated scroll session:
  // initial positioning and reply/pinned jumps must not flash the chip.
  updateFloatDate(start: number): void {
    if (!this.didInitialScroll || start < 0 || start >= this.groups.length) {
      return;
    }
    // 行号得是新鲜的：往上翻插进一页后 groups 已经换了，而 curStartIdx 要等下一次
    // onScrollIndex 才刷新，这期间拿旧行号查新 groups 会差出一整页（issue #163
    // 的另一半）。refreshAtBottom 用的是同一道判据。
    if (this.indexGroupsLen !== this.groups.length) {
      return;
    }
    const now: number = Date.now();
    // onDidScroll fires every rendered frame. If the top row hasn't changed,
    // skip the group scan and the date formatting; only refresh the hide timer
    // at a coarse cadence so a long drag keeps the chip visible.
    //
    // **这道早退必须排在下面那次量布局之前**：firstRowBelowChrome 要 getItemRect
    // （布局查询，每帧最多三次）。
    //
    // 【为什么不能只拿 start 当键 —— issue #163 的另一半】上一版写的是"顶行
    // 下标没变时结果一定和上次一样"，那句不成立：start 在顶行的整段行程里恒定，
    // 而这期间那一行会一点点滑到标题栏底下，chrome 跳过的结果本该跟着变。
    // 闸看的自变量是"系统上报的下标"，现象的自变量是"那一行相对标题栏滑了多远"
    // ——两者对不上，于是跳过结果被冻在每个下标区间开头那一帧的答案上，
    // 区间末尾就显示成上面那一天。
    //
    // 现在下标没变**且**位移不够时才跳过。位移判据见
    // util/floatDateGate.floatDateScrollMovedEnough。
    const scrolledSince: number = this.userScrollOffsetTotal - this.floatDateScrollAt;
    if (start === this.floatDateStartIdx && this.floatDateIndex >= 0
      && !floatDateScrollMovedEnough(scrolledSince)) {
      this.floatDateState.keepAlive(now);
      return;
    }
    this.floatDateStartIdx = start;
    this.floatDateScrollAt = this.userScrollOffsetTotal;
    // start 是 List「显示区」的第一行，包括已经滚到浮动标题栏底下的那一行；
    // 日期条要报的是用户看得见的第一行，见 util/floatDateGate.firstRowBelowChrome。
    const top: number = firstRowBelowChrome(start, this.groups.length,
      this.bindings!.headerChromeHeight(), (index: number): number => this.rowBottomVp(index));
    // 两道判据的归属见 util/floatDateGate 的注释：扫不扫 groups 由这里判（数据
    // 在这边），续不续期由日期条自己判（定时器在那边）。
    if (!floatDateNeedsRescan(top, this.floatDateIndex)) {
      this.floatDateState.keepAlive(now);
      return;
    }
    let date: number = 0;
    for (let i = top; i < this.groups.length; i++) {
      if (this.groups[i].head.date > 0) {
        date = this.groups[i].head.date;
        break;
      }
    }
    if (date <= 0) {
      return;
    }
    if (!this.listUserScrollActive) {
      this.listUserScrollActive = true;
    }
    this.floatDateIndex = top;
    this.floatDateState.show(formatDateSeparator(date), now);
  }

  clearFloatingDate(): void {
    // 定时器与两个显示态一起归 FloatingDateState 管；clear() 不回调 onHidden，
    // 下面这两个标志本来就在同一句里清。
    this.floatDateState.clear();
    this.floatDateIndex = -1;
    this.floatDateStartIdx = -1;
    this.listTouchActive = false;
    this.listUserScrollActive = false;
  }

  // 隐藏定时器烧到底时由 FloatingDateState 回调（aboutToAppear 里挂上）。
  //
  // 【为什么时序等价】搬走之前，这三件事写在**同一个** 820ms 定时器体里：
  // floatDateShown = false、listUserScrollActive = false、floatDateIndex = -1。
  // 现在定时器还是同一条、时长还是 820ms，只是拆成"日期条自己翻 shown" +
  // "回调里翻另外两个"，两段在同一次回调的同一个同步块里先后执行，中间没有
  // await、没有再一次 setTimeout。对读 listUserScrollActive 的那两方（翻页闸
  // util/pageGate、锚点判据 appendAnchorGateProbe）来说，它翻假的那一刻与原来
  // 分毫不差。
  onFloatDateHidden(): void {
    this.listUserScrollActive = false;
    this.floatDateIndex = -1;
    this.floatDateStartIdx = -1;
    // 列表停稳了：把滑动期间攒下的译文一次性落。译文改的是布局，滑动中改
    // 就是"边滑边跳"（用户 2026-09-09 实测），见 util/deferredTranslation。
    // 放在翻假**之后**：flushPending 会经 land() 再问一次 listMoving()。
    // onListSettled = 放出滑动中攒下的「翻译中/失败」 + 补跑挡下的 drive + 落译文。
    this.bindings!.translation.onListSettled();
  }

  // 判定本身在 util/atBottom（10 条测）：那里记着两条上线过的 bug——
  // isAtEnd() 瞬时误报导致把用户从中间拽到最新，以及拿陈旧行号否决导致的自锁死。
  refreshAtBottom(): void {
    const timelineStore: MessageStore | null = this.bindings!.store();
    const scrollerAtEnd: boolean = this.bindings!.viewerOpen() ? false : this.scroller.isAtEnd();
    const hasMoreNewer: boolean = timelineStore !== null && timelineStore.getHasMoreNewer();
    const verdict: string = atBottomVerdict({
      viewerOpen: this.bindings!.viewerOpen(),
      imeTailPinned: this.bindings!.imeTailPinned(),
      scrollerAtEnd: scrollerAtEnd,
      visibleEndIdx: this.curEndIdx,
      indexGroupsLen: this.indexGroupsLen,
      groupsLen: this.groups.length,
      hasMoreNewer: hasMoreNewer
    });
    if (verdict === AT_BOTTOM_KEEP) {
      return;
    }
    const next: boolean = verdict === AT_BOTTOM_YES;
    if (this.atBottom !== next) {
      // 诊断（issue #62）：报告人给的复现极精确——点右下角箭头到底之后，新消息
      // 会自动跟随；自己手滑到底就不会。两条路的差别只可能落在这四个输入之一，
      // 但光看代码分不出是哪个。**只在翻转时打**，稳态不打：那是每次滚动帧都
      // 会走的路，逐次记会把环形缓冲刷满。
      this.atBottom = next;
    }
  }

  // Mark read up to the bottom-most visible message, so only what the user has
  // actually scrolled past gets marked read (entering without scrolling leaves
  // the rest unread).
  // 视口最底下那条真实消息的 id。系统行没有 member id，往回走到最近的真消息。
  bottomVisibleId(end: number): number {
    if (end < 0 || end >= this.groups.length) {
      return this.curBottomId;
    }
    for (let i: number = end; i >= 0; i--) {
      const id: number = this.groups[i].head.id;
      if (id > 0) {
        return id;
      }
    }
    return this.curBottomId;
  }

  // 把可见行区间换算成消息 id 区间交给 store。外扩几行做缓冲，滑动时不会
  // 因为一行之差反复取消又重下。
  syncMediaWindow(startIdx: number, endIdx: number): void {
    const store = this.bindings!.store();
    if (store === null) {
      return;
    }
    // 外扩与夹取在 util/visibleWindow（10 条测）：上界取末行的最后一个成员，
    // 相册一整行多条，取行首会把更新的那几条漏在窗外。
    const w: MediaWindow = mediaWindowRange(
      startIdx, endIdx, this.groups.length,
      (index: number): number => this.groups[index].head.id,
      (index: number): number => {
        const members: number[] = this.groups[index].memberIds;
        return members[members.length - 1];
      });
    if (w.valid) {
      store.setMediaWindow(w.fromId, w.toId);
    }
  }

  // 翻译 + 媒体窗口的统一驱动。滑动时由 onScrollIndex 带着真实区间调用，
  // 数据变化时由这里按"当前视口"调用一次 —— 否则进页面不滑动就什么都不发生。
  driveVisibleWork(): void {
    if (this.groups.length === 0) {
      return;
    }
    // 首帧之前还没有滚动事件，curStartIdx/curEndIdx 是 -1：用首屏兜底
    // （聊天默认停在底部，所以取末尾一屏），滑动事件到了会立刻纠正。
    const range: VisibleRange = visibleRangeOrFallback(
      this.curStartIdx, this.curEndIdx, this.groups.length, this.bindings!.listCachedCount());
    this.bindings!.translation.drive(this.bindings!.translateChatsEnabled(), range.start, range.end);
    this.syncMediaWindow(range.start, range.end);
    // 同一个道理：数据一变（新消息到达、翻页、被查看器等场景清空候选表后
    // 恢复）就补一次播放位判定，不指望用户正好在这一刻滚动。
    this.bindings!.playSlot.armSettle();
  }

  anchorItemY(index: number): number {
    try {
      const rect = this.scroller.getItemRect(index);
      // width/height 两维都为 0 才是非法（正常停在视口顶端的行 y 就是 0，
      // x 在单列列表里恒为 0——照抄"四维都不为 0"会把它误判成不可见）。
      if (!(rect.width > 0) || !(rect.height > 0)) {
        return Number.NaN;
      }
      return rect.y;
    } catch (e) {
      return Number.NaN;
    }
  }

  // 行号是不是描述当前这份数据。锚点采样读的是 curStartIdx，它由 onScrollIndex
  // 给出、落后于数据一帧；拿旧行号去 groups 里取消息 id，会差出一整页
  // （updateFloatDate 为同一件事加过这道守卫，见 issue #163 的另一半）。
  anchorIndexFresh(): boolean {
    return this.indexGroupsLen === this.groups.length;
  }

  // 第 index 行相对 List 顶的下沿（vp）；量不到返回 NaN，调用方按"看得见"处理。
  //
  // 高度为 0 也算量不到：还没布局的行 getItemRect 返回**全 0 矩形**
  // （faqs-arkui-572，同 attemptAnchorRestore 里那条注释），而 0 会被当成
  // "整行都在标题栏上面"往下跳，日期条就报成了视口下方那一天。
  rowBottomVp(index: number): number {
    try {
      const rect = this.scroller.getItemRect(index);
      if (!(rect.height > 0)) {
        return Number.NaN;
      }
      return rect.y + rect.height;
    } catch (e) {
      return Number.NaN;
    }
  }

  stackFromEndWanted(): boolean {
    const timelineStore: MessageStore | null = this.bindings!.store();
    return stackFromEndWanted(
      timelineStore !== null && timelineStore.getHasMoreNewer(),
      this.curStartIdx,
      this.curEndIdx,
      this.indexGroupsLen,
      this.bindings!.threadRootId() > 0
    );
  }
  private static readonly FILL_VIEWPORT_MAX_ROWS: number = 80;

  // Invalidates delayed initial-unread layout confirmations when the page is
  // reset or another landing supersedes the current one.
  initialUnreadLayoutSeq: number = 0;

  initialMessageStageSeq: number = 0;

  initialMessageStageActive: boolean = false;

  initialMessagePendingGroups: AlbumGroup[] | null = null;

  initialMessageRevealCount: number = 0;

  // 0 means no callback is queued. Storing the stage sequence rather than a
  // boolean prevents an invalidated old callback from clearing a newer stage's
  // scheduled marker when it eventually arrives.
  initialMessageStageScheduledSeq: number = 0;

  initialTimelineReadyToPresent: boolean = false;

  // 视口铺满之后继续一行一帧铺到第几行（见 initialTailRevealTarget）。0 = 收尾。
  initialTailTarget: number = 0;

  initialTimelinePresentationSeq: number = 0;

  initialTimelinePresentationScheduledSeq: number = 0;

  initialTimelineEarliestAt: number = 0;

  @Trace initialMessageTransitionSettled: boolean = false;

  initialMessageReleaseTimer: number = -1;

  chatTgsStageSettling: boolean = false;

  chatTgsResumeTimer: number = -1;

  // 隐藏那一刻"屏幕最上面那条消息是哪条、它在哪个高度"。
  //
  // 必须在隐藏时就记：恢复时再拿 curStartIdx 去索引数据集，隐藏期间若发生过
  // prepend，这个下标已经指向别的消息了。
  hiddenAnchorId: number = 0;

  hiddenAnchorY: number = 0;

  // 隐藏那一刻是不是正贴着底，以及当时最后一行的消息 id。两者一起回答「隐藏
  // 期间列表动没动」——没动就别松开贴底（issue #62），见 resyncListAfterHidden。
  hiddenAtBottom: boolean = false;

  hiddenNewestId: number = 0;

  scrollActionSeq: number = 0;

  resumeDividerItemY: number = 0;

  // 触顶发生在拖动/惯性期间时只预取，不立刻发布。顶插会重排 Repeat 的整份
  // 下标表；等 List 停稳后再消费预取页，避免框架保位和手工锚点补偿夹在滚动帧里。
  olderLoadQueued: boolean = false;

  // 向下分页的一次性闸，语义和上面的 olderArmed 一致：打一发就下膛，只有
  // 真实用户输入才重新上膛（见 util/pageGate）。
  //
  // 光靠"end 越过上次开枪的位置"这道弱闸挡不住自持回路：stackFromEnd 是底部
  // 锚定，一页 newer 追加到末尾就把视口往下推，end 自己变大，弱闸每次都放行。
  // 真机上一次开会话连锁拉了 9 页（rowsBefore 132 → 356）。弱闸留着防同一个
  // end 被重复敲，真正止血的是 armed。
  newerGate: PageGate = armedPageGate();

  // [NewerFire] 去重用：上一条已经记过的 end。
  newerFireLoggedEnd: number = -1;

  // 锚点复位簇（前插/追加/恢复落位三条路径的"把那一行按回原来的 y"）整簇
  // 搬进了 ScrollAnchorController（第二轮 R2-B）。原来的 prependRestoreSeq 代次
  // 守卫是它的内部机件，页面只经 invalidate() 作废，见该文件文件头。
  anchor: ScrollAnchorController = new ScrollAnchorController();

  pauseChatTgsForScroll(): void {
    this.chatTgsScrollActive = true;
    this.bindings!.syncChatTgsGate();
  }

  scheduleChatTgsResume(delayMs: number = 140): void {
    if (this.chatTgsResumeTimer !== -1) {
      clearTimeout(this.chatTgsResumeTimer);
    }
    this.chatTgsStageSettling = true;
    this.bindings!.syncChatTgsGate();
    this.chatTgsResumeTimer = setTimeout((): void => {
      this.chatTgsResumeTimer = -1;
      this.chatTgsStageSettling = false;
      this.bindings!.syncChatTgsGate();
    }, delayMs);
  }

  resumeChatTgsAfterScroll(): void {
    this.chatTgsScrollActive = false;
    this.scheduleChatTgsResume();
  }

  // The normal publication gate also invalidates an unfinished initial stage.
  publishGroups(groups: AlbumGroup[]): void {
    const wasStaging: boolean = this.initialMessageStageActive;
    this.initialMessageStageSeq++;
    this.initialMessageStageActive = false;
    this.initialMessagePendingGroups = null;
    this.initialMessageRevealCount = 0;
    this.initialMessageStageScheduledSeq = 0;
    if (wasStaging) {
      this.scheduleChatTgsResume();
    }
    this.publishGroupsNow(groups);
  }

  // MessageStore can publish another ready snapshot while the initial rows are
  // still being revealed (reply/photo metadata often arrives immediately).
  // Keep the newest snapshot for the next batch instead of cancelling staging
  // and putting the complete list back into the very next VSync.
  publishMessageGroups(groups: AlbumGroup[]): void {
    if (this.initialMessageStageActive) {
      this.initialMessagePendingGroups = groups;
      this.postInitialMessageFrame(this.initialMessageStageSeq);
      return;
    }
    this.publishGroups(groups);
  }

  initialMessageStageTarget(groups: AlbumGroup[]): InitialMessageStageTarget {
    const timelineStore: MessageStore | null = this.bindings!.store();
    // A selected remembered position is a first-frame START anchor just like
    // unread, but it has no read-state semantics. Check it before asking the
    // store for firstUnreadId (which is correctly 0 in a fully-read chat).
    if (this.resumeDividerId > 0) {
      const resumeIndex: number = groupIndexOf(groups, this.resumeDividerId);
      if (resumeIndex >= 0) {
        return {
          anchorIndex: resumeIndex,
          alignFromStart: true,
          availableRows: Math.max(0, groups.length - resumeIndex)
        };
      }
    }
    const firstUnreadId: number = timelineStore !== null ? timelineStore.getFirstUnreadId() : 0;
    const anchor: InitialAnchor = initialAnchorOf(
      firstUnreadId,
      firstUnreadId > 0 ? groupIndexOf(groups, firstUnreadId) : -1,
      (index: number): number => groups[index].head.id
    );
    const alignFromStart: boolean = anchor.kind === ANCHOR_UNREAD;
    const anchorIndex: number = alignFromStart ? anchor.index : groups.length - 1;
    const availableRows: number = alignFromStart
      ? Math.max(0, groups.length - anchorIndex) : Math.max(0, anchorIndex + 1);
    return { anchorIndex, alignFromStart, availableRows };
  }

  initialTimelinePresentRows(groups: AlbumGroup[],
    target: InitialMessageStageTarget): number {
    const timelineStore: MessageStore | null = this.bindings!.store();
    // contentStartOffset/contentEndOffset define the real message viewport.
    // Both unread and bottom landings prepare that full anchored window before
    // reveal so every row that can affect the first visible frame is stable.
    const viewportHeight: number = Math.max(
      180,
      this.bindings!.screenH() - this.bindings!.headerChromeHeight() - this.bindings!.bottomChromeH() + 32
    );
    const unreadId: number = this.resumeDividerId > 0
      ? this.resumeDividerId
      : (this.firstUnreadId > 0
        ? this.firstUnreadId : (timelineStore !== null ? timelineStore.getFirstUnreadId() : 0));
    return initialMessageViewportRows(
      groups,
      target.anchorIndex,
      target.alignFromStart,
      this.bindings!.screenW(),
      viewportHeight,
      unreadId,
      (group: AlbumGroup, _screenWidth: number, _showDivider: boolean): number =>
        this.viewportGeometry.rowHeight(group)
    );
  }

  finishInitialMessageStage(groups: AlbumGroup[]): void {
    this.publishGroupsNow(groups);
    this.initialMessageStageActive = false;
    this.initialMessagePendingGroups = null;
    this.initialMessageRevealCount = 0;
    this.initialTailTarget = 0;
    this.initialMessageStageScheduledSeq = 0;
    // Keep Lottie startup out of the final placeholder replacement frame.
    this.scheduleChatTgsResume();
    // The timeline stays masked until this full snapshot has been laid out and
    // the final id-based anchor has been applied. Never issue another delayed
    // landing after the mask is gone: that was the visible second jump.
    this.initialTimelineReadyToPresent = true;
    this.scheduleInitialTimelinePresentation();
    // Do not put the editor's stylus bridge into the final message-row frame.
    // scheduleComposerEditorMount adds one more real VSync boundary.
    this.bindings!.scheduleComposerEditorMount();
  }

  finishInitialMessageStageForInteraction(): void {
    // Normally the viewport-sized stage finishes before the mask is removed. A
    // bounded initial-history fill can deliberately keep it waiting, though;
    // once the user touches the list, ownership must transfer in that same
    // gesture. The old code returned while initialTimelineMasked was true and
    // the List itself was disabled during that interval. A finger that went
    // down in the first layout window therefore stayed attached to a disabled
    // target for its whole 3~5 second drag, even after the timeline appeared.
    if (!this.initialMessageStageActive && !this.initialTimelineMasked) {
      return;
    }
    if (this.initialMessageStageActive) {
      const groups: AlbumGroup[] = this.initialMessagePendingGroups ?? this.groups;
      this.initialMessageStageSeq++;
      this.finishInitialMessageStage(groups);
    }
    if (!this.initialTimelineMasked) {
      return;
    }
    // finishInitialMessageStage may just have queued the normal two-frame
    // presentation. Invalidate it before exposing the list: otherwise its
    // settleInitialTimelineAnchor() would run after the user's drag begins and
    // visibly pull the viewport back to the unread marker/bottom.
    this.initialTimelinePresentationSeq++;
    this.initialTimelinePresentationScheduledSeq = 0;
    this.initialTimelineReadyToPresent = false;
    this.initialTailTarget = 0;
    this.settleInitialTimelineAnchor();
    this.cancelInitialMessageTransitionSettle();
    this.initialMessageTransitionSettled = true;
    this.revealInitialTimeline();
  }

  // 遮罩掀开只做一次同步状态切换。这里不能再包 animateTo：首屏 trace 显示
  // 它会在 JSAnimateTo 内同步触发 FlushLayoutTask（约 30ms），把本来已经
  // 分帧完成的首屏重新合并成一个超预算帧。行自己的 transition 仍负责逐行淡入。
  revealInitialTimeline(): void {
    this.initialTimelineMasked = false;
    // 旁路可见性工作在首屏稳定后统一启动一次。
    this.driveVisibleWork();
  }

  applyInitialUnreadLanding(seq: number): void {
    if (seq !== this.initialUnreadLayoutSeq || !this.didInitialScroll ||
      !this.stayAtUnread || this.firstUnreadId <= 0) {
      return;
    }
    // Recompute from the latest full snapshot. Initial backfill can prepend
    // rows between the first command and this layout-confirmation pass.
    const index: number = groupIndexOf(this.groups, this.firstUnreadId);
    if (index < 0) {
      return;
    }
    this.scroller.scrollToIndex(index, false, ScrollAlign.START);
  }

  scheduleInitialUnreadLanding(delayMs: number = 80): void {
    if (!this.didInitialScroll || !this.stayAtUnread || this.firstUnreadId <= 0) {
      return;
    }
    const seq: number = this.initialUnreadLayoutSeq;
    setTimeout((): void => {
      this.applyInitialUnreadLanding(seq);
    }, delayMs);
  }

  beginInitialUnreadLanding(): void {
    const seq: number = ++this.initialUnreadLayoutSeq;
    // Keep the immediate path for an already-laid-out list, then confirm after
    // ArkUI has consumed the newly published LazyForEach operations.
    this.applyInitialUnreadLanding(seq);
    this.scheduleInitialUnreadLanding();
  }

  // 跳到某条消息：居中（#219-6，理由见 util/jumpAlign）。进会话落到第一条未读、
  // 回到上次阅读位置、翻页锚点**不走这里**。
  scrollToJumpTarget(index: number): void {
    this.scroller.scrollToIndex(index, false, ScrollAlign.CENTER);
  }

  scrollToTimelineIndexAtY(index: number, itemY: number = 0): void {
    this.scroller.scrollToIndex(index, false, ScrollAlign.START);
    if (Number.isFinite(itemY) && Math.abs(itemY) > 0.5) {
      // START puts the row at y=0. Restore the captured partial-row offset so
      // leaving and reopening a chat returns to the same viewport geometry.
      this.scroller.scrollBy(0, -itemY);
    }
  }

  settleInitialTimelineAnchor(): void {
    if (!this.didInitialScroll || this.groups.length === 0) {
      return;
    }
    if (this.resumeDividerId > 0) {
      const resumeIndex: number = groupIndexOf(this.groups, this.resumeDividerId);
      if (resumeIndex >= 0) {
        this.scrollToTimelineIndexAtY(resumeIndex, this.resumeDividerItemY);
      }
      return;
    }
    if (this.stayAtUnread && this.firstUnreadId > 0) {
      const index: number = groupIndexOf(this.groups, this.firstUnreadId);
      if (index >= 0) {
        this.scroller.scrollToIndex(index, false, ScrollAlign.START);
      }
      return;
    }
    this.scroller.scrollToIndex(this.groups.length - 1, false, ScrollAlign.END);
    this.scroller.scrollEdge(Edge.Bottom);
  }

  scheduleInitialTimelinePresentation(): void {
    if (!this.initialTimelineMasked || !this.initialTimelineReadyToPresent ||
      this.initialTimelinePresentationScheduledSeq !== 0) {
      return;
    }
    const seq: number = ++this.initialTimelinePresentationSeq;
    this.initialTimelinePresentationScheduledSeq = seq;
    const delayMs: number = Math.max(0, this.initialTimelineEarliestAt - Date.now());
    this.bindings!.getUIContext().postDelayedFrameCallback(new ChatPageFrameCallback((): void => {
      if (seq !== this.initialTimelinePresentationSeq || !this.pageVisible ||
        !this.initialTimelineMasked || !this.initialTimelineReadyToPresent) {
        if (this.initialTimelinePresentationScheduledSeq === seq) {
          this.initialTimelinePresentationScheduledSeq = 0;
        }
        return;
      }
      // First frame consumes the scroll command while the list is still
      // invisible. The next frame confirms against final row heights and only
      // then removes the mask, so no intermediate position can be painted.
      // Keep the scheduled marker locked across BOTH frames. Clearing it here
      // let the next one-row staging publication start a new presentation and
      // invalidate this second frame; a 101-row bottom timeline therefore
      // restarted the landing 99 times and stayed blank for about two seconds.
      this.settleInitialTimelineAnchor();
      this.bindings!.getUIContext().postDelayedFrameCallback(new ChatPageFrameCallback((): void => {
        if (seq !== this.initialTimelinePresentationSeq || !this.pageVisible ||
          !this.initialTimelineMasked || !this.initialTimelineReadyToPresent) {
          if (this.initialTimelinePresentationScheduledSeq === seq) {
            this.initialTimelinePresentationScheduledSeq = 0;
          }
          return;
        }
        this.settleInitialTimelineAnchor();
        // Reveal the complete chat surface as one visual event. Header and
        // composer start their fade in the same frame as the first real bubble;
        // the remaining bubbles keep their per-row stagger below.
        this.cancelInitialMessageTransitionSettle();
        this.initialMessageTransitionSettled = true;
        this.revealInitialTimeline();
        if (this.initialTimelinePresentationScheduledSeq === seq) {
          this.initialTimelinePresentationScheduledSeq = 0;
        }
      }), INITIAL_MESSAGE_RELEASE_DELAY_MS);
    }), delayMs);
  }

  releaseNextInitialMessageBatch(stageSeq: number): InitialMessageReleaseResult {
    const timelineStore: MessageStore | null = this.bindings!.store();
    if (stageSeq !== this.initialMessageStageSeq || !this.initialMessageStageActive) {
      return 'finished';
    }
    // A short first TDLib page immediately starts a bounded older-page fill.
    // Do not reveal against that moving snapshot: the unread/bottom anchor can
    // move when the prepend arrives, turning a nominal one-row admission into
    // several MessageBubble builds in one layout. The 11:04 device trace caught
    // exactly that shape (six bubbles and a 48.7 ms frame just after the push).
    // The final onHistory notification calls publishMessageGroups(), which
    // posts this callback again once isInitialFillPending() becomes false.
    const groups: AlbumGroup[] = this.initialMessagePendingGroups ?? this.groups;
    const target: InitialMessageStageTarget = this.initialMessageStageTarget(groups);
    const fillPending: boolean = timelineStore !== null && timelineStore.isInitialFillPending();
    if (fillPending && target.alignFromStart) {
      return 'waiting';
    }
    // The visible landing window is already stable. While a bounded history
    // fill is still moving the snapshot, keep the current geometry and wait
    // for its final publication instead of proactively materializing every
    // off-screen row. When the fill completes, publish the real snapshot once;
    // LazyForEach then builds only its visible/cache window.
    if (this.initialTimelineReadyToPresent) {
      if (fillPending) {
        return 'waiting';
      }
      // 视口已就位、遮罩已在撤除路上，但**别**在这里把剩余行一次性转真：List 的
      // 缓存窗（cachedCount 8/10）里那几行会在同一帧里全部构建。按同样的一行一
      // 帧把缓存窗铺完，再发最后一份完整快照。
      const tailNext: number = nextInitialMessageRevealCount(
        this.initialMessageRevealCount, this.initialTailTarget);
      if (tailNext > this.initialMessageRevealCount) {
        this.initialMessageRevealCount = tailNext;
        this.publishGroupsNow(stageInitialMessageGroups(
          groups, target.anchorIndex, target.alignFromStart, tailNext));
        return 'released';
      }
      this.finishInitialMessageStage(groups);
      return 'finished';
    }
    const nextRevealCount: number = nextInitialMessageRevealCount(
      this.initialMessageRevealCount,
      target.availableRows
    );
    if (nextRevealCount <= this.initialMessageRevealCount) {
      // A newly visited chat can publish a one-row `latest` page and then chain
      // one or more `older` requests. Keep admission open while that bounded
      // chain is in flight; its next snapshot restarts the frame scheduler via
      // publishMessageGroups instead of dumping every added row at once.
      if (timelineStore !== null && timelineStore.isInitialFillPending()) {
        return 'waiting';
      }
      // Unread anchoring can leave older, off-screen rows deferred even after
      // every row below the unread marker is real. Publish those in one final
      // frame; bottom anchoring normally completes in the branch below.
      this.finishInitialMessageStage(groups);
      return 'finished';
    }

    const staged: AlbumGroup[] = stageInitialMessageGroups(
      groups,
      target.anchorIndex,
      target.alignFromStart,
      nextRevealCount
    );
    this.initialMessageRevealCount = nextRevealCount;
    this.publishGroupsNow(staged);
    const presentRows: number = Math.min(
      this.initialTimelinePresentRows(groups, target), target.availableRows);
    // A short page may still be growing through the bounded initial fill. Do
    // not reveal a lone bottom row and then let older rows visibly climb upward.
    // The presentation target above is a stable lower slice for bottom landings
    // and the complete anchored window for unread landings.
    if (!this.initialTimelineReadyToPresent && nextRevealCount >= presentRows &&
      (!fillPending || presentRows > 0)) {
      this.initialTimelineReadyToPresent = true;
      this.initialTailTarget = initialTailRevealTarget(presentRows, target.availableRows);
      this.scheduleInitialTimelinePresentation();
      if (!fillPending) {
        // 缓存窗还没铺完就继续一行一帧（分支在上面那个 readyToPresent 里）。
        if (nextRevealCount < this.initialTailTarget) {
          return 'released';
        }
        this.finishInitialMessageStage(groups);
        return 'finished';
      }
      // Do not keep walking the off-screen history one row per VSync after the
      // complete landing window is ready. A later store publication restarts
      // this callback when the bounded initial fill settles.
      return 'waiting';
    }
    if (staged === groups) {
      if (fillPending) {
        // The rows currently available are real, but a short-page backfill is
        // still running. Stay active and let that next snapshot extend the
        // same staged dataset.
        this.initialMessagePendingGroups = groups;
        return 'waiting';
      }
      this.finishInitialMessageStage(groups);
      return 'finished';
    }
    return 'released';
  }

  postInitialMessageFrame(stageSeq: number): void {
    if (this.initialMessageStageScheduledSeq === stageSeq) {
      return;
    }
    this.initialMessageStageScheduledSeq = stageSeq;
    this.bindings!.getUIContext().postDelayedFrameCallback(new ChatPageFrameCallback((): void => {
      if (this.initialMessageStageScheduledSeq === stageSeq) {
        this.initialMessageStageScheduledSeq = 0;
      }
      if (stageSeq !== this.initialMessageStageSeq || !this.initialMessageStageActive) {
        return;
      }
      const result: InitialMessageReleaseResult = this.releaseNextInitialMessageBatch(stageSeq);
      if (result === 'released') {
        this.postInitialMessageFrame(stageSeq);
      }
    }), INITIAL_MESSAGE_RELEASE_DELAY_MS);
  }

  publishInitialMessageGroups(groups: AlbumGroup[]): void {
    const target: InitialMessageStageTarget = this.initialMessageStageTarget(groups);
    // Publish a placeholder-only list first. The initial MessageStore snapshot
    // also changes title/load/list state and makes ChatPage rerender as a whole;
    // the frame trace measured 8 ms in that rerender before message layout even
    // began. Releasing real rows here would put both jobs back into one 52 ms
    // VSync. The delayed callback gives this cheap dataset one full page frame,
    // then releaseNextInitialMessageBatch() admits exactly one row per VSync.
    const firstRevealCount: number = 0;
    const staged: AlbumGroup[] = stageInitialMessageGroups(
      groups,
      target.anchorIndex,
      target.alignFromStart,
      firstRevealCount
    );
    if (staged === groups) {
      this.publishGroups(groups);
      return;
    }

    const stageSeq: number = ++this.initialMessageStageSeq;
    this.initialTimelineMasked = true;
    this.initialTimelineReadyToPresent = false;
    this.initialTailTarget = 0;
    this.initialTimelinePresentationSeq++;
    this.initialTimelinePresentationScheduledSeq = 0;
    this.initialTimelineEarliestAt = Date.now() + (target.alignFromStart
      ? INITIAL_TIMELINE_PRESENT_MIN_MS : INITIAL_BOTTOM_PRESENT_MIN_MS);
    this.initialMessageStageActive = true;
    this.bindings!.syncChatTgsGate();
    this.initialMessagePendingGroups = groups;
    this.initialMessageRevealCount = firstRevealCount;
    // 首屏那几行的发送者头像先异步解出来（见 util/avatarWarm）。这一刻是最好的
    // 时机：占位行已经发布、真行还没揭示，主线程正空着。等行真挂上来时
    // CachedImage 直接命中内存，#137 那条同步解码的支路根本不会被走到
    // （2026-09-14 trace：那条支路在进会话那一秒里占 19.9ms）。
    warmSenderAvatars(initialAvatarPaths(groups, target.anchorIndex));
    this.publishGroupsNow(staged);
    this.postInitialMessageFrame(stageSeq);
  }

  // 隐藏时把视口位置记下来，供回来后还原。
  //
  // **包括当时正停在底部的情况**：停在底部只说明那一刻那里是最新的，不代表
  // 用户愿意把隐藏期间到达的消息当成看过的划走。原来那一支直接 glueBottom，
  // 表现就是"切出去、来了消息、切回来直接甩到最底下"。还原到原位之后，新消息
  // 留在下方，「↓」带未读数指回去，要不要下去由用户决定。
  captureHiddenAnchor(): void {
    this.hiddenAnchorId = 0;
    this.hiddenAnchorY = 0;
    this.hiddenAtBottom = false;
    this.hiddenNewestId = 0;
    if (!this.didInitialScroll ||
      this.curStartIdx < 0 || this.curStartIdx >= this.groups.length) {
      return;
    }
    this.hiddenAtBottom = this.atBottom;
    this.hiddenNewestId = this.groups[this.groups.length - 1].head.id;
    this.hiddenAnchorId = this.groups[this.curStartIdx].head.id;
    try {
      this.hiddenAnchorY = this.scroller.getItemRect(this.curStartIdx).y;
    } catch (e) {
      this.hiddenAnchorY = 0;
    }
  }

  resyncListAfterHidden(): void {
    const anchorId: number = this.hiddenAnchorId;
    const anchorY: number = this.hiddenAnchorY;
    const wasAtBottom: boolean = this.hiddenAtBottom;
    const newestBefore: number = this.hiddenNewestId;
    this.hiddenAnchorId = 0;
    this.hiddenAnchorY = 0;
    this.hiddenAtBottom = false;
    this.hiddenNewestId = 0;
    // 迁 Repeat 之前这里是 groupsData.reload()。等价物见 rebuildAllRows()。
    this.rebuildAllRows();
    const newestNow: number = this.groups.length > 0
      ? this.groups[this.groups.length - 1].head.id : 0;
    if (anchorId > 0 && wasAtBottom && newestBefore > 0 && newestNow === newestBefore) {
      // 隐藏期间一条新消息都没来，而隐藏时正贴着底：列表没动过，没什么可还原的，
      // **贴底也不能松**（issue #62）。松开之后只有 onScrollIndex 会把它判回来，
      // 而没有位移就没有滚动回调，atBottom 从此一直是 false，之后每条新消息都
      // 被当成"用户不在底部"不跟随——「锁屏解锁后就不滚了」正是这条路。
      //
      // 不改成"还原完再补判一次"：还原本身跑在 setTimeout 里、量不到还会重试
      // （attemptAnchorRestore），补判会插在中间，用一个还没落位的 isAtEnd 下
      // 结论，反而可能把用户从还原点拽到底部。
    } else if (anchorId > 0) {
      // 先松开贴底：还原发起到 onScrollIndex 回调落地之间，atBottom 还是隐藏
      // 前那个 true，这期间任何一条到达通知都会走"在底部就跟随"那一支
      // （见 L1242）把视口又拽回底部。同文件 1216 / 1227 两处也是这个写法。
      //
      // 走到这里的两种情况：隐藏时不在底部（本来就该还原到原位），或者隐藏期间
      // 来了新消息——后者按 3ff77fc 的有意设计仍然停在原位，新消息留在下方由
      // 「↓」带未读数指回去，不自动甩到最新。
      this.atBottom = false;
      this.anchor.restorePrependAnchor(this.groups, anchorId, anchorY);
    } else if (this.atBottom && this.didInitialScroll) {
      const actionSeq: number = ++this.scrollActionSeq;
      setTimeout((): void => {
        if (actionSeq === this.scrollActionSeq) {
          this.glueBottom('L279');
        }
      }, 0);
    }
  }

  // Fire at most one loadOlder per arm (see olderArmed).
  maybeLoadOlder(): void {
    // 诊断：用户报"999+ 却滑不动"，而日志里 loadOlder 一次都没被调用过——
    // 需要看清是没被叫、还是被 olderArmed 挡住、还是 store 拒绝。
    const store: MessageStore | null = this.bindings!.store();
    if (!this.olderArmed || store === null) {
      return;
    }
    // 手指**物理按着**时仍旧只排队、不发布。
    //
    // 【2026-09-11 真机回归，用户报"有时会往前跳一页"】这是拆闸时开的洞：
    //   · ScrollAnchorController 在 touchActive 时**只跳过 fallback 那一支**
    //     （reason=touch-fallback）；
    //   · 而 29 行的前插必然把锚点行推出可视区，getItemRect 返回全零哨兵，
    //     算出来的 mode 恰恰就是 fallback；
    //   · 老设计里两者永远撞不上——flushQueuedOlderLoad 明确「手指按着不发」。
    // 删掉排队之后，手指按着时发布 → 需要补位 → 补位被 touch 闸挡掉 → 一次都
    // 不补 → 内容整页飞走。
    //
    // 惯性那半边保留（延迟收益主要在那儿：撞顶到历史出现原本要等 835~1187ms）。
    // 惯性中没有手指在控制位置，fallback 也不会被 touch 闸挡。
    if (this.listTouchActive) {
      this.olderArmed = false;
      this.olderLoadQueued = true;
      // 保留网络提前量，但 prefetchOlder 不发布消息快照。
      store.prefetchOlder();
      return;
    }
    // **不再等停稳**（2026-09-10）。
    //
    // 这道闸原来的理由是"发布会让内容动，动就得补位，补位在惯性中是抢"。
    // 三处几何跳变修掉之后（首行假胶囊、接缝行昵称回收、半个相册补齐，见
    // util/collapseAlbums 的 RunHeadHints），前插对 List 而言已经是**纯插入**，
    // 位置由 maintainVisibleContentPosition 自己保住，一次程序性滚动都不需要
    // ——没有可抢的东西，也就没有等的必要。
    //
    // 等待的代价是实打实的：真机实测撞顶到历史出现 835 / 1053 / 1187ms，数据
    // 其实早就在手上（`older prefetch ready`），纯粹被这道闸压着，用户报"卡在那"、
    // "得再拽一下"。
    //
    // ⚠️ 更正（2026-09-11，真机 71/71 打脸）：这里原本写着"几何不变时补位闸
    // 自己会返回 false"——**那是错的**。向上这侧的判据是 shouldCapturePrependAnchor，
    // 它只看 `notifyKind==='older' && 消息窗口变长`，从不问 key 变没变；
    // prependBreaksAnchor 除了单测没有任何生产调用方（向下那侧的
    // appendBreaksAnchor 才是接着的）。所以只要翻一页历史就必然补位一次。
    // 2026-09-11 之后前插锚点整体默认不做（见 PREPEND_ANCHOR_ENABLED），此段仅作历史。
    //
    // 两页在手时仍然**合成一次**发布（loadOlderMerged）：连发两次会让第二页
    // 撞上 stale-index、整页无补偿地插进来，那是另一回事，与等不等手势无关。
    const started: boolean = store.loadOlderMerged();
    if (started || !store.getHasMoreOlder()) {
      this.olderArmed = false;
    }
  }

  // ⚠️ 更正（2026-09-11）：下面这段里「惯性中既不 prime、也不做事后补偿」在
  // 写下时就与代码不符——anchorRestore.shouldPrimePrependAnchor 明写"手指抬起之后
  // 一律 prime，含惯性"，日志里 prime=true active=true 出现过 81 次。现在前插锚点
  // 默认整个关掉（见 NO_PREPEND_ANCHOR_DEFAULT），位置由 splice 发布 + MVCP 保。
  //
  // **松手即发**，不等惯性跑完（2026-09-10）。
  //
  // 等停稳的代价是白等整个惯性时长：真机实测撞顶到历史出现 835 / 1053 / 1187ms，
  // 数据其实早在手上（older prefetch ready），纯粹被这道闸压着——用户报"卡在那"。
  //
  // 【惯性中一次程序性滚动都不发】试过在惯性里 prime：位置全对（dy=0），
  // 但 scrollToIndex 会打断正在跑的滚动动画，用户报"页面被拉住一下"。
  // 所以现在惯性中既不 prime、也不做事后补偿，**位置全交给框架的
  // maintainVisibleContentPosition**——同一轮的漂移探针支持这么赌：
  // 用户静止时 drift 恒为 0，框架在这条路上没有失手。
  // 惯性结束后 onScrollStop 仍会走一次静止路径，那时该补的还能补上。
  //
  // 手指仍按着时**照旧不发**：那时用户正在主动控制位置，任何程序性滚动都是抢。
  //
  // 手指抬起时把按着期间攒下的那一发打出去（maybeLoadOlder 的排队分支）。
  flushQueuedOlderLoad(): void {
    if (!this.olderLoadQueued || this.listTouchActive) {
      return;
    }
    this.olderLoadQueued = false;
    const store: MessageStore | null = this.bindings!.store();
    if (store === null) {
      return;
    }
    const started: boolean = store.loadOlderMerged();
    logW(`[OlderGate] flush started=${started} start=${this.curStartIdx}` +
      ` rows=${this.groups.length}`);
    if (!started && store.getHasMoreOlder()) {
      // 请求若被另一条在途事务拒绝，下一次手势仍可重试。
      this.olderArmed = true;
    }
  }

  // 内容不足一屏时主动补页。
  //
  // 向上分页全靠滚动事件驱动（onReachStart / onScrollIndex 里 start<=4），
  // 可内容铺不满一屏时列表根本滚不动，这两个事件永远不来，于是卡在初始那点
  // 内容上——用户看到的就是"999+ 却滑不动"。平板尤其容易中招：屏幕更高，
  // 要更多行才铺得满。
  //
  // 判据是"整份数据都在屏幕上"（首行和末行同时可见）⇒ 列表滚不动 ⇒ 滚动事件
  // 永远不来，得自己敲门。判据与完整推导见 util/viewportFill——第一版只问
  // "最后一行可见吗"，而列表是 stackFromEnd(true)、最后一行几乎恒可见，于是
  // 用户停在底部时也会一路往上补页，正是"带未读进会话立刻下滑却滑不动"的直接
  // 成因之一。
  fillViewportIfNeeded(): void {
    const timelineStore: MessageStore | null = this.bindings!.store();
    if (timelineStore === null || !this.initialViewportFillEnabled) {
      return;
    }
    const fill: boolean = shouldFillViewport({
      hasMoreOlder: timelineStore.getHasMoreOlder(),
      rows: this.groups.length,
      maxRows: ChatTimelineSession.FILL_VIEWPORT_MAX_ROWS,
      startIdx: this.curStartIdx,
      endIdx: this.curEndIdx,
      indexRows: this.indexGroupsLen
    });
    if (!fill) {
      return;
    }
    this.olderArmed = true;
    this.maybeLoadOlder();
  }

  // 只有闸在膛上、且视口确实往下走过，才再取一页。见 util/pageGate。
  maybeLoadNewer(end: number): void {
    const timelineStore: MessageStore | null = this.bindings!.store();
    if (timelineStore === null) {
      return;
    }
    const gate: PageGate = this.newerGate;
    const canFire: boolean = canFirePageGate(gate, end);
    // ⚠️ 诊断 [NewerFire]：用户报"下滑也推不动"。要能分清两件完全不同的事：
    //   闸挡住了      → 这里 canFire=false，且写明是 armed 还是弱闸挡的；
    //   闸放行了没进展 → canFire=true / started=true，但后面 rows 不涨、
    //                    或者 rows 涨了而 endIdx 原地不动（位置被布局吃掉）。
    // 按 end 去重：onScrollIndex 只在可见区间变化时触发，但布局抖动会让它高频
    // 变化，不去重会把环形缓冲刷满（logW 攒 300 行才落盘）。
    if (end !== this.newerFireLoggedEnd) {
      this.newerFireLoggedEnd = end;
      const blockedBy: string = canFire
        ? 'none' : (gate.armed ? 'weakGate' : 'disarmed');
    }
    if (!canFire) {
      return;
    }
    // 谁扣的这一枪的扳机。判据是**这一膛是谁压上去的**：手指位移上膛的是用户
    // （armedByUser=true），会话开局给首屏自动补页留的那一发不是。标记随请求带
    // 到发布点，决定那一页落地时复不复位锚点。
    // 不能读 listTouchActive / listUserScrollActive——那两个标志的语义不对，而且
    // 和上膛条件同源，会让 skip 结构上不可达（见 util/appendAnchor）。
    const userDriven: boolean = newerPageIsUserDriven(pageGateShotIsUserDriven(gate));
    const started: boolean = timelineStore.loadNewer(userDriven);
    if (started || !timelineStore.getHasMoreNewer()) {
      this.newerGate = firedPageGate(gate, end);
    }
  }

  // 用户手指拖动列表：攒够位移就给向下分页的闸重新上膛。
  //
  // 只从 onDidScroll 的 ScrollState.Scroll 那一支进来（见那里的说明）。上膛的
  // 那一帧在**仍处于末端触发区**时立刻补敲一次门：onScrollIndex 只在可见行号
  // 区间变化时触发，而用户正贴在末尾时 end 恒等于 rows - 1，纹丝不动——光等
  // onScrollIndex 的话，刚上膛的这一发会一直没机会打出去。
  //
  // 末端检查不能少：append 锚点复位若发生在手指仍按住时，ArkUI 会把控制器位移
  // 也报成 Scroll。真机日志里它在 rows=70/end=41 时重新上膛；旧代码无条件补敲，
  // 于是远离末端仍继续拉页并再次复位，正是进入未读很多的频道后 3~5 秒内滑动
  // 不跟手、松手弹回的闭环。
  accumulateNewerDrag(offset: number): void {
    const before: PageGate = this.newerGate;
    if (before.armed) {
      return;
    }
    const after: PageGate = draggedPageGate(before, offset);
    this.newerGate = after;
    if (!after.armed) {
      return;
    }
    if (reachedNewerPageTrigger(this.curEndIdx, this.groups.length)) {
      this.maybeLoadNewer(this.curEndIdx);
    }
  }

  // 诊断：视口明明停在中段却触发了"贴底"。正常贴底不打——那是每次新消息
  // 到达都会走的路，逐次记会把环形缓冲刷满，导出日志时最该看的那段反而被
  // 挤掉。只在自相矛盾时打：说自己在底部，可见的最后一行却离末尾很远。
  glueBottom(tag: string): void {
    if (this.curEndIdx >= 0 && this.groups.length - this.curEndIdx > 3) {
      logW(`glueBottom ${tag} atBottom=${this.atBottom} endIdx=${this.curEndIdx}` +
        ` rows=${this.groups.length} stayUnread=${this.stayAtUnread}`);
    }
    this.scroller.scrollEdge(Edge.Bottom);
  }

  cancelInitialMessageTransitionSettle(): void {
    if (this.initialMessageReleaseTimer !== -1) {
      clearTimeout(this.initialMessageReleaseTimer);
      this.initialMessageReleaseTimer = -1;
    }
  }

  armInitialMessageTransitionSettle(): void {
    if (this.initialMessageTransitionSettled) {
      return;
    }
    this.cancelInitialMessageTransitionSettle();
    this.initialMessageReleaseTimer = setTimeout((): void => {
      this.initialMessageReleaseTimer = -1;
      if (!this.pageVisible) {
        return;
      }
      // This used to be an unconditional 640 ms fallback. When TDLib needed
      // longer, it exposed the header/composer while the timeline was still
      // empty, so messages visibly arrived afterwards. A non-empty timeline
      // has one authoritative release point: scheduleInitialTimelinePresentation.
      if (this.messageLoadState === 'loading' || this.visibleGroupCount > 0 ||
        this.initialMessageStageActive || this.initialTimelineMasked) {
        return;
      }
      this.initialMessageTransitionSettled = true;
    }, INITIAL_MESSAGE_TRANSITION_SETTLE_MS);
  }
}
