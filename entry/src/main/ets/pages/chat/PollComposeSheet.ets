import {
  COLOR_PRIMARY, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_ICON_SECONDARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';

const MAX_OPTIONS: number = 10;

// 投票编辑器（底部面板）：问题 + 2~10 个选项 + 匿名/测验开关。
// 测验模式必须点选一个正确答案。
@Component
export struct PollComposeSheet {
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  onSubmit: (question: string, options: string[], isAnonymous: boolean,
    isQuiz: boolean, correctOptionId: number) => void =
    (): void => {};
  onClose: () => void = (): void => {};
  @State question: string = '';
  @State options: string[] = ['', ''];
  @State isAnonymous: boolean = true;
  @State isQuiz: boolean = false;
  @State correctIdx: number = -1;
  @State errorText: string = '';

  private validOptions(): string[] {
    return this.options.map((o: string): string => o.trim())
      .filter((o: string): boolean => o !== '');
  }

  private submit(): void {
    const question: string = this.question.trim();
    const options: string[] = this.validOptions();
    if (question === '') {
      this.errorText = str('poll_need_question');
      return;
    }
    if (options.length < 2) {
      this.errorText = str('poll_need_two');
      return;
    }
    if (this.isQuiz) {
      const correctText: string = this.correctIdx >= 0 && this.correctIdx < this.options.length
        ? this.options[this.correctIdx].trim() : '';
      if (correctText === '') {
        this.errorText = str('poll_need_answer');
        return;
      }
      this.onSubmit(question, options, this.isAnonymous, true, options.indexOf(correctText));
      return;
    }
    this.onSubmit(question, options, this.isAnonymous, false, 0);
  }

  @Builder
  optionRow(index: number) {
    Row({ space: 8 }) {
      if (this.isQuiz) {
        Row() {
          if (this.correctIdx === index) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(20).fontColor([COLOR_PRIMARY]);
          } else {
            Row().width(18).height(18).borderRadius(9)
              .border({ width: 1.5, color: '#8E8E93' });
          }
        }
        .width(28).justifyContent(FlexAlign.Center)
        .onClick((): void => {
          this.correctIdx = index;
        });
      }
      TextInput({ placeholder: str('poll_option_n', index + 1), text: this.options[index] })
        .fontSize(15).layoutWeight(1).height(40)
        .onChange((value: string): void => {
          const next = [...this.options];
          next[index] = value;
          this.options = next;
        });
      if (this.options.length > 2) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([COLOR_ICON_SECONDARY])
          .onClick((): void => {
            this.options = this.options.filter((_: string, i: number): boolean => i !== index);
            if (this.correctIdx === index) {
              this.correctIdx = -1;
            } else if (this.correctIdx > index) {
              this.correctIdx--;
            }
          });
      }
    }
    .width('100%');
  }

  @Builder
  toggleRow(label: string, value: boolean, onChange: (next: boolean) => void) {
    Row() {
      Text(label).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: value }).selectedColor(COLOR_PRIMARY)
        .onChange(onChange);
    }
    .width('100%').height(44);
  }

  build() {
    Column() {
      Column().layoutWeight(1).onClick((): void => this.onClose());
      Column({ space: 10 }) {
        Row().width(40).height(4).borderRadius(2).backgroundColor('#D0D0D0');
        Text($r('app.string.poll_new')).fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
        TextInput({ placeholder: $r('app.string.poll_question'), text: this.question })
          .fontSize(15).height(44)
          .onChange((value: string): void => {
            this.question = value;
          });
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.options, (_: string, index: number) => {
              this.optionRow(index);
            }, (_: string, index: number): string => `poll_option_${index}`);
            if (this.options.length < MAX_OPTIONS) {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.plus')).fontSize(16).fontColor([COLOR_PRIMARY]);
                Text($r('app.string.poll_add_option')).fontSize(14).fontColor(COLOR_PRIMARY);
              }
              .onClick((): void => {
                this.options = [...this.options, ''];
              });
            }
          }
          .width('100%');
        }
        .constraintSize({ maxHeight: 240 }).align(Alignment.Top);
        this.toggleRow(str('poll_anonymous'), this.isAnonymous,
          (next: boolean): void => {
            this.isAnonymous = next;
          });
        this.toggleRow(str('poll_quiz'), this.isQuiz,
          (next: boolean): void => {
            this.isQuiz = next;
            if (!next) {
              this.correctIdx = -1;
            }
          });
        if (this.errorText !== '') {
          Text(this.errorText).fontSize(13).fontColor('#E5484D').width('100%');
        }
        Row({ space: 12 }) {
          Button($r('app.string.cancel')).buttonStyle(ButtonStyleMode.NORMAL).layoutWeight(1)
            .onClick((): void => this.onClose());
          Button($r('app.string.send')).backgroundColor(COLOR_PRIMARY).layoutWeight(1)
            .onClick((): void => this.submit());
        }
        .width('100%');
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 24 })
      .backgroundColor(COLOR_SURFACE)
      .borderRadius({ topLeft: 16, topRight: 16 });
    }
    .width('100%').height('100%')
    .backgroundColor('#66000000');
  }
}
