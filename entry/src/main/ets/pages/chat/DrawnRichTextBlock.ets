import { MessageEntry } from '../../store/MessageEntry';
import { DrawnRichLink, drawnRichSegmentSource } from '../../util/drawnRichTextPolicy';
import { RichSegment } from '../../util/richText';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { bubbleTextFor, COLOR_PRIMARY } from '../../util/theme';
import { logW } from '../../util/log';
import { drawnTextUsesRtlLayout } from './DrawnPlainTextLayout';
import { DrawnRichTextLayout, DrawnRichTextLayouts } from './DrawnRichTextLayout';
import { DrawnRichTextView } from './DrawnRichTextView';

// A text block owns its paragraph cache. A quote/code/emoji elsewhere in the
// same message no longer forces these ordinary runs back to native Span nodes.
@ComponentV2
export struct DrawnRichTextBlock {
  @Require @Param msg: MessageEntry;
  @Require @Param segment: RichSegment;
  @Require @Param maxWidthVp: number;
  @Param outgoing: boolean = false;
  @Param reserve: string = '';
  @BuilderParam fallback: () => void;
  @Event onLinkTap: (link: DrawnRichLink) => void = (_link: DrawnRichLink): void => {};
  private env = chatEnv;
  private layouts: DrawnRichTextLayouts | null = null;
  private failureLogged: boolean = false;

  @Computed
  private get plan(): DrawnRichTextLayout | null {
    if (this.env.drawnEnabled === false || this.env.drawnRich === false || this.env.bubbleMaterialOn) { return null; }
    const environment: string = `${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
    if (drawnTextUsesRtlLayout(environment)) { return null; }
    const source = drawnRichSegmentSource(this.segment);
    if (source === null) { return null; }
    try {
      if (this.layouts === null) { this.layouts = new DrawnRichTextLayouts(); }
      return this.layouts.prepare(this.getUIContext(), { source, maxWidthVp: this.maxWidthVp,
        minWidthVp: 0, fontSize: this.env.msgTextSize, reserve: this.reserve,
        foreground: bubbleTextFor(this.outgoing), accent: COLOR_PRIMARY,
        environment: `${this.env.appearanceEpoch}:${environment}` });
    } catch (error) {
      if (!this.failureLogged) {
        this.failureLogged = true;
        logW(`DrawnRichTextBlock: layout unavailable, using native text: ${(error as Error)?.message ?? String(error)}`);
      }
      return null;
    }
  }

  build() {
    if (this.plan !== null) {
      DrawnRichTextView({ plan: this.plan, msg: this.msg,
        onLinkTap: (link: DrawnRichLink): void => { this.onLinkTap(link); } });
    } else {
      this.fallback();
    }
  }
}
