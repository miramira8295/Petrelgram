import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { getTdClient } from '../tdkit/Globals';
import { documentFileId, documentFilePath } from './drawnDocumentMedia';
import { publishProgress } from './mediaProgressChannel';

export interface DocumentFileState { path: string; progress: number; failed: boolean; active?: boolean; }
type DocumentFileListener = (state: DocumentFileState) => void;
const states: Map<number, DocumentFileState> = new Map<number, DocumentFileState>();
const recent: Map<number, DocumentFileState> = new Map<number, DocumentFileState>();
const listeners: Map<number, Set<DocumentFileListener>> = new Map<number, Set<DocumentFileListener>>();
const requested: Map<number, number> = new Map<number, number>();
const requests: Map<number, number> = new Map<number, number>();
let requestSerial: number = 0;
let clientEpoch: number = 0;
let client: TdClient | null = null;
let offUpdates: (() => void) | null = null;

function currentClient(): TdClient {
  const next = getTdClient();
  if (client !== next) {
    offUpdates?.(); offUpdates = null; client = next; clientEpoch++;
    states.clear(); recent.clear(); listeners.clear(); requested.clear(); requests.clear();
  }
  return next;
}
function stateFrom(file: TdObject): DocumentFileState {
  const local = file['local'] as TdObject | undefined;
  const path = documentFilePath(file);
  const size = ((file['size'] as number | undefined) ?? 0) || ((file['expected_size'] as number | undefined) ?? 0);
  const loaded = (local?.['downloaded_size'] as number | undefined) ?? 0;
  return { path, progress: path !== '' ? 100 : size > 0 ? Math.min(99, Math.floor(100 * loaded / size)) : 0, failed: false, active: local?.['is_downloading_active'] === true };
}
function remember(id: number, state: DocumentFileState): void {
  recent.delete(id); recent.set(id, state);
  if (recent.size > 256) { recent.delete(recent.keys().next().value as number); }
}
function publish(id: number, next: DocumentFileState): void {
  const old = states.get(id) ?? recent.get(id);
  if (listeners.has(id)) { states.set(id, next); } else { remember(id, next); }
  publishProgress(id, next.progress);
  // Progress rings listen directly; byte updates do not rebuild media/rows.
  if (old?.path !== next.path || old?.failed !== next.failed || (old?.active === true) !== (next.active === true)) {
    listeners.get(id)?.forEach((listener: DocumentFileListener): void => listener(next));
  }
  if (next.path !== '' || next.failed) { requested.delete(id); }

}
export function documentFileState(file: TdObject): DocumentFileState {
  currentClient();
  const id = documentFileId(file);
  const old = states.get(id) ?? recent.get(id);
  if (old !== undefined) { return old; }
  const initial = stateFrom(file); publish(id, initial); return initial;
}
export function watchDocumentFile(file: TdObject, listener: DocumentFileListener, includeActivity: boolean = false): () => void {
  const target = currentClient(), id = documentFileId(file);
  const generation = clientEpoch;
  const initial = documentFileState(file);
  let set = listeners.get(id);
  if (set === undefined) { set = new Set<DocumentFileListener>(); listeners.set(id, set); }
  let previous = initial;
  const deliver: DocumentFileListener = (next: DocumentFileState): void => {
    const changed = previous.path !== next.path || previous.failed !== next.failed ||
      (includeActivity && (previous.active === true) !== (next.active === true));
    previous = next;
    if (changed) { listener(next); }
  };
  set.add(deliver); states.set(id, initial); recent.delete(id);
  if (offUpdates === null) {
    offUpdates = target.onUpdate('updateFile', (update: TdObject): void => {
      if (client !== target || generation !== clientEpoch) { return; }
      const changed = update['file'] as TdObject | undefined;
      if (changed !== undefined && listeners.has(documentFileId(changed))) { publish(documentFileId(changed), stateFrom(changed)); }
    });
  }
  return (): void => {
    if (client !== target || generation !== clientEpoch) { return; }
    set?.delete(deliver);
    if (set?.size === 0) {
      listeners.delete(id); requested.delete(id); requests.delete(id);
      const state = states.get(id); states.delete(id); if (state !== undefined) { remember(id, state); }
    }
    if (listeners.size === 0) { offUpdates?.(); offUpdates = null; }
  };
}
export function requestDocumentFile(file: TdObject, priority: number, retry: boolean = false): void {
  const target = currentClient(), id = documentFileId(file), state = documentFileState(file);
  if (id <= 0 || state.path !== '' || (!retry && (state.failed || (requested.get(id) ?? 0) >= priority))) { return; }
  const serial = ++requestSerial; requests.set(id, serial);
  requested.set(id, priority);
  publish(id, { path: '', progress: state.progress, failed: false, active: true });
  const request: TdRequest = { '@type': 'downloadFile' };
  request['file_id'] = id; request['priority'] = priority; request['synchronous'] = false;
  target.send(request).then((result: TdObject): void => {
    if (client === target && requests.get(id) === serial) {
      const next = stateFrom(result), current = states.get(id) ?? recent.get(id);
      if (next.path !== '' || current?.path === '') { publish(id, next); }
      if (!listeners.has(id)) { requests.delete(id); requested.delete(id); }
    }
  }).catch((): void => {
    const current = states.get(id) ?? recent.get(id);
    if (client === target && requests.get(id) === serial && current?.path === '') { publish(id, { path: '', progress: current.progress, failed: true }); }
    if (requests.get(id) === serial) { requests.delete(id); }
  });
}

// Explicit user cancellation. Invalidate the outstanding request before asking
// TDLib to stop, so an older completion cannot resurrect the open intent.
export function cancelDocumentFile(file: TdObject): void {
  const target = currentClient(), id = documentFileId(file);
  const state = documentFileState(file);
  if (id <= 0 || state.path !== '') { return; }
  const serial = ++requestSerial; requests.set(id, serial); requested.delete(id);
  const request: TdRequest = { '@type': 'cancelDownloadFile' };
  request['file_id'] = id; request['only_if_pending'] = false;
  target.send(request).then((): void => {
    if (client !== target || requests.get(id) !== serial) { return; }
    const current = states.get(id) ?? recent.get(id);
    if (current !== undefined && current.path === '') { publish(id, { path: '', progress: current.progress, failed: false, active: false }); }
    requests.delete(id);
  }).catch((): void => {
    if (client !== target || requests.get(id) !== serial) { return; }
    const current = states.get(id) ?? recent.get(id);
    if (current !== undefined && current.path === '') { publish(id, { path: '', progress: current.progress, failed: true, active: false }); }
    requests.delete(id);
  });
}
