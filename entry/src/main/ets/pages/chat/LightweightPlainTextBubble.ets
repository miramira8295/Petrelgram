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
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { GESTURE_CLASSIC, MessageGesturePolicy, messageGesturePolicy } from '../../util/messageGestures';
import {
  glassTailBlur, glassTailFill, overlayBackdropBlur, overlayBlur, overlayGlassFill, overlayMaterial
} from '../../util/overlayMaterial';
import {
  GLASS_OUTLINE_COLOR, GLASS_OUTLINE_WIDTH, TAIL_H, TAIL_W, bubbleGlassModifier, glassOutlineCommands, tailClip
} from '../../util/bubbleTail';
import { tailShapeCommands } from '../../util/bubbleGlassPath';
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
import { logW } from '../../util/log';
import { reuseParam } from '../../util/reuseParams';

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
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // @Watch（审计设计约束「订阅按 key 自愈」）：头像订阅的 key 就是 senderId。
  // aboutToReuse 的 params 未必带得到新值，而父级 ReusableMessageBubble
  // **已经是** @ReusableV2（P3 批 1），它的 aboutToReuse 没有入参。挂 @Watch
  // 之后，senderId 只要
  // **变了**，@Prop 无论何时落地订阅都会按新 key 自己纠正，不必依赖 params。
  //
  // **但它替代不了 aboutToReuse 里的 setTimeout 兜底，别删那条（I-3）。**
  // @Watch 只在值**变化**时触发：同一个发送者连发几条时 senderId 不变，
  // watch 根本不跑，而 aboutToRecycle 已经清了 path、退了订阅、把
  // attachedKey 归零。那时 setTimeout 是唯一的复活路径，删掉会永久空白。
  @Prop @Watch('onSenderChanged') senderId: number = 0;
  @Prop @Watch('onSenderChanged') senderIsUser: boolean = true;
  @Prop initialPath: string = '';
  @Prop initials: string = '?';
  @State private path: string = '';
  private unsub: (() => void) | null = null;

  // 订阅当前挂在哪个发送者 key 上：既用于同 key 短路（审计 P1-1，一次复用会
  // 经 aboutToReuse 和 @Watch 各挂一次），也让「订阅挂在哪」变成可判定的事实。
  private attachedKey: string = '';

  private attach(senderId: number, senderIsUser: boolean, initialPath: string): void {
    const key: string = senderChannelKey(senderId, senderIsUser);
    const known: string = senderAvatarFor(key);
    if (this.unsub !== null && this.attachedKey === key) {
      // 同 key 短路：订阅不动，但 path 要重新播种——P0-2 让 aboutToRecycle /
      // aboutToReuse 无条件清空了它，不补种会空一帧头像。
      this.path = known !== '' ? known : initialPath;
      return;
    }
    this.detach();
    this.attachedKey = key;
    this.path = known !== '' ? known : initialPath;
    this.unsub = subscribeSenderAvatar(key, (path: string): void => { this.path = path; });
  }

  // 按 key 自愈：@Prop 落地时若发送者换了，把订阅重挂到新 key 上。
  // 第三个参数刻意传 ''，不传 this.initialPath（I-2）：@Prop 逐个赋值，
  // senderId 的 watch 回调触发时 this.initialPath 可能还是上一个发送者的路径，
  // 而 attach 里「通道没缓存就用 initialPath」会在新面孔滚入时画出上一个人的
  // 头像——就是这轮要修的「头像串行」换了条路径。传 '' 最差是先显示首字母。
  private onSenderChanged(): void {
    this.attach(this.senderId, this.senderIsUser, '');
  }

  private detach(): void {
    if (this.unsub !== null) {
      this.unsub();
      this.unsub = null;
    }
    this.attachedKey = '';
  }

  aboutToAppear(): void { this.attach(this.senderId, this.senderIsUser, this.initialPath); }
  aboutToDisappear(): void { this.detach(); }
  aboutToRecycle(): void {
    this.detach();
    // P0-2（审计 3.1；C 类变量 path，行 110）：detach 只停订阅、不改值，而
    // CachedImage 的 path 与 visibility 都直接读它。不清空的话，走 aboutToReuse
    // 兜底分支的那一帧画的就是上一个发送者的位图——历史上的「头像串行」。
    // 清 path 不依赖新参数，所以回收与复用两条路径都无条件执行。
    this.path = '';
  }
  aboutToReuse(params: Record<string, Object>): void {
    // 无条件前置（审计 S1）：清理跑在 params 判断之前，V2 无入参时同样成立。
    this.path = '';
    // reuseParam：params 是 {} 还是 undefined 都安全，取不到就落到 else 的
    // setTimeout 兜底（P3 批 2 第 0 项，见 util/reuseParams.ets）。
    const senderId: number | undefined = reuseParam(params, 'senderId') as number | undefined;
    const senderIsUser: boolean | undefined =
      reuseParam(params, 'senderIsUser') as boolean | undefined;
    const initialPath: string | undefined =
      reuseParam(params, 'initialPath') as string | undefined;
    if (senderId !== undefined && senderIsUser !== undefined) {
      this.attach(senderId, senderIsUser, initialPath ?? '');
    } else {
      // **实测（2026-08-26 真机，820 个复用样本，P2-1 探针，已下架）**：params
      // 恒带全 senderId/senderIsUser，present=0 一次都没出现，params 与此刻的
      // @Prop 也从未不一致——这条分支在当前调用图下**不可达**。
      // **推导（不是实测）**：仍然不能删（I-3）。@Watch 只在值变化时触发，连续
      // 两条同一发送者的消息 senderId 不变 → onSenderChanged 不跑；而
      // aboutToRecycle 已经清了 path、退了订阅、把 attachedKey 归零，那时这里是
      // 唯一复活路径，删掉会得到永久空白头像。父级**已经是** @ReusableV2
      // （P3 批 1），aboutToReuse 没有入参，这条**已经是**唯一分支。
      //
      // 官方没写清 @ReusableV2 递归调用 V1 子组件的 aboutToReuse 时，params
      // 传的是 {} 还是 undefined。P3 批 2 第 0 项改用 reuseParam 读，两种都不抛，
      // 都落到这条兜底。见 MessageBubble 同一处。
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

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  @Prop @Watch('onMessageChanged') msg: MessageEntry;
  @Prop nowSec: number = 0;
  @Prop chatId: number = 0;
  @Prop isGroup: boolean = false;
  @Prop themeBubbleOut: string = '';
  // 本地外观：同 MessageBubble——epoch 驱动底色/文字色重取，材质只给屏内且非省电的气泡。
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  @StorageProp(KEY_BUBBLE_MATERIAL_ON) bubbleMaterialOn: boolean = false;
  // 初值 true：行是在 LazyForEach 首批里建出来的，onVisibleAreaChange 的首帧
  // 回调常常不来，初值 false 会让玻璃层等到「滑动一下」才挂上（用户报的）。
  // 由回调负责在真正离屏时关掉——那一路是可靠的。
  @State onScreen: boolean = true;
  @State glassW: number = 0;
  @State glassH: number = 0;

  private bubbleFillColor(): ResourceColor {
    if (this.appearanceEpoch < 0) {
      return Color.Transparent; // 只为让 ArkUI 记下对 epoch 的依赖
    }
    if (this.msg.isOutgoing) {
      return this.themeBubbleOut !== '' ? this.themeBubbleOut : COLOR_BUBBLE_OUT;
    }
    return COLOR_BUBBLE_IN;
  }

  @Builder
  bubbleTail(outgoing: boolean) {
    if (this.bubbleMaterialLive()) {
      // 玻璃气泡的尾巴：实心玻璃色三角。材质是合成层、不吃 clipShape，挂上去会
      // 在三角外糊出一块矩形背板，所以这里只用它的回退色（见 glassTailFill）。
      // 玻璃档下尾巴只占位：整块形状由上层容器的轮廓裁剪画出来。
      Column().width(TAIL_W).height(TAIL_H).margin(outgoing ? { left: -1 } : { right: -1 });
    } else {
      // 和玻璃档同一条曲线（tailShapeCommands），两档尾巴必须长得一样。
      // strokeWidth(0)：Path 不显式关描边就会沿轮廓画一圈黑线，尾巴看着像被
      // 勾了边（真机实拍确认）。填充色由 fill 给，描边一律不要。
      Path({ width: TAIL_W, height: TAIL_H })
        .commands(tailShapeCommands(outgoing, TAIL_W, TAIL_H, vp2px(1)))
        .fill(this.bubbleFillColor())
        .stroke(Color.Transparent)
        .strokeWidth(0)
        // 压叠 2px 而不是 1px：去掉黑描边之后，尾巴和气泡是两个相邻节点，
        // 1px 压叠下拼缝的抗锯齿会露出一条细线（之前被那圈黑边盖住了）。
        // 只影响实心档——玻璃档整块是一条轮廓裁出来的，没有拼缝。
        .margin(outgoing ? { left: -2 } : { right: -2 });
    }
  }

  private bubbleMaterialLive(): boolean {
    return this.bubbleMaterialOn && this.onScreen && !this.powerSaving;
  }

  private bubbleBg(): ResourceColor {
    return this.bubbleMaterialLive() ? this.glassBg() : this.bubbleFillColor();
  }

  // 见 MessageBubble 同一处：气泡与尾巴统一走普通玻璃渲染，才能接成一体。
  private glassBg(): ResourceColor {
    return this.bubbleMaterialLive() ? overlayGlassFill('bubble', this.bubbleFillColor()) : Color.Transparent;
  }

  private glassBlur(): number {
    return this.bubbleMaterialLive() ? overlayBackdropBlur('bubble') : 0;
  }

  // 材质本体按节点的 borderRadius 画圆角，裁剪路径只管尾巴那一侧：尾巴侧的底角设 0。
  private glassRadius(): BorderRadiuses {
    const r = this.bubbleCorners();
    if (!this.hasTail()) {
      return r;
    }
    return this.msg.isOutgoing
      ? { topLeft: r.topLeft, topRight: r.topRight, bottomRight: 0, bottomLeft: r.bottomLeft }
      : { topLeft: r.topLeft, topRight: r.topRight, bottomRight: r.bottomRight, bottomLeft: 0 };
  }

  // 见 MessageBubble.glassOutline()：材质的边框只沿节点 border-box 画，尾巴那一侧
  // 补不上，自己沿整条轮廓描一圈；画在 .background() 里，不参与命中测试。
  @Builder
  glassOutline() {
    if (this.bubbleMaterialLive() && this.glassW > 0 && this.glassH > 0) {
      Path({ width: this.glassW, height: this.glassH })
        .commands(glassOutlineCommands(this.glassW, this.glassH, this.msg.isOutgoing,
          this.hasTail(), this.bubbleCorners()))
        .fill(Color.Transparent)
        .stroke(GLASS_OUTLINE_COLOR)
        .strokeWidth(GLASS_OUTLINE_WIDTH);
    }
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

  // 订阅当前挂在哪条消息上。发送状态按 rowId 订阅、翻译态按 message.id 订阅，
  // 所以 key 要把两者都算进去。用途同头像：同 key 短路（审计 P1-1，复用一次
  // 会经 aboutToReuse 和 @Watch onMessageChanged 各挂一次）+ 按 key 自愈。
  private attachedKey: string = '';

  private attachChannels(message: MessageEntry): void {
    const key: string = `${message.rowId}:${message.id}`;
    if (this.unsubSend !== null && this.attachedKey === key) {
      // 同 key 短路：退订+重订阅整轮省掉，只重新播种数值——清理是无条件的，
      // 不补种会空一帧。
      this.seedChannelValues(message);
      return;
    }
    this.detachChannels();
    this.attachedKey = key;
    this.seedChannelValues(message);
    this.unsubSend = subscribeSendState(message.rowId,
      (state: string): void => { this.liveSendState = state; });
    this.unsubTranslation = subscribeTranslationStatus(message.id,
      (next: TranslationStatus | null): void => { this.translationStatus = next; });
  }

  // 先读通道现值，没有才用 @Prop 带来的初值（滚回历史消息时不会有新的发布）。
  private seedChannelValues(message: MessageEntry): void {
    const known: string = sendStateFor(message.rowId);
    this.liveSendState = known !== '' ? known : message.sendState;
    this.translationStatus = translationStatusFor(message.id);
  }

  // C 类通道值同样不依赖新参数（同 MessageBubble 的 clearChannelValues，依据
  // 审计 3.2a）：不清就会拿上一条消息的发送勾/翻译态渲染新消息一帧。
  private clearChannelValues(): void {
    this.liveSendState = '';
    this.translationStatus = null;
  }

  private detachChannels(): void {
    if (this.unsubSend !== null) { this.unsubSend(); this.unsubSend = null; }
    if (this.unsubTranslation !== null) {
      this.unsubTranslation();
      this.unsubTranslation = null;
    }
    this.attachedKey = '';
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
    // 与 aboutToReuse 保持同一份清理（审计 S1）：通道值也归零，别让组件带着
    // 上一条消息的发送勾/翻译态躺在复用池里。
    this.clearChannelValues();
  }
  aboutToReuse(params: Record<string, Object>): void {
    probeHit('message.plain.reuse');
    // 无条件前置（审计 S1）：这两行不依赖新参数，父级 @ReusableV2 无入参时
    // 也成立。
    this.resetTransient();
    this.clearChannelValues();
    // reuseParam：params 是 {} 还是 undefined 都安全（P3 批 2 第 0 项）。
    const next: MessageEntry | undefined =
      reuseParam(params, 'msg') as MessageEntry | undefined;
    if (next !== undefined) {
      this.attachChannels(next);
    } else {
      // **实测（2026-08-26 真机，820 个复用样本，P2-1 探针，已下架）**：params
      // 恒带 msg，present=0 一次都没出现，params 与此刻的 @Prop 也从未不一致
      // ——这条分支在当前调用图下**不可达**。
      // **推导（不是实测）**：仍然不能删（I-3）。onMessageChanged 只在 @Prop msg
      // 真的变化时触发；复用回同一条消息时它不跑，而 aboutToRecycle 已经退订并
      // 把 attachedKey 归零，那时这里是唯一的重挂路径。父级**已经是**
      // @ReusableV2（P3 批 1），aboutToReuse 没有入参，这条**已经是**唯一分支。
      setTimeout((): void => { this.attachChannels(this.msg); }, 0);
    }
    // 见 MessageBubble 同一处：复用后玻璃层要重新量。
    this.glassW = 0;
    this.glassH = 0;
    this.onScreen = true;
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
    return animationDurationFor(
      this.chatEffectsEnabled && this.messageEffectsEnabled && !this.powerSaving,
      scrollActiveNow(), ms);
  }
  private reactionDuration(ms: number): number {
    return animationDurationFor(
      this.chatEffectsEnabled && this.reactionEffectsEnabled && this.emojiEnabled &&
        this.emojiReactionsEnabled && !this.powerSaving,
      scrollActiveNow(), ms);
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
          : (this.liveSendState === 'read' ? this.accent() : COLOR_TEXT_SECONDARY)])
        .visibility(this.liveSendState === 'none' || this.liveSendState === ''
          ? Visibility.None : Visibility.Visible);
      SymbolGlyph($r('sys.symbol.checkmark')).fontSize(12).fontColor([this.accent()])
        .margin({ left: -8 })
        .visibility(this.liveSendState === 'read' ? Visibility.Visible : Visibility.None);
    }
  }

  @Builder
  replyQuote() {
    Column() {
      Text(this.msg.replySenderName).fontSize(12).fontColor(this.accent()).maxLines(1)
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
    .border({ width: { left: 2 }, color: this.accent() })
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
            .fontColor(this.accent()).fontWeight(FontWeight.Medium);
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
          Row() {
          if (!this.msg.isOutgoing && this.hasTail()) {
            this.bubbleTail(false);
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
          .alignItems(HorizontalAlign.Start)
          // 与 MessageBubble 同一策略、同一理由（见那边的长注释）：气泡根节点上
          // 不挂常驻 .animation()，按下态直接切换。真机 trace 已证明换位置留不住
          // 动画边界，只有节点上完全没有常驻动画，普通数据更新才不会进入动画
          // 上下文、连带整张消息 List 的重测。两支气泡必须同改。
          .stateStyles({ normal: this.bubbleNormalStyle, pressed: this.bubblePressedStyle })
          .constraintSize({ maxWidth: this.bubbleMaxW() })
          .backgroundColor(this.bubbleBg())
          .backdropBlur(this.glassBlur())
          .onVisibleAreaChange([0, 0.01], (visible: boolean): void => {
            this.onScreen = visible;
          })
          .borderRadius(this.bubbleCorners()).padding(8)
          .shadow({ radius: this.bubbleMaterialLive() ? 0 : 2, color: '#14000000', offsetX: 0, offsetY: 1 })
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
            this.bubbleTail(true);
          } else if (this.msg.isOutgoing) {
            Column().width(7);
          }
          }
          // 「尾巴 + 气泡」整块由**上层**渲染：材质挂在这一层，形状由整体轮廓裁剪
          // 给出（圆角矩形 + 三角尾巴）。尾巴在布局里只占位——两者天生一体，
          // 不存在「一边材质一边普通渲染」对不齐的问题。
          .alignItems(VerticalAlign.Bottom)
          .backgroundColor(this.glassBg())
          .backdropBlur(this.glassBlur())
          // 见 MessageBubble 同一处：材质的边框沿本节点 border-box 画、吃 borderRadius，
          // 不设圆角就是个直角框，裁剪之后剩下半条亮线。
          .borderRadius(this.glassRadius())
          .background(this.glassOutline(), { align: Alignment.TopStart })
              .attributeModifier(bubbleGlassModifier(this.bubbleMaterialLive(), this.glassW, this.glassH,
            this.msg.isOutgoing, this.hasTail(), this.bubbleCorners(),
            this.bubbleMaterialOn ? (w: number, h: number): void => {
              this.glassW = w;
              this.glassH = h;
            } : null))
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
