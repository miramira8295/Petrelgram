import { UIContext } from '@kit.ArkUI';
import { MessageEntry } from '../../store/MessageEntry';
import { PollOptionInfo } from '../../util/formatMsgContent';
import { TdObject } from '../../tdkit/TdTypes';
import { PollRichSource } from '../../util/pollRichSource';
import { DrawnTextUnits } from '../../util/drawnTextUnits';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';
import { DrawnRichTextLayout, DrawnRichTextLayouts } from './DrawnRichTextLayout';
import { DrawnTextLineCache, drawnColor } from './DrawnTextLine';

export interface DrawnPollLayout {
  width: number;
  height: number;
  headerHeight: number;
  footerHeight: number;
  submitHeight: number;
  showSubmit: boolean;
  showExplanation: boolean;
  question: DrawnRichTextLayout;
  description: DrawnRichTextLayout | null;
  options: DrawnRichTextLayout[];
  optionHeights: number[];
  explanation: DrawnRichTextLayout | null;
  error: DrawnRichTextLayout | null;
  unavailable: DrawnRichTextLayout | null;
}

const pollLayouts: WeakMap<DrawnDocumentWidget, DrawnPollLayout> = new WeakMap<DrawnDocumentWidget, DrawnPollLayout>();
export function rememberPollLayout(widget: DrawnDocumentWidget, layout: DrawnPollLayout): void { pollLayouts.set(widget, layout); }
export function pollLayoutFor(widget: DrawnDocumentWidget): DrawnPollLayout | null { return pollLayouts.get(widget) ?? null; }
const EMPTY_POLL_LAYOUT_ENTITIES: TdObject[] = [];

class DrawnPollTextLayouts {
  private checkedText: string | null = null;
  private blank: boolean = true;
  private sources: PollRichSource = new PollRichSource();
  private layouts: DrawnRichTextLayouts = new DrawnRichTextLayouts();
  isBlank(content: string): boolean {
    if (this.checkedText !== content) {
      this.checkedText = content;
      this.blank = content.trim() === '';
    }
    return this.blank;
  }
  prepare(ui: UIContext, content: string, entities: TdObject[], width: number, font: number,
    color: ResourceColor, environment: string, bold: boolean = false, maxLines?: number): DrawnRichTextLayout {
    const source = this.sources.prepare(content, entities, bold);
    if (source === null) { throw new Error('unsupported poll text layout'); }
    return this.layouts.prepare(ui, { source, maxWidthVp: Math.max(1, width), minWidthVp: 0,
      fontSize: font, foreground: color, accent: COLOR_PRIMARY, environment, reserve: '', maxLines });
  }
}

// One linear options pass. Individual text engines retain paragraphs when only
// voters, chosen flags or equivalent entity arrays change.
export class DrawnPollLayouts {
  private units: DrawnTextUnits = new DrawnTextUnits();
  private header: DrawnTextLineCache = new DrawnTextLineCache();
  private footer: DrawnTextLineCache = new DrawnTextLineCache();
  private submit: DrawnTextLineCache = new DrawnTextLineCache();
  private question: DrawnPollTextLayouts = new DrawnPollTextLayouts();
  private description: DrawnPollTextLayouts = new DrawnPollTextLayouts();
  private explanation: DrawnPollTextLayouts = new DrawnPollTextLayouts();
  private error: DrawnPollTextLayouts = new DrawnPollTextLayouts();
  private unavailable: DrawnPollTextLayouts = new DrawnPollTextLayouts();
  private options: DrawnPollTextLayouts[] = [];
  private current: DrawnPollLayout | null = null;

  prepare(ui: UIContext, message: MessageEntry, width: number, environment: string, expired: boolean): DrawnPollLayout {
    const units = this.units.prepare(ui, environment), density = units.density;
    const questionText = message.pollQuestion ?? '';
    const descriptionText = message.pollDescription ?? '';
    const explanationText = message.pollExplanation ?? '';
    const errorText = message.pollVoteError ?? '';
    const options = message.pollOptions ?? [];
    const secondary = drawnColor(COLOR_TEXT_SECONDARY);
    const questionBlank = this.question.isBlank(questionText);
    const question = this.question.prepare(ui, questionBlank ? str('poll_unavailable') : questionText,
      message.pollQuestionEntities ?? EMPTY_POLL_LAYOUT_ENTITIES, width, 15,
      questionBlank ? '#B05D58' : COLOR_TEXT_PRIMARY, environment, true);
    const description = !this.description.isBlank(descriptionText) ? this.description.prepare(ui, descriptionText,
      message.pollDescriptionEntities ?? EMPTY_POLL_LAYOUT_ENTITIES, width, 13.5, COLOR_TEXT_SECONDARY, environment) : null;
    const optionPlans: DrawnRichTextLayout[] = [], optionHeights: number[] = [];
    let voted = false, pending = message.pollVotePending, optionHeight = 0, optionsChanged = false;
    for (let i = 0; i < options.length; i++) {
      const option: PollOptionInfo = options[i];
      if (option.isChosen) { voted = true; }
      if (option.isBeingChosen) { pending = true; }
      if (this.options[i] === undefined) { this.options[i] = new DrawnPollTextLayouts(); }
      const optionBlank = this.options[i].isBlank(option.text);
      const content = optionBlank ? str('poll_unnamed_option') : option.text;
      const plan = this.options[i].prepare(ui, content, option.entities ?? EMPTY_POLL_LAYOUT_ENTITIES,
        width - 94, 13.5, optionBlank ? COLOR_TEXT_SECONDARY : COLOR_TEXT_PRIMARY, environment);
      const height = Math.max(40, Math.max(20, plan.heightVp) + 14);
      optionPlans.push(plan); optionHeights.push(height); optionHeight += height;
      if (plan !== this.current?.options[i] || height !== this.current?.optionHeights[i]) { optionsChanged = true; }
    }
    if (this.options.length > options.length) { this.options.length = options.length; }
    const resultsVisible = voted || message.pollIsClosed || expired;
    const interactive = !questionBlank && optionPlans.length > 0 && !pending &&
      !message.pollIsClosed && !expired && !(message.pollIsQuiz && voted);
    const showSubmit = message.pollAllowMultiple && interactive;
    const showExplanation = !this.explanation.isBlank(explanationText) && resultsVisible;
    const explanation = showExplanation ? this.explanation.prepare(ui, explanationText,
      message.pollExplanationEntities ?? EMPTY_POLL_LAYOUT_ENTITIES, width - 40, 11.5, COLOR_TEXT_SECONDARY, environment) : null;
    const error = !this.error.isBlank(errorText) ? this.error.prepare(ui, errorText,
      EMPTY_POLL_LAYOUT_ENTITIES, width - 82, 10.5, '#D9514E', environment, false, 3) : null;
    const unavailable = optionPlans.length === 0 ? this.unavailable.prepare(ui, str('poll_no_options'),
      EMPTY_POLL_LAYOUT_ENTITIES, width - 44, 12, '#B05D58', environment) : null;
    const headerHeight = Math.max(16, this.header.prepare(message.pollIsQuiz ? '💡' : '📊', width * density,
      units.fp2px(16), secondary, environment).heightPx / density);
    const footerHeight = Math.max(13, this.footer.prepare(`0 ${str('submitting')}`, width * density,
      units.fp2px(10.5), secondary, environment).heightPx / density) + 10;
    const submitHeight = Math.max(34, this.submit.prepare(str('poll_submit_vote'), width * density,
      units.fp2px(13), secondary, environment).heightPx / density + 12);
    const previous = this.current;
    if (previous !== null && previous.width === width && previous.question === question && previous.description === description &&
      !optionsChanged && previous.options.length === optionPlans.length && previous.explanation === explanation &&
      previous.error === error && previous.unavailable === unavailable && previous.showSubmit === showSubmit &&
      previous.showExplanation === showExplanation && previous.headerHeight === headerHeight &&
      previous.footerHeight === footerHeight && previous.submitHeight === submitHeight) { return previous; }
    const blocks: number[] = [headerHeight, question.heightVp];
    if (description !== null) { blocks.push(description.heightVp + 6); }
    blocks.push(unavailable !== null ? Math.max(17, unavailable.heightVp) + 18 : optionHeight + Math.max(0, optionPlans.length - 1) * 6);
    if (showSubmit) { blocks.push(submitHeight); }
    if (explanation !== null) { blocks.push(Math.max(15, explanation.heightVp) + 14); }
    blocks.push(error !== null ? Math.max(14, error.heightVp) + 10 : footerHeight);
    let height = Math.max(0, blocks.length - 1) * 8;
    for (const block of blocks) { height += block; }
    if (!Number.isFinite(height) || height <= 0) { throw new Error('invalid poll prelayout height'); }
    this.current = { width, height, headerHeight, footerHeight, submitHeight, showSubmit, showExplanation,
      question, description, options: optionPlans, optionHeights, explanation, error, unavailable };
    return this.current;
  }
}
