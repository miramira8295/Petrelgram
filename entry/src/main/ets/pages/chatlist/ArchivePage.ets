import { collapseFloatingVideo } from '../../util/floatingVideoRuntime';
import { ChatListView } from './ChatListView';
import { CHAT_LIST_NOW } from './ChatListFreeze';
import { ChatEntry } from '../../store/ChatEntry';
import { getChatStore, getUnreadCountStore } from '../../tdkit/Globals';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { allocChatDestToken, markChatDestHidden, markChatDestShown } from '../../util/chatDestTracker';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { logE } from '../../util/log';
import { BLUR_MAX_VP, EDGE_OVERLAY_VP, edgeBlurStops } from '../../util/scrollEdgeBlur';

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
  // NavDestination 之后 this.getUIContext().getRouter().back() 弹的是 router 页栈，而本页已经不是
  // router 页了，弹不到自己。
  private navStack: NavPathStack | undefined = undefined;
  private readonly chatDestToken: number = allocChatDestToken();

  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  // 本页在不在眼前。被会话页盖住时置 false，退回来置 true——归档列表的发布闸
  // 跟这个走而不是跟全局那道（理由见 ChatListView.obeyGlobalGate：全局那道由
  // 首页导航栏的显隐驱动，而归档页在时导航栏自始至终是盖着的，开不回来）。
  @State private pageVisible: boolean = true;
  // 列表容器的高度，用来把边缘虚化的 fractionStops 归一化（0..1）。容器尺寸变了
  // 才写，避免每帧刷新触发重排。
  @State private bodyH: number = 0;
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
    markChatDestHidden(this.chatDestToken, true);
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

  // 返回上一层。**不能用 this.getUIContext().getRouter().back()**：本页是 HdsNavDestination，router 页栈里
  // 只剩 Index 一层，this.getUIContext().getRouter().back() 弹掉的是 Index——平板模拟器实测（Task 7 修复轮 1）
  // 的现象是「点返回箭头直接退到桌面」。要出的是 Navigation 栈。
  private goBack(): void {
    const stack = this.navStack;
    if (stack === undefined) {
      // navStack 由 onReady(ctx.pathStack) 填，而 onReady 必先于本页可见，所以
      // 这一支不该发生。这里**故意不回退到 this.getUIContext().getRouter().back()**：那正是会退出应用的
      // 那条路，把返回键做成"什么都不做 + 一条日志"远比把应用关掉好。
      logE('ArchivePage.goBack: navStack missing, back ignored');
      return;
    }
    // pop() 弹的就是本页这一层。栈空时它返回 undefined，但那意味着"本页正显示
    // 却不在栈里"，不可能发生，故不另做处理。
    stack.pop();
  }

  private archiveSummary(): string {
    if (this.archivedCount === 0) { return str('ap_subtitle'); }
    if (this.unreadCount > 0) {
      return str('ap_chats_and_unread', this.archivedCount, this.unreadCount);
    }
    return plural('ap_chats_n', this.archivedCount, this.archivedCount);
  }

  // 标题条高度：状态栏让位 + 56 的行高。列表的首行位置也用这个值，两者必须同源。
  private headerHeight(): number {
    return this.topSafe + 62;
  }

  build() {
    HdsNavDestination() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 列表铺满整页并往上顶：内容从标题条底下穿过去，标题条本身是透明的，
      // 靠 linearGradientBlur 只虚化顶部一条，落到标题上的内容自然淡出。
      // 注意 linearGradientBlur 是容器级属性，必须挂在包裹 List 的容器上。
      Column() {
        ChatListView({
          listKey: 'archive',
          reserveDockSpace: false,
          obeyGlobalGate: false,
          pageVisible: this.pageVisible,
          contentTopInset: this.headerHeight()
        });
      }
      .width('100%').height('100%')
      .linearGradientBlur(BLUR_MAX_VP, {
        fractionStops: edgeBlurStops(this.bodyH),
        direction: GradientDirection.Bottom
      })
      .clip(false)
      .onAreaChange((oldArea: Area, newArea: Area): void => {
        const h: number = Number(newArea.height);
        if (h > 0 && Math.abs(h - this.bodyH) > 0.5) {
          this.bodyH = h;
        }
      });
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
      .width('100%').height(this.headerHeight())
      .padding({ left: 6, right: 16, top: this.topSafe })
      .backgroundColor(Color.Transparent)
      // 标题条只负责画，不负责挡手指：触摸要穿到下面的列表去。
      .hitTestBehavior(HitTestMode.Transparent);
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
    }
    // 本页自绘标题栏（返回键 + 「归档」标题那一条），不要 HDS 的。
    .hideTitleBar(true)
    .onBackPressed((): boolean => collapseFloatingVideo())
    .onReady((ctx: NavDestinationContext): void => {
      this.navStack = ctx.pathStack;
    })
    // 盖住时停发、露出时补发。归档列表的未读角标就靠这一对回来
    //（2026-09-18：点进会话看完退回来，角标一直挂着）。
    .onWillShow((): void => { markChatDestShown(this.chatDestToken); })
    .onShown((): void => {
      markChatDestShown(this.chatDestToken);
      this.pageVisible = true;
    })
    .onHidden((): void => {
      markChatDestHidden(this.chatDestToken);
      this.pageVisible = false;
    })
    .width('100%').height('100%');
  }
}
