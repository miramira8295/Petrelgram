import { TdClient } from '../tdkit/TdClient';

export interface ChecklistActionState { pendingTaskIds: ReadonlySet<number>; error: string; }
const EMPTY_TASKS: ReadonlySet<number> = new Set<number>();
export const IDLE_CHECKLIST_ACTION: ChecklistActionState = { pendingTaskIds: EMPTY_TASKS, error: '' };
type ChecklistListener = (state: ChecklistActionState) => void;
class ChecklistChannel {
  active: Map<string, ChecklistActionState> = new Map();
  recent: Map<string, ChecklistActionState> = new Map();
  listeners: Map<string, Set<ChecklistListener>> = new Map();
}
const channels: WeakMap<TdClient, ChecklistChannel> = new WeakMap();
function channel(client: TdClient): ChecklistChannel {
  let result = channels.get(client);
  if (result === undefined) { result = new ChecklistChannel(); channels.set(client, result); }
  return result;
}
function key(chatId: number, messageId: number): string { return `${chatId}:${messageId}`; }
function remember(c: ChecklistChannel, id: string, state: ChecklistActionState): void {
  c.recent.delete(id);
  if (state !== IDLE_CHECKLIST_ACTION) { c.recent.set(id, state); }
  if (c.recent.size > 128) { c.recent.delete(c.recent.keys().next().value as string); }
}
export function checklistActionState(client: TdClient, chatId: number, messageId: number): ChecklistActionState {
  const c = channel(client), id = key(chatId, messageId);
  return c.active.get(id) ?? c.recent.get(id) ?? IDLE_CHECKLIST_ACTION;
}
export function publishChecklistAction(client: TdClient, chatId: number, messageId: number, state: ChecklistActionState): void {
  const c = channel(client), id = key(chatId, messageId), listeners = c.listeners.get(id);
  if (listeners !== undefined) {
    c.active.set(id, state);
    listeners.forEach((fn: ChecklistListener): void => fn(state));
  } else { remember(c, id, state); }
}
export function subscribeChecklistAction(client: TdClient, chatId: number, messageId: number,
  listener: ChecklistListener): () => void {
  const c = channel(client), id = key(chatId, messageId);
  let listeners = c.listeners.get(id);
  if (listeners === undefined) {
    listeners = new Set<ChecklistListener>(); c.listeners.set(id, listeners);
    c.active.set(id, c.recent.get(id) ?? IDLE_CHECKLIST_ACTION); c.recent.delete(id);
  }
  listeners.add(listener);
  return (): void => {
    const current = c.listeners.get(id);
    if (current === undefined) { return; }
    current.delete(listener);
    if (current.size === 0) {
      c.listeners.delete(id); remember(c, id, c.active.get(id) ?? IDLE_CHECKLIST_ACTION); c.active.delete(id);
    }
  };
}
