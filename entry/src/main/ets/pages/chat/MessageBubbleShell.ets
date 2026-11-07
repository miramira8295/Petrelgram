import { ReactionTransitions } from '../../util/reactionTransitions';
import { TextMeasureCache, textMeasureEnvironment, sharedTextMeasurements } from '../../util/textMeasureCache';
import { DissolveDeleteEffect } from '../common/DissolveDeleteEffect';
import { MessageDragGesture } from '../../util/messageDragGesture';
import { configureMessageDrag } from '../../services/MessageDragSource';
import { messageDragType } from '../../util/messageDrag';
import { tableScrollTouched } from '../../util/tableTouchChannel';
import { JUMP_FOCUS_BRIGHTNESS, JUMP_FOCUS_SCALE } from '../../util/bubbleFocusChannel';
import { pillSegments, PillSegment } from '../../util/systemPillLinks';
import { isFavoriteSticker } from '../../store/FavoriteStickers';
import { stickerSourceFileId } from '../../util/stickerSetItems';
import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { MessageMenuTransitions } from '../../util/messageMenuTransitions';
import { isEdgeSwipeStart, SWIPE_REPLY_MAX, SWIPE_REPLY_TRIGGER, SWIPE_SELECT_MAX, SWIPE_SELECT_TRIGGER } from '../../util/swipeReplyGesture';
import { pasteboard, deviceInfo } from '@kit.BasicServicesKit';
import { MessageEntry, ReactionInfo, InlineBtn } from '../../store/MessageEntry';
import { slotKey } from './playSlot';
import { TdObject } from '../../tdkit/TdTypes';
import { getAccentColorStore, getTdClient, getUserStore } from '../../tdkit/Globals';
import { senderHasAnimatedPhoto } from '../../services/PhotoAnimationFetch';
import { SenderAnimatedLayer } from './SenderAnimatedLayer';
import { CachedImage } from '../common/CachedImage';
import { CachedImageSpec } from '../../util/cachedImageSpec';
import { BubbleCornerCache, SenderAvatarSpec, SenderAvatarSpecCache } from '../../util/messageBubblePresentation';
import { cornerPx, senderLeadInset } from '../../util/bubbleCornerInset';
import { BubbleGlassGeometry } from './BubbleGlassGeometry';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { rememberLabelWidth, recallLabelWidth } from '../../util/labelWidthMemory';
import { SenderRoleTag } from './SenderRoleTag';
import { BUBBLE_AVATAR_GAP_VP, BUBBLE_AVATAR_GUTTER_VP, BUBBLE_ROW_SIDE_VP, bubbleMaxWidth, hitSenderAvatarColumn } from '../../util/mediaBox';
import { formatClockTime } from '../../util/formatTime';
import { isUnformattedPlainText, messageUrls, parseFormattedText } from '../../util/richText';
import { inlineButtonKey, inlineButtonRowKey } from '../../util/inlineButtonKey';
import { reactionKeyFrom } from '../../util/reactions';
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_OUT, COLOR_BUBBLE_IN, AVATAR_PALETTE, botButtonBg, accentSoft, bubbleTextFor } from '../../util/theme';
import { senderAvatarFor, senderChannelKey, subscribeSenderAvatar } from '../../util/senderAvatarChannel';
import { plural, str } from '../../util/strings';
import { sendStateFor, subscribeSendState } from '../../util/sendStateChannel';
import { TranslationStatus, subscribeTranslationStatus, translationStatusFor } from '../../util/translationChannel';
import { subscribeViewCount, viewCountLabelFor, viewsReserve } from '../../util/viewCountChannel';
import { pinForTranslationGrowth } from '../../util/translationGrowthPin';
import { containerBlur, overlayMaterial } from '../../util/overlayMaterial';
import { GLASS_OUTLINE_COLOR, GLASS_OUTLINE_WIDTH, TAIL_H, TAIL_W, bubbleGlassModifier, glassOutlineCommands, SolidBubbleShadowCache } from '../../util/bubbleTail';
import { glassBodyFallbackPainted, glassBodyPainted, glassPaintReady, tailShapeCommands } from '../../util/bubbleGlassPath';
import { timeLayerMinWidth } from '../../util/timeLayerWidth';
import { MessageGesturePolicy, messageGesturePolicy } from '../../util/messageGestures';
import { CHIP_ICON_VP, reactionChipWidth, reactionsRowMaxWidth, reactionsRowWidth, timeOverlayWidth } from '../../util/reactionsWidth';
import { logW } from '../../util/log';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { canBackgroundCache } from '../../util/backgroundCacheEligibility';
import { editableCached, ensureEditable } from '../../util/messageEditable';
import { deletableCached, ensureDeletable } from '../../util/messageDeletable';
import { replyThumbSrc } from '../../util/replyThumb';
import { DiceEndFrame } from './DiceEndFrame';
import { menuPreviewCompact } from '../../util/menuPreview';
import { bubbleGlassBlurStyle, bubbleGlassFill } from '../../util/surfaceGlass';
import { firstFinger } from '../../util/firstFinger';

// 气泡玻璃自绘：明确不指望 systemMaterial（系统已收回组件级材质），
// 和输入栏同一对函数，受「界面模糊质感」开关与档位控制。

// SDK capability is fixed for this process. Read lazily once, not through
// the deviceInfo native getter on every local text-measure cache miss.
let sharedTextMeasurementSupported: boolean | undefined = undefined;

const REACTORS_ARROW_PAD_H: number = 7;
const REACTORS_ARROW_ICON_VP: number = 16;
const REACTORS_ARROW_MARGIN_R: number = 4;
const REPLY_QUOTE_WIDTH_RATIO: number = 0.76;
const REPLY_QUOTE_LINE_H: number = 16;
const REPLY_THUMB_SIZE: number = 32;
const REPLY_THUMB_GAP: number = 6;
const QUICK_REACTIONS: string[] = ['❤️', '👍', '👎', '🔥', '🥰', '👏'];
const EDITABLE_CAPTION_TYPES: string[] = ['photo', 'video', 'file', 'audio', 'voice'];

@Styles
function msgBotButtonNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

@Styles
function msgBotButtonPressedStyle() { .opacity(0.72).scale({ x: 0.975, y: 0.975 }) }

@Styles
function msgMenuActionNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

@Styles
function msgMenuActionPressedStyle() { .opacity(0.72).scale({ x: 0.97, y: 0.94 }) }
class PressDimModifier implements AttributeModifier<CommonAttribute> {
  private dimOpacity: number;
  private dimScale: number;
  private active: boolean;
  private wholeShell: boolean;

  constructor(dimOpacity: number, dimScale: number, active: boolean, wholeShell: boolean = false) {
    this.dimOpacity = dimOpacity;
    this.dimScale = dimScale;
    this.active = active;
    this.wholeShell = wholeShell;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (this.wholeShell) { instance.renderGroup(false); }
    instance.opacity(1);
    instance.scale({ x: 1, y: 1 });
  }

  applyPressedAttribute(instance: CommonAttribute): void {
    const on: boolean = this.active && !tableScrollTouched();
    // 只在按压期合成，防止主体/尾角的重叠像素各自叠加透明度。
    if (this.wholeShell) { instance.renderGroup(on); }
    instance.opacity(on ? this.dimOpacity : 1);
    const s: number = on ? this.dimScale : 1;
    instance.scale({ x: s, y: s });
  }
}

const BUBBLE_PRESS_DIM: PressDimModifier = new PressDimModifier(0.84, 0.992, true, true);
const BUBBLE_PRESS_NONE: PressDimModifier = new PressDimModifier(0.84, 0.992, false, true);
const SYSTEM_PILL_PRESS_DIM: PressDimModifier = new PressDimModifier(0.72, 0.985, true);
const SYSTEM_PILL_PRESS_NONE: PressDimModifier = new PressDimModifier(0.72, 0.985, false);

// P4 批 3b：迁 @ComponentV2，配方与 LightweightSenderAvatar（批 1）完全一致，
// 判读依据见 2026-09-02-p4-bubble-v2-survey.md 批 0.5 节（1370 真机样本）：
// aboutToReuse 时 @Param 已是新值、@Local 已重置、@Monitor 复用期静默——
// 同步重挂订阅，V1 的 nextFrameQueue 延帧兜底/reuseParam 读参/按 key 保留
// path（#137 修法）整套退役。批 2 已在真机验证过同款（avatar.plain.reuse
// 满速 + kept=true 连串）。原 struct 的 appearanceEpoch/accent() 是从未被
// build 引用的死代码，随迁移清掉。
// 占位用的内边距（第五刀，2026-09-14，与 LightweightPlainTextBubble 第四刀同一做法）：
// 原来这两个位置各垫一个定宽空 Column，每行白付一个节点、一层测量和一份复用时要重跑的
// 更新。换成所在容器的内边距，占的宽度逐像素不变。
// 没有尾巴时给尾巴留的位，见 bubbleTailGutter / tailGutterPadding。
const TAIL_GUTTER_VP: number = 7;
const TAIL_GUTTER_LEFT: Padding = { left: TAIL_GUTTER_VP };
const TAIL_GUTTER_RIGHT: Padding = { right: TAIL_GUTTER_VP };
// 群聊来信不显示头像时给头像留的 44vp 位（头像 38 + 右边距 6），见 avatarGutterPadding。
const AVATAR_GUTTER: Padding = { left: BUBBLE_AVATAR_GUTTER_VP };
// 行边距与气泡最大宽同源，见 util/mediaBox.BUBBLE_ROW_SIDE_VP。
const NO_GUTTER: Padding = {};
const PURE_MEDIA_CORNER_RADIUS: BorderRadiuses = {
  topLeft: 15, topRight: 15, bottomLeft: 15, bottomRight: 15
};
const MEDIA_TIME_PADDING: Padding = { left: 6, right: 6, top: 2, bottom: 2 };
const PLAIN_TIME_PADDING: Padding = { left: 0 };

interface SenderAvatarState {
  path: string;
  animated: boolean;
}
const EMPTY_SENDER_AVATAR_STATE: SenderAvatarState = { path: '', animated: false };

@ComponentV2
struct LiveSenderAvatar {
  // One atomic input keeps sender identity/path together and resets one Param
  // per reuse. The caller keeps the 38vp sender / 22vp comment policies.
  @Require @Param spec: SenderAvatarSpec;
  @Local private avatarState: SenderAvatarState = EMPTY_SENDER_AVATAR_STATE;
  private get path(): string { return this.avatarState.path; }
  private get animated(): boolean { return this.avatarState.animated; }

  private setAvatarState(path: string, animated: boolean): void {
    if (this.path !== path || this.animated !== animated) {
      this.avatarState = { path, animated };
    }
  }
  // 无装饰器成员复用时不重置（官方表格 + 批 0.5 实测），照旧记订阅与回收态。
  private unsubAvatar: (() => void) | null = null;
  private attachedAvatarKey: string = '';

  private attachAvatarChannel(senderId: number, senderIsUser: boolean, initialPath: string): void {
    const key: string = senderChannelKey(senderId, senderIsUser);
    const known: string = senderAvatarFor(key);
    this.setAvatarState(known !== '' ? known : initialPath,
      this.spec.animate && senderHasAnimatedPhoto(senderId, senderIsUser));
    if (this.unsubAvatar !== null && this.attachedAvatarKey === key) { return; }
    this.detachAvatarChannel();
    this.attachedAvatarKey = key;
    this.unsubAvatar = subscribeSenderAvatar(key, (path: string): void => {
      if (this.attachedAvatarKey !== key) { return; }
      const spec = this.spec;
      this.setAvatarState(path, spec.animate && senderHasAnimatedPhoto(spec.senderId, spec.senderIsUser));
    });
  }

  @Monitor('spec')
  onSpecChanged(): void {
    const spec = this.spec;
    if (this.unsubAvatar === null ||
      this.attachedAvatarKey !== senderChannelKey(spec.senderId, spec.senderIsUser)) {
      this.attachAvatarChannel(spec.senderId, spec.senderIsUser, spec.initialPath);
      return;
    }
    this.setAvatarState(this.path !== '' ? this.path : spec.initialPath,
      spec.animate && senderHasAnimatedPhoto(spec.senderId, spec.senderIsUser));
  }

  private detachAvatarChannel(): void {
    if (this.unsubAvatar !== null) {
      this.unsubAvatar();
      this.unsubAvatar = null;
    }
    this.attachedAvatarKey = '';
  }

  aboutToAppear(): void {
    const spec = this.spec;
    this.attachAvatarChannel(spec.senderId, spec.senderIsUser, spec.initialPath);
  }

  aboutToRecycle(): void {
    this.detachAvatarChannel();
  }

  aboutToReuse(): void {
    // @Param 已是新值、@Local path 已被框架重置（批 0.5 判读）：同步重挂+
    // 重播种即可。initialPath 也是新行的值，I-2 串头像坑在这条路不存在；
    // #137 的「按 key 保留 path」不再需要——同步重播种（通道现值或新行
    // initialPath）的窗口是零帧，比保留旧值更不闪。
    const spec = this.spec;
    this.attachAvatarChannel(spec.senderId, spec.senderIsUser, spec.initialPath);
  }

  aboutToDisappear(): void {
    this.detachAvatarChannel();
  }

  private preparedImageSpec: CachedImageSpec | undefined = undefined;

  private imageSpec(): CachedImageSpec {
    const size: number = this.spec.avatarSize;
    const path: string = this.path;
    const previous = this.preparedImageSpec;
    // All other fields are fixed policy or derived from size. Read live values
    // before comparing so channel updates and in-place input changes still win.
    if (previous !== undefined && previous.path === path && previous.boxWidth === size) {
      return previous;
    }
    // Preserve bounded pinning, synchronous small-avatar decoding and native
    // display. No Computed: the child expression reads the current path/size.
    const next: CachedImageSpec = {
      path: path, boxWidth: size, boxHeight: size, radius: size / 2,
      fit: ImageFit.Cover, pinBounded: true, syncSmall: true, syncDisplay: true
    };
    this.preparedImageSpec = next;
    return next;
  }

  build() {
    // One fixed subtree for initials and decoded bitmap. The old AvatarView
    // changed branches between empty/non-empty paths; under a recycled message
    // shell that both defeated reuse and accounted for 110 ms of build/destroy
    // work in the captured scroll trace.
    Stack() {
      // 底色圆和首字母合成一个 Text（背景色 + 半径圆角 = 原来的 Circle），头像少一个节点。
      // 字母只在真没头像时画；有路径但图还没到（极少数走异步的情况）就是纯色圆，
      // 色块→照片比字母→照片柔和得多——所以有图时只清空文字、不藏背景。
      Text(this.path === '' ? this.spec.initials : '')
        .width(this.spec.avatarSize).height(this.spec.avatarSize).borderRadius(this.spec.avatarSize / 2)
        .backgroundColor(AVATAR_PALETTE[Math.abs(this.spec.senderId) % AVATAR_PALETTE.length])
        .textAlign(TextAlign.Center).align(Alignment.Center)
        .fontColor(Color.White).fontSize(this.spec.avatarSize * 0.4).fontWeight(FontWeight.Medium);
      CachedImage({ spec: this.imageSpec() })
        .visibility(this.path !== '' ? Visibility.Visible : Visibility.None);
      if (this.animated) {
        SenderAnimatedLayer({
          senderId: this.spec.senderId, senderIsUser: this.spec.senderIsUser, avatarSize: this.spec.avatarSize
        });
      }
    }
    .width(this.spec.avatarSize).height(this.spec.avatarSize);
  }
}

// 壳与类型内容之间稳定的状态桥。共用通道仅在壳订阅一次，内容按需读取。
// 手势认领不参与绘制，保持普通字段，避免触摸事件触发整树更新。
@ObservedV2
export class MessageBubbleContext {
  @Trace liveSendState: string = '';
  @Trace liveViews: string = '';
  @Trace translationStatus: TranslationStatus | null = null;
  @Trace menuOffsetX: number = 0;
  @Trace msgContextMenuShown: boolean = false;
  @Trace forwardLabelW: number = 0;
  @Trace senderLabelW: number = 0;
  @Trace commentsRowW: number = 0;
  @Trace bubbleW: number = 0;
  gestureClaimed: boolean = false;

  resetInteraction(): void {
    this.gestureClaimed = false;
    if (this.menuOffsetX !== 0) { this.menuOffsetX = 0; }
    if (this.msgContextMenuShown) { this.msgContextMenuShown = false; }
  }

  recordMenuOffset(localX: number, width: number): void {
    this.menuOffsetX = width > 0 ? localX - width / 2 : 0;
  }
}

// 共用原有头像、标签/回复、材质/尾巴、时间/表态、菜单与行手势。
// body 是零参插槽，持有调用方的实时状态，不捕获带参 Builder 的旧消息快照。
@ComponentV2
export struct MessageBubbleShell {
  @Require @Param context: MessageBubbleContext;
  @BuilderParam body: () => void;
  private env: ChatEnvMirror = chatEnv;

  @Require @Param msg: MessageEntry;

  private unsubSendState: (() => void) | null = null;

  private attachedRowId: number = 0;
  private attachedMessageId: number = 0;


  // 玻璃层几何缓存：可观测对象、属性级依赖（见 BubbleGlassGeometry）。
  // 背景属性直接读 geo.w / geo.h，测量完成只重算这几个属性。
  private geo: BubbleGlassGeometry = new BubbleGlassGeometry();

  private measuredGlassW: number = 0;

  private measuredGlassH: number = 0;

  private reactionTransitions: ReactionTransitions = new ReactionTransitions();

  private shadowShapeCache: SolidBubbleShadowCache = new SolidBubbleShadowCache();

  @Param nowSec: number = 0;

  @Param jumpFocus: number = 0;

  @Param leaving: number = 0;

  @Require @Param group: AlbumGroup;

  @Require @Param data: MessageBubbleRenderData;

  @Require @Param actions: MessageBubbleActions;

  private measuredBubbleW: number = 0;

  private menuFx: MessageMenuTransitions = new MessageMenuTransitions();

  private unsubTranslation: (() => void) | null = null;

  private unsubViews: (() => void) | null = null;

  private viewsAttachedId: number = 0;

  @Local private swipeReplyX: number = 0;

  private swipeFromEdge: boolean = false;

  private dragGesture: MessageDragGesture = new MessageDragGesture();

  @Local private draggingMessage: boolean = false;

  @Local private editableTick: number = 0;

  // 「能不能删」到货后触发菜单重绘，和 editableTick 同一套机制、同一个理由。
  @Local private deletableTick: number = 0;

  private textMeasureFailed: boolean = false;
  private textMeasureCache: TextMeasureCache = new TextMeasureCache();
  private rxWidthSig: string = '';

  private rxWidthCache: number = 0;

  private cornerCache: BubbleCornerCache = new BubbleCornerCache();
  private avatarSpecCache: SenderAvatarSpecCache = new SenderAvatarSpecCache();
  private commentAvatarSpecCaches: SenderAvatarSpecCache[] = [];

  private senderAvatarSpec(): SenderAvatarSpec {
    const msg = this.msg;
    return this.avatarSpecCache.prepare(msg.senderId, msg.senderIsUser, msg.senderAvatarPath,
      msg.senderInitials, 38, true);
  }

  private commentAvatarSpec(senderId: number, index: number): SenderAvatarSpec {
    const msg = this.msg;
    // Reuse cache slots by position, never by sender ID. Shrink when a later
    // message has fewer comment avatars so old senders are not retained.
    if (this.commentAvatarSpecCaches.length > msg.commentReplierIds.length) {
      this.commentAvatarSpecCaches.length = msg.commentReplierIds.length;
    }
    let cache = this.commentAvatarSpecCaches[index];
    if (cache === undefined) {
      cache = new SenderAvatarSpecCache();
      this.commentAvatarSpecCaches[index] = cache;
    }
    const paths = msg.commentReplierAvatarPaths;
    return cache.prepare(senderId, true, index < paths.length ? paths[index] : '', '?', 22, false);
  }

  private accent(): ResourceColor {
    return this.env.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  private compactMenuContext(): boolean {
    return this.context.msgContextMenuShown &&
      menuPreviewCompact(this.env.keyboardHeightVp, this.env.screenHeightVp);
  }

  private attachMessageChannels(message: MessageEntry): void {
    this.detachMessageChannels();
    // 发送状态不在行 key 里，行不会因为它重建——图标得自己订阅自己更新。
    // 与 LiveThumbImage / LiveProgressRing 同一套办法；先读通道现值，没有
    // 才用 @Prop 带来的初值（滚回历史消息时不会有新的发布）。
    const known: string = sendStateFor(message.rowId);
    this.context.liveSendState = known !== '' ? known : message.sendState;
    this.unsubSendState = subscribeSendState(message.rowId, (state: string): void => {
      this.context.liveSendState = state;
    });
    // 「翻译中 / 翻译失败」是瞬时态，不进行 key（见 translationChannel），
    // 所以行不会因为它们重建——这里自己订阅自己更新。
    this.context.translationStatus = translationStatusFor(message.id);
    this.unsubTranslation = subscribeTranslationStatus(message.id,
      (next: TranslationStatus | null): void => {
        this.context.translationStatus = next;
        // 「翻译中」一行出现/消失会改行高：贴底时同一帧钉住底部（util/translationGrowthPin）。
        pinForTranslationGrowth(this.data.chatId);
      });
    this.attachViews(message.id);
    this.attachedRowId = message.rowId;
    this.attachedMessageId = message.id;
  }

  private attachViews(messageId: number): void {
    if (this.unsubViews !== null && this.viewsAttachedId === messageId) {
      this.context.liveViews = viewCountLabelFor(this.data.chatId, messageId);
      return;
    }
    this.detachViews();
    this.viewsAttachedId = messageId;
    this.context.liveViews = viewCountLabelFor(this.data.chatId, messageId);
    this.unsubViews = subscribeViewCount(this.data.chatId, messageId,
      (label: string): void => { this.context.liveViews = label; });
  }

  private detachViews(): void {
    if (this.unsubViews !== null) {
      this.unsubViews();
      this.unsubViews = null;
    }
    this.viewsAttachedId = 0;
  }

  private detachMessageChannels(): void {
    this.detachViews();
    if (this.unsubSendState !== null) { this.unsubSendState(); this.unsubSendState = null; }
    if (this.unsubTranslation !== null) { this.unsubTranslation(); this.unsubTranslation = null; }
    this.attachedRowId = 0;
    this.attachedMessageId = 0;
  }

  private clearTransientState(): void {
    this.dragGesture.reset();
    // Context is a stable ordinary member of the content owner, so ArkUI does
    // not reset its traced fields when this child is rebound to another row.
    this.context.resetInteraction();
    if (this.draggingMessage) { this.draggingMessage = false; }
    this.swipeFromEdge = false;
    if (this.swipeReplyX !== 0) { this.swipeReplyX = 0; }
    if (this.editableTick !== 0) { this.editableTick = 0; }
    if (this.deletableTick !== 0) { this.deletableTick = 0; }
  }

  aboutToAppear(): void {
    this.context.resetInteraction();
    this.seedLabelWidths();
    this.attachMessageChannels(this.msg);
  }

  aboutToDisappear(): void { this.detachMessageChannels(); }

  aboutToRecycle(): void {
    this.detachMessageChannels();
    this.clearTransientState();
  }

  aboutToReuse(): void {
    this.clearTransientState();
    this.seedLabelWidths();
    this.context.bubbleW = this.measuredBubbleW;
    this.geo.setSize(this.measuredGlassW, this.measuredGlassH);
    this.attachMessageChannels(this.msg);
  }

  @Monitor('msg')
  onMsgPropChanged(): void {
    if (this.msg.rowId !== this.attachedRowId) {
      this.clearTransientState();
      this.seedLabelWidths();
      this.context.bubbleW = this.measuredBubbleW;
      this.attachMessageChannels(this.msg);
    } else if (this.msg.id !== this.attachedMessageId) {
      // Sending keeps rowId stable while replacing a temporary message id.
      // Translation, like views, is keyed by message id rather than rowId.
      this.attachMessageChannels(this.msg);
    }
    const known: string = sendStateFor(this.msg.rowId);
    this.context.liveSendState = known !== '' ? known : this.msg.sendState;
    this.attachViews(this.msg.id);
  }

  private bubbleMaxW(): number {
    // 只有群聊来信才有头像位；发出的消息和私聊来信按 0 算，能宽出 44vp。
    return bubbleMaxWidth(this.data.contentWidth, this.avatarReserve());
  }

  private inlineMaxW(): number {
    return this.bubbleMaxW() - 16;
  }

  // 只要是图片/视频气泡，不管有没有说明文字、转发标签，白框一律 2vp；
  // 之前只有「纯图」才 2vp，带说明的走 8vp，图片四周留出一大圈白边。
  private isMediaBubble(): boolean {
    return this.msg.contentType === 'photo' ||
      this.msg.contentType === 'video' || this.group.photoPaths.length > 1;
  }

  private isPureMediaBubble(): boolean {
    const isMedia: boolean = this.msg.contentType === 'photo' ||
      this.msg.contentType === 'video' || this.group.photoPaths.length > 1;
    if (!isMedia) {
      return false;
    }
    return this.msg.text === '' && this.msg.translatedText === '' &&
      this.group.caption === '' && this.msg.replyToMessageId === 0 &&
      this.msg.reactions.length === 0 && !this.forwardLabelShown() &&
      !this.senderLabelShown() && !this.commentsRowShown();
  }

  private hasBubbleTail(): boolean {
    return this.group.showAvatar && !this.isBareEmoji() && !this.isPureMediaBubble();
  }

  private bubbleTailGutter(): number {
    return TAIL_GUTTER_VP;
  }

  private tailGutterPadding(): Padding {
    if (this.hasBubbleTail()) {
      return NO_GUTTER;
    }
    return this.msg.isOutgoing ? TAIL_GUTTER_RIGHT : TAIL_GUTTER_LEFT;
  }

  private avatarGutterPadding(): Padding {
    return this.data.isGroup && !this.msg.isOutgoing && !this.group.showAvatar
      ? AVATAR_GUTTER : NO_GUTTER;
  }

  private avatarReserve(): number {
    return this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
  }

  private rowTopPadding(): number {
    return this.group.showSenderName ? 3 : 1;
  }

  private rowBottomPadding(): number {
    return this.group.showAvatar ? 3 : 1;
  }

  private effectDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }

  private reactionDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.reactionEffects &&
        this.env.animatedEmoji && this.env.emojiReactions && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }

  private swipeReplyDuration(duration: number): number {
    return this.env.powerSaving || this.env.reduceAnim ? 0 : duration;
  }

  private recordMenuOffset(localX: number, width: number): void {
    this.context.recordMenuOffset(localX, width);
  }

  // 整行热区用：点在气泡左右空白处时，x 是相对**整行**的，而菜单锚点是气泡。
  // 这里把 x 夹进气泡宽度再套原公式，空白区域点得再偏，菜单也不会飞到隔壁行。
  private recordRowMenuOffset(localX: number): void {
    const w: number = this.measuredBubbleW > 0 ? this.measuredBubbleW : 1;
    const x: number = Math.max(0, Math.min(localX, w));
    this.recordMenuOffset(x, w);
  }

  private canDragMessage(): boolean { return !this.data.selectionActive && !this.data.editingActive && this.group.memberIds.length === 1 && this.msg.id > 0 && messageDragType(this.msg.contentType) !== ''; }

  private onDragSourceTouch(event: TouchEvent): void {
    if (!this.canDragMessage()) { return; }
    const touch = event.touches[0] ?? event.changedTouches[0];
    const now = Date.now();
    if (event.type === TouchType.Down && touch !== undefined) {
      this.dragGesture.begin(touch.windowX, touch.windowY, now);
      this.recordMenuOffset(touch.x, Number(event.target.area.width));
    } else if (event.type === TouchType.Move && touch !== undefined) {
      this.dragGesture.move(touch.windowX, touch.windowY, now);
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (touch !== undefined) { this.dragGesture.move(touch.windowX, touch.windowY, now); }
      if (this.dragGesture.end(now, event.type === TouchType.Cancel)) { this.onLongPress(); }
    }
  }

  private onLongPress(event?: GestureEvent): void {
    if (this.draggingMessage) { return; }
    // 手指压在气泡里那张可横滑的表格上：不弹菜单、也不做"抬起气泡"那套预览
    // 动效（用户 2026-09-22：「滑动会响应气泡长按的视觉效果」）。按住不动 500ms
    // 再拖，长按先于拖动成立，于是滚表格的同时菜单弹了出来。
    // 标记只在表格**真的可滚**时才打，普通表格上长按照常出菜单。
    if (tableScrollTouched()) {
      return;
    }
    // issue #114 诊断：小窗 + 键盘展开时长按调不出菜单。手势有没有到、走的哪一
    // 支、当时窗口和键盘多高、预览模式取哪种——报告人导日志就能对上。
    logW(`[Menu114] longPress id=${this.msg.id} scheme=${this.env.gestureScheme}`
      + ` kbd=${Math.round(this.env.keyboardHeightVp)} winH=${Math.round(this.env.screenHeightVp)}`
      + ` compact=${this.compactMenuContext()} liveVideo=${this.hasLiveVideoSurface()}`
      + ` shown=${this.context.msgContextMenuShown}`);
    const finger: FingerInfo | undefined = event === undefined ? undefined : firstFinger(event.fingerList);
    if (finger !== undefined && event !== undefined) {
      this.recordMenuOffset(finger.localX, Number(event.target.area.width));
    }
    this.context.gestureClaimed = true;
    // 已在多选：长按就是"选这一行"（相册 = 整组媒体），不弹菜单、也不重进多选。
    // 单条行在多选态下气泡整个不收触摸（ChatPage 行外层 BLOCK_DESCENDANTS），
    // 能走到这里的是相册行——它为了逐格勾选放开了命中。
    if (this.data.selectionActive) {
      this.actions.onSelectMessages(this.group.memberIds);
      return;
    }
    this.askEditable();
    this.askDeletable();
    const policy: MessageGesturePolicy = messageGesturePolicy(this.env.gestureScheme);
    if (policy.longPressOpensMenu) {
      this.context.msgContextMenuShown = true;
      return;
    }
    if (policy.longPressSelects) {
      this.actions.onSelectMessages(this.group.memberIds);
    }
  }

  private swipeGestureEligible(): boolean {
    // 手指压在气泡里那张可横滑的表格上时，整行不跟手（用户 2026-09-22：
    // 「横向滑动会和气泡一起滑动」）。整行这条是 parallelGesture，按定义就要
    // 和子孙手势并行跑，子节点那边没有任何属性能让它让路——只能反过来由表格
    // 在按下时打个标记，这里读。详见 util/tableTouchChannel。
    if (this.draggingMessage || (this.canDragMessage() && this.dragGesture.prefersDrag(Date.now())) || tableScrollTouched()) {
      return false;
    }
    return !this.swipeFromEdge && !this.data.editingActive
      && this.msg.contentType !== 'system' && this.msg.contentType !== 'hidden';
  }

  private swipeReplyAllowed(): boolean {
    return this.swipeGestureEligible() && this.data.canReply;
  }

  private onSwipeReplyUpdate(offsetX: number): void {
    if (!this.swipeGestureEligible()) {
      return;
    }
    // 两个方向都跟手：向左（负）回复，向右（正）进多选，各自钳到自己的上限。
    // 不能回复的会话（只读频道等）把左边界收到 0：右滑照常，左滑不跟手。
    const lowerBound: number = this.data.canReply ? SWIPE_REPLY_MAX : 0;
    this.swipeReplyX = Math.max(lowerBound, Math.min(SWIPE_SELECT_MAX, offsetX));
    // 真的滑动起来了才算认领。PanGesture 的 distance 已经是 8，这里再确认
    // 一次位移，避免"手指抖了一下"就把一次正常点击吃掉。
    if (this.swipeReplyX !== 0) {
      this.context.gestureClaimed = true;
    }
  }

  private onSwipeReplyEnd(): void {
    const reply: boolean = this.swipeReplyAllowed() &&
      this.swipeReplyX <= SWIPE_REPLY_TRIGGER;
    // 右滑进多选，动作与长按选择完全一致（同一个 onSelectMessages 入口，
    // 传整组 memberIds——相册要整组一起选，和长按那条保持一致）。
    // 判据是 swipeGestureEligible 而不是 swipeReplyAllowed：多选与发言权无关。
    const select: boolean = this.swipeGestureEligible() &&
      this.swipeReplyX >= SWIPE_SELECT_TRIGGER;
    animateTo({ duration: this.swipeReplyDuration(180), curve: Curve.EaseOut }, (): void => {
      this.swipeReplyX = 0;
    });
    if (reply) {
      this.actions.onReplyTo(this.msg.id);
    } else if (select) {
      this.actions.onSelectMessages(this.group.memberIds);
    }
  }

  private suppressBubblePressDim(): boolean {
    return this.hasInlineLink() || this.hasLinkPreview() || this.msg.contentType === 'voice' ||
      this.msg.contentType === 'audio' || this.msg.contentType === 'file';
  }

  private isPlaySlot(albumIndex: number): boolean {
    return this.data.playSlotKey !== '' && !this.msg.isAnimation &&
      this.data.playSlotKey === slotKey(this.msg.id, albumIndex);
  }

  private hasLinkPreview(): boolean {
    return this.msg.linkUrl !== '' || this.msg.linkSiteName !== '' ||
      this.msg.linkTitle !== '' || this.msg.linkDescription !== '' ||
      this.msg.linkPhotoFileId !== 0;
  }

  private albumMemberIdAt(index: number): number {
    return this.group.memberIds[index] ?? 0;
  }

  private albumVideoFileIdAt(index: number): number {
    return this.group.videoFileIds[index] ?? 0;
  }

  private isAlbumCellPlaySlot(index: number): boolean {
    return this.data.playSlotKey !== '' && !this.msg.isAnimation &&
      this.data.playSlotKey === slotKey(this.albumMemberIdAt(index), index);
  }

  private senderColor(): ResourceColor {
    const accentId = this.msg.senderId > 0
      ? getUserStore().accentColorId(this.msg.senderId) : -1;
    if (accentId >= 0) {
      const hex = getAccentColorStore().nameColorHex(accentId, false);
      if (hex !== '') { return hex; }
    }
    return AVATAR_PALETTE[Math.abs(this.msg.senderId) % AVATAR_PALETTE.length];
  }

  @Builder
  statusIcon() {
    // Keep one stable node tree across sending/sent/read/failed. A send-state
    // update is delivered through a side channel without changing the list row
    // key; conditionally replacing SymbolGlyph with Row made a pooled plain-text
    // row enter the cache with a different structure than its reuseId promised.
    Row() {
      SymbolGlyph($r(this.context.liveSendState === 'sending'
        ? 'sys.symbol.clock'
        : (this.context.liveSendState === 'failed'
          ? 'sys.symbol.exclamationmark_circle' : 'sys.symbol.checkmark')))
        .fontSize(12)
        .fontColor([this.context.liveSendState === 'failed' ? Color.Red
          : (this.timeOnMedia() ? Color.White
            : (this.context.liveSendState === 'read' ? this.accent() : COLOR_ICON_SECONDARY))])
        .visibility(this.context.liveSendState === 'none' || this.context.liveSendState === ''
          ? Visibility.None : Visibility.Visible);
      // The second, overlapped check is present in every state and only shown
      // for read receipts, so reuse never creates or destroys it.
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(12).fontColor([this.timeOnMedia() ? Color.White : this.accent()]).margin({ left: -8 })
        .visibility(this.context.liveSendState === 'read' ? Visibility.Visible : Visibility.None);
    }
  }

  private messageTimeText(): string {
    return formatClockTime(this.msg.date);
  }

  private timeReserve(): string {
    const editReserve = this.msg.editDate > 0 ? '         ' : '';
    return `${viewsReserve(this.context.liveViews)}${editReserve}  ${this.messageTimeText()}${this.msg.isOutgoing ? '   ' : ''}`;
  }

  private openSystemPillUser(userId: number): void {
    if (this.context.gestureClaimed || userId <= 0) { return; }
    this.actions.onAvatarTap(userId);
  }

  private fallbackLabel(): string {
    const label = this.msg.placeholderLabel.trim();
    return label !== '' ? label : str('mb_unsupported');
  }

  private formattedTextHasLink(text: string, entities: TdObject[]): boolean {
    if (isUnformattedPlainText(text, entities)) {
      return false;
    }
    const segments = parseFormattedText(text, entities);
    for (const segment of segments) {
      for (const run of segment.runs) {
        if (run.url !== '') {
          return true;
        }
      }
    }
    return false;
  }

  private hasInlineLink(): boolean {
    return this.formattedTextHasLink(this.msg.text, this.msg.textEntities) ||
      (this.group.caption !== '' &&
        this.formattedTextHasLink(this.group.caption, this.group.captionEntities));
  }

  private useDirectPlainText(): boolean {
    return this.msg.contentType === 'text' && this.group.photoPaths.length <= 1 &&
      this.msg.reactions.length === 0 && this.msg.translatedText === '' &&
      this.context.translationStatus === null &&
      !this.hasLinkPreview() &&
      isUnformattedPlainText(this.msg.text, this.msg.textEntities);
  }

  @Builder
  directPlainTextBody() {
    Text() {
      Span(this.msg.text).fontColor(bubbleTextFor(this.msg.isOutgoing));
      Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
    }
    .fontSize(this.env.msgTextSize)
    .lineHeight(this.env.msgTextSize * 1.34)
    .wordBreak(WordBreak.BREAK_WORD)
    .constraintSize({
      minWidth: this.measuredTimeLayerWidth(),
      maxWidth: this.inlineMaxW()
    });
  }

  @Builder
  directPlainText() {
    if (this.msg.replyToMessageId !== 0) {
      Column() {
        this.replyQuote();
        this.directPlainTextBody();
      }
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ minWidth: this.measuredTimeLayerWidth() });
    } else {
      this.directPlainTextBody();
    }
  }

  @Builder
  commentsRow() {
    Row({ space: 6 }) {
      if (this.msg.commentReplierIds.length > 0) {
        Row() {
          ForEach(this.msg.commentReplierIds, (uid: number, idx: number) => {
            LiveSenderAvatar({ spec: this.commentAvatarSpec(uid, idx) })
              .margin({ left: idx === 0 ? 0 : -8 })
              .borderRadius(11)
              // 叠压处那圈是"挖掉的间隙"，不是描边——所以取气泡自己的底色，
              // 而不是白色。白色在这里会实实在在盖住下面那个头像的一道边，
              // 看着像多了个白框；同色则读作两个头像之间空开了一道。
              //
              // 用 outline 而不是 border：border 画在边框盒上，头像图片自己
              // 还带圆角，两者之间会露出一圈底色（"框和图片有段距离"）。
              // outline 画在边框盒之外、紧贴组件边缘，不占布局也不留缝。
              .outline({
                width: 1.5,
                color: this.bubbleFillColor(),
                radius: 11,
                style: OutlineStyle.SOLID
              });
          }, (uid: number, idx: number) => `replier_${idx}_${uid}`);
        }
      }
      Text(plural('mb_comments_n', this.msg.commentCount, this.msg.commentCount)).fontSize(13).fontColor(this.accent()).fontWeight(FontWeight.Medium);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([this.accent()]);
    }
    .constraintSize({ maxWidth: this.inlineMaxW() })
    .width('100%')
    .border({ width: { top: 1 }, color: '#00000014' })
    // 整条拉满气泡宽、上下各给 10：原来只有一行 13 号字加 6 的上内边距，
    // 热区不到 30 高，频道评论入口这么高频的动作点着费劲（用户点名要大）。
    .padding({ top: 10, bottom: 4 }).margin({ top: 6 })
    .onClick(() => {
      if (this.context.gestureClaimed) { return; }
      this.actions.onCommentTap(this.msg.id); });
  }

  @Builder
  inlineKeyboard() {
    Row() {
      Column({ space: 4 }) {
        ForEach(this.msg.inlineButtons, (row: InlineBtn[], rowIdx: number) => {
          Row({ space: 4 }) {
            ForEach(row, (btn: InlineBtn, btnIdx: number) => {
              Text(btn.text)
                .fontSize(14).fontColor(Color.White).fontWeight(FontWeight.Medium)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Center)
                .layoutWeight(1).height(36)
                .backgroundColor(botButtonBg(btn.style, '#4d000000'))
                .borderRadius(8)
                .stateStyles({ normal: msgBotButtonNormalStyle, pressed: msgBotButtonPressedStyle })
                .animation({ duration: this.effectDuration(100), curve: Curve.EaseOut })
                .onClick(() => {
                  if (this.context.gestureClaimed) { return; }
                  if ((btn.webAppUrl ?? '') !== '') {
                    this.actions.onMiniApp(this.msg.id, btn.webAppUrl!);
                  } else if (btn.url !== '') {
                    // 按钮上的字不是网址，先让用户看清要去哪（同官方）。
                    this.actions.onLinkTap(btn.url, true);
                  } else if (btn.callbackData !== '') {
                    this.actions.onBotCallback(this.msg.id, btn.callbackData);
                  } else if (btn.isGame) {
                    this.actions.onGameOpen(this.msg.id);
                  } else {
                    promptAction.showToast({ message: $r('app.string.miniapp_button_unsupported') });
                  }
                });
            // 点击目标、游戏分支和样式都属于组件身份，不能只看显示文字。
            }, (btn: InlineBtn, btnIdx: number) => inlineButtonKey(rowIdx, btnIdx, btn));
          }.width('100%');
        // 行键也得带内容。**只修内层的按钮键是修不动的**：外层键不变时 ForEach
      // 连行的构建函数都不会重跑，内层那个 ForEach 拿的还是上一条消息的
      // `row`，按钮文字于是停在上一条上——与相册格子当年同一个机理，推导见
      // albumGrid 上方那段（相册已改成固定槽位，不再靠键）。
      }, (row: InlineBtn[], rowIdx: number) => inlineButtonRowKey(rowIdx, row));
      }
      // Match the bubble's MEASURED width (it shrinks to fit its content), so
      // the keyboard is never wider than the bubble above it.
      .width(this.context.bubbleW > 0 ? this.context.bubbleW : this.inlineMaxW() + 16);
    }
    .width('100%')
    .padding({
      // Align with the bubble body; every row reserves the same 7vp tail
      // gutter so first/middle/last bubbles never shift horizontally.
      left: 10 + (this.msg.isOutgoing ? 0 : (this.data.isGroup ? 38 : 0) +
        this.bubbleTailGutter()),
      right: 10 + (this.msg.isOutgoing ? this.bubbleTailGutter() : 0),
      top: 2, bottom: 2
    })
    .justifyContent(this.msg.isOutgoing ? FlexAlign.End : FlexAlign.Start);
  }

  private hasLiveVideoSurface(): boolean {
    if (this.data.playSlotKey === '' || this.msg.isAnimation) {
      return false;
    }
    if (this.isPlaySlot(-1) && this.msg.videoFileId !== 0) {
      return true;
    }
    for (let i = 0; i < this.group.memberIds.length; i++) {
      if (this.isAlbumCellPlaySlot(i) && this.albumVideoFileIdAt(i) !== 0) {
        return true;
      }
    }
    return false;
  }

  private bubbleCornerRadius(): BorderRadiuses {
    // Read all reactive inputs before the cache lookup, including on hits.
    const group = this.group;
    const base = this.cornerCache.prepare(this.env.bubbleRadius, this.msg.isOutgoing,
      group.showSenderName, group.showAvatar);
    if (this.isPureMediaBubble()) {
      return PURE_MEDIA_CORNER_RADIUS;
    }
    return base;
  }

  @Builder
  reactionsRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.msg.reactions, (r: ReactionInfo) => {
        Row({ space: 4 }) {
          if (r.customEmojiId !== '') {
            // 位图还没下载完时给一个同尺寸占位，chip 宽度不会跳动。
            if (r.customEmojiPath !== '') {
              Image(this.reactionImageSource(r.customEmojiPath))
                .width(15).height(15).objectFit(ImageFit.Contain)
                .draggable(false);
            } else {
              Row()
                .width(15).height(15).borderRadius(4)
                .backgroundColor(r.isChosen ? '#40FFFFFF' : '#1A000000');
            }
          } else {
            Text(r.emoji).fontSize(13);
          }
          Text(`${r.count}`).fontSize(12).fontColor(r.isChosen ? Color.White : COLOR_TEXT_SECONDARY);
        }
        // 未选中态原来是写死的 '#00000010'（6% 的黑）：浅色气泡上几乎看不见，
        // 深色气泡上黑叠黑更是没有。换成跟随主题的资源，深色那边用的是白色
        // 透明度而不是黑色。
        .backgroundColor(r.isChosen ? this.accent() : $r('app.color.reaction_chip'))
        // 半径取高度的一半（15 的内容 + 上下各 4 = 23），两端才是正圆弧。
        .borderRadius(12).padding({ left: 9, right: 9, top: 4, bottom: 4 })
        .margin({ right: 4, top: 4 })
        .stateStyles({ normal: msgMenuActionNormalStyle, pressed: msgMenuActionPressedStyle })
        .animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
        .onClick(() => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onSetReaction(this.msg.id, reactionKeyFrom(r.emoji, r.customEmojiId), r.isChosen);
        })
        // Long-press a chip to see who reacted with it.
        .gesture(LongPressGesture().onAction(() => {
          this.actions.onShowReactors(this.msg.id, reactionKeyFrom(r.emoji, r.customEmojiId));
        }))
        .transition(this.reactionTransitions.prepare(r, this.reactionDuration(180)));
        // key 里带上路径，位图下载完成后 chip 才会重建并显示图片。
      // count 与 isChosen 必须进键：它们是这枚 chip 上**唯一会变的两样**，而键不变
      // 时 ForEach 不重跑子构建函数（同 albumGrid 上方那段推导）——点赞数会停在
      // 上一条消息、或者停在自己点之前的那个数上。
      }, (r: ReactionInfo) => `rx_${reactionKeyFrom(r.emoji, r.customEmojiId)}` +
        `_${r.customEmojiPath}_${r.count}_${r.isChosen ? 'y' : 'n'}`);
      // 末尾的「>」：点开看谁回应了（按表情分组的名单，见 ReactorsMenu）。
      // 频道里 Telegram 不给查回应人，不挂。
      if (this.reactorsArrowShown()) {
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(REACTORS_ARROW_ICON_VP).fontWeight(FontWeight.Medium)
            .fontColor([COLOR_TEXT_SECONDARY]);
        }
        // 不垫底色：它不是一个回应，只是「看名单」的入口，和表情胶囊长得一样会被
        // 读成又一个表情（用户：「箭头有个灰色的底色，能去掉吗」）。热区照旧。
        .height(23)
        .borderRadius(12).padding({ left: REACTORS_ARROW_PAD_H, right: REACTORS_ARROW_PAD_H })
        .margin({ right: 4, top: 4 })
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .id(this.reactorsAnchorId())
        .stateStyles({ normal: msgMenuActionNormalStyle, pressed: msgMenuActionPressedStyle })
        .animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
        .onClick(() => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onShowReactorsList(this.msg.id, this.reactorsAnchorId());
        });
      }
    }
    // **Flex 开了 wrap 就按父容器最大宽测量**，只写 maxWidth 挡不住，alignSelf
    // 也挡不住（那只管对齐不管测量——上一版就是这么修的，1.4.0 里用户报仍然
    // 一个反应就把短消息顶到最大内容宽，issue #100）。给它一个明确宽度：按
    // chip 内容测出来的自然宽，封顶 inlineMaxW，超了才由 wrap 换行。
    .width(this.reactionsRowWidth())
    .constraintSize({ maxWidth: this.inlineMaxW() }).margin({ top: 4 });
  }

  private canEditNow(): boolean {
    // editableTick 必须在这一支里被**读到**，否则 V2 不会把它登记成依赖，
    // 答案到货时菜单就不会重绘。它自身不参与判断，只当"缓存可能变了"的信号。
    const known: boolean | undefined =
      this.editableTick >= 0 ? editableCached(this.msg.id) : undefined;
    if (known !== undefined) {
      return known;
    }
    return this.msg.isOutgoing && this.nowSec - this.msg.date < 172800;
  }

  private askEditable(): void {
    ensureEditable(this.data.chatId, this.msg.id, (): void => {
      this.editableTick = this.editableTick + 1;
    });
  }

  private canDeleteNow(): boolean {
    // 和 canEditNow 一样：deletableTick 必须在这一支里被**读到**，否则 V2 不会
    // 把它登记成依赖，答案到货时菜单就不会重绘。它自身不参与判断。
    const known: boolean | undefined =
      this.deletableTick >= 0 ? deletableCached(this.msg.id) : undefined;
    // **未知时按能删显示。** 查询没回来、失败、或者 TDLib 返回了认不出来的结构，
    // 都退回修之前的样子——点了才发现删不了，绝不能因为没答案就把「删除」藏掉。
    return known !== false;
  }

  private askDeletable(): void {
    ensureDeletable(getTdClient(), this.data.chatId, this.msg.id, (): void => {
      this.deletableTick = this.deletableTick + 1;
    });
  }

  private reactionsRowWidth(): number {
    const environment: string = `${textMeasureEnvironment.epoch}:${this.env.langEpoch}:${this.env.appearanceEpoch}`;
    this.textMeasureCache.prepare(environment);
    const availableWidth: number = this.inlineMaxW();
    const reactions: ReactionInfo[] = this.msg.reactions;
    const arrowShown: boolean = this.reactorsArrowShown();
    const timeText: string = this.messageTimeText();
    const edited: boolean = this.msg.editDate > 0;
    const outgoing: boolean = this.msg.isOutgoing;
    const views: string = this.context.liveViews;
    // 签名里必须带上影响时间戳宽度的四样（时刻文本、已编辑、自己发的、浏览数），
    // 否则同一条消息被编辑过之后仍拿着旧的上限。
    const sig: string = reactions
      .map((r: ReactionInfo): string => `${r.emoji}|${r.customEmojiId}|${r.count}`).join(',') +
      `>${arrowShown}` +
      `#${timeText}|${edited}|${outgoing}|${views}` +
      `@${environment}:${availableWidth}`;
    if (sig === this.rxWidthSig && this.rxWidthCache > 0) {
      return this.rxWidthCache;
    }
    this.textMeasureFailed = false;
    const chips: number[] = [];
    for (const r of reactions) {
      // 自定义表情是 15×15 的位图（或同尺寸占位）；unicode 表情是 13fp 的 Text，得测。
      const icon: number = r.customEmojiId !== '' ? CHIP_ICON_VP : this.measureTextVp(r.emoji, 13);
      chips.push(reactionChipWidth(icon, this.measureTextVp(`${r.count}`, 12)));
    }
    if (arrowShown) {
      chips.push(REACTORS_ARROW_PAD_H * 2 + REACTORS_ARROW_ICON_VP + REACTORS_ARROW_MARGIN_R);
    }
    // 时间戳和反应条同处一行，先把它要占的位扣掉再封顶——不扣的话反应条会
    // 顶满 inlineMaxW，把时间戳挤到气泡外面（见 util/reactionsWidth 的说明）。
    const timeVp: number = timeOverlayWidth(
      this.measureTextVp(timeText, 11),
      edited ? this.measureTextVp(str('mb_edited'), 10.5) : 0,
      edited, outgoing,
      // 眼睛 11 + 间隙 2 + 标签。
      views !== '' ? 13 + this.measureTextVp(views, 11) : 0);
    this.rxWidthSig = this.textMeasureFailed ? '' : sig;
    this.rxWidthCache = reactionsRowWidth(chips,
      reactionsRowMaxWidth(availableWidth, timeVp));
    return this.rxWidthCache;
  }

  private measureTextVp(text: string, fontSize: number): number {
    try {
      return this.textMeasureCache.width(text, fontSize, (content: string, size: number): number => {
        const uiContext = this.getUIContext();
        const measure = (value: string, font: number): number => {
          const measured: SizeOptions = uiContext.getMeasureUtils().measureTextSize({
            textContent: value, fontSize: font
          });
          return measured.width as number;
        };
        let scope: number = -1;
        let units: string = '';
        // getId is API 22+. On API 20/21 or an unavailable context identity,
        // retain the original per-component cache and native measurement path.
        if (sharedTextMeasurementSupported === undefined) {
          sharedTextMeasurementSupported = deviceInfo.sdkApiVersion >= 22;
        }
        if (sharedTextMeasurementSupported) {
          try {
            const density: number = uiContext.vp2px(1);
            const fontScale: number = uiContext.fp2px(1);
            if (Number.isFinite(density) && density > 0 && Number.isFinite(fontScale) && fontScale > 0) {
              units = `${density}:${fontScale}`;
              scope = uiContext.getId();
            }
          } catch (e) { scope = -1; }
        }
        const environment: string = `${textMeasureEnvironment.epoch}:${this.env.langEpoch}:${this.env.appearanceEpoch}:${units}`;
        return px2vp(sharedTextMeasurements.width(scope, environment, content, size, measure));
      });
    } catch (e) {
      this.textMeasureFailed = true;
      return fontSize * Math.max(1, text.length);
    }
  }

  private reactorsArrowShown(): boolean {
    return !this.data.isChannel && this.msg.reactions.length > 0;
  }

  private reactorsAnchorId(): string {
    return `reactors_anchor_${this.data.chatId}_${this.msg.id}`;
  }

  private reactionImageSource(path: string): string {
    return path.startsWith('/') ? `file://${path}` : path;
  }

  private reactionChosen(reactionKey: string): boolean {
    for (const r of this.msg.reactions) {
      if (reactionKeyFrom(r.emoji, r.customEmojiId) === reactionKey) {
        return r.isChosen;
      }
    }
    return false;
  }

  private copyUrlToPasteboard(url: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
    pasteboard.getSystemPasteboard().setData(data).then((): void => {
      promptAction.showToast({ message: $r('app.string.link_copied'), duration: 1300 });
    }).catch((): void => {
      promptAction.showToast({ message: $r('app.string.copy_failed'), duration: 1300 });
    });
  }

  private copyMessageUrls(): void {
    const urls: string[] = messageUrls(this.msg.text, this.msg.textEntities);
    if (urls.length === 0) {
      return;
    }
    if (urls.length === 1) {
      this.copyUrlToPasteboard(urls[0]);
      return;
    }
    // 多条链接：弹菜单挑一条。showActionMenu 最多 6 个按钮，超出的截断——
    // 一条消息塞六条以上链接的场景，逐条挑本来也没有意义。
    const shown: string[] = urls.slice(0, 6);
    promptAction.showActionMenu({
      title: str('mb_copy_url'),
      buttons: shown.map((u: string): promptAction.Button => ({
        text: u.length > 40 ? u.substring(0, 37) + '…' : u,
        color: '#3390EC'
      })) as [promptAction.Button]
    }).then((result: promptAction.ActionMenuSuccessResponse): void => {
      const picked: string = shown[result.index] ?? '';
      if (picked !== '') {
        this.copyUrlToPasteboard(picked);
      }
    }).catch((): void => {});
  }

  @Builder
  messageReactionMenuItem() {
    Row({ space: 2 }) {
      ForEach(QUICK_REACTIONS, (e: string) => {
        Row() {
          Text(e).fontSize(23);
        }
        .width(32).height(34).borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.reactionChosen(e) ? '#263391E8' : Color.Transparent)
        .stateStyles({ normal: msgMenuActionNormalStyle, pressed: msgMenuActionPressedStyle })
        .animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
        .onClick((): void => { this.actions.onSetReaction(this.msg.id, e, this.reactionChosen(e)); })
        .gesture(LongPressGesture().onAction((): void => { this.actions.onSetDefaultReaction(e); }));
      }, (e: string): string => e);
      Blank();
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(15).fontColor([COLOR_ICON_SECONDARY]);
      }
      .width(30).height(30).borderRadius(15).backgroundColor('#0000000F')
      .justifyContent(FlexAlign.Center)
      .stateStyles({ normal: msgMenuActionNormalStyle, pressed: msgMenuActionPressedStyle })
      .animation({ duration: this.reactionDuration(110), curve: Curve.EaseOut })
      .onClick((): void => { this.actions.onOpenReactions(this.msg.id); });
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  msgContextMenu() {
    Menu() {
      MenuItem(this.messageReactionMenuItem);
      if (this.data.canReply && !this.data.editingActive &&
        this.msg.contentType !== 'system' && this.msg.contentType !== 'hidden') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_turn_up_left')),
          content: $r('app.string.mb_reply')
        }).onClick((): void => { this.actions.onReplyTo(this.msg.id); });
      }
      if (this.canEditNow() &&
        (this.msg.contentType === 'text' || EDITABLE_CAPTION_TYPES.indexOf(this.msg.contentType) >= 0)) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
          content: this.msg.contentType === 'text' ? $r('app.string.edit') : $r('app.string.mb_edit_caption')
        }).onClick((): void => { this.actions.onEditMsg(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus_square_on_square')),
        content: $r('app.string.mb_copy_text')
      }).onClick((): void => { this.actions.onCopyText(this.msg.id); });
      // 「复制文本」是整条全选，这一项是 issue #94 要的"只copy其中一段"。
      if (this.msg.text !== '') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.character_textbox')),
          content: $r('app.string.mb_select_text')
        }).onClick((): void => { this.actions.onSelectText(this.msg.id); });
      }
      if (this.msg.text !== '') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.translate')),
          content: $r('app.string.mb_translate')
        }).onClick((): void => { this.actions.onTranslateMsg(this.msg.id); });
      }
      if (messageUrls(this.msg.text, this.msg.textEntities).length > 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.paperclip')),
          content: $r('app.string.mb_copy_url')
        }).onClick((): void => { this.copyMessageUrls(); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_turn_up_right')),
        content: $r('app.string.mb_forward')
      }).onClick((): void => { this.actions.onForwardMessages(this.group.memberIds); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bookmark')),
        content: $r('app.string.mb_save_to_saved')
      }).onClick((): void => { this.actions.onSaveMessages(this.group.memberIds); });
      // 视频专有：后台缓存（不存相册，进度在通知栏和「设置 › 下载中心」）。
      if (canBackgroundCache(this.msg)) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrow_down_circle')),
          content: $r('app.string.dc_background_cache')
        }).onClick((): void => { this.actions.onBackgroundCache(this.group.memberIds); });
      }
      // 动图专有：存进账号的 saved animations，之后从输入栏的 GIF 面板取用。
      // 判据用 isAnimation 而不是 contentType——GIF 在本应用里 contentType 就是
      // 'video'（messageAnimation 走视频管线，见 util/formatMsgContent），
      // 只有这个标志能把动图和普通视频分开。
      // 贴纸专有两项（issue 反馈①②）：看合集、收藏/取消收藏。
      if (this.msg.contentType === 'sticker' && this.msg.stickerSetId !== '') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_grid_2x2')),
          content: $r('app.string.mb_view_sticker_set')
        }).onClick((): void => { this.actions.onViewStickerSet(this.msg.id); });
      }
      if (this.stickerFileForFavorite() !== 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier(isFavoriteSticker(this.stickerFileForFavorite())
            ? $r('sys.symbol.star_fill') : $r('sys.symbol.star')),
          content: isFavoriteSticker(this.stickerFileForFavorite())
            ? $r('app.string.mb_remove_favorite_sticker') : $r('app.string.mb_add_favorite_sticker')
        }).onClick((): void => { this.actions.onToggleFavoriteSticker(this.msg.id); });
      }
      if (this.msg.isAnimation && this.msg.videoFileId !== 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus_square_on_square')),
          content: $r('app.string.mb_add_to_gifs')
        }).onClick((): void => { this.actions.onAddToGifs(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.repeat')),
        content: $r('app.string.mb_repeat')
      }).onClick((): void => { this.actions.onRepeatMessages(this.group.memberIds); });
      if (this.data.isGroup && this.msg.senderIsUser && this.msg.senderId > 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person')),
          content: $r('app.string.mb_view_history')
        }).onClick((): void => { this.actions.onViewSenderHistory(this.msg.senderId); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pin')),
        content: this.data.isPinnedMsg ? $r('app.string.ft_unpin') : $r('app.string.ft_pin')
      }).onClick((): void => { this.actions.onPinMsg(this.msg.id, this.data.isPinnedMsg); });
      if (this.canEditNow() &&
        (this.msg.contentType === 'photo' || this.msg.contentType === 'video')) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.picture')),
          content: $r('app.string.mb_replace_media')
        }).onClick((): void => { this.actions.onReplaceMedia(this.msg.id); });
      }
      if (this.msg.contentType === 'poll' && this.msg.isOutgoing && !this.msg.pollIsClosed) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
          content: $r('app.string.mb_stop_poll')
        }).onClick((): void => { this.actions.onStopPoll(this.msg.id); });
      }
      if (this.msg.contentType === 'poll' && !this.msg.pollIsAnonymous) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person_2')),
          content: $r('app.string.mb_view_voters')
        }).onClick((): void => { this.actions.onPollVoters(this.msg.id); });
      }
      // 自己发的、密聊、我的收藏：没有可举报对象，不出这一项。
      if (this.data.canReport && !this.msg.isOutgoing) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.exclamationmark_circle')).fontColor([Color.Red]),
          content: $r('app.string.mb_report')
        }).onClick((): void => { this.actions.onReportMsg(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
        content: $r('app.string.mb_select')
      }).onClick((): void => { this.actions.onSelectMessages(this.group.memberIds); });
      // 不可删的消息（典型是频道里别人发的帖子、而你不是管理员）不出这一项：
      // 原来它照样出现，点下去要等一次查询、发现两个范围都不给，再弹一句
      // 「无法确认所选消息的可用删除范围」——等于点了个寂寞。
      if (this.canDeleteNow()) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([Color.Red]),
          content: $r('app.string.delete')
        }).onClick((): void => { this.actions.onDeleteMsg(this.msg.id); });
      }
    }
    // 百分比宽度的表情行会让未定宽的 Menu 采用整屏约束，随后屏幕边界夹取会
    // 吞掉手指落点带来的横向偏移。固定回原菜单宽度，菜单才能继续贴近落点。
    .width(262)
  }

  private replyQuoteMaxW(): number {
    return Math.round(this.inlineMaxW() * REPLY_QUOTE_WIDTH_RATIO);
  }

  @Builder
  private replyQuoteBackdrop() {
    Row({ space: 0 }) {
      Column() {}
        .width(4)
        .height('100%')
        .flexShrink(0)
        .backgroundColor(this.accent())
        .borderRadius({ topLeft: 4, bottomLeft: 4, topRight: 0, bottomRight: 0 });
      Column() {}
        .layoutWeight(1)
        .height('100%')
        .backgroundColor(accentSoft())
        .borderRadius({ topLeft: 0, bottomLeft: 0, topRight: 4, bottomRight: 4 });
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  replyQuote() {
    Row({ space: REPLY_THUMB_GAP }) {
      if (this.msg.replyDiceLayers.length > 0) {
        DiceEndFrame({ layers: this.msg.replyDiceLayers, thumbPath: this.msg.replyThumbPath,
          boxSize: REPLY_THUMB_SIZE });
      } else if (this.msg.replyThumbPath !== '') {
        Image(replyThumbSrc(this.msg.replyThumbPath)).draggable(false)
          .width(REPLY_THUMB_SIZE).height(REPLY_THUMB_SIZE)
          .borderRadius(this.msg.replyThumbSticker ? 0 : 4)
          .objectFit(this.msg.replyThumbSticker ? ImageFit.Contain : ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium);
      }
      Column() {
        Text(this.msg.replySenderName).fontSize(12).fontColor(this.accent()).maxLines(1)
          .lineHeight(REPLY_QUOTE_LINE_H).height(REPLY_QUOTE_LINE_H)
          .constraintSize({ maxWidth: this.replyQuoteMaxW() }).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(this.msg.replyText).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
          .lineHeight(REPLY_QUOTE_LINE_H).height(REPLY_QUOTE_LINE_H)
          .constraintSize({ maxWidth: this.replyQuoteMaxW() }).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .flexShrink(1);
    }
    .alignItems(VerticalAlign.Center)
    .alignSelf(ItemAlign.Stretch)
    .padding({ left: 10, right: 6, top: 3, bottom: 3 })
    .background(this.replyQuoteBackdrop(), { align: Alignment.TopStart })
    .margin({ bottom: 4 })
    .onClick(() => {
      if (this.context.gestureClaimed) { return; }
      if (this.msg.replyToMessageId !== 0) {
        this.actions.onReplyTap(this.msg.replyToMessageId, this.msg.id);
      }
    });
  }

  @Builder
  content() {
    if (this.msg.replyToMessageId !== 0) { this.replyQuote(); }
    this.body();
  }

  private isBareEmoji(): boolean {
    const type: string = this.msg.contentType;
    return type === 'emoji' || type === 'sticker' || type === 'customEmoji'
      || type === 'videoNote' || type === 'dice';
  }

  private stickerFileForFavorite(): number {
    return stickerSourceFileId(
      this.msg.contentType, this.msg.stickerFileId, this.msg.photoFileId, this.msg.stickerFormat);
  }

  private bubbleFillColor(): ResourceColor {
    if (this.env.appearanceEpoch < 0) {
      return Color.Transparent; // 只为让 ArkUI 记下对 epoch 的依赖
    }
    if (this.msg.isOutgoing) {
      return this.data.themeBubbleOut !== '' ? this.data.themeBubbleOut : COLOR_BUBBLE_OUT;
    }
    return COLOR_BUBBLE_IN;
  }

  private tailCornerRadius(): number {
    const corners = this.bubbleCornerRadius();
    const radius = cornerPx(this.msg.isOutgoing ? corners.bottomRight : corners.bottomLeft);
    if (this.geo.w <= 0 || this.geo.h <= 0) {
      return radius;
    }
    return Math.max(0, Math.min(radius, (this.geo.w - (TAIL_W - 2)) / 2, this.geo.h / 2));
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
      Path({ width: TAIL_W + this.tailCornerRadius(), height: Math.max(TAIL_H, this.tailCornerRadius()) })
        .commands(tailShapeCommands(outgoing, TAIL_W, TAIL_H, vp2px(1), this.tailCornerRadius(), 2))
        .fill(this.bubbleFillColor())
        .stroke(Color.Transparent)
        .strokeWidth(0)
        // 压叠 2px 而不是 1px：去掉黑描边之后，尾巴和气泡是两个相邻节点，
        // 1px 压叠下拼缝的抗锯齿会露出一条细线（之前被那圈黑边盖住了）。
        // 只影响实心档——玻璃档整块是一条轮廓裁出来的，没有拼缝。
        .margin(outgoing ? { left: -2 - this.tailCornerRadius() } : { right: -2 - this.tailCornerRadius() });
    }
  }

  // 材质档只看全局开关，不看单行可见性（理由见 LightweightPlainTextBubble）。
  private bubbleMaterialLive(): boolean {
    return this.env.bubbleMaterialOn && !this.env.powerSaving;
  }

  private bubbleBg(): ResourceColor {
    if (!this.bubbleMaterialLive()) {
      return this.bubbleFillColor();
    }
    return this.glassBodyFallbackOn() ? this.glassBg() : Color.Transparent;
  }

  private glassLive(): boolean {
    return this.bubbleMaterialLive() && !this.isBareEmoji();
  }

  private glassReady(): boolean {
    return glassPaintReady(this.glassLive(), this.geo.w, this.geo.h);
  }

  private glassBodyOn(): boolean {
    return glassBodyPainted(this.glassLive(), this.geo.w, this.geo.h);
  }

  private glassBodyFallbackOn(): boolean {
    return glassBodyFallbackPainted(this.glassLive(), this.geo.w, this.geo.h);
  }

  private glassBg(): ResourceColor {
    return this.glassBodyFallbackOn()
      ? bubbleGlassFill(this.bubbleFillColor()) : Color.Transparent;
  }

  // 本体不挂 backgroundBlurStyle：undefined 撤不掉已挂的模糊，会留下叠层
  // （见 LightweightPlainTextBubble 同名说明）。
  private containerGlassBg(): ResourceColor {
    return this.glassReady() ? bubbleGlassFill(this.bubbleFillColor()) : Color.Transparent;
  }

  private containerGlassBlurStyle(): BlurStyle | undefined {
    return this.glassReady() ? bubbleGlassBlurStyle() : undefined;
  }

  private glassRadius(): BorderRadiuses {
    const r = this.bubbleCornerRadius();
    if (!this.hasBubbleTail()) {
      return r;
    }
    return this.msg.isOutgoing
      ? { topLeft: r.topLeft, topRight: r.topRight, bottomRight: 0, bottomLeft: r.bottomLeft }
      : { topLeft: r.topLeft, topRight: r.topRight, bottomRight: r.bottomRight, bottomLeft: 0 };
  }

  @Builder
  solidShellShadow() {
    if (this.geo.w > 0 && this.geo.h > 0 && !this.isBareEmoji()) {
      // 单个完整轮廓负责外部投影，阴影不再落在主体与尾角之间。
      Column() {}
        .width(this.geo.w).height(this.geo.h)
        // Direct decorative child of the outer Row: absolute children do not
        // contribute to Row measurement, including when a reused bubble shrinks.
        .position({ x: 0, y: 0 })
        .clipShape(this.shadowShapeCache.prepare(this.geo.w, this.geo.h, this.msg.isOutgoing,
          this.hasBubbleTail(), this.bubbleCornerRadius()))
        .shadow({ radius: 2, color: '#14000000', offsetX: 0, offsetY: 1, fill: false })
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no');
    }
  }

  @Builder
  glassOutline() {
    if (this.glassReady()) {
      Path({ width: this.geo.w, height: this.geo.h })
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
        .commands(glassOutlineCommands(this.geo.w, this.geo.h, this.msg.isOutgoing,
          this.hasBubbleTail(), this.bubbleCornerRadius()))
        .fill(Color.Transparent)
        .stroke(GLASS_OUTLINE_COLOR)
        .strokeWidth(GLASS_OUTLINE_WIDTH);
    } else if (!this.glassBodyOn()) {
      this.solidShellShadow();
    }
  }

  private timeOnMedia(): boolean {
    if (this.msg.reactions.length > 0) {
      return false;
    }
    if (this.group.photoPaths.length > 1) {
      return this.group.caption === '';
    }
    if (this.isBareEmoji()) {
      return true;
    }
    return (this.msg.contentType === 'photo' || this.msg.contentType === 'video') && this.msg.text === '';
  }

  private measuredTimeLayerWidth(): number {
    if (this.isBareEmoji()) {
      return 0;
    }
    // 正文本来就在这个 Stack 里、天然参与它的固有宽度，不需要在这里照顾；
    // 需要照顾的只有排在 Stack 外面、可能比正文更宽的那几个标签。
    // 三个显示判据和 build 里的 if 是同一份（下面三个方法），量到的宽度只在
    // 标签真的显示时才算数。
    return timeLayerMinWidth(this.inlineMaxW(), {
      forwardShown: this.forwardLabelShown(), forwardW: this.context.forwardLabelW,
      senderShown: this.senderLabelShown(), senderW: this.context.senderLabelW,
      commentsShown: this.commentsRowShown(), commentsW: this.context.commentsRowW
    });
  }

  private forwardLabelShown(): boolean {
    return this.msg.forwardFrom !== '';
  }

  // 内容区基础内边距：图片/视频走紧贴的 2vp，其它走 8vp。
  // 媒体气泡（图片贴边，基础内边距只有 2）里，昵称/转发标签要和说明文字
  // 对齐，所以再补一份内边距。纯文字气泡的基础内边距已经是 8，不需要补。
  private labelSidePadding(): number {
    return this.isMediaBubble() ? 8 : 0;
  }

  // 媒体 + 说明文字时的左右内收量（图片贴边 2vp，文字/昵称/时间统一 10vp）。
  private captionInset(): number {
    return this.isMediaBubble() && this.msg.text !== '' ? 8 : 0;
  }

  private contentBasePadding(): number {
    return this.isMediaBubble() ? 2 : 8;
  }

  // 收到带昵称的消息时，昵称行贴在左上角圆弧里会被切掉一截。
  //
  // 只在**纵向**把它压到弧线以下（深度 ≥ R - √(R² - (R-base)²) 之后横向
  // 切宽就小于 base 了），不在横向加左缩进：横向加缩进会把图片左白边撑大，
  // 右白边不变，图片在气泡里就不居中了。纵向让开则昵称、正文、图片仍共用
  // 同一个左基准，左右白边也保持对称。
  private senderLeadPadding(): number {
    // 转发标签与昵称同样贴在左上角，两者都要让开弧线。
    if (!this.senderLabelShown() && !this.forwardLabelShown()) {
      return 0;
    }
    const base: number = this.contentBasePadding();
    const radius: number = cornerPx(this.bubbleCornerRadius().topLeft);
    return senderLeadInset(radius, base);
  }

  private senderLabelShown(): boolean {
    return this.data.isGroup && !this.msg.isOutgoing && this.msg.senderName !== '' && this.group.showSenderName;
  }

  private commentsRowShown(): boolean {
    return this.data.isChannel && this.msg.commentCount > 0;
  }

  @Builder
  viewsLabel() {
    Row({ space: 2 }) {
      SymbolGlyph($r('sys.symbol.eye')).fontSize(11)
        .fontColor([this.timeOnMedia() ? Color.White : COLOR_TEXT_SECONDARY]);
      Text(this.context.liveViews).fontSize(11)
        .fontColor(this.timeOnMedia() ? Color.White : COLOR_TEXT_SECONDARY);
    }.alignItems(VerticalAlign.Center);
  }

  @Builder
  timeOverlay() {
    Row({ space: 4 }) {
      if (this.context.liveViews !== '') {
        this.viewsLabel();
      }
      if (this.msg.editDate > 0) {
        Text($r('app.string.mb_edited')).fontSize(10.5)
          .fontColor(this.timeOnMedia() ? Color.White : COLOR_TEXT_SECONDARY);
      }
      if (this.messageTimeText() !== '') {
        Text(this.messageTimeText()).fontSize(11)
          .fontColor(this.timeOnMedia() ? Color.White : COLOR_TEXT_SECONDARY);
      }
      if (this.msg.isOutgoing) {
        this.statusIcon();
      }
    }
    .padding(this.timeOnMedia() ? MEDIA_TIME_PADDING : PLAIN_TIME_PADDING)
    .backgroundColor(this.timeOnMedia() ? '#66000000' : Color.Transparent)
    .borderRadius(8)
    // 媒体 + 文字时时间要跟着文字一起内收，否则贴着气泡右边缘（用户 2026-11-05）。
    .margin(this.timeOnMedia()
      ? { right: 6, bottom: 6 }
      : { right: this.captionInset(), bottom: 2 });
    // 这里**不能**挂 .animation()。时间条几乎每个完整气泡都有，是全 app 最普遍的
    // 一处常驻属性动画。
    //
    // 「滑动时让 effectDuration(140) 返回 0」挡不住它：duration:0 只是让视觉过渡
    // 瞬间完成，ArkUI 照样建动画上下文，同一刷新周期里的脏布局仍被包进 JSAnimation。
    // 2026-08-27 真机最慢的 280ms 帧就是这条链：
    //   CustomNodeUpdate MessageBubble 209ms → JSAnimation 204ms → duration:0 204ms
    //     → FlushLayoutTask 174ms → Measure[List] 100ms
    // 纯滑动区间里 MessageBubble 自己拥有的 duration:0 有 267 次、累计 1572ms。
    // 状态变化（发送中/已发送/已读/失败、已编辑）本阶段直接切换，不做过渡。
  }

  private liveVideoChatTappable(): boolean {
    return this.msg.isVideoChatStarted && this.data.liveGroupCallId > 0;
  }

  private systemPillIcon(): string {
    if (this.msg.systemKind === 'people') {
      return 'sys.symbol.person_2';
    }
    if (this.msg.systemKind === 'pin') {
      return 'sys.symbol.pin';
    }
    if (this.msg.systemKind === 'call') {
      return 'sys.symbol.video';
    }
    if (this.msg.systemKind === 'timer') {
      return 'sys.symbol.clock';
    }
    if (this.msg.systemKind === 'payment') {
      return 'sys.symbol.gift';
    }
    if (this.msg.systemKind === 'security') {
      return 'sys.symbol.lock_fill';
    }
    if (this.msg.systemKind === 'topic') {
      return 'sys.symbol.message';
    }
    return 'sys.symbol.info_circle';
  }

  @Builder
  systemPill() {
    Row({ space: 5 }) {
      SymbolGlyph($r(this.systemPillIcon()))
        .fontSize(12.5)
        .fontColor([this.liveVideoChatTappable() ? this.accent() : COLOR_ICON_SECONDARY])
        .width(14);
      if (this.msg.systemLinks.length > 0 && !this.liveVideoChatTappable()) {
        // 人名可点（issue #201 第 3 条）：逐段 Span，名字落在人身上，其余文字落在
        // 文案里最先出现的人（pillSegments 已经把默认人填进非名字段）。区间是
        // 对着 placeholderLabel 算的，这里必须用同一个字符串切段。
        Text() {
          ForEach(pillSegments(this.msg.placeholderLabel, this.msg.systemLinks),
            (seg: PillSegment) => {
              Span(seg.text)
                .fontWeight(seg.isName ? FontWeight.Medium : FontWeight.Regular)
                .onClick((): void => { this.openSystemPillUser(seg.userId); });
            }, (seg: PillSegment, index: number): string => `${index}_${seg.userId}_${seg.text}`);
        }
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: this.data.contentWidth * 0.68 });
      } else {
        Text(this.fallbackLabel())
          .fontSize(12)
          .fontColor(this.liveVideoChatTappable() ? this.accent() : COLOR_TEXT_SECONDARY)
          .fontWeight(this.liveVideoChatTappable() ? FontWeight.Medium : FontWeight.Regular)
          .textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: this.data.contentWidth * 0.68 });
      }
      if (this.liveVideoChatTappable()) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(10).fontColor([this.accent()]).width(10);
      }
    }
    .constraintSize({ maxWidth: this.data.contentWidth * 0.82 })
    .backgroundColor(this.liveVideoChatTappable() ? '#183478F6' : $r('app.color.system_pill'))
    .border({
      width: 0.5,
      color: this.liveVideoChatTappable() ? '#303478F6' : '#16FFFFFF'
    })
    .borderRadius(12)
    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
    .attributeModifier(this.liveVideoChatTappable() || this.msg.systemLinks.length > 0
      ? SYSTEM_PILL_PRESS_DIM : SYSTEM_PILL_PRESS_NONE)
    .animation({ duration: this.effectDuration(100), curve: Curve.EaseOut })
    .onClick((): void => {
      if (this.context.gestureClaimed) { return; }
      if (this.liveVideoChatTappable()) {
        this.actions.onLiveStreamTap(this.data.liveGroupCallId);
      }
    })
    .accessibilityText(this.liveVideoChatTappable()
      ? str('mb_fallback_open', this.fallbackLabel()) : this.fallbackLabel());
  }

  @Builder
  unreadDivider() {
    Row() {
      Divider()
        .layoutWeight(1)
        .strokeWidth(1)
        .color(COLOR_TEXT_SECONDARY)
        .opacity(0.55);
      Text(this.data.dividerIsResume
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

  @Builder
  bubbleCluster() {
    // 没有尾巴时的尾巴位由容器内边距占（见 tailGutterPadding），不再垫定宽空 Column。
    if (!this.msg.isOutgoing && this.hasBubbleTail()) {
      this.bubbleTail(false);
    }
    Column() {
      if (this.forwardLabelShown()) {
        // Tappable when the origin is known — opens the original post, or the
        // author's chat. A hidden-origin forward carries no ids and stays inert.
        Text(str('mb_forwarded_from', this.msg.forwardFrom)).fontSize(13).fontColor(this.accent())
          .fontWeight(FontWeight.Medium).margin({ bottom: 2 })
          .constraintSize({ maxWidth: this.inlineMaxW() })
          // onSizeChange 而不是 onAreaChange：后者每帧对所有注册节点逐个比对
          // （PipelineContext::HandleOnAreaChangeEvent，15:25 trace 翻页段每帧约 0.9ms），
          // 这里只要宽度；复用后尺寸没变不回调时，aboutToReuse 已按标签文本播种。
          .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
            const w: Length | undefined = size.width;
            if (typeof w === 'number') {
              this.context.forwardLabelW = w as number;
              rememberLabelWidth(`forward:${this.msg.forwardFrom}`, w as number);
            }
          })
          .padding({ left: this.labelSidePadding(), right: this.labelSidePadding() })
          .onClick(() => {
            if (this.context.gestureClaimed) { return; }
            if (this.msg.forwardOriginChatId !== 0 || this.msg.forwardOriginUserId !== 0) {
              this.actions.onForwardTap(this.msg.forwardOriginChatId, this.msg.forwardOriginMsgId,
                this.msg.forwardOriginUserId);
            }
          });
      }
      if (this.senderLabelShown()) {
        // 名字和身份标签同一行。标签自订阅（见 SenderRoleTag），名单到货时
        // 只有那一枚小标签换字，不会牵动整行重建。
        Row({ space: 5 }) {
          Text(this.msg.senderName).fontSize(14).fontColor(this.senderColor())
            .fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .flexShrink(1);
          SenderRoleTag({ chatId: this.data.chatId, senderId: this.msg.senderId,
            presetTag: this.msg.senderTag });
        }
        .padding({ left: this.labelSidePadding(), right: this.labelSidePadding() })
        .margin({ bottom: 4 })
        .alignItems(VerticalAlign.Center)
        // 同上：只要宽度，复用由 aboutToReuse 按文本播种。
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
          const w: Length | undefined = size.width;
          if (typeof w === 'number') {
            this.context.senderLabelW = w as number;
            rememberLabelWidth(`sender:${this.msg.senderName}`, w as number);
          }
        });
      }
      // Inline timestamp: overlaid at the content's bottom-right, sharing the
      // last text line (which reserves invisible tail space for it).
      Stack({ alignContent: Alignment.BottomEnd }) {
        // minWidth 挂在**正文 Column 上**，不是挂在 Stack 上。
        //
        // 挂在 Stack 上时，Stack 的 alignContent 作用在每一个孩子身上、不只是
        // 时间戳：标签比正文宽而把 Stack 撑开之后，BottomEnd 会把正文这个
        // Column 一起推到右边，正好压在时间戳上——正文靠右、和时间叠字。
        //
        // 挂在 Column 上则是 Column 自己变宽，而它的 alignItems(Start) 让正文
        // 留在左边；Stack 的宽度仍由这个最宽的孩子决定，BottomEnd 摆的就只剩
        // 时间戳，落点还是气泡真正的右下角。
        //
        // 注意别用「给时间戳套一层 width('100%') 的 Row」那种写法：百分比宽度
        // 的孩子会让 Stack 直接取到 maxWidth，每条气泡都被撑成整屏宽。
        if (this.useDirectPlainText()) {
          this.directPlainText();
        } else {
          Column() {
            this.content();
            if (this.msg.reactions.length > 0) {
              // 有反应时时间跟在反应行末尾（官方也是这样）：时间浮层原本贴
              // 气泡右下角，而反应行正好占住那一块，两者会叠在一起（issue #100）。
              Row({ space: 6 }) {
                this.reactionsRow();
                this.timeOverlay();
              }
              .alignItems(VerticalAlign.Bottom)
              .constraintSize({ maxWidth: this.inlineMaxW() });
            }
          }
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ minWidth: this.measuredTimeLayerWidth() });
        }
        if (this.msg.reactions.length === 0) {
          this.timeOverlay();
        }
      }
      // 时间贴的是这个 Stack 的右下角，而 Stack 按正文宽度排：正文比「昵称+
      // 标签」短时，时间就停在正文末尾、够不到气泡右边缘（用户报的）。昵称行
      // 的宽度已经量过（senderLabelW），拿它兜一个最小宽度，两行右边缘就对齐了。
      .constraintSize({
        maxWidth: this.inlineMaxW(),
        minWidth: Math.min(this.inlineMaxW(), this.senderLabelShown() ? this.context.senderLabelW : 0)
      })
      if (this.commentsRowShown()) {
        Column() {
          this.commentsRow();
        }
        // 同上：只要宽度，复用由 aboutToReuse 按文本播种。
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
          const w: Length | undefined = size.width;
          if (typeof w === 'number') {
            this.context.commentsRowW = w as number;
            rememberLabelWidth(`comments:${this.msg.commentCount}`, w as number);
          }
        });
      }
    }
    .alignItems(HorizontalAlign.Start)
    // 气泡根节点上**没有**常驻 .animation()：按下态的 opacity/scale 直接切换，
    // 不做过渡。
    //
    // 曾经这里挂着 110ms 的常驻 .animation()。第一次尝试是把它从属性链末尾
    // 提到紧跟 stateStyles 之后，指望作用域语义把几何与材质属性排除在外；
    // 2026-08-27 的真机 trace 否定了这个假设：fling 窗口内 duration:110 的
    // 切片只从 1329 降到 1261（-5.1%），duration:110 -> FlushLayoutTask ->
    // Measure[List] 这条链路仍在，最重的一帧反而从 210ms 涨到 463ms。
    // 换句话说，只要节点上挂着常驻动画，ArkUI 在组件更新时仍会建立动画
    // 上下文，并把同一刷新周期里的列表脏节点一起带进动画布局。所以复用重绑、
    // 宽度回写、发送态、下载进度、翻译态这些普通数据更新必须落在任何动画
    // 上下文之外——唯一可靠的办法是节点上根本不存在常驻动画。
    //
    // 平滑按压反馈如需恢复，只能由真实的 Down/Up/Cancel 触摸事件驱动一次
    // 显式 animateTo，不要再加回常驻 .animation()。
    //
    // 按压变暗/缩放由最外层气泡壳统一处理，主体不再独立改变透明度和尺寸。
    // 材质、内容手势和命中仍保留在各自原节点。
    // 只给 inlineKeyboard 对齐宽度用，却挂在每条富气泡上。
    // onSizeChange 而不是 onAreaChange：后者每帧对所有注册节点逐个比对
    // （PipelineContext::HandleOnAreaChangeEvent，15:25 trace 翻页段每帧约 0.9ms）。
    // 复用后尺寸没变不会回调、@Local 又被重置成 0，由 aboutToReuse 用 measuredBubbleW 回填。
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      const w: Length | undefined = size.width;
      if (typeof w === 'number') {
        this.measuredBubbleW = w as number;
        this.context.bubbleW = w as number;
      }
    })
    .constraintSize({ maxWidth: this.bubbleMaxW() })
    .backgroundColor(this.isBareEmoji() ? Color.Transparent : this.bubbleBg())

    // Adjacent rows share a restrained 7vp corner. Only the final row gets
    // the full bottom corner; a single-row run keeps the configured top arc.
    .borderRadius(this.bubbleCornerRadius())
    // 主体与内容绘制在尾巴上方，防止发出消息的尾巴压住正文或时间角标。
    .zIndex(1)
    .padding(this.isBareEmoji() ? 0 : {
      left: this.contentBasePadding(),
      right: this.contentBasePadding(),
      top: this.contentBasePadding() + this.senderLeadPadding(),
      // 有说明文字时底部多留 6vp：媒体的基础内边距只有 2，文字会贴着下沿
      // （用户 2026-11-05）。纯图片消息不加，图片仍然贴边。
      bottom: this.contentBasePadding() + (this.captionInset() > 0 ? 6 : 0)
    })
    // 实心尾角与主体相邻绘制，主体独立投影会落到尾角根部，形成竖向暗缝。
    // 阴影统一交给外壳的 solidShellShadow，玻璃档仍由外层整体绘制。
    // Controlled mode (mirrors ChatRow.ets bindContextMenu): a manual
    // LongPressGesture in parallelGesture keeps the chat List's pan
    // recognizer alive while held (movement still cancels the long press),
    // and drives the same "lift the bubble" preview animation as a
    // chat-list row long-press. The swipe-to-reply PanGesture joins the same
    // group in Exclusive mode (only one of long-press/swipe wins per
    // gesture), still parallel to the ancestor List so vertical scrolling
    // is untouched — PanDirection.Horizontal means a vertical drag simply
    // never satisfies this recognizer and falls through to the List.
    .parallelGesture(
      this.canDragMessage() ? undefined : LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
        .onAction((event: GestureEvent): void => { this.onLongPress(event); })
    )
    .onTouch((event: TouchEvent): void => { this.onDragSourceTouch(event); })
    // 单击出菜单只在新交互下挂。用 .onClick 而不是塞进上面那个
    // parallelGesture：官方文档明写父子都绑点击手势时**子组件优先、父组件
    // 不触发**，正是我们要的——点链接、点图片、点内联按钮各归各，只有落在
    // 气泡空白处的点击才轮到菜单。而 parallelGesture 是例外，它父子都会触发，
    // 用它就会出现"点链接同时开链接和菜单"。
    .onClick((event: ClickEvent): void => {
      if (this.context.gestureClaimed) { return; }
      // 多选态下点击归格子 / 让位栏去勾选，气泡空白处不出菜单（同上，只有相册行走得到）。
      if (this.data.selectionActive) { return; }
      if (messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) {
        // 单击出菜单的方案下同样跟手。ClickEvent.x 已经是局部坐标。
        this.recordMenuOffset(event.x, Number(event.target.area.width));
        this.askEditable();
        this.askDeletable();
        this.context.msgContextMenuShown = true;
      }
    })
    if (this.msg.isOutgoing && this.hasBubbleTail()) {
      this.bubbleTail(true);
    }
  }

  build() {
    if (this.msg.contentType === 'hidden') {
      // Filtered service notice (e.g. channel paid-DM price) — render nothing.
      Column().height(0);
    } else if (this.msg.contentType === 'system') {
      Column() {
        if (this.group.dateLabel !== '') {
          Text(this.group.dateLabel)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.system_pill')).borderRadius(11)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .margin({ bottom: 4 });
        }
        if (this.data.showUnreadDivider) {
          this.unreadDivider();
        }
        this.systemPill();
      }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 3, bottom: 3 });
    } else {
    Column() {
      if (this.group.dateLabel !== '') {
        // Day-change separator pill, centered ("7-6" / "2024-12-31").
        // 胶囊直接挂在根 Column 里（默认水平居中）：原来外面那层满宽 Row 只负责居中和上下
        // 5/3 的留白，换成胶囊自己的外边距，占的高度一样（与系统消息那一支写法一致）。
        Text(this.group.dateLabel)
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.system_pill')).borderRadius(11)
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .margin({ top: 5, bottom: 3 });
      }
      if (this.data.showUnreadDivider) {
        this.unreadDivider();
      }
      Row() {
      // 内层这一行按内容宽度，只裹住头像和气泡——消息菜单绑在它身上，
      // 抬起来的预览才是"头像 + 气泡"。绑到外面那层满宽的行上，浮起来的会是
      // 一条通栏横条，右边一大片空白也跟着抬。满宽那层继续负责左滑和对齐。
      Row() {
      // 群聊来信不显示头像时，头像位由这层 Row 的内边距占（avatarGutterPadding），
      // 不再垫定宽空 Column（原注释：mid-run row keeps the avatar column's width so
      // bubbles stay aligned）；两层 if 也并成一层。
      if (this.data.isGroup && !this.msg.isOutgoing && this.group.showAvatar) {
        // LiveSenderAvatar, not AvatarView directly: the path arrives via the
        // sender-avatar side channel and swaps in place — the row itself never
        // rebuilds for an avatar (see senderAvatarChannel).
        LiveSenderAvatar({ spec: this.senderAvatarSpec() })
          .margin({ right: BUBBLE_AVATAR_GAP_VP })
          .onClick(() => {
            if (this.context.gestureClaimed) { return; }
            // Group message avatar → that user's profile page.
            if (this.msg.senderIsUser && this.msg.senderId > 0) {
              this.actions.onAvatarTap(this.msg.senderId);
            }
          })
          .gesture(LongPressGesture().onAction(() => {
            if (this.msg.senderIsUser && this.msg.senderId > 0) {
              this.actions.onAvatarLongPress(this.msg.senderId, this.msg.senderName);
            }
          }));
      }
      // Telegram-style bubble tail poking out of the bottom corner (left for
      // incoming, right for outgoing); the adjacent bubble corner is squared off.
      // 【按材质开关分两支容器，2026-09-14】理由见 LightweightPlainTextBubble 同一处：
      // 玻璃关着时这串属性全是空值，却每次更新/复用都重算、new 修饰器、建描边背景，
      // 外加一个每帧参与全局遍历的可见区回调。两支气泡必须同改。
      DissolveDeleteEffect({ instanceKey: 'message-' + this.data.chatId, rowId: this.msg.rowId,
        leaving: this.leaving, channel: this.actions.rowLeave, captureSupported: !this.hasLiveVideoSurface() }) {
        // 主体、尾角、玻璃和外壳阴影一起响应按压，避免菜单截图留下双色接缝。
        Row() {
          if (this.env.bubbleMaterialOn) {
            Row() {
              // Direct nodes replace background(builder)'s detached snapshot.
              // Only the original padded Row contributes to measured geometry.
              this.glassOutline();
              Row() {
                this.bubbleCluster();
              }
              .alignItems(VerticalAlign.Bottom)
              .padding(this.tailGutterPadding());
            }
            // 「尾巴 + 气泡」整块由**上层**渲染：材质挂在这一层，形状由整体轮廓裁剪
            // 给出（圆角矩形 + 三角尾巴）。尾巴在布局里只占位——两者天生一体，
            // 不存在「一边材质一边普通渲染」对不齐的问题。
            // 容器跨着那 7vp 尾巴留白，形状**只**由 clipShape 给。所以它必须等量到
            // 尺寸才上色，否则没裁剪的一帧会把留白一起涂满、左边缘外扩 7vp。
            // 没量到时它全透明，这一帧的玻璃由气泡本体自己扛；量到后本体同步退为
            // 透明，完整态始终只有外层这一份背景与模糊。
            .backgroundColor(this.containerGlassBg())
            // Transform the bubble and tail without moving avatar/date or list geometry.
            // The jump controller owns the one-shot animation; no resident .animation().
            .scale({ x: (1 + this.jumpFocus * JUMP_FOCUS_SCALE),
              y: (1 + this.jumpFocus * JUMP_FOCUS_SCALE),
              centerX: this.msg.isOutgoing ? '100%' : '0%', centerY: '50%' })
            .brightness(1 + this.jumpFocus * JUMP_FOCUS_BRIGHTNESS)
            .backgroundBlurStyle(this.containerGlassBlurStyle())
            // 材质自带的边框沿**本节点的 border-box** 画，而且吃 borderRadius。不设圆角
            // 它就画一个直角矩形框，被轮廓裁掉左边/底边后只剩顶边一条直线拐到右边——
            // 真机上就是用户报的「气泡描边不对」。设成气泡自己的圆角，这条边框就和轮廓
            // 重合（尾巴那侧仍由裁剪负责）。
            .borderRadius(this.glassRadius())
            .attributeModifier(bubbleGlassModifier(this.glassReady(), this.geo.w, this.geo.h,
              this.msg.isOutgoing, this.hasBubbleTail(), this.bubbleCornerRadius()))
            // 玻璃尺寸从属性链上量，**不要搬回修饰器里**（理由见 BubbleGlassModifier
            // 上的长注释：apply*Attribute 里注册是叠加，会把注册表撑爆）。
            // onSizeChange 而不是 onAreaChange：后者每帧参与一次全局遍历（HandleOnAreaChangeEvent）。
            // 复用后尺寸没变不会回调，由 aboutToReuse 用 measuredGlassW/H 回填。
            // 同值不写：@Local 赋同一个数也会走一遍变更通知。
            .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
              const w: Length | undefined = size.width;
              const h: Length | undefined = size.height;
              if (typeof w !== 'number' || typeof h !== 'number') {
                return;
              }
              this.measuredGlassW = w as number;
              this.measuredGlassH = h as number;
              this.geo.setSize(this.measuredGlassW, this.measuredGlassH);
            })
          } else {
            Row() {
              this.solidShellShadow();
              Row() {
                this.bubbleCluster();
              }
              .alignItems(VerticalAlign.Bottom)
              .padding(this.tailGutterPadding());
            }
            // Decoration is absolute, behind content, and cannot grow this Row.
            // The complete shell keeps the original single continuous shadow.
            .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
              const w: Length | undefined = size.width;
              const h: Length | undefined = size.height;
              if (typeof w !== 'number' || typeof h !== 'number') {
                return;
              }
              this.measuredGlassW = w as number;
              this.measuredGlassH = h as number;
              this.geo.setSize(this.measuredGlassW, this.measuredGlassH);
            })
            .scale({ x: (1 + this.jumpFocus * JUMP_FOCUS_SCALE),
              y: (1 + this.jumpFocus * JUMP_FOCUS_SCALE),
              centerX: this.msg.isOutgoing ? '100%' : '0%', centerY: '50%' })
            .brightness(1 + this.jumpFocus * JUMP_FOCUS_BRIGHTNESS)
          }
        }
        .attributeModifier(this.suppressBubblePressDim() || this.hasLiveVideoSurface()
          ? BUBBLE_PRESS_NONE : BUBBLE_PRESS_DIM)
      }
      }
      .alignItems(VerticalAlign.Bottom)
      .padding(this.avatarGutterPadding())
      .draggable(this.canDragMessage())
      .onDragStart((event: DragEvent): DragItemInfo => {
        this.dragGesture.claim();
        this.draggingMessage = true;
        this.context.gestureClaimed = true;
        this.context.msgContextMenuShown = false;
        return configureMessageDrag(event, this.data.chatId, this.msg.id, messageDragType(this.msg.contentType));
      })
      .onDragEnd((): void => { this.draggingMessage = false; })
      .bindContextMenu(this.context.msgContextMenuShown, this.msgContextMenu(), {
        onAppear: (): void => {
          logW(`[Menu114] menu appear id=${this.msg.id}`);
        },
        // 朝手指那一侧挪。ArkUI 自己会把菜单夹在屏幕内，所以极端偏移不会出界。
        offset: { x: this.context.menuOffsetX, y: 0 },
        // A play-slot bubble hosts a XComponentType.SURFACE video surface that
        // componentSnapshot cannot capture (see hasLiveVideoSurface()) — fall
        // back to no preview there instead of lifting a black rectangle.
        preview: (this.hasLiveVideoSurface() || this.compactMenuContext())
          ? MenuPreviewMode.NONE : MenuPreviewMode.IMAGE,
        previewBorderRadius: this.bubbleCornerRadius(),
        // 两条动效链按实例缓存，不在复用路径上现建（见 util/messageMenuTransitions）。
        previewAnimationOptions: {
          scale: [0.98, 1.035],
          transition: this.menuFx.preview()
        },
        borderRadius: 16,
        backgroundColor: Color.Transparent,
        backgroundBlurStyle: containerBlur('menu'),
        systemMaterial: overlayMaterial('menu'),
        transition: this.menuFx.menu(),
        mask: {
          color: '#52000000',
          backgroundBlurStyle: BlurStyle.BACKGROUND_THIN
        },
        modalMode: ModalMode.TARGET_WINDOW,
        hapticFeedbackMode: HapticFeedbackMode.AUTO,
        onDisappear: (): void => {
          logW(`[Menu114] menu disappear id=${this.msg.id}`);
          this.context.msgContextMenuShown = false;
        }
      });
      }
      .width('100%').padding({
        left: BUBBLE_ROW_SIDE_VP, right: BUBBLE_ROW_SIDE_VP,
        top: this.rowTopPadding(), bottom: this.rowBottomPadding()
      })
      .justifyContent(this.msg.isOutgoing ? FlexAlign.End : FlexAlign.Start)
      .alignItems(VerticalAlign.Bottom)
      // 左滑回复作用在**整行**上：头像和气泡一起走。挂在气泡上时只有气泡
      // 滑动，头像钉在原地，看着像两个东西。
      .translate({ x: this.swipeReplyX })
      // 仍然是 parallelGesture：与祖先 List 的 pan 识别器并行，纵向拖动不满足
      // PanDirection.Horizontal，直接落到 List 去滚动，不受影响。
      .parallelGesture(
        // 【只认左滑】原来是 PanDirection.Horizontal——左右都认，而右滑本来就
        // 被 onSwipeReplyUpdate 的 Math.min(0, offsetX) 夹成 0、看不到位移，
        // 认它纯属多余；更糟的是**右滑正是从左边缘返回的方向**，认领之后
        // gestureClaimed 被置位，后续点击会被静默吞掉。
        // 双向：左滑回复、右滑多选。曾经为了躲系统边缘返回收成过 Left，
        // 现在由 36vp 的边缘死区兜底（见 util/swipeReplyGesture），可以放开。
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
          .onActionUpdate((event: GestureEvent): void => { this.onSwipeReplyUpdate(event.offsetX); })
          .onActionEnd((): void => { this.onSwipeReplyEnd(); })
          .onActionCancel((): void => { this.onSwipeReplyEnd(); })
      )
      // 【整行热区】菜单原来只挂在气泡上，气泡两侧的空白点不到。这里在**满宽行**
      // 上再挂一套：子组件（气泡、头像、图片、链接、内联按钮）自己有 onClick 时
      // ArkUI 由子组件优先、父组件不触发，所以只有点在空白处才轮到这一层；
      // 长按用 gesture（非 parallelGesture）与气泡身上的那一支互斥，气泡上长按
      // 仍走气泡自己的分支，不会两边同时响应。
      .onClick((event: ClickEvent): void => {
        if (this.context.gestureClaimed || this.data.selectionActive) { return; }
        if (!messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) { return; }
        this.recordRowMenuOffset(event.x);
        this.askEditable();
        this.askDeletable();
        this.context.msgContextMenuShown = true;
      })
      .parallelGesture(
        LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
          .onAction((event: GestureEvent): void => {
            if (this.context.gestureClaimed) { return; }
            const fingers = event.fingerList;
            const localX: number = fingers.length > 0 ? fingers[0].localX : 0;
            // 这一下按在发送者头像上：整手归头像（长按 = @ 对方），满宽行不再
            // 弹菜单、也不进多选。头像自己的 gesture 拦不住这里的 parallelGesture
            // （parent 与 child 并行触发），只能在这一层按落点让路。
            if (fingers.length > 0 && hitSenderAvatarColumn(localX, this.data.isGroup,
              this.msg.isOutgoing, this.group.showAvatar)) {
              return;
            }
            this.recordRowMenuOffset(localX);
            this.onLongPress(event);
          })
      )
      // 每次按下先把认领标记清掉。onTouch 是冒泡事件，落在任何子元素上都会
      // 走到这里，所以这一下一定发生在子元素的点击判定之前。
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.context.gestureClaimed = false;
          this.draggingMessage = false;
          // 按下这一刻判一次落点是否在边缘死区里，整个手势期间沿用。
          // 用 windowX 而不是 displayX：分栏/自由窗口下要的是**窗口**边缘，
          // 而 screenWidthVp 存的正是 windowRect.width（见 EntryAbility）。
          const touches: TouchObject[] = event.touches;
          this.swipeFromEdge = touches.length > 0
            && isEdgeSwipeStart(touches[0].windowX, this.env.screenWidthVp);
        }
      });
      // 认领之后，消息表面上的每个 onClick 都会自己早退（搜 gestureClaimed）。
      //
      // 本来想用 onGestureRecognizerJudgeBegin 一处驳回所有 CLICK 识别器——
      // 官方把它列为手势冲突的口子，文档也说拿得到整条响应链上的识别器。
      // **实测无效**：从图片上左滑、在链接上长按，松手照样触发子元素的点击。
      // 所以改成在每个处理函数里早退，代码多几行，但行为是确定的。
      if (this.msg.inlineButtons.length > 0) {
        this.inlineKeyboard();
      }
    }.width('100%')
    // A restrained message entrance: a short rise and fade feels responsive
    // without detaching the bubble from its final position.
    .transition(this.data.animateIn
      ? TransitionEffect.translate({ y: 16 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.effectDuration(220), curve: Curve.FastOutSlowIn })
      : TransitionEffect.IDENTITY);
    }
  }

  private seedLabelWidths(): void {
    this.context.forwardLabelW = recallLabelWidth(`forward:${this.msg.forwardFrom}`);
    this.context.senderLabelW = recallLabelWidth(`sender:${this.msg.senderName}`);
    this.context.commentsRowW = recallLabelWidth(`comments:${this.msg.commentCount}`);
  }
}
