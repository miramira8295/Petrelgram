import { router } from '@kit.ArkUI';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry } from '../../store/ChatEntry';
import { ChatRow } from './ChatRow';
import { ChatListDataSource } from './ChatListDataSource';
import { guardKey } from '../../util/keyGuard';
import { CHAT_MENU_OPEN, ChatListFreeze } from './ChatListFreeze';
import { CHAT_LIST_FLUSH_EPOCH, CHAT_LIST_RENDER_ACTIVE_KEY } from '../../util/chatListRenderGate';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import {
  AVATAR_SIZE, COLOR_MUTED_BADGE, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY,
  ROW_PAD_H, ROW_PAD_V
} from '../../util/theme';
import { SCOPE_MUTE_EPOCH } from '../../store/ScopeMuteStore';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { navigateToArchive } from '../../util/profileNav';
import { APPEARANCE_EPOCH } from '../../util/appearance';

// 与普通会话行同一套规格：头像 AVATAR_SIZE(56) + 上下 ROW_PAD_V(8)。归档入口
// 长得和会话行一个个头，拉出来时才不显得是另一种东西。
const ARCHIVE_ROW_HEIGHT: number = AVATAR_SIZE + ROW_PAD_V * 2;
// 归档行完全展开需要把顶部回弹拉多深（vp）。回弹带阻尼，这 96vp 对应一大段
// 实打实的手指行程——"不好出现"的力度感全在这。要松就调小。
const ARCHIVE_OVERPULL: number = 96;

@Preview
@Component
export struct MainTabBody {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // See ChatPage: the row key embeds this, so the data source must be told.
  @StorageProp(LANGUAGE_EPOCH) @Watch('onLanguageEpochChanged') langEpoch: number = 0;
  // 见 ChatListView 上的同名字段。
  @StorageProp(SCOPE_MUTE_EPOCH) @Watch('onLanguageEpochChanged') scopeMuteEpoch: number = 0;
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
  @StorageProp(CHAT_LIST_RENDER_ACTIVE_KEY) @Watch('onRenderGateChanged')
  private renderActive: boolean = true;
  @StorageProp(CHAT_LIST_FLUSH_EPOCH) @Watch('onFlushRequested')
  private flushEpoch: number = 0;
  @State chats: ChatEntry[] = [];
  private chatsData: ChatListDataSource = new ChatListDataSource();
  @State showArchive: boolean = false;
  @State archiveLoadFailed: boolean = false;
  private updateGate: ChatListFreeze = new ChatListFreeze();
  private unsubscribe: (() => void) | null = null;
  private unsubArchive: (() => void) | null = null;
  // 归档行的展开高度（0..行高），只由顶部回弹深度驱动。
  @State private archivePullPx: number = 0;
  // 拽到全展开后锁定；再往下滚一段自动收起。
  @State private archiveRevealed: boolean = false;

  private onLanguageEpochChanged(): void {
    this.chatsData.reload();
  }

  private flushBufferedChats(): void {
    if (this.menuOpen || !this.renderActive) {
      return;
    }
    const next = this.updateGate.flush();
    if (next !== null) {
      this.applyChats(next);
    }
  }

  private onMenuToggle(): void {
    this.flushBufferedChats();
  }

  private onRenderGateChanged(): void {
    this.flushBufferedChats();
  }

  // 闸还关着时的一次性刷新（issue #159，见 util/chatListRenderGate）：只发内容
  // 变更（身份顺序没变），顺序变了的放回缓冲等闸开。闸开着时走正常路。
  private onFlushRequested(): void {
    if (this.menuOpen || this.renderActive) {
      return;
    }
    const next = this.updateGate.flush();
    if (next === null) {
      return;
    }
    const sameOrder: boolean = this.chats.length === next.length &&
      this.chats.every((item: ChatEntry, index: number): boolean => item.id === next[index].id);
    if (sameOrder) {
      this.publishChats(next);
    } else {
      this.updateGate.accept(next, false);
    }
  }

  aboutToAppear(): void {
    const store = getChatStore();
    this.unsubscribe = store.subscribe((list: ChatEntry[]) => {
      const next = this.updateGate.accept(list, this.renderActive);
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
    return `${item.id}_${item.revision}_${pinned}_${this.langEpoch}_${this.scopeMuteEpoch}`;
  }

  // 归档入口是否作为列表第 0 行存在。
  private archiveRowShown(): boolean {
    return this.showArchive || this.archiveLoadFailed;
  }

  private openArchive(): void {
    // 曾经是 router.pushUrl('pages/chatlist/ArchivePage')——归档页已迁成
    // HdsNavDestination 并从 main_pages.json 摘出，整页路由跳不动，走漏斗。
    navigateToArchive();
  }

  private retryArchive(): void {
    this.archiveLoadFailed = false;
    getChatStore().ensureLoaded('archive').then((success: boolean): void => {
      this.archiveLoadFailed = !success;
    });
  }

  // 归档入口行。默认完全不存在；把顶部回弹拽到底才展开并停留（见 build 里的
  // 折叠容器与 onDidScroll）。曾经做成 Refresh（松手直接跳转，误触率高）和
  // 列表第 0 行（普通滚动一拉就 1:1 全露，毫无门槛），都被否了。
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
    // One screen contains roughly eight rows. Four follows the framework's
    // n/2 guidance while preserving enough painted cache for the frosted title
    // bar; eight caused hidden tab lists to prebuild ChatRows during chat push.
    .cachedCount(4, true)
    // cachedCount 的第二个参数 true 与这里的 clip(false) 是一对：前者让滚出
    // 视口的行不被回收，后者让它画得出来。官方《设置动态模糊样式》点名过——
    // 列表穿透到标题栏下方时缺了任一个，标题栏底下就是空的，渐变模糊没有
    // 东西可糊。
    .clip(false)
    // 归档入口依赖顶部回弹位移；即使会话不足一屏，也要允许下拉展开。
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .enableScrollInteraction(!this.menuOpen)
    .scrollBar(BarState.Off)
    .contentEndOffset(this.bottomSafe + 88)
    .contentStartOffset(this.contentTopInset)
    .onDidScroll((_offset: number, state: ScrollState): void => {
      const y: number = this.listScroller.currentOffset().yOffset;
      if (!this.archiveRevealed && this.archiveRowShown() && y < 0 &&
        state === ScrollState.Scroll) {
        // 展开只吃**手指拖动**的回弹深度（惯性冲进回弹区不算）。回弹自带阻尼，
        // 这一段越拉越沉——"不好出现"就是它。拽到全展开的瞬间锁定。
        const pull: number = Math.min(ARCHIVE_ROW_HEIGHT,
          -y * ARCHIVE_ROW_HEIGHT / ARCHIVE_OVERPULL);
        this.archivePullPx = pull;
        if (pull >= ARCHIVE_ROW_HEIGHT) {
          this.archiveRevealed = true;
        }
      } else if (!this.archiveRevealed && this.archivePullPx > 0) {
        // 没拽到底就松手/惯性阶段：跟着回弹的衰减一起缩回去。
        this.archivePullPx = y < 0
          ? Math.min(ARCHIVE_ROW_HEIGHT, -y * ARCHIVE_ROW_HEIGHT / ARCHIVE_OVERPULL)
          : 0;
      } else if (this.archiveRevealed && y > ARCHIVE_ROW_HEIGHT * 2) {
        // 已展开后往下滚一段，自动收起；下次要看还得再用力拉一次。
        animateTo({
          duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
          curve: Curve.EaseOut
        }, (): void => {
          this.archiveRevealed = false;
          this.archivePullPx = 0;
        });
      }
    })
    .onReachEnd(() => { getChatStore().loadMore('main'); });
  }

  build() {
    Column() {
      // No story ring here — stories live on the profile pages. StoryStore and
      // StoryViewerPage are kept, but nothing on the chat list launches them.
      //
      // 归档入口不在列表里，是列表上方的一个折叠容器：展开高度只由顶部回弹
      // 深度驱动（见 onDidScroll）。不在列表里，就不存在"藏在第 0 行"的一切
      // 收起时序问题；高度为 0 时它完全不占布局、也画不出来。
      if (this.archiveRowShown() && (this.archiveRevealed || this.archivePullPx > 0)) {
        Stack({ alignContent: Alignment.Bottom }) {
          this.archiveHeader();
        }
        .width('100%')
        .height(this.archiveRevealed ? ARCHIVE_ROW_HEIGHT : this.archivePullPx)
        .clip(true)
        .opacity(this.archiveRevealed ? 1 : this.archivePullPx / ARCHIVE_ROW_HEIGHT);
      }
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
