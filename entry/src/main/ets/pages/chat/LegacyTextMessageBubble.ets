import { DrawnContentRow } from './DrawnContentRow';
import { MessageTextPresentationCache, TRANSLATION_TEXT_INPUT } from '../../util/messageTextInput';
import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { RichMessageView } from './RichMessageView';
import { BUBBLE_AVATAR_GUTTER_VP, bubbleMaxWidth } from '../../util/mediaBox';
import { formatClockTime } from '../../util/formatTime';
import { linkPreviewPresentation, LinkPreviewPresentation } from '../../util/linkPreview';
import { animationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY, bubbleTextFor } from '../../util/theme';
import { str } from '../../util/strings';
import { progressForOr, subscribeProgress } from '../../util/mediaProgressChannel';
import { viewsReserve } from '../../util/viewCountChannel';
import { translationReplacesOriginal } from '../../util/translationMode';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { MessageBubbleContext } from './MessageBubbleShell';
import { MessageBubbleText } from './MessageBubbleText';

const LINK_PREVIEW_HEIGHT_RATIO: number = 0.62;
const LINK_PREVIEW_THUMB: number = 58;
const LINK_CARD_CHROME_W: number = 21;

interface RichContentBuilderParams {
  text: string;
  entities: TdObject[];
  maxWidth: number;
}
@Styles
function msgLinkCardNormalStyle() { .opacity(1).scale({ x: 1, y: 1 }) }

@Styles
function msgLinkCardPressedStyle() { .opacity(0.8).scale({ x: 0.986, y: 0.986 }) }

// 正文、富消息与链接预览的完整行入口，只订阅预览图下载。
@ComponentV2
export struct LegacyTextMessageBubble {
  private translationInputCache: MessageTextPresentationCache = new MessageTextPresentationCache();
  private textInputCache: MessageTextPresentationCache = new MessageTextPresentationCache();
  @Require @Param msg: MessageEntry;
  @Require @Param group: AlbumGroup;
  @Require @Param data: MessageBubbleRenderData;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param jumpFocus: number = 0;
  @Param leaving: number = 0;
  private context: MessageBubbleContext = new MessageBubbleContext();
  private env: ChatEnvMirror = chatEnv;
  @Local private linkPreviewOpening: boolean = false;
  private openingTimer: number = -1;
  private contentRowId: number = 0;
  private contentLinkUrl: string = '';

  private clearOpening(): void {
    if (this.openingTimer !== -1) {
      clearTimeout(this.openingTimer);
      this.openingTimer = -1;
    }
    if (this.linkPreviewOpening) { this.linkPreviewOpening = false; }
  }

  private syncContentIdentity(): void {
    if (this.contentRowId !== this.msg.rowId || this.contentLinkUrl !== this.msg.linkUrl) {
      this.clearOpening();
      this.contentRowId = this.msg.rowId;
      this.contentLinkUrl = this.msg.linkUrl;
    }
  }

  private releaseContent(): void {
    this.detachMessageChannels();
    this.clearOpening();
  }

  private attachedRowId: number = 0;
  private attachedLinkPhotoFileId: number = 0;
  @Local private liveLinkPhotoProgress: number = 0;
  private unsubLinkPhotoProgress: (() => void) | null = null;

  private attachMessageChannels(message: MessageEntry): void {
    this.syncContentIdentity();
    this.detachMessageChannels();
    this.seedProgress(message);
    if (message.linkPhotoFileId !== 0) {
      this.unsubLinkPhotoProgress = subscribeProgress(message.linkPhotoFileId,
        (percent: number): void => { this.liveLinkPhotoProgress = percent; });
    }
    // 原地替换媒体可能只换 fileId；保留精确的通道身份，普通正文/状态更新不重挂。
    this.attachedRowId = message.rowId;
    this.attachedLinkPhotoFileId = message.linkPhotoFileId;
  }

  private seedProgress(message: MessageEntry): void {
    this.liveLinkPhotoProgress = progressForOr(message.linkPhotoFileId, message.linkPhotoProgress);
  }

  private detachMessageChannels(): void {
    if (this.unsubLinkPhotoProgress !== null) {
      this.unsubLinkPhotoProgress();
      this.unsubLinkPhotoProgress = null;
    }
    this.attachedRowId = 0;
  }

  @Monitor('msg')
  onMsgPropChanged(): void {
    this.syncContentIdentity();
    if (this.attachedRowId !== this.msg.rowId ||
      this.attachedLinkPhotoFileId !== this.msg.linkPhotoFileId) {
      this.attachMessageChannels(this.msg);
    } else {
      this.seedProgress(this.msg);
    }
  }

  aboutToAppear(): void { this.attachMessageChannels(this.msg); }
  aboutToReuse(): void { this.attachMessageChannels(this.msg); }
  aboutToDisappear(): void { this.releaseContent(); }
  aboutToRecycle(): void { this.releaseContent(); }

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

  private avatarReserve(): number {
    return this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
  }

  private effectDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }

  private cardMaxW(): number {
    return this.inlineMaxW() - LINK_CARD_CHROME_W;
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
      this.actions.onLinkPreviewRetry(this.msg.id);
      return;
    }
    const presentation: LinkPreviewPresentation = this.linkPresentation();
    if (!presentation.actionable || this.linkPreviewOpening) {
      return;
    }
    this.linkPreviewOpening = true;
    this.openingTimer = setTimeout((): void => {
      this.openingTimer = -1;
      this.linkPreviewOpening = false;
    }, 650);
    this.actions.onLinkTap(this.msg.linkUrl, false); // 预览卡片本身就展示了站点，直接开
  }

  private linkPreviewActionLabel(): string {
    if (this.msg.linkPhotoFailed) {
      return str('mb_reload_preview');
    }
    return this.linkPreviewOpening ? str('opening_dots') : this.linkPresentation().actionLabel;
  }

  private messageTimeText(): string {
    return formatClockTime(this.msg.date);
  }

  private timeReserve(): string {
    const editReserve = this.msg.editDate > 0 ? '         ' : '';
    return `${viewsReserve(this.context.liveViews)}${editReserve}  ${this.messageTimeText()}${this.msg.isOutgoing ? '   ' : ''}`;
  }

  private replacementTranslationShown(): boolean {
    return translationReplacesOriginal(
      this.env.translateReplaceOriginal,
      this.msg.translatedText,
      this.msg.translationHidden
    );
  }

  private displayedMessageText(original: string): string {
    return this.replacementTranslationShown() ? this.msg.translatedText : original;
  }

  private displayedMessageEntities(original: TdObject[]): TdObject[] {
    // TDLib 的实体偏移属于原文，不能套到另一段译文上——译文用译文自己那份。
    // 这里曾经返回一个**恒为空**的数组，于是译文一上屏就丢掉全部格式：加粗、
    // 代码块，以及撑着"展开引用"的 textEntityTypeExpandableBlockQuote。
    // 用户 2026-09-10 报的「翻译后被强制展开、样式被破坏」就是它。
    // 服务端没给实体时这里仍是空数组，渲染层照旧自动识别链接（richText 的
    // AUTO_LINK_RE 只在 entities 为空时才上场），和从前一致。
    // 数组身份稳定（挂在 MessageEntry 上，每条消息一份），parseFormattedText
    // 的按身份缓存不会串槽。
    return this.replacementTranslationShown() ? this.msg.translatedEntities : original;
  }

  @Builder
  richContent(params: RichContentBuilderParams) {
    MessageBubbleText({ actions: this.actions,
      context: this.context, presentation: this.textInputCache.prepare(this.msg, this.group.showSenderName, this.data,
        params.text, params.entities, params.maxWidth, 'body') });
  }

  @Builder
  translationBlock() {
    if (this.msg.translatedText !== '' || this.context.translationStatus !== null) {
      MessageBubbleText({ actions: this.actions,
        context: this.context, presentation: this.translationInputCache.prepare(this.msg, this.group.showSenderName, this.data,
          TRANSLATION_TEXT_INPUT.text, TRANSLATION_TEXT_INPUT.entities, 0, 'translation') });
    }
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
  linkPreviewThumb() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.msg.linkPhotoPath !== '') {
        Image(this.msg.linkPhotoPath.startsWith('/')
          ? `file://${this.msg.linkPhotoPath}` : this.msg.linkPhotoPath).draggable(false)
          .width(LINK_PREVIEW_THUMB).height(LINK_PREVIEW_THUMB).objectFit(ImageFit.Cover)
          .transition(TransitionEffect.OPACITY.animation({
            duration: this.effectDuration(180), curve: Curve.EaseOut
          }));
      } else {
        Column({ space: 5 }) {
          if (this.msg.linkPhotoFailed) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([this.accent()]);
          } else {
            LoadingProgress().width(22).height(22).color(this.accent());
          }
        }
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .width(LINK_PREVIEW_THUMB).height(LINK_PREVIEW_THUMB)
        .backgroundColor($r('app.color.surface_alt'));
      }
    }
    .width(LINK_PREVIEW_THUMB).height(LINK_PREVIEW_THUMB)
    .borderRadius(LINK_PREVIEW_THUMB / 2).clip(true);
  }

  @Builder
  linkPreviewHero() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.msg.linkPhotoPath !== '') {
        Image(this.msg.linkPhotoPath.startsWith('/')
          ? `file://${this.msg.linkPhotoPath}` : this.msg.linkPhotoPath).draggable(false)
          .width(this.cardMaxW()).height(this.linkPreviewH()).objectFit(ImageFit.Cover)
          .transition(TransitionEffect.OPACITY.animation({
            duration: this.effectDuration(180), curve: Curve.EaseOut
          }));
      } else {
        Column({ space: 5 }) {
          if (this.msg.linkPhotoFailed) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(24).fontColor([this.accent()]);
            Text($r('app.string.mb_photo_load_failed')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
          } else {
            LoadingProgress().width(26).height(26).color(this.accent());
            if (this.liveLinkPhotoProgress > 0 && this.liveLinkPhotoProgress < 100) {
              Text(`${this.liveLinkPhotoProgress}%`).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
            }
          }
        }
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .width(this.cardMaxW()).height(this.linkPreviewH())
        .backgroundColor($r('app.color.surface_alt'));
      }
    }
    .width(this.cardMaxW()).height(this.linkPreviewH())
    .borderRadius(8).clip(true);
  }

  @Builder
  linkPreviewCard() {
    Column() {
      if (this.compactTelegramPreview()) {
        Row({ space: 10 }) {
          this.linkPreviewMeta(true);
          this.linkPreviewThumb();
        }
        .width(this.cardMaxW()).alignItems(VerticalAlign.Center);
      } else {
        this.linkPreviewMeta(false);
        if (this.msg.linkPhotoFileId !== 0) {
          this.linkPreviewHero();
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
      if (this.context.gestureClaimed) { return; }
      this.openOrRetryLinkPreview(); });
  }

  private hasTranslationStatusRow(): boolean {
    return this.msg.translatedText === '' && this.context.translationStatus !== null;
  }

  private timeReserveInText(): boolean {
    // 最后一行是翻译脚注或翻译状态行时，时间戳的占位改由那一行承担。
    return this.msg.reactions.length === 0 && this.msg.translatedText === '' &&
      !this.hasTranslationStatusRow();
  }

  @Builder
  content() {
    if (this.msg.contentType === 'richMessage') {
      if (this.replacementTranslationShown()) {
        // TDLib 返回的是纯文本译文，没有可映射回页面块的结构；替换时按普通正文画。
        this.richContent({
          text: this.displayedMessageText(this.msg.text),
          entities: this.displayedMessageEntities(this.msg.textEntities),
          maxWidth: this.inlineMaxW()
        });
      } else {
        // 原文仍用块渲染，保留标题分档、引用竖条和列表符号。
        RichMessageView({
          rawBlocks: this.msg.richBlocks ?? [],
          maxWidth: this.inlineMaxW(),
          onOpenUrl: (url: string): void => {
            if (this.context.gestureClaimed) { return; }
            // 块渲染这条路拿不到链接显示的文字，保留先确认。
            this.actions.onLinkTap(url, true);
          }
        });
      }
      this.translationBlock();
    } else if (this.msg.contentType === 'text') {
      if (this.displayedMessageText(this.msg.text).trim() === '') {
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
          text: this.displayedMessageText(this.msg.text),
          entities: this.displayedMessageEntities(this.msg.textEntities),
          maxWidth: this.inlineMaxW()
        });
      }
      if (this.hasLinkPreview()) {
        this.linkPreviewCard();
      }
      this.translationBlock();

    }
  }

  build() {
    DrawnContentRow({ msg: this.msg, group: this.group, data: this.data, actions: this.actions,
      nowSec: this.nowSec, jumpFocus: this.jumpFocus, leaving: this.leaving, context: this.context }) {
      this.content();
    }
  }
}
