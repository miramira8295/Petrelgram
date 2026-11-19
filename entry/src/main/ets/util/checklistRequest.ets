import { TdObject, TdRequest } from '../tdkit/TdTypes';
function checklistText(text: string): TdObject {
  const result: TdObject = { '@type': 'formattedText' }; result['text'] = text; result['entities'] = []; return result;
}
export function inputChecklist(title: string, tasks: string[], allowAdd: boolean, allowMark: boolean): TdObject {
  const heading = title.trim();
  if (heading === '') { throw new Error('CHECKLIST_TITLE_EMPTY'); }
  const items: TdObject[] = [];
  for (const task of tasks) {
    const text = task.trim(); if (text === '') { continue; }
    const item: TdObject = { '@type': 'inputChecklistTask' };
    item['id'] = items.length + 1; item['text'] = checklistText(text); items.push(item);
  }
  if (items.length === 0) { throw new Error('CHECKLIST_TASKS_EMPTY'); }
  const result: TdObject = { '@type': 'inputChecklist' };
  result['title'] = checklistText(heading); result['tasks'] = items;
  result['others_can_add_tasks'] = allowAdd; result['others_can_mark_tasks_as_done'] = allowMark;
  return result;
}
export function markChecklistRequest(chatId: number, messageId: number, taskId: number, done: boolean): TdRequest {
  if (!Number.isInteger(taskId) || taskId < -2147483648 || taskId > 2147483647) { throw new Error('CHECKLIST_TASK_INVALID'); }
  const result: TdRequest = { '@type': 'markChecklistTasksAsDone' };
  result['chat_id'] = chatId; result['message_id'] = messageId;
  result['marked_as_done_task_ids'] = done ? [taskId] : [];
  result['marked_as_not_done_task_ids'] = done ? [] : [taskId]; return result;
}
