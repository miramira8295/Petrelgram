import { SymbolGlyphModifier } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { getAccentColorStore, getUserStore } from '../../tdkit/Globals';
import { bubbleMaxWidth } from '../../util/mediaBox';
import {
  animationDurationFor, scrollActiveNow
} from '../../util/scrollEffects';
import { MessageGesturePolicy, messageGesturePolicy } from '../../util/messageGestures';
import {
  overlayBackdropBlur, overlayBlur, overlayGlassFill, overlayMaterial
} from '../../util/overlayMaterial';
import {
  GLASS_OUTLINE_COLOR, GLASS_OUTLINE_WIDTH, TAIL_H, TAIL_W, bubbleGlassModifier, glassOutlineCommands
} from '../../util/bubbleTail';
import {
  glassBodyFallbackPainted, glassBodyPainted, glassPaintReady, tailShapeCommands
} from '../../util/bubbleGlassPath';
import { timeLayerMinWidth } from '../../util/timeLayerWidth';
// 【临时探针，验完就删】见 util/tailFlipProbe.ets 的删除清单。
import { probeGlassMeasure } from '../../util/tailFlipProbe';
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
  COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, bubbleTextFor
} from '../../util/theme';
import { formatClockTime } from '../../util/formatTime';
import { probeHit } from '../../util/panelProbe';
import { CachedImage } from '../common/CachedImage';
import { SenderRoleTag } from './SenderRoleTag';
import { logW } from '../../util/log';
// ⚠️ 临时探针，验完即删——见 util/avatarReuseProbe 的删除清单。
import { probeAvatarReuse } from '../../util/avatarReuseProbe';
import { menuPreviewCompact } from '../../util/menuPreview';
// ⚠️ 临时探针（P4 批 0.5，判读完删）。
import { V2ReuseProbe } from './V2ReuseProbe';

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
//
// P4 批 1：迁 @ComponentV2。判读依据（批 0.5，1370 个真机复用样本）：
// aboutToRecycle/aboutToReuse 都触发；aboutToReuse 时 @Param 已是新值、
// @Local 已重置——所以重挂订阅在 aboutToReuse 里**同步**做，V1 时代的
// nextFrameQueue 延帧兜底、reuseParam 读参、按 recycledKey 保留 path
// （issue #137 的修法）整套都不再需要：同步重播种的窗口是零帧，比"保留旧
// 值等下一帧纠正"更不闪。收益本体：@Param 引用语义替掉 @Prop 深拷贝。
// （原 struct 里的 appearanceEpoch/accent() 是死代码，build 从未引用，随迁移清掉。）
@ComponentV2
struct LightweightSenderAvatar {
  @Param senderId: number = 0;
  @Param senderIsUser: boolean = true;
  @Param initialPath: string = '';
  @Param initials: string = '?';
  @Local path: string = '';
  // 无装饰器成员复用时不重置（官方表格 + 批 0.5 实测），照旧记订阅与回收态。
  private unsub: (() => void) | null = null;
  private attachedKey: string = '';
  private recycledKey: string = '';

  private attach(senderId: number, senderIsUser: boolean, initialPath: string): void {
    const key: string = senderChannelKey(senderId, senderIsUser);
    const known: string = senderAvatarFor(key);
    if (this.unsub !== null && this.attachedKey === key) {
      // 同 key 短路：订阅不动，只重新播种（@Local 复用时被框架清空）。
      this.path = known !== '' ? known : initialPath;
      return;
    }
    this.detach();
    this.attachedKey = key;
    this.path = known !== '' ? known : initialPath;
    this.unsub = subscribeSenderAvatar(key, (path: string): void => { this.path = path; });
  }

  // 非复用路径上同一实例真的换了发送者时兜底重挂。复用路径靠 aboutToReuse
  // ——批 0.5 实测 @Monitor 在复用期完全静默（453 次换行复用 0 触发），
  // 这里永远替代不了 aboutToReuse 里的无条件重挂。
  // 第三个参数传 ''：@Param 逐个落地，senderId 变化时 initialPath 可能还是
  // 上一行的（I-2 的串行头像坑在非复用路径依旧成立），最差先显示首字母。
  @Monitor('senderId', 'senderIsUser')
  onSenderChanged(): void {
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
  aboutToDisappear(): void {
    this.detach();
  }
  aboutToRecycle(): void {
    // 记下回收时挂在谁身上——只为探针对账；detach 会把 attachedKey 归零。
    this.recycledKey = this.attachedKey;
    this.detach();
  }
  aboutToReuse(): void {
    // @Param 已是新值（批 0.5 判读 Q1b），直接同步重挂+重播种。initialPath
    // 也是新行的值，V1 时代"watch 里不敢用 initialPath"的 I-2 坑在这条路
    // 不存在。
    const nextKey: string = senderChannelKey(this.senderId, this.senderIsUser);
    // ⚠️ 临时探针（判读与删除清单见 util/avatarReuseProbe）：语义微调——
    // kept 现在表示"通道在复用当口就有现成路径"（同步播种零闪的判据）。
    probeAvatarReuse('plain', this.recycledKey, nextKey,
      senderAvatarFor(nextKey) !== '', true);
    this.recycledKey = '';
    this.attach(this.senderId, this.senderIsUser, this.initialPath);
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

// 名字行宽度的进程级记忆（P4 批 2）：V1 时代靠 @State「复用不清零」兜住
// 「名字行比正文宽」的时间层最小宽度；@Local 复用必重置，改按名字文本记忆
// ——复用当口先播种，onAreaChange 实测后回写。上限防涨（FIFO 淘汰）。
const SENDER_LABEL_WIDTHS: Map<string, number> = new Map<string, number>();
const SENDER_LABEL_WIDTH_LIMIT: number = 512;

function rememberSenderLabelW(name: string, width: number): void {
  if (name === '' || !(width > 0)) {
    return;
  }
  if (!SENDER_LABEL_WIDTHS.has(name) && SENDER_LABEL_WIDTHS.size >= SENDER_LABEL_WIDTH_LIMIT) {
    const oldest = SENDER_LABEL_WIDTHS.keys().next().value as string | undefined;
    if (oldest !== undefined) {
      SENDER_LABEL_WIDTHS.delete(oldest);
    }
  }
  SENDER_LABEL_WIDTHS.set(name, width);
}

// 按压反馈这四组样式不读任何组件状态，随批 2 迁成全局 @Styles——
// @ComponentV2 不支持成员 @Styles。
@Styles
function plainBubbleNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

@Styles
function plainBubblePressedStyle() { .opacity(0.84).scale({ x: 0.992, y: 0.992 }) }

@Styles
function plainMenuNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

@Styles
function plainMenuPressedStyle() { .opacity(0.72).scale({ x: 0.94, y: 0.94 }) }

// P4 批 2：主体迁 @ComponentV2（判读依据同批 1，见 survey 批 0.5 节）。
// 收益本体：@Prop 深拷贝 → @Param 引用（msg/memberIds/actions 都是每次复用
// 整套重灌的大头）；延帧兜底（nextFrameQueue/reuseParam）整套退役。
@ComponentV2
export struct LightweightPlainTextBubble {

  // 全局环境值走 chatEnv 镜像（批 0 建的，V2 没有 @StorageProp）。@Trace
  // 字段在 build 里读到即登记依赖，写入点双写保证跟手。
  private env: ChatEnvMirror = chatEnv;

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.env.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  @Require @Param msg: MessageEntry;
  @Param nowSec: number = 0;
  @Param chatId: number = 0;
  @Param isGroup: boolean = false;
  @Param themeBubbleOut: string = '';
  // 初值 true：行是在 LazyForEach 首批里建出来的，onVisibleAreaChange 的首帧
  // 回调常常不来，初值 false 会让玻璃层等到「滑动一下」才挂上（用户报的）。
  // 由回调负责在真正离屏时关掉——那一路是可靠的。@Local 复用时重置回 true，
  // 语义与 V1 的手工赋值一致。
  @Local onScreen: boolean = true;
  @Local glassW: number = 0;
  @Local glassH: number = 0;

  private bubbleFillColor(): ResourceColor {
    if (this.env.appearanceEpoch < 0) {
      return Color.Transparent; // 只为让 ArkUI 记下对 epoch 的依赖
    }
    if (this.msg.isOutgoing) {
      return this.themeBubbleOut !== '' ? this.themeBubbleOut : COLOR_BUBBLE_OUT;
    }
    return COLOR_BUBBLE_IN;
  }

  @Builder
  bubbleTail(outgoing: boolean) {
    if (this.glassBodyOn()) {
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
    return this.env.bubbleMaterialOn && this.onScreen && !this.env.powerSaving;
  }

  // 见 MessageBubble.glassReady()：**容器**这一层要等量到尺寸，
  // 否则没裁剪的那一帧会把 7vp 尾巴留白一起涂满，左边缘外扩。
  private glassReady(): boolean {
    return glassPaintReady(this.bubbleMaterialLive(), this.glassW, this.glassH);
  }

  // 见 MessageBubble.glassBodyOn()：玻璃结构不等测量，避免首帧退回实心档。
  private glassBodyOn(): boolean {
    return glassBodyPainted(this.bubbleMaterialLive(), this.glassW, this.glassH);
  }

  private glassBodyFallbackOn(): boolean {
    return glassBodyFallbackPainted(this.bubbleMaterialLive(), this.glassW, this.glassH);
  }

  private bubbleBg(): ResourceColor {
    if (!this.bubbleMaterialLive()) {
      return this.bubbleFillColor();
    }
    return this.glassBodyFallbackOn() ? this.glassBg() : Color.Transparent;
  }

  // 见 MessageBubble 同一处：这里只是外层轮廓就绪前的本体玻璃兜底。
  private glassBg(): ResourceColor {
    return this.glassBodyFallbackOn()
      ? overlayGlassFill('bubble', this.bubbleFillColor()) : Color.Transparent;
  }

  private glassBlur(): number {
    return this.glassBodyFallbackOn() ? overlayBackdropBlur('bubble') : 0;
  }

  private containerGlassBg(): ResourceColor {
    return this.glassReady() ? overlayGlassFill('bubble', this.bubbleFillColor()) : Color.Transparent;
  }

  private containerGlassBlur(): number {
    return this.glassReady() ? overlayBackdropBlur('bubble') : 0;
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
    if (this.glassReady()) {
      Path({ width: this.glassW, height: this.glassH })
        .commands(glassOutlineCommands(this.glassW, this.glassH, this.msg.isOutgoing,
          this.hasTail(), this.bubbleCorners()))
        .fill(Color.Transparent)
        .stroke(GLASS_OUTLINE_COLOR)
        .strokeWidth(GLASS_OUTLINE_WIDTH);
    }
  }

  @Param showUnreadDivider: boolean = false;
  @Param dividerIsResume: boolean = false;
  @Param dateLabel: string = '';
  @Param editingActive: boolean = false;
  @Param isPinnedMsg: boolean = false;
  @Param showAvatar: boolean = true;
  @Param showSenderName: boolean = true;
  @Param animateIn: boolean = false;
  @Param memberIds: number[] = [];
  // V2 里无装饰器成员是纯本地常量、禁止外部构造传参（编译错误 10905324，
  // 见 ReusableMessageBubble 的同名注释）——必须 @Param。页面持有的引用全
  // 生命周期不变，每帧只多一次恒等比较。
  @Param actions: LightweightPlainTextActions = EMPTY_ACTIONS;

  // 环境值（内容列宽/键盘高/字号/圆角/省电系……）都在 this.env 里，见顶部。

  @Local private liveSendState: string = '';
  @Local private translationStatus: TranslationStatus | null = null;
  @Local private menuShown: boolean = false;
  @Local private swipeX: number = 0;
  private bubbleW: number = 0;
  // 名字行量出来的宽度。名字行比正文宽时，时间层要拿它兜最小宽度，时间戳才落在
  // 气泡右下角、引用块才能拉到气泡边缘。V1 靠「复用不清零」留住上一行的近似值；
  // V2 的 @Local 复用必重置，改为按名字文本进程级记忆（见 SENDER_LABEL_WIDTHS），
  // 复用当口播种，比 V1 的近似更准（同名即同宽，V1 拿的是上一行随机名字的宽）。
  @Local private senderLabelW: number = 0;
  private menuOffsetX: number = 0;
  private gestureClaimed: boolean = false;
  private unsubSend: (() => void) | null = null;
  private unsubTranslation: (() => void) | null = null;

  // 订阅当前挂在哪条消息上。发送状态按 rowId 订阅、翻译态按 message.id 订阅，
  // 所以 key 要把两者都算进去。用途同头像：同 key 短路 + 按 key 自愈。
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

  private detachChannels(): void {
    if (this.unsubSend !== null) { this.unsubSend(); this.unsubSend = null; }
    if (this.unsubTranslation !== null) {
      this.unsubTranslation();
      this.unsubTranslation = null;
    }
    this.attachedKey = '';
  }

  // 只剩无装饰器成员要手工归零：官方表格明确它们复用时**不重置**。
  // @Local（menuShown/swipeX/通道值/玻璃尺寸/onScreen）由框架在 aboutToReuse
  // 之前统一重置（批 0.5 实测 1370/1370）。
  private resetTransient(): void {
    this.bubbleW = 0;
    this.menuOffsetX = 0;
    this.gestureClaimed = false;
  }

  aboutToAppear(): void {
    probeHit('message.plain.mount');
    this.senderLabelW = SENDER_LABEL_WIDTHS.get(this.msg.senderName) ?? 0;
    this.attachChannels(this.msg);
  }
  aboutToDisappear(): void {
    this.detachChannels();
  }
  aboutToRecycle(): void {
    probeHit('message.plain.recycle');
    this.detachChannels();
    this.resetTransient();
  }
  aboutToReuse(): void {
    probeHit('message.plain.reuse');
    // @Param 已是新值、@Local 已重置（批 0.5 判读 Q1b/Q2）：同步重挂+重播种，
    // V1 时代的 reuseParam 读参和 nextFrameQueue 延帧兜底整套退役。
    this.resetTransient();
    this.senderLabelW = SENDER_LABEL_WIDTHS.get(this.msg.senderName) ?? 0;
    this.attachChannels(this.msg);
  }

  // 非复用路径上同一实例换消息时兜底重挂；复用路径靠 aboutToReuse（@Monitor
  // 复用期静默，批 0.5 实测 0 触发）。
  @Monitor('msg')
  onMessageChanged(): void { this.attachChannels(this.msg); }

  private bubbleMaxW(): number { return bubbleMaxWidth(this.env.chatContentWidth); }
  private inlineMaxW(): number { return this.bubbleMaxW() - 16; }
  private runRadius(): number { return Math.min(this.env.bubbleRadius, 7); }
  private tailRadius(): number { return Math.min(this.env.bubbleRadius, 2); }
  private hasTail(): boolean { return this.showAvatar; }
  private rowTopPadding(): number { return this.showSenderName ? 3 : 1; }
  private rowBottomPadding(): number { return this.showAvatar ? 3 : 1; }
  private effectDuration(ms: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), ms);
  }
  private reactionDuration(ms: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.reactionEffects && this.env.animatedEmoji &&
        this.env.emojiReactions && !this.env.powerSaving,
      scrollActiveNow(), ms);
  }

  private bubbleCorners(): BorderRadiuses {
    return {
      topLeft: this.msg.isOutgoing ? this.env.bubbleRadius :
        (this.showSenderName ? this.env.bubbleRadius : this.runRadius()),
      topRight: this.msg.isOutgoing ?
        (this.showSenderName ? this.env.bubbleRadius : this.runRadius()) : this.env.bubbleRadius,
      bottomLeft: this.msg.isOutgoing ? this.env.bubbleRadius :
        (this.showAvatar ? this.tailRadius() : this.runRadius()),
      bottomRight: this.msg.isOutgoing ?
        (this.showAvatar ? this.tailRadius() : this.runRadius()) : this.env.bubbleRadius
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
    const policy: MessageGesturePolicy = messageGesturePolicy(this.env.gestureScheme);
    // 诊断（issue #114）：和 MessageBubble 那条 [Menu114] 对照。报告人 1.4.2 的日志
    // 里一条菜单相关的行都没有，正是因为长按落在本组件、而本组件什么都不记。
    logW(`[Menu114] longPress(plain) kbd=${Math.round(this.env.keyboardHeightVp)}`
      + ` winH=${Math.round(this.env.screenHeightVp)}`
      + ` compact=${menuPreviewCompact(this.env.keyboardHeightVp, this.env.screenHeightVp)}`);
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
      duration: this.env.powerSaving || this.env.reduceAnim ? 0 : 180,
      curve: Curve.EaseOut
    }, (): void => { this.swipeX = 0; });
    if (reply) { this.actions.onReplyTo(this.msg.id); }
  }

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
          LoadingProgress().width(12).height(12).color(COLOR_ICON_SECONDARY);
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

  private senderLabelShown(): boolean {
    return this.isGroup && !this.msg.isOutgoing && this.msg.senderName !== '' && this.showSenderName;
  }

  // 与 MessageBubble.measuredTimeLayerWidth 同一策略；轻量气泡只有名字行这一个
  // 可能比正文宽的兄弟（没有转发标签、没有评论行）。
  private measuredTimeLayerWidth(): number {
    return timeLayerMinWidth(this.inlineMaxW(), {
      forwardShown: false, forwardW: 0,
      senderShown: this.senderLabelShown(), senderW: this.senderLabelW,
      commentsShown: false, commentsW: 0
    });
  }

  @Builder
  body() {
    // minWidth 挂在这个 Column 上（而不是只挂 Stack）：Stack 的 BottomEnd 会作用到
    // 每个孩子，Column 比 Stack 窄时会被一起推到右边、压在时间戳上。
    Column() {
      if (this.msg.replyToMessageId !== 0) { this.replyQuote(); }
      Text() {
        Span(this.msg.text).fontColor(bubbleTextFor(this.msg.isOutgoing));
        if (this.translationStatus === null) {
          Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
        }
      }
      .fontSize(this.env.msgTextSize).lineHeight(this.env.msgTextSize * 1.34)
      .wordBreak(WordBreak.BREAK_WORD)
      // minWidth 也挂在这个 Text 上：Column 给子节点做 Stretch 是按最宽的孩子量的，
      // Column 自己的 minWidth 钳位发生在那之后——只挂 Column 时引用块拉不到边
      // （真机看到时间到了右边缘、引用块没跟上）。Text 是最宽的孩子，它够宽
      // Column 才够宽，引用块的 alignSelf(Stretch) 才有得伸。
      .constraintSize({ minWidth: this.measuredTimeLayerWidth(), maxWidth: this.inlineMaxW() });
      this.translationState();
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ minWidth: this.measuredTimeLayerWidth() });
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
  messageReactionMenuItem() {
    Row({ space: 2 }) {
      ForEach(QUICK_REACTIONS, (emoji: string) => {
        Row() { Text(emoji).fontSize(23); }
          .width(32).height(34).borderRadius(17).justifyContent(FlexAlign.Center)
          .stateStyles({ normal: plainMenuNormalStyle, pressed: plainMenuPressedStyle })
          .animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
          .onClick((): void => { this.actions.onSetReaction(this.msg.id, emoji, false); })
          .gesture(LongPressGesture().onAction((): void => {
            this.actions.onSetDefaultReaction(emoji);
          }));
      }, (emoji: string): string => emoji);
      Blank();
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(15).fontColor([COLOR_ICON_SECONDARY]);
      }
      .width(30).height(30).borderRadius(15).backgroundColor('#0000000F')
      .justifyContent(FlexAlign.Center)
      .stateStyles({ normal: plainMenuNormalStyle, pressed: plainMenuPressedStyle })
      .onClick((): void => { this.actions.onOpenReactions(this.msg.id); });
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  contextMenu() {
    Menu() {
      MenuItem(this.messageReactionMenuItem);
      if (this.msg.isOutgoing && this.nowSec - this.msg.date < 172800) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
          content: $r('app.string.edit')
        }).onClick((): void => { this.actions.onEditMsg(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus_square_on_square')),
        content: $r('app.string.mb_copy_text')
      }).onClick((): void => { this.actions.onCopyText(this.msg.id); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.translate')),
        content: $r('app.string.mb_translate')
      }).onClick((): void => { this.actions.onTranslateMsg(this.msg.id); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_turn_up_right')),
        content: $r('app.string.mb_forward')
      }).onClick((): void => { this.actions.onForwardMessages(this.memberIds); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bookmark')),
        content: $r('app.string.mb_save_to_saved')
      }).onClick((): void => { this.actions.onSaveMessages(this.memberIds); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.repeat')),
        content: $r('app.string.mb_repeat')
      }).onClick((): void => { this.actions.onRepeatMessages(this.memberIds); });
      if (this.isGroup && this.msg.senderIsUser && this.msg.senderId > 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person')),
          content: $r('app.string.mb_view_history')
        }).onClick((): void => { this.actions.onViewSenderHistory(this.msg.senderId); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pin')),
        content: this.isPinnedMsg ? $r('app.string.ft_unpin') : $r('app.string.ft_pin')
      }).onClick((): void => { this.actions.onPinMsg(this.msg.id, this.isPinnedMsg); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.exclamationmark_circle')).fontColor([Color.Red]),
        content: $r('app.string.mb_report')
      }).onClick((): void => { this.actions.onReportMsg(this.msg.id); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
        content: $r('app.string.mb_select')
      }).onClick((): void => { this.actions.onSelectMessages(this.memberIds); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([Color.Red]),
        content: $r('app.string.delete')
      }).onClick((): void => { this.actions.onDeleteMsg(this.msg.id); });
    }
    // 和完整气泡保持同宽，避免表情行的 100% 宽度把菜单撑到屏幕边缘。
    .width(262)
  }

  @Builder
  unreadDivider() {
    Row() {
      Divider()
        .layoutWeight(1)
        .strokeWidth(1)
        .color(COLOR_TEXT_SECONDARY)
        .opacity(0.55);
      Text(this.dividerIsResume
        ? $r('app.string.mb_last_viewed_position') : $r('app.string.mb_unread'))
        .fontSize(13)
        .fontColor(this.accent())
        .fontWeight(FontWeight.Medium)
        .margin({ left: 10, right: 10 });
      Divider()
        .layoutWeight(1)
        .strokeWidth(1)
        .color(COLOR_TEXT_SECONDARY)
        .opacity(0.55);
    }
    .width('100%')
    .height(26)
    .padding({ left: 12, right: 12, bottom: 4 })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center);
  }

  build() {
    Column() {
      // ⚠️ 临时探针（P4 批 0.5，判读完删）：零尺寸 V2 子组件，采集复用时序。
      // 删除清单见 V2ReuseProbe.ets 顶部。
      V2ReuseProbe({ rowTag: this.msg.rowId });
      if (this.dateLabel !== '') {
        Row() {
          Text(this.dateLabel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .fontWeight(FontWeight.Medium).backgroundColor($r('app.color.system_pill'))
            .borderRadius(11).padding({ left: 10, right: 10, top: 3, bottom: 3 });
        }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 5, bottom: 3 });
      }
      if (this.showUnreadDivider) {
        this.unreadDivider();
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
            if (this.senderLabelShown()) {
              Row({ space: 5 }) {
                Text(this.msg.senderName).fontSize(14).fontColor(this.senderColor())
                  .fontWeight(FontWeight.Medium).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1);
                SenderRoleTag({
                  chatId: this.chatId, senderId: this.msg.senderId,
                  presetTag: this.msg.senderTag
                });
              }
              .margin({ bottom: 2 }).alignItems(VerticalAlign.Center)
              .onAreaChange((_old: Area, area: Area): void => {
                this.senderLabelW = area.width as number;
                rememberSenderLabelW(this.msg.senderName, this.senderLabelW);
              });
            }
            Stack({ alignContent: Alignment.BottomEnd }) {
              this.body();
              this.timeOverlay();
            }
            // 名字行比正文宽时时间戳停在正文末尾、够不到气泡右边缘（用户报的），
            // 拿量到的名字行宽度兜一个最小宽度。
            .constraintSize({ maxWidth: this.inlineMaxW(), minWidth: this.measuredTimeLayerWidth() });
          }
          .alignItems(HorizontalAlign.Start)
          // 与 MessageBubble 同一策略、同一理由（见那边的长注释）：气泡根节点上
          // 不挂常驻 .animation()，按下态直接切换。真机 trace 已证明换位置留不住
          // 动画边界，只有节点上完全没有常驻动画，普通数据更新才不会进入动画
          // 上下文、连带整张消息 List 的重测。两支气泡必须同改。
          .stateStyles({ normal: plainBubbleNormalStyle, pressed: plainBubblePressedStyle })
          .constraintSize({ maxWidth: this.bubbleMaxW() })
          .backgroundColor(this.bubbleBg())
          .backdropBlur(this.glassBlur())
          .onVisibleAreaChange([0, 0.01], (visible: boolean): void => {
            this.onScreen = visible;
          })
          .borderRadius(this.bubbleCorners()).padding(8)
          .shadow({ radius: this.glassBodyOn() ? 0 : 2, color: '#14000000', offsetX: 0, offsetY: 1 })
          .onAreaChange((_old: Area, area: Area): void => { this.bubbleW = area.width as number; })
          .parallelGesture(LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
            .onAction((event: GestureEvent): void => { this.onLongPress(event); }))
          .onClick((event: ClickEvent): void => {
            if (!this.gestureClaimed && messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) {
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
          // 见 MessageBubble 同一处：容器跨着 7vp 留白，必须等量到尺寸才上色；
          // 完整态本体同步退为透明，避免两层玻璃在同一区域重复合成。
          .backgroundColor(this.containerGlassBg())
          .backdropBlur(this.containerGlassBlur())
          // 见 MessageBubble 同一处：材质的边框沿本节点 border-box 画、吃 borderRadius，
          // 不设圆角就是个直角框，裁剪之后剩下半条亮线。
          .borderRadius(this.glassRadius())
          .background(this.glassOutline(), { align: Alignment.TopStart })
              .attributeModifier(bubbleGlassModifier(this.glassReady(), this.glassW, this.glassH,
            this.msg.isOutgoing, this.hasTail(), this.bubbleCorners(),
            this.env.bubbleMaterialOn ? (w: number, h: number): void => {
              probeGlassMeasure('plain', this.msg.id, w, h);
              this.glassW = w;
              this.glassH = h;
            } : null))
        }
        .alignItems(VerticalAlign.Bottom)
        .bindContextMenu(this.menuShown, this.contextMenu(), {
          offset: { x: this.menuOffsetX, y: 0 },
          preview: menuPreviewCompact(this.env.keyboardHeightVp, this.env.screenHeightVp)
            ? MenuPreviewMode.NONE : MenuPreviewMode.IMAGE,
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
