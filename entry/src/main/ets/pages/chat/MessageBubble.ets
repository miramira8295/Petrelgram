import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { MessageEntry, ReactionInfo, InlineBtn } from '../../store/MessageEntry';
import { PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO, slotKey } from './playSlot';
import { VideoBubbleSurface } from './VideoBubbleSurface';
import { TdObject } from '../../tdkit/TdTypes';
import { getAccentColorStore, getUserStore } from '../../tdkit/Globals';
import { CachedImage } from '../common/CachedImage';
import { actionMenuRow } from './ActionMenuRow';
import {
  KEY_TEXT_SIZE, KEY_BUBBLE_RADIUS, KEY_REDUCE_ANIM, TEXT_SIZE_DEFAULT, RADIUS_DEFAULT,
  KEY_POWER_ACTIVE, KEY_POWER_AUTOPLAY_GIF, KEY_POWER_CHAT_EFFECTS,
  KEY_POWER_EFFECT_MESSAGE, KEY_POWER_EFFECT_REACTION, KEY_POWER_EMOJI, KEY_POWER_EMOJI_CHAT,
  KEY_POWER_EMOJI_REACTIONS, KEY_POWER_STICKERS, KEY_POWER_STICKER_AUTOPLAY,
  KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration
} from '../../store/AppSettings';
import { TgsStickerView } from './TgsStickerView';
import { WebmStickerView } from './WebmStickerView';
import { SenderRoleTag } from './SenderRoleTag';
import { RichMessageView } from './RichMessageView';
import { SmartLoopVideo } from '../common/SmartLoopVideo';
import { LiveThumbImage } from './LiveThumbImage';
import {
  bubbleMaxWidth, MediaBox, MEDIA_MAX_HEIGHT_RATIO, MEDIA_MAX_WIDTH, mediaBoxFor, mediaThumbWidth
} from '../../util/mediaBox';
import { AvLoopVideo } from '../common/AvLoopVideo';
import { VoiceBubble } from './VoiceBubble';
import { MusicBubble } from './MusicBubble';
import { FileBubble } from './FileBubble';
import { ContactBubble } from './ContactBubble';
import { LocationBubble } from './LocationBubble';
import { PollBubble } from './PollBubble';
import { DiceBubble } from './DiceBubble';
import { GameBubble } from './GameBubble';
import { PaidMediaBubble } from './PaidMediaBubble';
import { GiftBubble } from './GiftBubble';
import { GiveawayBubble } from './GiveawayBubble';
import { formatClockTime } from '../../util/formatTime';
import { formatFileSize } from '../../util/formatFileSize';
import {
  isUnformattedPlainText, messageUrls, parseFormattedText, RichSegment, RichRun
} from '../../util/richText';
import { packAlbumRows, AlbumCell } from '../../util/packAlbumRows';
import { linkPreviewPresentation, LinkPreviewPresentation } from '../../util/linkPreview';
import { reactionKeyFrom } from '../../util/reactions';
import {
  animationDurationFor, persistentAnimationDurationFor, scrollActiveNow
} from '../../util/scrollEffects';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_OUT, COLOR_BUBBLE_IN, AVATAR_PALETTE, botButtonBg, accentSoft, bubbleTextFor } from '../../util/theme';
import { languageDisplayName } from '../../services/TranslationService';
import {
  senderAvatarFor, senderChannelKey, subscribeSenderAvatar
} from '../../util/senderAvatarChannel';
import { plural, str } from '../../util/strings';
import { LiveProgressRing } from './LiveProgressRing';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { sendStateFor, subscribeSendState } from '../../util/sendStateChannel';
import {
  TranslationStatus, subscribeTranslationStatus, translationStatusFor
} from '../../util/translationChannel';
import {
  MATERIAL_EPOCH, glassTailBlur, glassTailFill, overlayBackdropBlur, overlayBlur, overlayGlassFill, overlayMaterial
} from '../../util/overlayMaterial';
import {
  GLASS_OUTLINE_COLOR, GLASS_OUTLINE_WIDTH, TAIL_H, TAIL_W, bubbleGlassModifier, glassOutlineCommands, tailClip
} from '../../util/bubbleTail';
import { glassPaintReady, tailShapeCommands } from '../../util/bubbleGlassPath';
// 【临时探针，验完就删】见 util/tailFlipProbe.ets 的删除清单。
import { probeGlassMeasure } from '../../util/tailFlipProbe';
import { materialModifierWhen } from '../../util/materialModifier';
import { APPEARANCE_EPOCH, KEY_BUBBLE_MATERIAL_ON } from '../../util/appearance';
import { LINK_NAV_BUSY_KEY } from '../../util/linkTapGuard';
import { ThumbReadyGate } from './ThumbReadyGate';
import { GESTURE_CLASSIC, MessageGesturePolicy, messageGesturePolicy } from '../../util/messageGestures';
import { KEY_MSG_GESTURE } from '../../store/AppSettings';
import { CHAT_CONTENT_WIDTH_KEY } from '../../util/chatContentWidth';
import { CHIP_ICON_VP, reactionChipWidth, reactionsRowWidth } from '../../util/reactionsWidth';
import { logW } from '../../util/log';
import { reuseParam } from '../../util/reuseParams';
import { probeHit } from '../../util/panelProbe';

// 圆形视频气泡直径。和 Telegram 的观感接近，同时不至于挤占整行宽度。
const VIDEO_NOTE_SIDE: number = 180;
const REPLY_QUOTE_WIDTH_RATIO: number = 0.76;
// 引用块每行的固定行高。12 号字的默认行高由字体度量决定，内容为空时那一行
// 会塌成 0——锁死它，加载中的占位和加载完的内容才是同一个高度。
const REPLY_QUOTE_LINE_H: number = 16;

const ALBUM_MAX_WIDTH: number = 280;
const STICKER_MAX: number = 160;
const LINK_PREVIEW_HEIGHT_RATIO: number = 0.62;
// Quick reactions shown in the long-press menu's top row (tap the chevron to
// open the full emoji picker).
const QUICK_REACTIONS: string[] = ['❤️', '👍', '👎', '🔥', '🥰', '👏'];
// Media whose caption can be replaced via editMessageCaption.
const EDITABLE_CAPTION_TYPES: string[] = ['photo', 'video', 'file', 'audio', 'voice'];
// Swipe-to-reply: how far (vp) the bubble can be dragged left, and how far it
// must travel before release commits to a reply (both negative — drag is
// leftward-only).
const SWIPE_REPLY_MAX: number = -56;
const SWIPE_REPLY_TRIGGER: number = -40;

// MessageBubble remains the complete renderer. ChatPage mounts it through a
// thin shell that owns the page-level callbacks. Component-level reuse is
// deliberately disabled on the message tree: HarmonyOS 7.0 can double-free a
// TextPattern while purging that cache as ChatPage is destroyed.

// 群消息的发送者头像。路径经 senderAvatarChannel 旁路直达这里就地刷新，
// 不触发行重建 —— 头像路径已从行的内容 key 里摘除。
@Component
struct LiveSenderAvatar {
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // @Watch（审计设计约束「订阅按 key 自愈」）：头像订阅的 key 就是 senderId，
  // 而 aboutToReuse 的 params 未必带得到新 senderId——父级 ReusableMessageBubble
  // **已经是** @ReusableV2（P3 批 1），它的 aboutToReuse 没有入参（官方
  // 《@ReusableV2装饰器：V2组件复用》：「与@Reusable不同的是，aboutToReuse
  // 没有入参」），所以递归下来这一层的 params 也不再带值。
  // 挂 @Watch 之后，senderId 只要**变了**，@Prop 无论早一帧还是晚一帧落地，
  // 订阅都会按新 key 自己纠正，不必依赖 params。
  //
  // **但它替代不了 aboutToReuse 里的 setTimeout 兜底，别删那条（I-3）。**
  // @Watch 只在值**变化**时触发：同一个发送者连发几条时 senderId 不变，
  // watch 根本不跑，而 aboutToRecycle 已经清了 path、退了订阅、把
  // attachedAvatarKey 归零。那种情况下 setTimeout 是唯一的复活路径，
  // 删掉的结果是永久空白头像。
  @Prop @Watch('onSenderChanged') senderId: number = 0;
  @Prop @Watch('onSenderChanged') senderIsUser: boolean = true;
  @Prop initialPath: string = '';
  @Prop initials: string = '?';
  // 评论行的头像栈比发送者头像小一圈。
  // 群聊里发送者头像的直径。占位列宽 = 它 + 6 的右外边距，两处必须一起改，
  // 否则连续消息的气泡和带头像那行会错开。
  @Prop avatarSize: number = 38;
  @State private path: string = '';
  private unsubAvatar: (() => void) | null = null;
  // 订阅当前挂在哪个发送者 key 上。两个用途：① 同 key 短路（审计 P1-1：一次
  // 复用会经 aboutToReuse 和 @Watch 各挂一次，每次都是一整轮退订+重订阅）；
  // ② 让「订阅挂在哪」成为可判定的事实，而不是靠推断 params 有没有到。
  private attachedAvatarKey: string = '';

  private attachAvatarChannel(senderId: number, senderIsUser: boolean, initialPath: string): void {
    const key: string = senderChannelKey(senderId, senderIsUser);
    const known: string = senderAvatarFor(key);
    if (this.unsubAvatar !== null && this.attachedAvatarKey === key) {
      // 同 key 短路：订阅原样保留，但 path 必须重新播种——P0-1 让
      // aboutToRecycle / aboutToReuse 无条件清空了 path，不补种会空一帧。
      this.path = known !== '' ? known : initialPath;
      return;
    }
    this.detachAvatarChannel();
    this.attachedAvatarKey = key;
    this.path = known !== '' ? known : initialPath;
    this.unsubAvatar = subscribeSenderAvatar(key, (path: string): void => {
      this.path = path;
    });
  }

  // 按 key 自愈：@Prop 落地时若发送者已经换了，这里把订阅重挂到新 key 上。
  // 第三个参数刻意传 ''，不传 this.initialPath（I-2）：@Prop 是逐个赋值的，
  // senderId 的 watch 回调触发时 this.initialPath 可能还是**上一个发送者**的
  // 路径。attach 里「通道没缓存就用 initialPath」那条会在新面孔滚入（通道缓存
  // 常常为空）时画出上一个人的头像——正是这轮要修的「头像串行」，只是从
  // params 路径挪到了 @Watch 路径。传 '' 最差是先显示首字母圆底，等通道推送
  // 真路径，方向上安全。
  private onSenderChanged(): void {
    this.attachAvatarChannel(this.senderId, this.senderIsUser, '');
  }

  private detachAvatarChannel(): void {
    if (this.unsubAvatar !== null) {
      this.unsubAvatar();
      this.unsubAvatar = null;
    }
    this.attachedAvatarKey = '';
  }

  aboutToAppear(): void {
    this.attachAvatarChannel(this.senderId, this.senderIsUser, this.initialPath);
  }

  aboutToRecycle(): void {
    this.detachAvatarChannel();
    // P0-1（审计 3.1，C 类变量 path，行 121）：detach 只停订阅、不改值，
    // 而 CachedImage 的 path 与 visibility 都直接读它。不清空的话，走
    // aboutToReuse 兜底分支的那一帧画出来的就是**上一个发送者的位图**——
    // 这正是历史上全量开 @Reusable 时「头像串行」的机理。
    // 清 path 不依赖任何新参数，所以回收与复用两条路径都无条件执行。
    this.path = '';
  }

  aboutToReuse(params: Record<string, Object>): void {
    // 无条件前置（审计 S1）：不依赖新参数的清理放在 params 判断之前。
    // 这样兜底分支最差是「空一帧」，不会是「别人的一帧」；而且 V2 的
    // aboutToReuse 没有入参（C2）时这一句依然成立。
    this.path = '';
    // reuseParam：params 是 {} 还是 undefined 都安全，取不到就落到下面的
    // setTimeout 兜底（P3 批 2 第 0 项，见 util/reuseParams.ets 的说明）。
    const nextId: number | undefined = reuseParam(params, 'senderId') as number | undefined;
    const nextIsUser: boolean | undefined =
      reuseParam(params, 'senderIsUser') as boolean | undefined;
    const nextPath: string | undefined =
      reuseParam(params, 'initialPath') as string | undefined;
    if (nextId !== undefined && nextIsUser !== undefined) {
      this.attachAvatarChannel(nextId, nextIsUser, nextPath ?? '');
      return;
    }
    // **实测（2026-08-26 真机，820 个复用样本，P2-1 探针，已下架）**：
    // aboutToReuse 执行时 params 恒带全 senderId/senderIsUser，present=0 一次
    // 都没出现，且 params 与此刻的 @Prop 从未不一致。也就是说这条兜底分支在
    // 当前调用图下**不可达**。
    // **推导（不是实测）**：它仍然不能删（I-3）。@Watch 只在值**变化**时触发，
    // 连续两条同一发送者的消息 senderId 不变 → onSenderChanged 根本不跑；而
    // aboutToRecycle 已经把 path 清空、订阅退掉、attachedAvatarKey 归零。那种
    // 情况下这条 setTimeout 是唯一的复活路径，删掉会得到永久空白头像。
    // 另外父级**已经是** @ReusableV2（P3 批 1），aboutToReuse 没有入参，所以
    // 这条**已经不是**兜底分支，而是唯一分支。
    //
    // 官方只写了 @ReusableV2 会「递归地调用所有子组件的 aboutToReuse 回调」，
    // **没有写清递归到 V1 子组件时 params 传的是空对象 {} 还是根本不传
    // （undefined）**。P3 批 2 第 0 项把读法换成了 reuseParam：两种情况都不抛，
    // 都落到这条兜底。上机时仍要看这条兜底的命中率（0% 说明是 {}，100% 说明
    // 是 undefined），但**无论哪种都不会崩**。
    setTimeout((): void => {
      this.attachAvatarChannel(this.senderId, this.senderIsUser, this.initialPath);
    }, 0);
  }

  aboutToDisappear(): void {
    this.detachAvatarChannel();
  }

  build() {
    // One fixed subtree for initials and decoded bitmap. The old AvatarView
    // changed branches between empty/non-empty paths; under a recycled message
    // shell that both defeated reuse and accounted for 110 ms of build/destroy
    // work in the captured scroll trace.
    Stack() {
      Circle({ width: this.avatarSize, height: this.avatarSize })
        .fill(AVATAR_PALETTE[Math.abs(this.senderId) % AVATAR_PALETTE.length]);
      Text(this.initials)
        .fontColor(Color.White).fontSize(this.avatarSize * 0.4).fontWeight(FontWeight.Medium);
      CachedImage({
        path: this.path,
        boxWidth: this.avatarSize,
        boxHeight: this.avatarSize,
        radius: this.avatarSize / 2,
        fit: ImageFit.Cover
      })
        .visibility(this.path !== '' ? Visibility.Visible : Visibility.None);
    }
    .width(this.avatarSize).height(this.avatarSize);
  }
}

@Component
export struct MessageBubble {

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // 材质档位（厚度/光感）改变时重绘。overlayMaterial 是 util，订阅不了
  // AppStorage，只能由调用方订阅，同 LANGUAGE_EPOCH 的做法。
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  // @Watch fires whenever ChatPage hands down a new msg object (edits, status
  // changes, "replace media", etc.) — not once per frame — so the transition
  // check inside onMsgPropChanged is cheap and only fires onMediaGone on an
  // actual video→non-video flip (see onMsgPropChanged for why this matters).
  @Prop @Watch('onMsgPropChanged') msg: MessageEntry;
  @State private liveSendState: string = '';
  private unsubSendState: (() => void) | null = null;
  // 6 个通道（发送勾 + 4 个下载进度 + 翻译态）当前挂在哪一条消息的 rowId 上。
  // P0-4（审计 3.2b）：这是本组件订阅自愈的唯一依据——「params 里的 msg 是新
  // 是旧」静态判不了，「订阅挂在哪」却是本地可判定的事实。0 = 未挂。
  private attachedRowId: number = 0;
  // Chat-theme outgoing bubble color ('' = the standard theme resource color).
  @Prop themeBubbleOut: string = '';
  // 本地外观：epoch 一变，气泡底色/文字色（theme 里的活绑定）跟着重取。
  @StorageProp(APPEARANCE_EPOCH) appearanceEpoch: number = 0;
  // 气泡材质只给屏内气泡挂，离屏纯色；省电时也退回纯色。
  @StorageProp(KEY_BUBBLE_MATERIAL_ON) bubbleMaterialOn: boolean = false;
  // 初值 true：行是在 LazyForEach 首批里建出来的，onVisibleAreaChange 的首帧
  // 回调常常不来，初值 false 会让玻璃层等到「滑动一下」才挂上（用户报的）。
  // 由回调负责在真正离屏时关掉——那一路是可靠的。
  @State onScreen: boolean = true;
  // 「尾巴 + 气泡」外层容器量到的尺寸，整块玻璃的裁剪路径靠它。只在材质开着时被读。
  @State glassW: number = 0;
  @State glassH: number = 0;
  @Prop nowSec: number;
  // 本机正在共享实时位置的那条消息 id（0 = 没有共享）。
  @Prop liveSharingId: number = 0;
  onStopLiveLocation: () => void = (): void => {};
  // 身份标签按群区分（同一个人在别的群未必是管理员），所以标签通道的 key
  // 要带 chatId。MessageEntry 里没有这个字段，由页面传。
  @Prop chatId: number = 0;
  @Prop isGroup: boolean;
  @Prop isChannel: boolean;
  @Prop showUnreadDivider: boolean;
  @Prop dateLabel: string = ''; // date pill above this row when the day changes
  @Prop albumPaths: string[];
  @Prop albumFileIds: number[];
  @Prop albumRatios: number[];
  @Prop albumMemberIds: number[];
  // Same reasoning as msg above: fires on a new albumIsVideo array reference
  // from ChatPage, not per frame; onAlbumIsVideoChanged only emits when a
  // specific cell actually flips true→false.
  @Prop @Watch('onAlbumIsVideoChanged') albumIsVideo: boolean[];
  @Prop albumProgress: number[];
  @Prop albumFailed: boolean[];
  // 相册视频格子的播放位数据源：缩略图（albumFileIds/albumPaths）不足以起播，
  // 播放位选中的那一格要挂 VideoBubbleSurface，需要真正的视频文件信息。
  @Prop albumVideoFileIds: number[];
  @Prop albumVideoFileSizes: number[];
  @Prop albumVideoMimeTypes: string[];
  @Prop albumCaption: string;
  @Prop albumCaptionEntities: TdObject[] = [];
  // 读的是**内容列宽**，不是窗口宽——分栏下两者差一个左栏（issue #107）。
  // 字段仍叫 screenW：下面十几处按它算宽的式子一个都不用动。
  @StorageProp(CHAT_CONTENT_WIDTH_KEY) screenW: number = 360;
  // 长按菜单要不要带预览。小窗（悬浮窗）里键盘一弹起，剩下的高度放不下
  // "预览 + 菜单"，ArkUI 干脆不弹——用户报的就是这个（issue #114）。键盘在、或
  // 窗口本来就很矮时改成无预览，菜单本身占的高度小得多。
  @StorageProp('keyboardHeightVp') private menuKeyboardH: number = 0;
  @StorageProp('screenHeightVp') private menuWindowH: number = 780;
  // 手势方案（老交互 / 新交互），设置里改完立即生效，不用重进页面。
  @StorageProp(KEY_MSG_GESTURE) gestureScheme: string = GESTURE_CLASSIC;
  // 正在解析中的链接 url（linkTapGuard 广播）。只在渲染链接段时读，因此
  // 不含链接的气泡不会因为它变化而重建。
  @StorageProp(LINK_NAV_BUSY_KEY) linkNavBusyUrl: string = '';
  // Measured width of the bubble (it shrinks to fit content) — the inline
  // keyboard below matches it exactly instead of the theoretical max width.
  @State bubbleW: number = 0;
  // 长按/点击的落点相对气泡中心的水平偏移，交给 bindContextMenu 的 offset。
  // 菜单默认贴着气泡排（ArkUI 按组件矩形算位置，与触点无关，实测同一条消息
  // 按左缘和按右缘弹出位置完全一样），这个值让它朝手指那一侧挪。
  @State menuOffsetX: number = 0;
  // 时间层要跟随"气泡里最宽的那个兄弟"（转发标签 / 发送者名 / 评论行），
  // 它们都在时间 Stack **外面**，所以测它们不构成环。
  // 曾经是拿 bubbleW 回灌的，那是 minWidth ← bubbleW ← minWidth 的循环，
  // 只能涨不能落：任何一次量到偏大的宽度都被固化，气泡再也缩不回去，
  // BottomEnd 随即把正文推到右侧、时间戳压到文字底下——就是那个偶发的
  // "气泡横贯整屏、文字靠右、时间戳不见了"。
  @State private forwardLabelW: number = 0;
  @State private senderLabelW: number = 0;
  @State private commentsRowW: number = 0;
  // 换成另一条消息时把上面三个清零：新消息若不再显示某个标签，那个节点
  // 不会重新触发 onAreaChange，旧值会一直留着。
  //
  // 用 rowId 而不是 id：发送成功时 TDLib 把临时 id 换成真实 id，而 rowId 由
  // 新条目继承旧条目（MessageStore.onSendSucceeded），跨过那次替换保持不变。
  // 用 id 会让每条自己发出去的消息在成功那一刻白白重量一次宽度。
  private labelWidthRowId: number = 0;
  @State revealedSpoilerKeys: string[] = [];
  @State expandedQuoteKeys: string[] = [];
  // x/y are the tap's window coordinates (vp) — the fullscreen viewer uses them
  // as the anchor for its expand-from-tap / shrink-back-to-tap transition.
  onMediaTap: (messageId: number, x: number, y: number) => void = (): void => {};
  onLinkTap: (url: string) => void = (): void => {};
  onCommentTap: (messageId: number) => void = (): void => {};
  onBotCallback: (messageId: number, data: string) => void = (): void => {};
  onAvatarTap: (userId: number) => void = (): void => {};
  // Long press on a group message avatar → mention that sender in the composer.
  onAvatarLongPress: (userId: number, name: string) => void =
    (_userId: number, _name: string): void => {};
  // 第二个参数是"从哪条跳走的"。页面拿它当返回点——只用视口底部那条的话，
  // 引用块在屏幕靠上时返回位置会偏，跨屏的长消息尤其明显。
  onReplyTap: (messageId: number, fromId: number) => void = (): void => {};
  onFileTap: (messageId: number) => void = (): void => {};
  onFileSave: (messageId: number) => void = (): void => {};
  onFilePause: (messageId: number) => void = (): void => {};
  onStickerRetry: (messageId: number) => void = (): void => {};
  onLinkPreviewRetry: (messageId: number) => void = (): void => {};
  onContactOpen: (userId: number, phone: string, vcard: string) => void =
    (_userId: number, _phone: string, _vcard: string): void => {};
  onPhoneOpen: (phone: string) => void = (_phone: string): void => {};
  onLocationOpen: (latitude: number, longitude: number, label: string, valid: boolean) => void =
    (_latitude: number, _longitude: number, _label: string, _valid: boolean): void => {};
  onPollVote: (messageId: number, optionIds: number[]) => void =
    (_messageId: number, _optionIds: number[]): void => {};
  onGameOpen: (messageId: number) => void = (_messageId: number): void => {};
  onGamePhotoRetry: (messageId: number) => void = (_messageId: number): void => {};
  @Prop paidMediaPending: boolean = false;
  onPaidMediaUnlock: (messageId: number) => void = (_messageId: number): void => {};
  onPaidMediaOpen: (messageId: number) => void = (_messageId: number): void => {};
  onSpecialPhotoRetry: (messageId: number) => void = (_messageId: number): void => {};
  // 视频缩略图/文件下载失败后的重试；和图片重试分开，走的是 downloadFile 而非缩略图。
  onVideoRetry: (messageId: number) => void = (_messageId: number): void => {};
  onGiftCodeCopy: (code: string) => void = (_code: string): void => {};
  onGiveawayOpen: (chatId: number, messageId: number) => void =
    (_chatId: number, _messageId: number): void => {};
  onVoiceTap: (messageId: number) => void = (): void => {};
  onVoicePlaybackStarted: (messageId: number) => void = (): void => {};
  onAudioTap: (messageId: number) => void = (): void => {};
  onAudioPrevious: (messageId: number) => void = (): void => {};
  onAudioNext: (messageId: number) => void = (): void => {};
  onAudioSeek: (messageId: number, fraction: number) => void =
    (_messageId: number, _fraction: number): void => {};
  @Prop audioQueuePosition: number = 0;
  @Prop audioQueueLength: number = 0;
  @Prop audioHasPrevious: boolean = false;
  @Prop audioHasNext: boolean = false;
  onAutoplayVideoNeedDownload: (messageId: number) => void = (): void => {};
  // 播放位竞选上报：可见比例变化 / 组件消失。albumIndex 为 -1 表示非相册整条消息，
  // 相册格子用该格自己在 albumMemberIds 里的下标。回调由 ChatPage 接（见 playSlot.ets）。
  onMediaRatio: (messageId: number, albumIndex: number, ratio: number, centerY: number) => void =
    (_messageId: number, _albumIndex: number, _ratio: number, _centerY: number): void => {};
  onMediaGone: (messageId: number, albumIndex: number) => void =
    (_messageId: number, _albumIndex: number): void => {};
  // 当前播放位的 key（playSlot.slotKey 的输出），'' 表示没有播放位。
  @Prop playSlotKey: string = '';
  // 自动播放静音开关（KEY_AUTOPLAY_MUTED，由 ChatPage 用 @StorageProp 下发）。
  @Prop autoplayMuted: boolean = true;
  // 播放位视频的播放进度：每 350ms 一次的高频回调，故意不接到 @State——接上去
  // 会让 ChatPage 每 350ms 重建整个消息列表。ChatPage 用普通 Map 接住（按
  // messageId 记录），供全屏查看器交接时读取。
  onPlaySlotPositionChanged: (messageId: number, albumIndex: number, positionMs: number) => void =
    (_messageId: number, _albumIndex: number, _positionMs: number): void => {};
  // 播放位视频播完或内嵌播放失败：这一条主动退位，让同屏其它候选重新竞选。
  // 不接的话播完的那条会永久霸占播放位，同屏另一条永远起不来。
  onPlaySlotEnded: (messageId: number, albumIndex: number) => void =
    (_messageId: number, _albumIndex: number): void => {};
  // 播放位起播位置（毫秒）。由 ChatPage 在换届时从气泡进度表查出并随
  // playSlotKey 一起下发——全屏查看器交还的进度就是靠这条路接上的。
  @Prop playSlotStartMs: number = 0;
  onAnimationTap: (messageId: number, isPlaying: boolean) => void =
    (_messageId: number, _isPlaying: boolean): void => {};
  onAnimationPlaybackFailed: (messageId: number) => void = (): void => {};
  @Prop animationPaused: boolean = false;
  @Prop animationForcePlay: boolean = false;
  @Prop animationPlaybackFailed: boolean = false;
  // Long-press context menu actions.
  // emoji 参数其实是 reaction key：标准 emoji 原样，自定义 emoji 为 'ce:<id>'。
  onSetReaction: (messageId: number, emoji: string, isChosen: boolean) => void = (): void => {};
  onReplyTo: (messageId: number) => void = (): void => {};
  // Blocks swipe-to-reply while the composer is in edit mode (avoids the two
  // states fighting over the reply/edit strip). Long-press → 回复 is unaffected.
  @Prop editingActive: boolean = false;
  onEditMsg: (messageId: number) => void = (): void => {};
  onShowReactors: (messageId: number, emoji: string) => void = (): void => {};
  onTranslateMsg: (messageId: number) => void = (): void => {};
  onPinMsg: (messageId: number, unpin: boolean) => void = (): void => {};
  onStopPoll: (messageId: number) => void = (): void => {};
  onReplaceMedia: (messageId: number) => void = (): void => {};
  onPollVoters: (messageId: number) => void = (): void => {};
  onSetDefaultReaction: (emoji: string) => void = (): void => {};
  @Prop isPinnedMsg: boolean = false;
  onCopyText: (messageId: number) => void = (): void => {};
  onCopyCode: (text: string) => void = (): void => {};
  onCopyLink: (messageId: number) => void = (): void => {};
  onForwardMsg: (messageIds: number[]) => void = (): void => {};
  // 直接转发到收藏（和自己的会话），不弹选择面板。
  onSaveToSaved: (messageIds: number[]) => void = (): void => {};
  // 转发回本会话——群里俗称"复读"。
  onRepeatMsg: (messageIds: number[]) => void = (): void => {};
  // 在本会话里筛出这个发送者的全部消息。
  onViewSenderHistory: (senderId: number) => void = (): void => {};
  onReportMsg: (messageId: number) => void = (): void => {};
  onSelectMsg: (messageIds: number[]) => void = (): void => {};
  onDeleteMsg: (messageId: number) => void = (): void => {};
  // "转发自 X" tapped: (originChatId, originMsgId, originUserId) — chat ids for a
  // channel/chat origin, user id for a user origin.
  onForwardTap: (chatId: number, messageId: number, userId: number) => void = (): void => {};
  onOpenReactions: (messageId: number) => void = (): void => {};
  onRecognizeSpeech: (messageId: number) => void = (): void => {};
  onVideoNoteDownload: (messageId: number) => void = (): void => {};
  // 整聊天翻译：点「隐藏译文/显示译文」的单条折叠开关，状态存在条目上。
  onToggleTranslation: (messageId: number, hidden: boolean) => void = (): void => {};
  onRetryTranslation: (messageId: number) => void = (): void => {};
  @State private translationStatus: TranslationStatus | null = null;
  private unsubTranslation: (() => void) | null = null;
  @State private livePhotoProgress: number = 0;
  @State private liveLinkPhotoProgress: number = 0;
  @State private liveVideoProgress: number = 0;
  @State private liveStickerProgress: number = 0;
  private unsubPhotoProgress: (() => void) | null = null;
  private unsubLinkPhotoProgress: (() => void) | null = null;
  private unsubVideoProgress: (() => void) | null = null;
  private unsubStickerProgress: (() => void) | null = null;
  // 圆形视频原地播放的开关，逐条独立。
  @State private videoNotePlaying: boolean = false;
  // Chat's currently active video chat, if any (0 = none live) — lets a
  // "started" system pill know whether it's still tappable, and supplies the
  // id to hand off on tap. Sourced from ChatPage's existing updateChatVideoChat
  // subscription (see liveGroupCallId there) rather than re-subscribing here.
  @Prop liveGroupCallId: number = 0;
  onLiveStreamTap: (groupCallId: number) => void = (): void => {};
  // Live arrival: slide the bubble in from below (never set for history rows).
  @Prop animateIn: boolean = false;
  // 聊天设置 → 消息字号 / 消息圆角, applied live.
  @StorageProp(KEY_TEXT_SIZE) msgTextSize: number = TEXT_SIZE_DEFAULT;
  @StorageProp(KEY_BUBBLE_RADIUS) bubbleRadius: number = RADIUS_DEFAULT;
  @StorageProp(KEY_REDUCE_ANIM) @Watch('onPlaybackPolicyChanged') reduceAnim: boolean = false;
  @StorageProp(KEY_POWER_ACTIVE) @Watch('onPlaybackPolicyChanged') powerSaving: boolean = false;
  @StorageProp('appIsForeground') appIsForeground: boolean = true;
  @StorageProp(KEY_POWER_CHAT_EFFECTS) chatEffectsEnabled: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_MESSAGE) messageEffectsEnabled: boolean = true;
  @StorageProp(KEY_POWER_EFFECT_REACTION) reactionEffectsEnabled: boolean = false;
  @StorageProp(KEY_POWER_EMOJI) emojiEnabled: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_CHAT) emojiChatEnabled: boolean = true;
  @StorageProp(KEY_POWER_EMOJI_REACTIONS) emojiReactionsEnabled: boolean = true;
  @StorageProp(KEY_POWER_STICKERS) stickersEnabled: boolean = true;
  @StorageProp(KEY_POWER_STICKER_AUTOPLAY) stickerAutoplay: boolean = true;
  @StorageProp(KEY_POWER_AUTOPLAY_GIF) @Watch('onPlaybackPolicyChanged') autoplayGif: boolean = true;
  @Prop showAvatar: boolean = true;     // last row of a same-sender run
  @Prop showSenderName: boolean = true; // first row of a same-sender run
  @State mediaVisible: boolean = true;
  @State stickerPlaybackFailed: boolean = false;
  @State linkPreviewOpening: boolean = false;
  // Controlled context-menu presentation — mirrors ChatRow's bubble-lift preview
  // (see ChatRow.ets bindContextMenu) so long-pressing a message bubble gets the
  // same lift/scale animation as long-pressing a chat-list row.
  @State private msgContextMenuShown: boolean = false;
  // Swipe-to-reply: live horizontal offset (vp, always <= 0 — the bubble only
  // drags leftward) applied as a translate on the bubble container while
  // dragging, then sprung back to 0 on release. onReplyTo fires once the drag
  // clears SWIPE_REPLY_TRIGGER; it never fires mid-drag.
  @State private swipeReplyX: number = 0;
  // 这一次触摸已经被左滑或长按认领了。认领之后抬手时的点击必须吞掉，否则
  // 手指从一张图片上划走、或在链接上长按出多选，松手时那张图/那个链接还会
  // 被"点"一下。普通字段而不是 @State：没有任何界面依赖它。
  private gestureClaimed: boolean = false;
  // 播放位竞选用的中心 y（vp）。只在 onAreaChange 回调里写、onVisibleAreaApproximateChange
  // 回调里读，不参与 build() —— 用普通字段而非 @State，避免每帧 onAreaChange 触发重建。
  private mediaCenterY: number = 0;
  // 相册九宫格每格各自的中心 y，key 为 cell.idx。同样是普通 Map，不驱动刷新。
  private albumCellCenterY: Map<number, number> = new Map<number, number>();
  // 上一次已知的「整条消息是否参与竞选」状态，供 onMsgPropChanged 判断翻转。
  // 普通字段而非 @State：只在 @Watch 回调里读写，不参与 build()。
  private wasCompetingVideo: boolean = false;
  // 上一次已知的「相册第 idx 格是否参与竞选」状态，key 为 cell.idx。同样是普通 Map。
  private albumWasCompetingVideo: Map<number, boolean> = new Map<number, boolean>();

  // 见 menuKeyboardH 的说明。窗口矮的判据取 480vp：正常手机竖屏远大于此，悬浮
  // 小窗和分屏下半截才会落到这一档。
  private compactMenuContext(): boolean {
    return this.menuKeyboardH > 0 || this.menuWindowH < 480;
  }

  private isCompetingVideo(): boolean {
    return this.msg.contentType === 'video' && !this.msg.isAnimation;
  }

  private attachMessageChannels(message: MessageEntry): void {
    this.detachMessageChannels();
    // 发送状态不在行 key 里，行不会因为它重建——图标得自己订阅自己更新。
    // 与 LiveThumbImage / LiveProgressRing 同一套办法；先读通道现值，没有
    // 才用 @Prop 带来的初值（滚回历史消息时不会有新的发布）。
    const known: string = sendStateFor(message.rowId);
    this.liveSendState = known !== '' ? known : message.sendState;
    this.unsubSendState = subscribeSendState(message.rowId, (state: string): void => {
      this.liveSendState = state;
    });
    // 「翻译中 / 翻译失败」是瞬时态，不进行 key（见 translationChannel），
    // 所以行不会因为它们重建——这里自己订阅自己更新。
    this.translationStatus = translationStatusFor(message.id);
    this.unsubTranslation = subscribeTranslationStatus(message.id,
      (next: TranslationStatus | null): void => { this.translationStatus = next; });
    this.livePhotoProgress = progressForOr(message.photoFileId, message.photoProgress);
    this.liveLinkPhotoProgress = progressForOr(
      message.linkPhotoFileId, message.linkPhotoProgress);
    this.liveVideoProgress = progressForOr(message.videoFileId, message.videoProgress);
    this.liveStickerProgress = progressForOr(message.stickerFileId, message.stickerProgress);
    if (message.photoFileId !== 0) {
      this.unsubPhotoProgress = subscribeProgress(message.photoFileId,
        (percent: number): void => { this.livePhotoProgress = percent; });
    }
    if (message.linkPhotoFileId !== 0) {
      this.unsubLinkPhotoProgress = subscribeProgress(message.linkPhotoFileId,
        (percent: number): void => { this.liveLinkPhotoProgress = percent; });
    }
    if (message.videoFileId !== 0) {
      this.unsubVideoProgress = subscribeProgress(message.videoFileId,
        (percent: number): void => { this.liveVideoProgress = percent; });
    }
    if (message.stickerFileId !== 0) {
      this.unsubStickerProgress = subscribeProgress(message.stickerFileId,
        (percent: number): void => { this.liveStickerProgress = percent; });
    }
    // 记下这套订阅挂在哪条消息上，供 onMsgPropChanged 判断是否需要重挂（P0-4）。
    this.attachedRowId = message.rowId;
  }

  private detachMessageChannels(): void {
    if (this.unsubSendState !== null) {
      this.unsubSendState();
      this.unsubSendState = null;
    }
    if (this.unsubTranslation !== null) {
      this.unsubTranslation();
      this.unsubTranslation = null;
    }
    if (this.unsubPhotoProgress !== null) {
      this.unsubPhotoProgress();
      this.unsubPhotoProgress = null;
    }
    if (this.unsubLinkPhotoProgress !== null) {
      this.unsubLinkPhotoProgress();
      this.unsubLinkPhotoProgress = null;
    }
    if (this.unsubVideoProgress !== null) {
      this.unsubVideoProgress();
      this.unsubVideoProgress = null;
    }
    if (this.unsubStickerProgress !== null) {
      this.unsubStickerProgress();
      this.unsubStickerProgress = null;
    }
    this.attachedRowId = 0;
  }

  // P0-3（审计 3.3）：把「清」和「拿新值」拆开。这一半是 A 类 16 个 @State
  // 加四个普通字段/Map，全部是本行自己量出来或点出来的瞬态值，**不依赖任何
  // 新参数**，所以它必须能在 aboutToReuse 的 params 判断之前无条件执行，并且
  // 在 aboutToRecycle 里执行同一份。原来它只挂在 params 拿得到这个假设上，
  // 一旦走兜底分支，这 16 个值会以上一条消息的取值渲染一帧（剧透已揭开、
  // 引用已展开、圆形视频在播、气泡宽度是别人的）。
  private clearTransientState(): void {
    // onAreaChange 量出来的尺寸；新消息若不再显示某个标签，那个节点不会重新
    // 触发 onAreaChange，旧值会一直留着（见 forwardLabelW 声明处的注释）。
    this.bubbleW = 0;
    this.menuOffsetX = 0;
    this.forwardLabelW = 0;
    this.senderLabelW = 0;
    this.commentsRowW = 0;
    // key 由本条消息的文本段算出，换消息后旧 key 可能碰撞 → 新消息的剧透
    // 直接就是揭开的、引用直接就是展开的。
    this.revealedSpoilerKeys = [];
    this.expandedQuoteKeys = [];
    this.mediaVisible = true;
    this.stickerPlaybackFailed = false;
    this.linkPreviewOpening = false;
    this.msgContextMenuShown = false;
    this.swipeReplyX = 0;
    this.gestureClaimed = false;
    this.mediaCenterY = 0;
    this.albumCellCenterY.clear();
    this.albumWasCompetingVideo.clear();
    // M-1：按 P0-3 的判据（不依赖新参数就该无条件清）归到这里。清成 false 是
    // 安全方向——它只用于「从参与竞选翻到不参与」的一次性补报，false 起步最多
    // 少报一次，不会误报。拿得到新消息时 resetReusedState 会立刻覆盖成真值。
    this.wasCompetingVideo = false;
    this.videoNotePlaying = false;
    // 玻璃层的尺寸是量出来的：复用成另一条消息后，旧尺寸算出的裁剪路径是错的，
    // 清零等这一帧的 onAreaChange 重新给。onScreen 回到 true 的理由同它的声明处。
    this.glassW = 0;
    this.glassH = 0;
    this.onScreen = true;
  }

  // C 类 6 个通道值（审计 3.2a）。它们同样不依赖新参数：清零最多空一帧，不清
  // 则会用上一条消息的「发送中/已读」勾和下载百分比去渲染新消息。重新挂订阅
  // 时 attachMessageChannels 会立刻重播种，所以这里放心清。
  private clearChannelValues(): void {
    this.liveSendState = '';
    this.translationStatus = null;
    this.livePhotoProgress = 0;
    this.liveLinkPhotoProgress = 0;
    this.liveVideoProgress = 0;
    this.liveStickerProgress = 0;
  }

  // 剩下的两条是**依赖新参数**的，只能在拿得到新消息时做。
  // 前提：调用方必须已经跑过 clearTransientState()。两个调用点都在
  // aboutToReuse 里，而它开头就无条件跑了那一份（I-4：这里再跑一次是纯重复，
  // 每复用一行多约 20 次 @State 写入，就在滚动热路径上）。
  private resetReusedState(next: MessageEntry): void {
    this.labelWidthRowId = next.rowId;
    this.wasCompetingVideo = next.contentType === 'video' && !next.isAnimation;
  }

  aboutToAppear(): void {
    this.attachMessageChannels(this.msg);
    this.requestAutoplayDownload();
    // 只记录初始状态，不在这里上报——上报的语义是「不再参与竞选」，首次挂载时
    // 谈不上「不再」。真正的上报发生在 aboutToDisappear（组件销毁）和
    // onMsgPropChanged / onAlbumIsVideoChanged（同一组件原地翻转）两条路径上。
    this.wasCompetingVideo = this.isCompetingVideo();
    for (let i = 0; i < this.albumIsVideo.length; i++) {
      this.albumWasCompetingVideo.set(i, this.albumIsVideoAt(i));
    }
  }

  aboutToDisappear(): void {
    this.detachMessageChannels();
    this.reportCompetingMediaGone();
  }

  private reportCompetingMediaGone(): void {
    // LazyForEach 回收组件时若不上报，候选表里会留下永远不消失的幽灵条目。
    if (this.isCompetingVideo()) {
      this.onMediaGone(this.msg.id, -1);
    }
    for (let i = 0; i < this.albumIsVideo.length; i++) {
      if (this.albumIsVideoAt(i)) {
        this.onMediaGone(this.albumMemberIdAt(i), i);
      }
    }
  }

  // Keep this cleanup defensive in case the component is hosted by a reusable
  // parent elsewhere. ChatPage itself currently does not use that path.
  aboutToRecycle(): void {
    // ── 复用钩子证据探针（F-5，**临时**，删除清单见本函数下方）─────────
    //
    // 这是整条复用链路上唯一还**没有任何运行时证据**的一环。
    // util/reuseParams.ets 的文件头处理的是「params 取不到」，但更坏的一支
    // 没人处理过：官方《@ReusableV2装饰器》只写「递归地调用所有子组件的
    // aboutToReuse 回调（即使子组件未被标记可复用）」，**没写清递归到 V1 子
    // 组件时到底走不走**。本组件是 V1，挂在 @ReusableV2 的 ReusableMessageBubble
    // 之下。
    //
    // 后果是不对称的：下面的 clearTransientState() 清 16 项（剧透揭开态
    // revealedSpoilerKeys、引用展开态 expandedQuoteKeys、glassW/glassH、
    // swipeReplyX、mediaVisible 等），而唯一的自愈路径 onMsgPropChanged 只补
    // 三项。钩子不触发 ⇒ 复用出来的行带着上一条消息的剧透已揭开、引用已展开、
    // 错误的玻璃裁剪尺寸。
    //
    // 而支撑「钩子会触发」的那 820 个复用样本是 **P2 时期父级还是 V1
    // @Reusable** 时采的（探针已在 ad3d4ab 下架），对当前形态**没有证据力**。
    //
    // 用 util/panelProbe 的聚合探针：只累加计数，每秒吐一行汇总，静止时一行
    // 都不打，代价可忽略。上机判读：
    //   recycle / reuse 两个计数都在涨 ⇒ 递归到 V1 子组件成立，本探针可删；
    //   recycle 在涨、reuse 恒为 0     ⇒ 钩子**不触发**，clearTransientState
    //                                    的 16 项必须换成 onMsgPropChanged
    //                                    那条按 rowId 的自愈路径补全；
    //   两个都恒为 0                   ⇒ 这一层根本没被回收（Repeat 的
    //                                    reusable:false 之下由 @ReusableV2 承担
    //                                    复用），回头查全局池的分桶计数。
    probeHit('msgBubble.recycle');
    this.detachMessageChannels();
    this.reportCompetingMediaGone();
    // 和 aboutToReuse 用同一份清理（P0-3 + 3.2a）：组件躺进复用池之前就把
    // A 类 16 个和 6 个通道值全部归零，别让它带着上一条消息的剧透揭开态、
    // 引用展开态、发送勾和下载百分比等下一次复用。
    // （原来这里只清了 translationStatus 和 msgContextMenuShown 两个，
    //   两者现在分别被 clearChannelValues / clearTransientState 覆盖。）
    this.clearTransientState();
    this.clearChannelValues();
  }

  // ── F-5 探针删除清单（判读完成后一次删干净）────────────────────────
  //   1. 本文件里的三处 probeHit（'msgBubble.recycle' / 'msgBubble.reuse' /
  //      'msgBubble.reuse.noParams'）及其上面这两段说明；
  //   2. 本文件顶部 `import { probeHit } from '../../util/panelProbe';`；
  //   3. util/panelProbe.ets 本身——**只有在贴纸面板那轮标定也结束时才删**，
  //      它是共用的（见该文件头「定位完整体删除」）。
  aboutToReuse(params: Record<string, Object>): void {
    probeHit('msgBubble.reuse');
    // 无条件前置（审计 S1 / P0-3）：不依赖新参数的清理跑在 params 判断之前。
    // 父级**已经是** @ReusableV2（P3 批 1），aboutToReuse 没有入参，下面的
    // setTimeout **已经是**唯一分支——这两行依然成立，最差是「空一帧」，
    // 不会是「别人的一帧」。
    // params 是 {} 还是 undefined 未定，两种都用 reuseParam 读，见
    // util/reuseParams.ets（P3 批 2 第 0 项）。
    this.clearTransientState();
    this.clearChannelValues();
    const next: MessageEntry | undefined =
      reuseParam(params, 'msg') as MessageEntry | undefined;
    if (next === undefined) {
      // **实测（2026-08-26 真机，820 个复用样本，P2-1 探针，已下架）**：
      // params 恒带 msg，present=0 一次都没出现——这条兜底分支当前**不可达**。
      // **推导（不是实测）**：仍然不能删（I-3）。复用回同一条消息时 @Prop msg
      // 没变化 → onMsgPropChanged 不触发 → P0-4 那条自愈也不跑；而
      // aboutToRecycle 已经退订并把 attachedRowId 归零，那时这里是唯一的重挂
      // 路径。父级**已经是** @ReusableV2（P3 批 1），aboutToReuse 没有入参，
      // 这条**已经是**唯一分支。
      // 这一支在 P2 的 820 个样本里一次都没出现过，但那份样本对当前形态没有
      // 证据力（见 aboutToRecycle 的说明）。单独计数，好和总数对账。
      probeHit('msgBubble.reuse.noParams');
      setTimeout((): void => {
        this.resetReusedState(this.msg);
        this.attachMessageChannels(this.msg);
        this.requestAutoplayDownload();
      }, 0);
      return;
    }
    this.resetReusedState(next);
    this.attachMessageChannels(next);
    const nextAlbum: boolean[] | undefined =
      reuseParam(params, 'albumIsVideo') as boolean[] | undefined;
    if (nextAlbum !== undefined) {
      for (let i = 0; i < nextAlbum.length; i++) {
        this.albumWasCompetingVideo.set(i, nextAlbum[i]);
      }
    }
    setTimeout((): void => { this.requestAutoplayDownload(); }, 0);
  }

  // "替换媒体"（约 1511 行附近的菜单项）能在同一条消息 id 上把 contentType 从
  // video 改成 photo；组件按 messageId 复用、不会走 aboutToDisappear，所以那次
  // 上报的「静默停止」不够——候选表里旧的可见比例记录还在，播放位可能锁定一个
  // 已经不是视频的气泡。这里在 @Prop msg 每次被 ChatPage 换成新对象时（编辑、
  // 状态变化、替换媒体等，不是每帧）比较一次「参与竞选」状态，只在从 true 翻到
  // false 的那一次补发 onMediaGone，翻转之外什么也不做。
  private onMsgPropChanged(): void {
    if (this.msg.rowId !== this.labelWidthRowId) {
      this.labelWidthRowId = this.msg.rowId;
      this.forwardLabelW = 0;
      this.senderLabelW = 0;
      this.commentsRowW = 0;
    }
    // P0-4（审计 3.2b）：按「订阅挂在哪个 rowId 上」自愈——不一致就整套重挂。
    // 担心的是 aboutToReuse 把 6 个通道挂在上一条消息的 rowId / fileId 上而
    // 后续无人纠正（审计当时无法静态排除这一点）。
    //
    // **实测（2026-08-26 真机，820 个复用样本，P2-1 探针，已下架）**：
    // aboutToReuse 执行时 params 与 @Prop msg **都已经是新消息的数据**，两者
    // 从未不一致，present=0 从未出现。所以在**当前调用图**下这段自愈是
    // **防御性**的，不是在修一个正在发生的 bug。
    //
    // **但不要因为「现在用不上」把它删掉。** @ReusableV2 的 aboutToReuse
    // 没有入参（审计 C2），迁 V2 之后 params 恒空，这套按 rowId 的自愈就是
    // 唯一依靠。它也让本组件和 LightweightPlainTextBubble.onMessageChanged /
    // ReusableMessageBubble.onGroupChanged 拉平。
    // 重挂本身带重播种，下面几行只对 rowId 未变的真·原地更新起作用（幂等）。
    if (this.msg.rowId !== this.attachedRowId) {
      this.attachMessageChannels(this.msg);
    }
    const known: string = sendStateFor(this.msg.rowId);
    this.liveSendState = known !== '' ? known : this.msg.sendState;
    this.livePhotoProgress = progressForOr(this.msg.photoFileId, this.msg.photoProgress);
    this.liveLinkPhotoProgress = progressForOr(
      this.msg.linkPhotoFileId, this.msg.linkPhotoProgress);
    this.liveVideoProgress = progressForOr(this.msg.videoFileId, this.msg.videoProgress);
    this.liveStickerProgress = progressForOr(this.msg.stickerFileId, this.msg.stickerProgress);
    const competing = this.isCompetingVideo();
    if (this.wasCompetingVideo && !competing) {
      this.onMediaGone(this.msg.id, -1);
    }
    this.wasCompetingVideo = competing;
  }

  // 同样的翻转检测，作用在相册每一格上：某格从「是视频」变成「不是视频」时补发
  // 一次 onMediaGone，只在那一次触发，不逐帧触发。
  private onAlbumIsVideoChanged(): void {
    for (let i = 0; i < this.albumIsVideo.length; i++) {
      const isVideo = this.albumIsVideoAt(i);
      const wasVideo = this.albumWasCompetingVideo.get(i) ?? false;
      if (wasVideo && !isVideo) {
        this.onMediaGone(this.albumMemberIdAt(i), i);
      }
      this.albumWasCompetingVideo.set(i, isVideo);
    }
  }

  // Everything this row shows has to be re-seeded here.
  //
  // Two separate hazards. First, undecorated members are NOT updated when a
  // component is reused (albumCaptionEntities is the only one that carries
  // data; the on* callbacks are page-level closures keyed by messageId, so a
  // stale one still does the right thing). Second, this component's own @State
  // is per-message — a reused bubble would otherwise inherit the previous
  // message's revealed spoilers, expanded quotes, playing video note or failed
  // sticker. Both are silent wrong-content bugs rather than crashes, so the
  // reset is exhaustive on purpose.
  private requestAutoplayDownload(): void {
    if (this.msg.contentType !== 'video' || this.msg.videoFileId === 0 ||
      this.msg.videoPath !== '' || this.msg.videoFailed || !this.mediaVisible) {
      return;
    }
    // 普通视频：可见不等于要看。整文件下载改由「点开」或二期的播放位触发，
    // 这里只放行 GIF/动图 —— 它们体积小且要无限循环，仍走整文件路径。
    if (!this.msg.isAnimation) {
      return;
    }
    if ((this.autoplayGif && !this.powerSaving && !this.reduceAnim) || this.animationForcePlay) {
      this.onAutoplayVideoNeedDownload(this.msg.id);
    }
  }

  private onPlaybackPolicyChanged(): void {
    this.requestAutoplayDownload();
  }

  // mm:ss (or h:mm:ss for long videos) duration badge text.
  private formatDuration(totalSeconds: number): string {
    const safeSeconds = Math.max(0, Math.floor(totalSeconds));
    const h = Math.floor(safeSeconds / 3600);
    const m = Math.floor((safeSeconds % 3600) / 60);
    const s = safeSeconds % 60;
    const mm = h > 0 ? `${m}`.padStart(2, '0') : `${m}`;
    const ss = `${s}`.padStart(2, '0');
    return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  // Keep all shell/content measurements on the same concrete cap. A percentage
  // max width on the outer shrink-to-fit Column can resolve differently from
  // the numeric caps used by text/media and cause a late first-layout reflow.
  private bubbleMaxW(): number {
    return bubbleMaxWidth(this.screenW);
  }

  private inlineMaxW(): number {
    return this.bubbleMaxW() - 16;
  }

  private runCornerRadius(): number {
    return Math.min(this.bubbleRadius, 7);
  }

  private tailCornerRadius(): number {
    return Math.min(this.bubbleRadius, 2);
  }

  // A tail belongs only to the final bubble of a consecutive sender run.
  // showAvatar is the run-end flag for private chats too, even when no avatar
  // column is rendered there.
  private hasBubbleTail(): boolean {
    return this.showAvatar && !this.isBareEmoji();
  }

  // 头像和气泡之间那 7vp。有尾巴的行由三角 Polygon 占掉（宽 8、右边距 -1），
  // 没尾巴的行垫一个等宽的空 Column，一个发送者连发多条时左边缘才不会跳。
  //
  // 贴纸/大表情/视频消息曾经不占这一槽——它们没有气泡，看着"不需要留位"。
  // 但这一槽的作用是**横向对齐**，和有没有气泡无关：不占就比上下的文字气泡
  // 整整左移 7vp，正是 issue #81 里那条歪掉的贴纸。
  private bubbleTailGutter(): number {
    return 7;
  }

  private rowTopPadding(): number {
    return this.showSenderName ? 3 : 1;
  }

  private rowBottomPadding(): number {
    return this.showAvatar ? 3 : 1;
  }

  private effectDuration(duration: number): number {
    return animationDurationFor(
      this.chatEffectsEnabled && this.messageEffectsEnabled && !this.powerSaving,
      scrollActiveNow(), duration);
  }

  // 不吃滑动门控的时长。用于**参数在 build 之后才被消费**的动画：行内链接药丸
  // 按下态的 stateStyles 过渡、以及它 iterations:-1 的循环忙态。滑动中渲染的那
  // 一帧会把时长固定成 0，而这类动画在那之后才播——结果是滑动停下后按链接没有
  // 过渡、循环胶囊永久静止。滑动中本来也按不到，门控它们收益为零。
  // 气泡根节点已经不再使用它：那里现在完全不挂常驻动画（见 build 里的注释）。
  private persistentEffectDuration(duration: number): number {
    return persistentAnimationDurationFor(
      this.chatEffectsEnabled, this.messageEffectsEnabled, this.powerSaving, duration);
  }

  private reactionDuration(duration: number): number {
    return animationDurationFor(
      this.chatEffectsEnabled && this.reactionEffectsEnabled &&
        this.emojiEnabled && this.emojiReactionsEnabled && !this.powerSaving,
      scrollActiveNow(), duration);
  }

  // Swipe-to-reply's snap-back/settle animation — degrades to an instant jump
  // under 省电模式/减少动效, matching the rest of the bubble's motion gating.
  private swipeReplyDuration(duration: number): number {
    return this.powerSaving || this.reduceAnim ? 0 : duration;
  }

  // 长按干什么由方案决定：老交互出菜单，新交互直接进多选并选中这一条。
  // 两者互斥（messageGesturePolicy 的测试钉着这一点），不会同时发生。
  // 记下这次触摸落在气泡内的水平位置，换算成相对中心的偏移。
  //
  // 用**局部坐标**（localX，相对气泡左上角）而不是窗口坐标：要的就是"手指偏离
  // 气泡中心多远"，局部坐标直接给出这个量，不必再去查气泡在窗口里的绝对位置——
  // 那在分栏、滚动、软键盘顶起的情况下都要重新算，多一处出错的地方。
  //
  // 只动 x：y 方向的关系（菜单贴在被抬起的气泡下方）是抬起预览的一部分，动它
  // 会和 ArkUI 的预览布局打架。
  private recordMenuOffset(localX: number): void {
    const w: number = this.bubbleW;
    // 首帧还没量到宽度时不猜，用 0 退化成原来的居中行为。
    this.menuOffsetX = w > 0 ? localX - w / 2 : 0;
  }

  private onLongPress(event: GestureEvent): void {
    // issue #114 诊断：小窗 + 键盘展开时长按调不出菜单。手势有没有到、走的哪一
    // 支、当时窗口和键盘多高、预览模式取哪种——报告人导日志就能对上。
    logW(`[Menu114] longPress id=${this.msg.id} scheme=${this.gestureScheme}`
      + ` kbd=${Math.round(this.menuKeyboardH)} winH=${Math.round(this.menuWindowH)}`
      + ` compact=${this.compactMenuContext()} liveVideo=${this.hasLiveVideoSurface()}`
      + ` shown=${this.msgContextMenuShown}`);
    const fingers = event.fingerList;
    if (fingers.length > 0) {
      this.recordMenuOffset(fingers[0].localX);
    }
    this.gestureClaimed = true;
    const policy: MessageGesturePolicy = messageGesturePolicy(this.gestureScheme);
    if (policy.longPressOpensMenu) {
      this.msgContextMenuShown = true;
      return;
    }
    if (policy.longPressSelects) {
      this.onSelectMsg(this.albumMemberIds);
    }
  }

  private swipeReplyEligible(): boolean {
    // System/hidden rows carry no replyable message; editing owns the
    // reply/edit strip below and must not fight a concurrent swipe.
    return !this.editingActive && this.msg.contentType !== 'system' && this.msg.contentType !== 'hidden';
  }

  private onSwipeReplyUpdate(offsetX: number): void {
    if (!this.swipeReplyEligible()) {
      return;
    }
    // Leftward-only, clamped to SWIPE_REPLY_MAX (both negative).
    this.swipeReplyX = Math.max(SWIPE_REPLY_MAX, Math.min(0, offsetX));
    // 真的滑动起来了才算认领。PanGesture 的 distance 已经是 8，这里再确认
    // 一次位移，避免"手指抖了一下"就把一次正常点击吃掉。
    if (this.swipeReplyX < 0) {
      this.gestureClaimed = true;
    }
  }

  private onSwipeReplyEnd(): void {
    const triggered: boolean = this.swipeReplyEligible() && this.swipeReplyX <= SWIPE_REPLY_TRIGGER;
    animateTo({ duration: this.swipeReplyDuration(180), curve: Curve.EaseOut }, (): void => {
      this.swipeReplyX = 0;
    });
    if (triggered) {
      this.onReplyTo(this.msg.id);
    }
  }

  // Keep the bubble's own colors intact and dim the whole surface while held.
  // ArkUI's pressed state also cancels naturally when a list drag takes over.
  @Styles
  bubbleNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  bubblePressedStyle() {
    // A tappable inline Span owns its own pressed feedback. Letting the parent
    // bubble dim as well makes a tiny link tap flash the whole message. Voice
    // controls also provide their own compact pressed feedback.
    .opacity(this.hasInlineLink() || this.hasLinkPreview() || this.msg.contentType === 'voice' ||
      this.msg.contentType === 'audio' || this.msg.contentType === 'file' ? 1 : 0.84)
    .scale({
      x: this.hasInlineLink() || this.hasLinkPreview() || this.msg.contentType === 'voice' ||
        this.msg.contentType === 'audio' || this.msg.contentType === 'file' ? 1 : 0.992,
      y: this.hasInlineLink() || this.hasLinkPreview() || this.msg.contentType === 'voice' ||
        this.msg.contentType === 'audio' || this.msg.contentType === 'file' ? 1 : 0.992
    })
  }

  @Styles
  linkCardNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  linkCardPressedStyle() {
    .opacity(0.8)
    .scale({ x: 0.986, y: 0.986 })
  }

  // 链接底色。忙碌时换成 select_highlight——一层带透明度的主色调，浅色深色
  // 两套资源都已经定好，也不会被自定义强调色带跑。代码体的链接本来就有底色，
  // 忙碌时同样切到高亮色，才看得出变化。
  private linkRunBackground(run: RichRun): ResourceColor {
    if (this.linkNavBusyUrl === run.url) {
      return $r('app.color.select_highlight');
    }
    return run.code ? $r('app.color.surface_alt') : Color.Transparent;
  }

  @Styles
  linkRunNormalStyle() {
    .opacity(1)
  }

  @Styles
  linkRunPressedStyle() {
    .opacity(0.52)
  }

  @Styles
  botButtonNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  botButtonPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.975, y: 0.975 })
  }

  @Styles
  systemPillNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  systemPillPressedStyle() {
    .opacity(this.liveVideoChatTappable() ? 0.72 : 1)
    .scale({
      x: this.liveVideoChatTappable() ? 0.985 : 1,
      y: this.liveVideoChatTappable() ? 0.985 : 1
    })
  }

  @Styles
  menuActionNormalStyle() {
    .opacity(1)
    .scale({ x: 1, y: 1 })
  }

  @Styles
  menuActionPressedStyle() {
    .opacity(0.72)
    .scale({ x: 0.97, y: 0.94 })
  }

  // albumIndex -1 表示非相册整条消息；相册格子传该格自己在 albumMemberIds
  // 里的下标（与上报给 PlaySlotRegistry 的 key 一致，见 onMediaRatio）。
  // 排除 isAnimation：onVisibleAreaApproximateChange 只在"视频→动图"翻转时
  // 停止上报新的 ratio，不会追溯撤回已经选中的候选，所以消息对象翻转的那
  // 一帧 playSlotKey 可能还没跟着变——这里兜一道，不让动图错挂流式播放器。
  private isPlaySlot(albumIndex: number): boolean {
    return this.playSlotKey !== '' && !this.msg.isAnimation &&
      this.playSlotKey === slotKey(this.msg.id, albumIndex);
  }

  // 普通视频的播放已经交给播放位机制（isPlaySlot → VideoBubbleSurface 分片流
  // 式播放），这里只剩动图（GIF）走整文件下载 + 循环播放（SmartLoopVideo）。
  // 圆形视频消息（videoNote）走的是另一条独立分支，不受这里影响。
  private autoplayInlineVideo(): boolean {
    if (this.msg.contentType !== 'video' || !this.msg.isAnimation || this.msg.videoPath === '' ||
      !this.mediaVisible || !this.appIsForeground || this.animationPlaybackFailed) {
      return false;
    }
    if (this.animationPaused) {
      return false;
    }
    return this.animationForcePlay || (!this.powerSaving && !this.reduceAnim && this.autoplayGif);
  }

  private autoplayCategory(): string {
    return this.msg.isAnimation ? 'gif' : 'video';
  }

  private animationDownloadExpected(): boolean {
    return this.msg.isAnimation && this.msg.videoFileId !== 0 &&
      this.msg.videoPath === '' && !this.msg.videoFailed &&
      (this.animationForcePlay || (!this.powerSaving && !this.reduceAnim && this.autoplayGif));
  }

  // The link preview card adds its own 8+8 horizontal padding on top of the
  // bubble's, so content inside it needs a narrower cap than inlineMaxW().
  private cardMaxW(): number {
    return this.inlineMaxW() - 16;
  }

  private mediaThumbW(): number {
    return mediaThumbWidth(this.screenW);
  }

  private mediaMaxH(): number {
    return this.mediaThumbW() * MEDIA_MAX_HEIGHT_RATIO;
  }

  private mediaRatio(): number {
    if (this.msg.photoWidth > 0 && this.msg.photoHeight > 0) {
      // Extreme source ratios remain visible through Cover cropping without
      // producing an unusably narrow/tall chat bubble.
      return Math.max(0.56, Math.min(2.1, this.msg.photoWidth / this.msg.photoHeight));
    }
    // An unknown photo remains square; an unknown video starts at the common
    // 16:9 shape so its placeholder doesn't jump from square once decoded.
    return this.msg.contentType === 'video' ? 16 / 9 : 1;
  }

  private videoFileUnavailable(): boolean {
    return this.msg.contentType === 'video' &&
      this.msg.videoFileId === 0 && this.msg.videoPath === '';
  }

  private videoDownloadActive(): boolean {
    return this.msg.videoPath === '' &&
      this.liveVideoProgress > 0 && this.liveVideoProgress < 100;
  }

  private videoMetaText(): string {
    if (this.msg.isAnimation) {
      return this.msg.videoDuration > 0
        ? `GIF · ${this.formatDuration(this.msg.videoDuration)}`
        : 'GIF';
    }
    // 时长和大小一起显示（issue #93）：只有时长时看不出这条视频要下多少。
    const size: string = this.msg.videoFileSize > 0 ? formatFileSize(this.msg.videoFileSize) : '';
    if (this.msg.videoDuration > 0) {
      const duration: string = this.formatDuration(this.msg.videoDuration);
      return size !== '' ? `${duration} · ${size}` : duration;
    }
    return size;
  }

  private videoAccessibilityText(): string {
    if (this.msg.isAnimation) {
      if (this.videoFileUnavailable()) {
        return str('mb_gif_unavailable');
      }
      if (this.msg.videoFailed || this.animationPlaybackFailed) {
        return str('mb_gif_failed');
      }
      if (this.videoDownloadActive() || this.animationDownloadExpected()) {
        return this.liveVideoProgress > 0
          ? str('mb_gif_downloaded_pct', this.liveVideoProgress)
          : str('mb_gif_loading');
      }
      return this.autoplayInlineVideo() ? str('mb_gif_playing') : str('mb_gif_paused');
    }
    if (this.videoFileUnavailable()) {
      return str('mb_video_unavailable');
    }
    if (this.msg.videoFailed) {
      return str('mb_video_failed');
    }
    if (this.videoDownloadActive()) {
      return str('mb_video_downloaded_pct', this.liveVideoProgress);
    }
    if (this.msg.photoFailed) {
      return str('mb_video_cover_failed');
    }
    return this.msg.videoDuration > 0
      ? str('mb_video_duration', this.formatDuration(this.msg.videoDuration))
      : str('mb_tap_play_video');
  }

  // Same helper the prefetcher uses — the two must agree exactly or the
  // prefetched bitmap lands under a key this bubble never asks for.
  private mediaBox(): MediaBox {
    return mediaBoxFor(this.screenW, this.msg.photoWidth, this.msg.photoHeight,
      this.msg.contentType === 'video');
  }

  private linkPreviewH(width: number = this.cardMaxW()): number {
    if (this.msg.linkPhotoWidth > 0 && this.msg.linkPhotoHeight > 0) {
      const ratio: number = Math.max(0.82,
        Math.min(1.92, this.msg.linkPhotoWidth / this.msg.linkPhotoHeight));
      return Math.max(108, Math.min(188, width / ratio));
    }
    return width * LINK_PREVIEW_HEIGHT_RATIO;
  }

  private hasLinkPreview(): boolean {
    return this.msg.linkUrl !== '' || this.msg.linkSiteName !== '' ||
      this.msg.linkTitle !== '' || this.msg.linkDescription !== '' ||
      this.msg.linkPhotoFileId !== 0;
  }

  private linkPresentation(): LinkPreviewPresentation {
    return linkPreviewPresentation(
      this.msg.linkUrl, this.msg.linkPreviewType, this.msg.linkSiteName);
  }

  private compactTelegramPreview(): boolean {
    const kind: string = this.linkPresentation().kind;
    return this.msg.linkPhotoFileId !== 0 &&
      (kind === 'telegramChat' || kind === 'telegramInvite');
  }

  private openOrRetryLinkPreview(): void {
    if (this.msg.linkPhotoFailed) {
      this.onLinkPreviewRetry(this.msg.id);
      return;
    }
    const presentation: LinkPreviewPresentation = this.linkPresentation();
    if (!presentation.actionable || this.linkPreviewOpening) {
      return;
    }
    this.linkPreviewOpening = true;
    this.onLinkTap(this.msg.linkUrl);
    setTimeout((): void => {
      this.linkPreviewOpening = false;
    }, 650);
  }

  private linkPreviewActionLabel(): string {
    if (this.msg.linkPhotoFailed) {
      return str('mb_reload_preview');
    }
    return this.linkPreviewOpening ? str('opening_dots') : this.linkPresentation().actionLabel;
  }

  private albumW(): number {
    return Math.min(ALBUM_MAX_WIDTH, this.inlineMaxW());
  }

  // Per-sender name color: the sender's Telegram accent color when known,
  // otherwise the avatar hash palette so name and avatar stay visually tied.
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
      SymbolGlyph($r(this.liveSendState === 'sending'
        ? 'sys.symbol.clock'
        : (this.liveSendState === 'failed'
          ? 'sys.symbol.exclamationmark_circle' : 'sys.symbol.checkmark')))
        .fontSize(12)
        .fontColor([this.liveSendState === 'failed' ? Color.Red
          : (this.liveSendState === 'read' ? this.accent() : COLOR_TEXT_SECONDARY)])
        .visibility(this.liveSendState === 'none' || this.liveSendState === ''
          ? Visibility.None : Visibility.Visible);
      // The second, overlapped check is present in every state and only shown
      // for read receipts, so reuse never creates or destroys it.
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(12).fontColor([this.accent()]).margin({ left: -8 })
        .visibility(this.liveSendState === 'read' ? Visibility.Visible : Visibility.None);
    }
  }

  private messageTimeText(): string {
    return formatClockTime(this.msg.date);
  }

  // Invisible tail appended to the last text line: reserves exactly the space
  // the overlaid timestamp occupies, so it never covers real text (Telegram's
  // inline-time layout).
  private timeReserve(): string {
    const editReserve = this.msg.editDate > 0 ? '         ' : '';
    return `${editReserve}  ${this.messageTimeText()}${this.msg.isOutgoing ? '   ' : ''}`;
  }

  // 点击：没下载好先触发下载（下载完成后 videoPath 到位，用户再点一次即可），
  // 已就绪则切换播放态。
  private toggleVideoNote(): void {
    if (this.msg.videoPath === '') {
      this.onVideoNoteDownload(this.msg.id);
      return;
    }
    this.videoNotePlaying = !this.videoNotePlaying;
  }

  private videoNoteDuration(): string {
    const total: number = Math.max(0, this.msg.videoDuration);
    const m: number = Math.floor(total / 60);
    const sec: number = total % 60;
    return `${m}:${`${sec}`.padStart(2, '0')}`;
  }

  private fallbackLabel(): string {
    const label = this.msg.placeholderLabel.trim();
    return label !== '' ? label : str('mb_unsupported');
  }

  private richRunDecoration(run: RichRun): TextDecorationType {
    if (run.strike) {
      return TextDecorationType.LineThrough;
    }
    return run.underline ? TextDecorationType.Underline : TextDecorationType.None;
  }

  private spoilerKey(run: RichRun): string {
    return `${run.offset}_${run.text.length}`;
  }

  private spoilerRevealed(run: RichRun): boolean {
    return this.revealedSpoilerKeys.indexOf(this.spoilerKey(run)) >= 0;
  }

  private revealSpoiler(run: RichRun): void {
    const key = this.spoilerKey(run);
    if (this.revealedSpoilerKeys.indexOf(key) < 0) {
      this.revealedSpoilerKeys = [...this.revealedSpoilerKeys, key];
    }
  }

  private quoteKey(segment: RichSegment): string {
    return `${segment.offset}_${segment.text.length}`;
  }

  private quoteExpanded(segment: RichSegment): boolean {
    return this.expandedQuoteKeys.indexOf(this.quoteKey(segment)) >= 0;
  }

  private toggleQuote(segment: RichSegment): void {
    const key = this.quoteKey(segment);
    if (this.quoteExpanded(segment)) {
      this.expandedQuoteKeys = this.expandedQuoteKeys.filter((item: string): boolean => item !== key);
    } else {
      this.expandedQuoteKeys = [...this.expandedQuoteKeys, key];
    }
  }

  private inlineCustomEmojiPath(customEmojiId: string): string {
    const idx = this.msg.inlineCustomEmojiIds.indexOf(customEmojiId);
    if (idx < 0 || idx >= this.msg.inlineCustomEmojiPaths.length) {
      return '';
    }
    return this.msg.inlineCustomEmojiPaths[idx];
  }

  private inlineCustomEmojiSource(customEmojiId: string): string {
    const path = this.inlineCustomEmojiPath(customEmojiId);
    return path.startsWith('/') ? `file://${path}` : path;
  }

  private codeTextSize(): number {
    return Math.max(12, this.msgTextSize - 2);
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
      (this.albumCaption !== '' &&
        this.formattedTextHasLink(this.albumCaption, this.albumCaptionEntities));
  }

  @Builder
  richInlineRun(run: RichRun) {
    // Spoiler masking has priority over every nested style, including custom
    // emoji. Otherwise an emoji inside a spoiler is visible before reveal.
    if (run.spoiler && !this.spoilerRevealed(run)) {
      Span(run.text)
        .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
        .fontFamily(run.code ? 'monospace' : '')
        .fontColor(Color.Transparent)
        .decoration({ type: this.richRunDecoration(run), color: Color.Transparent })
        .textBackgroundStyle({ color: '#708E8E93', radius: 3 })
        .animation({ duration: this.effectDuration(150), curve: Curve.EaseOut })
        .onClick((): void => {
          if (this.gestureClaimed) { return; }
          this.revealSpoiler(run); });
    } else if (run.customEmojiId !== '' && this.inlineCustomEmojiPath(run.customEmojiId) !== '') {
      ImageSpan(this.inlineCustomEmojiSource(run.customEmojiId))
        .width(this.msgTextSize + 3)
        .height(this.msgTextSize + 3)
        .verticalAlign(ImageSpanAlignment.CENTER)
        .objectFit(ImageFit.Contain);
    } else if (run.url !== '') {
      // 这一段被点中、正在向服务器问"这个链接该开哪一页"的时候，文字自己
      // 呼吸起来。链接是 Span，挂不了子组件也没有 opacity，能动的只有它自己
      // 的颜色和底色，所以加载态就画成一颗一明一暗的药丸。
      //
      // this.linkNavBusyUrl 只在这条分支里读：不含链接的气泡从头到尾不碰
      // 这个变量，也就不会因为别人点了链接而重建。
      Span(run.text)
        .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
        .fontFamily(run.code ? 'monospace' : '')
        .fontColor(this.accent())
        .decoration({ type: this.richRunDecoration(run), color: this.accent() })
        .textBackgroundStyle({
          color: this.linkRunBackground(run),
          radius: run.code || this.linkNavBusyUrl === run.url ? 3 : 0
        })
        // iterations: -1 + Alternate —— 一次状态变化就能永远来回，不需要
        // 定时器逐帧改状态（那会把整个气泡按帧重建）。省电模式下
        // effectDuration 归零，退化成一个静止的暗色药丸，仍然看得出在忙。
        .animation({
          duration: this.persistentEffectDuration(620),
          curve: Curve.EaseInOut,
          iterations: this.linkNavBusyUrl === run.url ? -1 : 1,
          playMode: PlayMode.Alternate
        })
        .stateStyles({
          normal: this.linkRunNormalStyle,
          pressed: this.linkRunPressedStyle
        })
        .animation({ duration: this.persistentEffectDuration(90), curve: Curve.EaseOut })
        .onClick(() => {
          if (this.gestureClaimed) { return; }
          this.onLinkTap(run.url); });
    } else {
      // 这里刻意不挂 .animation()：普通 run 是气泡里数量最多的节点，一条常驻
      // 属性动画会按 run 数线性放大更新开销。2026-08-27 11:57 的真机 trace 里，
      // 34 个 >20ms 的 CustomNodeUpdate 全部落在 MessageBubble 上；每次
      // ExecuteRerender 内串着 12–52 个 JSAnimation，每个都会同步 flush 一遍
      // FlushLayoutTask → Measure[List]/[ListItem]，单个 0.65–1.0ms。也就是
      // 更新开销 ≈ 气泡上 .animation() 修饰器个数 × 约 0.8ms 的同步重排。
      //
      // 别指望用 effectDuration() 在滑动时返回 0 来挡：duration:0 只是让视觉
      // 过渡瞬间完成，ArkUI 照样建 JSAnimation 上下文，同刷新周期的脏布局照样
      // 被同步 flush 进去（同一份 trace 里 duration:0 有 3932 个）。要省掉这笔
      // 开销，只能不写这个修饰器本身。
      Span(run.text)
        .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
        .fontFamily(run.code ? 'monospace' : '')
        .fontColor(run.link ? this.accent() : bubbleTextFor(this.msg.isOutgoing))
        .decoration({
          type: this.richRunDecoration(run),
          color: run.link ? this.accent() : bubbleTextFor(this.msg.isOutgoing)
        })
        .textBackgroundStyle({
          color: run.code ? $r('app.color.surface_alt') : Color.Transparent,
          radius: run.code ? 3 : 0
        });
    }
  }

  @Builder
  richRuns(runs: RichRun[], maxWidth: number, isLastSegment: boolean) {
    Text() {
      ForEach(runs, (r: RichRun) => {
        this.richInlineRun(r);
      }, (r: RichRun, i: number) => `run_${i}_${r.offset}_${r.text}`);
      if (this.timeReserveInText() && isLastSegment) {
        // fontSize 14 (not 11): when this reserve wraps onto its own line, the
        // taller line leaves a visible gap between the text and the timestamp.
        Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
      }
    }
    .fontSize(this.msgTextSize)
    .lineHeight(this.msgTextSize * 1.34)
    .wordBreak(WordBreak.BREAK_WORD)
    .constraintSize({ maxWidth });
  }

  // Common first-screen path: one Text node instead of
  // Column -> ForEach(segment) -> Text -> ForEach(run). The full renderer is
  // retained for links, formatting, replies, previews, translations and
  // reactions, so this changes layout work rather than message behaviour.
  private useDirectPlainText(): boolean {
    return this.msg.contentType === 'text' && this.albumPaths.length <= 1 &&
      this.msg.reactions.length === 0 && this.msg.translatedText === '' &&
      this.translationStatus === null &&
      !this.hasLinkPreview() &&
      isUnformattedPlainText(this.msg.text, this.msg.textEntities);
  }

  @Builder
  directPlainTextBody() {
    Text() {
      Span(this.msg.text).fontColor(bubbleTextFor(this.msg.isOutgoing));
      Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
    }
    .fontSize(this.msgTextSize)
    .lineHeight(this.msgTextSize * 1.34)
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

  // Render TDLib formatted text: inline bold/link runs, pre/code blocks and
  // blockquotes as gray boxes. maxWidth is the caller's available content
  // width (narrower inside nested cards like the link preview).
  //
  // 时间戳的尾部占位**不作为参数传进来**，而是在这里读 this.timeReserveInText()。
  //
  // 带多个参数的 @Builder，参数变化不会刷新它内部的 UI（官方《自定义构建函数》
  // 写明：按引用传递只在单参数时生效，多参数不支持刷新）。而这个占位恰恰是会
  // 翻转的：翻译开始时它移到状态行、翻译撤销时又该回到正文。作为参数传的话，
  // 翻转那一下正文不会重画，时间戳就直接压在最后几个字上（issue #83：群内自动
  // 翻译遇到"这句不用翻"时复现）。
  //
  // 规则：会变的值从 this 读，参数里只留稳定的东西（如 isLast）。
  @Builder
  richContent(text: string, entities: TdObject[], maxWidth: number) {
    Column() {
      ForEach(parseFormattedText(text, entities), (seg: RichSegment, segIdx: number) => {
        if (seg.kind === 'pre') {
          Column() {
            Row({ space: 8 }) {
              Text(seg.language !== '' ? seg.language : $r('app.string.mb_code'))
                .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1);
              Row() {
                Text($r('app.string.copy'))
                  .fontSize(11).fontColor(this.accent()).fontWeight(FontWeight.Medium);
              }
                .height(26)
                .padding({ left: 8, right: 8 })
                .borderRadius(13)
                .backgroundColor('#10000000')
                .stateStyles({
                  normal: this.linkRunNormalStyle,
                  pressed: this.linkRunPressedStyle
                })
                .animation({ duration: this.effectDuration(90), curve: Curve.EaseOut })
                .onClick((): void => {
                  if (this.gestureClaimed) { return; }
                  this.onCopyCode(seg.text); });
            }
            .width(maxWidth - 18)
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: 5 });
            Text() {
              Span(seg.text);
              if (this.timeReserveInText() && seg.isLast) {
                Span(this.timeReserve()).fontColor(Color.Transparent);
              }
            }
            .fontSize(this.codeTextSize())
            .lineHeight(this.codeTextSize() * 1.42)
            .fontColor(bubbleTextFor(this.msg.isOutgoing))
            .fontFamily('monospace')
            .constraintSize({ maxWidth: maxWidth - 20 })
            .wordBreak(WordBreak.BREAK_ALL);
          }
          .width(maxWidth)
          .backgroundColor($r('app.color.surface_alt')).borderRadius(7)
          .padding({ left: 9, right: 9, top: 7, bottom: 8 })
          .margin({ top: 4, bottom: 2 })
          .clip(true);
        } else if (seg.kind === 'quote') {
          Column() {
            // Span-based rendering keeps links inside the quote tappable.
            Text() {
              ForEach(seg.runs, (r: RichRun) => {
                this.richInlineRun(r);
              }, (r: RichRun, i: number) => `qrun_${i}_${r.offset}_${r.text}`);
              if (this.timeReserveInText() && seg.isLast) {
                Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
              }
            }
            .fontSize(this.msgTextSize)
            .lineHeight(this.msgTextSize * 1.34)
            .maxLines(seg.expandable && !this.quoteExpanded(seg) ? 4 : 10000)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: maxWidth - 20 }).wordBreak(WordBreak.BREAK_WORD);
            if (seg.expandable) {
              Text(this.quoteExpanded(seg) ? $r('app.string.mb_collapse_quote') : $r('app.string.mb_expand_quote'))
                .fontSize(11).fontColor(this.accent()).fontWeight(FontWeight.Medium)
                .margin({ top: 4 })
                .stateStyles({
                  normal: this.linkRunNormalStyle,
                  pressed: this.linkRunPressedStyle
                })
                .animation({ duration: this.effectDuration(100), curve: Curve.EaseOut })
                .onClick((): void => {
                  if (this.gestureClaimed) { return; }
                  this.toggleQuote(seg); });
            }
          }
          .backgroundColor('#103391E8').borderRadius(7)
          .border({ width: { left: 3 }, color: this.accent() })
          .padding({ left: 9, right: 8, top: 7, bottom: 7 }).margin({ top: 4, bottom: 2 })
          .animation({ duration: this.effectDuration(180), curve: Curve.EaseOut });
        } else {
          this.richRuns(seg.runs, maxWidth, seg.isLast);
        }
      }, (seg: RichSegment, i: number) => `seg_${i}_${seg.kind}`);
    }
    .constraintSize({ maxWidth })
    .alignItems(HorizontalAlign.Start);
  }

  // 整聊天翻译块：原文之下分隔线 + 斜体译文 + 「已翻译成X · 隐藏译文」小字。
  // 原文永远保留（对照式，不是替换式），隐藏只折叠译文本体，脚注变为
  // 「显示译文」。存在译文时时间戳的占位挪到脚注行（见 timeReserveInText）。
  @Builder
  translationBlock() {
    // 译文还没到：显示瞬时态。分隔线沿用译文那条，让三种状态占同一个位置。
    if (this.msg.translatedText === '' && this.translationStatus !== null) {
      Divider().color(COLOR_TEXT_SECONDARY).opacity(0.3).strokeWidth(0.6)
        .margin({ top: 6, bottom: 5 });
      if (this.translationStatus?.phase === 'loading') {
        Row({ space: 5 }) {
          LoadingProgress().width(12).height(12).color(COLOR_TEXT_SECONDARY);
          Text($r('app.string.mb_translating')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
          if (this.timeReserveOnStatus()) {
            Text(this.timeReserve()).fontSize(11).fontColor(Color.Transparent);
          }
        }.constraintSize({ maxWidth: this.inlineMaxW() });
      } else {
        // 原始报错原样展示（按要求）。失败行整体可点，点一下立刻重发，
        // 绕过 TranslationService 的 60 秒失败冷却。
        Row({ space: 4 }) {
          Text(str('mb_translate_failed', this.translationStatus?.error ?? ''))
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text($r('app.string.settings_retry'))
            .fontSize(11).fontColor(this.accent()).fontWeight(FontWeight.Medium);
          if (this.timeReserveOnStatus()) {
            Text(this.timeReserve()).fontSize(11).fontColor(Color.Transparent);
          }
        }
        .constraintSize({ maxWidth: this.inlineMaxW() })
        .onClick((): void => {
          if (this.gestureClaimed) { return; }
          this.onRetryTranslation(this.msg.id); });
      }
    }
    if (this.msg.translatedText !== '') {
      Divider().color(COLOR_TEXT_SECONDARY).opacity(0.3).strokeWidth(0.6)
        .margin({ top: 6, bottom: 5 });
      if (!this.msg.translationHidden) {
        Text(this.msg.translatedText)
          .fontSize(this.msgTextSize)
          .lineHeight(this.msgTextSize * 1.34)
          .fontStyle(FontStyle.Italic)
          .fontColor(bubbleTextFor(this.msg.isOutgoing))
          .wordBreak(WordBreak.BREAK_WORD)
          .constraintSize({ maxWidth: this.inlineMaxW() });
      }
      Row({ space: 4 }) {
        Text(str('mb_translated_into', languageDisplayName(this.msg.translatedLang)))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        Text('·').fontSize(11).fontColor(COLOR_TEXT_SECONDARY); // i18n-exempt: 标点
        Text(this.msg.translationHidden
          ? $r('app.string.mb_show_translation') : $r('app.string.mb_hide_translation'))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
        if (this.timeReserveOnFooter()) {
          Text(this.timeReserve()).fontSize(11).fontColor(Color.Transparent);
        }
      }
      .margin({ top: 4 })
      .onClick((): void => {
        if (this.gestureClaimed) { return; }
        this.onToggleTranslation(this.msg.id, !this.msg.translationHidden);
      });
    }
  }

  // Channel post footer: recent-commenter avatars + comment count + chevron,
  // tapping opens the linked discussion group's thread for this post.
  @Builder
  commentsRow() {
    Row({ space: 6 }) {
      if (this.msg.commentReplierIds.length > 0) {
        Row() {
          ForEach(this.msg.commentReplierIds, (uid: number, idx: number) => {
            LiveSenderAvatar({
              senderId: uid,
              senderIsUser: true,
              initialPath: idx < this.msg.commentReplierAvatarPaths.length
                ? this.msg.commentReplierAvatarPaths[idx] : '',
              initials: '?',
              avatarSize: 22
            })
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
      if (this.gestureClaimed) { return; }
      this.onCommentTap(this.msg.id); });
  }

  // Bot inline keyboard rendered below the bubble: translucent rounded buttons,
  // equal widths per row (Telegram style). URL buttons open links; callback
  // buttons send the payload back to the bot.
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
                .stateStyles({
                  normal: this.botButtonNormalStyle,
                  pressed: this.botButtonPressedStyle
                })
                .animation({ duration: this.effectDuration(100), curve: Curve.EaseOut })
                .onClick(() => {
                  if (this.gestureClaimed) { return; }
                  if (btn.url !== '') {
                    this.onLinkTap(btn.url);
                  } else if (btn.callbackData !== '') {
                    this.onBotCallback(this.msg.id, btn.callbackData);
                  } else if (btn.isGame) {
                    this.onGameOpen(this.msg.id);
                  }
                });
            }, (btn: InlineBtn, btnIdx: number) => `ib_${rowIdx}_${btnIdx}_${btn.text}`);
          }.width('100%');
        }, (_row: InlineBtn[], rowIdx: number) => `ibrow_${rowIdx}`);
      }
      // Match the bubble's MEASURED width (it shrinks to fit its content), so
      // the keyboard is never wider than the bubble above it.
      .width(this.bubbleW > 0 ? this.bubbleW : this.inlineMaxW() + 16);
    }
    .width('100%')
    .padding({
      // Align with the bubble body; every row reserves the same 7vp tail
      // gutter so first/middle/last bubbles never shift horizontally.
      left: 10 + (this.msg.isOutgoing ? 0 : (this.isGroup ? 38 : 0) +
        this.bubbleTailGutter()),
      right: 10 + (this.msg.isOutgoing ? this.bubbleTailGutter() : 0),
      top: 2, bottom: 2
    })
    .justifyContent(this.msg.isOutgoing ? FlexAlign.End : FlexAlign.Start);
  }

  // Loading ring shown centered on a media placeholder while its thumbnail
  // downloads — same style as the fullscreen viewer's (percent inside the ring).
  @Builder
  mediaLoadState(size: number, fileId: number, initialPercent: number, failed: boolean) {
    if (failed) {
      Column({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(Math.max(17, size * 0.5))
          .fontColor([Color.White]);
        Text($r('app.string.settings_retry')).fontSize(11).fontColor(Color.White).fontWeight(FontWeight.Medium);
      }
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .backgroundColor('#80000000').borderRadius(18);
    } else {
      // 进度不进 key，环自己订阅自己更新（见 LiveProgressRing / collapseAlbums）。
      LiveProgressRing({ fileId: fileId, initialPercent: initialPercent, ringSize: size });
    }
  }

  // Shared by both the LiveThumbImage placeholder (hasFile === true, only
  // reached once this message has a photoFileId) and the no-fileId fallback
  // (hasFile === false) so the two never drift apart.
  @Builder
  singleMediaPlaceholder(hasFile: boolean) {
    Stack() {
      Column().width(this.mediaBox().width).height(this.mediaBox().height).borderRadius(8)
        .backgroundColor(this.msg.contentType === 'video' ? '#AEB6C0' : '#D7DCE2');
      if (this.msg.contentType === 'video') {
        // Wait only when a real thumbnail file exists. Videos without a
        // cover remain playable and get the normal play control below.
        if (hasFile && !this.msg.photoFailed) {
          this.mediaLoadState(36, this.msg.photoFileId, this.livePhotoProgress, false);
        }
      } else {
        this.mediaLoadState(36, this.msg.photoFileId, this.livePhotoProgress,
          this.msg.photoFailed || !hasFile);
      }
    }.width(this.mediaBox().width).height(this.mediaBox().height);
  }

  @Builder
  stickerStatusBadge(failed: boolean, percent: number) {
    Stack() {
      Circle({ width: 30, height: 30 }).fill('#78000000')
        .stroke('#20FFFFFF').strokeWidth(0.7);
      if (failed) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(16).fontColor([Color.White]);
      } else if (percent > 0) {
        Progress({ value: percent, total: 100, type: ProgressType.Ring })
          .width(20).height(20).color(Color.White);
      } else {
        LoadingProgress().width(17).height(17).color(Color.White);
      }
    }
    .width(30).height(30)
    .accessibilityText(failed ? $r('app.string.mb_sticker_failed') : $r('app.string.mb_sticker_loading'));
  }

  @Builder
  stickerUnavailable() {
    Column({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(24).fontColor([COLOR_TEXT_SECONDARY]);
      Text($r('app.string.mb_sticker_unavailable'))
        .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
    }
    .width(this.stickerW()).height(this.stickerH())
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#12000000')
    .borderRadius(18);
  }

  @Builder
  stickerPausedFallback() {
    if (this.msg.text !== '') {
      Text(this.msg.text)
        .fontSize(this.msg.isEmojiSticker ? 52 : 42)
        .textAlign(TextAlign.Center)
        .width(this.stickerW()).height(this.stickerH());
    } else {
      Column({ space: 5 }) {
        SymbolGlyph($r('sys.symbol.pause')).fontSize(21).fontColor([COLOR_TEXT_SECONDARY]);
        Text($r('app.string.mb_animation_paused')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }
      .width(this.stickerW()).height(this.stickerH())
      .justifyContent(FlexAlign.Center);
    }
  }

  // Centered play-triangle badge, overlaid on video thumbnails.
  @Builder
  playBadge(size: number) {
    Stack() {
      Circle({ width: size, height: size }).fill('#73000000')
        .stroke('#24FFFFFF').strokeWidth(1);
      SymbolGlyph($r('sys.symbol.play_fill')).fontSize(size * 0.42).fontColor([Color.White]).margin({ left: 2 });
    }.width(size).height(size);
  }

  // One unambiguous center control for video states. Thumbnail loading owns
  // the center until it finishes; after that this control changes between
  // download progress, retry, unavailable, and play without stacking icons.
  @Builder
  videoActionBadge(size: number) {
    Stack() {
      Circle({ width: size, height: size }).fill('#78000000')
        .stroke('#24FFFFFF').strokeWidth(1);
      if (this.videoDownloadActive()) {
        Progress({ value: this.liveVideoProgress, total: 100, type: ProgressType.Ring })
          .width(size).height(size).color(Color.White);
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(size * 0.34).fontColor([Color.White]).margin({ left: 2 });
      } else if (this.msg.isAnimation && this.animationDownloadExpected()) {
        LoadingProgress().width(size * 0.62).height(size * 0.62).color(Color.White);
      } else if (this.msg.videoFailed || this.animationPlaybackFailed) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(size * 0.4).fontColor([Color.White]);
      } else if (this.videoFileUnavailable()) {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(size * 0.4).fontColor([Color.White]);
      } else {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(size * 0.42).fontColor([Color.White]).margin({ left: 2 });
      }
    }
    .width(size).height(size)
    .animation({ duration: this.effectDuration(160), curve: Curve.EaseOut });
  }

  // Masonry album grid: each row is scaled to fill the media width while preserving
  // every photo's own aspect ratio (rows vary in height), instead of a uniform
  // square grid that crops everything to 1:1. Video members get a play badge;
  // tapping any cell opens the fullscreen viewer for that specific message.
  // The album arrays are parallel, and the cell list is derived from just one
  // of them (albumRatios). Reuse re-seeds them one at a time, so a render can
  // land while the new ratios are in place and another array is still the old,
  // shorter one — that read used to be unguarded and took the process down with
  // "Cannot read property startsWith of undefined". A missing cell renders as
  // the placeholder for one frame; nothing here is worth crashing over.
  // A retry is only worth offering when there is a file to fetch: photoFileId 0
  // means the message never had a thumbnail, and re-requesting nothing would
  // just spin.
  private thumbnailRetryable(): boolean {
    return this.msg.photoPath === '' && this.msg.photoFailed && this.msg.photoFileId !== 0;
  }

  private albumCellRetryable(index: number): boolean {
    return this.albumPathAt(index) === '' && (this.albumFailed[index] ?? false) &&
      (this.albumFileIds[index] ?? 0) !== 0;
  }

  private albumPathAt(index: number): string {
    return this.albumPaths[index] ?? '';
  }

  private albumIsVideoAt(index: number): boolean {
    return this.albumIsVideo[index] ?? false;
  }

  private albumMemberIdAt(index: number): number {
    return this.albumMemberIds[index] ?? 0;
  }

  private albumVideoFileIdAt(index: number): number {
    return this.albumVideoFileIds[index] ?? 0;
  }

  private albumVideoFileSizeAt(index: number): number {
    return this.albumVideoFileSizes[index] ?? 0;
  }

  private albumVideoMimeTypeAt(index: number): string {
    return this.albumVideoMimeTypes[index] ?? '';
  }

  // 与 isPlaySlot() 同一道 !isAnimation 兜底：动图不参加竞选（spec §3.3），
  // 相册格子也不例外，否则相册里的动图会错挂流式播放器。
  private isAlbumCellPlaySlot(index: number): boolean {
    return this.playSlotKey !== '' && !this.msg.isAnimation &&
      this.playSlotKey === slotKey(this.albumMemberIdAt(index), index);
  }

  // The play slot renders through StreamingVideoPlayer, whose XComponent is
  // XComponentType.SURFACE (see StreamingVideoPlayer.ets) — that surface is
  // composited by the platform outside ArkUI's render tree, so
  // MenuPreviewMode.IMAGE's componentSnapshot cannot capture it (it would show
  // up as a black/blank rectangle in the lifted preview). When this bubble
  // currently owns the play slot — main content or an album cell — the
  // long-press menu falls back to the plain, preview-less presentation instead
  // of lying about what the frozen snapshot contains.
  private hasLiveVideoSurface(): boolean {
    if (this.playSlotKey === '' || this.msg.isAnimation) {
      return false;
    }
    if (this.isPlaySlot(-1) && this.msg.videoFileId !== 0) {
      return true;
    }
    for (let i = 0; i < this.albumMemberIds.length; i++) {
      if (this.isAlbumCellPlaySlot(i) && this.albumVideoFileIdAt(i) !== 0) {
        return true;
      }
    }
    return false;
  }

  // Same per-corner rounding the bubble itself draws (see the .borderRadius()
  // call in build()) — reused as the context-menu preview's crop radius so the
  // lifted snapshot matches the bubble's own configured KEY_BUBBLE_RADIUS
  // instead of a hardcoded value.
  private bubbleCornerRadius(): BorderRadiuses {
    return {
      topLeft: this.msg.isOutgoing ? this.bubbleRadius :
        (this.showSenderName ? this.bubbleRadius : this.runCornerRadius()),
      topRight: this.msg.isOutgoing ?
        (this.showSenderName ? this.bubbleRadius : this.runCornerRadius()) : this.bubbleRadius,
      bottomLeft: this.msg.isOutgoing ? this.bubbleRadius :
        (this.showAvatar ? this.tailCornerRadius() : this.runCornerRadius()),
      bottomRight: this.msg.isOutgoing ?
        (this.showAvatar ? this.tailCornerRadius() : this.runCornerRadius()) : this.bubbleRadius
    };
  }

  // Shared by both the LiveThumbImage placeholder (hasFile reflects the real
  // fileId, since that branch can now also be entered via a bare path — see
  // albumCellBody) and the no-fileId-no-path fallback (hasFile === false) so
  // the two never drift apart.
  // Wrapped in its own Stack: LiveThumbImage.build() mounts this as its own
  // component root when path is empty, and without the wrapper the Column +
  // mediaLoadState would be two sibling root nodes instead of one stacked on
  // the other — the progress ring would stop sitting on top of the tint.
  @Builder
  albumMediaPlaceholder(cellIdx: number, width: number, height: number, hasFile: boolean) {
    Stack() {
      Column().width(width).height(height).borderRadius(6)
        .backgroundColor(this.albumIsVideoAt(cellIdx) ? '#AEB6C0' : '#D7DCE2');
      if (hasFile && !(this.albumFailed[cellIdx] ?? false)) {
        this.mediaLoadState(
          Math.min(34, Math.min(width, height) * 0.4),
          this.albumFileIds[cellIdx] ?? 0,
          this.albumProgress[cellIdx] ?? 0,
          false
        );
      } else if (!this.albumIsVideoAt(cellIdx)) {
        this.mediaLoadState(
          Math.min(34, Math.min(width, height) * 0.4),
          0,
          0,
          true
        );
      }
    }.width(width).height(height);
  }

  // Body shared by both attribute variants below, so the only difference
  // between them stays confined to whether onAreaChange is attached.
  @Builder
  albumCellBody(cell: AlbumCell) {
    if (this.isAlbumCellPlaySlot(cell.idx) && this.albumVideoFileIdAt(cell.idx) !== 0) {
      // 播放位选中这一格：挂播放器而不是静态封面。
      VideoBubbleSurface({
        fileId: this.albumVideoFileIdAt(cell.idx),
        fileSize: this.albumVideoFileSizeAt(cell.idx),
        mimeType: this.albumVideoMimeTypeAt(cell.idx),
        posterPath: this.albumPathAt(cell.idx),
        muted: this.autoplayMuted,
        startPositionMs: this.playSlotStartMs,
        onPositionChanged: (positionMs: number): void => {
          this.onPlaySlotPositionChanged(this.albumMemberIdAt(cell.idx), cell.idx, positionMs);
        },
        onEnded: (): void => {
          this.onPlaySlotEnded(this.albumMemberIdAt(cell.idx), cell.idx);
        }
      })
        .width(cell.width).height(cell.height).clip(true)
        .borderRadius(6)
        // 同理：交给格子自己的 onClick 打开全屏查看器。
        .hitTestBehavior(HitTestMode.None);
    } else if ((this.albumFileIds[cell.idx] ?? 0) !== 0 || this.albumPathAt(cell.idx) !== '') {
      // No appear transition, for the same reason as the single-media
      // thumbnail: a row rebuild re-creates this node and would
      // replay the fade every time.
      // desiredSize matters most here: a cell is a few tens of vp
      // wide while the file behind it is the conversation-wide size.
      // Self-subscribing: the row key no longer carries the path, so
      // this node must react to the thumbnail landing on its own.
      // The condition can't be fileId-only: MessageStore backfills
      // photoPath from the full-size download while fileId can still be 0
      // for that entry, and losing the path there would regress an already
      // downloaded photo to a dead "retry" tile.
      LiveThumbImage({
        fileId: this.albumFileIds[cell.idx] ?? 0,
        initialPath: this.albumPathAt(cell.idx),
        boxWidth: cell.width,
        boxHeight: cell.height,
        radius: 6,
        fit: ImageFit.Cover,
        placeholder: (): void => {
          this.albumMediaPlaceholder(cell.idx, cell.width, cell.height, (this.albumFileIds[cell.idx] ?? 0) !== 0);
        }
      });
    } else {
      // A video without a downloadable thumbnail remains playable;
      // don't leave an endless 0% spinner over that intentional state.
      this.albumMediaPlaceholder(cell.idx, cell.width, cell.height, false);
    }
    if (this.albumIsVideoAt(cell.idx) &&
      !(this.isAlbumCellPlaySlot(cell.idx) && this.albumVideoFileIdAt(cell.idx) !== 0)) {
      // 同单图那处：缩略图到没到要问通道，albumPathAt 在旁路化之后不再回填。
      ThumbReadyGate({
        fileId: this.albumFileIds[cell.idx] ?? 0,
        initialPath: this.albumPathAt(cell.idx),
        ready: (this.albumFileIds[cell.idx] ?? 0) === 0 || (this.albumFailed[cell.idx] ?? false),
        content: (): void => {
          this.playBadge(Math.min(40, Math.min(cell.width, cell.height) * 0.46));
        }
      })
    }
  }

  @Builder
  albumGrid() {
    Column({ space: 2 }) {
      ForEach(packAlbumRows(this.albumRatios, this.albumW()), (row: AlbumCell[], rowIdx: number) => {
        Row({ space: 2 }) {
          ForEach(row, (cell: AlbumCell) => {
            if (this.albumIsVideoAt(cell.idx)) {
              // Video cells alone feed the play-slot center-y election, so
              // onAreaChange is only mounted here — profiling showed every
              // cell reporting geometry at 2100-2300/s when it was unconditional,
              // and pure image cells never consumed that data.
              Stack() {
                this.albumCellBody(cell);
              }
              .width(cell.width).height(cell.height)
              .accessibilityText(str('mb_album_item_video', cell.idx + 1))
              .onVisibleAreaApproximateChange(
                { ratios: [0.0, PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, 0.9],
                  expectedUpdateInterval: 200 },
                (_visible: boolean, ratio: number): void => {
                  const memberId = this.albumMemberIdAt(cell.idx);
                  if (ratio <= 0) {
                    this.onMediaGone(memberId, cell.idx);
                  } else {
                    this.onMediaRatio(memberId, cell.idx, ratio, this.albumCellCenterY.get(cell.idx) ?? 0);
                  }
                })
              .onAreaChange((_old: Area, area: Area): void => {
                this.albumCellCenterY.set(cell.idx,
                  (area.globalPosition.y as number) + (area.height as number) / 2);
              })
              .onClick((e: ClickEvent) => {
                if (this.gestureClaimed) { return; }
                // Same as the single-media case: a failed cell offers retry.
                if (this.albumCellRetryable(cell.idx)) {
                  this.onSpecialPhotoRetry(this.albumMemberIdAt(cell.idx));
                  return;
                }
                this.onMediaTap(this.albumMemberIdAt(cell.idx), e.windowX, e.windowY);
              });
            } else {
              Stack() {
                this.albumCellBody(cell);
              }
              .width(cell.width).height(cell.height)
              // 见单图分支：按被点的那一格的消息 id 绑定，相册里每格各自成对。
              .geometryTransition(`media_${this.albumMemberIdAt(cell.idx)}`)
              .accessibilityText((this.albumFailed[cell.idx] ?? false)
                ? str('mb_photo_failed') : str('mb_album_item', cell.idx + 1))
              .onVisibleAreaApproximateChange(
                { ratios: [0.0, PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, 0.9],
                  expectedUpdateInterval: 200 },
                (_visible: boolean, _ratio: number): void => {
                  // 相册竞选只看这一格是不是视频，图片格不上报
                })
              .onClick((e: ClickEvent) => {
                if (this.gestureClaimed) { return; }
                // Same as the single-media case: a failed cell offers retry.
                if (this.albumCellRetryable(cell.idx)) {
                  this.onSpecialPhotoRetry(this.albumMemberIdAt(cell.idx));
                  return;
                }
                this.onMediaTap(this.albumMemberIdAt(cell.idx), e.windowX, e.windowY);
              });
            }
          }, (cell: AlbumCell) => `cell_${cell.idx}`);
        }
      }, (_row: AlbumCell[], rowIdx: number) => `row_${rowIdx}`);
    }.alignItems(HorizontalAlign.Start).width(this.albumW()).constraintSize({ maxWidth: this.albumW() });
  }

  @Builder
  linkPreviewMeta(compact: boolean) {
    Column() {
      Text(this.linkPresentation().siteLabel)
        .fontSize(12).fontColor(this.accent()).fontWeight(FontWeight.Medium)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      if (this.msg.linkTitle !== '') {
        Text(this.msg.linkTitle)
          .fontSize(14).fontColor(bubbleTextFor(this.msg.isOutgoing)).fontWeight(FontWeight.Bold)
          .lineHeight(19).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 });
      }
      if (this.msg.linkDescription !== '') {
        // Description entities are deliberately display-only: the entire card
        // has one predictable target and nested links can't hijack a tap.
        Text(this.msg.linkDescription)
          .fontSize(13).fontColor(bubbleTextFor(this.msg.isOutgoing)).lineHeight(18)
          .maxLines(compact ? 3 : 4).textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 });
      } else if (this.msg.linkTitle === '') {
        Text(this.linkPresentation().isTelegram ? $r('app.string.mb_telegram_link') : $r('app.string.mb_web_link'))
          .fontSize(13).fontColor(COLOR_TEXT_SECONDARY).margin({ top: 2 });
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(compact ? 1 : 0);
  }

  @Builder
  linkPreviewImage(width: number, height: number, compact: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.msg.linkPhotoPath !== '') {
        Image(this.msg.linkPhotoPath.startsWith('/')
          ? `file://${this.msg.linkPhotoPath}` : this.msg.linkPhotoPath).draggable(false)
          .width(width).height(height).objectFit(ImageFit.Cover)
          .transition(TransitionEffect.OPACITY.animation({
            duration: this.effectDuration(180), curve: Curve.EaseOut
          }));
      } else {
        Column({ space: 5 }) {
          if (this.msg.linkPhotoFailed) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(compact ? 20 : 24).fontColor([this.accent()]);
            if (!compact) {
              Text($r('app.string.mb_photo_load_failed')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
            }
          } else {
            LoadingProgress()
              .width(compact ? 22 : 26).height(compact ? 22 : 26).color(this.accent());
            if (!compact && this.liveLinkPhotoProgress > 0 && this.liveLinkPhotoProgress < 100) {
              Text(`${this.liveLinkPhotoProgress}%`).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
            }
          }
        }
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .width(width).height(height).backgroundColor($r('app.color.surface_alt'));
      }
    }
    .width(width).height(height)
    .borderRadius(compact ? Math.floor(width / 2) : 8)
    .clip(true);
  }

  // URL / Telegram preview card: compact avatar treatment for channel/invite
  // targets, proportion-aware hero image for web/message previews, stable
  // loading/error geometry and a target-specific action label.
  @Builder
  linkPreviewCard() {
    Column() {
      if (this.compactTelegramPreview()) {
        Row({ space: 10 }) {
          this.linkPreviewMeta(true);
          this.linkPreviewImage(58, 58, true);
        }
        .width(this.cardMaxW()).alignItems(VerticalAlign.Center);
      } else {
        this.linkPreviewMeta(false);
        if (this.msg.linkPhotoFileId !== 0) {
          this.linkPreviewImage(this.cardMaxW(), this.linkPreviewH(), false);
          Blank().height(6);
        }
      }
      Row({ space: 5 }) {
        Text(this.msg.linkPhotoFailed ? '↻' : (this.linkPresentation().isTelegram ? '›' : '↗'))
          .fontSize(14).fontColor(this.linkPresentation().actionable || this.msg.linkPhotoFailed
            ? this.accent() : COLOR_TEXT_SECONDARY);
        Text(this.linkPreviewActionLabel())
          .fontSize(12).fontColor(this.linkPresentation().actionable || this.msg.linkPhotoFailed
            ? this.accent() : COLOR_TEXT_SECONDARY)
          .fontWeight(FontWeight.Medium).maxLines(1);
        if (this.linkPreviewOpening) {
          LoadingProgress().width(13).height(13).color(this.accent());
        }
      }
      .margin({ top: 6 });
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.inlineMaxW())
    .backgroundColor($r('app.color.surface_alt')).borderRadius(10)
    .border({ width: { left: 3 }, color: this.accent() })
    .padding({ left: 9, right: 9, top: 8, bottom: 8 }).margin({ top: 5 })
    .stateStyles({ normal: this.linkCardNormalStyle, pressed: this.linkCardPressedStyle })
    .animation({ duration: this.effectDuration(120), curve: Curve.EaseOut })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 4 }))
      .animation({ duration: this.effectDuration(180), curve: Curve.EaseOut }))
    .accessibilityText(`${this.linkPresentation().siteLabel}，${this.linkPreviewActionLabel()}`)
    .enabled(this.linkPresentation().actionable || this.msg.linkPhotoFailed)
    .onClick((): void => {
      if (this.gestureClaimed) { return; }
      this.openOrRetryLinkPreview(); });
  }

  // Emoji reaction pills (👍 3, ❤️ 2, ...), highlighted when the current user
  // has picked that reaction.
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
        .stateStyles({
          normal: this.menuActionNormalStyle,
          pressed: this.menuActionPressedStyle
        })
        .animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
        .onClick(() => {
          if (this.gestureClaimed) { return; }
          this.onSetReaction(this.msg.id, reactionKeyFrom(r.emoji, r.customEmojiId), r.isChosen);
        })
        // Long-press a chip to see who reacted with it.
        .gesture(LongPressGesture().onAction(() => {
          this.onShowReactors(this.msg.id, reactionKeyFrom(r.emoji, r.customEmojiId));
        }))
        .transition(
          TransitionEffect.scale({ x: 0.6, y: 0.6 })
            .combine(TransitionEffect.OPACITY)
            .animation({ duration: this.reactionDuration(180), curve: Curve.EaseOut })
        );
        // key 里带上路径，位图下载完成后 chip 才会重建并显示图片。
      }, (r: ReactionInfo) => `rx_${reactionKeyFrom(r.emoji, r.customEmojiId)}_${r.customEmojiPath}`);
    }
    // **Flex 开了 wrap 就按父容器最大宽测量**，只写 maxWidth 挡不住，alignSelf
    // 也挡不住（那只管对齐不管测量——上一版就是这么修的，1.4.0 里用户报仍然
    // 一个反应就把短消息顶到最大内容宽，issue #100）。给它一个明确宽度：按
    // chip 内容测出来的自然宽，封顶 inlineMaxW，超了才由 wrap 换行。
    .width(this.reactionsRowWidth())
    .constraintSize({ maxWidth: this.inlineMaxW() }).margin({ top: 4 });
  }

  // 反应条的自然宽度（vp），见 util/reactionsWidth。按内容签名缓存：同一条消息
  // 每次 build 都重测是白烧，反应变了签名才变。
  private rxWidthSig: string = '';
  private rxWidthCache: number = 0;

  private reactionsRowWidth(): number {
    const sig: string = this.msg.reactions
      .map((r: ReactionInfo): string => `${r.emoji}|${r.customEmojiId}|${r.count}`).join(',');
    if (sig === this.rxWidthSig && this.rxWidthCache > 0) {
      return this.rxWidthCache;
    }
    const chips: number[] = [];
    for (const r of this.msg.reactions) {
      // 自定义表情是 15×15 的位图（或同尺寸占位）；unicode 表情是 13fp 的 Text，得测。
      const icon: number = r.customEmojiId !== '' ? CHIP_ICON_VP : this.measureTextVp(r.emoji, 13);
      chips.push(reactionChipWidth(icon, this.measureTextVp(`${r.count}`, 12)));
    }
    this.rxWidthSig = sig;
    this.rxWidthCache = reactionsRowWidth(chips, this.inlineMaxW());
    return this.rxWidthCache;
  }

  // 一段文本按给定字号排一行的宽度（vp）。measureTextSize 返回 px。量不出来就按
  // 字号 × 字数估——宁可略宽也别让最后一个 chip 掉行。
  private measureTextVp(text: string, fontSize: number): number {
    try {
      const size: SizeOptions = this.getUIContext().getMeasureUtils().measureTextSize({
        textContent: text, fontSize: fontSize
      });
      return px2vp(size.width as number);
    } catch (e) {
      return fontSize * Math.max(1, text.length);
    }
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

  // Long-press context menu: quick-reaction row (tap an emoji to toggle it, the
  // chevron opens the full picker) over the standard message actions.
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
  msgContextMenu() {
    Column() {
      Row({ space: 2 }) {
        ForEach(QUICK_REACTIONS, (e: string) => {
          Row() {
            Text(e).fontSize(23);
          }
            .width(32).height(34).borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.reactionChosen(e) ? '#263391E8' : Color.Transparent)
            .stateStyles({
              normal: this.menuActionNormalStyle,
              pressed: this.menuActionPressedStyle
            })
            .animation({ duration: this.reactionDuration(120), curve: Curve.EaseOut })
            .onClick(() => { this.onSetReaction(this.msg.id, e, this.reactionChosen(e)); })
            // Long-press a quick emoji to make it the account's default
            // reaction (used by double-tap in the official clients).
            .gesture(LongPressGesture().onAction(() => { this.onSetDefaultReaction(e); }));
        }, (e: string) => e);
        Blank();
        // Round "expand" button → opens the full emoji reaction picker.
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(15).fontColor([bubbleTextFor(this.msg.isOutgoing)]);
        }
        .width(30).height(30).borderRadius(15).backgroundColor('#0000000F')
        .justifyContent(FlexAlign.Center)
        .stateStyles({
          normal: this.menuActionNormalStyle,
          pressed: this.menuActionPressedStyle
        })
        .animation({ duration: this.reactionDuration(110), curve: Curve.EaseOut })
        .onClick(() => { this.onOpenReactions(this.msg.id); });
      }
      .width('100%').padding({ left: 12, right: 10, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center);
      Divider().color($r('app.color.divider')).strokeWidth(0.7);
      actionMenuRow('sys.symbol.arrowshape_turn_up_left', str('mb_reply'), false, () => { this.onReplyTo(this.msg.id); });
      // TDLib 1.8.65 has no can_be_edited on message (it moved to
      // getMessageProperties); gate locally on Telegram's 48h edit window and
      // let the server be the final judge. Media types edit their caption.
      if (this.msg.isOutgoing && this.nowSec - this.msg.date < 172800 &&
        (this.msg.contentType === 'text' ||
          EDITABLE_CAPTION_TYPES.indexOf(this.msg.contentType) >= 0)) {
        actionMenuRow('sys.symbol.square_and_pencil',
          this.msg.contentType === 'text' ? str('edit') : str('mb_edit_caption'),
          false, () => { this.onEditMsg(this.msg.id); });
      }
      actionMenuRow('sys.symbol.plus_square_on_square', str('mb_copy_text'), false, () => { this.onCopyText(this.msg.id); });
      if (this.msg.text !== '') {
        actionMenuRow('sys.symbol.translate', str('mb_translate'), false, () => { this.onTranslateMsg(this.msg.id); });
      }
      // 「复制链接」复制的是**正文里的 URL**（显式超链接的目标 + 裸链接原文，
      // @提及/#话题不算）；和下面「拷贝消息链接」（这条消息的 t.me 跳转）是两回事。
      // Span 不支持长按手势（ArkUI 限制），所以"长按链接复制"落在消息菜单这里。
      if (messageUrls(this.msg.text, this.msg.textEntities).length > 0) {
        actionMenuRow('sys.symbol.paperclip', str('mb_copy_url'), false, () => {
          this.copyMessageUrls();
        });
      }
      actionMenuRow('sys.symbol.link', str('mb_copy_link'), false, () => { this.onCopyLink(this.msg.id); });
      actionMenuRow('sys.symbol.arrowshape_turn_up_right', str('mb_forward'), false,
        () => { this.onForwardMsg(this.albumMemberIds); });
      // 「保存消息」= 转发到收藏（和自己的会话）。和上面的「转发」区别只在
      // 目标固定、不弹选择面板，所以紧挨着放。
      actionMenuRow('sys.symbol.bookmark', str('mb_save_to_saved'), false,
        () => { this.onSaveToSaved(this.albumMemberIds); });
      // 「复读」= 转发回本会话。群里的常见玩法，官方要走"转发→再选回本群"两步。
      actionMenuRow('sys.symbol.repeat', str('mb_repeat'), false,
        () => { this.onRepeatMsg(this.albumMemberIds); });
      // 「查看历史」= 在本会话里筛出这个人的全部消息。
      // **只在群里、且发送者确实是个用户时出现**：私聊里整个会话就是对方的
      // 消息，这一项没有意义；频道身份/匿名管理员发的消息 senderIsUser 为假，
      // 按 user 筛不出来，给了也是个死项。
      if (this.isGroup && this.msg.senderIsUser && this.msg.senderId > 0) {
        actionMenuRow('sys.symbol.person', str('mb_view_history'), false,
          () => { this.onViewSenderHistory(this.msg.senderId); });
      }
      actionMenuRow('sys.symbol.pin', this.isPinnedMsg ? str('ft_unpin') : str('ft_pin'), false,
        () => { this.onPinMsg(this.msg.id, this.isPinnedMsg); });
      if (this.msg.isOutgoing && this.nowSec - this.msg.date < 172800 &&
        (this.msg.contentType === 'photo' || this.msg.contentType === 'video')) {
        actionMenuRow('sys.symbol.picture', str('mb_replace_media'), false,
          () => { this.onReplaceMedia(this.msg.id); });
      }
      if (this.msg.contentType === 'poll' && this.msg.isOutgoing && !this.msg.pollIsClosed) {
        actionMenuRow('sys.symbol.checkmark_circle', str('mb_stop_poll'), false,
          () => { this.onStopPoll(this.msg.id); });
      }
      if (this.msg.contentType === 'poll' && !this.msg.pollIsAnonymous) {
        actionMenuRow('sys.symbol.person_2', str('mb_view_voters'), false,
          () => { this.onPollVoters(this.msg.id); });
      }
      actionMenuRow('sys.symbol.exclamationmark_circle', str('mb_report'), true, () => { this.onReportMsg(this.msg.id); });
      actionMenuRow('sys.symbol.checkmark_circle', str('mb_select'), false,
        () => { this.onSelectMsg(this.albumMemberIds); });
      actionMenuRow('sys.symbol.trash', str('delete'), true, () => { this.onDeleteMsg(this.msg.id); });
    }
    .width(262)
    .padding({ top: 6, bottom: 6 });
  }

  // 引用块比正文更窄。单行 + 省略号的文本会一直吃满可用宽度，长 URL 直接把
  // 气泡撑到上限——哪怕正文只有两个字。引用是次要信息，不该决定气泡宽度。
  private replyQuoteMaxW(): number {
    return Math.round(this.inlineMaxW() * REPLY_QUOTE_WIDTH_RATIO);
  }

  @Builder
  replyQuote() {
    // 条件是"有没有回复"，不是"引用内容到没到"。被引用的消息是异步取回来的，
    // 等内容到了才画这一块，气泡就会在落地后凭空长高约 40vp——进聊天页时那次
    // 重排就是这么来的。两行都锁死行高，加载中和加载完是同一个高度。
    // 前提：拉不到原消息时 store 会填 mb_reply_unavailable，不会永远空着。
    Column() {
      Text(this.msg.replySenderName).fontSize(12).fontColor(this.accent()).maxLines(1)
        .lineHeight(REPLY_QUOTE_LINE_H).height(REPLY_QUOTE_LINE_H)
        .constraintSize({ maxWidth: this.replyQuoteMaxW() }).textOverflow({ overflow: TextOverflow.Ellipsis });
      Text(this.msg.replyText).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
        .lineHeight(REPLY_QUOTE_LINE_H).height(REPLY_QUOTE_LINE_H)
        .constraintSize({ maxWidth: this.replyQuoteMaxW() }).textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .alignItems(HorizontalAlign.Start)
    // 整块染一层强调色的淡底，并撑满气泡的内宽——这样点击区域就是看得见的
    // 那一块，而不是只有文字那几个字宽。
    //
    // 用 alignSelf(Stretch) 而不是 width('100%')：百分比宽度的孩子会按父级
    // 的**上限**来量，气泡会被这一块顶到最宽（同样的坑在时间戳那层踩过一次，
    // 见 inline timestamp 的 Stack 注释）。Stretch 是先由别的内容定出宽度、
    // 再把这一块拉满，正是要的语义。
    //
    // 引用文本仍然吃 replyQuoteMaxW 的上限：引用是次要信息，不该决定气泡
    // 宽度（长 URL 会把气泡撑满，哪怕正文只有两个字）。
    .alignSelf(ItemAlign.Stretch)
    .backgroundColor(accentSoft())
    .borderRadius(6)
    .border({ width: { left: 2 }, color: this.accent() })
    .padding({ left: 6, right: 6, top: 3, bottom: 3 }).margin({ bottom: 4 })
    // Tap the quote → jump to the original message.
    .onClick(() => {
      if (this.gestureClaimed) { return; }
      if (this.msg.replyToMessageId !== 0) {
        this.onReplyTap(this.msg.replyToMessageId, this.msg.id);
      }
    });
  }

  @Builder
  content() {
    if (this.msg.replyToMessageId !== 0) {
      this.replyQuote();
    }
    if (this.albumPaths.length > 1) {
      this.albumGrid();
      if (this.albumCaption !== '') {
        // Rich caption: links/@mentions/#hashtags stay tappable in albums too.
        Column() {
          this.richContent(this.albumCaption, this.albumCaptionEntities, this.inlineMaxW());
          // 相册配文也要能翻译（issue #128）。和单张媒体那一支（见下面
          // contentType 'photo'/'video' 分支）是同一个疏漏的两半：
          // translationCandidates 一直把带配文的媒体收进去、译文也存下来了，
          // 只是没有地方显示。
          //
          // this.msg 是 albumHead()——第一条成员的克隆，而配文按约定也取第一条
          // （见 collapseAlbums），所以 translationBlock 读的 translatedText、
          // translationStatus 订阅的 id、行签名里的翻译态，三者指的是同一条消息。
          this.translationBlock();
        }.margin({ top: 6 });
      }
    } else if (this.msg.contentType === 'richMessage') {
      // 富文本长帖单独一个组件，见 RichMessageView。这个文件已经够大，
      // 那套按块渲染（标题分档、引用竖条、列表符号）不往里塞。
      RichMessageView({
        rawBlocks: this.msg.richBlocks ?? [],
        maxWidth: this.inlineMaxW(),
        onOpenUrl: (url: string): void => {
          if (this.gestureClaimed) { return; }
          this.onLinkTap(url);
        }
      });
    } else if (this.msg.contentType === 'text') {
      if (this.msg.text.trim() === '') {
        Text() {
          Span($r('app.string.mb_empty')).fontColor(COLOR_TEXT_SECONDARY);
          if (this.timeReserveInText()) {
            Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
          }
        }
        .fontSize(this.msgTextSize)
        .lineHeight(this.msgTextSize * 1.34);
      } else {
        this.richContent(this.msg.text, this.msg.textEntities, this.inlineMaxW());
      }
      if (this.hasLinkPreview()) {
        this.linkPreviewCard();
      }
      this.translationBlock();
    } else if (this.msg.contentType === 'photo' || this.msg.contentType === 'video') {
      Stack() {
        if (this.isPlaySlot(-1) && this.msg.contentType === 'video' && this.msg.videoFileId !== 0) {
          // 播放位气泡：只有滚动停下、被选中的这一条才挂流式播放器。
          VideoBubbleSurface({
            fileId: this.msg.videoFileId,
            fileSize: this.msg.videoFileSize,
            mimeType: this.msg.videoMimeType,
            sourceWidth: this.msg.photoWidth,
            sourceHeight: this.msg.photoHeight,
            posterPath: this.msg.photoPath,
            muted: this.autoplayMuted,
            startPositionMs: this.playSlotStartMs,
            onPositionChanged: (positionMs: number): void => {
              this.onPlaySlotPositionChanged(this.msg.id, -1, positionMs);
            },
            onEnded: (): void => {
              this.onPlaySlotEnded(this.msg.id, -1);
            }
          })
            .width(this.mediaBox().width).height(this.mediaBox().height)
            // 播放位没有手势层，但底层 XComponent 会默认吃掉点击——和下面
            // SmartLoopVideo 同理，交给外层 Stack 的 onClick 打开全屏查看器。
            .hitTestBehavior(HitTestMode.None);
        } else if (this.autoplayInlineVideo()) {
          SmartLoopVideo({
            videoPath: this.msg.videoPath,
            thumbPath: this.msg.photoPath,
            boxWidth: this.mediaBox().width,
            boxHeight: this.mediaBox().height,
            powerCategory: this.autoplayCategory(),
            forcePlay: this.msg.isAnimation && this.animationForcePlay,
            onPlaybackFailed: (): void => {
              if (this.msg.isAnimation) {
                this.onAnimationPlaybackFailed(this.msg.id);
              }
            }
          })
            // Native texture components can otherwise consume the tap before
            // the media wrapper gets a chance to toggle GIF pause/play.
            .hitTestBehavior(HitTestMode.None);
        } else if (this.msg.photoFileId !== 0 || this.msg.photoPath !== '') {
          // Keep the thumbnail mounted while fullscreen preview is open. ArkUI's
          // geometry transition can re-parent this Image node; with LazyForEach
          // recycling that occasionally restored only the placeholder/background
          // or an undecoded blank node after returning to the chat.
          // No appear transition here. A LazyForEach CHANGE rebuilds this
          // subtree, so the Image comes back as a new node and any appear
          // transition replays — during a download that fired at the updateFile
          // rate and read as the thumbnail flickering. The row key now buckets
          // progress (see collapseAlbums.progressBucket), but a rebuild is still
          // normal for every other field, and a thumbnail must not blink on one.
          // Decoded through the PixelMap cache: DMA memory so the first draw
          // costs no texture upload on the render thread, and desiredSize
          // downsamples during the decode rather than after it.
          // Self-subscribing: the row key no longer carries the path, so this
          // node must react to the thumbnail landing on its own.
          // The condition can't be fileId-only: MessageStore backfills
          // photoPath from the full-size download while photoFileId can still
          // be 0, and losing the path there would regress an already
          // downloaded photo to a dead "retry" tile.
          LiveThumbImage({
            fileId: this.msg.photoFileId,
            initialPath: this.msg.photoPath,
            boxWidth: this.mediaBox().width,
            boxHeight: this.mediaBox().height,
            radius: 8,
            fit: ImageFit.Cover,
            placeholder: (): void => {
              this.singleMediaPlaceholder(this.msg.photoFileId !== 0);
            }
          });
        } else {
          this.singleMediaPlaceholder(false);
        }
        if (this.msg.contentType === 'video' && !this.autoplayInlineVideo() &&
          !(this.isPlaySlot(-1) && this.msg.videoFileId !== 0)) {
          // 不要和缩略图自己的加载圈叠成两个中心控件——所以要等缩略图到位。
          // 这个"到没到"必须问通道：路径旁路化之后 msg.photoPath 不再回填，
          // 直接读它会永远是空，播放钮就再也不出现（用户报的正是这个）。
          ThumbReadyGate({
            fileId: this.msg.photoFileId,
            initialPath: this.msg.photoPath,
            ready: this.msg.photoFileId === 0 || this.msg.photoFailed,
            content: (): void => {
              this.videoActionBadge(
                Math.min(56, Math.min(this.mediaBox().width, this.mediaBox().height) * 0.34));
            }
          })
        }
        if (this.msg.contentType === 'video' && this.videoMetaText() !== '') {
          Text(this.videoMetaText())
            .fontSize(11).fontColor(Color.White).backgroundColor('#00000066')
            .borderRadius(4).padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .position({ x: 8, y: Math.max(8, this.mediaBox().height - 25) });
        }
      }
      .width(this.mediaBox().width).height(this.mediaBox().height)
      // 一镜到底：和全屏查看器里同一条消息的图绑同一个 id，打开/关闭时由系统
      // 把两者的宽高与位置对齐过渡（见 MediaViewerOverlay）。气泡在查看器打开
      // 期间仍然挂在列表里，所以出场节点一直存在，动画不会半路断掉。
      .geometryTransition(`media_${this.msg.id}`)
      .accessibilityText(this.msg.contentType === 'video'
        ? this.videoAccessibilityText()
        : (this.msg.photoFailed ? str('mb_photo_failed') : str('mb_open_photo')))
      // onVisibleAreaChange 每帧都要重新计算可见比例，聊天列表里挂几十个媒体节点会
      // 明显拖累功耗（HarmonyOS 文档已载明这点）；onVisibleAreaApproximateChange 按
      // expectedUpdateInterval 限频上报，正是为这种「列表里大量媒体节点」的场景加的。
      .onVisibleAreaApproximateChange(
        { ratios: [0.0, 0.08, PLAY_SLOT_KEEP_RATIO, PLAY_SLOT_ENTER_RATIO, 0.9],
          expectedUpdateInterval: 200 },
        (visible: boolean, ratio: number): void => {
          const nextVisible = visible && ratio > 0.02;
          if (this.mediaVisible !== nextVisible) {
            this.mediaVisible = nextVisible;
            if (nextVisible) {
              this.requestAutoplayDownload();
            }
          }
          if (this.msg.contentType !== 'video' || this.msg.isAnimation) {
            return; // 只有普通视频参与播放位竞选：GIF/动图仍走整文件循环播放
          }
          if (ratio <= 0) {
            this.onMediaGone(this.msg.id, -1);
          } else {
            this.onMediaRatio(this.msg.id, -1, ratio, this.mediaCenterY);
          }
        })
      .onAreaChange((_old: Area, area: Area): void => {
        this.mediaCenterY = (area.globalPosition.y as number) + (area.height as number) / 2;
      })
      .onClick((e: ClickEvent) => {
        if (this.gestureClaimed) { return; }
        // When the media shows a retry control, the tap has to retry. It used
        // to fall through to onMediaTap, which opened a viewer onto a file that
        // was never downloaded — the retry badge was decoration.
        if (this.thumbnailRetryable()) {
          this.onSpecialPhotoRetry(this.msg.id);
          return;
        }
        if (this.msg.contentType === 'video' && this.msg.videoFailed) {
          this.onVideoRetry(this.msg.id);
          return;
        }
        if (this.msg.isAnimation) {
          this.onAnimationTap(this.msg.id, this.autoplayInlineVideo());
        } else {
          this.onMediaTap(this.msg.id, e.windowX, e.windowY);
        }
      });
      // Media caption shown below the media, within the same bubble.
      if (this.msg.text !== '') {
        Column() {
          this.richContent(this.msg.text, this.msg.textEntities, this.inlineMaxW());
          // 配文也要能翻译。translationCandidates 一直把带配文的媒体收进去，
          // 译文也存下来了，只是原来 translationBlock() 只挂在 text 分支上，
          // 结果"请求发了、译文有了、没地方显示"。
          this.translationBlock();
        }.margin({ top: 6 });
      }
    } else if (this.msg.contentType === 'videoNote') {
      // 圆形视频：点一下原地播放，不进全屏——它本来就是个小圆，放大到全屏
      // 既没有更多信息，还要处理旋转元数据（ijk 不读，会转 90 度）。
      Stack({ alignContent: Alignment.Center }) {
        // 封面始终垫在底下，播放器叠上去。做成 if/else 的话切换瞬间封面已经
        // 卸载、首帧还没到，中间会空一帧——表现就是点下去闪一下。
        if (this.msg.photoPath !== '') {
          Image(this.msg.photoPath.startsWith('/')
            ? `file://${this.msg.photoPath}` : this.msg.photoPath)
            .width(VIDEO_NOTE_SIDE).height(VIDEO_NOTE_SIDE)
            .objectFit(ImageFit.Cover)
            .draggable(false);
        } else {
          Column()
            .width(VIDEO_NOTE_SIDE).height(VIDEO_NOTE_SIDE)
            .backgroundColor($r('app.color.surface_alt'));
        }
        if (this.videoNotePlaying && this.msg.videoPath !== '') {
          AvLoopVideo({
            videoPath: this.msg.videoPath,
            boxWidth: VIDEO_NOTE_SIDE,
            boxHeight: VIDEO_NOTE_SIDE,
            loop: false,
            muted: false,
            onFinished: (): void => { this.videoNotePlaying = false; },
            onFailed: (): void => { this.videoNotePlaying = false; }
          });
        }
        if (!this.videoNotePlaying) {
          Row() {
            SymbolGlyph($r('sys.symbol.play_fill')).fontSize(22).fontColor([Color.White]);
          }
          .width(46).height(46).borderRadius(23)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#66000000');
        }
        // 时长压在圆底，和 Telegram 一致。
        Text(this.videoNoteDuration())
          .fontSize(11).fontColor(Color.White)
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor('#66000000').borderRadius(9)
          .offset({ y: VIDEO_NOTE_SIDE / 2 - 18 });
      }
      .width(VIDEO_NOTE_SIDE).height(VIDEO_NOTE_SIDE)
      .borderRadius(VIDEO_NOTE_SIDE / 2)
      .clip(true)
      .accessibilityText(this.videoNotePlaying
        ? str('mb_video_note_playing') : str('mb_video_note', this.videoNoteDuration()))
      .onClick((): void => {
        if (this.gestureClaimed) { return; }
        this.toggleVideoNote(); });
    } else if (this.msg.contentType === 'voice') {
      // Voice note with live playback progress — VoiceBubble subscribes to the
      // shared player itself, so ticks don't depend on this row re-rendering.
      VoiceBubble({
        msgId: this.msg.id,
        durationSec: this.msg.videoDuration,
        isOutgoing: this.msg.isOutgoing,
        voiceFileId: this.msg.videoFileId,
        voicePath: this.msg.videoPath,
        downloadProgress: this.liveVideoProgress,
        downloadFailed: this.msg.videoFailed,
        waveform: this.msg.voiceWaveform,
        listened: this.msg.voiceListened,
        speechState: this.msg.speechState,
        speechText: this.msg.speechText,
        onNeedDownload: (): void => { this.onVoiceTap(this.msg.id); },
        onPlaybackStarted: (): void => { this.onVoicePlaybackStarted(this.msg.id); },
        onRecognizeTap: (): void => { if (this.gestureClaimed) { return; } this.onRecognizeSpeech(this.msg.id); }
      });
    } else if (this.msg.contentType === 'audio') {
      // Music is intentionally distinct from a voice note: album artwork and
      // metadata lead the card, while the shared player guarantees that only
      // one voice/music item owns audio focus at a time.
      MusicBubble({
        msgId: this.msg.id,
        durationSec: this.msg.videoDuration,
        isOutgoing: this.msg.isOutgoing,
        audioFileId: this.msg.videoFileId,
        audioPath: this.msg.videoPath,
        fileSize: this.msg.videoFileSize,
        fileName: this.msg.videoFileName,
        title: this.msg.audioTitle,
        performer: this.msg.audioPerformer,
        coverPath: this.msg.photoPath,
        coverFailed: this.msg.photoFailed,
        downloadProgress: this.liveVideoProgress,
        downloadFailed: this.msg.videoFailed,
        downloadActive: this.msg.mediaDownloadActive,
        queuePosition: this.audioQueuePosition,
        queueLength: this.audioQueueLength,
        hasPrevious: this.audioHasPrevious,
        hasNext: this.audioHasNext,
        maxWidth: this.inlineMaxW(),
        onToggle: (): void => { if (this.gestureClaimed) { return; } this.onAudioTap(this.msg.id); },
        onPrevious: (): void => { if (this.gestureClaimed) { return; } this.onAudioPrevious(this.msg.id); },
        onNext: (): void => { if (this.gestureClaimed) { return; } this.onAudioNext(this.msg.id); },
        onSeek: (fraction: number): void => { this.onAudioSeek(this.msg.id, fraction); }
      });
      if (this.msg.text !== '') {
        Column() {
          this.richContent(this.msg.text, this.msg.textEntities, this.inlineMaxW());
          // 见上：配文的译文原来无处可显示。
          this.translationBlock();
        }.margin({ top: 5 });
      }
    } else if (this.msg.contentType === 'file') {
      FileBubble({
        fileId: this.msg.videoFileId,
        fileName: this.msg.videoFileName,
        mimeType: this.msg.videoMimeType,
        fileSize: this.msg.videoFileSize,
        filePath: this.msg.videoPath,
        downloadProgress: this.liveVideoProgress,
        downloadFailed: this.msg.videoFailed,
        downloadActive: this.msg.mediaDownloadActive,
        maxWidth: this.inlineMaxW(),
        // 长按弹菜单/左滑回复会认领手势；FileBubble 是子组件、看不到认领标记，
        // 早退只能在这层闭包里做——否则长按文件消息弹菜单的同时把下载也触发了。
        onOpen: (): void => {
          if (this.gestureClaimed) { return; }
          this.onFileTap(this.msg.id);
        },
        onSave: (): void => {
          if (this.gestureClaimed) { return; }
          this.onFileSave(this.msg.id);
        },
        onPause: (): void => {
          if (this.gestureClaimed) { return; }
          this.onFilePause(this.msg.id);
        }
      });
      if (this.msg.text !== '') {
        Column() {
          this.richContent(this.msg.text, this.msg.textEntities, this.inlineMaxW());
          // 见上：配文的译文原来无处可显示。
          this.translationBlock();
        }.margin({ top: 5 });
      }
    } else if (this.msg.contentType === 'contact') {
      ContactBubble({
        firstName: this.msg.contactFirstName,
        lastName: this.msg.contactLastName,
        phone: this.msg.contactPhone,
        vcard: this.msg.contactVcard,
        userId: this.msg.contactUserId,
        avatarPath: this.msg.contactAvatarPath,
        maxWidth: this.inlineMaxW(),
        onOpen: (): void => {
          if (this.gestureClaimed) { return; }
          this.onContactOpen(
            this.msg.contactUserId,
            this.msg.contactPhone,
            this.msg.contactVcard
          );
        },
        onCall: (): void => { if (this.gestureClaimed) { return; } this.onPhoneOpen(this.msg.contactPhone); }
      });
    } else if (this.msg.contentType === 'location' || this.msg.contentType === 'venue') {
      LocationBubble({
        latitude: this.msg.locationLatitude,
        longitude: this.msg.locationLongitude,
        accuracy: this.msg.locationAccuracy,
        valid: this.msg.locationValid,
        livePeriod: this.msg.locationLivePeriod,
        expiresIn: this.msg.locationExpiresIn,
        messageDate: this.msg.date,
        nowSec: this.nowSec,
        venueTitle: this.msg.venueTitle,
        venueAddress: this.msg.venueAddress,
        venueProvider: this.msg.venueProvider,
        proximityRadius: this.msg.locationProximityRadius,
        maxWidth: this.inlineMaxW(),
        sharing: this.liveSharingId !== 0 && this.liveSharingId === this.msg.id,
        onStopLive: (): void => { if (this.gestureClaimed) { return; } this.onStopLiveLocation(); },
        onOpen: (): void => {
          if (this.gestureClaimed) { return; }
          this.onLocationOpen(
            this.msg.locationLatitude,
            this.msg.locationLongitude,
            this.locationLabel(),
            this.msg.locationValid
          );
        }
      });
    } else if (this.msg.contentType === 'poll') {
      PollBubble({
        messageId: this.msg.id,
        question: this.msg.pollQuestion,
        options: this.msg.pollOptions,
        totalVoterCount: this.msg.pollTotalVoterCount,
        isAnonymous: this.msg.pollIsAnonymous,
        isQuiz: this.msg.pollIsQuiz,
        allowMultiple: this.msg.pollAllowMultiple,
        correctOptionId: this.msg.pollCorrectOptionId,
        explanation: this.msg.pollExplanation,
        closeDate: this.msg.pollCloseDate,
        isClosed: this.msg.pollIsClosed,
        pending: this.msg.pollVotePending,
        errorText: this.msg.pollVoteError,
        nowSec: this.nowSec,
        revision: this.pollRevision(),
        maxWidth: this.inlineMaxW(),
        onVote: (messageId: number, optionIds: number[]): void => {
          if (this.gestureClaimed) { return; }
          this.onPollVote(messageId, optionIds);
        }
      });
    } else if (this.msg.contentType === 'dice') {
      DiceBubble({
        emoji: this.msg.diceEmoji,
        value: this.msg.diceValue,
        hasFinalState: this.msg.diceHasFinalState,
        successFrame: this.msg.diceSuccessFrame,
        stickerPath: this.msg.stickerPath,
        layerPaths: this.msg.diceLayerPaths
      });
    } else if (this.msg.contentType === 'game') {
      GameBubble({
        messageId: this.msg.id,
        title: this.msg.gameTitle,
        shortName: this.msg.gameShortName,
        description: this.msg.gameDescription,
        gameText: this.msg.gameText,
        photoPath: this.msg.photoPath,
        photoFileId: this.msg.photoFileId,
        photoProgress: this.livePhotoProgress,
        photoFailed: this.msg.photoFailed,
        maxWidth: this.inlineMaxW(),
        onOpen: (messageId: number): void => { if (this.gestureClaimed) { return; } this.onGameOpen(messageId); },
        onRetryPhoto: (messageId: number): void => { if (this.gestureClaimed) { return; } this.onGamePhotoRetry(messageId); }
      });
    } else if (this.msg.contentType === 'paidMedia') {
      PaidMediaBubble({
        messageId: this.msg.id,
        locked: this.msg.paidMediaLocked,
        starCount: this.msg.paidMediaStarCount,
        mediaCount: this.msg.paidMediaCount,
        mediaKind: this.msg.paidMediaKind,
        caption: this.msg.text,
        photoPath: this.msg.photoPath,
        photoFileId: this.msg.photoFileId,
        photoProgress: this.livePhotoProgress,
        photoFailed: this.msg.photoFailed,
        pending: this.paidMediaPending,
        maxWidth: this.inlineMaxW(),
        onUnlock: (messageId: number): void => { if (this.gestureClaimed) { return; } this.onPaidMediaUnlock(messageId); },
        onOpen: (messageId: number): void => { if (this.gestureClaimed) { return; } this.onPaidMediaOpen(messageId); },
        onRetryPhoto: (messageId: number): void => {
          if (this.gestureClaimed) { return; }
          this.onSpecialPhotoRetry(messageId);
        }
      });
    } else if (this.msg.contentType === 'gift') {
      GiftBubble({
        messageId: this.msg.id,
        kind: this.msg.giftKind,
        title: this.msg.giftTitle,
        value: this.msg.giftValue,
        status: this.msg.giftStatus,
        text: this.msg.text,
        code: this.msg.giftCode,
        refunded: this.msg.giftRefunded,
        photoPath: this.msg.photoPath,
        photoFileId: this.msg.photoFileId,
        photoProgress: this.livePhotoProgress,
        photoFailed: this.msg.photoFailed,
        maxWidth: this.inlineMaxW(),
        onRetryPhoto: (messageId: number): void => {
          if (this.gestureClaimed) { return; }
          this.onSpecialPhotoRetry(messageId);
        },
        onCopyCode: (code: string): void => { if (this.gestureClaimed) { return; } this.onGiftCodeCopy(code); }
      });
    } else if (this.msg.contentType === 'giveaway') {
      GiveawayBubble({
        messageId: this.msg.id,
        state: this.msg.giveawayState,
        winnerCount: this.msg.giveawayWinnerCount,
        prize: this.msg.giveawayPrize,
        description: this.msg.giveawayDescription,
        selectionDate: this.msg.giveawaySelectionDate,
        unclaimedCount: this.msg.giveawayUnclaimedCount,
        originalMessageId: this.msg.giveawayMessageId,
        boostedChatId: this.msg.giveawayBoostedChatId,
        refunded: this.msg.giveawayRefunded,
        onlyNewMembers: this.msg.giveawayOnlyNewMembers,
        photoPath: this.msg.photoPath,
        maxWidth: this.inlineMaxW(),
        onOpenOriginal: (chatId: number, messageId: number): void => {
          if (this.gestureClaimed) { return; }
          this.onGiveawayOpen(chatId, messageId);
        }
      });
    } else if (this.msg.contentType === 'emoji' || this.msg.contentType === 'customEmoji') {
      // Keep the Unicode alternative visible while a custom emoji resolves;
      // a small corner state communicates loading without replacing it.
      Stack() {
        if (this.msg.text !== '') {
          Text(this.msg.text)
            .fontSize(this.msg.contentType === 'customEmoji' ? 52 : 56)
            .textAlign(TextAlign.Center);
        } else {
          Text($r('app.string.mb_emoji_unavailable'))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium);
        }
        if (this.msg.contentType === 'customEmoji') {
          Column() {
            if (this.msg.photoFailed) {
              this.stickerStatusBadge(true, 0);
            } else {
              LoadingProgress().width(14).height(14).color(this.accent())
                .backgroundColor('#CCFFFFFF').borderRadius(9).padding(2);
            }
          }
          .width('100%').height('100%')
          .padding({ right: 1, top: 1 })
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.End);
        }
      }
      .width(72).height(68)
      .alignContent(Alignment.Center)
      .onClick(() => {
        if (this.gestureClaimed) { return; }
        if (this.msg.contentType === 'customEmoji' && this.msg.photoFailed) {
          this.onStickerRetry(this.msg.id);
        }
      })
      .accessibilityText(this.msg.contentType === 'customEmoji'
        ? (this.msg.photoFailed ? str('mb_custom_emoji_failed') : str('mb_custom_emoji_loading'))
        : this.msg.text);
    } else if (this.msg.contentType === 'sticker') {
      Stack() {
        if (this.stickerAnimationSuspended() && this.msg.photoPath === '') {
          this.stickerPausedFallback();
        } else if (this.stickerPlaybackFailed && this.msg.photoPath !== '') {
          Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath).draggable(false)
            .width(this.stickerW()).height(this.stickerH()).objectFit(ImageFit.Contain);
        } else if (this.stickerAnimationSuspended() && this.msg.photoPath !== '') {
          Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath).draggable(false)
            .width(this.stickerW()).height(this.stickerH()).objectFit(ImageFit.Contain);
        } else if (!this.stickerPlaybackFailed &&
          this.msg.stickerFormat === 'tgs' && this.msg.stickerPath !== '') {
          TgsStickerView({ tgsPath: this.msg.stickerPath, thumbPath: this.msg.photoPath,
            boxWidth: this.stickerW(), boxHeight: this.stickerH(),
            powerCategory: this.msg.isEmojiSticker ? 'emojiChat' : 'sticker',
            chatTimeline: true,
            onFailed: (): void => { this.stickerPlaybackFailed = true; } })
            .hitTestBehavior(HitTestMode.None);
        } else if (!this.stickerPlaybackFailed &&
          this.msg.stickerFormat === 'webm' && this.msg.stickerPath !== '') {
          SmartLoopVideo({ videoPath: this.msg.stickerPath, thumbPath: this.msg.photoPath,
            boxWidth: this.stickerW(), boxHeight: this.stickerH(),
            powerCategory: this.msg.isEmojiSticker ? 'emojiChat' : 'sticker',
            onPlaybackFailed: (): void => { this.stickerPlaybackFailed = true; } })
            .hitTestBehavior(HitTestMode.None);
        } else if (this.msg.photoPath !== '') {
          Image(this.msg.photoPath.startsWith('/') ? `file://${this.msg.photoPath}` : this.msg.photoPath).draggable(false)
            .width(this.stickerW()).height(this.stickerH()).objectFit(ImageFit.Contain)
            .transition(TransitionEffect.OPACITY.animation({
              duration: this.effectDuration(180), curve: Curve.EaseOut
            }));
        } else if (this.msg.photoFileId === 0 && this.msg.stickerFileId === 0) {
          this.stickerUnavailable();
        } else {
          Stack()
            .width(this.stickerW()).height(this.stickerH())
            .backgroundColor('#10000000').borderRadius(18);
        }

        if (this.msg.stickerPath === '' && this.msg.stickerFileId !== 0) {
          Column() {
            this.stickerStatusBadge(this.msg.stickerFailed,
              this.liveStickerProgress > 0 ? this.liveStickerProgress : this.livePhotoProgress);
          }
          .width('100%').height('100%')
          .padding({ right: 7, top: 7 })
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.End);
        } else if (this.msg.photoPath === '' && this.msg.photoFileId !== 0) {
          Column() {
            this.stickerStatusBadge(this.msg.photoFailed, this.livePhotoProgress);
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center);
        } else if (this.stickerPlaybackFailed) {
          Column() {
            this.stickerStatusBadge(true, 0);
          }
          .width('100%').height('100%')
          .padding({ right: 7, top: 7 })
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.End);
        }
      }
      .width(this.stickerW()).height(this.stickerH())
      .onClick(() => {
        if (this.gestureClaimed) { return; }
        if (this.stickerPlaybackFailed) {
          this.stickerPlaybackFailed = false;
          return;
        }
        if (this.msg.stickerFailed || this.msg.photoFailed) {
          this.onStickerRetry(this.msg.id);
        }
      })
      .accessibilityText(this.msg.stickerFailed || this.msg.photoFailed || this.stickerPlaybackFailed
        ? $r('app.string.mb_sticker_failed') : $r('app.string.sticker_tab'));
    } else if (this.msg.isUnsupportedMessage) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.info_circle'))
          .fontSize(20).fontColor([this.accent()]).width(22);
        Column({ space: 1 }) {
          Text(this.fallbackLabel())
            .fontSize(13).fontColor(bubbleTextFor(this.msg.isOutgoing)).fontWeight(FontWeight.Medium)
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text() {
            Span($r('app.string.mb_partial_content')).fontColor(COLOR_TEXT_SECONDARY);
            Span(this.timeReserve()).fontSize(12).fontColor(Color.Transparent);
          }.fontSize(11);
        }.alignItems(HorizontalAlign.Start);
      }
      .constraintSize({ maxWidth: this.inlineMaxW() })
      .padding({ top: 2, bottom: 2 })
      .accessibilityText(str('mb_fallback_partial', this.fallbackLabel()));
    } else {
      Text() {
        Span(this.fallbackLabel()).fontColor(COLOR_TEXT_SECONDARY);
        Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
      }.fontSize(this.msgTextSize);
    }
  }

  private pollRevision(): string {
    let revision = `${this.msg.pollId}_${this.msg.pollIsClosed}_${this.msg.pollTotalVoterCount}` +
      `_${this.msg.pollVotePending}_${this.msg.pollCorrectOptionId}`;
    this.msg.pollOptions.forEach((option, index: number): void => {
      revision += `_${index}_${option.voterCount}_${option.votePercentage}` +
        `_${option.isChosen}_${option.isBeingChosen}`;
    });
    return revision;
  }

  // Big bare emoji / stickers render without bubble background/tail, like bare media.
  // 圆形视频同理：在 Telegram 里圆本身就是消息，外面再套一层圆角矩形气泡
  // 会变成"方框里嵌个圆"，很难看。
  private isBareEmoji(): boolean {
    return this.msg.contentType === 'emoji' || this.msg.contentType === 'sticker'
      || this.msg.contentType === 'customEmoji' || this.msg.contentType === 'videoNote';
  }

  // Sticker display box: longest side capped, aspect preserved (512 fallback).
  private stickerW(): number {
    const w = this.msg.photoWidth > 0 ? this.msg.photoWidth : 512;
    const h = this.msg.photoHeight > 0 ? this.msg.photoHeight : 512;
    return w >= h ? STICKER_MAX : Math.round(STICKER_MAX * (w / h));
  }

  private stickerH(): number {
    const w = this.msg.photoWidth > 0 ? this.msg.photoWidth : 512;
    const h = this.msg.photoHeight > 0 ? this.msg.photoHeight : 512;
    return h >= w ? STICKER_MAX : Math.round(STICKER_MAX * (h / w));
  }

  private stickerAnimationSuspended(): boolean {
    if (this.msg.stickerFormat !== 'tgs' && this.msg.stickerFormat !== 'webm') {
      return false;
    }
    if (this.powerSaving || this.reduceAnim) {
      return true;
    }
    if (this.msg.isEmojiSticker) {
      return !this.emojiEnabled || !this.emojiChatEnabled;
    }
    return !this.stickersEnabled || !this.stickerAutoplay;
  }

  private locationLabel(): string {
    const title = this.msg.venueTitle.trim();
    const address = this.msg.venueAddress.trim();
    if (title !== '' && address !== '') {
      return `${title}，${address}`;
    }
    return title !== '' ? title : address;
  }

  // Whether the timestamp overlay should reserve space at the end of the last
  // text line (only when the time actually lands there — not when reactions
  // or a comments bar sit below the text).
  // 「翻译中 / 翻译失败」这一行也是气泡的最后一行。它出现时 translatedText
  // 还是空，所以不能只按"有没有译文"分流——漏了这一支，占位会留在正文里，
  // 时间戳浮在状态行上面，和「重试」两个字叠在一起（实测截图）。
  private hasTranslationStatusRow(): boolean {
    return this.msg.translatedText === '' && this.translationStatus !== null;
  }

  // 气泡自身的填充色。叠压头像的间隙圈要取它，才能读作"挖空"而不是描边。
  private bubbleFillColor(): ResourceColor {
    if (this.appearanceEpoch < 0) {
      return Color.Transparent; // 只为让 ArkUI 记下对 epoch 的依赖
    }
    if (this.msg.isOutgoing) {
      return this.themeBubbleOut !== '' ? this.themeBubbleOut : COLOR_BUBBLE_OUT;
    }
    return COLOR_BUBBLE_IN;
  }

  // 尾巴：材质开着时是一小块裁成三角的玻璃（和气泡同一套材质），否则实色 Polygon。
  @Builder
  bubbleTail(outgoing: boolean) {
    if (this.glassReady()) {
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

  // 材质开着时气泡本体透明，底色/材质/模糊都挂在外层「尾巴 + 气泡」容器上。
  private bubbleBg(): ResourceColor {
    return this.glassReady() ? this.glassBg() : this.bubbleFillColor();
  }

  private glassLive(): boolean {
    return this.bubbleMaterialLive() && !this.isBareEmoji();
  }

  // 玻璃**真的画出来**的条件：想画（glassLive）之外还要**已经量到尺寸**。
  //
  // 玻璃档的形状全靠 clipShape，而 clipShape 要等 onAreaChange 把 glassW/glassH
  // 填上才挂得上（见 bubbleGlassModifier）。原来上色只看 glassLive、裁剪却要
  // 尺寸，两者不同步——「已上色、还没量到」的那一帧画的是**没裁剪的矩形**：
  // 整块玻璃连尾巴留白一起涂满、没有尾巴、没有那条描边，左边缘因此比正常位置
  // 外扩一个 bubbleTailGutter（7vp）。量到之后裁剪挂上，边缘再弹回来。
  // 判据本体是纯函数 glassPaintReady，单测在 BubbleGlassPath.test.ets。
  private glassReady(): boolean {
    return glassPaintReady(this.glassLive(), this.glassW, this.glassH);
  }

  // 玻璃档：气泡和尾巴用**同一套**普通渲染（玻璃色 + 背景模糊）。
  //
  // 不用系统材质：材质是合成层、不吃 clipShape，尾巴那种三角形状挂不上去，只能
  // 退成普通渲染——一边材质一边普通，两块颜色对不齐，看着就不是一体的（用户报的）。
  // 统一成普通渲染后两者严丝合缝，代价是没有沉浸光感的动态高光。
  private glassBg(): ResourceColor {
    return this.glassReady() ? overlayGlassFill('bubble', this.bubbleFillColor()) : Color.Transparent;
  }

  private glassBlur(): number {
    return this.glassReady() ? overlayBackdropBlur('bubble') : 0;
  }

  // 材质本体按节点的 borderRadius 画圆角，裁剪路径只管尾巴那一侧：尾巴侧的底角设 0。
  private glassRadius(): BorderRadiuses {
    const r = this.bubbleCornerRadius();
    if (!this.hasBubbleTail()) {
      return r;
    }
    return this.msg.isOutgoing
      ? { topLeft: r.topLeft, topRight: r.topRight, bottomRight: 0, bottomLeft: r.bottomLeft }
      : { topLeft: r.topLeft, topRight: r.topRight, bottomRight: r.bottomRight, bottomLeft: 0 };
  }

  // 材质的边框只沿节点自身的 border-box 画。尾巴那一侧（气泡的那条竖边 + 三角的
  // 两条斜边）在整体轮廓里、却在矩形外，材质画不到，裁剪之后那半圈是秃的——
  // 顶/右/底有边、左边和尾巴没有。自己沿整条轮廓补一圈同色发丝线，四面才统一。
  // 画在 .background() 里：背景节点不参与命中测试，绝不会吃掉点击和长按
  // （这正是当初「玻璃气泡整块点不动」的真凶，裁剪是背锅的）。
  @Builder
  glassOutline() {
    if (this.glassReady()) {
      Path({ width: this.glassW, height: this.glassH })
        .commands(glassOutlineCommands(this.glassW, this.glassH, this.msg.isOutgoing,
          this.hasBubbleTail(), this.bubbleCornerRadius()))
        .fill(Color.Transparent)
        .stroke(GLASS_OUTLINE_COLOR)
        .strokeWidth(GLASS_OUTLINE_WIDTH);
    }
  }

  private timeReserveInText(): boolean {
    // 最后一行是翻译脚注或翻译状态行时，时间戳的占位改由那一行承担。
    return this.msg.reactions.length === 0 && this.msg.translatedText === '' &&
      !this.hasTranslationStatusRow();
  }

  private timeReserveOnFooter(): boolean {
    return this.msg.reactions.length === 0 && this.msg.translatedText !== '';
  }

  private timeReserveOnStatus(): boolean {
    return this.msg.reactions.length === 0 && this.hasTranslationStatusRow();
  }

  // Bare media at the bubble's bottom edge → the timestamp needs a translucent
  // chip over the image instead of plain gray text.
  private timeOnMedia(): boolean {
    if (this.msg.reactions.length > 0) {
      return false;
    }
    if (this.albumPaths.length > 1) {
      return this.albumCaption === '';
    }
    if (this.isBareEmoji()) {
      return true;
    }
    return (this.msg.contentType === 'photo' || this.msg.contentType === 'video') && this.msg.text === '';
  }

  // The timestamp Stack used to shrink to the message body even when a long
  // sender/forward label or reply preview made the surrounding bubble wider.
  // Reuse the measured shell width so BottomEnd always means the bubble's real
  // lower-right corner, while short bubbles can still remain shrink-to-fit.
  private measuredTimeLayerWidth(): number {
    if (this.isBareEmoji()) {
      return 0;
    }
    // 正文本来就在这个 Stack 里、天然参与它的固有宽度，不需要在这里照顾；
    // 需要照顾的只有排在 Stack 外面、可能比正文更宽的那几个标签。
    const widest: number = Math.max(this.forwardLabelW,
      Math.max(this.senderLabelW, this.commentsRowW));
    if (widest <= 0) {
      return 0;
    }
    return Math.min(this.inlineMaxW(), widest);
  }

  // Timestamp (+ send status) overlaid at the bubble's bottom-right, sharing
  // the last line with the message text (space reserved by timeReserve()).
  @Builder
  timeOverlay() {
    Row({ space: 4 }) {
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
    .padding(this.timeOnMedia() ? { left: 5, right: 5, top: 1, bottom: 1 } : { left: 0 })
    .backgroundColor(this.timeOnMedia() ? '#00000066' : Color.Transparent)
    .borderRadius(8)
    .margin(this.timeOnMedia() ? { right: 6, bottom: 6 } : { right: 0, bottom: 2 });
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

  // Service/system messages (title/photo changes, joins, pins, ...) render as
  // a centered pill, never as a left/right chat bubble. A "video chat started"
  // pill is tappable — but only while the chat's video chat is still live —
  // and opens the live viewer with that call's id.
  private liveVideoChatTappable(): boolean {
    return this.msg.isVideoChatStarted && this.liveGroupCallId > 0;
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
        .fontColor([this.liveVideoChatTappable() ? this.accent() : COLOR_TEXT_SECONDARY])
        .width(14);
      Text(this.fallbackLabel())
        .fontSize(12)
        .fontColor(this.liveVideoChatTappable() ? this.accent() : COLOR_TEXT_SECONDARY)
        .fontWeight(this.liveVideoChatTappable() ? FontWeight.Medium : FontWeight.Regular)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: this.screenW * 0.68 });
      if (this.liveVideoChatTappable()) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(10).fontColor([this.accent()]).width(10);
      }
    }
    .constraintSize({ maxWidth: this.screenW * 0.82 })
    .backgroundColor(this.liveVideoChatTappable() ? '#183478F6' : $r('app.color.system_pill'))
    .border({
      width: 0.5,
      color: this.liveVideoChatTappable() ? '#303478F6' : '#16FFFFFF'
    })
    .borderRadius(12)
    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
    .stateStyles({
      normal: this.systemPillNormalStyle,
      pressed: this.systemPillPressedStyle
    })
    .animation({ duration: this.effectDuration(100), curve: Curve.EaseOut })
    .onClick((): void => {
      if (this.gestureClaimed) { return; }
      if (this.liveVideoChatTappable()) {
        this.onLiveStreamTap(this.liveGroupCallId);
      }
    })
    .accessibilityText(this.liveVideoChatTappable()
      ? str('mb_fallback_open', this.fallbackLabel()) : this.fallbackLabel());
  }

  build() {
    if (this.msg.contentType === 'hidden') {
      // Filtered service notice (e.g. channel paid-DM price) — render nothing.
      Column().height(0);
    } else if (this.msg.contentType === 'system') {
      Column() {
        if (this.dateLabel !== '') {
          Text(this.dateLabel)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.system_pill')).borderRadius(11)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .margin({ bottom: 4 });
        }
        this.systemPill();
      }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 3, bottom: 3 });
    } else {
    Column() {
      if (this.dateLabel !== '') {
        // Day-change separator pill, centered ("7-6" / "2024-12-31").
        Row() {
          Text(this.dateLabel)
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.system_pill')).borderRadius(11)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 });
        }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 5, bottom: 3 });
      }
      if (this.showUnreadDivider) {
        Text($r('app.string.mb_unread'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').textAlign(TextAlign.Center)
          .backgroundColor($r('app.color.system_pill'))
          .padding({ top: 3, bottom: 3 }).margin({ bottom: 4 });
      }
      Row() {
      // 内层这一行按内容宽度，只裹住头像和气泡——消息菜单绑在它身上，
      // 抬起来的预览才是"头像 + 气泡"。绑到外面那层满宽的行上，浮起来的会是
      // 一条通栏横条，右边一大片空白也跟着抬。满宽那层继续负责左滑和对齐。
      Row() {
      if (this.isGroup && !this.msg.isOutgoing) {
        if (this.showAvatar) {
          // LiveSenderAvatar, not AvatarView directly: the path arrives via the
          // sender-avatar side channel and swaps in place — the row itself never
          // rebuilds for an avatar (see senderAvatarChannel).
          LiveSenderAvatar({
            senderId: this.msg.senderId,
            senderIsUser: this.msg.senderIsUser,
            initialPath: this.msg.senderAvatarPath,
            initials: this.msg.senderInitials
          })
            .margin({ right: 6 })
            .onClick(() => {
              if (this.gestureClaimed) { return; }
              // Group message avatar → that user's profile page.
              if (this.msg.senderIsUser && this.msg.senderId > 0) {
                this.onAvatarTap(this.msg.senderId);
              }
            })
            .gesture(LongPressGesture().onAction(() => {
              if (this.msg.senderIsUser && this.msg.senderId > 0) {
                this.onAvatarLongPress(this.msg.senderId, this.msg.senderName);
              }
            }));
        } else {
          // Mid-run row: keep the avatar column's width so bubbles stay aligned.
          Column().width(44);
        }
      }
      // Telegram-style bubble tail poking out of the bottom corner (left for
      // incoming, right for outgoing); the adjacent bubble corner is squared off.
      Row() {
      if (!this.msg.isOutgoing && this.hasBubbleTail()) {
        this.bubbleTail(false);
      } else if (!this.msg.isOutgoing) {
        Column().width(this.bubbleTailGutter());
      }
      Column() {
        if (this.msg.forwardFrom !== '') {
          // Tappable when the origin is known — opens the original post, or the
          // author's chat. A hidden-origin forward carries no ids and stays inert.
          Text(str('mb_forwarded_from', this.msg.forwardFrom)).fontSize(13).fontColor(this.accent())
            .fontWeight(FontWeight.Medium).margin({ bottom: 2 })
            .constraintSize({ maxWidth: this.inlineMaxW() })
            .onAreaChange((_old: Area, area: Area): void => {
              this.forwardLabelW = area.width as number;
            })
            .onClick(() => {
              if (this.gestureClaimed) { return; }
              if (this.msg.forwardOriginChatId !== 0 || this.msg.forwardOriginUserId !== 0) {
                this.onForwardTap(this.msg.forwardOriginChatId, this.msg.forwardOriginMsgId,
                  this.msg.forwardOriginUserId);
              }
            });
        }
        if (this.isGroup && !this.msg.isOutgoing && this.msg.senderName !== '' && this.showSenderName) {
          // 名字和身份标签同一行。标签自订阅（见 SenderRoleTag），名单到货时
          // 只有那一枚小标签换字，不会牵动整行重建。
          Row({ space: 5 }) {
            Text(this.msg.senderName).fontSize(14).fontColor(this.senderColor())
              .fontWeight(FontWeight.Medium)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .flexShrink(1);
            SenderRoleTag({ chatId: this.chatId, senderId: this.msg.senderId,
              presetTag: this.msg.senderTag });
          }
          .margin({ bottom: 2 })
          .alignItems(VerticalAlign.Center)
          .onAreaChange((_old: Area, area: Area): void => {
            this.senderLabelW = area.width as number;
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
          minWidth: Math.min(this.inlineMaxW(), this.senderLabelW)
        })
        if (this.isChannel && this.msg.commentCount > 0) {
          Column() {
            this.commentsRow();
          }
          .onAreaChange((_old: Area, area: Area): void => {
            this.commentsRowW = area.width as number;
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
      // 刻意没有另加一层视觉包装节点：材质挂在上层 Row（bubbleGlassModifier）、
      // 手势与命中都挂在本节点，插节点会动到材质/裁剪/命中三者的相对关系。
      .stateStyles({
        normal: this.bubbleNormalStyle,
        pressed: this.bubblePressedStyle
      })
      .constraintSize({ maxWidth: this.bubbleMaxW() })
      .backgroundColor(this.isBareEmoji() ? Color.Transparent : this.bubbleBg())
      .backdropBlur(this.glassBlur())
      .onVisibleAreaChange([0, 0.01], (visible: boolean): void => {
        this.onScreen = visible;
      })
      // Adjacent rows share a restrained 7vp corner. Only the final row gets
      // the tight tail corner; a single-row run keeps the configured top arc.
      .borderRadius(this.bubbleCornerRadius())
      .padding(this.isBareEmoji() ? 0 : 8)
      .shadow(this.isBareEmoji() ? { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
        : { radius: 2, color: '#14000000', offsetX: 0, offsetY: 1 })
      .onAreaChange((_old: Area, area: Area) => { this.bubbleW = area.width as number; })
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
        LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
          .onAction((event: GestureEvent): void => { this.onLongPress(event); })
      )
      // 单击出菜单只在新交互下挂。用 .onClick 而不是塞进上面那个
      // parallelGesture：官方文档明写父子都绑点击手势时**子组件优先、父组件
      // 不触发**，正是我们要的——点链接、点图片、点内联按钮各归各，只有落在
      // 气泡空白处的点击才轮到菜单。而 parallelGesture 是例外，它父子都会触发，
      // 用它就会出现"点链接同时开链接和菜单"。
      .onClick((event: ClickEvent): void => {
        if (this.gestureClaimed) { return; }
        if (messageGesturePolicy(this.gestureScheme).tapOpensMenu) {
          // 单击出菜单的方案下同样跟手。ClickEvent.x 已经是局部坐标。
          this.recordMenuOffset(event.x);
          this.msgContextMenuShown = true;
        }
      })
      if (this.msg.isOutgoing && this.hasBubbleTail()) {
        this.bubbleTail(true);
      } else if (this.msg.isOutgoing) {
        Column().width(this.bubbleTailGutter());
      }
      }
      // 「尾巴 + 气泡」整块由**上层**渲染：材质挂在这一层，形状由整体轮廓裁剪
      // 给出（圆角矩形 + 三角尾巴）。尾巴在布局里只占位——两者天生一体，
      // 不存在「一边材质一边普通渲染」对不齐的问题。
      .alignItems(VerticalAlign.Bottom)
      .backgroundColor(this.glassBg())
      .backdropBlur(this.glassBlur())
      // 材质自带的边框沿**本节点的 border-box** 画，而且吃 borderRadius。不设圆角
      // 它就画一个直角矩形框，被轮廓裁掉左边/底边后只剩顶边一条直线拐到右边——
      // 真机上就是用户报的「气泡描边不对」。设成气泡自己的圆角，这条边框就和轮廓
      // 重合（尾巴那侧仍由裁剪负责）。
      .borderRadius(this.glassRadius())
      .background(this.glassOutline(), { align: Alignment.TopStart })
      .attributeModifier(bubbleGlassModifier(this.glassReady(), this.glassW, this.glassH,
        this.msg.isOutgoing, this.hasBubbleTail(), this.bubbleCornerRadius(),
        this.bubbleMaterialOn ? (w: number, h: number): void => {
          probeGlassMeasure('rich', this.msg.id, w, h);
          this.glassW = w;
          this.glassH = h;
        } : null))
      }
      .alignItems(VerticalAlign.Bottom)
      .bindContextMenu(this.msgContextMenuShown, this.msgContextMenu(), {
        onAppear: (): void => {
          logW(`[Menu114] menu appear id=${this.msg.id}`);
        },
        // 朝手指那一侧挪。ArkUI 自己会把菜单夹在屏幕内，所以极端偏移不会出界。
        offset: { x: this.menuOffsetX, y: 0 },
        // A play-slot bubble hosts a XComponentType.SURFACE video surface that
        // componentSnapshot cannot capture (see hasLiveVideoSurface()) — fall
        // back to no preview there instead of lifting a black rectangle.
        preview: (this.hasLiveVideoSurface() || this.compactMenuContext())
          ? MenuPreviewMode.NONE : MenuPreviewMode.IMAGE,
        previewBorderRadius: this.bubbleCornerRadius(),
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
        mask: {
          color: '#52000000',
          backgroundBlurStyle: BlurStyle.BACKGROUND_THIN
        },
        modalMode: ModalMode.TARGET_WINDOW,
        hapticFeedbackMode: HapticFeedbackMode.AUTO,
        onDisappear: (): void => {
          logW(`[Menu114] menu disappear id=${this.msg.id}`);
          this.msgContextMenuShown = false;
        }
      });
      }
      .width('100%').padding({
        left: 10, right: 10,
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
        PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 8 })
          .onActionUpdate((event: GestureEvent): void => { this.onSwipeReplyUpdate(event.offsetX); })
          .onActionEnd((): void => { this.onSwipeReplyEnd(); })
          .onActionCancel((): void => { this.onSwipeReplyEnd(); })
      )
      // 每次按下先把认领标记清掉。onTouch 是冒泡事件，落在任何子元素上都会
      // 走到这里，所以这一下一定发生在子元素的点击判定之前。
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) {
          this.gestureClaimed = false;
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
    .transition(this.animateIn
      ? TransitionEffect.translate({ y: 16 })
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: this.effectDuration(220), curve: Curve.FastOutSlowIn })
      : TransitionEffect.IDENTITY);
    }
  }
}
