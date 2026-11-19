import { getTdClient } from '../tdkit/Globals';
import { TdClient } from '../tdkit/TdClient';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { parseReactionKey } from '../util/reactions';
import { customEmojiNeedsRepainting } from '../util/inlineCustomEmojiPaint';
import { logW } from '../util/log';

export interface ReactionArtwork {
  poster: TdObject | undefined;
  animation: TdObject | undefined;
  format: string;
  emoji: string;
  repaint: boolean;
}
type Listener = (art: ReactionArtwork | null) => void;
class ReactionArtworkRecord {
  key: string;
  value: ReactionArtwork | null = null;
  expires: number = 0;
  listeners: Set<Listener> = new Set();
  next: ReactionArtworkRecord | null = null;
  previous: ReactionArtworkRecord | null = null;
  queued: boolean = false;
  running: boolean = false;
  constructor(key: string) { this.key = key; }
}
interface RecentArtwork { value: ReactionArtwork | null; expires: number; }
const records: Map<string, ReactionArtworkRecord> = new Map();
const recent: Map<string, RecentArtwork> = new Map();
let client: TdClient | null = null;
let epoch: number = 0;
let active: number = 0;
let first: ReactionArtworkRecord | null = null;
let last: ReactionArtworkRecord | null = null;
const LIMIT: number = 256;
const CONCURRENCY: number = 4;
function file(sticker: TdObject | undefined): TdObject | undefined { return sticker?.['sticker'] as TdObject | undefined; }
function format(sticker: TdObject | undefined): string { return ((sticker?.['format'] as TdObject | undefined)?.['@type'] as string | undefined) ?? ''; }
function poster(sticker: TdObject | undefined): TdObject | undefined {
  if (format(sticker) === 'stickerFormatWebp') { return file(sticker); }
  return (sticker?.['thumbnail'] as TdObject | undefined)?.['file'] as TdObject | undefined;
}
export function reactionArtworkFrom(key: string, raw: TdObject): ReactionArtwork | null {
  const parsed = parseReactionKey(key);
  if (parsed.customEmojiId !== '') {
    const stickers = (raw['stickers'] as TdObject[] | undefined) ?? [];
    // Match the returned int64 string; never associate a different sticker by index.
    for (const sticker of stickers) {
      const full = sticker['full_type'] as TdObject | undefined;
      if (`${full?.['custom_emoji_id'] ?? sticker['custom_emoji_id'] ?? ''}` !== parsed.customEmojiId) { continue; }
      return { poster: poster(sticker), animation: file(sticker), format: format(sticker),
        emoji: (sticker['emoji'] as string | undefined) ?? '', repaint: customEmojiNeedsRepainting(sticker) };
    }
    return null;
  }
  const icon = raw['static_icon'] as TdObject | undefined;
  const animation = (raw['center_animation'] ?? raw['activate_animation'] ?? raw['select_animation']) as TdObject | undefined;
  if (icon === undefined) { return null; }
  return { poster: poster(icon), animation: file(animation), format: format(animation), emoji: parsed.emoji, repaint: false };
}
function notify(listener: Listener, value: ReactionArtwork | null): void {
  try { listener(value); } catch (error) { logW(`Reaction artwork observer: ${(error as Error).message}`); }
}
function remember(record: ReactionArtworkRecord): void {
  recent.delete(record.key); recent.set(record.key, { value: record.value, expires: record.expires });
  if (recent.size > LIMIT) { recent.delete(recent.keys().next().value as string); }
}
function unlink(record: ReactionArtworkRecord): void {
  if (!record.queued) { return; }
  if (record.previous) { record.previous.next = record.next; } else { first = record.next; }
  if (record.next) { record.next.previous = record.previous; } else { last = record.previous; }
  record.queued = false; record.next = null; record.previous = null;
}
function enqueue(record: ReactionArtworkRecord): void {
  if (record.queued || record.running) { return; }
  record.queued = true; record.previous = last;
  if (last !== null) { last.next = record; } else { first = record; }
  last = record;
}
function finish(record: ReactionArtworkRecord, target: TdClient, generation: number, value: ReactionArtwork | null): void {
  if (generation !== epoch || records.get(record.key) !== record || !record.running) { return; }
  active--; record.running = false; record.value = value;
  record.expires = Date.now() + (value === null ? 15000 : 300000);
  if (value !== null || record.listeners.size > 0) { remember(record); }
  // A listener may unsubscribe or add another listener while being notified.
  // The new listener already receives the current snapshot in watch().
  const listeners = Array.from(record.listeners);
  for (const listener of listeners) {
    if (generation !== epoch) { return; }
    if (records.get(record.key) !== record) { break; }
    if (record.listeners.has(listener)) { notify(listener, value); }
  }
  if (generation !== epoch) { return; }
  if (records.get(record.key) === record && record.listeners.size === 0) { records.delete(record.key); }
  pump(target);
}
function pump(target: TdClient): void {
  if (target !== client) { return; }
  while (active < CONCURRENCY && first !== null) {
    const record = first; unlink(record);
    if (record.listeners.size === 0) { records.delete(record.key); continue; }
    active++; record.running = true;
    const generation = epoch, parsed = parseReactionKey(record.key);
    const request: TdRequest = { '@type': parsed.customEmojiId !== '' ? 'getCustomEmojiStickers' : 'getEmojiReaction' };
    if (parsed.customEmojiId !== '') { request['custom_emoji_ids'] = [parsed.customEmojiId]; }
    else { request['emoji'] = parsed.emoji; }
    // Promise boundary handles synchronous send errors without recursive queue
    // draining. Account changes/cancellation before dispatch do not send a request.
    Promise.resolve().then((): Promise<TdObject> | null => {
      if (generation !== epoch || records.get(record.key) !== record || record.listeners.size === 0) { return null; }
      return target.send(request, 15000);
    }).then((raw: TdObject | null): void => {
      finish(record, target, generation, raw === null ? null : reactionArtworkFrom(record.key, raw));
    }).catch((): void => { finish(record, target, generation, null); });
  }
}
export function resetReactionArtwork(): void {
  epoch++; records.clear(); recent.clear(); first = null; last = null; active = 0; client = null;
}
// Metadata is single-flight by account/reaction. O(1) enqueue/cancel/LRU;
// O(subscribers) delivery only on resolution. TTL retries happen on remount or
// a new subscriber, never via a permanent polling timer on visible messages.
export function watchReactionArtwork(key: string, listener: Listener): () => void {
  // Paid stars are not an ordinary emojiReaction; their icon remains the local
  // star. Never issue getEmojiReaction with the internal paid discriminator.
  if (key === 'paid:stars') { notify(listener, null); return (): void => {}; }
  const target = getTdClient();
  if (target !== client) { resetReactionArtwork(); client = target; }
  const generation = epoch;
  let record = records.get(key);
  if (record === undefined) {
    record = new ReactionArtworkRecord(key); records.set(key, record);
    const cached = recent.get(key);
    if (cached !== undefined && cached.expires > Date.now()) {
      record.value = cached.value; record.expires = cached.expires;
      recent.delete(key); recent.set(key, cached);
    } else { recent.delete(key); }
  }
  if (record.expires <= Date.now()) { enqueue(record); }
  const held = record; held.listeners.add(listener); notify(listener, held.value); pump(target);
  let subscribed = true;
  return (): void => {
    if (!subscribed) { return; } subscribed = false; held.listeners.delete(listener);
    if (generation !== epoch || held.listeners.size > 0) { return; }
    unlink(held);
    if (!held.running && records.get(key) === held) { records.delete(key); }
  };
}
