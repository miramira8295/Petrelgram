import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { ChatBotHit, isChatBotListMessage, parseChatBotList } from '../util/musicChatBotParse';
import { MusicTrack, musicTrackFromMessage } from '../util/musicTrackModel';
import { logE, logI } from '../util/log';

// 会话式音乐机器人（2026-09-20）。和 MusicBotSearchApi 是**两条不同的投递链**：
//
//   MusicBotSearchApi（@LyBot）：内联结果里直接带文件，一次 getInlineQueryResults
//                               就拿到歌，发消息只是为了拿持久身份。
//   这里（@music_v1bot 一类）：内联模式**只搜不给文件**（四次不同角度实测
//                               audio=0），拿歌只能在私聊里走它的对话协议。
//
// 【协议】真机样本：
//   我们 → /search 想你就写信 (Live)
//   bot  → 「搜索源 网易云音乐，当前为第1页，搜索结果如下：」+ 1..8 编号列表
//          + 一排内联键盘按钮 [1][2]…[8]
//   我们 → getCallbackQueryAnswer 点其中一个
//   bot  → 一条音频消息（很快）
//
// 【为什么搜索必须是"按需"而不是随输入自动跑】每搜一次就往 bot 会话里**真的发一条
// 消息**。跟着输入框防抖自动搜，等于用户敲几个字就在那个会话里堆几条 /search。
// 所以界面上是一颗要手点的按钮，不是输入即搜。
//
// 【脆在哪儿，明说】列表格式是 bot 自己排的、没有版本、没有契约。解析不出来时
// 这里返回**空数组 + 一条 logE**，调用方必须报「读不懂回复」而不是「没搜到」——
// 否则 bot 哪天改了版式，我们永远察觉不到，用户只会看到点了没反应。

export const MUSIC_CHAT_BOT_USERNAME: string = 'music_v1bot';

const SEND_TIMEOUT_MS: number = 20000;
// 等 bot 回列表。用户实测「很快」，20s 足够，超了基本是 bot 挂了或被限流。
const LIST_TIMEOUT_MS: number = 20000;
// 等音频。bot 要现去源站抓，给宽一点。
const AUDIO_TIMEOUT_MS: number = 45000;
// 收件缓冲：等待方挂上之前先到的消息也要能被捡走（同 MusicBotSearchApi 里
// 那次「第二首必定 confirm 超时」的教训）。
const INBOX_MAX: number = 32;

interface ChatBotSession {
  chatId: number;
  botId: number;
}

let cached: ChatBotSession | null = null;

// ── 收件监听。发之前就挂上，别等发完再挂。 ──────────────────────────────
const inbox: TdObject[] = [];
type InboxWaiter = (m: TdObject) => void;
const waiters: Set<InboxWaiter> = new Set<InboxWaiter>();
let inboxUnsub: (() => void) | null = null;
let watchedChatId: number = 0;

function ensureInboxWatch(chatId: number): void {
  if (inboxUnsub !== null && watchedChatId === chatId) {
    return;
  }
  if (inboxUnsub !== null) {
    inboxUnsub();
    inboxUnsub = null;
  }
  watchedChatId = chatId;
  inbox.length = 0;
  inboxUnsub = getTdClient().onUpdate('updateNewMessage', (u: TdObject): void => {
    const m = u['message'] as TdObject | undefined;
    if (m === undefined) {
      return;
    }
    if ((m['chat_id'] as number | undefined) !== watchedChatId) {
      return;
    }
    if ((m['is_outgoing'] as boolean | undefined) === true) {
      return;   // 自己发的那条 /search
    }
    // 先给等待方，没人要就进缓冲。
    let taken: boolean = false;
    waiters.forEach((w: InboxWaiter): void => {
      if (!taken) {
        taken = true;
        w(m);
      }
    });
    if (taken) {
      return;
    }
    if (inbox.length >= INBOX_MAX) {
      inbox.shift();
    }
    inbox.push(m);
  });
}

// 等一条满足条件的入站消息。先翻缓冲（可能已经到了），再挂等待方。
function awaitIncoming(
  match: (m: TdObject) => boolean, timeoutMs: number, what: string
): Promise<TdObject | null> {
  for (let i = 0; i < inbox.length; i++) {
    if (match(inbox[i])) {
      const hit: TdObject = inbox[i];
      inbox.splice(i, 1);
      return Promise.resolve(hit);
    }
  }
  return new Promise<TdObject | null>((resolve: (m: TdObject | null) => void): void => {
    let done: boolean = false;
    const waiter: InboxWaiter = (m: TdObject): void => {
      if (done || !match(m)) {
        // 不匹配的（比如 bot 先回一句提示）放回缓冲，别吞掉。
        if (!done) {
          if (inbox.length >= INBOX_MAX) {
            inbox.shift();
          }
          inbox.push(m);
        }
        return;
      }
      done = true;
      waiters.delete(waiter);
      resolve(m);
    };
    waiters.add(waiter);
    setTimeout((): void => {
      if (done) {
        return;
      }
      done = true;
      waiters.delete(waiter);
      logE(`MusicChatBotApi: timed out waiting for ${what}`);
      resolve(null);
    }, timeoutMs);
  });
}

// ── 会话准备 ────────────────────────────────────────────────────────────

async function session(): Promise<ChatBotSession | null> {
  if (cached !== null) {
    return cached;
  }
  try {
    const find: TdRequest = { '@type': 'searchPublicChat' };
    find['username'] = MUSIC_CHAT_BOT_USERNAME;
    const chat: TdObject = await getTdClient().send(find, 15000);
    const type = chat['type'] as TdObject | undefined;
    const botId: number = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
    const chatId: number = (chat['id'] as number | undefined) ?? 0;
    if (botId === 0 || chatId === 0) {
      return null;
    }
    // 首次要 /start（用户 2026-09-20 实测）。判据是这个会话还没有任何消息。
    if ((chat['last_message'] as TdObject | undefined) === undefined) {
      const start: TdRequest = { '@type': 'sendBotStartMessage' };
      start['bot_user_id'] = botId;
      start['chat_id'] = chatId;
      start['parameter'] = '';
      await getTdClient().send(start, SEND_TIMEOUT_MS);
      logI(`[ChatBot] started @${MUSIC_CHAT_BOT_USERNAME}`);
    }
    cached = { chatId: chatId, botId: botId };
    return cached;
  } catch (e) {
    logE(`MusicChatBotApi.session failed: ${(e as TdError).message}`);
    return null;
  }
}

async function sendText(chatId: number, text: string): Promise<boolean> {
  const formatted: TdObject = { '@type': 'formattedText' };
  formatted['text'] = text;
  const content: TdObject = { '@type': 'inputMessageText' };
  content['text'] = formatted;
  const options: TdObject = { '@type': 'messageSendOptions' };
  options['disable_notification'] = true;
  options['from_background'] = true;
  const req: TdRequest = { '@type': 'sendMessage' };
  req['chat_id'] = chatId;
  req['input_message_content'] = content;
  req['options'] = options;
  try {
    await getTdClient().send(req, SEND_TIMEOUT_MS);
    return true;
  } catch (e) {
    logE(`MusicChatBotApi.sendMessage failed: ${(e as TdError).message}`);
    return false;
  }
}

// ── 对外的两步 ──────────────────────────────────────────────────────────

export interface ChatBotSearchOutcome {
  // 列表所在消息的 id；点按钮要用。
  listMessageId: number;
  hits: ChatBotHit[];
  // '' = 成功。非空是给用户看的失败原因键（调用方转成文案）。
  error: string;
}

export const CHAT_BOT_ERR_OFFLINE: string = 'offline';
export const CHAT_BOT_ERR_TIMEOUT: string = 'timeout';
export const CHAT_BOT_ERR_UNREADABLE: string = 'unreadable';

const EMPTY_OUTCOME: ChatBotSearchOutcome = { listMessageId: 0, hits: [], error: '' };

// 第一步：发 /search，等它回那条带编号按钮的列表。
export async function chatBotSearch(query: string): Promise<ChatBotSearchOutcome> {
  const q: string = query.trim();
  if (q === '') {
    return EMPTY_OUTCOME;
  }
  const s: ChatBotSession | null = await session();
  if (s === null) {
    return { listMessageId: 0, hits: [], error: CHAT_BOT_ERR_OFFLINE };
  }
  ensureInboxWatch(s.chatId);
  if (!await sendText(s.chatId, `/search ${q}`)) {
    return { listMessageId: 0, hits: [], error: CHAT_BOT_ERR_OFFLINE };
  }
  const reply: TdObject | null = await awaitIncoming(
    (m: TdObject): boolean => isChatBotListMessage(m), LIST_TIMEOUT_MS, 'search list');
  if (reply === null) {
    // 没等到能解析的列表。可能是超时，也可能 bot 回了我们读不懂的东西——
    // 两种都不能说成"没搜到"。
    return { listMessageId: 0, hits: [], error: CHAT_BOT_ERR_TIMEOUT };
  }
  const hits: ChatBotHit[] = parseChatBotList(reply);
  if (hits.length === 0) {
    logE(`MusicChatBotApi: reply parsed to zero hits (format changed?)`);
    return { listMessageId: 0, hits: [], error: CHAT_BOT_ERR_UNREADABLE };
  }
  return {
    listMessageId: (reply['id'] as number | undefined) ?? 0, hits: hits, error: ''
  };
}

// 第二步：点那个编号按钮，等它把音频发过来。
export async function chatBotFetch(
  listMessageId: number, hit: ChatBotHit
): Promise<MusicTrack | null> {
  const s: ChatBotSession | null = await session();
  if (s === null || listMessageId === 0) {
    return null;
  }
  ensureInboxWatch(s.chatId);
  const payload: TdObject = { '@type': 'callbackQueryPayloadData' };
  // data 是 bytes，JSON 接口里就是 base64；原样回传，不要解码。
  payload['data'] = hit.callbackData;
  const req: TdRequest = { '@type': 'getCallbackQueryAnswer' };
  req['chat_id'] = s.chatId;
  req['message_id'] = listMessageId;
  req['payload'] = payload;
  try {
    await getTdClient().send(req, SEND_TIMEOUT_MS);
  } catch (e) {
    logE(`MusicChatBotApi.getCallbackQueryAnswer failed: ${(e as TdError).message}`);
    return null;
  }
  const audio: TdObject | null = await awaitIncoming((m: TdObject): boolean => {
    const c = m['content'] as TdObject | undefined;
    return c !== undefined && (c['@type'] as string | undefined) === 'messageAudio';
  }, AUDIO_TIMEOUT_MS, 'audio reply');
  if (audio === null) {
    return null;
  }
  const track: MusicTrack | null = musicTrackFromMessage(audio);
  if (track === null) {
    logE(`MusicChatBotApi: audio reply did not parse into a track`);
    return null;
  }
  logI(`[ChatBot] fetched "${hit.label}" -> ${track.chatId}_${track.messageId}`);
  return track;
}

// 换账号时清掉：chat id / bot id 都是按账号发的。
export function resetMusicChatBot(): void {
  cached = null;
  if (inboxUnsub !== null) {
    inboxUnsub();
    inboxUnsub = null;
  }
  watchedChatId = 0;
  inbox.length = 0;
  waiters.clear();
}
