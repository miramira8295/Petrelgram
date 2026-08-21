import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { ChatListDataSource } from './ChatListDataSource';
import { guardKey } from '../../util/keyGuard';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

@Component
export struct ChatListView {
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLanguageEpochChanged') langEpoch: number = 0;
  @Prop listKey: string;
  // Folder tabs sit behind MainScreen's floating dock; ArchivePage does not.
  @Prop reserveDockSpace: boolean = true;
  // Floating frosted folder bar overlays the list top — start content below
  // it while still letting rows scroll (blurred) underneath.
  // 顶部悬浮 chrome（顶栏 + 文件夹条）的总高度。改成数值是因为顶栏也浮起来
  // 了：列表从它底下穿过去，才有玻璃透隐可看。原来是个布尔，只够表达"有没有
  // 文件夹条"。
  @Prop contentTopInset: number = 0;
  // 由 ChatListPage 传进来，每个文件夹页签一个。HdsNavigation 靠它拿到滚动量
  // 才能驱动标题栏收缩与渐变模糊；页签里的列表在子组件内部，父层拿不到，
  // 只能这样把控制器递下来。
  listScroller: Scroller = new Scroller();
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  @State chats: ChatEntry[] = [];
  @State loading: boolean = true;
  @State loadFailed: boolean = false;
  @State paging: boolean = false;
  @State pagingFailed: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  private chatsData: ChatListDataSource = new ChatListDataSource();
  private unsubscribe: (() => void) | null = null;
  private active: boolean = false;

  // 行 key 里带着 langEpoch。ForEach 时它一变就等于所有行改名、整表重建；
  // 换成 LazyForEach 之后没人会替我们做这件事，得显式告诉数据源。
  // 与 MainTabBody.onLanguageEpochChanged 同理。
  private onLanguageEpochChanged(): void {
    this.chatsData.reload();
  }

  @Styles
  actionNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  actionPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.96, y: 0.96 })
  }

  aboutToAppear(): void {
    this.active = true;
    const store = getChatStore();
    this.unsubscribe = store.subscribe((list: ChatEntry[]) => {
      const next = this.updateGate.accept(list);
      if (next !== null) {
        this.applyChats(next);
      }
    }, this.listKey);
    this.loadInitial();
  }

  private loadInitial(): void {
    this.loading = true;
    this.loadFailed = false;
    const store = getChatStore();
    store.ensureLoaded(this.listKey).then((success: boolean): void => {
      if (!this.active) { return; }
      // TDLib normally emits the positions before resolving loadChats. Read
      // the bucket once here as well so the empty state can't flash while the
      // coalesced store notification is still waiting for the next frame.
      const next = this.updateGate.accept(store.getChats(this.listKey));
      if (next !== null) { this.applyChats(next); }
      this.loading = false;
      this.loadFailed = !success;
    });
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

  // this.chats 仍然留着：空态判断和上面的 structureChanged 比较都要读它。
  // 真正驱动列表的是 chatsData。
  private publishChats(next: ChatEntry[]): void {
    this.chats = next;
    this.chatsData.update(next, next.map((item: ChatEntry): string => this.rowKey(item)));
  }

  // langEpoch in the key: see MainTabBody.rowKey.
  private rowKey(item: ChatEntry): string {
    const pinned = getChatStore().isPinned(this.listKey, item.id) ? 1 : 0;
    return `${item.id}_${item.revision}_${pinned}_${this.langEpoch}`;
  }

  private loadMore(): void {
    const store = getChatStore();
    if (this.paging || store.isListExhausted(this.listKey)) {
      return;
    }
    this.paging = true;
    this.pagingFailed = false;
    store.loadMore(this.listKey).then((success: boolean): void => {
      if (!this.active) { return; }
      this.paging = false;
      this.pagingFailed = !success;
    });
  }

  private endInset(): number {
    return this.bottomSafe + (this.reserveDockSpace ? 88 : 16);
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

  aboutToDisappear(): void {
    this.active = false;
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
  }

  @Builder
  emptyState() {
    Column({ space: 10 }) {
      if (this.loading) {
        Stack({ alignContent: Alignment.Center }) {
          Circle({ width: 58, height: 58 }).fill($r('app.color.surface_alt'));
          LoadingProgress().width(28).height(28).color(COLOR_PRIMARY);
        }
        Text(this.listKey === 'archive' ? $r('app.string.cl_syncing_archive') : $r('app.string.cl_loading_chats'))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cl_content_appears'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      } else if (this.loadFailed) {
        Row() {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(28).fontColor([COLOR_PRIMARY]);
        }
        .width(58).height(58).borderRadius(29)
        .backgroundColor($r('app.color.surface_alt'))
        .justifyContent(FlexAlign.Center);
        Text(this.listKey === 'archive' ? $r('app.string.cl_archive_failed') : $r('app.string.cl_chats_failed'))
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        Text($r('app.string.cl_check_network'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(14).fontColor([Color.White]);
          Text($r('app.string.settings_reload')).fontSize(14).fontWeight(FontWeight.Medium).fontColor(Color.White);
        }
        .height(38).padding({ left: 15, right: 16 }).borderRadius(19)
        .backgroundColor(COLOR_PRIMARY)
        .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
        .onClick((): void => this.loadInitial());
      } else {
        Row() {
          SymbolGlyph(this.listKey === 'archive'
            ? $r('sys.symbol.archivebox') : $r('sys.symbol.message'))
            .fontSize(27).fontColor([COLOR_TEXT_SECONDARY]);
        }
        .width(56).height(56).borderRadius(28)
        .backgroundColor($r('app.color.surface_alt'))
        .justifyContent(FlexAlign.Center);
        Text(this.listKey === 'archive' ? $r('app.string.cl_no_archived') : $r('app.string.cl_folder_empty'))
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        if (this.listKey === 'archive') {
          Text($r('app.string.cl_archive_hint'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center);
        } else {
          Text($r('app.string.cl_add_hint'))
            .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }
      }
    }
    .layoutWeight(1).width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: this.endInset() })
    .transition(TransitionEffect.OPACITY.animation({
      duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 160),
      curve: Curve.EaseOut
    }));
  }

  build() {
    if (this.chats.length === 0) {
      this.emptyState();
    } else {
      List({ scroller: this.listScroller }) {
        if (this.loadFailed) {
          ListItem() {
            Row({ space: 7 }) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(14).fontColor([COLOR_PRIMARY]);
              Text($r('app.string.cl_archive_sync_failed'))
                .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).layoutWeight(1);
              Text($r('app.string.settings_retry')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
            }
            .height(40).padding({ left: 14, right: 14 })
            .backgroundColor($r('app.color.surface_alt'))
            .onClick((): void => this.loadInitial());
          }
        }
        // LazyForEach 而不是 ForEach：ForEach 会把每一行都提前建出来，
        // 归档和文件夹页签在会话多的账号上一样长（主列表 MainTabBody 早就
        // 迁过去了，:128 的注释记着当时实测 Ids.size[424]）。
        // 上面那个 .cachedCount(8) 配 ForEach 本来是空转的，现在才真正生效。
        LazyForEach(this.chatsData, (item: ChatEntry) => {
          ListItem() {
            ChatRow({ chat: item, listKey: this.listKey });
          }
          .transition(
            TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 12 })).animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.EaseOut
            })
          )
        }, (item: ChatEntry, index: number) =>
          guardKey(this.chatsData.keyTableId, index, this.rowKey(item)));
        if (this.paging) {
          ListItem() {
            Row() {
              LoadingProgress().width(22).height(22).color(COLOR_PRIMARY);
            }.width('100%').height(44).justifyContent(FlexAlign.Center);
          }
        } else if (this.pagingFailed) {
          ListItem() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(13).fontColor([COLOR_PRIMARY]);
              Text($r('app.string.load_more_failed')).fontSize(12).fontColor(COLOR_PRIMARY);
            }
            .width('100%').height(44).justifyContent(FlexAlign.Center)
            .stateStyles({ normal: this.actionNormalStyle, pressed: this.actionPressedStyle })
            .onClick((): void => this.loadMore());
          }
        }
      }
      .layoutWeight(1).width('100%')
      .cachedCount(8, true)
      // cachedCount 的第二个参数 true 与这里的 clip(false) 是一对：前者让滚出
      // 视口的行不被回收，后者让它画得出来。官方《设置动态模糊样式》点名过——
      // 列表穿透到标题栏下方时缺了任一个，标题栏底下就是空的，渐变模糊没有
      // 东西可糊。
      .clip(false)
      .edgeEffect(EdgeEffect.Spring)
      // Stop touch scrolling as soon as the long-press menu begins to appear.
      // This prevents residual spring/inertia from shifting the source row
      // while ArkUI captures its floating preview.
      .enableScrollInteraction(!this.menuOpen)
      .scrollBar(BarState.Off)
      .contentEndOffset(this.endInset())
      .contentStartOffset(this.contentTopInset)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .onReachEnd(() => { this.loadMore(); });
    }
  }
}
