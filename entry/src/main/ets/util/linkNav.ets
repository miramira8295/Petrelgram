// A tapped link normalized to a full t.me URL suitable for TDLib's
// getMessageLinkInfo, or '' if it isn't a Telegram link at all (plain web
// links open in the system browser instead).
//
// Handles: https://t.me/<username>, https://t.me/<username>/<messageId>
// (channel post links, e.g. .../DocOfCard_Channel/2429), and @<username>.
export function normalizeTelegramLink(url: string): string {
  const raw = url.trim();
  if (raw.startsWith('@')) {
    const name = raw.substring(1);
    return isUsername(name) ? `https://t.me/${name}` : '';
  }
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  const slash = rest.indexOf('/');
  const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
  if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
    return '';
  }
  return raw;
}

// 应用内可解析的 Telegram 链接：tg:// 深链、@用户名、t.me/telegram.me/
// telegram.dog 全域名（含 addlist/addstickers/邀请链/消息链等一切路径）。
// 命中的链接**跳过「打开/复制」确认层**直接走应用内解析链（用户反馈：
// t.me 被当浏览器链接多弹一层）；解析不动的仍会经 onLinkUnresolved 的
// 内链判据挡在浏览器门外。外部 http 链接保持确认。
export function isTelegramInternalUrl(url: string): boolean {
  const raw = url.trim();
  return raw.startsWith('tg://') || raw.startsWith('tg:resolve') ||
    raw.startsWith('@') || normalizeTelegramLink(raw) !== '';
}

// Username for links that point at a chat/user directly — '@name' or a t.me
// link with a single path segment. '' for message links / invites / web URLs.
export function bareUsernameOf(url: string): string {
  const raw = url.trim();
  if (raw.startsWith('@')) {
    const name = raw.substring(1);
    return isUsername(name) ? name : '';
  }
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  const slash = rest.indexOf('/');
  const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
  if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
    return '';
  }
  if (slash < 0) {
    return '';
  }
  // Drop any query/fragment (bot start params, ?comment=, #anchor, …) before
  // splitting — otherwise t.me/<name>?start=xxx isn't recognized as a username
  // link and wrongly falls through to the browser.
  const seg = rest.substring(slash + 1);
  const clean = seg.split('?')[0].split('#')[0];
  const parts = clean.split('/').filter((p: string) => p.length > 0);
  if (parts.length !== 1 || parts[0].startsWith('+') || parts[0].toLowerCase() === 'joinchat') {
    return '';
  }
  return isUsername(parts[0]) ? parts[0] : '';
}

// Private-chat invite link (t.me/+<hash> or t.me/joinchat/<hash>) normalized
// with an https:// scheme for TDLib's checkChatInviteLink, or '' if the URL
// isn't an invite. t.me/+<digits only> is a phone-number link, not an invite
// (real invite hashes always contain letters), so it's excluded.
export function inviteLinkOf(url: string): string {
  const raw = url.trim();
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  const slash = rest.indexOf('/');
  const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
  if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
    return '';
  }
  if (slash < 0) {
    return '';
  }
  const clean = rest.substring(slash + 1).split('?')[0].split('#')[0];
  const parts = clean.split('/').filter((p: string) => p.length > 0);
  if (parts.length === 1 && parts[0].startsWith('+')) {
    const hash = parts[0].substring(1);
    return hash !== '' && !isAllDigits(hash) ? `https://t.me/+${hash}` : '';
  }
  if (parts.length === 2 && parts[0].toLowerCase() === 'joinchat' && parts[1] !== '') {
    return `https://t.me/joinchat/${parts[1]}`;
  }
  return '';
}

function telegramPathParts(url: string): string[] {
  const raw = url.trim();
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  const slash = rest.indexOf('/');
  const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
  if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
    return [];
  }
  if (slash < 0) {
    return [];
  }
  const clean = rest.substring(slash + 1).split('?')[0].split('#')[0];
  return clean.split('/').filter((part: string): boolean => part.length > 0);
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (_e) {
    return value;
  }
}

function validResourceToken(value: string): boolean {
  if (value.length === 0 || value.length > 160) {
    return false;
  }
  return value.indexOf('/') < 0 && value.indexOf('?') < 0 && value.indexOf('#') < 0;
}

// Shared chat-folder invite: https://t.me/addlist/<slug> or
// tg://addlist?slug=<slug>. Returns the canonical URL expected by TDLib.
export function chatFolderInviteLinkOf(url: string): string {
  const raw = url.trim();
  if (raw.startsWith('tg://addlist?')) {
    const slug = safeDecode(queryParamOf(raw.substring(raw.indexOf('?') + 1), 'slug'));
    return validResourceToken(slug) ? `https://t.me/addlist/${slug}` : '';
  }
  const parts = telegramPathParts(raw);
  if (parts.length !== 2 || parts[0].toLowerCase() !== 'addlist') {
    return '';
  }
  const slug = safeDecode(parts[1]);
  return validResourceToken(slug) ? `https://t.me/addlist/${slug}` : '';
}

export interface StickerSetLink {
  name: string;
  expectCustomEmoji: boolean;
}

// Sticker/custom-emoji set: t.me/addstickers/<name>, t.me/addemoji/<name>,
// plus their tg://addstickers?set= and tg://addemoji?set= equivalents.
export function stickerSetLinkOf(url: string): StickerSetLink | null {
  const raw = url.trim();
  if (raw.startsWith('tg://addstickers?') || raw.startsWith('tg://addemoji?')) {
    const expectCustomEmoji = raw.startsWith('tg://addemoji?');
    const name = safeDecode(queryParamOf(raw.substring(raw.indexOf('?') + 1), 'set'));
    return validResourceToken(name) ? { name, expectCustomEmoji } : null;
  }
  const parts = telegramPathParts(raw);
  if (parts.length !== 2) {
    return null;
  }
  const action = parts[0].toLowerCase();
  if (action !== 'addstickers' && action !== 'addemoji') {
    return null;
  }
  const name = safeDecode(parts[1]);
  return validResourceToken(name) ? { name, expectCustomEmoji: action === 'addemoji' } : null;
}

// A chat link that carries an action in its query string:
// t.me/<bot>?start=<payload>  → open the bot chat and auto-send /start <payload>
// t.me/<name>?text=<draft>    → open the chat with a prefilled draft
// tg://resolve?domain=<name>&start=/&text= is the deep-link equivalent.
export interface ChatLinkAction {
  username: string;
  startParam: string; // ?start= payload ('' = none)
  draftText: string;  // ?text= prefill ('' = none)
}

function queryParamOf(query: string, key: string): string {
  for (const pair of query.split('&')) {
    const eq = pair.indexOf('=');
    if (eq <= 0 || pair.substring(0, eq) !== key) {
      continue;
    }
    const raw = pair.substring(eq + 1).replace(/\+/g, ' ');
    try {
      return decodeURIComponent(raw);
    } catch (_e) {
      return raw; // malformed escape — use it verbatim rather than dropping it
    }
  }
  return '';
}

// Parse a username link whose query carries a start/text action; null when the
// link has no such action (plain username links keep their existing routing).
export function chatLinkActionOf(url: string): ChatLinkAction | null {
  const raw = url.trim();
  let rest = raw;
  const scheme = rest.indexOf('://');
  if (scheme >= 0) {
    rest = rest.substring(scheme + 3);
  }
  let username = '';
  let query = '';
  if (raw.startsWith('tg://') || raw.startsWith('tg:resolve')) {
    // tg://resolve?domain=<name>&start=... — the host segment IS the action.
    const q = rest.indexOf('?');
    if (q < 0 || !rest.substring(0, q).startsWith('resolve')) {
      return null;
    }
    query = rest.substring(q + 1).split('#')[0];
    username = queryParamOf(query, 'domain');
  } else {
    const slash = rest.indexOf('/');
    const host = (slash >= 0 ? rest.substring(0, slash) : rest).toLowerCase();
    if (host !== 't.me' && host !== 'telegram.me' && host !== 'telegram.dog') {
      return null;
    }
    if (slash < 0) {
      return null;
    }
    const seg = rest.substring(slash + 1);
    const q = seg.indexOf('?');
    if (q < 0) {
      return null;
    }
    query = seg.substring(q + 1).split('#')[0];
    const parts = seg.substring(0, q).split('/').filter((p: string) => p.length > 0);
    if (parts.length !== 1) {
      return null;
    }
    username = parts[0];
  }
  if (!isUsername(username)) {
    return null;
  }
  const startParam = queryParamOf(query, 'start');
  const draftText = queryParamOf(query, 'text');
  if (startParam === '' && draftText === '') {
    return null;
  }
  return { username, startParam, draftText };
}

function isAllDigits(s: string): boolean {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 48 || c > 57) {
      return false;
    }
  }
  return true;
}

function isUsername(name: string): boolean {
  if (name.length < 3 || name.length > 32) {
    return false;
  }
  for (let i = 0; i < name.length; i++) {
    const c = name.charCodeAt(i);
    const isDigit = c >= 48 && c <= 57;
    const isUpper = c >= 65 && c <= 90;
    const isLower = c >= 97 && c <= 122;
    const isUnderscore = c === 95;
    if (!isDigit && !isUpper && !isLower && !isUnderscore) {
      return false;
    }
  }
  return true;
}
