import { PollOptionInfo } from '../../util/formatMsgContent';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { plural, str } from '../../util/strings';
import { reuseParam } from '../../util/reuseParams';

@Component
export struct PollBubble {
  @Prop messageId: number = 0;
  @Prop question: string = '';
  @Prop options: PollOptionInfo[] = [];
  @Prop totalVoterCount: number = 0;
  @Prop isAnonymous: boolean = true;
  @Prop isQuiz: boolean = false;
  @Prop allowMultiple: boolean = false;
  @Prop correctOptionId: number = -1;
  @Prop explanation: string = '';
  @Prop closeDate: number = 0;
  @Prop isClosed: boolean = false;
  @Prop pending: boolean = false;
  @Prop errorText: string = '';
  @Prop nowSec: number = 0;
  @Prop @Watch('onRevisionChanged') revision: string = '';
  @Prop maxWidth: number = 260;
  onVote: (messageId: number, optionIds: number[]) => void =
    (_messageId: number, _optionIds: number[]): void => {};

  @State draftIds: number[] = [];
  @State draftChanged: boolean = false;

  aboutToAppear(): void {
    this.resetDraft();
  }

  aboutToRecycle(): void {
    this.draftIds = [];
    this.draftChanged = false;
  }

  aboutToReuse(params: Record<string, Object>): void {
    // reuseParam：params 是 {} 还是 undefined 都安全，取不到就落到下面的
    // setTimeout 兜底（P3 批 2 第 1 项，见 util/reuseParams.ets）。
    const options: PollOptionInfo[] | undefined =
      reuseParam(params, 'options') as PollOptionInfo[] | undefined;
    if (options !== undefined) {
      this.draftIds = this.chosenIdsFrom(options);
      this.draftChanged = false;
      return;
    }
    setTimeout((): void => { this.resetDraft(); }, 0);
  }

  private onRevisionChanged(): void {
    if (!this.submitting()) {
      this.resetDraft();
    }
  }

  @Styles
  private optionNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private optionPressedStyle(): void {
    .scale({ x: 0.985, y: 0.985 })
    .opacity(0.76)
  }

  @Styles
  private submitNormalStyle(): void {
    .scale({ x: 1, y: 1 })
    .opacity(1)
  }

  @Styles
  private submitPressedStyle(): void {
    .scale({ x: 0.97, y: 0.97 })
    .opacity(0.72)
  }

  private chosenIds(): number[] {
    return this.chosenIdsFrom(this.options);
  }

  private chosenIdsFrom(options: PollOptionInfo[]): number[] {
    const ids: number[] = [];
    options.forEach((option: PollOptionInfo, index: number): void => {
      if (option.isChosen) {
        ids.push(index);
      }
    });
    return ids;
  }

  private resetDraft(): void {
    this.draftIds = this.chosenIds();
    this.draftChanged = false;
  }

  private expired(): boolean {
    return this.closeDate > 0 && this.nowSec >= this.closeDate;
  }

  private hasVoted(): boolean {
    return this.options.some((option: PollOptionInfo): boolean => option.isChosen);
  }

  private unavailable(): boolean {
    return this.question.trim() === '' || this.options.length < 2;
  }

  private interactive(): boolean {
    if (this.unavailable() || this.submitting() || this.isClosed || this.expired()) {
      return false;
    }
    return !(this.isQuiz && this.hasVoted());
  }

  private submitting(): boolean {
    return this.pending || this.options.some(
      (option: PollOptionInfo): boolean => option.isBeingChosen
    );
  }

  private resultsVisible(): boolean {
    return this.hasVoted() || this.isClosed || this.expired();
  }

  private selected(index: number): boolean {
    if (this.draftChanged) {
      return this.draftIds.indexOf(index) >= 0;
    }
    // MessageStore marks the submitted target set with isBeingChosen while
    // TDLib is processing the request. Message rows are keyed by that mutable
    // state and may be rebuilt, so the pending flag must itself render as the
    // active selection instead of relying only on this component's local draft.
    if (this.submitting()) {
      return this.options[index]?.isBeingChosen ?? false;
    }
    return this.options[index]?.isChosen ?? false;
  }

  private toggleOption(index: number): void {
    if (!this.interactive()) {
      return;
    }
    if (!this.allowMultiple) {
      const wasChosen = this.options[index].isChosen;
      const next = wasChosen && !this.isQuiz ? [] : [index];
      // Give a single-choice poll immediate visual feedback. The authoritative
      // update still comes from TDLib; on failure the revision watcher resets
      // this draft to the server-backed option state.
      this.draftIds = next;
      this.draftChanged = true;
      this.onVote(this.messageId, next);
      return;
    }
    const base = this.draftChanged ? this.draftIds.slice() : this.chosenIds();
    const at = base.indexOf(index);
    if (at >= 0) {
      base.splice(at, 1);
    } else {
      base.push(index);
    }
    this.draftIds = base;
    this.draftChanged = true;
  }

  private submitDraft(): void {
    if (this.interactive() && this.allowMultiple && this.draftChanged) {
      this.onVote(this.messageId, this.draftIds.slice());
    }
  }

  private optionAccent(index: number): string {
    if (!this.resultsVisible()) {
      return this.selected(index) ? '#3390EC' : '#99A2AC';
    }
    if (this.isQuiz && this.correctOptionId === index) {
      return '#32A765';
    }
    if (this.isQuiz && this.options[index].isChosen && this.correctOptionId !== index) {
      return '#D9514E';
    }
    return this.options[index].isChosen ? '#3390EC' : '#86919D';
  }

  private optionFill(index: number): string {
    const accent = this.optionAccent(index);
    if (accent === '#32A765') {
      return '#2032A765';
    }
    if (accent === '#D9514E') {
      return '#20D9514E';
    }
    return this.selected(index) ? '#183390EC' : '#0D000000';
  }

  private statusText(): string {
    if (this.unavailable()) {
      return str('poll_unavailable');
    }
    const type = this.isQuiz ? str('poll_quiz_word') :
      (this.isAnonymous ? str('poll_anonymous') : str('poll_public'));
    if (this.isClosed || this.expired()) {
      return str('poll_type_closed', type);
    }
    if (this.closeDate > 0) {
      const remaining = Math.max(0, this.closeDate - this.nowSec);
      if (remaining < 3600) {
        return str('poll_type_closes_in', type, Math.max(1, Math.ceil(remaining / 60)));
      }
    }
    return type;
  }

  private voterText(): string {
    return plural('poll_voters', Math.max(0, this.totalVoterCount), Math.max(0, this.totalVoterCount));
  }

  @Builder
  private optionRow(option: PollOptionInfo, index: number) {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.resultsVisible() && option.votePercentage > 0) {
        Row()
          .width(`${option.votePercentage}%`)
          .height(3)
          .backgroundColor(this.optionAccent(index))
          .borderRadius(1.5)
          .opacity(0.5)
          .animation({ duration: 180, curve: Curve.EaseOut });
      }
      Row({ space: 8 }) {
        Stack() {
          Circle({ width: 20, height: 20 })
            .fill(this.selected(index) ? this.optionAccent(index) : Color.Transparent)
            .stroke(this.optionAccent(index))
            .strokeWidth(1.5);
          if (this.selected(index)) {
            SymbolGlyph($r(this.isQuiz && this.resultsVisible() &&
              this.correctOptionId !== index ? 'sys.symbol.xmark' : 'sys.symbol.checkmark'))
              .fontSize(11).fontColor([Color.White]);
          }
        }.width(20).height(20);
        Text(option.text.trim() !== '' ? option.text : $r('app.string.poll_unnamed_option'))
          .layoutWeight(1)
          .fontSize(13.5)
          .fontWeight(this.selected(index) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(option.text.trim() !== '' ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY)
          .lineHeight(18)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        if (this.resultsVisible()) {
          Text(`${option.votePercentage}%`)
            .fontSize(11.5).fontWeight(FontWeight.Medium)
            .fontColor(this.optionAccent(index));
        } else if (option.isBeingChosen) {
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
    .border({ width: 1, color: this.selected(index) ? this.optionAccent(index) : '#16000000' })
    .borderRadius(10)
    .clip(true)
    .stateStyles({
      normal: this.optionNormalStyle,
      pressed: this.optionPressedStyle
    })
    .animation({ duration: 110, curve: Curve.EaseOut })
    .opacity(this.interactive() ? 1 : 0.9)
    .accessibilityText(`${option.text}，${option.votePercentage}%`)
    .onClick((): void => { this.toggleOption(index); });
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 7 }) {
        Text(this.isQuiz ? '💡' : '📊').fontSize(16);
        Text(this.isQuiz ? $r('app.string.poll_quiz_word') : $r('app.string.poll_word'))
          .fontSize(11.5).fontWeight(FontWeight.Medium).fontColor(COLOR_PRIMARY);
        Blank();
        Text(this.statusText())
          .fontSize(10.5)
          .fontColor(this.unavailable() || this.isClosed || this.expired()
            ? '#9A6562' : COLOR_TEXT_SECONDARY);
      }.width('100%');

      Text(this.question.trim() !== '' ? this.question : $r('app.string.poll_unavailable'))
        .fontSize(15)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.question.trim() !== '' ? COLOR_TEXT_PRIMARY : '#B05D58')
        .maxLines(6)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');

      if (this.options.length >= 2) {
        Column({ space: 6 }) {
          ForEach(this.options, (option: PollOptionInfo, index: number) => {
            this.optionRow(option, index);
          }, (option: PollOptionInfo, index: number) =>
            `poll_option_${index}_${option.text}_${option.votePercentage}` +
              `_${option.isChosen}_${option.isBeingChosen}`);
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

      if (this.allowMultiple && this.interactive()) {
        Row() {
          if (this.pending) {
            LoadingProgress().width(16).height(16).color(Color.White);
          } else {
            Text(this.hasVoted() ? $r('app.string.poll_update_vote') : $r('app.string.poll_submit_vote'))
              .fontSize(13).fontWeight(FontWeight.Medium).fontColor(Color.White);
          }
        }
        .width('100%').height(34)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.draftChanged ? COLOR_PRIMARY : '#A7AFB8')
        .borderRadius(9)
        .stateStyles({
          normal: this.submitNormalStyle,
          pressed: this.submitPressedStyle
        })
        .animation({ duration: 110, curve: Curve.EaseOut })
        .onClick((): void => { this.submitDraft(); });
      }

      if (this.explanation.trim() !== '' && this.resultsVisible()) {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(15).fontColor([COLOR_PRIMARY]);
          Text(this.explanation)
            .layoutWeight(1)
            .fontSize(11.5).lineHeight(16).fontColor(COLOR_TEXT_SECONDARY)
            .maxLines(5).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .width('100%')
        .padding({ top: 7, bottom: 7, left: 9, right: 9 })
        .backgroundColor('#0E3390EC')
        .borderRadius(9);
      }

      if (this.errorText.trim() !== '') {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(14).fontColor(['#D9514E']);
          Text(this.errorText)
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
          if (this.submitting()) {
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
    .accessibilityText(`${this.question}，${this.statusText()}，${this.voterText()}`);
  }
}
