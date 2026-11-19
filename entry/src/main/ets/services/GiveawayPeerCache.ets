import { logW } from '../util/log';
import { getTdClient } from '../tdkit/Globals';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { documentFileId, documentFilePath } from '../util/drawnDocumentMedia';

export interface GiveawayPeerInfo {
  id: number;
  user: boolean;
  name: string;
  photo: TdObject | undefined;
}
type GiveawayPeerListener = (info: GiveawayPeerInfo | null) => void;
class GiveawayPeerRecord {
  id: number;
  user: boolean;
  key: string;
  info: GiveawayPeerInfo | null = null;
  listeners: Set<GiveawayPeerListener> = new Set();
  previous: GiveawayPeerRecord | null = null;
  next: GiveawayPeerRecord | null = null;
  queued: boolean = false;
  active: boolean = false;
  nameRevision: number = 0;
  photoRevision: number = 0;
  constructor(id: number, user: boolean) { this.id = id; this.user = user; this.key = peerKey(id, user); }
}
const records: Map<string, GiveawayPeerRecord> = new Map();
const recent: Map<string, GiveawayPeerInfo> = new Map();
const RECENT_LIMIT: number = 512;
const CONCURRENCY: number = 4;
let owner: TdClient | null = null;
let epoch: number = 0;
let active: number = 0;
let head: GiveawayPeerRecord | null = null;
let tail: GiveawayPeerRecord | null = null;
let offUser: (() => void) | null = null;
let offChat: (() => void) | null = null;
let offTitle: (() => void) | null = null;
let offPhoto: (() => void) | null = null;

function peerKey(id: number, user: boolean): string { return `${user ? 'u' : 'c'}${id}`; }
function peerInfo(id: number, user: boolean, raw: TdObject): GiveawayPeerInfo {
  const name = user ? `${(raw['first_name'] as string | undefined) ?? ''} ${(raw['last_name'] as string | undefined) ?? ''}`.trim()
    : (raw['title'] as string | undefined) ?? '';
  const photo = raw[user ? 'profile_photo' : 'photo'] as TdObject | undefined;
  return { id, user, name, photo: photo?.['small'] as TdObject | undefined };
}
function remember(info: GiveawayPeerInfo): void {
  const key = peerKey(info.id, info.user);
  recent.delete(key); recent.set(key, info);
  if (recent.size > RECENT_LIMIT) { recent.delete(recent.keys().next().value as string); }
}
function publish(record: GiveawayPeerRecord, info: GiveawayPeerInfo): void {
  const old = record.info;
  record.info = info;
  if (old?.name === info.name && documentFileId(old.photo) === documentFileId(info.photo) &&
    documentFilePath(old.photo) === documentFilePath(info.photo)) { return; }
  record.listeners.forEach((listener: GiveawayPeerListener): void => listener(info));
}
function updatePeer(id: number, user: boolean, info: GiveawayPeerInfo, name: boolean, photo: boolean): void {
  const key = peerKey(id, user), record = records.get(key);
  if (record !== undefined) {
    if (name) { record.nameRevision++; }
    if (photo) { record.photoRevision++; }
    publish(record, info);
  }
  if (recent.has(key)) { remember(info); }
}
function currentClient(): TdClient {
  const client = getTdClient();
  if (owner === client) { return client; }
  resetGiveawayPeers(); owner = client;
  const token = epoch;
  offUser = client.onUpdate('updateUser', (update: TdObject): void => {
    if (token !== epoch) { return; }
    const raw = update['user'] as TdObject | undefined, id = (raw?.['id'] as number | undefined) ?? 0;
    if (raw && id > 0 && (records.has(peerKey(id, true)) || recent.has(peerKey(id, true)))) {
      updatePeer(id, true, peerInfo(id, true, raw), true, true);
    }
  });
  offChat = client.onUpdate('updateNewChat', (update: TdObject): void => {
    if (token !== epoch) { return; }
    const raw = update['chat'] as TdObject | undefined, id = (raw?.['id'] as number | undefined) ?? 0;
    if (raw && id !== 0 && (records.has(peerKey(id, false)) || recent.has(peerKey(id, false)))) {
      updatePeer(id, false, peerInfo(id, false, raw), true, true);
    }
  });
  offTitle = client.onUpdate('updateChatTitle', (update: TdObject): void => {
    if (token !== epoch) { return; }
    const id = (update['chat_id'] as number | undefined) ?? 0, key = peerKey(id, false);
    const old = records.get(key)?.info ?? recent.get(key);
    if (!old && !records.has(key)) { return; }
    updatePeer(id, false, { id, user: false, name: (update['title'] as string | undefined) ?? '', photo: old?.photo }, true, false);
  });
  offPhoto = client.onUpdate('updateChatPhoto', (update: TdObject): void => {
    if (token !== epoch) { return; }
    const id = (update['chat_id'] as number | undefined) ?? 0, key = peerKey(id, false);
    const old = records.get(key)?.info ?? recent.get(key);
    if (!old && !records.has(key)) { return; }
    const photo = update['photo'] as TdObject | undefined;
    updatePeer(id, false, { id, user: false, name: old?.name ?? '', photo: photo?.['small'] as TdObject | undefined }, false, true);
  });
  return client;
}
function unlink(record: GiveawayPeerRecord): void {
  if (!record.queued) { return; }
  if (record.previous) { record.previous.next = record.next; } else { head = record.next; }
  if (record.next) { record.next.previous = record.previous; } else { tail = record.previous; }
  record.previous = null; record.next = null; record.queued = false;
}
function drain(client: TdClient): void {
  while (active < CONCURRENCY && head !== null) {
    const record = head; unlink(record);
    if (record.listeners.size === 0) { records.delete(record.key); continue; }
    record.active = true; active++;
    const token = epoch, nameRevision = record.nameRevision, photoRevision = record.photoRevision;
    const req: TdRequest = { '@type': record.user ? 'getUser' : 'getChat' };
    req[record.user ? 'user_id' : 'chat_id'] = record.id;
    client.send(req).then((raw: TdObject): void => {
      if (token !== epoch || records.get(record.key) !== record) { return; }
      const result = peerInfo(record.id, record.user, raw), old = record.info;
      // A newer update can arrive before the older request's reply. Preserve
      // each updated field independently; title updates must not lose a photo.
      if (record.nameRevision !== nameRevision && old !== null) { result.name = old.name; }
      if (record.photoRevision !== photoRevision && old !== null) { result.photo = old.photo; }
      publish(record, result);
    }, (): void => {}).finally((): void => {
      if (token !== epoch || records.get(record.key) !== record) { return; }
      record.active = false; active--;
      if (record.listeners.size === 0) {
        records.delete(record.key);
        if (record.info !== null) { remember(record.info); }
      }
      drain(client);
    }).catch((error: Error): void => { logW(`Giveaway peer observer: ${error.message}`); });
  }
}

// Single-flight per account/peer. Queue operations and cancellation are O(1),
// four requests at a time. Retained memory: O(live watched peers)+512 recent.
export function watchGiveawayPeer(id: number, user: boolean, listener: GiveawayPeerListener): () => void {
  if (!Number.isSafeInteger(id) || (user ? id <= 0 : id === 0)) { listener(null); return (): void => {}; }
  const client = currentClient(), key = peerKey(id, user), token = epoch;
  let record = records.get(key);
  if (!record) {
    record = new GiveawayPeerRecord(id, user); record.info = recent.get(key) ?? null;
    recent.delete(key); records.set(key, record);
    if (record.info === null) {
      record.queued = true; record.previous = tail;
      if (tail) { tail.next = record; } else { head = record; }
      tail = record;
    }
  }
  const held = record;
  held.listeners.add(listener); listener(held.info); drain(client);
  let subscribed = true;
  return (): void => {
    if (!subscribed) { return; } subscribed = false; held.listeners.delete(listener);
    if (token !== epoch || held.listeners.size > 0) { return; }
    unlink(held);
    if (!held.active) { records.delete(key); if (held.info !== null) { remember(held.info); } }
  };
}
export function resetGiveawayPeers(): void {
  epoch++; offUser?.(); offChat?.(); offTitle?.(); offPhoto?.();
  offUser = null; offChat = null; offTitle = null; offPhoto = null;
  records.clear(); recent.clear(); head = null; tail = null; active = 0; owner = null;
}
