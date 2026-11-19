import { DrawnMediaTexts, DrawnMediaTextPlan, DrawnMediaTextPainter } from './DrawnMediaText';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

// Static alternatives for native animated media: one centered paragraph pair,
// cached independently from download/playback. Localized text remains complete;
// unusually large text fits the reserved box rather than losing trailing lines.
@ComponentV2
export struct DrawnMediaPlaceholder {
  @Param primary: string = '';
  @Param secondary: string = '';
  @Param primaryKey: string = '';
  @Param secondaryKey: string = '';
  @Param primarySize: number = 24;
  @Param secondarySize: number = 12;
  @Param primaryColor: ResourceColor = COLOR_TEXT_SECONDARY;
  @Param secondaryColor: ResourceColor = COLOR_TEXT_SECONDARY;
  @Param boxWidth: number = 160;
  @Param boxHeight: number = 160;
  @Param gap: number = 6;
  @Param tone: ResourceColor = '#00000000';
  @Param cornerRadius: number = 0;
  private env = chatEnv;
  private layouts: DrawnMediaTexts = new DrawnMediaTexts();
  private painter: DrawnMediaTextPainter = new DrawnMediaTextPainter();
  @Computed private get environment(): string { return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`; }
  @Computed private get plan(): DrawnMediaTextPlan {
    return this.layouts.prepare(this.getUIContext(), this.environment, Math.max(1, this.boxWidth),
      this.primaryKey ? str(this.primaryKey) : this.primary, this.primarySize, this.primaryColor,
      this.secondaryKey ? str(this.secondaryKey) : this.secondary, this.secondarySize, this.secondaryColor,
      0, false, this.gap, Math.max(1, this.boxHeight), false, true, 0);
  }
  build() {
    Row().width(this.boxWidth).height(this.boxHeight).clip(true)
      .backgroundColor(this.tone).borderRadius(this.cornerRadius)
      .drawModifier(this.painter.bind(this.plan, this.boxHeight))
      .accessibilityText(`${this.primaryKey ? str(this.primaryKey) : this.primary} ${this.secondaryKey ? str(this.secondaryKey) : this.secondary}`);
  }
}
