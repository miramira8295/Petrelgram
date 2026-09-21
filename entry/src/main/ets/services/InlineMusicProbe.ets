import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logI } from '../util/log';

// TEMPORARY probe (2026-09-20): music-bot feasibility calibration.
//   1. does the bot support inline queries (userTypeBot.is_inline)
//   2. are the results inlineQueryResultAudio or just Article
//   3. can the file id be downloaded WITHOUT sending a message
//   4. is there any lyrics-bearing field
// Log prefix [MBProbe]. ASCII log text on purpose: services/ is an
// i18n-migrated directory and the checker rejects Chinese literals there.

const TAG: string = '[MBProbe]';
const CHUNK: number = 700;

function logJson(label: string, value: Object): void {
  let text: string = '';
  try {
    text = JSON.stringify(value);
  } catch (e) {
    text = `<stringify failed: ${e}>`;
  }
  if (text.length <= CHUNK) {
    logI(`${TAG} ${label} ${text}`);
    return;
  }
  const total: number = Math.ceil(text.length / CHUNK);
  for (let i = 0; i < total; i++) {
    logI(`${TAG} ${label} [${i + 1}/${total}] ${text.substring(i * CHUNK, (i + 1) * CHUNK)}`);
  }
}

function sniffLyrics(node: Object | undefined, path: string, hits: string[]): void {
  if (node === undefined || node === null || hits.length >= 8) {
    return;
  }
  const record = node as Record<string, Object>;
  for (const key of Object.keys(record)) {
    const child: Object = record[key];
    const lower: string = key.toLowerCase();
    if (lower.includes('lyric')) {
      hits.push(`${path}.${key}=${JSON.stringify(child).substring(0, 200)}`);
    } else if (lower.includes('caption') || lower.includes('description')) {
      hits.push(`${path}.${key}=${JSON.stringify(child).substring(0, 160)}`);
    } else if (typeof child === 'object' && key !== 'album_cover_minithumbnail') {
      sniffLyrics(child, `${path}.${key}`, hits);
    }
  }
}

async function send(req: TdRequest, ms: number, what: string): Promise<TdObject | null> {
  try {
    return await getTdClient().send(req, ms);
  } catch (e) {
    logI(`${TAG} ${what} FAILED: ${(e as TdError).message}`);
    return null;
  }
}

async function tryDownload(fileId: number): Promise<void> {
  const req: TdRequest = { '@type': 'downloadFile' };
  req['file_id'] = fileId;
  req['priority'] = 1;
  req['offset'] = 0;
  req['limit'] = 65536;
  req['synchronous'] = true;
  const file: TdObject | null = await send(req, 40000, `downloadFile(${fileId})`);
  if (file === null) {
    return;
  }
  const local = file['local'] as TdObject | undefined;
  logI(`${TAG} downloadFile(${fileId}) OK size=${file['size']}`
    + ` prefix=${local !== undefined ? local['downloaded_prefix_size'] : '?'}`
    + ` path=${local !== undefined ? local['path'] : '?'}`);
}

export async function probeMusicBot(username: string, query: string): Promise<void> {
  logI(`${TAG} ==== start @${username} q="${query}" ====`);
  const chatReq: TdRequest = { '@type': 'searchPublicChat' };
  chatReq['username'] = username;
  const chat: TdObject | null = await send(chatReq, 15000, `searchPublicChat(${username})`);
  if (chat === null) {
    return;
  }
  const chatId: number = (chat['id'] as number | undefined) ?? 0;
  const ctype = chat['type'] as TdObject | undefined;
  const botId: number = ctype !== undefined ? ((ctype['user_id'] as number | undefined) ?? 0) : 0;
  logI(`${TAG} chatId=${chatId} botUserId=${botId} title=${chat['title']}`);
  if (botId === 0) {
    logI(`${TAG} no user_id, stop`);
    return;
  }

  const userReq: TdRequest = { '@type': 'getUser' };
  userReq['user_id'] = botId;
  const user: TdObject | null = await send(userReq, 15000, 'getUser');
  const utype = user !== null ? (user['type'] as TdObject | undefined) : undefined;
  logI(`${TAG} is_inline=${utype !== undefined ? utype['is_inline'] : '?'}`
    + ` placeholder=${utype !== undefined ? utype['inline_query_placeholder'] : '?'}`
    + ` guest=${utype !== undefined ? utype['supports_guest_queries'] : '?'}`);

  const q: TdRequest = { '@type': 'getInlineQueryResults' };
  q['bot_user_id'] = botId;
  q['chat_id'] = chatId;
  q['query'] = query;
  q['offset'] = '';
  const res: TdObject | null = await send(q, 25000, 'getInlineQueryResults');
  if (res === null) {
    return;
  }
  const rows: TdObject[] = (res['results'] as TdObject[] | undefined) ?? [];
  const button = res['button'] as TdObject | undefined;
  logI(`${TAG} n=${rows.length} nextOffset="${res['next_offset']}"`
    + ` button=${button !== undefined ? JSON.stringify(button) : 'null'}`);

  let audioCount: number = 0;
  const kinds: string[] = [];
  for (const r of rows) {
    const t: string = `${r['@type']}`;
    kinds.push(t.replace('inlineQueryResult', ''));
    if (t === 'inlineQueryResultAudio') {
      audioCount++;
    }
  }
  logI(`${TAG} audio=${audioCount}/${rows.length} kinds=${kinds.join(',')}`);

  for (let i = 0; i < Math.min(1, rows.length); i++) {
    logJson(`r${i}`, rows[i]);
  }
  for (let i = 0; i < Math.min(3, rows.length); i++) {
    const hits: string[] = [];
    sniffLyrics(rows[i], `r${i}`, hits);
    logI(`${TAG} r${i} lyricSniff=${hits.length === 0 ? '(none)' : hits.join(' | ')}`);
  }

  for (const r of rows) {
    const audio = r['audio'] as TdObject | undefined;
    const file = audio !== undefined ? (audio['audio'] as TdObject | undefined) : undefined;
    const fileId: number = file !== undefined ? ((file['id'] as number | undefined) ?? 0) : 0;
    if (fileId > 0) {
      const hasMini = audio!['album_cover_minithumbnail'] !== undefined;
      logI(`${TAG} audio title="${audio!['title']}" performer="${audio!['performer']}"`
        + ` dur=${audio!['duration']} mime=${audio!['mime_type']} mini=${hasMini}`);
      await tryDownload(fileId);
      break;
    }
  }
  logI(`${TAG} ==== done ====`);
}

export async function probeMusicSequence(username: string, queries: string[]): Promise<void> {
  for (const q of queries) {
    await probeMusicBot(username, q);
  }
  logI(`${TAG} ######## sequence finished (${queries.length}) ########`);
}

// ── 第二个问题（2026-09-20）：机器人搜来的歌能不能加进合集 ─────────────
//
// 合集存的是曲目键，取歌走 getMessage —— 机器人结果没有消息，所以现在加不了。
// 唯一可能的持久标识是 remoteFile.id，td_api 原话：「Can be used by the current
// user across application restarts or even from other devices」。
// 但同一段文档又说 getRemoteFile「the file can be used only if it is still
// accessible to the user」，对不来自消息的文件到底算不算数，文档没说，只能实测。
//
// 这里传入的是 45 分钟前那次内联查询抓到的 remote.id，中间应用重装重启过数次，
// 也没有再发过同样的内联查询 —— 正是"存下来隔天再用"的场景。
export async function probeRemoteFile(remoteId: string, label: string): Promise<void> {
  logI(`${TAG} ==== remote ${label} ====`);
  const req: TdRequest = { '@type': 'getRemoteFile' };
  req['remote_file_id'] = remoteId;
  req['file_type'] = { '@type': 'fileTypeAudio' } as TdObject;
  const file: TdObject | null = await send(req, 20000, 'getRemoteFile');
  if (file === null) {
    logI(`${TAG} remote ${label}: getRemoteFile rejected -> collections CANNOT use it`);
    return;
  }
  const fileId: number = (file['id'] as number | undefined) ?? 0;
  logI(`${TAG} remote ${label}: fileId=${fileId} size=${file['size']}`
    + ` expected=${file['expected_size']}`);
  if (fileId <= 0) {
    return;
  }
  await tryDownload(fileId);
}

export async function probeRemoteSequence(): Promise<void> {
  // 都取自 10:15 那轮 @LyBot 的真机抓取。
  await probeRemoteFile(
    'CQACAgIAAxUAAWqvQbfvVeRE2682_ngQU4_HQ4F0AAJWCAAC4IwRScmJC6ZoLVDdPAQ', 'qingtian-4.5MB');
  await probeRemoteFile(
    'CQACAgIAAxUAAWqvQbkULvCnHf8q75gIJv8-AAEVpQACgKoAAhm8QUhbfFjSRXtOozwE', 'help-2.2MB');
  logI(`${TAG} ######## remote sequence finished ########`);
}
