import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { ChecklistModel } from './checklistModel';
import { ChecklistActionState, checklistActionState, IDLE_CHECKLIST_ACTION, publishChecklistAction } from './checklistStateChannel';
import { markChecklistRequest } from './checklistRequest';
import { str } from './strings';

// One request per message; current entry and permissions are checked immediately
// before mutation. Server content updates remain the source of completion state.
export class ChecklistOperations {
  private client: TdClient;
  private chatId: number;
  private read: (id: number) => ChecklistModel | null;
  private refresh: (id: number) => Promise<void>;
  private isCurrent: () => boolean;
  private pending: Map<number, Promise<void>> = new Map();
  private pendingStates: Map<number, ChecklistActionState> = new Map();
  private epoch: number = 0;
  private closed: boolean = false;
  constructor(client: TdClient, chatId: number, read: (id: number) => ChecklistModel | null,
    refresh: (id: number) => Promise<void>, isCurrent: () => boolean) {
    this.client = client; this.chatId = chatId; this.read = read; this.refresh = refresh; this.isCurrent = isCurrent;
  }
  toggle(messageId: number, taskId: number, done: boolean): Promise<void> {
    const previous = this.pending.get(messageId);
    if (previous !== undefined) { return previous; }
    if (this.closed || !this.isCurrent()) { return Promise.resolve(); }
    const model = this.read(messageId), task = model?.taskById.get(taskId);
    if (model === null || task === undefined) { return Promise.reject(new TdError(400, str('checklist_task_missing'))); }
    if ((task.completionDate > 0) === done) { return Promise.resolve(); }
    const epoch = this.epoch;
    const state: ChecklistActionState = { pendingTaskIds: new Set<number>([taskId]), error: '' };
    const work: Promise<void> = Promise.resolve().then(async (): Promise<void> => {
      if (!this.accepts(epoch)) { return; }
      const properties: TdRequest = { '@type': 'getMessageProperties' };
      properties['chat_id'] = this.chatId; properties['message_id'] = messageId;
      const result = await this.client.send(properties);
      if (!this.accepts(epoch)) { return; }
      if (result['can_mark_tasks_as_done'] !== true) { throw new TdError(403, str('checklist_readonly')); }
      const current = this.read(messageId)?.taskById.get(taskId);
      if (current === undefined) { throw new TdError(400, str('checklist_task_missing')); }
      if ((current.completionDate > 0) === done) { return; }
      await this.client.send(markChecklistRequest(this.chatId, messageId, taskId, done));
      if (this.accepts(epoch)) { await this.refresh(messageId); }
    }).then((): void => {
      this.releaseState(messageId, state, IDLE_CHECKLIST_ACTION);
    }, (error: Error): void => {
      this.releaseState(messageId, state, this.accepts(epoch)
        ? { pendingTaskIds: new Set<number>(), error: error.message } : IDLE_CHECKLIST_ACTION);
      throw error;
    }).finally((): void => { if (this.pending.get(messageId) === work) { this.pending.delete(messageId); this.pendingStates.delete(messageId); } });
    this.pending.set(messageId, work);
    this.pendingStates.set(messageId, state);
    publishChecklistAction(this.client, this.chatId, messageId, state);
    return work;
  }
  private releaseState(messageId: number, owned: ChecklistActionState, next: ChecklistActionState): void {
    if (checklistActionState(this.client, this.chatId, messageId) === owned) {
      publishChecklistAction(this.client, this.chatId, messageId, next);
    }
  }
  private accepts(epoch: number): boolean { return !this.closed && epoch === this.epoch && this.isCurrent(); }
  close(): void {
    this.closed = true; this.epoch++;
    this.pendingStates.forEach((state: ChecklistActionState, messageId: number): void => {
      this.releaseState(messageId, state, IDLE_CHECKLIST_ACTION);
    });
    this.pending.clear(); this.pendingStates.clear();
  }
}
