import { TdObject } from '../tdkit/TdTypes';

// Immutable text identity is separate from completion/permissions. Server
// snapshots may replace every TD object when only one checkbox changed.
export interface ChecklistText {
  text: string;
  entities: TdObject[];
  entitiesKey: string;
}
export interface ChecklistTaskContent { id: number; label: ChecklistText; }
export interface ChecklistTask {
  id: number;
  text: string;
  entities: TdObject[];
  content: ChecklistTaskContent;
  completed: boolean;
  completedById: number;
  completedByIsUser: boolean;
  completionDate: number;
}
export interface ChecklistGeometry {
  revision: number;
  title: ChecklistText;
  tasks: ChecklistTaskContent[];
}
export interface ChecklistModel {
  title: ChecklistText;
  tasks: ChecklistTask[];
  taskById: ReadonlyMap<number, ChecklistTask>;
  geometry: ChecklistGeometry;
  canMarkTasksAsDone: boolean;
  canAddTasks: boolean;
  othersCanAddTasks: boolean;
  othersCanMarkTasksAsDone: boolean;
  completedCount: number;
  preview: string;
  signature: string;
}

const EMPTY_CHECKLIST_ENTITIES: TdObject[] = [];
const checklistSnapshots: WeakMap<TdObject, ChecklistModel> = new WeakMap<TdObject, ChecklistModel>();
let checklistRevision: number = 0;
let checklistGeometryRevision: number = 0;

function checklistText(raw: TdObject | undefined, previous?: ChecklistText): ChecklistText | null {
  if (raw === undefined || raw === null || typeof raw !== 'object' || typeof raw['text'] !== 'string') { return null; }
  const text = raw['text'] as string;
  const rawEntities = raw['entities'];
  if (rawEntities !== undefined && !Array.isArray(rawEntities)) { return null; }
  const entities = (rawEntities as TdObject[] | undefined) ?? EMPTY_CHECKLIST_ENTITIES;
  if (previous !== undefined && previous.text === text && previous.entities === entities) { return previous; }
  for (const entity of entities) {
    if (entity === null || typeof entity !== 'object') { return null; }
    const offset = entity['offset'] as number, length = entity['length'] as number;
    if (!Number.isSafeInteger(offset) || !Number.isSafeInteger(length) || offset < 0 || length <= 0 ||
      offset + length > text.length || entity['type'] === undefined) { return null; }
  }
  let entitiesKey: string;
  try { entitiesKey = JSON.stringify(entities); } catch (_) { return null; }
  if (previous !== undefined && previous.text === text && previous.entitiesKey === entitiesKey) { return previous; }
  return { text, entities, entitiesKey };
}

// O(N+T+E) on a new snapshot, O(1) for the same raw immutable list. No arbitrary
// task count cap, nested task lookup, or per-checkbox paragraph invalidation.
export function parseChecklist(raw: TdObject | undefined, previous?: ChecklistModel): ChecklistModel | null {
  if (raw === undefined || raw === null || typeof raw !== 'object') { return null; }
  const hit = checklistSnapshots.get(raw);
  if (hit !== undefined) { return hit; }
  const title = checklistText(raw['title'] as TdObject | undefined, previous?.title);
  const rawTasks = raw['tasks'];
  if (title === null || !Array.isArray(rawTasks)) { return null; }
  const tasks: ChecklistTask[] = [], contents: ChecklistTaskContent[] = [];
  const taskById: Map<number, ChecklistTask> = new Map<number, ChecklistTask>();
  const preview: string[] = [title.text];
  let completedCount = 0, sameTasks = previous?.tasks.length === rawTasks.length;
  let sameGeometry = previous?.geometry.title === title && previous?.geometry.tasks.length === rawTasks.length;
  let index = 0;
  for (const object of rawTasks as TdObject[]) {
    if (object === null || typeof object !== 'object') { return null; }
    const id = object['id'] as number;
    if (!Number.isInteger(id) || id < -2147483648 || id > 2147483647 || taskById.has(id)) { return null; }
    const before = previous?.taskById.get(id);
    const label = checklistText(object['text'] as TdObject | undefined, before?.content.label);
    if (label === null) { return null; }
    const rawDate = (object['completion_date'] as number | undefined) ?? 0;
    if (!Number.isSafeInteger(rawDate) || rawDate < 0) { return null; }
    const sender = object['completed_by'] as TdObject | undefined;
    const completedByIsUser = sender?.['@type'] === 'messageSenderUser';
    const completedById = sender === undefined || sender === null ? 0 :
      ((sender[completedByIsUser ? 'user_id' : 'chat_id'] as number | undefined) ?? 0);
    if (!Number.isSafeInteger(completedById)) { return null; }
    const completed = rawDate > 0;
    const content: ChecklistTaskContent = before?.content.label === label ? before.content : { id, label };
    const task: ChecklistTask = before !== undefined && before.content === content && before.completed === completed &&
      before.completionDate === rawDate && before.completedById === completedById && before.completedByIsUser === completedByIsUser
      ? before : { id, text: label.text, entities: label.entities, content, completed,
        completedById, completedByIsUser, completionDate: rawDate };
    tasks.push(task); contents.push(content); taskById.set(id, task);
    if (completed) { completedCount++; }
    preview.push(`${completed ? '☑' : '☐'} ${label.text}`);
    if (previous?.tasks[index] !== task) { sameTasks = false; }
    if (previous?.geometry.tasks[index] !== content) { sameGeometry = false; }
    index++;
  }
  const canMarkTasksAsDone = raw['can_mark_tasks_as_done'] === true;
  const canAddTasks = raw['can_add_tasks'] === true;
  const othersCanAddTasks = raw['others_can_add_tasks'] === true;
  const othersCanMarkTasksAsDone = raw['others_can_mark_tasks_as_done'] === true;
  if (previous !== undefined && previous.title === title && sameTasks && previous.canMarkTasksAsDone === canMarkTasksAsDone &&
    previous.canAddTasks === canAddTasks && previous.othersCanAddTasks === othersCanAddTasks &&
    previous.othersCanMarkTasksAsDone === othersCanMarkTasksAsDone) {
    checklistSnapshots.set(raw, previous); return previous;
  }
  const geometry: ChecklistGeometry = previous !== undefined && sameGeometry ? previous.geometry :
    { revision: ++checklistGeometryRevision, title, tasks: contents };
  const result: ChecklistModel = { title, tasks, taskById, geometry, canMarkTasksAsDone, canAddTasks,
    othersCanAddTasks, othersCanMarkTasksAsDone, completedCount, preview: preview.join('\n'), signature: `checklist:${++checklistRevision}` };
  checklistSnapshots.set(raw, result); return result;
}
