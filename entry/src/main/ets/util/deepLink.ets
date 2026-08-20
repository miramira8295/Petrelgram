import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { openTelegramLink } from './openTelegramLink';
import { navigateToChat } from './chatNav';

// Incoming deep links arrive as tg:// URIs (a browser https://t.me link can't
// hand off to a third-party client — see module.json5). Map the tg:// forms
// onto the t.me URL shape openTelegramLink already routes, then reuse that one
// shared router so deep links behave exactly like tapping an in-message link.

// Value of `key` in a `a=1&b=2` query string, URI-decoded ('' if absent).
function queryParam(query: string, key: string): string {
  for (const pair of query.split('&')) {
    const eq = pair.indexOf('=');
    if (eq < 0) {
      continue;
    }
    if (pair.substring(0, eq) === key) {
      try {
        return decodeURIComponent(pair.substring(eq + 1));
      } catch (e) {
        return pair.substring(eq + 1);
      }
    }
  }
  return '';
}

// —— tg://openmessage ——
//
// 给自建 Web Push 中转服务用的跳转入口：推送里带上这个 URL，点通知就能直接
// 落到具体会话。参数名刻意和 Telegram 推送 payload 的 `custom` 字段一一对应，
// 中转服务原样抄过来即可，不需要懂下面这些换算。
//
//   tg://openmessage?from_id=<用户id>&msg_id=<服务端消息id>     私聊
//   tg://openmessage?chat_id=<基础群id>&msg_id=<...>            基础群
//   tg://openmessage?channel_id=<频道id>&msg_id=<...>           超级群/频道
//
// `user_id` 是 `from_id` 的别名（真实 Telegram 客户端用这个名字）。msg_id 可
// 省略，省略时只打开会话不跳转到具体消息。
//
// 换算依据 TDLib 源码，push 的 custom 给的是原始 id，td_api 用的是另一套：
//   DialogId.h:27          ZERO_CHANNEL_ID = -1000000000000
//   MessageId.h:27         SERVER_ID_SHIFT = 20
const ZERO_CHANNEL_ID: number = -1000000000000;
// 注意必须用乘法：JS 的位运算是 32 位的，`<< 20` 会直接溢出。
const SERVER_MESSAGE_ID_SCALE: number = 1048576; // 1 << 20

export interface OpenMessageTarget {
  chatId: number;
  messageId: number; // td_api 消息 id（已换算）；0 表示只打开会话
}

// 严格的十进制整数解析：queryParam 拿到的是任意用户输入，parseInt 会把
// "12abc" 读成 12，这里不接受这种。
function intParam(query: string, key: string): number {
  const raw = queryParam(query, key).trim();
  if (raw === '' || !/^-?\d+$/.test(raw)) {
    return 0;
  }
  const value = Number(raw);
  return Number.isSafeInteger(value) ? value : 0;
}

export function parseOpenMessageLink(uri: string): OpenMessageTarget | null {
  if (!uri.startsWith('tg://')) {
    return null;
  }
  const rest = uri.substring('tg://'.length);
  const q = rest.indexOf('?');
  if (q < 0 || rest.substring(0, q) !== 'openmessage') {
    return null;
  }
  const query = rest.substring(q + 1);

  let chatId: number = 0;
  const channelId: number = intParam(query, 'channel_id');
  const basicGroupId: number = intParam(query, 'chat_id');
  const userId: number = intParam(query, 'from_id') !== 0
    ? intParam(query, 'from_id') : intParam(query, 'user_id');
  if (channelId > 0) {
    chatId = ZERO_CHANNEL_ID - channelId;
  } else if (basicGroupId > 0) {
    chatId = -basicGroupId;
  } else if (userId > 0) {
    chatId = userId;
  } else {
    return null;
  }

  const serverMessageId: number = intParam(query, 'msg_id');
  const messageId: number = serverMessageId > 0 ? serverMessageId * SERVER_MESSAGE_ID_SCALE : 0;
  return { chatId, messageId };
}

// tg://resolve?domain=foo&post=12 → https://t.me/foo/12
// tg://resolve?domain=foo         → https://t.me/foo
// tg://join?invite=HASH           → https://t.me/+HASH
// tg://user?id=123 and anything else are left untouched — openTelegramLink
// handles tg://user directly and falls back to the browser for the rest.
// 系统递过来的可能是 `tg:resolve?domain=x` —— **没有双斜杠**。
//
// 这在 URI 语法上完全合法：`//` 只有在有 authority 段时才需要，而 tg 链接
// 的 authority 是空的，华为浏览器（或系统的 want 规范化）会把它省掉。实测
// want.uri = "tg:resolve?domain=Petrelgram"。
//
// 下游所有解析都假设 `tg://`，所以在最外层补齐一次，而不是让每个调用点各自
// 判断两种形态（linkNav 里已经出现过 `startsWith('tg:resolve')` 这种窄补丁，
// 就是这么来的）。
export function normalizeTgScheme(uri: string): string {
  if (uri.startsWith('tg://') || !uri.startsWith('tg:')) {
    return uri;
  }
  return `tg://${uri.substring('tg:'.length)}`;
}

export function tgSchemeToUrl(rawUri: string): string {
  const uri = normalizeTgScheme(rawUri);
  if (!uri.startsWith('tg://')) {
    return uri;
  }
  const rest = uri.substring('tg://'.length);
  const q = rest.indexOf('?');
  const action = q >= 0 ? rest.substring(0, q) : rest;
  const query = q >= 0 ? rest.substring(q + 1) : '';
  if (action === 'resolve') {
    const domain = queryParam(query, 'domain');
    if (domain === '') {
      return uri;
    }
    const post = queryParam(query, 'post');
    return post !== '' ? `https://t.me/${domain}/${post}` : `https://t.me/${domain}`;
  }
  if (action === 'join') {
    const invite = queryParam(query, 'invite');
    return invite !== '' ? `https://t.me/+${invite}` : uri;
  }
  return uri;
}

// Route a raw incoming deep-link URI into the app.
export function handleIncomingLink(context: common.UIAbilityContext, rawUri: string): void {
  const uri = normalizeTgScheme(rawUri.trim());
  console.warn(`[LinkDiag] handleIncomingLink raw=${rawUri} -> ${tgSchemeToUrl(uri)}`);
  if (uri === '') {
    return;
  }
  // openmessage 走本地路由而不是 t.me —— 它带的是数字 id，没有对应的公开链接
  // 形式（私聊和无用户名的群根本没有 t.me 地址）。
  const target = parseOpenMessageLink(uri);
  if (target !== null) {
    const params: Record<string, Object> = { 'chatId': target.chatId };
    if (target.messageId > 0) {
      params['jumpTo'] = target.messageId;
    }
    navigateToChat(params);
    return;
  }
  // allowBrowser=false: a deep link that fails to resolve must NOT re-open the
  // system browser — that bounces browser → app → browser. Fail with a toast.
  openTelegramLink(context, tgSchemeToUrl(uri), false);
}
