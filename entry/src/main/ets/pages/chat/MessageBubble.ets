import { promptAction, SymbolGlyphModifier } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { MessageEntry, ReactionInfo, InlineBtn } from '../../store/MessageEntry';
import { PLAY_SLOT_ENTER_RATIO, PLAY_SLOT_KEEP_RATIO, slotKey } from './playSlot';
import { VideoBubbleSurface } from './VideoBubbleSurface';
import { TdObject } from '../../tdkit/TdTypes';
import { getAccentColorStore, getUserStore } from '../../tdkit/Globals';
import { CachedImage } from '../common/CachedImage';
import { KEY_POWER_SMOOTH_TRANSITIONS, powerAnimationDuration } from '../../store/AppSettings';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { rememberLabelWidth, recallLabelWidth } from '../../util/labelWidthMemory';
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
  isUnformattedPlainText, messageUrls, parseFormattedText, richSegmentKey,
  RichSegment, RichRun
} from '../../util/richText';
import { packAlbumRows, AlbumCell } from '../../util/packAlbumRows';
import { albumCellKey, albumRowKey } from '../../util/albumCellKey';
import { inlineButtonKey, inlineButtonRowKey } from '../../util/inlineButtonKey';
import { linkPreviewPresentation, LinkPreviewPresentation } from '../../util/linkPreview';
import { reactionKeyFrom } from '../../util/reactions';
import {
  animationDurationFor, persistentAnimationDurationFor, scrollActiveNow
} from '../../util/scrollEffects';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_OUT, COLOR_BUBBLE_IN, AVATAR_PALETTE, botButtonBg, accentSoft, bubbleTextFor } from '../../util/theme';
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
import { ThumbReadyGate } from './ThumbReadyGate';
import { MessageGesturePolicy, messageGesturePolicy } from '../../util/messageGestures';
import { CHIP_ICON_VP, reactionChipWidth, reactionsRowWidth } from '../../util/reactionsWidth';
import { logW } from '../../util/log';
import { isLivePhotoVideo } from '../../util/livePhoto';
import { menuPreviewCompact } from '../../util/menuPreview';

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

// @Builder 的动态参数必须整体装进一个对象字面量再传。ArkUI 官方约束是：
// 按引用传递只在「单参数 + 调用处直接传对象字面量」时支持内部 UI 刷新；多个
// 参数是按值快照，消息气泡被复用后会继续拿上一条消息的 text/entities。
//
// 这里分两层都做成单参数：只改 richContent 还不够，它里面的 richRuns 原来也有
// 三个参数，外层虽然拿到了新分段，最内层 Text 仍可能保留上一条的 runs。
interface RichRunsBuilderParams {
  runs: RichRun[];
  maxWidth: number;
  isLastSegment: boolean;
}

interface RichContentBuilderParams {
  text: string;
  entities: TdObject[];
  maxWidth: number;
}

// MessageBubble remains the complete renderer. ChatPage mounts it through a
// thin shell that owns the page-level callbacks. Component-level reuse is
// deliberately disabled on the message tree: HarmonyOS 7.0 can double-free a
// TextPattern while purging that cache as ChatPage is destroyed.

// 群消息的发送者头像。路径经 senderAvatarChannel 旁路直达这里就地刷新，
// 不触发行重建 —— 头像路径已从行的内容 key 里摘除。
// —— P4 批 3c：成员 @Styles 迁出（V2 不支持成员 @Styles）——————————
// 8 个无状态的直接迁全局；bubble/systemPill 两对按压样式读组件状态，改用
// AttributeModifier 的多态样式（applyPressedAttribute），按条件挑双例之一，
// 零每帧分配。
@Styles
function msgLinkCardNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

@Styles
function msgLinkCardPressedStyle() { .opacity(0.8).scale({ x: 0.986, y: 0.986 }) }

@Styles
function msgLinkRunNormalStyle() { .opacity(1) }

@Styles
function msgLinkRunPressedStyle() { .opacity(0.52) }

@Styles
function msgBotButtonNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

@Styles
function msgBotButtonPressedStyle() { .opacity(0.72).scale({ x: 0.975, y: 0.975 }) }

@Styles
function msgMenuActionNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

@Styles
function msgMenuActionPressedStyle() { .opacity(0.72).scale({ x: 0.97, y: 0.94 }) }

// active=false 的实例按下不做任何变化（内联链接/语音/音频/文件卡自带按压
// 反馈，整泡再暗一层会闪整条消息；不可点的系统丸同理）。
class PressDimModifier implements AttributeModifier<CommonAttribute> {
  private dimOpacity: number;
  private dimScale: number;
  private active: boolean;

  constructor(dimOpacity: number, dimScale: number, active: boolean) {
    this.dimOpacity = dimOpacity;
    this.dimScale = dimScale;
    this.active = active;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    instance.opacity(1);
    instance.scale({ x: 1, y: 1 });
  }

  applyPressedAttribute(instance: CommonAttribute): void {
    instance.opacity(this.active ? this.dimOpacity : 1);
    const s: number = this.active ? this.dimScale : 1;
    instance.scale({ x: s, y: s });
  }
}

const BUBBLE_PRESS_DIM: PressDimModifier = new PressDimModifier(0.84, 0.992, true);
const BUBBLE_PRESS_NONE: PressDimModifier = new PressDimModifier(0.84, 0.992, false);
const SYSTEM_PILL_PRESS_DIM: PressDimModifier = new PressDimModifier(0.72, 0.985, true);
const SYSTEM_PILL_PRESS_NONE: PressDimModifier = new PressDimModifier(0.72, 0.985, false);

// P4 批 3b：迁 @ComponentV2，配方与 LightweightSenderAvatar（批 1）完全一致，
// 判读依据见 2026-09-02-p4-bubble-v2-survey.md 批 0.5 节（1370 真机样本）：
// aboutToReuse 时 @Param 已是新值、@Local 已重置、@Monitor 复用期静默——
// 同步重挂订阅，V1 的 nextFrameQueue 延帧兜底/reuseParam 读参/按 key 保留
// path（#137 修法）整套退役。批 2 已在真机验证过同款（avatar.plain.reuse
// 满速 + kept=true 连串）。原 struct 的 appearanceEpoch/accent() 是从未被
// build 引用的死代码，随迁移清掉。
@ComponentV2
struct LiveSenderAvatar {
  @Param senderId: number = 0;
  @Param senderIsUser: boolean = true;
  @Param initialPath: string = '';
  @Param initials: string = '?';
  // 评论行的头像栈比发送者头像小一圈。
  // 群聊里发送者头像的直径。占位列宽 = 它 + 6 的右外边距，两处必须一起改，
  // 否则连续消息的气泡和带头像那行会错开。
  @Param avatarSize: number = 38;
  @Local private path: string = '';
  // 无装饰器成员复用时不重置（官方表格 + 批 0.5 实测），照旧记订阅与回收态。
  private unsubAvatar: (() => void) | null = null;
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

  // 非复用路径上同一实例真的换了发送者时兜底重挂；复用路径靠 aboutToReuse
  // （@Monitor 复用期静默，批 0.5 实测 0 触发）。第三个参数传 ''：@Param
  // 逐个落地时 initialPath 可能还是上一行的（I-2 串头像坑在非复用路径依旧
  // 成立），最差先显示首字母圆底。
  @Monitor('senderId', 'senderIsUser')
  onSenderChanged(): void {
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
  }

  aboutToReuse(): void {
    // @Param 已是新值、@Local path 已被框架重置（批 0.5 判读）：同步重挂+
    // 重播种即可。initialPath 也是新行的值，I-2 串头像坑在这条路不存在；
    // #137 的「按 key 保留 path」不再需要——同步重播种（通道现值或新行
    // initialPath）的窗口是零帧，比保留旧值更不闪。
    this.attachAvatarChannel(this.senderId, this.senderIsUser, this.initialPath);
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

@ComponentV2
export struct MessageBubble {

  // P4 批 3c：主体迁 @ComponentV2（判读依据 survey 批 0.5 节；配方经批 1/2/3b
  // 三轮真机验证）。全局环境值走 chatEnv 镜像（V2 无 @StorageProp），@Trace
  // 读到即登记依赖；~60 个页面回调转 @Param（V2 禁止父层初始化无装饰器成员，
  // 编译错误 10905324），页面持有的引用全生命周期稳定，每帧只多恒等比较。
  private env: ChatEnvMirror = chatEnv;

  // 强调色是 theme 里的活绑定，读一次 epoch 让 ArkUI 记下依赖，用户改色后即时重绘。
  private accent(): ResourceColor {
    return this.env.appearanceEpoch < 0 ? Color.Transparent : COLOR_PRIMARY;
  }

  // @Monitor fires whenever ChatPage hands down a new msg object (edits, status
  // changes, "replace media", etc.) — not once per frame — so the transition
  // check inside onMsgPropChanged is cheap and only fires onMediaGone on an
  // actual video→non-video flip (see onMsgPropChanged for why this matters).
  // 复用路径它静默（批 0.5 实测），由 aboutToReuse 无条件重挂覆盖。
  @Require @Param msg: MessageEntry;
  @Local private liveSendState: string = '';
  private unsubSendState: (() => void) | null = null;
  // 6 个通道（发送勾 + 4 个下载进度 + 翻译态）当前挂在哪一条消息的 rowId 上。
  // P0-4（审计 3.2b）：这是本组件订阅自愈的唯一依据——「params 里的 msg 是新
  // 是旧」静态判不了，「订阅挂在哪」却是本地可判定的事实。0 = 未挂。
  private attachedRowId: number = 0;
  // Chat-theme outgoing bubble color ('' = the standard theme resource color).
  @Param themeBubbleOut: string = '';
  // 初值 true：行是在 LazyForEach 首批里建出来的，onVisibleAreaChange 的首帧
  // 回调常常不来，初值 false 会让玻璃层等到「滑动一下」才挂上（用户报的）。
  // 由回调负责在真正离屏时关掉——那一路是可靠的。@Local 复用重置回 true。
  @Local onScreen: boolean = true;
  // 「尾巴 + 气泡」外层容器量到的尺寸，整块玻璃的裁剪路径靠它。只在材质开着时被读。
  @Local glassW: number = 0;
  @Local glassH: number = 0;
  @Param nowSec: number = 0;
  // 本机正在共享实时位置的那条消息 id（0 = 没有共享）。
  @Param liveSharingId: number = 0;
  @Param onStopLiveLocation: () => void = (): void => {};
  // 身份标签按群区分（同一个人在别的群未必是管理员），所以标签通道的 key
  // 要带 chatId。MessageEntry 里没有这个字段，由页面传。
  @Param chatId: number = 0;
  @Param isGroup: boolean = false;
  @Param isChannel: boolean = false;
  @Param showUnreadDivider: boolean = false;
  @Param dividerIsResume: boolean = false;
  @Param dateLabel: string = ''; // date pill above this row when the day changes
  @Param albumPaths: string[] = [];
  @Param albumFileIds: number[] = [];
  @Param albumRatios: number[] = [];
  @Param albumMemberIds: number[] = [];
  // Same reasoning as msg above: fires on a new albumIsVideo array reference
  // from ChatPage, not per frame; onAlbumIsVideoChanged only emits when a
  // specific cell actually flips true→false.（复用路径由 aboutToReuse 播种。）
  @Param albumIsVideo: boolean[] = [];
  // 相册里哪几格是实况（见 util/livePhoto）。不挂监视：它只影响角标怎么画，
  // 不参与播放位竞选。复用时并行数组是一条条重新播种的，读一律走带兜底的
  // 访问器——这些数组长度不同步曾经把进程搞崩过。
  @Param albumIsLive: boolean[] = [];
  @Param albumProgress: number[] = [];
  @Param albumFailed: boolean[] = [];
  // 相册视频格子的播放位数据源：缩略图（albumFileIds/albumPaths）不足以起播，
  // 播放位选中的那一格要挂 VideoBubbleSurface，需要真正的视频文件信息。
  @Param albumVideoFileIds: number[] = [];
  @Param albumVideoFileSizes: number[] = [];
  @Param albumVideoDurations: number[] = [];
  @Param albumVideoMimeTypes: string[] = [];
  @Param albumCaption: string = '';
  @Param albumCaptionEntities: TdObject[] = [];
  // 内容列宽/键盘高/窗口高/手势方案/链接忙碌 url 等环境值全部走 this.env
  // （chatEnv 镜像，批 0/3a 建的通道），原 @StorageProp 声明随迁移删除。
  // Measured width of the bubble (it shrinks to fit content) — the inline
  // keyboard below matches it exactly instead of the theoretical max width.
  @Local bubbleW: number = 0;
  // 长按/点击的落点相对气泡中心的水平偏移，交给 bindContextMenu 的 offset。
  // 菜单默认贴着气泡排（ArkUI 按组件矩形算位置，与触点无关，实测同一条消息
  // 按左缘和按右缘弹出位置完全一样），这个值让它朝手指那一侧挪。
  @Local menuOffsetX: number = 0;
  // 时间层要跟随"气泡里最宽的那个兄弟"（转发标签 / 发送者名 / 评论行），
  // 它们都在时间 Stack **外面**，所以测它们不构成环。
  // 曾经是拿 bubbleW 回灌的，那是 minWidth ← bubbleW ← minWidth 的循环，
  // 只能涨不能落：任何一次量到偏大的宽度都被固化，气泡再也缩不回去，
  // BottomEnd 随即把正文推到右侧、时间戳压到文字底下——就是那个偶发的
  // "气泡横贯整屏、文字靠右、时间戳不见了"。
  // 这三个宽度的「换消息/复用时不清零」不变量（timeLayerWidth.ets 的说明；
  // 清零的话 onAreaChange 同宽不回调，宽度停在 0——时间停在正文末尾、引用块
  // 够不到气泡边缘）在 V2 下改为按标签文本的进程级记忆兜底：@Local 复用必
  // 重置，aboutToReuse 里按新行的标签文本播种（util/labelWidthMemory，批 2
  // senderLabelW 同款配方），比 V1 拿上一行随机标签的宽更准。
  @Local private forwardLabelW: number = 0;
  @Local private senderLabelW: number = 0;
  @Local private commentsRowW: number = 0;
  @Local revealedSpoilerKeys: string[] = [];
  @Local expandedQuoteKeys: string[] = [];
  // x/y are the tap's window coordinates (vp) — the fullscreen viewer uses them
  // as the anchor for its expand-from-tap / shrink-back-to-tap transition.
  @Param onMediaTap: (messageId: number, x: number, y: number) => void = (): void => {};
  @Param onLinkTap: (url: string) => void = (): void => {};
  @Param onCommentTap: (messageId: number) => void = (): void => {};
  @Param onBotCallback: (messageId: number, data: string) => void = (): void => {};
  @Param onAvatarTap: (userId: number) => void = (): void => {};
  // Long press on a group message avatar → mention that sender in the composer.
  @Param onAvatarLongPress: (userId: number, name: string) => void =
    (_userId: number, _name: string): void => {};
  // 第二个参数是"从哪条跳走的"。页面拿它当返回点——只用视口底部那条的话，
  // 引用块在屏幕靠上时返回位置会偏，跨屏的长消息尤其明显。
  @Param onReplyTap: (messageId: number, fromId: number) => void = (): void => {};
  @Param onFileTap: (messageId: number) => void = (): void => {};
  @Param onFileSave: (messageId: number) => void = (): void => {};
  @Param onFilePause: (messageId: number) => void = (): void => {};
  @Param onStickerRetry: (messageId: number) => void = (): void => {};
  @Param onLinkPreviewRetry: (messageId: number) => void = (): void => {};
  @Param onContactOpen: (userId: number, phone: string, vcard: string) => void =
    (_userId: number, _phone: string, _vcard: string): void => {};
  @Param onPhoneOpen: (phone: string) => void = (_phone: string): void => {};
  @Param onLocationOpen: (latitude: number, longitude: number, label: string, valid: boolean) => void =
    (_latitude: number, _longitude: number, _label: string, _valid: boolean): void => {};
  @Param onPollVote: (messageId: number, optionIds: number[]) => void =
    (_messageId: number, _optionIds: number[]): void => {};
  @Param onGameOpen: (messageId: number) => void = (_messageId: number): void => {};
  @Param onGamePhotoRetry: (messageId: number) => void = (_messageId: number): void => {};
  @Param paidMediaPending: boolean = false;
  @Param onPaidMediaUnlock: (messageId: number) => void = (_messageId: number): void => {};
  @Param onPaidMediaOpen: (messageId: number) => void = (_messageId: number): void => {};
  @Param onSpecialPhotoRetry: (messageId: number) => void = (_messageId: number): void => {};
  // 视频缩略图/文件下载失败后的重试；和图片重试分开，走的是 downloadFile 而非缩略图。
  @Param onVideoRetry: (messageId: number) => void = (_messageId: number): void => {};
  @Param onGiftCodeCopy: (code: string) => void = (_code: string): void => {};
  @Param onGiveawayOpen: (chatId: number, messageId: number) => void =
    (_chatId: number, _messageId: number): void => {};
  @Param onVoiceTap: (messageId: number) => void = (): void => {};
  @Param onVoicePlaybackStarted: (messageId: number) => void = (): void => {};
  @Param onAudioTap: (messageId: number) => void = (): void => {};
  @Param onAudioPrevious: (messageId: number) => void = (): void => {};
  @Param onAudioNext: (messageId: number) => void = (): void => {};
  @Param onAudioSeek: (messageId: number, fraction: number) => void =
    (_messageId: number, _fraction: number): void => {};
  @Param audioQueuePosition: number = 0;
  @Param audioQueueLength: number = 0;
  @Param audioHasPrevious: boolean = false;
  @Param audioHasNext: boolean = false;
  @Param onAutoplayVideoNeedDownload: (messageId: number) => void = (): void => {};
  // 播放位竞选上报：可见比例变化 / 组件消失。albumIndex 为 -1 表示非相册整条消息，
  // 相册格子用该格自己在 albumMemberIds 里的下标。回调由 ChatPage 接（见 playSlot.ets）。
  @Param onMediaRatio: (messageId: number, albumIndex: number, ratio: number, centerY: number) => void =
    (_messageId: number, _albumIndex: number, _ratio: number, _centerY: number): void => {};
  @Param onMediaGone: (messageId: number, albumIndex: number) => void =
    (_messageId: number, _albumIndex: number): void => {};
  // 当前播放位的 key（playSlot.slotKey 的输出），'' 表示没有播放位。
  @Param playSlotKey: string = '';
  // 自动播放静音开关（KEY_AUTOPLAY_MUTED，由 ChatPage 用 @StorageProp 下发）。
  @Param autoplayMuted: boolean = true;
  // 播放位视频的播放进度：每 350ms 一次的高频回调，故意不接到 @State——接上去
  // 会让 ChatPage 每 350ms 重建整个消息列表。ChatPage 用普通 Map 接住（按
  // messageId 记录），供全屏查看器交接时读取。
  @Param onPlaySlotPositionChanged: (messageId: number, albumIndex: number, positionMs: number) => void =
    (_messageId: number, _albumIndex: number, _positionMs: number): void => {};
  // 播放位视频播完或内嵌播放失败：这一条主动退位，让同屏其它候选重新竞选。
  // 不接的话播完的那条会永久霸占播放位，同屏另一条永远起不来。
  @Param onPlaySlotEnded: (messageId: number, albumIndex: number) => void =
    (_messageId: number, _albumIndex: number): void => {};
  // 播放位起播位置（毫秒）。由 ChatPage 在换届时从气泡进度表查出并随
  // playSlotKey 一起下发——全屏查看器交还的进度就是靠这条路接上的。
  @Param playSlotStartMs: number = 0;
  @Param onAnimationTap: (messageId: number, isPlaying: boolean) => void =
    (_messageId: number, _isPlaying: boolean): void => {};
  @Param onAnimationPlaybackFailed: (messageId: number) => void = (): void => {};
  @Param animationPaused: boolean = false;
  @Param animationForcePlay: boolean = false;
  @Param animationPlaybackFailed: boolean = false;
  // Long-press context menu actions.
  // emoji 参数其实是 reaction key：标准 emoji 原样，自定义 emoji 为 'ce:<id>'。
  @Param onSetReaction: (messageId: number, emoji: string, isChosen: boolean) => void = (): void => {};
  @Param onReplyTo: (messageId: number) => void = (): void => {};
  // Blocks swipe-to-reply while the composer is in edit mode (avoids the two
  // states fighting over the reply/edit strip). Long-press → 回复 is unaffected.
  @Param editingActive: boolean = false;
  @Param onEditMsg: (messageId: number) => void = (): void => {};
  @Param onShowReactors: (messageId: number, emoji: string) => void = (): void => {};
  @Param onTranslateMsg: (messageId: number) => void = (): void => {};
  @Param onPinMsg: (messageId: number, unpin: boolean) => void = (): void => {};
  @Param onStopPoll: (messageId: number) => void = (): void => {};
  @Param onReplaceMedia: (messageId: number) => void = (): void => {};
  @Param onPollVoters: (messageId: number) => void = (): void => {};
  @Param onSetDefaultReaction: (emoji: string) => void = (): void => {};
  @Param isPinnedMsg: boolean = false;
  @Param onCopyText: (messageId: number) => void = (): void => {};
  @Param onCopyCode: (text: string) => void = (): void => {};
  @Param onCopyLink: (messageId: number) => void = (): void => {};
  @Param onForwardMsg: (messageIds: number[]) => void = (): void => {};
  // 直接转发到收藏（和自己的会话），不弹选择面板。
  @Param onSaveToSaved: (messageIds: number[]) => void = (): void => {};
  // 转发回本会话——群里俗称"复读"。
  @Param onRepeatMsg: (messageIds: number[]) => void = (): void => {};
  // 在本会话里筛出这个发送者的全部消息。
  @Param onViewSenderHistory: (senderId: number) => void = (): void => {};
  @Param onReportMsg: (messageId: number) => void = (): void => {};
  @Param onSelectMsg: (messageIds: number[]) => void = (): void => {};
  @Param onDeleteMsg: (messageId: number) => void = (): void => {};
  // "转发自 X" tapped: (originChatId, originMsgId, originUserId) — chat ids for a
  // channel/chat origin, user id for a user origin.
  @Param onForwardTap: (chatId: number, messageId: number, userId: number) => void = (): void => {};
  @Param onOpenReactions: (messageId: number) => void = (): void => {};
  @Param onRecognizeSpeech: (messageId: number) => void = (): void => {};
  @Param onVideoNoteDownload: (messageId: number) => void = (): void => {};
  // 整聊天翻译：点「隐藏译文/显示译文」的单条折叠开关，状态存在条目上。
  @Param onToggleTranslation: (messageId: number, hidden: boolean) => void = (): void => {};
  @Param onRetryTranslation: (messageId: number) => void = (): void => {};
  @Local private translationStatus: TranslationStatus | null = null;
  private unsubTranslation: (() => void) | null = null;
  @Local private livePhotoProgress: number = 0;
  @Local private liveLinkPhotoProgress: number = 0;
  @Local private liveVideoProgress: number = 0;
  @Local private liveStickerProgress: number = 0;
  private unsubPhotoProgress: (() => void) | null = null;
  private unsubLinkPhotoProgress: (() => void) | null = null;
  private unsubVideoProgress: (() => void) | null = null;
  private unsubStickerProgress: (() => void) | null = null;
  // 圆形视频原地播放的开关，逐条独立。
  @Local private videoNotePlaying: boolean = false;
  // Chat's currently active video chat, if any (0 = none live) — lets a
  // "started" system pill know whether it's still tappable, and supplies the
  // id to hand off on tap. Sourced from ChatPage's existing updateChatVideoChat
  // subscription (see liveGroupCallId there) rather than re-subscribing here.
  @Param liveGroupCallId: number = 0;
  @Param onLiveStreamTap: (groupCallId: number) => void = (): void => {};
  // Live arrival: slide the bubble in from below (never set for history rows).
  @Param animateIn: boolean = false;
  // 字号/圆角/省电系等设置全部走 this.env（chatEnv 镜像）。V1 时代
  // reduceAnim/powerSaving/autoplayGif 上的 @Watch('onPlaybackPolicyChanged')
  // 改为 @Monitor 深层路径（@Trace 支持），见 onPlaybackPolicyChanged。
  @Param showAvatar: boolean = true;     // last row of a same-sender run
  @Param showSenderName: boolean = true; // first row of a same-sender run
  @Local mediaVisible: boolean = true;
  @Local stickerPlaybackFailed: boolean = false;
  @Local linkPreviewOpening: boolean = false;
  // Controlled context-menu presentation — mirrors ChatRow's bubble-lift preview
  // (see ChatRow.ets bindContextMenu) so long-pressing a message bubble gets the
  // same lift/scale animation as long-pressing a chat-list row.
  @Local private msgContextMenuShown: boolean = false;
  // Swipe-to-reply: live horizontal offset (vp, always <= 0 — the bubble only
  // drags leftward) applied as a translate on the bubble container while
  // dragging, then sprung back to 0 on release. onReplyTo fires once the drag
  // clears SWIPE_REPLY_TRIGGER; it never fires mid-drag.
  @Local private swipeReplyX: number = 0;
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
    return menuPreviewCompact(this.env.keyboardHeightVp, this.env.screenHeightVp);
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
  // P4 批 3c 之后这份清理只剩**无装饰器成员**（官方表格：复用不重置）。
  // 原 A 类 16 个 @State（剧透揭开态/引用展开态/玻璃尺寸/滑动位移等，审计
  // P0-3）已全部是 @Local，由框架在 aboutToReuse 之前统一重置（批 0.5 实测
  // 1370/1370）；C 类 6 个通道值同理，且 attachMessageChannels 会同步重播种。
  private clearTransientState(): void {
    this.gestureClaimed = false;
    this.mediaCenterY = 0;
    this.albumCellCenterY.clear();
    this.albumWasCompetingVideo.clear();
    // M-1：清成 false 是安全方向——它只用于「从参与竞选翻到不参与」的一次性
    // 补报，false 起步最多少报一次。aboutToReuse 里随即用新 msg 覆盖成真值。
    this.wasCompetingVideo = false;
  }

  aboutToAppear(): void {
    // 首建也播种三个标签宽度：同文本行在别的实例量过就直接有底。
    this.forwardLabelW = recallLabelWidth(`forward:${this.msg.forwardFrom}`);
    this.senderLabelW = recallLabelWidth(`sender:${this.msg.senderName}`);
    this.commentsRowW = recallLabelWidth(`comments:${this.msg.commentCount}`);
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

  aboutToRecycle(): void {
    this.detachMessageChannels();
    this.reportCompetingMediaGone();
    // 只剩无装饰器成员要手工清（@Local 由框架在下次复用前统一重置）。
    this.clearTransientState();
  }

  aboutToReuse(): void {
    // @Param 已是新值、@Local 已重置（批 0.5 判读，1370 样本）：全部同步做，
    // V1 时代的 reuseParam 读参、params 兜底分支、nextFrameQueue 延帧整套
    // 退役。三个测量宽度按标签文本播种（util/labelWidthMemory，声明处说明）。
    this.clearTransientState();
    this.forwardLabelW = recallLabelWidth(`forward:${this.msg.forwardFrom}`);
    this.senderLabelW = recallLabelWidth(`sender:${this.msg.senderName}`);
    this.commentsRowW = recallLabelWidth(`comments:${this.msg.commentCount}`);
    this.wasCompetingVideo = this.isCompetingVideo();
    this.attachMessageChannels(this.msg);
    for (let i = 0; i < this.albumIsVideo.length; i++) {
      this.albumWasCompetingVideo.set(i, this.albumIsVideo[i]);
    }
    this.requestAutoplayDownload();
  }

  // "替换媒体"（约 1511 行附近的菜单项）能在同一条消息 id 上把 contentType 从
  // video 改成 photo；组件按 messageId 复用、不会走 aboutToDisappear，所以那次
  // 上报的「静默停止」不够——候选表里旧的可见比例记录还在，播放位可能锁定一个
  // 已经不是视频的气泡。这里在 @Prop msg 每次被 ChatPage 换成新对象时（编辑、
  // 状态变化、替换媒体等，不是每帧）比较一次「参与竞选」状态，只在从 true 翻到
  // false 的那一次补发 onMediaGone，翻转之外什么也不做。
  @Monitor('msg')
  onMsgPropChanged(): void {
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
  @Monitor('albumIsVideo')
  onAlbumIsVideoChanged(): void {
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
    if ((this.env.autoplayGif && !this.env.powerSaving && !this.env.reduceAnim) || this.animationForcePlay) {
      this.onAutoplayVideoNeedDownload(this.msg.id);
    }
  }

  // V1 时代挂在 reduceAnim/powerSaving/autoplayGif 三个 @StorageProp 上的
  // @Watch；迁 env 后用 @Monitor 深层路径（@Trace 对象支持）。
  @Monitor('env.reduceAnim', 'env.powerSaving', 'env.autoplayGif')
  onPlaybackPolicyChanged(): void {
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
    return bubbleMaxWidth(this.env.chatContentWidth);
  }

  private inlineMaxW(): number {
    return this.bubbleMaxW() - 16;
  }

  private runCornerRadius(): number {
    return Math.min(this.env.bubbleRadius, 7);
  }

  private tailCornerRadius(): number {
    return Math.min(this.env.bubbleRadius, 2);
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
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }

  // 不吃滑动门控的时长。用于**参数在 build 之后才被消费**的动画：行内链接药丸
  // 按下态的 stateStyles 过渡、以及它 iterations:-1 的循环忙态。滑动中渲染的那
  // 一帧会把时长固定成 0，而这类动画在那之后才播——结果是滑动停下后按链接没有
  // 过渡、循环胶囊永久静止。滑动中本来也按不到，门控它们收益为零。
  // 气泡根节点已经不再使用它：那里现在完全不挂常驻动画（见 build 里的注释）。
  private persistentEffectDuration(duration: number): number {
    return persistentAnimationDurationFor(
      this.env.chatEffects, this.env.messageEffects, this.env.powerSaving, duration);
  }

  private reactionDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.reactionEffects &&
        this.env.animatedEmoji && this.env.emojiReactions && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }

  // Swipe-to-reply's snap-back/settle animation — degrades to an instant jump
  // under 省电模式/减少动效, matching the rest of the bubble's motion gating.
  private swipeReplyDuration(duration: number): number {
    return this.env.powerSaving || this.env.reduceAnim ? 0 : duration;
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
    logW(`[Menu114] longPress id=${this.msg.id} scheme=${this.env.gestureScheme}`
      + ` kbd=${Math.round(this.env.keyboardHeightVp)} winH=${Math.round(this.env.screenHeightVp)}`
      + ` compact=${this.compactMenuContext()} liveVideo=${this.hasLiveVideoSurface()}`
      + ` shown=${this.msgContextMenuShown}`);
    const fingers = event.fingerList;
    if (fingers.length > 0) {
      this.recordMenuOffset(fingers[0].localX);
    }
    this.gestureClaimed = true;
    const policy: MessageGesturePolicy = messageGesturePolicy(this.env.gestureScheme);
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
  // 成员 @Styles 已迁模块级（V2 不支持），见文件顶部。bubble 按压的抑制
  // 条件收敛成这一个判据，AttributeModifier 双例按它挑。
  private suppressBubblePressDim(): boolean {
    return this.hasInlineLink() || this.hasLinkPreview() || this.msg.contentType === 'voice' ||
      this.msg.contentType === 'audio' || this.msg.contentType === 'file';
  }

  // 链接底色。忙碌时换成 select_highlight——一层带透明度的主色调，浅色深色
  // 两套资源都已经定好，也不会被自定义强调色带跑。代码体的链接本来就有底色，
  // 忙碌时同样切到高亮色，才看得出变化。
  private linkRunBackground(run: RichRun): ResourceColor {
    if (this.env.linkNavBusy === run.url) {
      return $r('app.color.select_highlight');
    }
    return run.code ? $r('app.color.surface_alt') : Color.Transparent;
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
      !this.mediaVisible || !this.env.appIsForeground || this.animationPlaybackFailed) {
      return false;
    }
    if (this.animationPaused) {
      return false;
    }
    return this.animationForcePlay || (!this.env.powerSaving && !this.env.reduceAnim && this.env.autoplayGif);
  }

  private autoplayCategory(): string {
    return this.msg.isAnimation ? 'gif' : 'video';
  }

  private animationDownloadExpected(): boolean {
    return this.msg.isAnimation && this.msg.videoFileId !== 0 &&
      this.msg.videoPath === '' && !this.msg.videoFailed &&
      (this.animationForcePlay || (!this.env.powerSaving && !this.env.reduceAnim && this.env.autoplayGif));
  }

  // The link preview card adds its own 8+8 horizontal padding on top of the
  // bubble's, so content inside it needs a narrower cap than inlineMaxW().
  private cardMaxW(): number {
    return this.inlineMaxW() - 16;
  }

  private mediaThumbW(): number {
    return mediaThumbWidth(this.env.chatContentWidth);
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
    return mediaBoxFor(this.env.chatContentWidth, this.msg.photoWidth, this.msg.photoHeight,
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
          : (this.liveSendState === 'read' ? this.accent() : COLOR_ICON_SECONDARY)])
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
    return Math.max(12, this.env.msgTextSize - 2);
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
        .width(this.env.msgTextSize + 3)
        .height(this.env.msgTextSize + 3)
        .verticalAlign(ImageSpanAlignment.CENTER)
        .objectFit(ImageFit.Contain);
    } else if (run.url !== '') {
      // 这一段被点中、正在向服务器问"这个链接该开哪一页"的时候，文字自己
      // 呼吸起来。链接是 Span，挂不了子组件也没有 opacity，能动的只有它自己
      // 的颜色和底色，所以加载态就画成一颗一明一暗的药丸。
      //
      // this.env.linkNavBusy 只在这条分支里读：不含链接的气泡从头到尾不碰
      // 这个变量，也就不会因为别人点了链接而重建。
      Span(run.text)
        .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
        .fontFamily(run.code ? 'monospace' : '')
        .fontColor(this.accent())
        .decoration({ type: this.richRunDecoration(run), color: this.accent() })
        .textBackgroundStyle({
          color: this.linkRunBackground(run),
          radius: run.code || this.env.linkNavBusy === run.url ? 3 : 0
        })
        // iterations: -1 + Alternate —— 一次状态变化就能永远来回，不需要
        // 定时器逐帧改状态（那会把整个气泡按帧重建）。省电模式下
        // effectDuration 归零，退化成一个静止的暗色药丸，仍然看得出在忙。
        .animation({
          duration: this.persistentEffectDuration(620),
          curve: Curve.EaseInOut,
          iterations: this.env.linkNavBusy === run.url ? -1 : 1,
          playMode: PlayMode.Alternate
        })
        .stateStyles({ normal: msgLinkRunNormalStyle, pressed: msgLinkRunPressedStyle })
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
  richRuns(params: RichRunsBuilderParams) {
    Text() {
      ForEach(params.runs, (r: RichRun) => {
        this.richInlineRun(r);
      }, (r: RichRun, i: number) => `run_${i}_${r.offset}_${r.text}`);
      if (this.timeReserveInText() && params.isLastSegment) {
        // fontSize 14 (not 11): when this reserve wraps onto its own line, the
        // taller line leaves a visible gap between the text and the timestamp.
        Span(this.timeReserve()).fontSize(14).fontColor(Color.Transparent);
      }
    }
    .fontSize(this.env.msgTextSize)
    .lineHeight(this.env.msgTextSize * 1.34)
    .wordBreak(WordBreak.BREAK_WORD)
    .constraintSize({ maxWidth: params.maxWidth });
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

  // Render TDLib formatted text: inline bold/link runs, pre/code blocks and
  // blockquotes as gray boxes. maxWidth is the caller's available content
  // width (narrower inside nested cards like the link preview).
  //
  // 时间戳的尾部占位**不作为参数传进来**，而是在这里读 this.timeReserveInText()。
  //
  // @Builder 的参数整体打成一个对象字面量：官方《自定义构建函数》明确只有
  // 「单参数 + 对象字面量」的按引用传递支持内部 UI 刷新。原来的 text / entities /
  // maxWidth 三参数写法在气泡复用时会把旧正文关在构建函数里，外面的媒体已经切到
  // 新消息、里面的文字却仍是上一条——只修 ForEach 的 key 也跨不过这一层。
  //
  // 时间戳占位仍从 this 读：翻译开始时它移到状态行、翻译撤销时又回到正文，
  // 避免把这个高频翻转再复制进分段数据。
  @Builder
  richContent(params: RichContentBuilderParams) {
    Column() {
      ForEach(parseFormattedText(params.text, params.entities), (seg: RichSegment, segIdx: number) => {
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
                .stateStyles({ normal: msgLinkRunNormalStyle, pressed: msgLinkRunPressedStyle })
                .animation({ duration: this.effectDuration(90), curve: Curve.EaseOut })
                .onClick((): void => {
                  if (this.gestureClaimed) { return; }
                  this.onCopyCode(seg.text); });
            }
            .width(params.maxWidth - 18)
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
            .constraintSize({ maxWidth: params.maxWidth - 20 })
            .wordBreak(WordBreak.BREAK_ALL);
          }
          .width(params.maxWidth)
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
            .fontSize(this.env.msgTextSize)
            .lineHeight(this.env.msgTextSize * 1.34)
            .maxLines(seg.expandable && !this.quoteExpanded(seg) ? 4 : 10000)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: params.maxWidth - 20 }).wordBreak(WordBreak.BREAK_WORD);
            if (seg.expandable) {
              Text(this.quoteExpanded(seg) ? $r('app.string.mb_collapse_quote') : $r('app.string.mb_expand_quote'))
                .fontSize(11).fontColor(this.accent()).fontWeight(FontWeight.Medium)
                .margin({ top: 4 })
                .stateStyles({ normal: msgLinkRunNormalStyle, pressed: msgLinkRunPressedStyle })
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
          this.richRuns({
            runs: seg.runs,
            maxWidth: params.maxWidth,
            isLastSegment: seg.isLast
          });
        }
      // 键必须带内容，取值与完整推导见 util/richText.richSegmentKey——只有序号和
      // kind 的话，「格式一致的频道」里每条消息都算出同一串键，正文会停在上一条上。
      }, (seg: RichSegment, i: number) => richSegmentKey(i, seg));
    }
    // minWidth 挂在这里（正文，content() 里最宽的孩子）而不是只挂外层 Column：
    // Column 给子节点做 Stretch 是按最宽的孩子量的，自己的 minWidth 钳位在那之后。
    // 只挂外层时引用块的 alignSelf(Stretch) 拉不到气泡边缘（真机确认）。
    .constraintSize({ minWidth: this.measuredTimeLayerWidth(), maxWidth: params.maxWidth })
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
          LoadingProgress().width(12).height(12).color(COLOR_ICON_SECONDARY);
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
          .fontSize(this.env.msgTextSize)
          .lineHeight(this.env.msgTextSize * 1.34)
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
    .onAreaChange((_old: Area, area: Area): void => {
      this.commentsRowW = area.width as number;
      rememberLabelWidth(`comments:${this.msg.commentCount}`, this.commentsRowW);
    })
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
                .stateStyles({ normal: msgBotButtonNormalStyle, pressed: msgBotButtonPressedStyle })
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
            // 点击目标、游戏分支和样式都属于组件身份，不能只看显示文字。
            }, (btn: InlineBtn, btnIdx: number) => inlineButtonKey(rowIdx, btnIdx, btn));
          }.width('100%');
        // 行键也得带内容。**只修内层的按钮键是修不动的**：外层键不变时 ForEach
      // 连行的构建函数都不会重跑，内层那个 ForEach 拿的还是上一条消息的
      // `row`，按钮文字于是停在上一条上——与相册格子同一个机理，
      // 见 util/albumCellKey。
      }, (row: InlineBtn[], rowIdx: number) => inlineButtonRowKey(rowIdx, row));
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
        .fontSize(24).fontColor([COLOR_ICON_SECONDARY]);
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
        SymbolGlyph($r('sys.symbol.pause')).fontSize(21).fontColor([COLOR_ICON_SECONDARY]);
        Text($r('app.string.mb_animation_paused')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
      }
      .width(this.stickerW()).height(this.stickerH())
      .justifyContent(FlexAlign.Center);
    }
  }

  // 实况角标。缩略图上（单图与相册格子都用它）标出「这条是实况」——和查看器
  // 左下角那枚胶囊同一套元素：同心圆的 sys.symbol.livephoto + LIVE 文案。
  //
  // 位置固定在左上角：左下角被时长/大小那条 meta 占着（单图），中心是播放钮，
  // 只有左上角是空的，相册格子同理。
  @Builder
  liveChip() {
    Row({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.livephoto')).fontSize(12).fontColor([Color.White]);
      Text($r('app.string.cp_live_photo'))
        .fontSize(10).fontColor(Color.White).fontWeight(FontWeight.Medium);
    }
    .height(18)
    .padding({ left: 5, right: 6 })
    .backgroundColor('#66000000')
    .borderRadius(9)
    .position({ x: 6, y: 6 });
  }

  private msgIsLivePhoto(): boolean {
    return this.msg.contentType === 'video' &&
      isLivePhotoVideo(this.msg.videoFileName, this.msg.videoDuration);
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

  private albumIsLiveAt(index: number): boolean {
    return this.albumIsLive[index] ?? false;
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

  private albumVideoDurationAt(index: number): number {
    return this.albumVideoDurations[index] ?? 0;
  }

  private albumVideoMimeTypeAt(index: number): string {
    return this.albumVideoMimeTypes[index] ?? '';
  }

  private albumVideoMetaText(index: number, cellWidth: number): string {
    const size: string = this.albumVideoFileSizeAt(index) > 0
      ? formatFileSize(this.albumVideoFileSizeAt(index)) : '';
    const durationSec: number = this.albumVideoDurationAt(index);
    if (durationSec <= 0) {
      return size;
    }
    const duration: string = this.formatDuration(durationSec);
    // 三列等窄格优先保证 issue #93 要求的文件大小可见；宽格与单视频一致。
    return size !== '' && cellWidth >= 112 ? `${duration} · ${size}` : (size !== '' ? size : duration);
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
      topLeft: this.msg.isOutgoing ? this.env.bubbleRadius :
        (this.showSenderName ? this.env.bubbleRadius : this.runCornerRadius()),
      topRight: this.msg.isOutgoing ?
        (this.showSenderName ? this.env.bubbleRadius : this.runCornerRadius()) : this.env.bubbleRadius,
      bottomLeft: this.msg.isOutgoing ? this.env.bubbleRadius :
        (this.showAvatar ? this.tailCornerRadius() : this.runCornerRadius()),
      bottomRight: this.msg.isOutgoing ?
        (this.showAvatar ? this.tailCornerRadius() : this.runCornerRadius()) : this.env.bubbleRadius
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
    if (this.albumIsLiveAt(cell.idx)) {
      this.liveChip();
    }
    if (this.albumIsVideoAt(cell.idx) && this.albumVideoMetaText(cell.idx, cell.width) !== '') {
      Text(this.albumVideoMetaText(cell.idx, cell.width))
        .fontSize(10.5)
        .fontColor(Color.White)
        .backgroundColor('#00000066')
        .borderRadius(4)
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: Math.max(24, cell.width - 12) })
        .position({ x: 6, y: Math.max(6, cell.height - 23) });
    }
  }

  // 这一格的 ForEach 键。**纯位置的键会让配图配错文**，完整推导见
  // util/albumCellKey。
  private cellKeyAt(index: number): string {
    return albumCellKey(index, this.albumMemberIdAt(index),
      this.albumFileIds[index] ?? 0, this.albumIsVideoAt(index));
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
              // 图片格不挂可见性监听：相册竞选只看视频格（那侧才注册），这里
              // 原来挂着一个回调体为空的 onVisibleAreaApproximateChange——每个
              // 图片格一份注册与逐帧近似计算，纯浪费（节点普查 09-02 目标 #1）。
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
          }, (cell: AlbumCell) => this.cellKeyAt(cell.idx));
        }
      }, (row: AlbumCell[], rowIdx: number) => albumRowKey(rowIdx,
        row.map((c: AlbumCell): string => this.cellKeyAt(c.idx))));
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
    .stateStyles({ normal: msgLinkCardNormalStyle, pressed: msgLinkCardPressedStyle })
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
        .stateStyles({ normal: msgMenuActionNormalStyle, pressed: msgMenuActionPressedStyle })
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
      // count 与 isChosen 必须进键：它们是这枚 chip 上**唯一会变的两样**，而键不变
      // 时 ForEach 不重跑子构建函数（同 util/albumCellKey 那段推导）——点赞数会停在
      // 上一条消息、或者停在自己点之前的那个数上。
      }, (r: ReactionInfo) => `rx_${reactionKeyFrom(r.emoji, r.customEmojiId)}` +
        `_${r.customEmojiPath}_${r.count}_${r.isChosen ? 'y' : 'n'}`);
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
        .onClick((): void => { this.onSetReaction(this.msg.id, e, this.reactionChosen(e)); })
        .gesture(LongPressGesture().onAction((): void => { this.onSetDefaultReaction(e); }));
      }, (e: string): string => e);
      Blank();
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(15).fontColor([COLOR_ICON_SECONDARY]);
      }
      .width(30).height(30).borderRadius(15).backgroundColor('#0000000F')
      .justifyContent(FlexAlign.Center)
      .stateStyles({ normal: msgMenuActionNormalStyle, pressed: msgMenuActionPressedStyle })
      .animation({ duration: this.reactionDuration(110), curve: Curve.EaseOut })
      .onClick((): void => { this.onOpenReactions(this.msg.id); });
    }
    .width('100%')
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  msgContextMenu() {
    Menu() {
      MenuItem(this.messageReactionMenuItem);
      if (this.msg.isOutgoing && this.nowSec - this.msg.date < 172800 &&
        (this.msg.contentType === 'text' || EDITABLE_CAPTION_TYPES.indexOf(this.msg.contentType) >= 0)) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
          content: this.msg.contentType === 'text' ? $r('app.string.edit') : $r('app.string.mb_edit_caption')
        }).onClick((): void => { this.onEditMsg(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.plus_square_on_square')),
        content: $r('app.string.mb_copy_text')
      }).onClick((): void => { this.onCopyText(this.msg.id); });
      if (this.msg.text !== '') {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.translate')),
          content: $r('app.string.mb_translate')
        }).onClick((): void => { this.onTranslateMsg(this.msg.id); });
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
      }).onClick((): void => { this.onForwardMsg(this.albumMemberIds); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.bookmark')),
        content: $r('app.string.mb_save_to_saved')
      }).onClick((): void => { this.onSaveToSaved(this.albumMemberIds); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.repeat')),
        content: $r('app.string.mb_repeat')
      }).onClick((): void => { this.onRepeatMsg(this.albumMemberIds); });
      if (this.isGroup && this.msg.senderIsUser && this.msg.senderId > 0) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person')),
          content: $r('app.string.mb_view_history')
        }).onClick((): void => { this.onViewSenderHistory(this.msg.senderId); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.pin')),
        content: this.isPinnedMsg ? $r('app.string.ft_unpin') : $r('app.string.ft_pin')
      }).onClick((): void => { this.onPinMsg(this.msg.id, this.isPinnedMsg); });
      if (this.msg.isOutgoing && this.nowSec - this.msg.date < 172800 &&
        (this.msg.contentType === 'photo' || this.msg.contentType === 'video')) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.picture')),
          content: $r('app.string.mb_replace_media')
        }).onClick((): void => { this.onReplaceMedia(this.msg.id); });
      }
      if (this.msg.contentType === 'poll' && this.msg.isOutgoing && !this.msg.pollIsClosed) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
          content: $r('app.string.mb_stop_poll')
        }).onClick((): void => { this.onStopPoll(this.msg.id); });
      }
      if (this.msg.contentType === 'poll' && !this.msg.pollIsAnonymous) {
        MenuItem({
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.person_2')),
          content: $r('app.string.mb_view_voters')
        }).onClick((): void => { this.onPollVoters(this.msg.id); });
      }
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.exclamationmark_circle')).fontColor([Color.Red]),
        content: $r('app.string.mb_report')
      }).onClick((): void => { this.onReportMsg(this.msg.id); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')),
        content: $r('app.string.mb_select')
      }).onClick((): void => { this.onSelectMsg(this.albumMemberIds); });
      MenuItem({
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash')).fontColor([Color.Red]),
        content: $r('app.string.delete')
      }).onClick((): void => { this.onDeleteMsg(this.msg.id); });
    }
    // 百分比宽度的表情行会让未定宽的 Menu 采用整屏约束，随后屏幕边界夹取会
    // 吞掉手指落点带来的横向偏移。固定回原菜单宽度，菜单才能继续贴近落点。
    .width(262)
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
          this.richContent({
            text: this.albumCaption,
            entities: this.albumCaptionEntities,
            maxWidth: this.inlineMaxW()
          });
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
        .fontSize(this.env.msgTextSize)
        .lineHeight(this.env.msgTextSize * 1.34);
      } else {
        this.richContent({
          text: this.msg.text,
          entities: this.msg.textEntities,
          maxWidth: this.inlineMaxW()
        });
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
        if (this.msgIsLivePhoto()) {
          this.liveChip();
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
        // A failed cover remains a thumbnail-only retry. A failed video does
        // not intercept the whole media surface: ChatPage.openViewer can open
        // the streaming viewer and independently restart the file download.
        if (this.thumbnailRetryable()) {
          this.onSpecialPhotoRetry(this.msg.id);
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
          this.richContent({
            text: this.msg.text,
            entities: this.msg.textEntities,
            maxWidth: this.inlineMaxW()
          });
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
          this.richContent({
            text: this.msg.text,
            entities: this.msg.textEntities,
            maxWidth: this.inlineMaxW()
          });
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
          this.richContent({
            text: this.msg.text,
            entities: this.msg.textEntities,
            maxWidth: this.inlineMaxW()
          });
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
      }.fontSize(this.env.msgTextSize);
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
    if (this.env.powerSaving || this.env.reduceAnim) {
      return true;
    }
    if (this.msg.isEmojiSticker) {
      return !this.env.animatedEmoji || !this.env.emojiChat;
    }
    return !this.env.stickers || !this.env.stickerAutoplay;
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
    if (this.env.appearanceEpoch < 0) {
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

  // 未量到外层尺寸时由本体临时画玻璃；完整轮廓就绪后本体透明，只留外层一份。
  private bubbleBg(): ResourceColor {
    if (!this.glassLive()) {
      return this.bubbleFillColor();
    }
    return this.glassBodyFallbackOn() ? this.glassBg() : Color.Transparent;
  }

  private glassLive(): boolean {
    return this.bubbleMaterialLive() && !this.isBareEmoji();
  }

  // **容器**这一层的点亮条件：想要玻璃（glassLive）之外还要**已经量到尺寸**。
  //
  // 容器跨着 [尾巴/留白 | 气泡] 整块，它的形状**只**由 clipShape 给，而
  // clipShape 要等 onAreaChange 填上 glassW/glassH 才挂得上。没量到就上色，
  // 画出来的是没裁剪的矩形：留白被一起涂满、没有尾巴、没有描边，左边缘外扩
  // 一个 bubbleTailGutter（7vp）——真机上那个横跳。
  //
  // 气泡**本体**不受这条约束，见 glassBodyOn()。三段式判据的完整说明和
  // 「为什么不能退回实心档」在 bubbleGlassPath.glassStage 的注释里，
  // 判据本体是纯函数，单测在 BubbleGlassPath.test.ets。
  private glassReady(): boolean {
    return glassPaintReady(this.glassLive(), this.glassW, this.glassH);
  }

  // 玻璃结构是否开启。它不等测量，用于尾巴占位等结构判定；本体是否临时绘制
  // 玻璃由 glassBodyFallbackOn 单独决定。
  private glassBodyOn(): boolean {
    return glassBodyPainted(this.glassLive(), this.glassW, this.glassH);
  }

  private glassBodyFallbackOn(): boolean {
    return glassBodyFallbackPainted(this.glassLive(), this.glassW, this.glassH);
  }

  // 首帧外层轮廓尚未就绪时，本体临时使用同档玻璃色与背景模糊，避免退回实心
  // 白底。完整态由外层统一接管，本体的这两项归零。
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
    // 三个显示判据和 build 里的 if 是同一份（下面三个方法），量到的宽度只在
    // 标签真的显示时才算数。
    return timeLayerMinWidth(this.inlineMaxW(), {
      forwardShown: this.forwardLabelShown(), forwardW: this.forwardLabelW,
      senderShown: this.senderLabelShown(), senderW: this.senderLabelW,
      commentsShown: this.commentsRowShown(), commentsW: this.commentsRowW
    });
  }

  private forwardLabelShown(): boolean {
    return this.msg.forwardFrom !== '';
  }

  private senderLabelShown(): boolean {
    return this.isGroup && !this.msg.isOutgoing && this.msg.senderName !== '' && this.showSenderName;
  }

  private commentsRowShown(): boolean {
    return this.isChannel && this.msg.commentCount > 0;
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
        .fontColor([this.liveVideoChatTappable() ? this.accent() : COLOR_ICON_SECONDARY])
        .width(14);
      Text(this.fallbackLabel())
        .fontSize(12)
        .fontColor(this.liveVideoChatTappable() ? this.accent() : COLOR_TEXT_SECONDARY)
        .fontWeight(this.liveVideoChatTappable() ? FontWeight.Medium : FontWeight.Regular)
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: this.env.chatContentWidth * 0.68 });
      if (this.liveVideoChatTappable()) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(10).fontColor([this.accent()]).width(10);
      }
    }
    .constraintSize({ maxWidth: this.env.chatContentWidth * 0.82 })
    .backgroundColor(this.liveVideoChatTappable() ? '#183478F6' : $r('app.color.system_pill'))
    .border({
      width: 0.5,
      color: this.liveVideoChatTappable() ? '#303478F6' : '#16FFFFFF'
    })
    .borderRadius(12)
    .padding({ left: 9, right: 9, top: 4, bottom: 4 })
    .attributeModifier(this.liveVideoChatTappable() ? SYSTEM_PILL_PRESS_DIM : SYSTEM_PILL_PRESS_NONE)
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
        if (this.showUnreadDivider) {
          this.unreadDivider();
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
        this.unreadDivider();
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
        if (this.forwardLabelShown()) {
          // Tappable when the origin is known — opens the original post, or the
          // author's chat. A hidden-origin forward carries no ids and stays inert.
          Text(str('mb_forwarded_from', this.msg.forwardFrom)).fontSize(13).fontColor(this.accent())
            .fontWeight(FontWeight.Medium).margin({ bottom: 2 })
            .constraintSize({ maxWidth: this.inlineMaxW() })
            .onAreaChange((_old: Area, area: Area): void => {
              this.forwardLabelW = area.width as number;
              rememberLabelWidth(`forward:${this.msg.forwardFrom}`, this.forwardLabelW);
            })
            .onClick(() => {
              if (this.gestureClaimed) { return; }
              if (this.msg.forwardOriginChatId !== 0 || this.msg.forwardOriginUserId !== 0) {
                this.onForwardTap(this.msg.forwardOriginChatId, this.msg.forwardOriginMsgId,
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
            SenderRoleTag({ chatId: this.chatId, senderId: this.msg.senderId,
              presetTag: this.msg.senderTag });
          }
          .margin({ bottom: 2 })
          .alignItems(VerticalAlign.Center)
          .onAreaChange((_old: Area, area: Area): void => {
            this.senderLabelW = area.width as number;
            rememberLabelWidth(`sender:${this.msg.senderName}`, this.senderLabelW);
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
          minWidth: Math.min(this.inlineMaxW(), this.senderLabelShown() ? this.senderLabelW : 0)
        })
        if (this.commentsRowShown()) {
          // 量宽回调直接挂在 commentsRow 自己的根 Row 上（builder 内），原来
          // 只为挂 onAreaChange 包了一层 Column——频道每行省一个容器节点
          // （节点普查 09-02 目标 #11）。
          this.commentsRow();
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
      .attributeModifier(this.suppressBubblePressDim() ? BUBBLE_PRESS_NONE : BUBBLE_PRESS_DIM)
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
        if (messageGesturePolicy(this.env.gestureScheme).tapOpensMenu) {
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
      // 容器跨着那 7vp 尾巴留白，形状**只**由 clipShape 给。所以它必须等量到
      // 尺寸才上色，否则没裁剪的一帧会把留白一起涂满、左边缘外扩 7vp。
      // 没量到时它全透明，这一帧的玻璃由气泡本体自己扛；量到后本体同步退为
      // 透明，完整态始终只有外层这一份背景与模糊。
      .backgroundColor(this.containerGlassBg())
      .backdropBlur(this.containerGlassBlur())
      // 材质自带的边框沿**本节点的 border-box** 画，而且吃 borderRadius。不设圆角
      // 它就画一个直角矩形框，被轮廓裁掉左边/底边后只剩顶边一条直线拐到右边——
      // 真机上就是用户报的「气泡描边不对」。设成气泡自己的圆角，这条边框就和轮廓
      // 重合（尾巴那侧仍由裁剪负责）。
      .borderRadius(this.glassRadius())
      .background(this.glassOutline(), { align: Alignment.TopStart })
      .attributeModifier(bubbleGlassModifier(this.glassReady(), this.glassW, this.glassH,
        this.msg.isOutgoing, this.hasBubbleTail(), this.bubbleCornerRadius(),
        this.env.bubbleMaterialOn ? (w: number, h: number): void => {
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
