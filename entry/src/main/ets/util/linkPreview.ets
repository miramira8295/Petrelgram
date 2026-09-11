import { str } from './strings';
import {
  normalizeTelegramLink, inviteLinkOf, bareUsernameOf,
  chatFolderInviteLinkOf, stickerSetLinkOf
} from './linkNav';

export interface LinkPreviewPresentation {
  kind: string; // web | telegramMessage | telegramChat | telegramInvite | telegramResource | unavailable
  actionLabel: string;
  siteLabel: string;
  isTelegram: boolean;
  actionable: boolean;
}

function withoutScheme(value: string): string {
  const scheme: number = value.indexOf('://');
  return scheme >= 0 ? value.substring(scheme + 3) : value;
}

export function linkPreviewDomain(url: string): string {
  const raw: string = url.trim();
  if (raw === '' || raw.startsWith('@')) {
    return raw.startsWith('@') ? 'Telegram' : '';
  }
  const rest: string = withoutScheme(raw);
  const endCandidates: number[] = [rest.indexOf('/'), rest.indexOf('?'), rest.indexOf('#')]
    .filter((index: number): boolean => index >= 0);
  let end: number = rest.length;
  for (const candidate of endCandidates) {
    end = Math.min(end, candidate);
  }
  let host: string = rest.substring(0, end).toLowerCase();
  if (host.startsWith('www.')) {
    host = host.substring(4);
  }
  return host;
}

function telegramPathParts(url: string): string[] {
  const rest: string = withoutScheme(url.trim());
  const slash: number = rest.indexOf('/');
  if (slash < 0) {
    return [];
  }
  const clean: string = rest.substring(slash + 1).split('?')[0].split('#')[0];
  return clean.split('/').filter((part: string): boolean => part !== '');
}

function isPositiveInteger(value: string): boolean {
  if (value === '') {
    return false;
  }
  for (let index: number = 0; index < value.length; index++) {
    const code: number = value.charCodeAt(index);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

function isTelegramMessageLink(url: string, previewType: string): boolean {
  if (previewType.toLowerCase().indexOf('message') >= 0) {
    return true;
  }
  const parts: string[] = telegramPathParts(url);
  if (parts.length < 2) {
    return false;
  }
  // Public posts: t.me/<channel>/<messageId>; private posts:
  // t.me/c/<internalChatId>/<messageId>.
  return isPositiveInteger(parts[parts.length - 1]);
}

// 结果记忆表。
//
// 【为什么】(2026-09-11 帧 trace) linkPreviewCard 一次构建里 linkPresentation()
// 被调 11 次（compactTelegramPreview、动作图标、动作文案、accessibilityText、
// enabled…各要一次），每次都重跑一遍 URL 解析 + 若干次 str() + new 一个对象，
// 合计 56.3ms。同一条消息的三个入参在它整个生命周期里一个字都不会变。
//
// 语言切换会改 str() 的结果，所以 appLanguage 在调 invalidateStringCache() 的
// 同一句里清这张表（clearLinkPreviewPresentationCache）。
const PRESENTATION_CACHE_LIMIT: number = 512;
const presentationCache: Map<string, LinkPreviewPresentation> =
  new Map<string, LinkPreviewPresentation>();

export function clearLinkPreviewPresentationCache(): void {
  presentationCache.clear();
}

export function linkPreviewPresentation(url: string, previewType: string,
    siteName: string): LinkPreviewPresentation {
  const cacheKey: string = `${url}\u0000${previewType}\u0000${siteName}`;
  const hit: LinkPreviewPresentation | undefined = presentationCache.get(cacheKey);
  if (hit !== undefined) {
    return hit;
  }
  const computed: LinkPreviewPresentation =
    computeLinkPreviewPresentation(url, previewType, siteName);
  if (presentationCache.size >= PRESENTATION_CACHE_LIMIT) {
    presentationCache.clear();
  }
  presentationCache.set(cacheKey, computed);
  return computed;
}

function computeLinkPreviewPresentation(url: string, previewType: string,
    siteName: string): LinkPreviewPresentation {
  const raw: string = url.trim();
  const explicitSite: string = siteName.trim();
  if (raw === '') {
    return {
      kind: 'unavailable', actionLabel: str('link_preview_unavailable'),
      siteLabel: explicitSite !== '' ? explicitSite : str('link_preview_title'),
      isTelegram: false, actionable: false
    };
  }
  const telegramUrl: string = normalizeTelegramLink(raw);
  const telegram: boolean = telegramUrl !== '' || raw.startsWith('tg://') || raw.startsWith('@');
  if (!telegram) {
    const domain: string = linkPreviewDomain(raw);
    return {
      kind: 'web', actionLabel: str('link_preview_open_web'),
      siteLabel: explicitSite !== '' ? explicitSite : (domain !== '' ? domain : str('link_preview_web_link')),
      isTelegram: false, actionable: true
    };
  }
  if (chatFolderInviteLinkOf(raw) !== '') {
    return {
      kind: 'telegramResource', actionLabel: str('link_preview_open_folder'),
      siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
      isTelegram: true, actionable: true
    };
  }
  if (stickerSetLinkOf(raw) !== null) {
    return {
      kind: 'telegramResource', actionLabel: str('link_preview_open_stickers'),
      siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
      isTelegram: true, actionable: true
    };
  }
  if (inviteLinkOf(raw) !== '') {
    return {
      kind: 'telegramInvite', actionLabel: str('link_preview_open_invite'),
      siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
      isTelegram: true, actionable: true
    };
  }
  if (isTelegramMessageLink(raw, previewType)) {
    return {
      kind: 'telegramMessage', actionLabel: str('link_preview_open_message'),
      siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
      isTelegram: true, actionable: true
    };
  }
  const directUsername: string = bareUsernameOf(raw);
  return {
    kind: directUsername !== '' ? 'telegramChat' : 'telegramResource',
    actionLabel: directUsername !== '' ? str('link_preview_open_profile') : str('link_preview_open_in_telegram'),
    siteLabel: explicitSite !== '' ? explicitSite : 'Telegram',
    isTelegram: true, actionable: true
  };
}
