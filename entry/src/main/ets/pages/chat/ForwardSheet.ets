import { TargetFolderTabs } from '../common/TargetFolderTabs';
import { sendWithChatPermissions, requireForwardPermissions } from '../../store/SendPermissionApi';
import { TargetGrid } from '../common/TargetGrid';
import { ForwardSendTask } from '../../util/forwardSendTask';
import { ShareRow } from '../../util/shareSearch';
import { pickerChatRows, localShareRows, searchShareRows, ensureSavedTarget } from '../../services/ShareChatSearch';
import { FolderInfo } from '../../store/FolderStore';
import {
  ALL_FOLDER_ID, forwardColumnsTemplate, forwardGridColumns, forwardListKey
} from '../../util/forwardFolders';
import { promptAction } from '@kit.ArkUI';
import { ChatEntry } from '../../store/ChatEntry';
import { getChatStore, getFolderStore, getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_ON_PRIMARY
} from '../../util/theme';
import {
  KEY_POWER_EFFECT_REPLY, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { selectionCount, targetSelected, toggleTarget } from '../../util/targetSelection';
import { FanoutResult, fanoutShare } from '../../util/shareFanout';

// "Forward to…" chat picker, extracted from ChatPage.
//
// Ownership split with the page: the page decides *whether* the sheet is up and
// which messages are being forwarded (it has to filter out non-forwardable ones
// before there is anything to show). The chat list — loading, retry, filtering,
// and the forwardMessages request itself — lives here. The page's
// `if (showForwardSheet)` branch creates and destroys this component, so the
// query box and in-flight send state reset per open without explicit teardown.
// 面板顶边与标题栏（含置顶条/横幅）底边之间留的缝。
const FORWARD_SHEET_TOP_GAP: number = 8;

@Component
export struct ForwardSheet {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  // 单向入 + 回调出，而不是 @Link（@Link 只能被 V1 状态变量初始化，页面迁到
  // 状态管理 V2 之后就接不上了）：关闭按钮和发送成功都是从这里关的。
  @Prop show: boolean;
  onShowChange: (show: boolean) => void = (): void => {};

  // Set by the page at construction. Plain fields are correct: the sheet is
  // rebuilt on each open, and these never change while it is up.
  messageIds: number[] = [];
  sourceChatId: number = 0;
  threadRootId: number = 0;
  @Prop canRemoveCaption: boolean = false;
  // 页面顶部标题栏 + 横幅的高度（vp）。标题栏是 HdsNavDestination 的 titleBar，画在
  // 内容区之上；本面板在内容区里盖不住它，只能把顶边让到它下面
  // （2026-09-14 用户截图：面板顶部压在标题栏和置顶条底下）。
  @Prop topInset: number = 0;

  // Read directly rather than passed down — same source the page uses, so the
  // padding still tracks the keyboard while the search box has focus.
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('keyboardHeightVp') keyboardH: number = 0;

  effectDuration: (key: string, ms: number) => number =
    (_key: string, ms: number): number => ms;
  // The page leaves multi-select mode after a successful forward.
  onSent: () => void = (): void => {};

  @State chats: ChatEntry[] = [];
  // 文件夹页签（issue #200）：0 = 全部；列表键随之在 'main' / folder:<id> 之间切。
  @State folderId: number = ALL_FOLDER_ID;
  // 网格列数按面板可用宽度自适应（见 forwardGridColumns）。
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State folders: FolderInfo[] = [];
  private unsubFolders: (() => void) | null = null;
  @State query: string = '';
  @State loadState: string = 'ready'; // loading | ready | error
  @State sendingChatId: number = 0;
  // 选中的目标会话。点击=切换，底部发送条一次发给全部（util/targetSelection）。
  @State selectedIds: number[] = [];
  // 扇出进行中：整条发送链跑完才落下，期间禁用重复点击。
  @State sending: boolean = false;
  @State sendCopy: boolean = false;
  @State removeCaption: boolean = false;

  // Guards async continuations against a sheet that has since been closed or
  // reopened. Kept even though the component is destroyed on close: a request
  // in flight at that moment would otherwise write state on a dead instance.
  private seq: number = 0;
  private sendSeq: number = 0;
  private searchSeq: number = 0;
  private searchTimer: number = -1;
  @State private results: ShareRow[] = [];
  @State private optionsLocked: boolean = false;
  private sendTask: ForwardSendTask | null = null;
  private unsubChats: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubFolders = getFolderStore().subscribe((folders: FolderInfo[]): void => {
      this.folders = folders;
      if (this.folderId !== ALL_FOLDER_ID && !folders.some((folder: FolderInfo): boolean => folder.id === this.folderId)) {
        this.selectFolder(ALL_FOLDER_ID);
      }
    });
    this.bindChats();
    this.loadChats();
  }

  aboutToDisappear(): void {
    this.sendSeq++;
    this.searchSeq++;
    if (this.searchTimer !== -1) { clearTimeout(this.searchTimer); }
    this.seq++;
    if (this.unsubChats !== null) {
      this.unsubChats();
      this.unsubChats = null;
    }
    if (this.unsubFolders !== null) {
      this.unsubFolders();
      this.unsubFolders = null;
    }
  }

  private listKey(): string {
    return forwardListKey(this.folderId);
  }

  // 订阅当前页签对应的那个分桶；切页签时换订阅。回调会立刻给一次缓存里的列表。
  private bindChats(): void {
    if (this.unsubChats !== null) {
      this.unsubChats();
    }
    this.unsubChats = getChatStore().subscribe((list: ChatEntry[]): void => {
      this.applyChats(list);
    }, this.listKey());
  }

  private selectFolder(id: number): void {
    if (this.sending || id === this.folderId) {
      return;
    }
    this.folderId = id;
    this.chats = [];
    this.bindChats();
    this.loadChats();
    this.onQueryChanged(this.query);
  }

  private bottomInset(): number {
    return this.keyboardH > 0 ? Math.max(this.bottomSafe, 12) : this.bottomSafe;
  }

  private applyChats(list: ChatEntry[]): void {
    // 只排占位条目。**不能写 id > 0**：Telegram 的 chat id 只有私聊是正数，
    // 普通群是负数、超级群和频道是 -100… 开头的负数，那样写等于把所有群组
    // 和频道都过滤掉——现象就是转发时只列得出个人。
    this.chats = list.filter((chat: ChatEntry): boolean => chat.id !== 0);
    if (this.chats.length > 0) {
      this.loadState = 'ready';
    }
  }

  // The subscription above has already seeded `chats`; this only drives the
  // loading/error state and asks the store to fill an empty cache.
  private loadChats(): void {
    this.loadState = this.chats.length > 0 ? 'ready' : 'loading';
    const seq: number = ++this.seq;
    Promise.all([getChatStore().ensureLoaded(this.listKey()), ensureSavedTarget().then((): boolean => true).catch((): boolean => false)])
      .then((loaded: boolean[]): void => {
      const success: boolean = loaded[0] || loaded[1];
      if (seq !== this.seq) {
        return;
      }
      this.applyChats(getChatStore().getChats(this.listKey()));
      if (!success && this.chats.length === 0) {
        this.loadState = 'error';
      } else {
        this.loadState = 'ready';
      }
    });
  }

  private retryChats(): void {
    if (this.loadState === 'loading') {
      return;
    }
    this.loadState = 'loading';
    const seq: number = ++this.seq;
    getChatStore().loadMore(this.listKey()).then((): void => {
      if (seq !== this.seq) {
        return;
      }
      this.applyChats(getChatStore().getChats(this.listKey()));
      this.loadState = this.chats.length > 0 ? 'ready' : 'error';
    });
  }

  private close(): void {
    this.sendSeq++;
    this.searchSeq++;
    this.seq++;
    this.show = false;
    this.onShowChange(false);
  }

  private filteredChats(): ShareRow[] {
    return this.query.trim() === '' ? pickerChatRows(this.chats) : this.results;
  }

  private onQueryChanged(query: string): void {
    this.query = query;
    const seq: number = ++this.searchSeq;
    if (this.searchTimer !== -1) { clearTimeout(this.searchTimer); this.searchTimer = -1; }
    if (query.trim() === '') { this.results = []; return; }
    this.results = localShareRows(query, this.folderId);
    const folderId: number = this.folderId;
    this.searchTimer = setTimeout((): void => {
      this.searchTimer = -1;
      searchShareRows(query, folderId).then((rows: ShareRow[]): void => {
        if (seq === this.searchSeq) { this.results = rows; }
      });
    }, 220);
  }

  private toggleTarget(chatId: number): void {
    if (this.sending) {
      return;
    }
    this.selectedIds = toggleTarget(this.selectedIds, chatId);
  }

  private titleOf(chatId: number): string {
    const row: ShareRow | undefined = pickerChatRows(this.chats).find(
      (candidate: ShareRow): boolean => candidate.chatId === chatId);
    return row?.title ?? getChatStore().entryOf(chatId)?.title ?? '';
  }

  // 发给选中的全部会话。串行（见 util/shareFanout 的说明），每个目标各自
  // 按 100 一批切开（buildForwardMessagesRequests 的既有契约）。
  private sendToSelected(): void {
    if (this.sending || this.selectedIds.length === 0 || this.messageIds.length === 0) {
      return;
    }
    const seq: number = ++this.sendSeq;
    const targets: number[] = this.selectedIds.slice();
    if (this.sendTask === null) {
      this.sendTask = new ForwardSendTask({ toChatId: 0, fromChatId: this.sourceChatId,
        messageIds: this.messageIds, threadRootId: this.threadRootId, sendCopy: this.sendCopy,
        removeCaption: this.removeCaption, canRemoveCaption: this.canRemoveCaption });
    }
    const task: ForwardSendTask = this.sendTask;
    this.optionsLocked = true;
    this.sending = true;
    fanoutShare(targets, (chatId: number): Promise<void> => {
      if (seq !== this.sendSeq) { return Promise.reject(new Error('forward closed')); }
      this.sendingChatId = chatId;
      const client = getTdClient();
      return requireForwardPermissions((request: TdRequest): Promise<TdObject> => client.send(request, 15000),
        chatId, task.sourceChatId(), task.remainingMessageIds(chatId)).then((): Promise<void> =>
        task.send(chatId, (request: TdRequest): Promise<TdObject> => sendWithChatPermissions(client, request, undefined,
          (): boolean => seq === this.sendSeq),
          (): boolean => seq === this.sendSeq));
    }).then((result: FanoutResult): void => {
      if (seq !== this.sendSeq) {
        return;
      }
      this.selectedIds = result.failedIds;
      this.sending = false;
      this.sendingChatId = 0;
      if (result.failed === 0) {
        this.close();
        this.onSent();
      }
      promptAction.showToast({ message: task.hasUncertain() ? str('share_result_unknown') : this.resultMessage(result, targets), duration: 1800 });
    });
  }

  private resultMessage(result: FanoutResult, targets: number[]): string {
    if (result.failed === 0) {
      return targets.length === 1
        ? str('fw_forwarded_to', this.titleOf(targets[0]))
        : str('fw_sent_to_n', result.ok);
    }
    if (result.ok === 0) {
      return str('fw_failed');
    }
    return str('fw_sent_partial', result.ok, result.failed);
  }

  @Styles
  rowNormalStyle() {
    .backgroundColor(Color.Transparent)
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  rowPressedStyle() {
    .backgroundColor($r('app.color.surface_alt'))
    .opacity(0.76)
    .scale({ x: 0.985, y: 0.96 })
  }

  // 取消「隐藏来源」时连带取消「移除说明文字」：TDLib 的 remove_caption 只在
  // send_copy 下有意义，保留来源的转发去不掉说明。
  private toggleHideSource(): void {
    if (this.optionsLocked) { return; }
    this.sendCopy = !this.sendCopy;
    if (!this.sendCopy) {
      this.removeCaption = false;
    }
  }

  private toggleRemoveCaption(): void {
    if (this.optionsLocked) { return; }
    this.removeCaption = !this.removeCaption;
  }

  // 转发选项：一排可勾选的胶囊（2026-09-14 用户：「保留来源和隐藏来源留一个就行，
  // 允许取消勾选」）。默认不勾 = 保留来源。
  //
  // 「移除说明文字」只在勾了隐藏来源、且选中的消息里确实有能去掉的说明时才出现。
  // 更早那版是两个始终可见、互相牵制的开关，用户实测觉得丑也难懂；现在第二个只在
  // 它有意义时出现，看不到牵制。
  //
  // 两个胶囊直接写开、不抽成带参数的 @Builder：按值传参的 @Builder 不随勾选状态刷新。

  // 底部发送条。n=0 时禁用并显示提示文案——按钮始终在位，不随选择跳出跳入
  // （出现/消失会把上面的网格顶一下，滚动位置跟着跳）。
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
    .onClick((): void => { this.sendToSelected(); });
  }

  @Builder
  forwardOptionsRow() {
    Row({ space: 8 }) {
      Row({ space: 6 }) {
        if (this.sendCopy) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(17).fontColor([COLOR_PRIMARY]);
        } else {
          SymbolGlyph($r('sys.symbol.circle')).fontSize(17).fontColor([COLOR_ICON_SECONDARY]);
        }
        Text($r('app.string.fw_hide_source'))
          .fontSize(13)
          .fontWeight(this.sendCopy ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.sendCopy ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1);
      }
      .flexShrink(1)
      .padding({ left: 10, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.sendCopy ? '#1A3390EC' : $r('app.color.surface_alt'))
      .onClick((): void => { this.toggleHideSource(); });
      if (this.canRemoveCaption && this.sendCopy) {
        Row({ space: 6 }) {
          if (this.removeCaption) {
            SymbolGlyph($r('sys.symbol.checkmark_circle_fill')).fontSize(17).fontColor([COLOR_PRIMARY]);
          } else {
            SymbolGlyph($r('sys.symbol.circle')).fontSize(17).fontColor([COLOR_ICON_SECONDARY]);
          }
          Text($r('app.string.fw_remove_caption'))
            .fontSize(13)
            .fontWeight(this.removeCaption ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.removeCaption ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1);
        }
        .flexShrink(1)
        .padding({ left: 10, right: 12, top: 6, bottom: 6 })
        .borderRadius(16)
        .backgroundColor(this.removeCaption ? '#1A3390EC' : $r('app.color.surface_alt'))
        .onClick((): void => { this.toggleRemoveCaption(); });
      }
    }
    .width('100%');
  }
  build() {
    Column() {
      // 顶部留白（点了关闭）：默认 14%，面板约占 86%；但至少让到标题栏和横幅下面。
      Column().width('100%').height('14%')
        .constraintSize({ minHeight: this.topInset + FORWARD_SHEET_TOP_GAP })
        .onClick(() => { this.close(); });
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        }
        .width('100%').justifyContent(FlexAlign.Center);
        Row() {
          Column({ space: 2 }) {
            Text(this.messageIds.length > 1
              ? plural('fw_forward_n', this.messageIds.length, this.messageIds.length)
              : $r('app.string.fw_title'))
              .fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
            Text($r('app.string.fw_pick_chat')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
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
          .animation({ duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 110), curve: Curve.EaseOut })
          .onClick(() => { this.close(); });
        }
        .width('100%');
        TextInput({ text: this.query, placeholder: $r('app.string.fw_search') })
          .width('100%').height(40)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.surface_alt')).borderRadius(20)
          .onChange((value: string): void => { this.onQueryChanged(value); });
        if (this.folders.length > 0) {
          TargetFolderTabs({ folders: this.folders, folderId: this.folderId,
            onSelect: (id: number): void => { this.selectFolder(id); } });
        }
        Column() { this.forwardOptionsRow(); }.enabled(!this.optionsLocked).opacity(this.optionsLocked ? 0.5 : 1);
        this.sendBar();
        if (this.loadState === 'loading') {
          Column({ space: 10 }) {
            LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
            Text($r('app.string.fw_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.loadState === 'error') {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(28).fontColor([COLOR_ICON_SECONDARY]);
            Text($r('app.string.fw_load_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            Button($r('app.string.settings_retry'))
              .fontSize(14).fontColor(COLOR_ON_PRIMARY)
              .height(36).padding({ left: 20, right: 20 })
              .backgroundColor(COLOR_PRIMARY).borderRadius(18)
              .onClick(() => { this.retryChats(); });
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.filteredChats().length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(28).fontColor([COLOR_ICON_SECONDARY]);
            Text(this.query.trim() === '' ? $r('app.string.fw_empty') : $r('app.string.fw_no_match'))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else {
          // 头像网格（issue #200）：转发时用户找的是"人"，四列一屏能看 16 个。
          // 昵称固定两行高，行与行对齐。
          TargetGrid({ rows: this.filteredChats(), selectedIds: this.selectedIds,
            busyId: this.sendingChatId,
            onToggle: (id: number): void => { this.toggleTarget(id); },
            onMore: (): void => {
              if (this.query.trim() === '') { getChatStore().loadMore(this.listKey()); }
            }
          }).layoutWeight(1).width('100%');
        }
      }
      .width('calc(100% - 16vp)').layoutWeight(1)
      .padding({ left: 12, right: 12, top: 10, bottom: 12 + this.bottomInset() })
      .backgroundColor($r('app.color.surface')).borderRadius(20)
      .shadow({ radius: 12, color: '#26000000', offsetX: 0, offsetY: -2 })
      .margin({ left: 8, right: 8, bottom: 8 });
    }
    .width('100%').height('100%')
    .backgroundColor('#00000066')
    .transition(
      TransitionEffect.translate({ y: 24 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.effectDuration(KEY_POWER_EFFECT_REPLY, 220), curve: Curve.EaseOut })
    );
  }
}
