import { MessageEntry } from '../../store/MessageEntry';
import {
  KEY_BUBBLE_RADIUS, KEY_POWER_ACTIVE, KEY_POWER_CHAT_EFFECTS,
  KEY_POWER_EFFECT_MESSAGE, KEY_POWER_EFFECT_REACTION, KEY_POWER_EMOJI,
  KEY_POWER_EMOJI_REACTIONS, KEY_POWER_SMOOTH_TRANSITIONS, KEY_REDUCE_ANIM,
  KEY_TEXT_SIZE, RADIUS_DEFAULT, TEXT_SIZE_DEFAULT, powerAnimationDuration,
  KEY_MSG_GESTURE
} from '../../store/AppSettings';
import { getAccentColorStore, getUserStore } from '../../tdkit/Globals';
import { bubbleMaxWidth } from '../../util/mediaBox';
import { GESTURE_CLASSIC, MessageGesturePolicy, messageGesturePolicy } from '../../util/messageGestures';
import { overlayBlur, overlayMaterial, overlayBackdropBlur, overlayGlassFill } from '../../util/overlayMaterial';
import { materialModifierWhen } from '../../util/materialModifier';
import { APPEARANCE_EPOCH, KEY_BUBBLE_MATERIAL_ON } from '../../util/appearance';
import {
  senderAvatarFor, senderChannelKey, subscribeSenderAvatar
} from '../../util/senderAvatarChannel';
import { sendStateFor, subscribeSendState } from '../../util/sendStateChannel';
import { str } from '../../util/strings';
import {
  subscribeTranslationStatus, TranslationStatus, translationStatusFor
} from '../../util/translationChannel';
import {
  accentSoft, AVATAR_PALETTE, COLOR_BUBBLE_IN, COLOR_BUBBLE_OUT,
  COLOR_PRIMARY, COLOR_TEXT_SECONDARY, bubbleTextFor
} from '../../util/theme';
import { formatClockTime } from '../../util/formatTime';
import { probeHit } from '../../util/panelProbe';
import { CachedImage } from '../common/CachedImage';
import { actionMenuRow } from './ActionMenuRow';
import { SenderRoleTag } from './SenderRoleTag';
import { CHAT_CONTENT_WIDTH_KEY } from '../../util/chatContentWidth';

const QUICK_REACTIONS: string[] = ['❤️', '👍', '👎', '🔥', '🥰', '👏'];
const SWIPE_REPLY_MAX: number = -56;
const SWIPE_REPLY_TRIGGER: number = -40;
const REPLY_QUOTE_WIDTH_RATIO: number = 0.76;
const REPLY_QUOTE_LINE_H: number = 16;

// Narrow contract on purpose: the lightweight renderer never receives media,
// poll, game, file or playback callbacks. The page-owned MessageBubbleActions
// object is structurally compatible with this subset.
export interface LightweightPlainTextActions {
  onAvatarTap: (userId: number) => void;
  onAvatarLongPress: (userId: number, name: string) => void;
  onReplyTap: (messageId: number, fromId: number) => void;
  onSetReaction: (messageId: number, emoji: string, chosen: boolean) => void;
  onReplyTo: (messageId: number) => void;
  onEditMsg: (messageId: number) => void;
  onTranslateMsg: (messageId: number) => void;
  onPinMsg: (messageId: number, unpin: boolean) => void;
  onSetDefaultReaction: (emoji: string) => void;
  onCopyText: (messageId: number) => void;
  onCopyLink: (messageId: number) => void;
  onForwardMessages: (messageIds: number[]) => void;
  onSaveMessages: (messageIds: number[]) => void;
  onRepeatMessages: (messageIds: number[]) => void;
  onViewSenderHistory: (senderId: number) => void;
  onReportMsg: (messageId: number) => void;
  onSelectMessages: (messageIds: number[]) => void;
  onDeleteMsg: (messageId: number) => void;
  onOpenReactions: (messageId: number) => void;
  onRetryTranslation: (messageId: number) => void;
}

const EMPTY_ACTIONS: LightweightPlainTextActions = {
  onAvatarTap: (_id: number): void => {},
  onAvatarLongPress: (_id: number, _name: string): void => {},
  onReplyTap: (_id: number, _fromId: number): void => {},
  onSetReaction: (_id: number, _emoji: string, _chosen: boolean): void => {},
  onReplyTo: (_id: number): void => {}, onEditMsg: (_id: number): void => {},
  onTranslateMsg: (_id: number): void => {},
  onPinMsg: (_id: number, _unpin: boolean): void => {},
  onSetDefaultReaction: (_emoji: string): void => {},
  onCopyText: (_id: number): void => {}, onCopyLink: (_id: number): void => {},
  onForwardMessages: (_ids: number[]): void => {},
  onSaveMessages: (_ids: number[]): void => {},
  onRepeatMessages: (_ids: number[]): void => {},
  onViewSenderHistory: (_id: number): void => {},
  onReportMsg: (_id: number): void => {},
  onSelectMessages: (_ids: number[]): void => {},
  onDeleteMsg: (_id: number): void => {},
  onOpenReactions: (_id: number): void => {},
  onRetryTranslation: (_id: number): void => {}
};

// The avatar remains independently subscribed so an asynchronous avatar path
// refreshes only this 38vp node, not the whole lightweight row.
@Component
struct LightweightSenderAvatar {
  @Prop senderId: number = 0;
  @Prop senderIsUser: boolean = true;
  @Prop initialPath: string = '';
  @Prop initials: string = '?';
  @State private path: string = '';
  private unsub: (() => void) | null = null;

  private attach(senderId: number, senderIsUser: boolean, initialPath: string): void {
    this.detach();
    const known: string = senderAvatarFor(senderChannelKey(senderId, senderIsUser));
    this.path = known !== '' ? known : initialPath;
    this.unsub = subscribeSenderAvatar(senderChannelKey(senderId, senderIsUser),
      (path: string): void => { this.path = path; });
  }

  private detach(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
  }

  aboutToAppear(): void { this.attach(this.senderId, this.senderIsUser, this.initialPath); }
  aboutToDisappear(): void { this.detach(); }
  aboutToRecycle(): void { this.detach(); }
  aboutToReuse(params: Record<string, Object>): void {
    const senderId: number | undefined = params['senderId'] as number | undefined;
    const senderIsUser: boolean | undefined = params['senderIsUser'] as boolean | undefined;
    const initialPath: string | undefined = params['initialPath'] as string | undefined;
    if (senderId !== undefined && senderIsUser !== undefined) {
      this.attach(senderId, senderIsUser, initialPath ?? '');
    } else {
      setTimeout((): void => {
        this.attach(this.senderId, this.senderIsUser, this.initialPath);
      }, 0);
    }
  }

  build() {
    Stack() {
      Circle({ width: 38, height: 38 })
        .fill(AVATAR_PALETTE[Math.abs(this.senderId) % AVATAR_PALETTE.length]);
      Text(this.initials).fontColor(Color.White).fontSize(15.2).fontWeight(FontWeight.Medium);
      CachedImage({
        path: this.path, boxWidth: 38, boxHeight: 38, radius: 19, fit: ImageFit.Cover
      }).visibility(this.path !== '' ? Visibility.Visible : Visibility.None);
    }.width(38).height(38);
  }
}

@Component
export struct LightweightPlainTextBubble {
  @Prop @Watch('onMessageChanged') msg: MessageEntry;
  @Prop nowSec: number = 0;
  @Prop chatId: number = 0;
  @Prop isGroup: boolean = false;
  @Prop themeBubbleOut: string = '';
  // 本地外观：同 MessageBubble——epoch 驱动底色/文字色重取，材质只给屏内且非省电的气泡。
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @StorageProp(KEY_BUBBLE_MATERIAL_ON) bubbleMaterialOn: boolean = false;
  @State onScreen: boolean = false;

  private bubbleFillColor(): ResourceColor {
    if (this.appearanceEpoch < 0) {
      return Color.Transparent; // 只为让 ArkUI 记下对 epoch 的依赖
    }
    if (this.msg.isOutgoing) {
      return this.themeBubbleOut !== '' ? this.themeBubbleOut : COLOR_BUBBLE_OUT;
    }
    return COLOR_BUBBLE_IN;
  }

  private bubbleMaterialLive(): boolean {
    return this.bubbleMaterialOn && this.onScreen && !this.powerSaving;
  }

  private bubbleBg(): ResourceColor {
    const solid = this.bubbleFillColor();
    return this.bubbleMaterialLive() ? overlayGlassFill('bubble', solid) : solid;
  }
  @Prop showUnreadDivider: boolean = false;
  @Prop dateLabel: string = '';
  @Prop editingActive: boolean = false;
  @Prop isPinnedMsg: boolean = false;
  @Prop showAvatar: boolean = true;
  @Prop showSenderName: boolean = true;
  @Prop animateIn: boolean = false;
  @Prop memberIds: number[] = [];
  actions: LightweightPlainTextActions = EMPTY_ACTIONS;

  // 读的是**内容列宽**，不是窗口宽——分栏下两者差一个左栏（issue #107）。
  // 字段仍叫 screenW：下面十几处按它算宽的式子一个都不用动。
  @StorageProp(CHAT_CONTENT_WIDTH_KEY) screenW: number = 360;
  @StorageProp(KEY_TEXT_SIZE) msgTextSize: number = TEXT_SIZE_DEFAULT;
  @StorageProp(KEY_BUBBLE_RADIUS) bubbleRadius: number = RADIUS_DEFAULT;
  @StorageProp(KEY_REDUCE_ANIM) reduceAnim: boolean = false;
  @StorageProp(KEY_POWER_ACTIVE) powerSaving: boolean = false;
  @StorageProp(KEY_POWER_CHAT_EFFECTS) chatEffectsEnabled: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_MESSAGE) messageEffectsEnabled: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_REACTION) reactionEffectsEnabled: boolean = false;
  @StorageProp(KEY_POWER_EMOJI) emojiEnabled: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) emojiReactionsEnabled: boolean = true;
  @StorageProp(KEY_MSG_GESTURE) gestureScheme: string = GESTURE_CLASSIC;

  @State private liveSendState: string = '';
  @State private translationStatus: TranslationStatus | null = null;
  @State private menuShown: boolean = false;
  @State private swipeX: number = 0;
  private bubbleW: number = 0;
  private menuOffsetX: number = 0;
  private gestureClaimed: boolean = false;
  private unsubSend: (() => void) | null = null;
  private unsubTranslation: (() => void) | null = null;

  private attachChannels(message: MessageEntry): void {
    this.detachChannels();
    const known: string = sendStateFor(message.rowId);
    this.liveSendState = known !== '' ? known : message.sendState;
    this.unsubSend = subscribeSendState(message.rowId,
      (state: string): void => { this.liveSendState = state; });
    this.translationStatus = translationStatusFor(message.id);
    this.unsubTranslation = subscribeTranslationStatus(message.id,
      (next: TranslationStatus | null): void => { this.translationStatus = next; });
  }

  private detachChannels(): void {
    if (this.unsubSend !== null) { this.unsubSend(); this.unsubSend = null; }
    if (this.unsubTranslation !== null) {
      this.unsubTranslation();
      this.unsubTranslation = null;
    }
  }

  private resetTransient(): void {
    this.menuShown = false;
    this.swipeX = 0;
    this.bubbleW = 0;
    this.menuOffsetX = 0;
    this.gestureClaimed = false;
  }

  aboutToAppear(): void {
    probeHit('message.plain.mount');
    this.attachChannels(this.msg);
  }
  aboutToDisappear(): void { this.detachChannels(); }
  aboutToRecycle(): void {
    probeHit('message.plain.recycle');
    this.detachChannels();
    this.resetTransient();
  }
  aboutToReuse(params: Record<string, Object>): void {
    probeHit('message.plain.reuse');
    this.resetTransient();
    const next: MessageEntry | undefined = params['msg'] as MessageEntry | undefined;
    if (next !== undefined) {
      this.attachChannels(next);
    } else {
      setTimeout((): void => { this.attachChannels(this.msg); }, 0);
    }
  }

  private onMessageChanged(): void { this.attachChannels(this.msg); }

  private bubbleMaxW(): number { return bubbleMaxWidth(this.screenW); }
  private inlineMaxW(): number { return this.bubbleMaxW() - 16; }
  private runRadius(): number { return Math.min(this.bubbleRadius, 7); }
  private tailRadius(): number { return Math.min(this.bubbleRadius, 2); }
  private hasTail(): boolean { return this.showAvatar; }
  private rowTopPadding(): number { return this.showSenderName ? 3 : 1; }
  private rowBottomPadding(): number { return this.showAvatar ? 3 : 1; }
  private effectDuration(ms: number): number {
    return this.chatEffectsEnabled && this.messageEffectsEnabled && !this.powerSaving ? ms : 0;
  }
  private reactionDuration(ms: number): number {
    return this.chatEffectsEnabled && this.reactionEffectsEnabled && this.emojiEnabled &&
      this.emojiReactionsEnabled && !this.powerSaving ? ms : 0;
  }

  private bubbleCorners(): BorderRadiuses {
    return {
      topLeft: this.msg.isOutgoing ? this.bubbleRadius :
        (this.showSenderName ? this.bubbleRadius : this.runRadius()),
      topRight: this.msg.isOutgoing ?
        (this.showSenderName ? this.bubbleRadius : this.runRadius()) : this.bubbleRadius,
      bottomLeft: this.msg.isOutgoing ? this.bubbleRadius :
        (this.showAvatar ? this.tailRadius() : this.runRadius()),
      bottomRight: this.msg.isOutgoing ?
        (this.showAvatar ? this.tailRadius() : this.runRadius()) : this.bubbleRadius
    };
  }

  private senderColor(): ResourceColor {
    const accentId: number = this.msg.senderId > 0
      ? getUserStore().accentColorId(this.msg.senderId) : -1;
    if (accentId >= 0) {
      const color: string = getAccentColorStore().nameColorHex(accentId, false);
      if (color !== '') { return color; }
    }
    return AVATAR_PALETTE[Math.abs(this.msg.senderId) % AVATAR_PALETTE.length];
  }

  private messageTime(): string { return formatClockTime(this.msg.date); }
  private timeReserve(): string {
    const edit: string = this.msg.editDate > 0 ? '         ' : '';
    return `${edit}  ${this.messageTime()}${this.msg.isOutgoing ? '   ' : ''}`;
  }

  private replyMaxW(): number { return Math.round(this.inlineMaxW() * REPLY_QUOTE_WIDTH_RATIO); }

  private recordMenuOffset(localX: number): void {
    this.menuOffsetX = this.bubbleW > 0 ? localX - this.bubbleW / 2 : 0;
  }

  private onLongPress(event: GestureEvent): void {
    if (event.fingerList.length > 0) {
      this.recordMenuOffset(event.fingerList[0].localX);
    }
    this.gestureClaimed = true;
    const policy: MessageGesturePolicy = messageGesturePolicy(this.gestureScheme);
    if (policy.longPressOpensMenu) {
      this.menuShown = true;
    } else if (policy.longPressSelects) {
      this.actions.onSelectMessages(this.memberIds);
    }
  }

  private onSwipeUpdate(offsetX: number): void {
    if (this.editingActive) { return; }
    this.swipeX = Math.max(SWIPE_REPLY_MAX, Math.min(0, offsetX));
    if (this.swipeX < 0) { this.gestureClaimed = true; }
  }

  private onSwipeEnd(): void {
    const reply: boolean = !this.editingActive && this.swipeX <= SWIPE_REPLY_TRIGGER;
    animateTo({
      duration: this.powerSaving || this.reduceAnim ? 0 : 180,
      curve: Curve.EaseOut
    }, (): void => { this.swipeX = 0; });
    if (reply) { this.actions.onReplyTo(this.msg.id); }
  }

  @Styles
  bubbleNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

  @Styles
  bubblePressedStyle() { .opacity(0.84).scale({ x: 0.992, y: 0.992 }) }

  @Styles
  menuNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

  @Styles
  menuPressedStyle() { .opacity(0.72).scale({ x: 0.94, y: 0.94 }) }

  @Builder
  statusIcon() {
    Row() {
      SymbolGlyph($r(this.liveSendState === 'sending'
        ? 'sys.symbol.clock'
        : (this.liveSendState === 'failed'
          ? 'sys.symbol.exclamationmark_circle' : 'sys.symbol.checkmark')))
        .fontSize(12)
        .fontColor([this.liveSendState === 'failed' ? Color.Red
          : (this.liveSendState === 'read' ? COLOR_PRIMARY : COLOR_TEXT_SECONDARY)])
        .visibility(this.liveSendState === 'none' || this.liveSendState === ''
          ? Visibility.None : Visibility.Visible);
      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontColor([COLOR_PRIMARY])
        .margin({ left: -8 })
        .visibility(this.liveSendState === 'read' ? Visibility.Visible : Visibility.None);
    }
  }

  @Builder
  replyQuote() {
    Column() {
      Text(this.msg.replySenderName).fontSize(12).fontColor(COLOR_PRIMARY).maxLines(1)
        .lineHeight(REPLY_QUOTE_LINE_H).height(REPLY_QUOTE_LINE_H)
        .constraintSize({ maxWidth: this.replyMaxW() })
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Text(this.msg.replyText).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
        .lineHeight(REPLY_QUOTE_LINE_H).height(REPLY_QUOTE_LINE_H)
        .constraintSize({ maxWidth: this.replyMaxW() })
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(HorizontalAlign.Start).alignSelf(ItemAlign.Stretch)
    .backgroundColor(accentSoft()).borderRadius(6)
    .border({ width: { left: 2 }, color: COLOR_PRIMARY })
    .padding({ left: 6, right: 6, top: 3, bottom: 3 }).margin({ bottom: 4 })
    .onClick((): void => {
      if (!this.gestureClaimed) {
        this.actions.onReplyTap(this.msg.replyToMessageId, this.msg.id);
      }
    });
  }

  @Builder
  translationState() {
    if (this.translationStatus !== null) {
      Divider().color(COLOR_TEXT_SECONDARY).opacity(0.3).strokeWidth(0.6)
        .margin({ top: 6, bottom: 5 });
      if (this.translationStatus?.phase === 'loading') {
        Row({ space: 5 }) {
          LoadingProgress().width(12).height(12).color(COLOR_TEXT_SECONDARY);
          Text($r('app.string.mb_translating')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
          Text(this.timeReserve()).fontSize(11).fontColor(Color.Transparent);
        }.constraintSize({ maxWidth: this.inlineMaxW() });
      } else {
        Row({ space: 4 }) {
          Text(str('mb_translate_failed', this.translationStatus?.error ?? ''))
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          Text($r('app.string.settings_retry')).fontSize(11)
            .fontColor(COLOR_PRIMARY).fontWeight(FontWeight.Medium);
          Text(this.timeReserve()).fontSize(11).fontColor(Color.Transparent);
        }
        .constraintSize({ maxWidth: this.inlineMaxW() })
        .onClick((): void => {
          if (!this.gestureClaimed) { this.actions.onRetryTranslation(this.msg.id); }
        });
      }
    }
  }

  @Builder
  body() {
    Column() {
      if (this.msg.replyToMessageId !== 0) { this.replyQuote(); }
      Text() {
        Span(this.msg.text).fontColor(bubbleTextFor(this.msg.isOutgoing));
        if (this.translationStatus === null) {
          Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
        }
      }
      .fontSize(this.msgTextSize).lineHeight(this.msgTextSize * 1.34)
      .wordBreak(WordBreak.BREAK_WORD).constraintSize({ maxWidth: this.inlineMaxW() });
      this.translationState();
    }.alignItems(HorizontalAlign.Start);
  }

  @Builder
  timeOverlay() {
    Row({ space: 4 }) {
      if (this.msg.editDate > 0) {
        Text($r('app.string.mb_edited')).fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY);
      }
      if (this.messageTime() !== '') {
        Text(this.messageTime()).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }
      if (this.msg.isOutgoing) { this.statusIcon(); }
    }.margin({ bottom: 2 });
  }

  @Builder
  contextMenu() {
    Column() {
      Row({ space: 2 }) {
        ForEach(QUICK_REACTIONS, (emoji: string) => {
          Row() { Text(emoji).fontSize(23); }
            .width(32).height(34).borderRadius(17).justifyContent(FlexAlign.Center)
            .stateStyles({ normal: this.menuNormalStyle, pressed: this.menuPressedStyle })
            .animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
            .onClick((): void => { this.actions.onSetReaction(this.msg.id, emoji, false); })
            .gesture(LongPressGesture().onAction((): void => {
              this.actions.onSetDefaultReaction(emoji);
            }));
        }, (emoji: string): string => emoji);
        Blank();
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(15).fontColor([bubbleTextFor(this.msg.isOutgoing)]);
        }
        .width(30).height(30).borderRadius(15).backgroundColor('#0000000F')
        .justifyContent(FlexAlign.Center)
        .stateStyles({ normal: this.menuNormalStyle, pressed: this.menuPressedStyle })
        .onClick((): void => { this.actions.onOpenReactions(this.msg.id); });
      }
      .width('100%').padding({ left: 12, right: 10, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center);
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow('sys.symbol.arrowshape_turn_up_left', str('mb_reply'), false,
        (): void => { this.actions.onReplyTo(this.msg.id); });
      if (this.msg.isOutgoing && this.nowSec - this.msg.date < 172800) {
        actionMenuRow('sys.symbol.square_and_pencil', str('edit'), false,
          (): void => { this.actions.onEditMsg(this.msg.id); });
      }
      actionMenuRow('sys.symbol.plus_square_on_square', str('mb_copy_text'), false,
        (): void => { this.actions.onCopyText(this.msg.id); });
      actionMenuRow('sys.symbol.translate', str('mb_translate'), false,
        (): void => { this.actions.onTranslateMsg(this.msg.id); });
      actionMenuRow('sys.symbol.link', str('mb_copy_link'), false,
        (): void => { this.actions.onCopyLink(this.msg.id); });
      actionMenuRow('sys.symbol.arrowshape_turn_up_right', str('mb_forward'), false,
        (): void => { this.actions.onForwardMessages(this.memberIds); });
      actionMenuRow('sys.symbol.bookmark', str('mb_save_to_saved'), false,
        (): void => { this.actions.onSaveMessages(this.memberIds); });
      actionMenuRow('sys.symbol.repeat', str('mb_repeat'), false,
        (): void => { this.actions.onRepeatMessages(this.memberIds); });
      if (this.isGroup && this.msg.senderIsUser && this.msg.senderId > 0) {
        actionMenuRow('sys.symbol.person', str('mb_view_history'), false,
          (): void => { this.actions.onViewSenderHistory(this.msg.senderId); });
      }
      actionMenuRow('sys.symbol.pin', this.isPinnedMsg ? str('ft_unpin') : str('ft_pin'), false,
        (): void => { this.actions.onPinMsg(this.msg.id, this.isPinnedMsg); });
      actionMenuRow('sys.symbol.exclamationmark_circle', str('mb_report'), true,
        (): void => { this.actions.onReportMsg(this.msg.id); });
      actionMenuRow('sys.symbol.checkmark_circle', str('mb_select'), false,
        (): void => { this.actions.onSelectMessages(this.memberIds); });
      actionMenuRow('sys.symbol.trash', str('delete'), true,
        (): void => { this.actions.onDeleteMsg(this.msg.id); });
    }.width(262).padding({ top: 6, bottom: 6 });
  }

  build() {
    Column() {
      if (this.dateLabel !== '') {
        Row() {
          Text(this.dateLabel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .fontWeight(FontWeight.Medium).backgroundColor($r('app.color.system_pill'))
            .borderRadius(11).padding({ left: 10, right: 10, top: 3, bottom: 3 });
        }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 5, bottom: 3 });
      }
      if (this.showUnreadDivider) {
        Text($r('app.string.mb_unread')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.system_pill'))
          .padding({ top: 3, bottom: 3 }).margin({ bottom: 4 });
      }
      Row() {
        Row() {
          if (this.isGroup && !this.msg.isOutgoing) {
            if (this.showAvatar) {
              LightweightSenderAvatar({
                senderId: this.msg.senderId,
                senderIsUser: this.msg.senderIsUser,
                initialPath: this.msg.senderAvatarPath,
                initials: this.msg.senderInitials
              })
                .margin({ right: 6 })
                .onClick((): void => {
                  if (!this.gestureClaimed && this.msg.senderIsUser && this.msg.senderId > 0) {
                    this.actions.onAvatarTap(this.msg.senderId);
                  }
                })
                .gesture(LongPressGesture().onAction((): void => {
                  if (this.msg.senderIsUser && this.msg.senderId > 0) {
                    this.actions.onAvatarLongPress(this.msg.senderId, this.msg.senderName);
                  }
                }));
            } else {
              Column().width(44);
            }
          }
          if (!this.msg.isOutgoing && this.hasTail()) {
            Polygon({ width: 8, height: 12 }).points([[8, 0], [0, 12], [8, 12]])
              .fill(this.bubbleFillColor()).margin({ right: -1 });
          } else if (!this.msg.isOutgoing) {
            Column().width(7);
          }
          Column() {
            if (this.isGroup && !this.msg.isOutgoing && this.msg.senderName !== '' &&
              this.showSenderName) {
              Row({ space: 5 }) {
                Text(this.msg.senderName).fontSize(14).fontColor(this.senderColor())
                  .fontWeight(FontWeight.Medium).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1);
                SenderRoleTag({
                  chatId: this.chatId, senderId: this.msg.senderId,
                  presetTag: this.msg.senderTag
                });
              }.margin({ bottom: 2 }).alignItems(VerticalAlign.Center);
            }
            Stack({ alignContent: Alignment.BottomEnd }) {
              this.body();
              this.timeOverlay();
            }.constraintSize({ maxWidth: this.inlineMaxW() });
          }
          .alignItems(HorizontalAlign.Start).constraintSize({ maxWidth: this.bubbleMaxW() })
          .backgroundColor(this.bubbleBg())
          .backdropBlur(this.bubbleMaterialLive() ? overlayBackdropBlur('bubble') : 0)
          .attributeModifier(materialModifierWhen('bubble', this.bubbleMaterialLive()))
          .onVisibleAreaChange([0, 0.01], (visible: boolean): void => {
            this.onScreen = visible;
          })
          .borderRadius(this.bubbleCorners()).padding(8)
          .shadow({ radius: 2, color: '#14000000', offsetX: 0, offsetY: 1 })
          .stateStyles({ normal: this.bubbleNormalStyle, pressed: this.bubblePressedStyle })
          .animation({ duration: this.effectDuration(110), curve: Curve.EaseOut })
          .onAreaChange((_old: Area, area: Area): void => { this.bubbleW = area.width as number; })
          .parallelGesture(LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
            .onAction((event: GestureEvent): void => { this.onLongPress(event); }))
          .onClick((event: ClickEvent): void => {
            if (!this.gestureClaimed && messageGesturePolicy(this.gestureScheme).tapOpensMenu) {
              this.recordMenuOffset(event.x);
              this.menuShown = true;
            }
          });
          if (this.msg.isOutgoing && this.hasTail()) {
            Polygon({ width: 8, height: 12 }).points([[0, 0], [8, 12], [0, 12]])
              .fill(this.themeBubbleOut !== '' ? this.themeBubbleOut : COLOR_BUBBLE_OUT)
              .margin({ left: -1 });
          } else if (this.msg.isOutgoing) {
            Column().width(7);
          }
        }
        .alignItems(VerticalAlign.Bottom)
        .bindContextMenu(this.menuShown, this.contextMenu(), {
          offset: { x: this.menuOffsetX, y: 0 },
          preview: MenuPreviewMode.IMAGE,
          previewBorderRadius: this.bubbleCorners(),
          previewAnimationOptions: {
            scale: [0.98, 1.035],
            transition: TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.98, y: 0.98 }))
              .animation({
                duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
                curve: Curve.FastOutSlowIn
              })
          },
          borderRadius: 16,
          backgroundColor: Color.Transparent,
          backgroundBlurStyle: overlayBlur('menu'),
          systemMaterial: overlayMaterial('menu'),
          transition: TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
            .animation({
              duration: powerAnimationDuration(KEY_POWER_SMOOTH_TRANSITIONS, 180),
              curve: Curve.FastOutSlowIn
            }),
          mask: { color: '#52000000', backgroundBlurStyle: BlurStyle.BACKGROUND_THIN },
          modalMode: ModalMode.TARGET_WINDOW,
          hapticFeedbackMode: HapticFeedbackMode.AUTO,
          onDisappear: (): void => { this.menuShown = false; }
        });
      }
      .width('100%').padding({
        left: 10, right: 10, top: this.rowTopPadding(), bottom: this.rowBottomPadding()
      })
      .justifyContent(this.msg.isOutgoing ? FlexAlign.End : FlexAlign.Start)
      .alignItems(VerticalAlign.Bottom).translate({ x: this.swipeX })
      .parallelGesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
        .onActionUpdate((event: GestureEvent): void => { this.onSwipeUpdate(event.offsetX); })
        .onActionEnd((): void => { this.onSwipeEnd(); })
        .onActionCancel((): void => { this.onSwipeEnd(); }))
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) { this.gestureClaimed = false; }
      });
    }
    .width('100%')
    .transition(this.animateIn
      ? TransitionEffect.translate({ y: 16 }).combine(TransitionEffect.OPACITY)
        .animation({ duration: this.effectDuration(220), curve: Curve.FastOutSlowIn })
      : TransitionEffect.IDENTITY);
  }
}
