import { router } from '@kit.ArkUI';
import { ChatListView } from './ChatListView';
import { CHAT_LIST_NOW } from './ChatListFreeze';
import { ChatEntry } from '../../store/ChatEntry';
import { getChatStore, getUnreadCountStore } from '../../tdkit/Globals';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { HdsNavDestination } from '@kit.UIDesignKit';

// 路由表（router_map.json）的 buildFunction 指向这里。系统在跳转时动态加载
// 本模块并调用它，页面因此不再需要进 main_pages.json。
@Builder
export function ArchivePageBuilder(): void {
  ArchivePage();
}

@Preview
@Component
export struct ArchivePage {
  // 本页所在的 Navigation 栈，onReady 时拿到。返回按钮要靠它出栈——迁成
  // NavDestination 之后 router.back() 弹的是 router 页栈，而本页已经不是
  // router 页了，弹不到自己。
  private navStack: NavPathStack | undefined = undefined;

  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @State archivedCount: number = 0;
  @State unreadCount: number = 0;
  private clockTimer: number = -1;
  private unsubscribeChats: (() => void) | null = null;
  private unsubscribeUnread: (() => void) | null = null;

  @Styles
  backNormalStyle() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  backPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
  }

  // 本页不读路由参数（归档列表没有入参），所以没有 ChatPage 那套
  // applyRouteParams()/paramsApplied 的拆分——aboutToAppear 原样保留。
  aboutToAppear(): void {
    this.unsubscribeChats = getChatStore().subscribe((chats: ChatEntry[]): void => {
      this.archivedCount = chats.length;
    }, 'archive');
    this.unsubscribeUnread = getUnreadCountStore().subscribe((): void => {
      this.unreadCount = getUnreadCountStore().getUnread('archive');
    });
    AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    this.clockTimer = setInterval((): void => {
      AppStorage.setOrCreate(CHAT_LIST_NOW, Math.floor(Date.now() / 1000));
    }, 60000);
  }

  aboutToDisappear(): void {
    if (this.unsubscribeChats !== null) {
      this.unsubscribeChats();
      this.unsubscribeChats = null;
    }
    if (this.unsubscribeUnread !== null) {
      this.unsubscribeUnread();
      this.unsubscribeUnread = null;
    }
    if (this.clockTimer !== -1) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
  }

  // 返回上一层。迁成 NavDestination 前这里是 router.back()。
  private goBack(): void {
    const stack = this.navStack;
    if (stack !== undefined) {
      stack.pop();
      return;
    }
    // 栈没拿到（理论上 onReady 必先于点击，留着兜底）时退回老路径。
    router.back();
  }

  private archiveSummary(): string {
    if (this.archivedCount === 0) { return str('ap_subtitle'); }
    if (this.unreadCount > 0) {
      return str('ap_chats_and_unread', this.archivedCount, this.unreadCount);
    }
    return plural('ap_chats_n', this.archivedCount, this.archivedCount);
  }

  build() {
    HdsNavDestination() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
        }
        .width(44).height(44).borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.backNormalStyle,
          pressed: this.backPressedStyle
        })
        .onClick(() => { this.goBack(); });
        Column({ space: 1 }) {
          Text($r('app.string.ap_title'))
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
          Text(this.archiveSummary())
            .fontSize(11).fontColor(this.unreadCount > 0 ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start).margin({ left: 4 });
      }
      .width('100%').height(this.topSafe + 62)
      .padding({ left: 6, right: 16, top: this.topSafe })
      .backgroundColor($r('app.color.surface'))
      .border({ width: { bottom: 0.5 }, color: $r('app.color.divider') });
      ChatListView({ listKey: 'archive', reserveDockSpace: false });
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    }
    // 本页自绘标题栏（返回键 + 「归档」标题那一条），不要 HDS 的。
    .hideTitleBar(true)
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
    })
    .width('100%').height('100%');
  }
}
