import { DrawnPollLayout } from './DrawnPollLayout';
import { DrawnPollOptionDecoration, DrawnPollPercentLabels } from './DrawnPollOptionDecoration';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { TdObject } from '../../tdkit/TdTypes';
import { DrawnPollText } from './DrawnPollText';
import { PollDraftSync, PollSelectionSummary, summarizePollOptions } from '../../util/pollDraftState';
import { MessageEntry } from '../../store/MessageEntry';
import { PollOptionInfo } from '../../util/formatMsgContent';
import { pollOptionState } from '../../util/pollOptionState';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plural, str } from '../../util/strings';
import { MessageBubbleContext } from './MessageBubbleShell';
import { MessageBubbleActions } from './ReusableMessageBubble';

// 成员 @Styles 迁全局（V2 不支持成员 @Styles，四组均无状态依赖）。
@Styles
function pollOptionNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }

@Styles
function pollOptionPressedStyle() { .scale({ x: 0.985, y: 0.985 }).opacity(0.76) }

@Styles
function pollSubmitNormalStyle() { .scale({ x: 1, y: 1 }).opacity(1) }

@Styles
function pollSubmitPressedStyle() { .scale({ x: 0.97, y: 0.97 }).opacity(0.72) }

function sameNumberArray(a: number[], b: number[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

// P4 批 5：迁 @ComponentV2（配方同批 1~4）。复用在 aboutToReuse 同步重置
// 草稿；@Monitor 兜非复用路径（挂错 = 草稿勾选来自上一条投票）。
//
// 【滚动帧率优化】
// 1. 17 个散装 @Param + 内联闭包 + pollRevision 字符串拼接收敛为 msg/context/actions/nowSec/maxWidth。
// 2. 移除 ForEach（旧键含 option.text / votePercentage，复用命中率 0%，每滚过一道题
//    都在主线程销毁并重建 ~40 个原生节点），常见 0..9 固定槽位 + 常驻内部节点，额外选项按稳定索引扩展。
// 3. 移除选项进度条、选项卡片与提交按钮上的常驻 .animation()，消除复用重绑时的
//    JSAnimation -> FlushLayoutTask -> Measure[List] 同步布局冲刷。
// 4. 已关闭或已过期的历史答题不再读取 @Param nowSec，避免每秒一次的时钟跳动把屏上所有答题拖进重绘。
@ComponentV2
export struct PollBubble {
  @Require @Param msg: MessageEntry;
  @Require @Param context: MessageBubbleContext;
  @Require @Param actions: MessageBubbleActions;
  @Param prepared: DrawnPollLayout | null = null;
  @Param nowSec: number = 0;
  @Param maxWidth: number = 260;
  @Param fitAvailableWidth: boolean = false;
  @Event onBeforeAction: () => boolean = (): boolean => true;

  private emptyEntities: TdObject[] = [];
  @Local draftIds: number[] = [];
  @Local draftChanged: boolean = false;

  private richLinkClaimed: boolean = false;
  private richLinkTimer: number = -1;
  private percentLabels: DrawnPollPercentLabels = new DrawnPollPercentLabels();
  private decorationUnits: DrawnTextUnits = new DrawnTextUnits();
  private decorations: DrawnPollOptionDecoration[] = [];
  private draftSync: PollDraftSync = new PollDraftSync();

  // @Computed 必须声明在 @Param / @Local 之后（@ReusableV2 按声明顺序重置）。
  @Computed
  get isExpired(): boolean {
    if (this.msg.pollIsClosed || this.msg.pollCloseDate <= 0) {
      return false;
    }
    // 若按当前墙钟已到达截止时间，过期是不可逆终态，直接返回 true 而不订阅每秒跳动的 nowSec。
    if (Math.floor(Date.now() / 1000) >= this.msg.pollCloseDate) {
      return true;
    }
    return this.nowSec >= this.msg.pollCloseDate;
  }

  @Computed
  get selectionSummary(): PollSelectionSummary { return summarizePollOptions(this.msg.pollOptions); }

  @Computed
  get draftMembership(): Set<number> { return new Set<number>(this.draftIds); }

  @Computed
  get extraOptionIndices(): number[] {
    const indices: number[] = [];
    for (let i = 10; i < this.msg.pollOptions.length; i++) { indices.push(i); }
    return indices;
  }

  @Computed
  get hasVoted(): boolean { return this.selectionSummary.chosenIds.length > 0; }

  @Computed
  get isSubmitting(): boolean { return this.msg.pollVotePending || this.selectionSummary.pending; }

  @Computed
  get isUnavailable(): boolean {
    // 判据是「一个选项都没有」，不是「少于两个」。
    //
    // 2026-11-03 真机 + 桌面端截图对照：服务端确实会下发**单选项**投票
    // （桌面端正常渲染一行选项 + 单选圈），而这里原来按 < 2 判成不可用，
    // 气泡于是同时显示「投票内容不可用」和「没有可用的投票选项」。
    return this.msg.pollQuestion.trim() === '' || this.msg.pollOptions.length === 0;
  }

  @Computed
  get isResultsVisible(): boolean {
    return this.hasVoted || this.msg.pollIsClosed || this.isExpired;
  }

  @Computed
  get isInteractive(): boolean {
    if (this.isUnavailable || this.isSubmitting || this.msg.pollIsClosed || this.isExpired) {
      return false;
    }
    return !(this.msg.pollIsQuiz && this.hasVoted);
  }

  aboutToAppear(): void { this.resetOwner(); }
  aboutToReuse(): void { this.resetOwner(); }

  private resetOwner(): void {
    this.resetLinkClaim();
    this.draftSync = new PollDraftSync();
    this.onMsgChanged();
  }

  @Monitor('msg')
  onMsgChanged(): void {
    if (this.decorations.length > this.msg.pollOptions.length) { this.decorations.length = this.msg.pollOptions.length; }
    if (this.draftSync.update(this.msg.rowId, this.msg.pollId, this.selectionSummary,
      this.isSubmitting, this.msg.pollVoteError, this.msg.pollIsClosed)) { this.resetDraft(); }
  }

  private chosenIds(): number[] { return this.selectionSummary.chosenIds.slice(); }

  private resetDraft(): void {
    const nextIds: number[] = this.chosenIds();
    if (!sameNumberArray(this.draftIds, nextIds)) {
      this.draftIds = nextIds;
    }
    if (this.draftChanged) {
      this.draftChanged = false;
    }
  }

  private optionAt(index: number): PollOptionInfo | undefined {
    return this.msg.pollOptions[index];
  }

  private selected(index: number): boolean {
    if (this.draftChanged) {
      return this.draftMembership.has(index);
    }
    // MessageStore marks the submitted target set with isBeingChosen while
    // TDLib is processing the request. Message rows are keyed by that mutable
    // state and may be rebuilt, so the pending flag must itself render as the
    // active selection instead of relying only on this component's local draft.
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    if (this.isSubmitting) {
      return opt !== undefined && opt.isBeingChosen;
    }
    return opt !== undefined && opt.isChosen;
  }

  private emitVote(optionIds: number[]): void {
    if (this.context.gestureClaimed) {
      return;
    }
    this.actions.onPollVote(this.msg.id, optionIds);
  }

  private toggleOption(index: number): void {
    if (this.richLinkClaimed || this.context.gestureClaimed || !this.isInteractive || !this.onBeforeAction()) {
      return;
    }
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    if (opt === undefined) {
      return;
    }
    if (!this.msg.pollAllowMultiple) {
      const wasChosen: boolean = opt.isChosen;
      const next: number[] = wasChosen && !this.msg.pollIsQuiz ? [] : [index];
      // Give a single-choice poll immediate visual feedback. The authoritative
      // update still comes from TDLib; on failure the msg watcher resets
      // this draft to the server-backed option state.
      this.draftIds = next;
      this.draftChanged = true;
      this.emitVote(next);
      return;
    }
    const base: number[] = this.draftChanged ? this.draftIds.slice() : this.chosenIds();
    const at: number = base.indexOf(index);
    if (at >= 0) {
      base.splice(at, 1);
    } else {
      base.push(index);
    }
    this.draftIds = base;
    this.draftChanged = true;
  }

  private submitDraft(): void {
    if (this.isInteractive && this.msg.pollAllowMultiple && this.draftChanged && !this.richLinkClaimed && !this.context.gestureClaimed && this.onBeforeAction()) {
      this.emitVote(this.draftIds.slice());
    }
  }

  private optionState(index: number): string {
    const options: PollOptionInfo[] = this.msg.pollOptions;
    const opt: PollOptionInfo | undefined = options[index];
    return pollOptionState({
      isQuiz: this.msg.pollIsQuiz,
      resultsVisible: this.isResultsVisible,
      correctOptionId: this.msg.pollCorrectOptionId,
      optionCount: options.length,
      index: index,
      chosen: opt !== undefined && opt.isChosen,
      selected: this.selected(index),
      submitting: this.isSubmitting
    });
  }

  private optionMarked(index: number): boolean {
    const state: string = this.optionState(index);
    return this.selected(index) || state === 'correct' || state === 'wrong';
  }

  private optionAccent(index: number): string {
    const state: string = this.optionState(index);
    if (state === 'correct') { return '#32A765'; }
    if (state === 'wrong') { return '#D9514E'; }
    if (state !== 'neutral') { return '#3390EC'; }
    return this.isResultsVisible ? '#86919D' : '#99A2AC';
  }

  private optionFill(index: number): string {
    const accent: string = this.optionAccent(index);
    if (accent === '#32A765') {
      return '#2032A765';
    }
    if (accent === '#D9514E') {
      return '#20D9514E';
    }
    return this.selected(index) ? '#183390EC' : '#0D000000';
  }

  private optionVotePercentage(index: number): number {
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    return opt !== undefined ? opt.votePercentage : 0;
  }

  private optionBarPercent(index: number): number {
    if (!this.isResultsVisible) {
      return 0;
    }
    const pct: number = this.optionVotePercentage(index);
    return pct > 0 ? pct : 0;
  }

  private optionHasText(index: number): boolean {
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    return opt !== undefined && opt.text.trim() !== '';
  }

  private optionDisplayText(index: number): string {
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    if (opt !== undefined && opt.text.trim() !== '') {
      return opt.text;
    }
    return str('poll_unnamed_option');
  }

  private optionAccessibilityText(index: number): string {
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    if (opt === undefined) {
      return '';
    }
    return `${opt.text}，${opt.votePercentage}%`;
  }

  private richTextWidth(inset: number): number {
    const width = this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(220, Math.min(278, this.maxWidth));
    return Math.max(1, width - inset);
  }
  private resetLinkClaim(): void {
    if (this.richLinkTimer !== -1) { clearTimeout(this.richLinkTimer); this.richLinkTimer = -1; }
    this.richLinkClaimed = false;
  }
  aboutToDisappear(): void { this.resetLinkClaim(); }
  aboutToRecycle(): void { this.resetLinkClaim(); }
  private claimTextLink(): boolean {
    if (this.richLinkClaimed || this.context.gestureClaimed || !this.onBeforeAction()) { return false; }
    this.richLinkClaimed = true;
    // ClickEvent has no stopPropagation on the project's SDK. Consume only
    // this dispatch, including a parent option callback; keyboard taps recover.
    this.richLinkTimer = setTimeout((): void => { this.richLinkTimer = -1; this.richLinkClaimed = false; }, 0);
    return true;
  }

  private statusText(): string {
    if (this.isUnavailable) {
      return str('poll_unavailable');
    }
    const type: string = this.msg.pollIsQuiz ? str('poll_quiz_word') :
      (this.msg.pollIsAnonymous ? str('poll_anonymous') : str('poll_public'));
    if (this.msg.pollIsClosed || this.isExpired) {
      return str('poll_type_closed', type);
    }
    if (this.msg.pollCloseDate > 0) {
      const remaining: number = Math.max(0, this.msg.pollCloseDate - this.nowSec);
      if (remaining < 3600) {
        return str('poll_type_closes_in', type, Math.max(1, Math.ceil(remaining / 60)));
      }
    }
    return type;
  }

  private voterText(): string {
    const count: number = Math.max(0, this.msg.pollTotalVoterCount);
    return plural('poll_voters', count, count);
  }

  private optionDecoration(index: number): DrawnPollOptionDecoration {
    let decoration = this.decorations[index];
    if (decoration === undefined) {
      decoration = new DrawnPollOptionDecoration();
      this.decorations[index] = decoration;
    }
    const units = this.decorationUnits.prepare(this.getUIContext(), `${textMeasureEnvironment.epoch}`);
    const accent = this.optionAccent(index);
    const label = this.isResultsVisible ? this.percentLabels.prepare(this.optionVotePercentage(index), accent,
      units.fp2px(11.5), 40 * units.density, `${textMeasureEnvironment.epoch}`) : null;
    return decoration.bind(units.density, accent, this.optionState(index),
      this.optionMarked(index), this.optionBarPercent(index), label);
  }

  @Builder
  private optionSlot(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      Row({ space: 8 }) {
        Stack() {
          if (this.optionState(index) === 'pending') {
            LoadingProgress().width(14).height(14).color(Color.White);
          }
        }.width(20).height(20);
        DrawnPollText({ msg: this.msg, content: this.optionDisplayText(index),
          preparedLayout: this.prepared?.options[index] ?? null,
          entities: this.optionAt(index)?.entities ?? this.emptyEntities, boxWidth: this.richTextWidth(94),
          textColor: this.optionHasText(index) ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY,
          onBeforeLink: (): boolean => this.claimTextLink(),
          onLink: (url: string, hidesUrl: boolean): void => this.actions.onLinkTap(url, hidesUrl) })
          .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 9, right: 57, top: 7, bottom: 7 });
    }
    .width('100%')
    .constraintSize({ minHeight: 40 })
    .height(this.prepared?.optionHeights[index])
    .drawModifier(this.optionDecoration(index))
    .backgroundColor(this.optionFill(index))
    .border({ width: 1, color: this.optionMarked(index) ? this.optionAccent(index) : '#16000000' })
    .borderRadius(10)
    .clip(true)
    .stateStyles({
      normal: pollOptionNormalStyle,
      pressed: pollOptionPressedStyle
    })
    .opacity(this.isInteractive ? 1 : 0.9)
    .accessibilityText(this.optionAccessibilityText(index))
    .onClick((): void => { this.toggleOption(index); });
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 7 }) {
        Text(this.msg.pollIsQuiz ? '💡' : '📊').fontSize(16);
        Text(this.msg.pollIsQuiz ? $r('app.string.poll_quiz_word') : $r('app.string.poll_word'))
          .fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY)
          .maxLines(this.prepared ? 1 : undefined).layoutWeight(this.prepared ? 1 : 0);
        if (!this.prepared) { Blank(); }
        Text(this.statusText())
          .fontSize(10.5)
          .fontColor(this.isUnavailable || this.msg.pollIsClosed || this.isExpired
            ? '#9A6562' : COLOR_TEXT_SECONDARY)
          .maxLines(this.prepared ? 1 : undefined).layoutWeight(this.prepared ? 1 : 0);
      }.width('100%').height(this.prepared?.headerHeight);

      DrawnPollText({ msg: this.msg, preparedLayout: this.prepared?.question ?? null,
        content: this.msg.pollQuestion.trim() !== '' ? this.msg.pollQuestion : str('poll_unavailable'),
        entities: this.msg.pollQuestionEntities ?? this.emptyEntities, boxWidth: this.richTextWidth(0),
        textSize: 15, bold: true, textColor: this.msg.pollQuestion.trim() !== '' ? COLOR_TEXT_PRIMARY : '#B05D58',
        onBeforeLink: (): boolean => this.claimTextLink(),
        onLink: (url: string, hidesUrl: boolean): void => this.actions.onLinkTap(url, hidesUrl) });

      // 投票说明。它在 messagePoll 这一层（不是 poll 里面），带换行与链接实体；
      // 官方客户端就渲染在问题和选项之间（2026-11-04 用户报「文字展示不全」的
      // 真正原因 —— 我们之前根本没读这个字段）。
      if (this.msg.pollDescription.trim() !== '') {
        DrawnPollText({ msg: this.msg, content: this.msg.pollDescription,
          preparedLayout: this.prepared?.description ?? null,
          entities: this.msg.pollDescriptionEntities ?? this.emptyEntities, boxWidth: this.richTextWidth(0),
          onBeforeLink: (): boolean => this.claimTextLink(),
          onLink: (url: string, hidesUrl: boolean): void => this.actions.onLinkTap(url, hidesUrl) })
          .margin({ top: 6 });
      }

      if (this.msg.pollOptions.length >= 1) {
        Column({ space: 6 }) {
          this.optionSlot(0);
          if (this.msg.pollOptions.length > 1) { this.optionSlot(1); }
          if (this.msg.pollOptions.length > 2) { this.optionSlot(2); }
          if (this.msg.pollOptions.length > 3) { this.optionSlot(3); }
          if (this.msg.pollOptions.length > 4) { this.optionSlot(4); }
          if (this.msg.pollOptions.length > 5) { this.optionSlot(5); }
          if (this.msg.pollOptions.length > 6) { this.optionSlot(6); }
          if (this.msg.pollOptions.length > 7) { this.optionSlot(7); }
          if (this.msg.pollOptions.length > 8) { this.optionSlot(8); }
          if (this.msg.pollOptions.length > 9) { this.optionSlot(9); }
          ForEach(this.extraOptionIndices, (index: number) => {
            this.optionSlot(index);
          }, (index: number): string => `${index}`);
        }.width('100%');
      } else {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(17).fontColor(['#B05D58']);
          if (this.prepared?.unavailable) {
            DrawnPollText({ msg: this.msg, content: str('poll_no_options'), preparedLayout: this.prepared.unavailable,
              boxWidth: this.richTextWidth(44), textSize: 12, textColor: '#B05D58' });
          } else {
            Text($r('app.string.poll_no_options')).fontSize(12).fontColor('#B05D58');
          }
        }
        .width('100%')
        .height(this.prepared?.unavailable ? Math.max(17, this.prepared.unavailable.heightVp) + 18 : undefined)
        .padding({ top: 9, bottom: 9, left: 10, right: 10 })
        .backgroundColor('#10D9514E')
        .borderRadius(9);
      }

      if (this.prepared ? this.prepared.showSubmit : this.msg.pollAllowMultiple && this.isInteractive) {
        Row() {
          if (this.msg.pollVotePending) {
            LoadingProgress().width(16).height(16).color(Color.White);
          } else {
            Text(this.hasVoted ? $r('app.string.poll_update_vote') : $r('app.string.poll_submit_vote'))
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White).maxLines(this.prepared ? 1 : undefined);
          }
        }
        .width('100%').height(this.prepared?.submitHeight ?? 34)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.draftChanged ? COLOR_PRIMARY : '#A7AFB8')
        .borderRadius(9)
        .stateStyles({
          normal: pollSubmitNormalStyle,
          pressed: pollSubmitPressedStyle
        })
        .onClick((): void => { this.submitDraft(); });
      }

      if (this.prepared ? this.prepared.showExplanation : this.msg.pollExplanation.trim() !== '' && this.isResultsVisible) {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(15).fontColor([COLOR_PRIMARY]);
          DrawnPollText({ msg: this.msg, content: this.msg.pollExplanation,
            preparedLayout: this.prepared?.explanation ?? null,
            entities: this.msg.pollExplanationEntities ?? this.emptyEntities, boxWidth: this.richTextWidth(40), textSize: 11.5,
            onBeforeLink: (): boolean => this.claimTextLink(),
            onLink: (url: string, hidesUrl: boolean): void => this.actions.onLinkTap(url, hidesUrl) });
        }
        .width('100%')
        .height(this.prepared?.explanation ? Math.max(15, this.prepared.explanation.heightVp) + 14 : undefined)
        .padding({ top: 7, bottom: 7, left: 9, right: 9 })
        .backgroundColor('#0E3390EC')
        .borderRadius(9);
      }

      if (this.msg.pollVoteError.trim() !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(14).fontColor(['#D9514E']);
          if (this.prepared?.error) {
            DrawnPollText({ msg: this.msg, content: this.msg.pollVoteError, preparedLayout: this.prepared.error,
              boxWidth: this.richTextWidth(82), textSize: 10.5, textColor: '#D9514E' });
          } else {
            Text(this.msg.pollVoteError).layoutWeight(1).fontSize(10.5).lineHeight(15).fontColor('#D9514E')
              .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .height(this.prepared?.error ? Math.max(14, this.prepared.error.heightVp) + 10 : undefined)
        .padding({ right: 62, bottom: 10 });
      } else {
        Row() {
          Text(this.voterText()).fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(this.prepared ? 1 : undefined).layoutWeight(this.prepared ? 1 : 0);
          if (!this.prepared) { Blank(); }
          if (this.isSubmitting) {
            Row({ space: 5 }) {
              LoadingProgress().width(13).height(13).color(COLOR_PRIMARY);
              Text($r('app.string.submitting')).fontSize(10.5).fontColor(COLOR_PRIMARY)
                .maxLines(this.prepared ? 1 : undefined);
            }
          }
        }
        .width('100%')
        .height(this.prepared?.footerHeight)
        .padding({ right: 62, bottom: 10 });
      }
    }
    .width(this.fitAvailableWidth ? Math.max(1, this.maxWidth) : Math.max(220, Math.min(278, this.maxWidth)))
    .alignItems(HorizontalAlign.Start)
    .height(this.prepared?.height)
    .onTouch((event: TouchEvent): void => { if (event.type === TouchType.Down) { this.resetLinkClaim(); } })
    .accessibilityText(`${this.msg.pollQuestion}，${this.statusText()}，${this.voterText()}`);
  }
}
