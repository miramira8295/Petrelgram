// 点了消息里的一个链接，该走哪一路。
//
// 前四种是应用自己合成的本地 scheme——渲染消息实体时把机器人命令、可复制的
// 号码、话题标签、无用户名的文本提及各自编码成一个假 URL，点击时再解回来。
// 它们不出网，纯字符串解析。
//
// 其余一律算"远程"：要么需要往返服务器才知道该开哪一页（消息链接、邀请链接、
// 贴纸包…），要么是普通网页。这一档由页面接手，先过 beginLinkNav 的闸门。
//
// 抽出来是因为这几条分支的边界很容易写错，而错了都很隐蔽：前缀没锚在开头会
// 让正文里恰好含 "tg-copy:" 的普通链接被劫走；载荷为空时若不拦住，会发出一条
// 空命令或跳到一个空话题；用户 id 解析失败得到 NaN，任何比较都是 false，
// 于是静默什么都不做——这几条都由单测钉住。

export const LINK_NONE: string = 'none';        // 认得出来但载荷无效，什么都不做
export const LINK_COMMAND: string = 'command';  // 发一条机器人命令
export const LINK_COPY: string = 'copy';        // 复制一段文本
export const LINK_HASHTAG: string = 'hashtag';  // 全局搜索这个话题标签
export const LINK_USER: string = 'user';        // 打开某个用户的资料页
export const LINK_REMOTE: string = 'remote';    // 交给页面走解析链

const PREFIX_COMMAND: string = 'tg-command:';
const PREFIX_COPY: string = 'tg-copy:';
const PREFIX_HASHTAG: string = 'tg-hashtag:';
const PREFIX_USER: string = 'tg://user?id=';

export interface LinkAction {
  kind: string;
  // 文本载荷：命令、要复制的内容、话题标签。其余为空串。
  text: string;
  // LINK_USER 的用户 id，其余为 0。
  userId: number;
}

function action(kind: string, text: string, userId: number): LinkAction {
  return { kind: kind, text: text, userId: userId };
}

export function linkActionOf(url: string): LinkAction {
  // 前缀一律锚在开头：正文里恰好含 "tg-copy:" 的普通网址不该被劫走。
  if (url.startsWith(PREFIX_COMMAND)) {
    const command: string = url.substring(PREFIX_COMMAND.length);
    return command !== '' ? action(LINK_COMMAND, command, 0) : action(LINK_NONE, '', 0);
  }
  if (url.startsWith(PREFIX_COPY)) {
    const text: string = url.substring(PREFIX_COPY.length);
    // 复制空串没有意义，但也不该落到远程去开浏览器。
    return text !== '' ? action(LINK_COPY, text, 0) : action(LINK_NONE, '', 0);
  }
  if (url.startsWith(PREFIX_HASHTAG)) {
    const tag: string = url.substring(PREFIX_HASHTAG.length);
    return tag !== '' ? action(LINK_HASHTAG, tag, 0) : action(LINK_NONE, '', 0);
  }
  if (url.startsWith(PREFIX_USER)) {
    // 解析失败得到 NaN，任何比较都是 false——显式收成 NONE，别让它往下漏。
    const uid: number = Number(url.substring(PREFIX_USER.length));
    return Number.isFinite(uid) && uid > 0
      ? action(LINK_USER, '', uid) : action(LINK_NONE, '', 0);
  }
  return action(LINK_REMOTE, '', 0);
}

// 显示出来的文字是不是藏着另一个网址（issue #169 第 6 条）。点普通链接直接打开，
// 只有文字和它实际指向的网址对不上时才先弹「打开 / 复制」让用户看清真网址——防钓鱼
// 的那一道，官方客户端也只对这种链接确认。比较时忽略协议、开头的 www.、结尾斜杠和
// 大小写：TDLib 的 url 实体原样是正文里那段字，常常不带协议。
function linkCompareForm(s: string): string {
  return s.trim().toLowerCase()
    .replace(new RegExp('^[a-z][a-z0-9+.-]*://'), '')
    .replace(new RegExp('^www\\.'), '')
    .replace(new RegExp('/+$'), '');
}

export function linkTextHidesUrl(displayText: string, url: string): boolean {
  const shown: string = linkCompareForm(displayText);
  return shown === '' || shown !== linkCompareForm(url);
}
