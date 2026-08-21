import { router } from '@kit.ArkUI';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { ChatListDataSource } from './ChatListDataSource';
import { guardKey } from '../../util/keyGuard';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const ARCHIVE_ROW_HEIGHT: number = 56;

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

  // 归档行是**插在列表顶端之上**的，插进去会把内容整体下推一行高。列表还停在
  // 顶端时要顺手把它滚掉，用户才看不见；已经滚下去了就不动，免得把人拽回顶部。
  //
  // 延后一帧：@Watch 在状态写入时就跑，那一刻新行还没进布局，scrollToIndex(1)
  // 会滚到一个不存在的位置。
  private onArchiveRowToggled(): void {
    if (!this.archiveRowShown()) {
      return;
    }
    setTimeout((): void => {
      if (this.listScroller.currentOffset().yOffset <= 1) {
        this.listScroller.scrollToIndex(1);
      }
    }, 0);
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
    Row() {
      SymbolGlyph(this.archiveLoadFailed
        ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.archivebox'))
        .fontSize(22).fontColor([COLOR_TEXT_SECONDARY]).margin({ right: 12 });
      Text(this.archiveLoadFailed ? $r('app.string.cl_archive_failed_tap') : $r('app.string.ap_title'))
        .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
    }
    .width('100%').height(ARCHIVE_ROW_HEIGHT).padding({ left: 14, right: 14 })
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
