import { DrawnRichSource, DrawnRichLink } from '../../util/drawnRichTextPolicy';
import { MessageEntry } from '../../store/MessageEntry';
import { DrawnRichTextLayout, DrawnRichTextLayouts } from './DrawnRichTextLayout';
import { DrawnRichTextView } from './DrawnRichTextView';
import { chatEnv } from '../../util/chatEnvMirror';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY } from '../../util/theme';

@ComponentV2
export struct DrawnDocumentNote {
  @Param source: DrawnRichSource | null = null;
  @Require @Param msg: MessageEntry;
  @Param maxWidthVp: number = 300;
  @Event onLinkTap: (link: DrawnRichLink) => void = (_link: DrawnRichLink): void => {};
  @Local private mathRevision: number = 0;
  private layouts: DrawnRichTextLayouts = new DrawnRichTextLayouts();
  private env = chatEnv;
  @Computed private get plan(): DrawnRichTextLayout | null {
    if (this.source === null) { return null; }
    return this.layouts.prepare(this.getUIContext(), { source: this.source, mathRevision: this.mathRevision, maxWidthVp: this.maxWidthVp,
      minWidthVp: 0, fontSize: this.env.msgTextSize, reserve: '', foreground: COLOR_TEXT_PRIMARY,
      accent: COLOR_PRIMARY, environment: `${this.env.appearanceEpoch}:${this.env.langEpoch}` });
  }
  build() {
    Scroll() {
      Column() {
        DrawnRichTextView({ msg: this.msg, plan: this.plan, onMetricsChanged: (): void => { this.mathRevision++; }, onLinkTap: this.onLinkTap });
      }.padding(16).width('100%');
    }.width('100%').height('100%');
  }
}
