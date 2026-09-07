import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { InlineQueryPage, InlineResultRow, getInlineResults } from './BotApi';
import { logE } from '../util/log';

// GIF 搜索与「热门 GIF」。
//
// **Telegram 没有独立的 GIF 市场接口**——那个「市场」就是一个内联机器人。
// TDLib 给出它的用户名（选项 animation_search_bot_username，默认 "gif"），
// 之后完全按普通内联机器人查：空 query 拿到的是热门，带词就是搜索，结果是
// 一串 inlineQueryResultAnimation，选中用 sendInlineQueryResultMessage 发出去
// （BotApi.sendInlineResult）。
//
// 这一层只负责「问出 bot 是谁」和「查一页回来」，界面与下载留给调用方
// （pages/chat/GifPicker）。抽成独立文件是因为 GifPicker 本来就不小，而这套
// 解析逻辑与界面无关、也可能被别处复用。

// 机器人身份在一次运行里不会变，解析要两次往返（getOption + searchPublicChat），
// 所以缓存住。失败不缓存——网络恢复后还要能再试。
let cachedBotId: number = 0;
let pending: Promise<number> | null = null;

const DEFAULT_BOT: string = 'gif';

function searchBotUsername(): Promise<string> {
  const req: TdRequest = { '@type': 'getOption' };
  req['name'] = 'animation_search_bot_username';
  return getTdClient().send(req, 10000).then((opt: TdObject): string => {
    // optionValueString{value}；服务端没配时是 optionValueEmpty，退回官方默认。
    const value = (opt['value'] as string | undefined) ?? '';
    return value !== '' ? value : DEFAULT_BOT;
  }).catch((): string => DEFAULT_BOT);
}

// GIF 搜索机器人的 user_id。0 表示这台设备上解析不出来（离线、或者账号看不到
// 这个公开机器人），调用方据此退化成「只有已保存」。
export function animationSearchBotId(): Promise<number> {
  if (cachedBotId !== 0) {
    return Promise.resolve(cachedBotId);
  }
  if (pending !== null) {
    return pending;
  }
  const chain: Promise<number> = searchBotUsername().then((username: string): Promise<TdObject> => {
    const req: TdRequest = { '@type': 'searchPublicChat' };
    req['username'] = username;
    return getTdClient().send(req, 10000);
  }).then((chat: TdObject): number => {
    // 私聊的 chat.type 是 chatTypePrivate{user_id}，内联查询要的是 user_id 而
    // 不是 chat id（同一条判据见 ComposerSuggestionState 里 @bot 那条链）。
    const type = chat['type'] as TdObject | undefined;
    const botId: number = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
    cachedBotId = botId;
    pending = null;
    return botId;
  }).catch((e: Object): number => {
    pending = null;
    logE(`GifSearchApi.animationSearchBotId failed: ${e}`);
    return 0;
  });
  pending = chain;
  return chain;
}

// 只保留动图结果。文章/照片这些机器人一般不返回，但内联协议不禁止，
// 而 GIF 面板拿到一条文章结果既画不出来也发不对。
function animationsOnly(rows: InlineResultRow[]): InlineResultRow[] {
  return rows.filter((r: InlineResultRow): boolean => r.kind === 'animation');
}

// 查一页。query 为空 = 热门。chatId 是**当前会话**——内联协议要求带上它
// （机器人据此判断能不能在这里发），不是搜索条件。
export function searchGifs(chatId: number, query: string): Promise<InlineQueryPage> {
  return animationSearchBotId().then((botId: number): Promise<InlineQueryPage> => {
    if (botId === 0) {
      return Promise.resolve({ queryId: '', rows: [] } as InlineQueryPage);
    }
    return getInlineResults(botId, chatId, query);
  }).then((page: InlineQueryPage): InlineQueryPage => {
    return { queryId: page.queryId, rows: animationsOnly(page.rows) };
  });
}
