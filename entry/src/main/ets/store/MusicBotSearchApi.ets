import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import {
  MusicTrack, musicTrackFromInlineAudio, musicTrackFromMessage, musicTrackKey, parseMusicTrackKey,
  MusicTrackRef, trackKeyOf
} from '../util/musicTrackModel';
import { forgetBotSent, musicBotSentKey, rememberBotSent } from './MusicBotSentStore';
import { logE, logI } from '../util/log';

// 机器人音乐搜索（2026-09-20）。曲库只有「你的会话里出现过的音频消息」，
// 搜不到的歌从这里来：向一个支持内联查询的音乐机器人发 getInlineQueryResults，
// 拿回来的 inlineQueryResultAudio 直接就是一首歌。
//
// 【为什么这条路成立】内联结果里的 audio 对象带完整的 file，**不把消息发出去
// 也能 downloadFile**——2026-09-20 对 @LyBot 真机实测，三首全过（晴天 4.5MB /
// 青花瓷 4.0MB / Help! 2.3MB，各下前 64KB 成功）。这和 GIF 面板从
// inlineQueryResultAnimation 里取 file id 直接做循环预览是同一条路。
//
// 【为什么不是随便哪个音乐 bot 都行】同一天实测 @Music163bot 走不通：它只回
// inlineQueryResultArticle（没有文件），拿到歌要先私聊 /start <id> 让它去缓存。
// 换 bot 之前先用同样的办法验一遍「回的是不是 Audio」。
//
// 【播放 = 把它变成一条真消息】搜索结果本身只是内联结果，没有 chatId/messageId，
// 进不了合集、上不了下载中心、文件引用也没有可刷新的来源。所以点播放的那一刻
// 先 sendInlineQueryResultMessage 发进**收藏夹**，拿回真消息再解析成曲目——
// 之后这首歌和曲库里任何一首完全一样，后续逻辑一行都不用改。
// 代价是收藏夹里会留下一条带「通过 @bot」的可见记录（hide_via_bot 按 td_api
// 只对官方那三个搜索 bot 开放，去不掉）。同一首歌不会重复发，见 MusicBotSentStore。
//
// 【这个常量是唯一的切换点】没有官方的「音乐搜索机器人」选项可用
// （TDLib 只给 animation / photo / venue 三个 *_search_bot_username），
// 所以 bot 是我们指定的。要换就改这里。

export const MUSIC_BOT_USERNAME: string = 'LyBot';

// 实测每次固定 20 条且 next_offset 恒为空——**这个 bot 不分页**，
// 所以这里没有 offset 参数，也别去写翻页。
const MAX_RESULTS: number = 20;

// bot 超时的时候 TDLib 返回 502（td_api 明说）。给足时间但别无限等：
// 实测正常在 200–600ms 回来，20s 还没有基本就是 bot 挂了。
const QUERY_TIMEOUT_MS: number = 20000;

// 时长离谱的条目要扔掉。实测搜 "help" 回来过一条 duration=31319（8.7 小时）的
// "Help! (Remastered 2009)"——那是整张合辑被当成一首歌，放进曲库会把进度条
// 和「大小÷时长」估出来的码率全弄乱。3 小时以上一律当脏数据。
const MAX_PLAUSIBLE_DURATION_SEC: number = 3 * 3600;

let cachedBotId: number = 0;
let pending: Promise<number> | null = null;

// 机器人的 user_id。0 = 这台设备上解析不出来（离线，或者这个账号看不到它），
// 调用方据此把搜索源退化成「只有曲库」。
//
// 失败不缓存：网络恢复之后还要能再试（同 GifSearchApi 的判断）。
export function musicBotId(): Promise<number> {
  if (cachedBotId !== 0) {
    return Promise.resolve(cachedBotId);
  }
  if (pending !== null) {
    return pending;
  }
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = MUSIC_BOT_USERNAME;
  const chain: Promise<number> = getTdClient().send(req, 15000).then((chat: TdObject): number => {
    // 私聊的 chat.type 是 chatTypePrivate{user_id}；内联查询要的是 user_id
    // 而不是 chat id（同 GifSearchApi、ComposerSuggestionState 那两条链）。
    const type = chat['type'] as TdObject | undefined;
    const botId: number = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
    cachedBotId = botId;
    pending = null;
    return botId;
  }).catch((e: TdError): number => {
    pending = null;
    logE(`MusicBotSearchApi.searchPublicChat(${MUSIC_BOT_USERNAME}) failed: ${e.message}`);
    return 0;
  });
  pending = chain;
  return chain;
}

// 一次搜索的结果。queryId 是**发送**这一步要用的（sendInlineQueryResultMessage
// 同时要 query_id 和 result_id），而且它在服务端有寿命，所以随结果一起交出去，
// 过期了再重查一次（见 materializeBotTrack）。
export interface MusicBotSearchResult {
  queryId: string;
  tracks: MusicTrack[];
}

const EMPTY_RESULT: MusicBotSearchResult = { queryId: '', tracks: [] };

// 一次搜索。空查询直接返回空：实测空 query 这个 bot 回 0 条，没有「热门」概念，
// 白跑一趟还占一次限流额度。
export async function searchMusicBot(query: string): Promise<MusicBotSearchResult> {
  const q: string = query.trim();
  if (q === '') {
    return EMPTY_RESULT;
  }
  const botId: number = await musicBotId();
  if (botId === 0) {
    return EMPTY_RESULT;
  }
  const req: TdRequest = { '@type': 'getInlineQueryResults' };
  req['bot_user_id'] = botId;
  // chat_id 传 bot 自己的会话。实测可用；文档只说是「查询发出的会话」，
  // 音乐中心不在任何会话里，拿它当上下文最贴近语义。
  req['chat_id'] = botId;
  req['query'] = q;
  req['offset'] = '';
  try {
    const res: TdObject = await getTdClient().send(req, QUERY_TIMEOUT_MS);
    return { queryId: `${res['inline_query_id'] ?? ''}`, tracks: tracksOf(res) };
  } catch (e) {
    logE(`MusicBotSearchApi.getInlineQueryResults failed: ${(e as TdError).message}`);
    return EMPTY_RESULT;
  }
}

// 结果里 Audio 与 Article 混着来：Article 是 bot 还没转好的曲目
// （description 写着「准备曲目中…」），没有文件，当不了歌，直接丢掉。
function tracksOf(res: TdObject): MusicTrack[] {
  const rows: TdObject[] = (res['results'] as TdObject[] | undefined) ?? [];
  const out: MusicTrack[] = [];
  const seen: Set<string> = new Set<string>();
  let dropped: number = 0;
  for (const row of rows) {
    if (out.length >= MAX_RESULTS) {
      break;
    }
    const track: MusicTrack | null = musicTrackFromInlineAudio(row);
    if (track === null) {
      continue;
    }
    if (track.durationSec > MAX_PLAUSIBLE_DURATION_SEC) {
      dropped++;
      continue;
    }
    if (seen.has(track.botResultId)) {
      continue;
    }
    seen.add(track.botResultId);
    out.push(track);
  }
  if (dropped > 0) {
    logI(`[MusicBot] dropped ${dropped} over-long result(s)`);
  }
  return out;
}

// 换账号时清掉：user_id 是按账号发的。
export function resetMusicBotCache(): void {
  cachedBotId = 0;
  pending = null;
}


// ── 播放即落地：把内联结果变成收藏夹里的一条真音频消息 ──────────────────

// 发送用的超时。文件已经在 Telegram 服务器上（bot 传的），这一步只是建一条消息。
const SEND_TIMEOUT_MS: number = 25000;
// 等「临时 id → 真实 id」的上限。实测远小于这个数；超时就退回待确认的那条消息，
// 播放照常（file id 是真的），只是这一首暂时进不了合集。
const CONFIRM_TIMEOUT_MS: number = 8000;

// 落点：**这个 bot 自己的会话**，不是收藏夹（用户 2026-09-20 定的）。
// 这些消息本质是这个功能的草稿纸，堆在 bot 的对话里比堆在用户真正用来
// 存东西的收藏夹里干净。私聊的 chat id 就等于对方的 user id，但仍然走
// createPrivateChat 把会话建出来——没建过的 bot 直接发会被拒。
async function botChatId(): Promise<number> {
  const botId: number = await musicBotId();
  if (botId === 0) {
    return 0;
  }
  try {
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = botId;
    req['force'] = true;
    const chat: TdObject = await getTdClient().send(req, 15000);
    return (chat['id'] as number | undefined) ?? 0;
  } catch (e) {
    logE(`MusicBotSearchApi.botChatId failed: ${(e as TdError).message}`);
    return 0;
  }
}

// 发出去的消息一开始带的是**临时 id**（messageSendingStatePending），真实 id 要等
// updateMessageSendSucceeded。曲目键会被写进合集，拿临时 id 存下去就是一条永远
// 取不回来的记录，所以这里必须等。
//
// 【为什么要常驻监听 + 缓冲】2026-09-20 真机日志：同一次会话里发第二首必定
// 「send confirm timed out」。因为原来是等 send() 的 Promise 回来之后才挂监听，
// 而 TDLib 可能在那之前就把 update 发出去了——错过一次就是死等到超时。
// 改成：发之前就把监听挂上，没人认领的结果先存进缓冲，等待方后到也能捡走。
const recentSucceeded: Map<number, TdObject> = new Map<number, TdObject>();
const sendWaiters: Map<number, (m: TdObject) => void> = new Map<number, (m: TdObject) => void>();
let sendWatchUnsub: (() => void) | null = null;
// 缓冲上限。只为了兜住"update 早于等待方"这一瞬，不是历史记录。
const RECENT_SUCCEEDED_MAX: number = 32;

function ensureSendWatch(): void {
  if (sendWatchUnsub !== null) {
    return;
  }
  sendWatchUnsub = getTdClient().onUpdate('updateMessageSendSucceeded', (u: TdObject): void => {
    const oldId = u['old_message_id'] as number | undefined;
    const m = u['message'] as TdObject | undefined;
    if (oldId === undefined || m === undefined) {
      return;
    }
    const waiter = sendWaiters.get(oldId);
    if (waiter !== undefined) {
      sendWaiters.delete(oldId);
      waiter(m);
      return;
    }
    if (recentSucceeded.size >= RECENT_SUCCEEDED_MAX) {
      const oldest: number | undefined = recentSucceeded.keys().next().value;
      if (oldest !== undefined) {
        recentSucceeded.delete(oldest);
      }
    }
    recentSucceeded.set(oldId, m);
  });
}

function awaitRealMessage(sent: TdObject): Promise<TdObject> {
  const state = sent['sending_state'] as TdObject | undefined;
  if (state === undefined || (state['@type'] as string | undefined) !== 'messageSendingStatePending') {
    return Promise.resolve(sent);
  }
  const tempId: number = (sent['id'] as number | undefined) ?? 0;
  if (tempId === 0) {
    return Promise.resolve(sent);
  }
  // 已经到了、只是当时没人等：直接捡走。
  const early: TdObject | undefined = recentSucceeded.get(tempId);
  if (early !== undefined) {
    recentSucceeded.delete(tempId);
    return Promise.resolve(early);
  }
  return new Promise<TdObject>((resolve: (m: TdObject) => void): void => {
    let done: boolean = false;
    const finish = (m: TdObject): void => {
      if (done) {
        return;
      }
      done = true;
      sendWaiters.delete(tempId);
      resolve(m);
    };
    sendWaiters.set(tempId, finish);
    setTimeout((): void => {
      if (!done) {
        logE(`MusicBotSearchApi: send confirm timed out for temp id ${tempId}`);
      }
      finish(sent);
    }, CONFIRM_TIMEOUT_MS);
  });
}

async function sendResult(
  chatId: number, queryId: string, resultId: string
): Promise<TdObject | null> {
  const req: TdRequest = { '@type': 'sendInlineQueryResultMessage' };
  req['chat_id'] = chatId;
  req['query_id'] = queryId;
  req['result_id'] = resultId;
  // 静音 + 后台：这是应用替用户做的动作，不该弹通知。
  const options: TdObject = { '@type': 'messageSendOptions' };
  options['disable_notification'] = true;
  options['from_background'] = true;
  req['options'] = options;
  // hide_via_bot 只对官方那三个搜索 bot 开放，这里传 true 会被拒。
  req['hide_via_bot'] = false;
  try {
    return await getTdClient().send(req, SEND_TIMEOUT_MS);
  } catch (e) {
    logE(`MusicBotSearchApi.sendInlineQueryResultMessage failed: ${(e as TdError).message}`);
    return null;
  }
}

// 已经发过的那条还在不在。取不回来（用户删了）就忘掉记录，让调用方重发。
async function reuseSent(resultId: string): Promise<MusicTrack | null> {
  const key: string = musicBotSentKey(resultId);
  if (key === '') {
    return null;
  }
  const ref: MusicTrackRef | null = parseMusicTrackKey(key);
  if (ref === null) {
    forgetBotSent(resultId);
    return null;
  }
  const req: TdRequest = { '@type': 'getMessage' };
  req['chat_id'] = ref.chatId;
  req['message_id'] = ref.messageId;
  try {
    const message: TdObject = await getTdClient().send(req, 15000);
    const track: MusicTrack | null = musicTrackFromMessage(message);
    if (track === null) {
      forgetBotSent(resultId);
      return null;
    }
    return track;
  } catch (e) {
    // 消息没了：忘掉，下面会重发一条。
    forgetBotSent(resultId);
    return null;
  }
}

// 内联结果 → 收藏夹里的真曲目。返回 null 表示这一步失败，调用方应提示用户。
//
// 三步：先看这首发过没有（发过就直接用那条消息，不再堆一条）；没有就用搜索时
// 那个 queryId 发；queryId 过期了（服务端有寿命）就重查一次拿新的再发一次。
export async function materializeBotTrack(
  query: string, queryId: string, resultId: string, now: number
): Promise<MusicTrack | null> {
  if (resultId === '') {
    return null;
  }
  const reused: MusicTrack | null = await reuseSent(resultId);
  if (reused !== null) {
    return reused;
  }
  const chatId: number = await botChatId();
  if (chatId === 0) {
    return null;
  }
  // 必须在第一次 send 之前挂好：update 可能比 send 的返回值还早。
  ensureSendWatch();
  let sent: TdObject | null = queryId !== '' ? await sendResult(chatId, queryId, resultId) : null;
  if (sent === null) {
    // queryId 过期或压根没有：重查一次，拿新鲜的再发。
    const fresh: MusicBotSearchResult = await searchMusicBot(query);
    const still: boolean = fresh.tracks.some(
      (t: MusicTrack): boolean => t.botResultId === resultId);
    if (!still || fresh.queryId === '') {
      logE(`MusicBotSearchApi: result ${resultId} no longer in results for "${query}"`);
      return null;
    }
    sent = await sendResult(chatId, fresh.queryId, resultId);
  }
  if (sent === null) {
    return null;
  }
  const real: TdObject = await awaitRealMessage(sent);
  const track: MusicTrack | null = musicTrackFromMessage(real);
  if (track === null) {
    logE(`MusicBotSearchApi: sent message is not an audio message`);
    return null;
  }
  // 临时 id 不写进去：那条记录取不回来，反而挡住下次重发。
  const state = real['sending_state'] as TdObject | undefined;
  if (state === undefined) {
    rememberBotSent(resultId, musicTrackKey(track.chatId, track.messageId), now);
  }
  logI(`[MusicBot] materialized ${resultId} -> ${trackKeyOf(track)}`);
  return track;
}
