import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { ChatEnvMirror, chatEnv } from '../../util/chatEnvMirror';
import { BUBBLE_AVATAR_GUTTER_VP, BUBBLE_ROW_SIDE_VP, bubbleMaxWidth } from '../../util/mediaBox';
import { formatClockTime } from '../../util/formatTime';
import { parseFormattedText, richSegmentKey, RichSegment, RichRun } from '../../util/richText';
import { animationDurationFor, persistentAnimationDurationFor, scrollActiveNow } from '../../util/scrollEffects';
import { COLOR_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY, bubbleTextFor } from '../../util/theme';
import { languageDisplayName } from '../../services/TranslationService';
import { str } from '../../util/strings';
import { viewsReserve } from '../../util/viewCountChannel';
import { translationReplacesOriginal } from '../../util/translationMode';
import { timeLayerMinWidth } from '../../util/timeLayerWidth';
import { AlbumGroup } from '../../util/collapseAlbums';
import { MessageBubbleActions, MessageBubbleRenderData } from './ReusableMessageBubble';
import { linkTextHidesUrl } from '../../util/messageLinkAction';
import { MessageBubbleContext } from './MessageBubbleShell';

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

type MessageTextMode = 'body' | 'caption' | 'translation';

@Styles
function msgLinkRunNormalStyle() { .opacity(1) }

@Styles
function msgLinkRunPressedStyle() { .opacity(0.52) }

// 消息正文和媒体配文共用的富文本渲染能力，包含剧透/可展开引用和翻译。
// 无独立通道订阅；只读取公共壳已播种的时间/翻译状态。
@ComponentV2
export struct MessageBubbleText {
  @Require @Param context: MessageBubbleContext;
  @Param text: string = '';
  @Param entities: TdObject[] = [];
  @Param maxWidth: number = 0;
  @Param mode: MessageTextMode = 'body';
  private env: ChatEnvMirror = chatEnv;

  @Require @Param msg: MessageEntry;

  @Require @Param group: AlbumGroup;

  @Require @Param data: MessageBubbleRenderData;

  @Require @Param actions: MessageBubbleActions;

  @Local revealedSpoilerKeys: string[] = [];

  @Local expandedQuoteKeys: string[] = [];
  private textRowId: number = 0;
  private previousText: string = '';

  aboutToAppear(): void { this.rememberTextSource(); }

  aboutToReuse(): void { this.rememberTextSource(); }

  private rememberTextSource(): void {
    this.textRowId = this.msg.rowId;
    this.previousText = this.text;
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

  private avatarReserve(): number {
    return this.data.isGroup && !this.msg.isOutgoing ? BUBBLE_AVATAR_GUTTER_VP : 0;
  }

  private effectDuration(duration: number): number {
    return animationDurationFor(
      this.env.chatEffects && this.env.messageEffects && !this.env.powerSaving,
      scrollActiveNow(), duration);
  }

  private persistentEffectDuration(duration: number): number {
    return persistentAnimationDurationFor(
      this.env.chatEffects, this.env.messageEffects, this.env.powerSaving, duration);
  }

  private linkRunBackground(run: RichRun): ResourceColor {
    if (this.env.linkNavBusy === run.url) {
      return $r('app.color.select_highlight');
    }
    // 【代码体底色必须是半透明叠加，不能是不透明底色】
    // 原来用的是 surface_alt——那是**页面级**底色（深色 #2B3A4C），而气泡底是
    // bubble_in #182533 / bubble_out #2B5278，三个色值互不相干。不透明底盖上去
    // 明度差一眼看得出，于是标签"浮"在气泡上，用户原话：像打了个补丁。
    // code_surface 是 6% 黑 / 10% 白的叠加层，落在哪种气泡上都只是薄薄提亮/压暗
    // 一档，跟着气泡走。
    return run.code ? $r('app.color.code_surface') : Color.Transparent;
  }

  private messageTimeText(): string {
    return formatClockTime(this.msg.date);
  }

  private timeReserve(): string {
    const editReserve = this.msg.editDate > 0 ? '         ' : '';
    return `${viewsReserve(this.context.liveViews)}${editReserve}  ${this.messageTimeText()}${this.msg.isOutgoing ? '   ' : ''}`;
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
          if (this.context.gestureClaimed) { return; }
          this.revealSpoiler(run); });
    } else if (run.customEmojiId !== '' && this.inlineCustomEmojiPath(run.customEmojiId) !== '') {
      ImageSpan(this.inlineCustomEmojiSource(run.customEmojiId))
        .width(this.env.msgTextSize + 3)
        .height(this.env.msgTextSize + 3)
        .verticalAlign(ImageSpanAlignment.CENTER)
        .objectFit(ImageFit.Contain);
    } else if (run.url !== '' && this.env.linkNavBusy === run.url) {
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
        .textBackgroundStyle({ color: this.linkRunBackground(run), radius: 3 })
        // iterations: -1 + Alternate —— 一次状态变化就能永远来回，不需要
        // 定时器逐帧改状态（那会把整个气泡按帧重建）。省电模式下
        // effectDuration 归零，退化成一个静止的暗色药丸，仍然看得出在忙。
        .animation({
          duration: this.persistentEffectDuration(620),
          curve: Curve.EaseInOut,
          iterations: -1,
          playMode: PlayMode.Alternate
        })
        .stateStyles({ normal: msgLinkRunNormalStyle, pressed: msgLinkRunPressedStyle })
        .animation({ duration: this.persistentEffectDuration(90), curve: Curve.EaseOut })
        .onClick(() => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onLinkTap(run.url, linkTextHidesUrl(run.text, run.url)); });
    } else if (run.url !== '') {
      // **闲着的链接：一个 .animation() 都不写。**
      //
      // 上面那条呼吸药丸只在"正在问服务器"时才有意义，可它原来是和普通链接
      // 共用一支的——于是每条含链接的消息，每次 ExecuteRerender 都要建两个
      // JSAnimation 上下文，各自同步 flush 一轮 FlushLayoutTask。09-03 的
      // Frame 录制里 `duration:620` 出现 20 次、81.6ms、单次最大 25.32ms，
      // 全部落在滚动段——而那段时间用户一个链接都没点。
      //
      // 下面那条注释（普通 run 为什么不挂 .animation()）解释了为什么
      // duration:0 挡不住：唯一的办法就是不写修饰器。这一支就是照做。
      Span(run.text)
        .fontWeight(run.bold ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(run.italic ? FontStyle.Italic : FontStyle.Normal)
        .fontFamily(run.code ? 'monospace' : '')
        .fontColor(this.accent())
        .decoration({ type: this.richRunDecoration(run), color: this.accent() })
        .textBackgroundStyle({
          color: run.code ? $r('app.color.code_surface') : Color.Transparent,
          radius: run.code ? 3 : 0
        })
        .stateStyles({ normal: msgLinkRunNormalStyle, pressed: msgLinkRunPressedStyle })
        .onClick(() => {
          if (this.context.gestureClaimed) { return; }
          this.actions.onLinkTap(run.url, linkTextHidesUrl(run.text, run.url)); });
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
          color: run.code ? $r('app.color.code_surface') : Color.Transparent,
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
                  if (this.context.gestureClaimed) { return; }
                  this.actions.onCopyCode(seg.text); });
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
                  if (this.context.gestureClaimed) { return; }
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

  @Builder
  translationSeparator() {
    // Divider 即便 alignSelf(Stretch)，在当前 ArkUI 上仍会先按父级 maxWidth
    // 参与固有尺寸测量，把短气泡撑满。空 Row 的固有宽度为 0，父列先由文字
    // 定宽，再在交叉轴上拉伸它，视觉相同但不会反向决定气泡宽度。
    Row()
      .height(0.6)
      .alignSelf(ItemAlign.Stretch)
      .backgroundColor(COLOR_TEXT_SECONDARY)
      .opacity(0.3)
      .margin({ top: 6, bottom: 5 })
      // 和译文同一条曲线一起淡入。分隔线不跟着淡的话会先硬出现、字再淡入，
      // 看着是两步。
      .transition(TransitionEffect.OPACITY.animation({
        duration: this.effectDuration(260), curve: Curve.FastOutSlowIn
      }));
  }

  @Builder
  translationBlock() {
    // 译文还没到：显示瞬时态。分隔线沿用译文那条，让三种状态占同一个位置。
    if (this.msg.translatedText === '' && this.context.translationStatus !== null) {
      this.translationSeparator();
      if (this.context.translationStatus?.phase === 'loading') {
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
          Text(str('mb_translate_failed', this.context.translationStatus?.error ?? ''))
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
          if (this.context.gestureClaimed) { return; }
          this.actions.onRetryTranslation(this.msg.id); });
      }
    }
    if (this.msg.translatedText !== '') {
      this.translationSeparator();
      if (!this.msg.translationHidden && !this.replacementTranslationShown()) {
        Text(this.msg.translatedText)
          .fontSize(this.env.msgTextSize)
          .lineHeight(this.env.msgTextSize * 1.34)
          .fontStyle(FontStyle.Italic)
          .fontColor(bubbleTextFor(this.msg.isOutgoing))
          .wordBreak(WordBreak.BREAK_WORD)
          .constraintSize({ maxWidth: this.inlineMaxW() })
          // 译文到货时淡入 + 轻微上移，不再是硬切（用户 2026-09-09：
          // 「现在是闪过去的」）。
          //
          // ⚠️ **必须是 transition，不能给气泡加 .animation()。** 常驻动画会让
          // ArkUI 在组件更新时建立动画上下文，把同一刷新周期里的列表脏节点一起
          // 拖进动画布局——2026-08-27 的真机 trace 量过，最重的一帧从 210ms
          // 涨到 463ms，而**翻译态**正是那条注释点名的、必须落在动画上下文之外的
          // 数据更新之一（见本文件气泡根节点上那段长注释）。
          // transition 只作用在这个节点的出现/消失上，不建立那种上下文。
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: -6 }))
            .animation({ duration: this.effectDuration(260), curve: Curve.FastOutSlowIn }));
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
        if (this.context.gestureClaimed) { return; }
        this.actions.onToggleTranslation(this.msg.id, !this.msg.translationHidden);
      });
    }
  }

  private isBareEmoji(): boolean {
    return this.msg.contentType === 'emoji' || this.msg.contentType === 'sticker'
      || this.msg.contentType === 'customEmoji' || this.msg.contentType === 'videoNote'
      || this.msg.contentType === 'dice';
  }

  private hasTranslationStatusRow(): boolean {
    return this.msg.translatedText === '' && this.context.translationStatus !== null;
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

  private senderLabelShown(): boolean {
    return this.data.isGroup && !this.msg.isOutgoing && this.msg.senderName !== '' && this.group.showSenderName;
  }

  private commentsRowShown(): boolean {
    return this.data.isChannel && this.msg.commentCount > 0;
  }

  build() {
    if (this.mode === 'translation') {
      this.translationBlock();
    } else if (this.mode === 'caption') {
      if (this.displayedMessageText(this.text) !== '') {
        Column() {
          this.richContent({ text: this.displayedMessageText(this.text),
            entities: this.displayedMessageEntities(this.entities), maxWidth: this.inlineMaxW() });
          this.translationBlock();
        }.margin({ top: 6 });
      }
    } else {
      this.richContent({ text: this.text, entities: this.entities, maxWidth: this.maxWidth });
    }
  }

  @Monitor('msg', 'text')
  resetTextState(): void {
    // MessageEntry 是普通快照，监听 @Param 根对象，再按身份判断。
    // 同一行的发送态/下载态更新不能收起用户已经展开的引用。
    if (this.textRowId !== this.msg.rowId || this.previousText !== this.text) {
      this.revealedSpoilerKeys = [];
      this.expandedQuoteKeys = [];
      this.rememberTextSource();
    }
  }
}
