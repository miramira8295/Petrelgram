import { promptAction } from '@kit.ArkUI';
import { ChatEntry } from '../../store/ChatEntry';
import { AvatarView } from '../chatlist/AvatarView';
import { getChatStore, getTdClient } from '../../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../../tdkit/TdTypes';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import {
  KEY_POWER_EFFECT_REPLY, KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { plural, str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

// "Forward to…" chat picker, extracted from ChatPage.
//
// Ownership split with the page: the page decides *whether* the sheet is up and
// which messages are being forwarded (it has to filter out non-forwardable ones
// before there is anything to show). The chat list — loading, retry, filtering,
// and the forwardMessages request itself — lives here. The page's
// `if (showForwardSheet)` branch creates and destroys this component, so the
// query box and in-flight send state reset per open without explicit teardown.
@Component
export struct ForwardSheet {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  // Two-way: the close button and a successful send both dismiss from in here.
  @Link show: boolean;

  // Set by the page at construction. Plain fields are correct: the sheet is
  // rebuilt on each open, and these never change while it is up.
  messageIds: number[] = [];
  sourceChatId: number = 0;
  threadRootId: number = 0;

  // Read directly rather than passed down — same source the page uses, so the
  // padding still tracks the keyboard while the search box has focus.
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('keyboardHeightVp') keyboardH: number = 0;

  effectDuration: (key: string, ms: number) => number =
    (_key: string, ms: number): number => ms;
  // The page leaves multi-select mode after a successful forward.
  onSent: () => void = (): void => {};

  @State chats: ChatEntry[] = [];
  @State query: string = '';
  @State loadState: string = 'ready'; // loading | ready | error
  @State sendingChatId: number = 0;

  // Guards async continuations against a sheet that has since been closed or
  // reopened. Kept even though the component is destroyed on close: a request
  // in flight at that moment would otherwise write state on a dead instance.
  private seq: number = 0;
  private unsubChats: (() => void) | null = null;

  aboutToAppear(): void {
    // Live subscription rather than a one-shot read: the main list reorders as
    // messages arrive and rows gain avatars as those downloads finish, and an
    // open picker has to track that. ChatPage used to push these updates in
    // from its own subscription; owning it here keeps that behaviour without
    // the page needing to know the sheet exists.
    this.unsubChats = getChatStore().subscribe((list: ChatEntry[]): void => {
      this.applyChats(list);
    }, 'main'); // fires immediately with the currently cached list
    this.loadChats();
  }

  aboutToDisappear(): void {
    this.seq++;
    if (this.unsubChats !== null) {
      this.unsubChats();
      this.unsubChats = null;
    }
  }

  // Empirically tuned on device: with the keyboard up the sheet needs lifting
  // clear of the IME edge; without it the layout already sits above the gesture
  // bar, so only minimal padding applies.
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
    getChatStore().ensureLoaded('main').then((success: boolean): void => {
      if (seq !== this.seq) {
        return;
      }
      this.applyChats(getChatStore().getChats('main'));
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
    getChatStore().loadMore('main').then((): void => {
      if (seq !== this.seq) {
        return;
      }
      this.applyChats(getChatStore().getChats('main'));
      this.loadState = this.chats.length > 0 ? 'ready' : 'error';
    });
  }

  private close(): void {
    this.seq++;
    this.show = false;
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
    // 必须升序且不重复：TDLib 对 forwardMessages 的原话是"Message identifiers
    // must be in a strictly increasing order"，多选是按点击顺序攒的，从下往上
    // 选就是递减，请求直接被拒。单条永远"有序"，所以这个坑只在多条时露出来。
    // 排序放在这里而不是选择那侧：这里是和 TDLib 的边界，任何调用方都得过。
    const ids: number[] = [...this.messageIds]
      .sort((a: number, b: number): number => a - b)
      .filter((id: number, i: number, arr: number[]): boolean => i === 0 || id !== arr[i - 1]);
    const seq: number = this.seq;
    this.sendingChatId = chat.id;
    const req: TdRequest = { '@type': 'forwardMessages' };
    req['chat_id'] = chat.id;
    req['message_thread_id'] = chat.id === this.sourceChatId ? this.threadRootId : 0;
    req['from_chat_id'] = this.sourceChatId;
    req['message_ids'] = ids;
    req['send_copy'] = false;
    req['remove_caption'] = false;
    getTdClient().send(req).then((result: TdObject): void => {
      // 诊断：反馈"多图消息转发过去变成一张一张"。相册要么在请求这一侧就没
      // 成组，要么 TDLib 成了组而我们没渲染成组——两者的修法完全不同，靠读
      // 代码分不出来。forwardMessages 回的是 Messages，把每条的 media_album_id
      // 打出来即可定论：都相同且非 0 = TDLib 成了组，问题在渲染侧；各不相同
      // 或缺失 = 问题在请求侧。
      //
      // 只打 id 和相册号，不含任何消息内容——与 StoreDiag 同一口径。
      const forwarded: TdObject[] = (result['messages'] as TdObject[] | undefined) ?? [];
      const albums: string[] = forwarded.map((m: TdObject): string =>
        `${(m['id'] as number | undefined) ?? 0}:${m['media_album_id'] ?? '-'}`);
      console.info(`[FwdDiag] sent=${ids.length} got=${forwarded.length} ${albums.join(' ')}`);
      if (seq !== this.seq) {
        return;
      }
      const count: number = ids.length;
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
      console.error(`ForwardSheet.forwardMessages failed: ${e.message}`);
      promptAction.showToast({ message: $r('app.string.fw_failed'), duration: 2000 });
    });
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

  build() {
    Column() {
      Column().layoutWeight(1)
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
            SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_TEXT_SECONDARY]);
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
        if (this.loadState === 'loading') {
          Column({ space: 10 }) {
            LoadingProgress().width(26).height(26).color(COLOR_PRIMARY);
            Text($r('app.string.fw_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.loadState === 'error') {
          Column({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
            Text($r('app.string.fw_load_failed')).fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
            Button($r('app.string.settings_retry'))
              .fontSize(14).fontColor(Color.White)
              .height(36).padding({ left: 20, right: 20 })
              .backgroundColor(COLOR_PRIMARY).borderRadius(18)
              .onClick(() => { this.retryChats(); });
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else if (this.filteredChats().length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(28).fontColor([COLOR_TEXT_SECONDARY]);
            Text(this.query.trim() === '' ? $r('app.string.fw_empty') : $r('app.string.fw_no_match'))
              .fontSize(14).fontColor(COLOR_TEXT_SECONDARY);
          }
          .layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else {
          List() {
            ForEach(this.filteredChats(), (chat: ChatEntry) => {
              ListItem() {
                Row({ space: 12 }) {
                  AvatarView({
                    avatarPath: chat.avatarPath,
                    initials: chat.initials,
                    colorSeed: chat.id,
                    avatarSize: 42
                  });
                  Column({ space: 3 }) {
                    Text(chat.title).fontSize(15).fontWeight(FontWeight.Medium)
                      .fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    Text(chat.id === this.sourceChatId ? $r('app.string.fw_current_chat') :
                      (chat.lastMessageText !== '' ? chat.lastMessageText : $r('app.string.fw_tap_forward')))
                      .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                  }
                  .alignItems(HorizontalAlign.Start).layoutWeight(1);
                  if (this.sendingChatId === chat.id) {
                    LoadingProgress().width(20).height(20).color(COLOR_PRIMARY);
                  } else {
                    SymbolGlyph($r('sys.symbol.paperplane'))
                      .fontSize(18).fontColor([COLOR_PRIMARY]);
                  }
                }
                .width('100%').padding({ left: 6, right: 6, top: 8, bottom: 8 })
                .alignItems(VerticalAlign.Center)
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
          .layoutWeight(1).width('100%')
          .divider({ strokeWidth: 0.7, color: $r('app.color.divider'), startMargin: 60, endMargin: 6 })
          .scrollBar(BarState.Auto)
          .onReachEnd((): void => { getChatStore().loadMore('main'); });
        }
      }
      .width('calc(100% - 16vp)').height('64%')
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
