import { FolderInfo } from '../../store/FolderStore';
import {
  ALL_FOLDER_ID, forwardColumnsTemplate, forwardFolderChips, forwardGridColumns, forwardListKey, ForwardFolderChip
} from '../../util/forwardFolders';
import { promptAction } from '@kit.ArkUI';
import { ChatEntry } from '../../store/ChatEntry';
import { AvatarView } from '../chatlist/AvatarView';
import { getChatStore, getFolderStore, getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_ON_PRIMARY
} from '../../util/theme';
import {
  KEY_POWER_EFFECT_REPLY, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { logE, logI } from '../../util/log';
import { buildForwardMessagesRequests } from '../../util/forwardMessagesRequest';

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
  @State sendCopy: boolean = false;
  @State removeCaption: boolean = false;

  // Guards async continuations against a sheet that has since been closed or
  // reopened. Kept even though the component is destroyed on close: a request
  // in flight at that moment would otherwise write state on a dead instance.
  private seq: number = 0;
  private unsubChats: (() => void) | null = null;

  aboutToAppear(): void {
    this.unsubFolders = getFolderStore().subscribe((folders: FolderInfo[]): void => {
      this.folders = folders;
    });
    this.bindChats();
    this.loadChats();
  }

  aboutToDisappear(): void {
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

  // 面板宽 = 屏宽 − 两侧各 8 − 内边距各 12。
  private gridColumnsTemplate(): string {
    return forwardColumnsTemplate(forwardGridColumns(this.screenW - 16 - 24));
  }

  private listKey(): string {
    return forwardListKey(this.folderId);
  }

  private chips(): ForwardFolderChip[] {
    return forwardFolderChips(this.folders);
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
    if (id === this.folderId) {
      return;
    }
    this.folderId = id;
    this.chats = [];
    this.bindChats();
    this.loadChats();
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
    getChatStore().ensureLoaded(this.listKey()).then((success: boolean): void => {
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
    this.seq++;
    this.show = false;
    this.onShowChange(false);
  }

  private filteredChats(): ChatEntry[] {
    const q: string = this.query.trim().toLowerCase();
    if (q === '') {
      return this.chats;
    }
    return this.chats.filter((chat: ChatEntry): boolean =>
      chat.title.toLowerCase().indexOf(q) >= 0
    );
  }

  private forwardToChat(chat: ChatEntry): void {
    if (this.sendingChatId !== 0 || this.messageIds.length === 0) {
      return;
    }
    // The request builder owns TDLib's strict ascending/unique-id boundary,
    // and splits anything over 100 ids into ordered batches (TDLib's per-call cap).
    const reqs: TdRequest[] = buildForwardMessagesRequests({
      toChatId: chat.id,
      fromChatId: this.sourceChatId,
      messageIds: this.messageIds,
      threadRootId: this.threadRootId,
      sendCopy: this.sendCopy,
      removeCaption: this.removeCaption,
      canRemoveCaption: this.canRemoveCaption
    });
    if (reqs.length === 0) {
      return;
    }
    const seq: number = this.seq;
    this.sendingChatId = chat.id;
    this.sendBatches(reqs).then((count: number): void => {
      if (seq !== this.seq) {
        return;
      }
      this.close();
      this.onSent();
      promptAction.showToast({
        message: count > 1 ? plural('fw_forwarded_n', count, count) : str('fw_forwarded_to', chat.title),
        duration: 1500
      });
    }).catch((e: TdError): void => {
      if (seq !== this.seq) {
        return;
      }
      this.sendingChatId = 0;
      logE(`ForwardSheet.forwardMessages failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.fw_failed'), duration: 2000 });
    });
  }

  // 一批发完再发下一批：TDLib 按到达顺序落时间线，并行发会乱序。返回总条数。
  private async sendBatches(reqs: TdRequest[]): Promise<number> {
    let count: number = 0;
    for (let i = 0; i < reqs.length; i++) {
      const ids: number[] = reqs[i]['message_ids'] as number[];
      const result: TdObject = await getTdClient().send(reqs[i]);
      const forwarded: TdObject[] = (result['messages'] as TdObject[] | undefined) ?? [];
      const albums: string[] = forwarded.map((m: TdObject): string =>
        `${(m['id'] as number | undefined) ?? 0}:${m['media_album_id'] ?? '-'}`);
      logI(`[FwdDiag] batch=${i + 1}/${reqs.length} sent=${ids.length} got=${forwarded.length} ${albums.join(' ')}`);
      count += ids.length;
    }
    return count;
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
    this.sendCopy = !this.sendCopy;
    if (!this.sendCopy) {
      this.removeCaption = false;
    }
  }

  private toggleRemoveCaption(): void {
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
  // 文件夹页签：横向可滚的一排胶囊，「全部」在首位。没有文件夹时整排不出现。
  @Builder
  folderChipsRow() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.chips(), (chip: ForwardFolderChip) => {
          Text(chip.isAll ? $r('app.string.filter_all') : chip.title)
            .fontSize(13)
            .fontWeight(chip.id === this.folderId ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(chip.id === this.folderId ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 140 })
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(16)
            .backgroundColor(chip.id === this.folderId ? '#1A3390EC' : $r('app.color.surface_alt'))
            .onClick((): void => { this.selectFolder(chip.id); });
        }, (chip: ForwardFolderChip): string => `chip_${chip.id}`);
      }
      .padding({ left: 2, right: 2 });
    }
    .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
    .width('100%').align(Alignment.Start);
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
          .onChange((value: string): void => { this.query = value; });
        if (this.chips().length > 1) {
          this.folderChipsRow();
        }
        this.forwardOptionsRow();
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
          Grid() {
            ForEach(this.filteredChats(), (chat: ChatEntry) => {
              GridItem() {
                Column({ space: 6 }) {
                  Stack() {
                    AvatarView({
                      avatarPath: chat.avatarPath,
                      initials: chat.initials,
                      colorSeed: chat.id,
                      avatarSize: 56
                    });
                    if (this.sendingChatId === chat.id) {
                      Column().width(56).height(56).borderRadius(28).backgroundColor('#66000000');
                      LoadingProgress().width(24).height(24).color(Color.White);
                    }
                  }
                  .width(56).height(56);
                  Text(chat.title)
                    .fontSize(12).lineHeight(16).fontColor(COLOR_TEXT_PRIMARY)
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(TextAlign.Center).width('100%').height(32);
                }
                .width('100%').padding({ top: 6, bottom: 4, left: 2, right: 2 })
                .borderRadius(12)
                .opacity(this.sendingChatId === 0 || this.sendingChatId === chat.id ? 1 : 0.45)
                .stateStyles({
                  normal: this.rowNormalStyle,
                  pressed: this.rowPressedStyle
                })
                .animation({
                  duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 120),
                  curve: Curve.EaseOut
                })
                .onClick(() => { this.forwardToChat(chat); });
              }
            }, (chat: ChatEntry): string => `forward_${chat.id}_${chat.revision}`);
          }
          .columnsTemplate(this.gridColumnsTemplate())
          .rowsGap(4).columnsGap(4)
          .layoutWeight(1).width('100%')
          .scrollBar(BarState.Auto)
          .onReachEnd((): void => { getChatStore().loadMore(this.listKey()); });
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
