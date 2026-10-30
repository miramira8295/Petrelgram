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
//    都在主线程销毁并重建 ~40 个原生节点），改为 0..9 固定槽位 + 常驻内部节点。
// 3. 移除选项进度条、选项卡片与提交按钮上的常驻 .animation()，消除复用重绑时的
//    JSAnimation -> FlushLayoutTask -> Measure[List] 同步布局冲刷。
// 4. 已关闭或已过期的历史答题不再读取 @Param nowSec，避免每秒一次的时钟跳动把屏上所有答题拖进重绘。
@ComponentV2
export struct PollBubble {
  @Require @Param msg: MessageEntry;
  @Require @Param context: MessageBubbleContext;
  @Require @Param actions: MessageBubbleActions;
  @Param nowSec: number = 0;
  @Param maxWidth: number = 260;

  @Local draftIds: number[] = [];
  @Local draftChanged: boolean = false;

  private attachedRowId: number = 0;

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
  get hasVoted(): boolean {
    return this.msg.pollOptions.some((option: PollOptionInfo): boolean => option.isChosen);
  }

  @Computed
  get isSubmitting(): boolean {
    return this.msg.pollVotePending || this.msg.pollOptions.some(
      (option: PollOptionInfo): boolean => option.isBeingChosen
    );
  }

  @Computed
  get isUnavailable(): boolean {
    return this.msg.pollQuestion.trim() === '' || this.msg.pollOptions.length < 2;
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

  aboutToAppear(): void {
    this.attachedRowId = this.msg.rowId;
    this.resetDraft();
  }

  aboutToReuse(): void {
    // @Param 已是新值、@Local 已重置：按新 msg 同步铺草稿。
    this.attachedRowId = this.msg.rowId;
    this.resetDraft();
  }

  @Monitor('msg')
  onMsgChanged(): void {
    if (this.attachedRowId !== this.msg.rowId) {
      this.attachedRowId = this.msg.rowId;
      this.resetDraft();
      return;
    }
    if (!this.isSubmitting) {
      this.resetDraft();
    }
  }

  private chosenIds(): number[] {
    const options: PollOptionInfo[] = this.msg.pollOptions;
    const ids: number[] = [];
    for (let i = 0; i < options.length; i++) {
      if (options[i].isChosen) {
        ids.push(i);
      }
    }
    return ids;
  }

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
      return this.draftIds.indexOf(index) >= 0;
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
    if (!this.isInteractive) {
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
    if (this.isInteractive && this.msg.pollAllowMultiple && this.draftChanged) {
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

  private optionShowsGlyph(index: number): boolean {
    const state: string = this.optionState(index);
    return state === 'correct' || state === 'wrong' || state === 'vote';
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

  private optionDisplayText(index: number): ResourceStr {
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    if (opt !== undefined && opt.text.trim() !== '') {
      return opt.text;
    }
    return $r('app.string.poll_unnamed_option');
  }

  private optionIsBeingChosen(index: number): boolean {
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    return opt !== undefined && opt.isBeingChosen;
  }

  private optionAccessibilityText(index: number): string {
    const opt: PollOptionInfo | undefined = this.optionAt(index);
    if (opt === undefined) {
      return '';
    }
    return `${opt.text}，${opt.votePercentage}%`;
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

  @Builder
  private optionSlot(index: number) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Row()
        .width(`${this.optionBarPercent(index)}%`)
        .height(3)
        .backgroundColor(this.optionAccent(index))
        .borderRadius(1.5)
        .opacity(0.5)
        .visibility(this.optionBarPercent(index) > 0 ? Visibility.Visible : Visibility.Hidden);
      Row({ space: 8 }) {
        Stack() {
          Circle({ width: 20, height: 20 })
            .fill(this.optionMarked(index) ? this.optionAccent(index) : Color.Transparent)
            .stroke(this.optionAccent(index))
            .strokeWidth(1.5);
          SymbolGlyph(this.optionState(index) === 'wrong'
            ? $r('sys.symbol.xmark') : $r('sys.symbol.checkmark'))
            .fontSize(11)
            .fontColor([Color.White])
            .visibility(this.optionShowsGlyph(index) ? Visibility.Visible : Visibility.Hidden);
          if (this.optionState(index) === 'pending') {
            LoadingProgress().width(14).height(14).color(Color.White);
          } else if (this.optionState(index) === 'selected') {
            Circle({ width: 7, height: 7 }).fill(Color.White);
          }
        }.width(20).height(20);
        Text(this.optionDisplayText(index))
          .layoutWeight(1)
          .fontSize(13.5)
          .fontWeight(this.optionMarked(index) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.optionHasText(index) ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
          .lineHeight(18)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${this.optionVotePercentage(index)}%`)
          .fontSize(11.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.optionAccent(index))
          .visibility(this.isResultsVisible ? Visibility.Visible : Visibility.Hidden);
        if (!this.isResultsVisible && this.optionIsBeingChosen(index)) {
          LoadingProgress().width(15).height(15).color(COLOR_PRIMARY);
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 9, right: 9, top: 7, bottom: 7 });
    }
    .width('100%')
    .constraintSize({ minHeight: 40, maxHeight: 58 })
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
          .fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
        Blank();
        Text(this.statusText())
          .fontSize(10.5)
          .fontColor(this.isUnavailable || this.msg.pollIsClosed || this.isExpired
            ? '#9A6562' : COLOR_TEXT_SECONDARY);
      }.width('100%');

      Text(this.msg.pollQuestion.trim() !== '' ? this.msg.pollQuestion : $r('app.string.poll_unavailable'))
        .fontSize(15)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.msg.pollQuestion.trim() !== '' ? COLOR_TEXT_PRIMARY : '#B05D58')
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');

      if (this.msg.pollOptions.length >= 2) {
        Column({ space: 6 }) {
          this.optionSlot(0);
          this.optionSlot(1);
          if (this.msg.pollOptions.length > 2) { this.optionSlot(2); }
          if (this.msg.pollOptions.length > 3) { this.optionSlot(3); }
          if (this.msg.pollOptions.length > 4) { this.optionSlot(4); }
          if (this.msg.pollOptions.length > 5) { this.optionSlot(5); }
          if (this.msg.pollOptions.length > 6) { this.optionSlot(6); }
          if (this.msg.pollOptions.length > 7) { this.optionSlot(7); }
          if (this.msg.pollOptions.length > 8) { this.optionSlot(8); }
          if (this.msg.pollOptions.length > 9) { this.optionSlot(9); }
        }.width('100%');
      } else {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(17).fontColor(['#B05D58']);
          Text($r('app.string.poll_no_options'))
            .fontSize(12).fontColor('#B05D58');
        }
        .width('100%')
        .padding({ top: 9, bottom: 9, left: 10, right: 10 })
        .backgroundColor('#10D9514E')
        .borderRadius(9);
      }

      if (this.msg.pollAllowMultiple && this.isInteractive) {
        Row() {
          if (this.msg.pollVotePending) {
            LoadingProgress().width(16).height(16).color(Color.White);
          } else {
            Text(this.hasVoted ? $r('app.string.poll_update_vote') : $r('app.string.poll_submit_vote'))
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White);
          }
        }
        .width('100%').height(34)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.draftChanged ? COLOR_PRIMARY : '#A7AFB8')
        .borderRadius(9)
        .stateStyles({
          normal: pollSubmitNormalStyle,
          pressed: pollSubmitPressedStyle
        })
        .onClick((): void => { this.submitDraft(); });
      }

      if (this.msg.pollExplanation.trim() !== '' && this.isResultsVisible) {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(15).fontColor([COLOR_PRIMARY]);
          Text(this.msg.pollExplanation)
            .layoutWeight(1)
            .fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .padding({ top: 7, bottom: 7, left: 9, right: 9 })
        .backgroundColor('#0E3390EC')
        .borderRadius(9);
      }

      if (this.msg.pollVoteError.trim() !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(14).fontColor(['#D9514E']);
          Text(this.msg.pollVoteError)
            .layoutWeight(1)
            .fontSize(10.5).lineHeight(15).fontColor('#D9514E')
            .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ right: 62, bottom: 10 });
      } else {
        Row() {
          Text(this.voterText()).fontSize(10.5).fontColor(COLOR_TEXT_SECONDARY);
          Blank();
          if (this.isSubmitting) {
            Row({ space: 5 }) {
              LoadingProgress().width(13).height(13).color(COLOR_PRIMARY);
              Text($r('app.string.submitting')).fontSize(10.5).fontColor(COLOR_PRIMARY);
            }
          }
        }
        .width('100%')
        .padding({ right: 62, bottom: 10 });
      }
    }
    .width(Math.max(220, Math.min(278, this.maxWidth)))
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`${this.msg.pollQuestion}，${this.statusText()}，${this.voterText()}`);
  }
}
