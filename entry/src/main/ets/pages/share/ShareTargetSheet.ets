import { ChatEntry } from '../../store/ChatEntry';
import { TargetAvatarCell } from '../common/TargetAvatarCell';
import { forwardColumnsTemplate, forwardGridColumns } from '../../util/forwardFolders';
import { KeyedListDataSource } from '../common/KeyedListDataSource';
import { guardKey } from '../../util/keyGuard';
import { getChatStore } from '../../tdkit/Globals';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  KEY_POWER_EFFECT_REPLY, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { SHARE_TARGET_LIMIT, ShareTarget, orderShareTargets } from '../../util/shareTargets';
import { recentOutgoingChats } from '../../util/recentOutgoing';
import { ShareRow, pinSavedFirst, rowFromEntry } from '../../util/shareSearch';
import { localShareRows, searchShareRows } from '../../services/ShareChatSearch';
import { promptAction } from '@kit.ArkUI';
import { getTdClient, getUserStore } from '../../tdkit/Globals';
import { MediaSendItem, MessageStore } from '../../store/MessageStore';
import { ShareArrivalHost, sendShareDirectly } from '../../util/shareArrival';
import { peekPendingShare, takePendingShare } from '../../services/ShareInbox';
import { SharedPayload } from '../../util/sharedContent';
import { selectionCount, targetSelected, toggleTarget } from '../../util/targetSelection';
import { FanoutResult, fanoutShare } from '../../util/shareFanout';
import { str } from '../../util/strings';
import { logE } from '../../util/log';

// 「分享到…」的会话选择器。系统分享把内容送进来之后由 Index 弹出。
//
// 【和 ForwardSheet 的区别不只是文案】转发的选择器按会话列表原样排（用户找的
// 是"某个群"），而分享的目标几乎总是"我常联系的人"。所以这里最上面单独有一
// 段「常用」：我的收藏置顶，后面是我主动发过消息的会话（见 util/shareTargets）。
// 下面才是完整会话列表。搜索时两段合一，只按标题过滤。

// 输入到发起搜索之间的静默期。每敲一下就查一次会把请求队列打满，而用户
// 打完一个词也就 200ms 左右。
const SEARCH_DEBOUNCE_MS: number = 220;

const RECENT_ROW_HEIGHT: number = 92;
const RECENT_CELL_WIDTH: number = 70;
const RECENT_AVATAR: number = 50;

@Component
export struct ShareTargetSheet {
  // 面板上给用户看的一行摘要（"IMG_0042.JPG +2" 之类）。
  @Prop preview: string = '';
  // 选中一个会话。**一律走"进会话编辑"**：内容落到输入框上方，用户配完字
  // 自己按发送。"直接发送"那一档的代码还在（ChatPage.sendSharedDirectly +
  // 路由参数 shareAutoSend），只是没有任何入口把它置位了。
  onPick: (chatId: number) => void = (): void => {};
  onCancel: () => void = (): void => {};

  @State @Watch('syncRowsData') private chats: ChatEntry[] = [];
  @State @Watch('syncRowsData') private query: string = '';
  @State private loadState: 'loading' | 'ready' | 'error' = 'loading';
  // 搜索结果。空查询时不用它，直接渲染 chats（主列表的既有顺序）。
  @State @Watch('syncRowsData') private results: ShareRow[] = [];
  // 会话列表的 LazyForEach 数据源，喂的是 rows() 那一份（见 syncRowsData）。
  private rowsData: KeyedListDataSource<ShareRow> = new KeyedListDataSource<ShareRow>('share-targets');
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 网格列数跟窗口宽走，同 ForwardSheet（面板左右外边距 8×2 + 内边距 12×2）。
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 选中的目标会话（util/targetSelection）。选 1 个仍走 onPick 进会话、可以再编辑；
  // 选 2 个以上才直接群发——发单个人时先写句话是常用的，不该因为加了多选就丢掉。
  @State private selectedIds: number[] = [];
  @State private sending: boolean = false;
  private unsubChats: (() => void) | null = null;
  private seq: number = 0;
  private searchSeq: number = 0;
  private searchTimer: number = -1;

  aboutToAppear(): void {
    // 与 ForwardSheet 同一理由：列表会随消息到达重排、头像下载完才有图，
    // 开着的选择器要跟着变。
    this.unsubChats = getChatStore().subscribe((list: ChatEntry[]): void => {
      this.applyChats(list);
    }, 'main');
    this.loadChats();
    this.syncRowsData();
  }

  aboutToDisappear(): void {
    this.seq++;
    this.searchSeq++;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    if (this.unsubChats !== null) {
      this.unsubChats();
      this.unsubChats = null;
    }
  }

  // 输入变化。**先同步出本机结果再去查远端**：本机那一层不用等，输入过程中
  // 列表始终有内容，远端回来只是往后追加（见 services/ShareChatSearch）。
  private onQueryChanged(value: string): void {
    this.query = value;
    const trimmed: string = value.trim();
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
    this.searchSeq++;
    if (trimmed === '') {
      this.results = [];
      return;
    }
    this.results = localShareRows(trimmed);
    const seq: number = this.searchSeq;
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      searchShareRows(trimmed).then((rows: ShareRow[]): void => {
        // 结果回来时用户可能已经改了词，认序号不认时间。
        if (seq === this.searchSeq) {
          this.results = rows;
        }
      });
    }, SEARCH_DEBOUNCE_MS);
  }

  private applyChats(list: ChatEntry[]): void {
    this.chats = list.filter((chat: ChatEntry): boolean => chat.id !== 0);
    if (this.chats.length > 0) {
      this.loadState = 'ready';
    }
  }

  private loadChats(): void {
    this.loadState = this.chats.length > 0 ? 'ready' : 'loading';
    const seq: number = ++this.seq;
    getChatStore().ensureLoaded('main').then((success: boolean): void => {
      if (seq !== this.seq) {
        return;
      }
      this.applyChats(getChatStore().getChats('main'));
      this.loadState = !success && this.chats.length === 0 ? 'error' : 'ready';
    });
  }

  private recent(): ShareTarget[] {
    return orderShareTargets(this.chats, recentOutgoingChats(), SHARE_TARGET_LIMIT);
  }

  // 列表要渲染的行。空查询走主列表的既有顺序；有查询走搜索结果
  // （候选集是本机全部会话 + TDLib 本地索引，见 services/ShareChatSearch）。
  private rows(): ShareRow[] {
    if (this.query.trim() === '') {
      // 收藏置顶：主列表按最后消息时间排，收藏常沉在很后面，而它是分享最
      // 高频的去处（用户明确要求）。搜索时不动——那时顺序应该按相关性。
      return pinSavedFirst(this.chats.map(rowFromEntry));
    }
    return this.results;
  }

  // 会话 / 搜索词 / 搜索结果变了：把当下要显示的那一份交给 LazyForEach。
  private syncRowsData(): void {
    const list: ShareRow[] = this.rows();
    this.rowsData.update(list,
      list.map((r: ShareRow): string => `${r.chatId}`),
      list.map((r: ShareRow): string =>
        `${r.chatId}_${r.title}_${r.subtitle}_${r.avatarPath}_${r.isSavedMessages ? 1 : 0}`));
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .borderRadius(10)
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(10)
  }

  // 「常用」一排与下面的网格同一种格子（TargetAvatarCell），选中态两处一致。
  // 「我的收藏」画书签，不画自己的头像——savedMessages 必须传，原来漏过一次，收藏长得
  // 和"某个联系人"一模一样，用户认不出。
  @Builder
  recentCell(target: ShareTarget) {
    TargetAvatarCell({
      avatarPath: target.avatarPath,
      initials: target.initials,
      colorSeed: target.chatId,
      savedMessages: target.isSavedMessages,
      title: target.isSavedMessages ? str('cl_saved_messages') : target.title,
      selected: targetSelected(this.selectedIds, target.chatId),
      avatarSize: RECENT_AVATAR,
      titleLines: 1
    })
      .width(RECENT_CELL_WIDTH)
      .onClick((): void => this.toggle(target.chatId));
  }

  private gridColumnsTemplate(): string {
    return forwardColumnsTemplate(forwardGridColumns(this.screenW - 16 - 24));
  }

  private toggle(chatId: number): void {
    if (this.sending) {
      return;
    }
    this.selectedIds = toggleTarget(this.selectedIds, chatId);
  }

  // 选 1 个：原样走 onPick——进会话、内容落输入框，用户还能再写一句。
  // 选 2 个以上：没有输入框可进了，直接群发。
  private confirm(): void {
    if (this.sending || this.selectedIds.length === 0) {
      return;
    }
    if (this.selectedIds.length === 1) {
      this.onPick(this.selectedIds[0]);
      return;
    }
    this.fanout();
  }

  // 每个目标一个**只用来发送**的 MessageStore：构造是纯赋值（不订阅、不拉历史），
  // 订阅发生在 open() 里，所以这里不 open；close() 对没 open 过的实例是安全的
  // （chatOpened 为假就不发 closeChat，unsubs 是空数组）。
  private hostFor(chatId: number): ShareArrivalHost {
    const store: MessageStore = new MessageStore(getTdClient(), getUserStore(), chatId, 0, 30, 0, 0);
    return {
      // 直发这一档不碰输入框暂存区，这四个用不上（见 util/shareArrival 的说明）。
      appendMedia: (_items: MediaSendItem[]): number => 0,
      setDraft: (_text: string): void => {},
      draftText: (): string => '',
      scrollToBottom: (): void => {},
      sendDocument: (path: string, caption: string): void => store.sendDocument(path, caption),
      sendAudio: (path: string, caption: string): void => store.sendAudio(path, caption),
      sendMedia: (items: MediaSendItem[], caption: string): Promise<void> =>
        store.sendMedia(items, caption),
      sendText: (text: string): void => { store.send(text); }
    };
  }

  private fanout(): void {
    // peek 不取走：全部成功之后才清，有失败就留着让用户重来（取走是破坏性的，
    // 见 services/ShareInbox）。
    const payload: SharedPayload | null = peekPendingShare();
    if (payload === null) {
      return;
    }
    const targets: number[] = this.selectedIds;
    this.sending = true;
    fanoutShare(targets, (chatId: number): Promise<void> =>
      sendShareDirectly(payload, this.hostFor(chatId))
    ).then((result: FanoutResult): void => {
      this.sending = false;
      if (result.failed === 0) {
        takePendingShare();
        promptAction.showToast({
          message: str('fw_sent_to_n', result.ok), duration: 1800
        });
        this.onCancel();
        return;
      }
      logE(`ShareTargetSheet.fanout failed for ${result.failedIds.join(',')}`);
      promptAction.showToast({
        message: result.ok === 0
          ? str('fw_sent_none')
          : str('fw_sent_partial', result.ok, result.failed),
        duration: 2400
      });
    });
  }

  @Builder
  sendBar() {
    Row({ space: 8 }) {
      Text(this.selectedIds.length === 0
        ? str('fw_pick_targets')
        : str('fw_send_n', selectionCount(this.selectedIds)))
        .fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(this.selectedIds.length === 0 ? COLOR_TEXT_SECONDARY : Color.White)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      if (this.sending) {
        LoadingProgress().width(18).height(18).color(Color.White);
      }
    }
    .width('100%').height(44).justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.selectedIds.length === 0 ? $r('app.color.surface_alt') : COLOR_PRIMARY)
    .enabled(this.selectedIds.length > 0 && !this.sending)
    .onClick((): void => { this.confirm(); });
  }

  build() {
    Column() {
      Column().layoutWeight(1).onClick((): void => this.onCancel());
      Column({ space: 10 }) {
        // 抓手/标题/关闭这一段**逐字照抄 ForwardSheet**：那一份在真机上是
        // 好用的，我原来手写的版本用户反馈"✕ 点不动"。少一层居中的 Row、
        // 少一句 .animation，就不再和已知可用的结构一致——这种地方不值得自创。
        Row({ space: 10 }) {
          Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        }
        .width('100%').justifyContent(FlexAlign.Center);
        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.share_to'))
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
            Text(this.preview !== '' ? this.preview : $r('app.string.fw_pick_chat'))
              .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .alignItems(HorizontalAlign.Start).layoutWeight(1);
          Row() {
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_ICON_SECONDARY]);
          }
          .width(34).height(34).borderRadius(17).justifyContent(FlexAlign.Center)
          .stateStyles({
            normal: this.rowNormalStyle,
            pressed: this.rowPressedStyle
          })
          .animation({
            duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110),
            curve: Curve.EaseOut
          })
          .onClick(() => { this.onCancel(); });
        }
        .width('100%');

        TextInput({ text: this.query, placeholder: $r('app.string.fw_search') })
          .width('100%').height(40)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.surface_alt')).borderRadius(20)
          .onChange((value: string): void => this.onQueryChanged(value));

        // 常用一排。搜索时收起——那时用户心里已经有目标，横排只会挡住结果。
        if (this.query.trim() === '' && this.recent().length > 0) {
          List({ space: 10 }) {
            ForEach(this.recent(), (target: ShareTarget): void => {
              ListItem() {
                this.recentCell(target);
              }
            }, (target: ShareTarget): string => `share_recent_${target.chatId}`);
          }
          .listDirection(Axis.Horizontal)
          .height(RECENT_ROW_HEIGHT).width('100%')
          .scrollBar(BarState.Off);
        }

        if (this.loadState === 'loading') {
          Column({ space: 10 }) {
            LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
            Text($r('app.string.fw_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.rows().length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(28).fontColor([COLOR_ICON_SECONDARY]);
            Text(this.query.trim() === '' ? $r('app.string.fw_empty') : $r('app.string.fw_no_match'))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else {
          // 头像网格，同 ForwardSheet（2026-09-17 用户要求分享抽屉也改成头像列表）。
          // LazyForEach：空查询时是整个会话列表，翻页会一直涨。
          Grid() {
            LazyForEach(this.rowsData, (row: ShareRow): void => {
              GridItem() {
                TargetAvatarCell({
                  avatarPath: row.avatarPath,
                  initials: row.initials,
                  colorSeed: row.chatId,
                  savedMessages: row.isSavedMessages,
                  title: row.isSavedMessages ? str('cl_saved_messages') : row.title,
                  selected: targetSelected(this.selectedIds, row.chatId)
                })
                  .onClick((): void => this.toggle(row.chatId));
              }
            }, (row: ShareRow, index: number): string =>
              guardKey(this.rowsData.keyTableId, index,
                `${row.chatId}_${row.title}_${row.avatarPath}_${row.isSavedMessages ? 1 : 0}`));
          }
          .columnsTemplate(this.gridColumnsTemplate())
          .rowsGap(4).columnsGap(4)
          .layoutWeight(1).width('100%')
          .cachedCount(2)
          .scrollBar(BarState.Auto)
          // 搜索时不翻主列表：结果来自搜索，翻页只会白拉数据。
          .onReachEnd((): void => {
            if (this.query.trim() === '') {
              getChatStore().loadMore('main');
            }
          });
        }
        this.sendBar();
      }
      .width('calc(100% - 16vp)').height('72%')
      .padding({ left: 12, right: 12, top: 10, bottom: 12 + this.bottomSafe })
      .backgroundColor($r('app.color.surface')).borderRadius(20)
      .shadow({ radius: 12, color: '#26000000', offsetX: 0, offsetY: -2 })
      .margin({ left: 8, right: 8, bottom: 8 });
    }
    .width('100%').height('100%')
    .backgroundColor('#00000066')
    .transition(
      TransitionEffect.translate({ y: 24 })
        .combine(TransitionEffect.OPACITY)
        .animation({
          duration: powerAnimationDuration(KEY_POWER_EFFECT_REPLY, 220), curve: Curve.EaseOut
        })
    );
  }
}
