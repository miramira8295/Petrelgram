import { ReactionTransitions } from '../../util/reactionTransitions';
import { TextMeasureCache, textMeasureEnvironment, sharedTextMeasurements } from '../../util/textMeasureCache';
import { deviceInfo } from '@kit.BasicServicesKit';
import { MessageEntry, ReactionInfo } from '../../store/MessageEntry';
import { getAccentColorStore, getUserStore } from '../../tdkit/Globals';
import { BubbleCornerCache, SenderAvatarSpec, SenderAvatarSpecCache } from '../../util/messageBubblePresentation';
import { cornerPx, senderLeadInset } from '../../util/bubbleCornerInset';
import { chatEnv } from '../../util/chatEnvMirror';
import { rememberLabelWidth, recallLabelWidth } from '../../util/labelWidthMemory';
import { SenderRoleTag } from './SenderRoleTag';
import { BUBBLE_AVATAR_GUTTER_VP, bubbleMaxWidth } from '../../util/mediaBox';
import { formatClockTime } from '../../util/formatTime';
import { reactionKeyFrom } from '../../util/reactions';
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, COLOR_BUBBLE_OUT, COLOR_BUBBLE_IN, AVATAR_PALETTE, accentSoft } from '../../util/theme';
import { plural, str } from '../../util/strings';
import { timeLayerMinWidth } from '../../util/timeLayerWidth';
import { CHIP_ICON_VP, reactionChipWidth, reactionsRowMaxWidth, reactionsRowWidth, timeOverlayWidth } from '../../util/reactionsWidth';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { replyThumbSrc } from '../../util/replyThumb';
import { DiceEndFrame } from './DiceEndFrame';

import { MessageBubbleContext } from './MessageBubbleShell';
import { MessageSenderAvatar } from './MessageSenderAvatar';

let contentSharedMeasureSupported: boolean | undefined = undefined;
const REACTORS_ARROW_PAD_H: number = 7;
const REACTORS_ARROW_ICON_VP: number = 16;
const REACTORS_ARROW_MARGIN_R: number = 4;
const REPLY_QUOTE_WIDTH_RATIO: number = .76;
const REPLY_QUOTE_LINE_H: number = 16;
const REPLY_THUMB_SIZE: number = 32;
const REPLY_THUMB_GAP: number = 6;
const PURE_MEDIA_CORNER_RADIUS: BorderRadiuses = { topLeft: 15, topRight: 15, bottomLeft: 15, bottomRight: 15 };
const MEDIA_TIME_PADDING: Padding = { left: 6, right: 6, top: 2, bottom: 2 };
const PLAIN_TIME_PADDING: Padding = { left: 0 };
@Styles
function contentReactionNormal() { .opacity(1).scale({ x: 1, y: 1 }) }
@Styles
function contentReactionPressed() { .opacity(.72).scale({ x: .97, y: .94 }) }

// Native islands keep their original sizing/accessibility. The surrounding
// row owns channels, menu and the single drawn outline; this owns content only.
@ComponentV2
export struct BubbleContentLayout {
  @Require @Param context: MessageBubbleContext;
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @BuilderParam body: () => void;
  private env = chatEnv;
  private measuredBubbleW: number = 0;
  private reactionTransitions: ReactionTransitions = new ReactionTransitions();
  private textMeasureCache: TextMeasureCache = new TextMeasureCache();
  private textMeasureFailed: boolean = false;
  private rxWidthSig: string = '';
  private rxSource: ReactionInfo[] | null = null;
  private rxWidthCache: number = 0;
  private cornerCache: BubbleCornerCache = new BubbleCornerCache();
  private commentAvatarSpecCaches: SenderAvatarSpecCache[] = [];

  aboutToAppear(): void { this.seedLabelWidths(); }
  aboutToReuse(): void { this.seedLabelWidths(); this.context.bubbleW = this.measuredBubbleW; }
  @Monitor('msg')
  private inputChanged(): void { this.seedLabelWidths(); }

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


  private bubbleMaxW(): number {
    // 只有群聊来信才有头像位；发出的消息和私聊来信按 0 算，能宽出 44vp。
    return bubbleMaxWidth(this.data.contentWidth, this.avatarReserve());
  }


  private inlineMaxW(): number {
    return this.bubbleMaxW() - 16;
  }


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


  private avatarReserve(): number {
    return this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
  }


  private reactionDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.reactionEffects &&
        this.env.animatedEmoji && this.env.emojiReactions && !this.env.powerSaving,
      scrollActiveNow(), duration);
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


  @Builder
  commentsRow() {
    Row({ space: 6 }) {
      if (this.msg.commentReplierIds.length > 0) {
        Row() {
          ForEach(this.msg.commentReplierIds, (uid: number, idx: number) => {
            MessageSenderAvatar({ spec: this.commentAvatarSpec(uid, idx) })
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
        .stateStyles({ normal: contentReactionNormal, pressed: contentReactionPressed })
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
        .stateStyles({ normal: contentReactionNormal, pressed: contentReactionPressed })
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
    const sig = `${arrowShown}:${timeText}:${edited}:${outgoing}:${views}:${environment}:${availableWidth}`;
    if (reactions === this.rxSource && sig === this.rxWidthSig && this.rxWidthCache > 0) {
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
    this.rxSource = this.textMeasureFailed ? null : reactions;
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
        if (contentSharedMeasureSupported === undefined) {
          contentSharedMeasureSupported = deviceInfo.sdkApiVersion >= 22;
        }
        if (contentSharedMeasureSupported) {
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
        return this.getUIContext().px2vp(sharedTextMeasurements.width(scope, environment, content, size, measure));
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


  private replyQuoteMaxW(): number {
    return Math.round(this.inlineMaxW() * REPLY_QUOTE_WIDTH_RATIO);
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
        Text(this.msg.replyText).fontSize(12).fontColor($r('app.color.quote_text')).maxLines(1)
          .lineHeight(REPLY_QUOTE_LINE_H).height(REPLY_QUOTE_LINE_H)
          .constraintSize({ maxWidth: this.replyQuoteMaxW() }).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .alignItems(HorizontalAlign.Start)
      .flexShrink(1);
    }
    .alignItems(VerticalAlign.Center)
    .alignSelf(ItemAlign.Stretch)
    // Stretch 需要 Flex 父容器；Column 的交叉轴对齐不支持拉伸。
    // 父 Flex 按内容收缩，引用行再拉伸到其中最宽的正文/引用宽度。
    .constraintSize({ maxWidth: this.inlineMaxW() })
    // background(builder) 的脱树装饰可能保留复用前的尺寸；原生背景/边框直接
    // 跟随当前行，不量尺寸、不回写可观测状态，也不增加滚动期间的重绘回调。
    .backgroundColor(accentSoft())
    .border({ width: { left: 4 }, color: this.accent() })
    .borderRadius(4)
    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
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


  @Builder
  contentWithReactions() {
    this.content();
    if (this.msg.reactions.length > 0) {
      Row({ space: 6 }) {
        this.reactionsRow();
        this.timeOverlay();
      }
      .alignItems(VerticalAlign.Bottom)
      .constraintSize({ maxWidth: this.inlineMaxW() });
    }
  }


  private isBareEmoji(): boolean {
    const type: string = this.msg.contentType;
    return type === 'emoji' || type === 'sticker' || type === 'customEmoji'
      || type === 'videoNote' || type === 'dice';
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


  private labelSidePadding(): number {
    return this.isMediaBubble() ? 8 : 0;
  }


  private captionInset(): number {
    return this.isMediaBubble() && this.msg.text !== '' ? 8 : 0;
  }


  private contentBasePadding(): number {
    return this.isMediaBubble() ? 2 : 8;
  }


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


  private seedLabelWidths(): void {
    this.context.forwardLabelW = recallLabelWidth(`forward:${this.msg.forwardFrom}`);
    this.context.senderLabelW = recallLabelWidth(`sender:${this.msg.senderName}`);
    this.context.commentsRowW = recallLabelWidth(`comments:${this.msg.commentCount}`);
  }


  build() {
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
        if (this.msg.replyToMessageId !== 0) {
          Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Start }) {
            this.contentWithReactions();
          }
          .width(LayoutPolicy.wrapContent)
          .height(LayoutPolicy.wrapContent)
          .constraintSize({ minWidth: this.measuredTimeLayerWidth() });
        } else {
          Column() {
            this.contentWithReactions();
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
    .constraintSize({ maxWidth: this.bubbleMaxW() })
    .padding({ left: this.contentBasePadding(), right: this.contentBasePadding(),
      top: this.contentBasePadding() + this.senderLeadPadding(),
      bottom: this.contentBasePadding() + (this.captionInset() > 0 ? 6 : 0) })
    .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
      if (typeof size.width === 'number' && size.width > 0) {
        this.measuredBubbleW = size.width;
        if (this.context.bubbleW !== size.width) { this.context.bubbleW = size.width; }
      }
    });
  }
}
