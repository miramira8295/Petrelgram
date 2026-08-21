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
  @State showArchive: boolean = false;
  @State archiveLoadFailed: boolean = false;
  @State refreshing: boolean = false;
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

  private openArchive(): void {
    router.pushUrl({ url: 'pages/chatlist/ArchivePage' });
  }

  private retryArchive(): void {
    this.archiveLoadFailed = false;
    getChatStore().ensureLoaded('archive').then((success: boolean): void => {
      this.archiveLoadFailed = !success;
    });
  }

  // Revealed only while the user over-scrolls (pulls down) at the top.
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
    List({ scroller: this.listScroller }) {
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
    if (this.showArchive || this.archiveLoadFailed) {
      Refresh({ refreshing: $$this.refreshing, builder: this.archiveHeader() }) {
        this.chatList();
      }
      .layoutWeight(1).width('100%')
      // 停留/触发高度钉在归档行高，否则默认下拉区比一行高得多（"很高"）。
      .refreshOffset(ARCHIVE_ROW_HEIGHT)
      .pullToRefresh(true)
      .onRefreshing(() => {
        // 同步复位会被 Refresh 忽略（进入 Refreshing 当帧的状态写丢失），
        // 下拉区就永远收不回去；下一帧异步复位。
        setTimeout((): void => {
          this.refreshing = false;
        }, 60);
        if (this.archiveLoadFailed) { this.retryArchive(); } else { this.openArchive(); }
      });
    } else {
      this.chatList();
    }
    }
    .width('100%').layoutWeight(1);
  }
}
