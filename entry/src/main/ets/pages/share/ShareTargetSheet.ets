import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { sharedSendPermissions } from '../../util/sendPermissions';
import { TargetSendFilter } from '../../services/TargetSendFilter';
import { TargetFolderTabs } from '../common/TargetFolderTabs';
import { FolderInfo } from '../../store/FolderStore';
import { ALL_FOLDER_ID, forwardListKey } from '../../util/forwardFolders';
import { TargetGrid } from '../common/TargetGrid';
import { SendProgress } from '../../util/sendProgress';
import { pickerChatRows, pickerRows, ensureSavedTarget } from '../../services/ShareChatSearch';
import { clearPendingShareIf, onPendingShareChanged } from '../../services/ShareInbox';
import { ChatEntry } from '../../store/ChatEntry';
import { TargetAvatarCell } from '../common/TargetAvatarCell';
import { getChatStore, getFolderStore } from '../../tdkit/Globals';
import {
  COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import {
  KEY_POWER_EFFECT_REPLY, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { SHARE_TARGET_LIMIT, ShareTarget, orderShareTargets } from '../../util/shareTargets';
import { recentOutgoingChats } from '../../util/recentOutgoing';
import { ShareRow } from '../../util/shareSearch';
import { localShareRows, searchShareRows } from '../../services/ShareChatSearch';
import { promptAction } from '@kit.ArkUI';
import { getTdClient, getUserStore } from '../../tdkit/Globals';
import { MediaSendItem, MessageStore } from '../../store/MessageStore';
import { ShareArrivalHost, sendShareDirectly } from '../../util/shareArrival';
import { peekPendingShare } from '../../services/ShareInbox';
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

  @State private chats: ChatEntry[] = [];
  @State private query: string = '';
  @State private loadState: 'loading' | 'ready' | 'error' = 'loading';
  // 搜索结果。空查询时不用它，直接渲染 chats（主列表的既有顺序）。
  @State private results: ShareRow[] = [];
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  // 网格列数跟窗口宽走，同 ForwardSheet（面板左右外边距 8×2 + 内边距 12×2）。
  @StorageProp('screenWidthVp') screenW: number = 360;
  // 选中的目标会话（util/targetSelection）。选 1 个仍走 onPick 进会话、可以再编辑；
  // 选 2 个以上才直接群发——发单个人时先写句话是常用的，不该因为加了多选就丢掉。
  @State private selectedIds: number[] = [];
  @State private sending: boolean = false;
  @State private folderId: number = ALL_FOLDER_ID;
  @State private folders: FolderInfo[] = [];
  private unsubFolders: (() => void) | null = null;
  private unsubChats: (() => void) | null = null;
  private seq: number = 0;
  private sendSeq: number = 0;
  private unsubPayload: (() => void) | null = null;
  private progress: Map<number, SendProgress> = new Map<number, SendProgress>();
  private taskPayload: SharedPayload | null = null;
  private searchSeq: number = 0;
  private searchTimer: number = -1;

  @State private allowedTargetIds: number[] = [];
  @State private checkingTargets: boolean = true;
  @State private targetCheckFailed: boolean = false;
  private targetFilter: TargetSendFilter | null = null;
  private autoPageCount: number = -1;

  private startTargetFilter(): void {
    this.targetFilter?.dispose();
    const client = getTdClient();
    const filter: TargetSendFilter = new TargetSendFilter(
      (request: TdRequest): Promise<TdObject> => client.send(request, 15000),
      async (): Promise<string[]> => {
        const payload = peekPendingShare();
        if (payload === null) { throw new Error('share ended'); }
        return sharedSendPermissions(payload);
      },
      (): void => {
        if (this.targetFilter !== filter) { return; }
        this.allowedTargetIds = filter.allowedIds();
        this.checkingTargets = filter.checking();
        this.targetCheckFailed = filter.failed();
        if (!this.sending && !this.checkingTargets && !this.targetCheckFailed) {
          this.selectedIds = this.selectedIds.filter((id: number): boolean => this.allowedTargetIds.includes(id));
          // A page containing only forbidden targets must not prevent reaching later chats.
          if (this.query.trim() === '' && this.chats.length > 0 &&
            !this.chats.some((chat: ChatEntry): boolean => this.allowedTargetIds.includes(chat.id)) &&
            this.autoPageCount !== this.chats.length) {
            this.autoPageCount = this.chats.length;
            getChatStore().loadMore(this.listKey());
          }
        }
      }, (): boolean => client === getTdClient());
    this.targetFilter = filter;
    filter.bind(client);
    this.refreshTargets();
  }

  private refreshTargets(): void {
    const ids: number[] = this.chats.map((chat: ChatEntry): number => chat.id);
    ids.push(...this.results.map((row: ShareRow): number => row.chatId));
    ids.push(...this.rawRecent().map((row: ShareTarget): number => row.chatId));
    ids.push(...this.selectedIds);
    this.targetFilter?.include(ids);
  }

  aboutToAppear(): void {
    this.startTargetFilter();
    this.unsubFolders = getFolderStore().subscribe((folders: FolderInfo[]): void => {
      this.folders = folders;
      if (this.folderId !== ALL_FOLDER_ID && !folders.some((folder: FolderInfo): boolean => folder.id === this.folderId)) {
        this.selectFolder(ALL_FOLDER_ID);
      }
    });
    this.bindChats();
    this.loadChats();
    this.unsubPayload = onPendingShareChanged((): void => {
      this.sendSeq++;
      this.sending = false;
      this.selectedIds = [];
      this.progress.clear();
      this.taskPayload = null;
      this.startTargetFilter();
    });
  }

  aboutToDisappear(): void {
    this.targetFilter?.dispose();
    this.targetFilter = null;
    this.sendSeq++;
    this.unsubFolders?.();
    this.unsubFolders = null;
    this.unsubPayload?.();
    this.unsubPayload = null;
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

  private listKey(): string {
    return forwardListKey(this.folderId);
  }

  private bindChats(): void {
    this.unsubChats?.();
    this.unsubChats = getChatStore().subscribe((list: ChatEntry[]): void => {
      this.applyChats(list);
    }, this.listKey());
  }

  private selectFolder(id: number): void {
    if (this.sending || id === this.folderId) { return; }
    this.autoPageCount = -1;
    this.folderId = id;
    this.chats = [];
    this.bindChats();
    this.loadChats();
    this.onQueryChanged(this.query);
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
      this.refreshTargets();
      return;
    }
    this.results = localShareRows(trimmed, this.folderId);
    this.refreshTargets();
    const seq: number = this.searchSeq;
    const folderId: number = this.folderId;
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      searchShareRows(trimmed, folderId).then((rows: ShareRow[]): void => {
        // 结果回来时用户可能已经改了词，认序号不认时间。
        if (seq === this.searchSeq) {
          this.results = rows;
          this.refreshTargets();
        }
      });
    }, SEARCH_DEBOUNCE_MS);
  }

  private applyChats(list: ChatEntry[]): void {
    this.chats = list.filter((chat: ChatEntry): boolean => chat.id !== 0);
    if (this.chats.length > 0) {
      this.loadState = 'ready';
    }
    this.refreshTargets();
  }

  private loadChats(): void {
    if (this.targetCheckFailed) { this.startTargetFilter(); }
    this.loadState = this.chats.length > 0 ? 'ready' : 'loading';
    const seq: number = ++this.seq;
    Promise.all([getChatStore().ensureLoaded(this.listKey()), ensureSavedTarget().then((): boolean => true).catch((): boolean => false)])
      .then((loaded: boolean[]): void => {
      const success: boolean = loaded[0] || loaded[1];
      if (seq !== this.seq) {
        return;
      }
      this.applyChats(getChatStore().getChats(this.listKey()));
      this.loadState = !success && this.chats.length === 0 ? 'error' : 'ready';
    });
  }

  private recent(): ShareTarget[] {
    return this.rawRecent().filter((row: ShareTarget): boolean => this.allowedTargetIds.includes(row.chatId));
  }

  private rawRecent(): ShareTarget[] {
    return pickerRows(orderShareTargets(this.chats, recentOutgoingChats(), SHARE_TARGET_LIMIT)
      .map((target: ShareTarget): ShareRow => ({ chatId: target.chatId, title: target.title,
        subtitle: '', avatarPath: target.avatarPath, initials: target.initials,
        isSavedMessages: target.isSavedMessages }))).slice(0, SHARE_TARGET_LIMIT);
  }

  // 列表要渲染的行。空查询走主列表的既有顺序；有查询走搜索结果
  // （候选集是本机全部会话 + TDLib 本地索引，见 services/ShareChatSearch）。
  private rows(): ShareRow[] {
    return this.rawRows().filter((row: ShareRow): boolean => this.allowedTargetIds.includes(row.chatId));
  }

  private rawRows(): ShareRow[] {
    if (this.query.trim() === '') {
      const rows: ShareRow[] = pickerChatRows(this.chats);
      // 横向常用栏已展示收藏时，下面的全部网格不再重复。
      // 文件夹和搜索会收起横栏，仍保留各自的收藏入口。
      const savedInRecent: boolean = this.folderId === ALL_FOLDER_ID &&
        this.recent().some((target: ShareTarget): boolean => target.isSavedMessages);
      return savedInRecent ? rows.filter((row: ShareRow): boolean => !row.isSavedMessages) : rows;
    }
    return this.results;
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

  private toggle(chatId: number): void {
    if (!this.allowedTargetIds.includes(chatId)) { return; }
    if (this.sending) {
      return;
    }
    this.selectedIds = toggleTarget(this.selectedIds, chatId);
  }

  // 选 1 个：原样走 onPick——进会话、内容落输入框，用户还能再写一句。
  // 选 2 个以上：没有输入框可进了，直接群发。
  private confirm(): void {
    if (this.sending || this.selectedIds.length === 0 ||
      !this.selectedIds.every((id: number): boolean => this.allowedTargetIds.includes(id))) {
      return;
    }
    if (this.selectedIds.length === 1 && this.taskPayload === null) {
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
      checkPermissions: (payload: SharedPayload): Promise<void> => store.checkSharePermissions(payload),
      // 直发这一档不碰输入框暂存区，这四个用不上（见 util/shareArrival 的说明）。
      appendMedia: (_items: MediaSendItem[]): number => 0,
      setDraft: (_text: string): void => {},
      draftText: (): string => '',
      scrollToBottom: (): void => {},
      sendDocument: (path: string, caption: string): Promise<void> => store.sendDocumentAsync(path, caption),
      sendAudio: (path: string, caption: string): Promise<void> => store.sendAudioAsync(path, caption),
      sendMedia: (items: MediaSendItem[], caption: string): Promise<void> =>
        store.sendMedia(items, caption),
      sendText: (text: string): Promise<void> => store.sendAsync(text)
    };
  }

  private fanout(): void {
    // peek 不取走：全部成功之后才清，有失败就留着让用户重来（取走是破坏性的，
    // 见 services/ShareInbox）。
    const payload: SharedPayload | null = peekPendingShare();
    if (payload === null) {
      return;
    }
    if (payload !== this.taskPayload) {
      this.progress.clear();
      this.taskPayload = payload;
    }
    const seq: number = ++this.sendSeq;
    const targets: number[] = this.selectedIds.slice();
    const active = (): boolean => seq === this.sendSeq && peekPendingShare() === payload;
    this.sending = true;
    fanoutShare(targets, (chatId: number): Promise<void> => {
      if (!active()) { return Promise.reject(new Error('share closed')); }
      let progress: SendProgress | undefined = this.progress.get(chatId);
      if (progress === undefined) { progress = new SendProgress(); this.progress.set(chatId, progress); }
      return sendShareDirectly(payload, this.hostFor(chatId), new Map(), progress, active);
    }).then((result: FanoutResult): void => {
      if (!active()) { return; }
      this.selectedIds = result.failedIds;
      this.sending = false;
      if (result.failed === 0) {
        clearPendingShareIf(payload);
        promptAction.showToast({
          message: str('fw_sent_to_n', result.ok), duration: 1800
        });
        this.onCancel();
        return;
      }
      logE(`ShareTargetSheet.fanout failed for ${result.failedIds.join(',')}`);
      let uncertain: boolean = false;
      this.progress.forEach((progress: SendProgress): void => { uncertain = uncertain || progress.hasUncertain(); });
      promptAction.showToast({
        message: uncertain ? str('share_result_unknown') : result.ok === 0
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
      // **宽度必须写死 100%**：Column 的交叉轴默认居中、不拉伸，空 Column 量出来
      // 就是 0 宽——这块遮罩于是只有高度没有宽度，点"抽屉外面"什么都打不中，
      // 只剩右上角那个 ✕ 能关（用户 2026-10-30）。ForwardSheet 那版一直是对的，
      // 因为它写的是 width('100%') + height('14%')。
      Column().width('100%').layoutWeight(1).onClick((): void => this.onCancel());
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

        if (this.folders.length > 0) {
          TargetFolderTabs({ folders: this.folders, folderId: this.folderId,
            onSelect: (id: number): void => { this.selectFolder(id); } });
        }

        // 常用一排。搜索时收起——那时用户心里已经有目标，横排只会挡住结果。
        if (this.folderId === ALL_FOLDER_ID && this.query.trim() === '' && this.recent().length > 0) {
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

        if (this.loadState === 'loading' || (this.checkingTargets && this.allowedTargetIds.length === 0)) {
          Column({ space: 10 }) {
            LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
            Text($r('app.string.fw_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.loadState === 'error' || this.targetCheckFailed) {
          Column({ space: 10 }) {
            Text($r('app.string.fw_load_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            Button($r('app.string.settings_retry')).onClick((): void => { this.loadChats(); });
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
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
          TargetGrid({ rows: this.rows(), selectedIds: this.selectedIds,
            onToggle: (id: number): void => { this.toggle(id); },
            onMore: (): void => { if (this.query.trim() === '') { getChatStore().loadMore(this.listKey()); } }
          }).layoutWeight(1).width('100%');
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
