import { i18n } from '@kit.LocalizationKit';
import { KEY_TRANSLATE_TARGET } from '../store/AppSettings';
import { TdClient } from '../tdkit/TdClient';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  clearTranslationStatus, publishTranslating, publishTranslationFailed
} from '../util/translationChannel';
import { logE } from '../util/log';

// Whole-chat translation engine.
//
// TDLib has no batch endpoint — translateMessageText is one round trip per
// message — so translating a chat is a stream of small requests. This service
// exists to make that stream safe and cheap:
//   - a cache keyed by (chat, message, editDate, target language), so a row is
//     translated once per content version, not once per render;
//   - a FIFO queue with a small concurrency cap, so opening a busy chat doesn't
//     fire thirty simultaneous requests;
//   - flood-wait backoff: Telegram answers bursts with "Too Many Requests:
//     retry after N", and the queue must go quiet for that long instead of
//     hammering on.
//
// The service is process-global (survives ChatPage instances) but holds only
// strings — no message objects, no store references. Writing results into the
// message list is the caller's job (MessageStore.applyTranslation), because
// only the store can raise the CHANGE notifications the list renders from.

// Cache/queue keys embed editDate: an edited message is a different content
// version and must be retranslated; the stale entry is simply never asked for
// again.
function keyOf(chatId: number, messageId: number, editDate: number, lang: string): string {
  return `${chatId}_${messageId}_${editDate}_${lang}`;
}

// The user-facing target language: the explicit setting, or the system UI
// language when the setting is "follow system" (''). Two-letter codes — that
// is what translateMessageText accepts.
export function resolveTranslateTarget(): string {
  const configured = AppStorage.get<string>(KEY_TRANSLATE_TARGET) ?? '';
  if (configured !== '') {
    return configured;
  }
  try {
    const lang = i18n.System.getSystemLanguage();
    if (lang.length >= 2) {
      return lang.split('-')[0];
    }
  } catch (_e) { /* fall through */ }
  return 'zh';
}

// Languages offered by the target-language pickers (settings and the
// translation sheet). Two-letter ISO 639-1 codes — what translateMessageText
// accepts — plus the two Chinese scripts, which Telegram's backend resolves.
// Display names come from languageDisplayName at render time, so the list
// localizes itself.
export const TRANSLATE_LANG_CODES: string[] = [
  'zh', 'zh-Hant', 'en', 'ja', 'ko', 'ru', 'fr', 'de', 'es', 'pt', 'it',
  'ar', 'tr', 'vi', 'th', 'id', 'hi'
];

// "已翻译成简体中文" needs the language's display name in the UI language;
// falls back to the raw code for anything the system can't name.
export function languageDisplayName(code: string): string {
  if (code === '') {
    return '';
  }
  try {
    const name = i18n.System.getDisplayLanguage(code, i18n.System.getSystemLanguage());
    if (name !== '') {
      return name;
    }
  } catch (_e) { /* fall through */ }
  return code;
}

// Script buckets for the cheap language check below.
interface ScriptCounts {
  han: number;
  kana: number;
  hangul: number;
  cyrillic: number;
  arabic: number;
  thai: number;
  devanagari: number;
  latin: number;
  total: number;
}

function countScripts(text: string): ScriptCounts {
  const c: ScriptCounts = {
    han: 0, kana: 0, hangul: 0, cyrillic: 0, arabic: 0,
    thai: 0, devanagari: 0, latin: 0, total: 0
  };
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code >= 0x4E00 && code <= 0x9FFF) {
      c.han++;
    } else if ((code >= 0x3040 && code <= 0x30FF) || (code >= 0x31F0 && code <= 0x31FF)) {
      c.kana++;
    } else if ((code >= 0xAC00 && code <= 0xD7AF) || (code >= 0x1100 && code <= 0x11FF)) {
      c.hangul++;
    } else if (code >= 0x0400 && code <= 0x04FF) {
      c.cyrillic++;
    } else if (code >= 0x0600 && code <= 0x06FF) {
      c.arabic++;
    } else if (code >= 0x0E00 && code <= 0x0E7F) {
      c.thai++;
    } else if (code >= 0x0900 && code <= 0x097F) {
      c.devanagari++;
    } else if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) ||
      (code >= 0xC0 && code <= 0x24F)) {
      c.latin++;
    } else {
      continue; // digits/punctuation/emoji/whitespace don't vote
    }
    c.total++;
  }
  return c;
}

// True when the text is already (detectably) in the target language, so a
// translation request would be a wasted round trip. This is a SCRIPT check,
// not real language identification: it can tell Chinese from Russian, but not
// English from French — Latin-script targets always return false and let the
// server decide (its identical-result answer is cached, so it's one round trip
// per content version, not per render). Kana vetoes the zh match because
// Japanese text is typically han + kana mixed.
export function looksLikeTargetLanguage(text: string, lang: string): boolean {
  const c = countScripts(text);
  if (c.total === 0) {
    return true; // nothing translatable: pure emoji/digits/links
  }
  if (lang === 'zh' || lang === 'zh-Hant') {
    return c.kana === 0 && c.han / c.total >= 0.5;
  }
  if (lang === 'ja') {
    // Pure-han text is more likely Chinese than kana-less Japanese; only kana
    // marks Japanese with any confidence.
    return c.kana > 0;
  }
  if (lang === 'ko') {
    return c.hangul / c.total >= 0.3;
  }
  if (lang === 'ru') {
    return c.cyrillic / c.total >= 0.5;
  }
  if (lang === 'ar') {
    return c.arabic / c.total >= 0.5;
  }
  if (lang === 'th') {
    return c.thai / c.total >= 0.5;
  }
  if (lang === 'hi') {
    return c.devanagari / c.total >= 0.5;
  }
  return false;
}

interface Job {
  key: string;
  chatId: number;
  messageId: number;
  lang: string;
  resolvers: Array<(text: string | null) => void>;
}

// 并发上限是自适应的：平时跑 MAX_ACTIVE_FAST，一旦撞上 flood-wait 就降到
// MAX_ACTIVE_SAFE 冷静一阵再爬回去。TDLib 的 "Too Many Requests: retry
// after N" 会把**整个队列**停住（同一个限流桶），所以一味开大反而更慢。
const MAX_ACTIVE_FAST: number = 6;
const MAX_ACTIVE_SAFE: number = 2;
// 撞限流后维持保守并发的时长，之后恢复。
const THROTTLE_COOLDOWN_MS: number = 30_000;
// A failed message is retried on a later request, but not in a tight loop.
const FAILURE_HOLD_MS: number = 60_000;

export class TranslationService {
  private client: TdClient;
  // '' means "translated, nothing to show" (result equals the original) —
  // cached like any other result so the row is never re-requested.
  private cache: Map<string, string> = new Map();
  private failedAt: Map<string, number> = new Map();
  private queue: Job[] = [];
  private queued: Set<string> = new Set();
  private active: number = 0;
  private backoffUntil: number = 0;
  // 上次撞上 flood-wait 的时刻，0 表示从没撞过。
  private throttledAt: number = 0;

  private maxActive(): number {
    if (this.throttledAt === 0 || Date.now() - this.throttledAt > THROTTLE_COOLDOWN_MS) {
      return MAX_ACTIVE_FAST;
    }
    return MAX_ACTIVE_SAFE;
  }

  constructor(client: TdClient) {
    this.client = client;
  }

  // Synchronous cache probe: null = no result yet (never requested, in flight,
  // or held after a failure).
  cached(chatId: number, messageId: number, editDate: number, lang: string): string | null {
    return this.cache.get(keyOf(chatId, messageId, editDate, lang)) ?? null;
  }

  // Idempotent: repeated requests for the same content version collapse into
  // one TDLib call, and everyone gets the same callback.
  request(chatId: number, messageId: number, editDate: number, lang: string,
    onDone: (text: string | null) => void): void {
    const key = keyOf(chatId, messageId, editDate, lang);
    const hit = this.cache.get(key);
    if (hit !== undefined) {
      onDone(hit);
      return;
    }
    const failedTime = this.failedAt.get(key);
    if (failedTime !== undefined && Date.now() - failedTime < FAILURE_HOLD_MS) {
      onDone(null);
      return;
    }
    if (this.queued.has(key)) {
      for (const job of this.queue) {
        if (job.key === key) {
          job.resolvers.push(onDone);
          return;
        }
      }
      // In flight (queued but no longer in the list): the result lands in the
      // cache momentarily; the next visible-range pass picks it up. Dropping
      // the callback here is fine — drivers poll, they don't await.
      onDone(null);
      return;
    }
    this.queued.add(key);
    this.queue.push({ key, chatId, messageId, lang, resolvers: [onDone] });
    this.pump();
  }

  // 失败行上的「重试」。清掉 60 秒冷却和瞬时态，调用方随后照常 request()
  // 即可——否则那次请求会被 FAILURE_HOLD_MS 静默挡掉。
  retry(chatId: number, messageId: number, editDate: number, lang: string): void {
    this.failedAt.delete(keyOf(chatId, messageId, editDate, lang));
    clearTranslationStatus(messageId);
  }

  private pump(): void {
    if (this.active >= this.maxActive() || this.queue.length === 0) {
      return;
    }
    const wait = this.backoffUntil - Date.now();
    if (wait > 0) {
      setTimeout((): void => this.pump(), wait + 50);
      return;
    }
    const job = this.queue.shift() as Job;
    this.active++;
    publishTranslating(job.messageId);
    const req: TdRequest = { '@type': 'translateMessageText' };
    req['chat_id'] = job.chatId;
    req['message_id'] = job.messageId;
    req['to_language_code'] = job.lang;
    this.client.send(req, 20000).then((result: TdObject): void => {
      const text = (result['text'] as string | undefined) ?? '';
      this.finish(job, text);
    }).catch((e: TdError): void => {
      // "Too Many Requests: retry after N" — quiet the whole queue, not just
      // this message; every queued request goes to the same rate bucket.
      const match = /retry after (\d+)/.exec(e.message);
      if (match !== null) {
        this.backoffUntil = Date.now() + (parseInt(match[1], 10) + 1) * 1000;
        this.throttledAt = Date.now();
      } else {
        this.failedAt.set(job.key, Date.now());
      }
      // 原始报错原样交给界面（用户要求）。限流是"稍后自动重来"，不是失败，
      // 所以那种情况保持「翻译中」，不弹错误。
      if (match === null) {
        publishTranslationFailed(job.messageId, e.message);
      }
      logE(`TranslationService: ${job.messageId} failed: ${e.message}`);
      this.finish(job, null, match !== null);
    });
  }

  private finish(job: Job, text: string | null, requeue: boolean = false): void {
    this.active--;
    this.queued.delete(job.key);
    if (text !== null) {
      this.cache.set(job.key, text);
      clearTranslationStatus(job.messageId);
    }
    if (requeue) {
      // Flood-waited, not failed: put it back so it retries after the backoff.
      this.queued.add(job.key);
      this.queue.unshift(job);
    } else {
      for (const resolve of job.resolvers) {
        resolve(text);
      }
    }
    this.pump();
  }
}

let instance: TranslationService | null = null;

export function getTranslationService(client: TdClient): TranslationService {
  if (instance === null) {
    instance = new TranslationService(client);
  }
  return instance;
}
