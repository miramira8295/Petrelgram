import { ChecklistActionState, IDLE_CHECKLIST_ACTION, checklistActionState, subscribeChecklistAction } from '../../util/checklistStateChannel';
import { getTdClient, isReady } from '../../tdkit/Globals';
import { ChecklistTask } from '../../util/checklistModel';
import { DrawnDocumentWidget } from '../../util/drawnDocumentWidget';
import { MessageEntry } from '../../store/MessageEntry';
import { MessageBubbleActions } from './ReusableMessageBubble';
import { DrawnChecklistLayout, DrawnChecklistTaskLayout, checklistLayoutFor } from './DrawnChecklistLayout';
import { DrawnChecklistDecoration } from './DrawnChecklistDecoration';
import { DrawnPollText } from './DrawnPollText';
import { DrawnLoadingSpinner } from './DrawnLoadingSpinner';
import { DrawnCardBar } from './DrawnCardBar';
import { chatEnv } from '../../util/chatEnvMirror';
import { textMeasureEnvironment } from '../../util/textMeasureCache';
import { COLOR_PRIMARY, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY } from '../../util/theme';
import { str } from '../../util/strings';

const EMPTY_CHECKLIST_PENDING: ReadonlySet<number> = new Set<number>();

@ComponentV2
struct DrawnChecklistTaskRow {
  @Require @Param msg: MessageEntry;
  @Require @Param layout: DrawnChecklistTaskLayout;
  @Param task: ChecklistTask | undefined = undefined;
  @Param allowed: boolean = false;
  @Param interactive: boolean = false;
  @Param pending: boolean = false;
  @Event onClaim: () => boolean = (): boolean => false;
  @Event onToggle: (taskId: number, completed: boolean) => void = (): void => {};
  @Event onLink: (url: string, hidesUrl: boolean) => void = (): void => {};
  private env = chatEnv;
  private decoration: DrawnChecklistDecoration = new DrawnChecklistDecoration();
  @Computed private get environment(): string {
    return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  private toggleCallback(): () => void {
    const task = this.task, id = this.msg.id, rowId = this.msg.rowId;
    return (): void => {
      if (task === undefined || task !== this.task || id !== this.msg.id || rowId !== this.msg.rowId ||
        !this.allowed || this.pending || !this.onClaim()) { return; }
      this.onToggle(task.id, !task.completed);
    };
  }
  private accessibilityLabel(): string {
    const task = this.task;
    if (task === undefined) { return ''; }
    return `${task.text}，${str(task.completed ? 'checklist_task_done' : 'checklist_task_open')}，` +
      str(this.pending ? 'submitting' : task.completed ? 'checklist_task_mark_open' : 'checklist_task_mark_done');
  }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.task !== undefined) {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.pending && this.layout.checkboxSize > 0) {
            DrawnLoadingSpinner({ ringSize: this.layout.checkboxSize, ringColor: COLOR_PRIMARY })
              .position({ x: (this.layout.checkboxHitWidth - this.layout.checkboxSize) / 2, y: this.layout.checkboxY });
          }
        }
        .width(this.layout.checkboxHitWidth).height(this.layout.height)

        .enabled(this.allowed && !this.pending).focusable(this.allowed && !this.pending)
        .accessibilityLevel('yes').accessibilityRole(AccessibilityRoleType.BUTTON)
        .accessibilityText(this.accessibilityLabel())
        .onClick(this.toggleCallback());
        // A separate text surface owns links/emoji/spoilers. It has no parent
        // row toggle, so opening a link can never also complete the task.
        DrawnPollText({ msg: this.msg, preparedLayout: this.layout.label, content: this.task.text,
          entities: this.task.entities, boxWidth: this.layout.label.widthVp, textSize: 16,
          textColor: COLOR_TEXT_PRIMARY, onBeforeLink: (): boolean => this.onClaim(),
          onLink: (url: string, hidesUrl: boolean): void => this.onLink(url, hidesUrl) })
          .opacity(this.task.completed ? .65 : 1)
          .position({ x: this.layout.textX, y: this.layout.textY });
      }
    }.width(this.layout.width).height(this.layout.height)
      .drawModifier(this.decoration.bind(this.getUIContext(), this.environment, this.layout.checkboxHitWidth,
        this.layout.checkboxSize, this.layout.checkboxY, this.task?.completed ?? false, this.pending,
        this.allowed, this.interactive, this.layout.width, this.layout.height));
  }
}

@ComponentV2
export struct DrawnChecklistMessage {
  @Require @Param msg: MessageEntry;
  @Require @Param actions: MessageBubbleActions;
  @Require @Param widget: DrawnDocumentWidget;
  @Param chatId: number = 0;
  @Param boxWidth: number = 262;
  @Param pendingTaskIds: ReadonlySet<number> = EMPTY_CHECKLIST_PENDING;
  @Param error: string = '';
  @Local private actionState: ChecklistActionState = IDLE_CHECKLIST_ACTION;
  private off: (() => void) | null = null;
  private generation: number = 0;
  private active: boolean = false;
  private detach(): void { this.generation++; this.off?.(); this.off = null; }
  private bind(): void {
    this.detach();
    if (!isReady()) { this.actionState = IDLE_CHECKLIST_ACTION; return; }
    const client = getTdClient(), chatId = this.chatId, messageId = this.msg.id;
    const state = checklistActionState(client, chatId, messageId);
    if (this.actionState !== state) { this.actionState = state; }
    if (!this.active) { return; }
    const generation = this.generation;
    this.off = subscribeChecklistAction(client, chatId, messageId, (next: ChecklistActionState): void => {
      if (generation === this.generation && this.active && client === getTdClient() &&
        chatId === this.chatId && messageId === this.msg.id && this.actionState !== next) { this.actionState = next; }
    });
  }
  @Monitor('msg', 'chatId', 'actions') private sourceChanged(): void { this.bind(); }
  aboutToAppear(): void { this.active = true; this.bind(); }
  aboutToReuse(): void { this.active = true; this.bind(); }
  aboutToRecycle(): void { this.active = false; this.detach(); }
  aboutToDisappear(): void { this.aboutToRecycle(); }
  private pending(id: number): boolean { return this.pendingTaskIds.has(id) || this.actionState.pendingTaskIds.has(id); }
  private allowed(): boolean {
    return this.active && this.msg.checklist?.canMarkTasksAsDone === true &&
      this.pendingTaskIds.size === 0 && this.actionState.pendingTaskIds.size === 0;
  }
  @Event onClaim: () => boolean = (): boolean => false;
  private env = chatEnv;
  private subtitle: DrawnCardBar = new DrawnCardBar();
  private footer: DrawnCardBar = new DrawnCardBar();
  @Computed private get environment(): string {
    return `${this.env.appearanceEpoch}:${this.env.langEpoch}:${textMeasureEnvironment.epoch}`;
  }
  @Computed private get layout(): DrawnChecklistLayout | null { return checklistLayoutFor(this.widget); }
  private footerLabel(): string {
    const error = this.error !== '' ? this.error : this.actionState.error;
    if (error !== '') { return error; }
    const model = this.msg.checklist;
    const done = `${model?.completedCount ?? 0}`, total = `${model?.tasks.length ?? 0}`;
    return !this.msg.isOutgoing && this.chatId > 0 && model?.othersCanMarkTasksAsDone === false && this.msg.senderName !== ''
      ? str('checklist_progress_by', done, total, this.msg.senderName)
      : str('checklist_progress', done, total);
  }
  build() {
    if (this.layout !== null) {
      Column() {
        DrawnPollText({ msg: this.msg, preparedLayout: this.layout.title, content: this.msg.checklist?.title.text ?? '',
          entities: this.msg.checklist?.title.entities ?? [], boxWidth: this.layout.width, textSize: 16,
          textColor: COLOR_TEXT_PRIMARY, bold: true, onBeforeLink: (): boolean => this.active && this.onClaim(),
          onLink: (url: string, hidesUrl: boolean): void => this.actions.onLinkTap(url, hidesUrl) })
          .margin({ bottom: 4 });
        Row().width(this.layout.width).height(this.layout.subtitleHeight)
          .drawModifier(this.subtitle.bind(this.getUIContext(), {
            width: this.layout.width, height: this.layout.subtitleHeight, environment: this.environment,
            leftPrepared: this.layout.subtitle, paddingBottom: 12
          })).accessibilityText(str('checklist_type'));
        ForEach(this.layout.rows, (row: DrawnChecklistTaskLayout) => {
          DrawnChecklistTaskRow({ msg: this.msg, layout: row, task: this.msg.checklist?.taskById.get(row.id),
            interactive: this.msg.checklist?.canMarkTasksAsDone === true,
            allowed: this.allowed(), pending: this.pending(row.id),
            onClaim: (): boolean => this.active && this.onClaim(),
            onToggle: (id: number, completed: boolean): void => this.actions.onChecklistToggle(this.msg.id, id, completed),
            onLink: (url: string, hidesUrl: boolean): void => this.actions.onLinkTap(url, hidesUrl) });
        }, (row: DrawnChecklistTaskLayout): string => `${row.id}`);
        Row().width(this.layout.width).height(this.layout.footerHeight)
          .drawModifier(this.footer.bind(this.getUIContext(), {
            width: this.layout.width, height: this.layout.footerHeight, environment: this.environment,
            center: this.footerLabel(), centerFont: 11, centerColor: this.error !== '' || this.actionState.error !== '' ? '#D9514E' : COLOR_TEXT_SECONDARY,
            paddingBottom: 4
          })).accessibilityText(this.footerLabel());
      }.width(this.layout.width).height(this.layout.height).alignItems(HorizontalAlign.Start);
    }
  }
}
