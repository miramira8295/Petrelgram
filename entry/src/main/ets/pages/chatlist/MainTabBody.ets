import { curves, router } from '@kit.ArkUI';
import { KEY_DOCK_AT_BOTTOM } from '../../util/splitMetrics';
import {
  archiveCardScale, archiveIconScale, archiveIconSpin, archiveRevealProgress
} from '../../util/archiveReveal';
import { getChatStore } from '../../tdkit/Globals';
import { ChatEntry, effectiveMuted } from '../../store/ChatEntry';
import { CHAT_ROW_SIDE_GUTTER, ChatRow } from './ChatRow';
import { KEY_APP_BG_ON } from '../../store/AppSettings';
import { MATERIAL_EPOCH, overlayBackdropBlur, overlayGlassFill } from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';
import { COLOR_DIVIDER, mainCardFill } from '../../util/theme';
import { formatTime } from '../../util/formatTime';
import { ChatListDataSource } from './ChatListDataSource';
import { guardKey } from '../../util/keyGuard';
import { CHAT_LIST_TOUCH_HOLD, CHAT_MENU_OPEN, ChatListFreeze, updateTouchHold } from './ChatListFreeze';
import { CHAT_LIST_FLUSH_EPOCH, CHAT_LIST_RENDER_ACTIVE_KEY } from '../../util/chatListRenderGate';
import {
  KEY_POWER_SMOOTH_TRANSITIONS, KEY_ROW_SWIPE_ACTIONS, powerAnimationDuration
} from '../../store/AppSettings';
import {
  AVATAR_SIZE, COLOR_MUTED_BADGE, COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY,
  ROW_PAD_H, ROW_PAD_V
} from '../../util/theme';
import { SCOPE_MUTE_EPOCH, scopeMutedForKind } from '../../store/ScopeMuteStore';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { navigateToArchive } from '../../util/profileNav';
import { rememberListPosition, recallListPosition } from '../../util/chatListPosition';
import { APPEARANCE_EPOCH } from '../../util/appearance';
import {
  isPriorityUnread, TAB_RETAP_EPOCH, TAB_RETAP_INDEX, nextUnreadIndex, reTapAction,
  RETAP_SMOOTH_SPAN, smoothJumpStage
} from '../../util/tabReTap';
import { markAsRead, markUnread, setArchived, setMute, MUTE_LONG } from '../../store/ChatActions';

// 与普通会话行同一套规格：头像 AVATAR_SIZE(56) + 上下 ROW_PAD_V(8)。归档入口
// 长得和会话行一个个头，拉出来时才不显得是另一种东西。
const ARCHIVE_ROW_HEIGHT: number = AVATAR_SIZE + ROW_PAD_V * 2;
// 归档卡片与上方文件夹条之间的空当。
const ARCHIVE_TOP_GAP: number = 8;
// 归档行完全展开需要把顶部回弹拉多深（vp）。回弹带阻尼，这 96vp 对应一大段
// 实打实的手指行程——"不好出现"的力度感全在这。要松就调小。
const ARCHIVE_OVERPULL: number = 96;
// 展开后滚多远自动收起。
//
// **只要开始滚，就收。** issue #186 的病根不是"谁盖谁"，而是"归档条和已经滚起来
// 的列表同时在屏上"这件事本身：列表那边是 clip(false) + cachedCount(…, true) 的
// 一对，滚出视口的行不回收、而且**故意画在列表边界之外**（好让标题栏底下的滚动
// 模糊有东西可糊）。归档条正落在那条带里，于是两者必然重叠——先是聊天卡片盖住
// 归档（原报告），把 zIndex 抬上去之后变成归档盖住聊天（用户："归档叠加在聊天
// 上面了"）。翻个面不解决问题，**不让它们同时出现**才解决。
//
// 阈值取 8 而不是 0：从过拉松手后弹回 0 的过程里 yOffset 可能有几个像素的抖动，
// 留一点余量，免得刚拉出来就自己收回去。滚过 8vp 说明用户确实在往下走了。
//
// 原值是 ARCHIVE_ROW_HEIGHT * 2（144vp）——那 144vp 就是重叠暴露的那段窗口。
const ARCHIVE_COLLAPSE_SCROLL: number = 8;

// 与 ChatListView 保持同一套滑动规格。主列表和文件夹列表是两个独立组件，
// 交互设置必须分别接入，不能只在文件夹列表上挂 swipeAction。
const SWIPE_BUTTON_VP: number = 76;
const SWIPE_TRIGGER_VP: number = 76;
const SWIPE_READ_BG: string = '#3390EC';
const SWIPE_MUTE_BG: string = '#8E8E93';
const SWIPE_ARCHIVE_BG: string = '#F09A37';

@Preview
@Component
export struct MainTabBody {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @StorageProp(KEY_DOCK_AT_BOTTOM) private dockBottom: boolean = true;
  // 归档入口要和会话卡片长一样，就得订阅同样这两个：壁纸开关决定给不给玻璃，
  // 材质纪元让用户改厚度/光感后这一行跟着重绘（同 ChatRow）。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(KEY_APP_BG_ON) private appWallpaperOn: boolean = false;
  // 归档里最新的那条会话。**只在归档入口真正露出来时才算**——ChatStore.getChats
  // 会把整桶拼成一个数组（排序结果本身是缓存的，拼数组不是），而这一行原本的
  // 注释就写着「只需要一个失效信号，避免为了推导一个布尔值就把整个归档桶排一遍」。
  // 所以这里守住同一条底线：没露出来时不算，露出来之后才跟着变化刷新。
  @State private archiveTop: ChatEntry | null = null;
  @StorageProp(KEY_ROW_SWIPE_ACTIONS) rowSwipeEnabled: boolean = false;
  // “所有”页使用独立列表组件，也要单独响应底栏重复点击（issue #35）。
  @StorageProp(TAB_RETAP_EPOCH) @Watch('onTabReTap') tabReTapEpoch: number = 0;
  private topVisible: boolean = true;
  private firstVisibleIndex: number = 0;
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
  listScroller: ListScroller = new ListScroller();
  // Rebuilding rows while a row's context menu is open would close it.
  @StorageProp(CHAT_MENU_OPEN) @Watch('onMenuToggle') menuOpen: boolean = false;
  // 手指按在列表上时同样缓冲发布（长按跑行的根修，见 ChatListFreeze）。
  @StorageProp(CHAT_LIST_TOUCH_HOLD) @Watch('onTouchHoldToggle') touchHold: boolean = false;
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

  private onTabReTap(): void {
    if ((AppStorage.get<number>(TAB_RETAP_INDEX) ?? 0) !== 0) {
      return;
    }
    const unread: boolean[] = this.chats.map((chat: ChatEntry): boolean =>
      isPriorityUnread(chat.unreadCount, chat.isMarkedUnread, this.rowMuted(chat)));
    const action: string = reTapAction(this.topVisible,
      unread.some((value: boolean): boolean => value));
    if (action === 'top') {
      this.jumpToRow(0);
      return;
    }
    if (action === 'none') {
      return;
    }
    const target: number = nextUnreadIndex(unread, this.firstVisibleIndex);
    this.jumpToRow(target >= 0 ? target : 0);
  }

  // 见 ChatListView.jumpToRow 同款注释：远距离平滑滚动逐行构建沿途内容
  //（实测跳 169 行 = 单帧 618ms），先无动画中转再平滑最后一屏。
  private jumpToRow(index: number): void {
    const stage = smoothJumpStage(this.firstVisibleIndex, index, RETAP_SMOOTH_SPAN);
    if (stage >= 0) {
      this.listScroller.scrollToIndex(stage, false, ScrollAlign.START);
    }
    this.listScroller.scrollToIndex(index, true, ScrollAlign.START);
  }

  private onLanguageEpochChanged(): void {
    this.chatsData.reload();
  }

  private flushBufferedChats(): void {
    if (this.menuOpen || this.touchHold || !this.renderActive) {
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

  private onTouchHoldToggle(): void {
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
      this.refreshArchiveTop();
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

  private rowUnread(chat: ChatEntry): boolean {
    return chat.unreadCount > 0 || chat.isMarkedUnread;
  }

  private rowMuted(chat: ChatEntry): boolean {
    return effectiveMuted(chat, scopeMutedForKind(chat.kind));
  }

  private toggleRead(chat: ChatEntry): void {
    if (this.rowUnread(chat)) {
      markAsRead(chat.id, chat.lastMessageId);
    } else {
      markUnread(chat.id, true);
    }
  }

  private toggleArchive(chat: ChatEntry): void {
    setArchived(chat.id, true);
  }

  private toggleMute(chat: ChatEntry): void {
    setMute(chat.id, this.rowMuted(chat) ? 0 : MUTE_LONG);
  }

  @Builder
  readSwipe(chat: ChatEntry) {
    Row() {
      this.swipeButton(
        this.rowUnread(chat) ? $r('app.string.cl_mark_read') : $r('app.string.cl_mark_unread'),
        this.rowUnread(chat) ? 'sys.symbol.checkmark_circle' : 'sys.symbol.circle_badge',
        SWIPE_READ_BG,
        (): void => this.toggleRead(chat));
    }
    .height('calc(100% - 6vp)')
    .margin({ left: CHAT_ROW_SIDE_GUTTER, top: 3, bottom: 3 })
    .borderRadius(16)
    .clip(true);
  }

  @Builder
  endSwipe(chat: ChatEntry) {
    Row() {
      this.swipeButton(
        this.rowMuted(chat) ? $r('app.string.cp_unmute') : $r('app.string.cp_mute'),
        this.rowMuted(chat) ? 'sys.symbol.bell' : 'sys.symbol.bell_slash',
        SWIPE_MUTE_BG,
        (): void => this.toggleMute(chat));
      this.swipeButton(
        $r('app.string.cl_archive'),
        'sys.symbol.archivebox',
        SWIPE_ARCHIVE_BG,
        (): void => this.toggleArchive(chat));
    }
    .height('calc(100% - 6vp)')
    .margin({ right: CHAT_ROW_SIDE_GUTTER, top: 3, bottom: 3 })
    .borderRadius(16)
    .clip(true);
  }

  @Builder
  swipeButton(label: ResourceStr, icon: string, background: ResourceColor, action: () => void) {
    Column({ space: 4 }) {
      SymbolGlyph($r(icon)).fontSize(20).fontColor([Color.White]);
      Text(label).fontSize(11).fontColor(Color.White).maxLines(1);
    }
    .width(SWIPE_BUTTON_VP).height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(background)
    .onClick((): void => {
      this.listScroller.closeAllSwipeActions();
      action();
    });
  }

  // 归档入口是否作为列表第 0 行存在。
  // 下拉进度 0..1，驱动卡片与图标的形变（见 util/archiveReveal）。
  private archiveProgress(): number {
    return archiveRevealProgress(this.archivePullPx, ARCHIVE_ROW_HEIGHT, this.archiveRevealed);
  }

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
  // ── 归档入口的卡片外观：**和普通会话行逐项一致** ──────────────────────
  //
  // 原来它是一条裸 Row，只有横向内边距——没有宽度收进、没有外边距、圆角、描边、
  // 玻璃、按压态，所以拉出来之后和下面的会话卡片完全不是一路货。
  //
  // 这三个取值和 ChatRow 的 rowGlassEnabled / rowFill / rowBackdropBlur 逐字相同：
  // 只有 APP 壁纸生效时才给玻璃（纯色页面上给玻璃没有视觉收益，还多一层合成），
  // materialEpoch 不参与计算但必须读到，否则用户改厚度/光感这一行不重绘。
  // 取归档里排第一的那条。入口没露出来时清空，别白算。
  private refreshArchiveTop(): void {
    if (!this.archiveRowShown() || (!this.archiveRevealed && this.archivePullPx <= 0)) {
      this.archiveTop = null;
      return;
    }
    const list: ChatEntry[] = getChatStore().getChats('archive');
    this.archiveTop = list.length > 0 ? list[0] : null;
  }

  private archiveGlassOn(): boolean {
    return this.appWallpaperOn && this.materialEpoch >= 0;
  }

  private archiveFill(pressed: boolean): ResourceColor {
    const solid: ResourceColor = mainCardFill(this.appWallpaperOn, pressed);
    return this.archiveGlassOn() ? overlayGlassFill('card', solid) : solid;
  }

  @Styles
  archiveNormalStyle() {
    .backgroundColor(this.archiveFill(false))
  }

  @Styles
  archivePressedStyle() {
    .backgroundColor(this.archiveFill(true))
  }

  @Builder
  archiveHeader() {
    Row({ space: 12 }) {
      // 照会话行的头像规格画一颗"归档头像"：灰底圆形，白色归档图标。
      // 出错态换成红一点的底和感叹号，一眼能分出"这行现在是重试"。
      Row() {
        SymbolGlyph(this.archiveLoadFailed
          ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.archivebox'))
          .fontSize(26).fontColor([Color.White])
          // 图标的形变比卡片夸张一档（-90°→0、0.6→1），成形感集中在这里。
          // 出错态也照走：那时它是感叹号，转正同样说得通。
          .rotate({ angle: archiveIconSpin(this.archiveProgress()) })
          .scale({
            x: archiveIconScale(this.archiveProgress()),
            y: archiveIconScale(this.archiveProgress())
          });
      }
      .width(AVATAR_SIZE).height(AVATAR_SIZE)
      .borderRadius(AVATAR_SIZE / 2)
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .backgroundColor(this.archiveLoadFailed ? '#E64646' : COLOR_MUTED_BADGE);
      // 标题 + 最新消息预览，字号/颜色与普通会话行逐项相同（17 中粗 / 14 次级，
      // 发送者用强调色）。取不到最新一条时只有标题，行高不变。
      Column({ space: 6 }) {
        Text(this.archiveLoadFailed ? $r('app.string.cl_archive_failed_tap') : $r('app.string.ap_title'))
          .fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(COLOR_TEXT_PRIMARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (!this.archiveLoadFailed && this.archiveTop !== null) {
          Row() {
            Text(`${this.archiveTop?.title ?? ''}: `)
              .fontSize(14).fontColor(COLOR_PRIMARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(0);
            Text(this.archiveTop?.lastMessageText ?? '')
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
          }.width('100%');
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1);
      if (!this.archiveLoadFailed && this.archiveTop !== null) {
        // 和普通会话行一样贴着标题那一行——外层 Row 是垂直居中的，只有这一个
        // 元素时时间会跑到两行的正中间，看着和别的行错位。
        Text(formatTime(this.archiveTop?.lastMessageDate ?? 0, Math.floor(Date.now() / 1000)))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).flexShrink(0)
          .alignSelf(ItemAlign.Start).margin({ top: 3 });
      }
    }
    // 与 ChatRow 的卡片同一套规格：同样的左右收进、外边距、圆角 16、0.5 描边、
    // 玻璃与按压态。
    .width(`calc(100% - ${CHAT_ROW_SIDE_GUTTER * 2}vp)`)
    .margin({ left: CHAT_ROW_SIDE_GUTTER, right: CHAT_ROW_SIDE_GUTTER, top: 3, bottom: 3 })
    .height(ARCHIVE_ROW_HEIGHT)
    .padding({ left: ROW_PAD_H, right: ROW_PAD_H })
    .borderRadius(16)
    .border({ width: this.appWallpaperOn ? 0.5 : 0, color: COLOR_DIVIDER })
    .backdropBlur(this.archiveGlassOn() ? overlayBackdropBlur('card') : 0)
    .attributeModifier(materialModifierWhen('card', this.archiveGlassOn()))
    .clip(true)
    .stateStyles({ normal: this.archiveNormalStyle, pressed: this.archivePressedStyle })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.archiveLoadFailed) { this.retryArchive(); } else { this.openArchive(); }
    });
  }

  @Builder
  chatList() {
    // initialIndex：「所有」页签也可能被 Tabs.cachedMaxCount 释放（用户滑到
    // 3 个文件夹以外时），重建时回到原来的行。见 util/chatListPosition。
    List({ scroller: this.listScroller, initialIndex: recallListPosition('main') }) {
      // LazyForEach, not ForEach: ForEach builds every row up front, which for
      // a real account meant hundreds of live ChatRow components for the eight
      // that are visible.
      LazyForEach(this.chatsData, (item: ChatEntry) => {
        ListItem() { ChatRow({ chat: item, listKey: 'main' }); }
          .swipeAction(this.rowSwipeEnabled ? {
            start: {
              builder: (): void => { this.readSwipe(item); },
              actionAreaDistance: SWIPE_TRIGGER_VP,
              onAction: (): void => { this.toggleRead(item); }
            },
            end: {
              builder: (): void => { this.endSwipe(item); },
              actionAreaDistance: SWIPE_TRIGGER_VP,
              onAction: (): void => { this.toggleArchive(item); }
            }
          } as SwipeActionOptions : {} as SwipeActionOptions)
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
    // 侧边页签模式下 dock 不在底部，撤掉那 88 的避让（见 splitMetrics）。
    .contentEndOffset(this.bottomSafe + (this.dockBottom ? 88 : 16))
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
          // 拉到底那一下用弹簧收尾：跟手段是线性的，锁定这一下给点回弹，
          // 手上才有"咔哒一声到位"的反馈。**曲线走省电分组**——关掉平滑过渡
          // 时 duration 会被压到 0，那时它就是原来的瞬时置位。
          animateTo({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 260),
            curve: curves.springMotion(0.34, 0.72)
          }, (): void => {
            this.archiveRevealed = true;
          });
        }
      } else if (!this.archiveRevealed && this.archivePullPx > 0) {
        // 没拽到底就松手/惯性阶段：跟着回弹的衰减一起缩回去。
        this.archivePullPx = y < 0
          ? Math.min(ARCHIVE_ROW_HEIGHT, -y * ARCHIVE_ROW_HEIGHT / ARCHIVE_OVERPULL)
          : 0;
      } else if (this.archiveRevealed && y > ARCHIVE_COLLAPSE_SCROLL) {
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
    .onScrollIndex((start: number): void => {
      this.firstVisibleIndex = start;
      this.topVisible = start <= 0;
      rememberListPosition('main', start);
    })
    // 指尖按下就关发布闸（抬手/被抢手势即开），见 ChatListView 同款注释。
    .onTouch((event: TouchEvent): void => { updateTouchHold(event.type); })
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
        // 文件夹条浮在内容之上、自身只留 2 的下外边距，归档卡片顶到它底下
        // 看着像被压住（用户："归档感觉被挡住一点"）。这一档让它离开那条边。
        .margin({ top: ARCHIVE_TOP_GAP })
        .clip(true)
        .opacity(this.archiveRevealed ? 1 : this.archivePullPx / ARCHIVE_ROW_HEIGHT)
        // 跟手形变：卡片从 0.86 长到 1。高度是"露出多少"，缩放是"成形多少"，
        // 两者一起才有被拉出来的手感（只有高度时像从缝里平推出来）。
        .scale({
          x: archiveCardScale(this.archiveProgress()),
          y: archiveCardScale(this.archiveProgress())
        })
        // **收起必须靠 transition，不能只靠 animateTo。** 收起时
        // `archiveRevealed || archivePullPx > 0` 直接变假，节点被 if 摘掉；
        // 没有出场过渡的话它是瞬间消失的——外面那个 animateTo 包着的其实只有
        // 状态赋值，画面上一帧都没动过。
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.92, y: 0.86 }))
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 200),
            curve: Curve.EaseOut
          }));
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
