import { PollRichSource } from '../../util/pollRichSource';
import { logW } from '../../util/log';
import { MessageEntry } from '../../store/MessageEntry';
import { TdObject } from '../../tdkit/TdTypes';
import { DrawnRichLink, DrawnRichSource } from '../../util/drawnRichTextPolicy';
import { DrawnRichTextLayouts, DrawnRichTextLayout } from './DrawnRichTextLayout';
import { DrawnRichTextView } from './DrawnRichTextView';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { COLOR_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';

// One source/paragraph cache per text block. No poll results in the layout key.
@ComponentV2
export struct DrawnPollText {
  @Require @Param msg: MessageEntry;
  @Param preparedLayout: DrawnRichTextLayout | null = null;
  @Param content: string = '';
  @Param entities: TdObject[] = [];
  @Param boxWidth: number = 200;
  @Param textSize: number = 13.5;
  @Param textColor: ResourceColor = COLOR_TEXT_SECONDARY;
  @Param bold: boolean = false;
  @Event onBeforeLink: () => boolean = (): boolean => true;
  @Event onLink: (url: string, hidesUrl: boolean) => void = (): void => {};
  @Local private revealed: boolean = false;
  @Local private metricRevision: number = 0;
  private sources: PollRichSource = new PollRichSource();
  private layouts: DrawnRichTextLayouts = new DrawnRichTextLayouts();
  private env = chatEnv;
  private failureLogged: boolean = false;
  @Computed private get source(): DrawnRichSource | null {
    try { return this.preparedLayout?.source ?? this.sources.prepare(this.content, this.entities, this.bold); }
    catch (error) { this.reportFailure(error as Error); return null; }
  }
  @Computed private get ownerIdentity(): number { return this.msg.rowId; }
  @Monitor('source', 'ownerIdentity') private resetContent(): void { this.revealed = false; }
  private reportFailure(error: Error): void {
    if (!this.failureLogged) { this.failureLogged = true; logW(`DrawnPollText: ${error.message}`); }
  }
  @Computed private get plan(): DrawnRichTextLayout | null {
    if (this.preparedLayout && !this.revealed && this.metricRevision === 0) { return this.preparedLayout; }
    try {
      const source = this.source;
      if (source === null || !(this.boxWidth > 0)) { return null; }
      return this.layouts.prepare(this.getUIContext(), { source, maxWidthVp: this.boxWidth, minWidthVp: 0,
        fontSize: this.textSize, reserve: '', foreground: this.textColor, accent: COLOR_PRIMARY,
        spoilersRevealed: this.revealed, mathRevision: this.metricRevision,
        environment: `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}` });
    } catch (error) {
      this.reportFailure(error as Error);
      return null;
    }
  }
  private activate(link: DrawnRichLink): void {
    if (!this.onBeforeLink()) { return; }
    if (link.action === 'spoiler') { this.revealed = true; }
    else if (link.url !== '') { this.onLink(link.url, link.hidesUrl); }
  }
  build() {
    if (this.plan !== null) {
      DrawnRichTextView({ msg: this.msg, plan: this.plan,
        onMetricsChanged: (): void => { this.metricRevision++; },
        onLinkTap: (link: DrawnRichLink): void => this.activate(link) });
    } else {
      Text(this.content).fontSize(this.textSize).fontColor(this.textColor).fontWeight(this.bold ? FontWeight.Bold : FontWeight.Regular).width(this.boxWidth);
    }
  }
}
