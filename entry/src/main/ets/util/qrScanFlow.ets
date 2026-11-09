import { TdObject, TdRequest } from '../tdkit/TdTypes';
import { isTelegramInternalUrl } from './linkNav';

export interface QrScanHost {
  current: () => boolean;
  send: (request: TdRequest) => Promise<TdObject>;
  confirmLogin: () => Promise<boolean>;
  openLink: (link: string) => void;
  openInvite: (link: string) => void;
}

// 只分类和分流，不记录扫码原文（登录token/私密邀请不进入日志）。
export async function dispatchScannedQr(raw: string, host: QrScanHost): Promise<string> {
  const link = raw.trim();
  if (!host.current()) { return 'cancelled'; }
  if (link === '') { return 'empty'; }
  if (link.length > 8192 || !isTelegramInternalUrl(link) || link.startsWith('@')) { return 'unsupported'; }
  const request: TdRequest = { '@type': 'getInternalLinkType' };
  request['link'] = link;
  const type = await host.send(request);
  if (!host.current()) { return 'cancelled'; }
  const kind = (type['@type'] as string | undefined) ?? '';
  if (kind === 'internalLinkTypeQrCodeAuthentication') {
    if (!await host.confirmLogin() || !host.current()) { return 'cancelled'; }
    const confirm: TdRequest = { '@type': 'confirmQrCodeAuthentication' };
    confirm['link'] = link;
    const result = await host.send(confirm);
    if (result['@type'] !== 'session') { throw new Error('QR login failed'); }
    return host.current() ? 'loggedIn' : 'cancelled';
  }
  if (kind === 'internalLinkTypeChatInvite') {
    // 始终先展示群资料/加入预览，由用户点击加入；扫描本身不加入群。
    host.openInvite((type['invite_link'] as string | undefined) || link);
    return 'opened';
  }
  if (kind === 'internalLinkTypePublicChat' || kind === 'internalLinkTypeUserToken' ||
    kind === 'internalLinkTypeMessage' || kind === 'internalLinkTypeStickerSet' ||
    kind === 'internalLinkTypeChatFolderInvite') {
    host.openLink(link);
    return 'opened';
  }
  return 'unsupported';
}
