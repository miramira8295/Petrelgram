import { router } from '@kit.ArkUI';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { ChatListDataSource } from './ChatListDataSource';
import { guardKey } from '../../util/keyGuard';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  AVATAR_SIZE, COLOR_MUTED_BADGE, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY,
  ROW_PAD_H, ROW_PAD_V
} from '../../util/theme';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

// 与普通会话行同一套规格：头像 AVATAR_SIZE(56) + 上下 ROW_PAD_V(8)。归档入口
// 长得和会话行一个个头，拉出来时才不显得是另一种东西。
const ARCHIVE_ROW_HEIGHT: number = AVATAR_SIZE + ROW_PAD_V * 2;

@Preview
@Component
export struct MainTabBody {
  // See ChatPage: the row key embeds this, so the data source must be told.
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLanguageEpochChanged') langEpoch: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Set when the floating folder bar overlays this list (see ChatListView).
  // 顶部悬浮 chrome（顶栏 + 文件夹条）的总高度。改成数值是因为顶栏也浮起来
  // 了：列表从它底下穿过去，才有玻璃透隐可看。原来是个布尔，只够表达"有没有
  // 文件夹条"。
  @Prop contentTopInset: number = 0;
  // 由 ChatListPage 传进来，每个文件夹页签一个。HdsNavigation 靠它拿到滚动量
  // 才能驱动标题栏收缩与渐变模糊；页签里的列表在子组件内部，父层拿不到，
  // 只能这样把控制器递下来。
  listScroller: Scroller = new Scroller();
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  @State chats: ChatEntry[] = [];
  private chatsData: ChatListDataSource = new ChatListDataSource();
  @State @Watch('onArchiveRowToggled') showArchive: boolean = false;
  @State @Watch('onArchiveRowToggled') archiveLoadFailed: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  private unsubscribe: (() => void) | null = null;
  private unsubArchive: (() => void) | null = null;
  // 首批会话到位时把归档行收上去一次就够。之后每次数据更新都收，会把正在
  // 看列表的用户反复拽回顶部。
  private archiveTucked: boolean = false;
  // 列表当前滚动偏移，只用来算归档行的透明度。初值取行高＝完全透明。
  @State private listTopOffset: number = ARCHIVE_ROW_HEIGHT;

  private onLanguageEpochChanged(): void {
    this.chatsData.reload();
  }

  private onMenuToggle(): void {
    if (this.menuOpen) {
      return;
    }
    const next = this.updateGate.flush();
    if (next !== null) {
      this.applyChats(next);
    }
  }

  aboutToAppear(): void {
    const store = getChatStore();
    this.unsubscribe = store.subscribe((list: ChatEntry[]) => {
      const next = this.updateGate.accept(list);
      if (next !== null) {
        this.applyChats(next);
      }
    }, 'main');
    this.showArchive = store.hasArchive();
    // The archive shortcut only needs an invalidation signal. Avoid sorting the
    // whole archive bucket for every update just to derive one boolean.
    this.unsubArchive = store.subscribeChanges(() => {
      this.showArchive = store.hasArchive();
    });
    store.ensureLoaded('main');
    store.ensureLoaded('archive').then((success: boolean): void => {
      this.archiveLoadFailed = !success;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) { this.unsubscribe(); this.unsubscribe = null; }
    if (this.unsubArchive !== null) { this.unsubArchive(); this.unsubArchive = null; }
  }

  private applyChats(next: ChatEntry[]): void {
    const structureChanged = this.chats.length !== next.length ||
      this.chats.some((item: ChatEntry, index: number): boolean => item.id !== next[index]?.id);
    if (structureChanged && this.chats.length > 0) {
      animateTo({
        duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
        curve: Curve.EaseOut
      }, (): void => { this.publishChats(next); });
    } else {
      this.publishChats(next);
    }
  }

  private publishChats(next: ChatEntry[]): void {
    this.chats = next;
    this.chatsData.update(next, next.map((item: ChatEntry): string => this.rowKey(item)));
    // 首帧列表是空的——会话是异步来的。空列表没有第 1 行可停，initialIndex: 1
    // 在那一刻是空转；等行到位时偏移已经是 0，归档行就留在顶上露着（真机截图
    // 证实）。首批数据落地时补收一次。
    if (!this.archiveTucked && next.length > 0) {
      this.archiveTucked = true;
      this.tuckArchiveRow();
    }
  }

  // langEpoch is in the key so a language switch rebuilds the rows once, rather
  // than every ChatRow carrying its own AppStorage observer for it.
  private rowKey(item: ChatEntry): string {
    const pinned = getChatStore().isPinned('main', item.id) ? 1 : 0;
    return `${item.id}_${item.revision}_${pinned}_${this.langEpoch}`;
  }

  // 归档入口是否作为列表第 0 行存在。
  private archiveRowShown(): boolean {
    return this.showArchive || this.archiveLoadFailed;
  }

  private onArchiveRowToggled(): void {
    this.tuckArchiveRow();
  }

  // 把第 0 行的归档入口滚出视口。归档行是**插在列表顶端之上**的，插进去会把
  // 内容整体下推一行高；列表还停在顶端时要顺手把它滚掉，用户才看不见。
  //
  // 补两拍，不是保险起见：调用点都在状态刚写入的那一刻，新行还没进布局，
  // scrollToIndex(1) 会滚到一个不存在的位置。下一帧（0ms）通常够；归档桶和
  // 首批会话几乎同时落地时还会差一拍，120ms 再补一次。
  //
  // 每拍都先看偏移，只在列表仍停在顶端时才滚——已经翻下去的话不动，免得把人
  // 拽回顶部。
  private tuckArchiveRow(): void {
    if (!this.archiveRowShown()) {
      return;
    }
    const tuck = (): void => {
      if (this.archiveRowShown() && this.listScroller.currentOffset().yOffset <= 1) {
        this.listScroller.scrollToIndex(1);
      }
    };
    setTimeout(tuck, 0);
    setTimeout(tuck, 120);
  }

  private openArchive(): void {
    router.pushUrl({ url: 'pages/chatlist/ArchivePage' });
  }

  private retryArchive(): void {
    this.archiveLoadFailed = false;
    getChatStore().ensureLoaded('archive').then((success: boolean): void => {
      this.archiveLoadFailed = !success;
    });
  }

  // 列表的第 0 行，默认滚在视口之上看不见；在顶部下拉才把它拉出来。
  //
  // 原来它挂在 Refresh 的 builder 上，下拉松手 onRefreshing 直接 pushUrl 进归档
  // ——手势太容易误触，而且拉出来的那一下根本来不及点。现在改成一行普通的
  // ListItem：拉出来会留在那儿，点一下才进去，往下滚一点它自己退回去。
  @Builder
  archiveHeader() {
    Row({ space: 12 }) {
      // 照会话行的头像规格画一颗"归档头像"：灰底圆形，白色归档图标。
      // 出错态换成红一点的底和感叹号，一眼能分出"这行现在是重试"。
      Row() {
        SymbolGlyph(this.archiveLoadFailed
          ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.archivebox'))
          .fontSize(26).fontColor([Color.White]);
      }
      .width(AVATAR_SIZE).height(AVATAR_SIZE)
      .borderRadius(AVATAR_SIZE / 2)
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .backgroundColor(this.archiveLoadFailed ? '#E64646' : COLOR_MUTED_BADGE);
      Text(this.archiveLoadFailed ? $r('app.string.cl_archive_failed_tap') : $r('app.string.ap_title'))
        .fontSize(17).fontWeight(FontWeight.Medium)
        .fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
    }
    .width('100%').height(ARCHIVE_ROW_HEIGHT)
    .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.archiveLoadFailed) { this.retryArchive(); } else { this.openArchive(); }
    });
  }

  @Builder
  chatList() {
    // initialIndex 让首帧就停在第 1 行——归档行在第 0 行，这样它一开始就在视口
    // 之上。initialIndex 只在创建时生效，之后归档桶从无到有的情况由
    // onArchiveRowToggled 兜底。
    List({ scroller: this.listScroller, initialIndex: this.archiveRowShown() ? 1 : 0 }) {
      if (this.archiveRowShown()) {
        ListItem() { this.archiveHeader(); }
        // 收进标题栏底下时必须**完全看不见**：列表是 clip(false) 的（滚动模糊
        // 需要内容穿到标题栏下面），单靠滚出视口，这一行还会透过标题栏的玻璃
        // 隐约露着。所以透明度跟着滚动走——收好（偏移≥行高）时为 0，下拉把它
        // 往外拉的过程中渐显。
        .opacity(Math.min(1, Math.max(0,
          (ARCHIVE_ROW_HEIGHT - this.listTopOffset) / ARCHIVE_ROW_HEIGHT)))
      }
      // LazyForEach, not ForEach: ForEach builds every row up front, which for
      // a real account meant hundreds of live ChatRow components for the eight
      // that are visible.
      LazyForEach(this.chatsData, (item: ChatEntry) => {
        ListItem() { ChatRow({ chat: item, listKey: 'main' }); }
      }, (item: ChatEntry, index: number) =>
        guardKey(this.chatsData.keyTableId, index, this.rowKey(item)));
    }
    .layoutWeight(1).width('100%')
    .cachedCount(8, true)
    // cachedCount 的第二个参数 true 与这里的 clip(false) 是一对：前者让滚出
    // 视口的行不被回收，后者让它画得出来。官方《设置动态模糊样式》点名过——
    // 列表穿透到标题栏下方时缺了任一个，标题栏底下就是空的，渐变模糊没有
    // 东西可糊。
    .clip(false)
    .edgeEffect(EdgeEffect.Spring)
    .enableScrollInteraction(!this.menuOpen)
    .scrollBar(BarState.Off)
    .contentEndOffset(this.bottomSafe + 88)
    .contentStartOffset(this.contentTopInset)
    .onDidScroll((): void => {
      // 只在归档行可能可见的区间里刷状态，翻到下面去之后没必要每帧驱动重绘。
      const y: number = this.listScroller.currentOffset().yOffset;
      if (y <= ARCHIVE_ROW_HEIGHT + 1 || this.listTopOffset <= ARCHIVE_ROW_HEIGHT) {
        this.listTopOffset = y;
      }
    })
    // 归档行的吸附门槛：轻轻一划就把它整行带出来太廉价，也容易误触。松手后
    // 停在"半露"区间时二选一——拉出来不到六成弹回收起，过了六成吸附到全露。
    // 想拉出来就得带点力度，和 Telegram 的手感一致。
    //
    // onScrollStop 在滚动完全停下（含惯性走完）后触发一次，在这里补位不会和
    // 用户手上的动作打架。
    .onScrollStop((): void => {
      if (!this.archiveRowShown()) {
        return;
      }
      const y: number = this.listScroller.currentOffset().yOffset;
      if (y <= 0 || y >= ARCHIVE_ROW_HEIGHT) {
        return;
      }
      const target: number = y > ARCHIVE_ROW_HEIGHT * 0.4 ? ARCHIVE_ROW_HEIGHT : 0;
      this.listScroller.scrollTo({
        xOffset: 0, yOffset: target,
        animation: { duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160), curve: Curve.EaseOut }
      });
    })
    .onReachEnd(() => { getChatStore().loadMore('main'); });
  }

  build() {
    Column() {
      // No story ring here — stories live on the profile pages. StoryStore and
      // StoryViewerPage are kept, but nothing on the chat list launches them.
      //
      // 归档入口不再包一层 Refresh：它现在是列表自己的第 0 行，靠 initialIndex
      // 藏在视口之上，下拉即现。见 archiveHeader。
      this.chatList();
    }
    .width('100%').layoutWeight(1)
    // 本组件的根节点。HdsNavigation → Tabs → TabContent → Column → 这里 →
    // ChatListView 的 List，整条链上任何一层裁剪，穿到标题栏底下的那部分就被
    // 切掉，滚动模糊没有东西可糊。之前只有这一层漏了，真机上表现为列表在文件夹
    // 横条下缘被一刀切平。
    .clip(false);
  }
}
