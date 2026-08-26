import { str } from './strings';
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import {
  normalizeTelegramLink, bareUsernameOf, inviteLinkOf, chatLinkActionOf, chatFolderInviteLinkOf,
  stickerSetLinkOf, ChatLinkAction, StickerSetLink
} from './linkNav';
import { openWebUrl } from './webBrowserNav';
import { getMainMiniApp, getMiniAppLinkUrl } from '../store/BotApi';
import { logChatNavFailure, navigateToChat } from './chatNav';
import { navigateToChatProfile, navigateToProfile } from './profileNav';
import { navigateToSetting } from './settingsNav';
import { logE } from './log';
import { navigateToSearch } from './searchNav';

function openChatPage(chatId: number, showJoinedNotice: boolean = false,
    joinedNoticeIsChannel: boolean = false): void {
  const params: Record<string, Object> = { 'chatId': chatId };
  if (showJoinedNotice) {
    params['showJoinedNotice'] = true;
    params['joinedNoticeIsChannel'] = joinedNoticeIsChannel;
  }
  navigateToChat(params).catch(logChatNavFailure);
}

function isTelegramInternalUrl(url: string): boolean {
  const raw = url.trim();
  return raw.startsWith('tg://') || raw.startsWith('@') || normalizeTelegramLink(raw) !== '';
}

// A link that couldn't be resolved in-app. For a tapped in-message link we hand
// off to the system browser; for a deep-link ENTRY point we must not — opening
// the browser there bounces browser → app → browser, so just tell the user.
function onLinkUnresolved(context: common.UIAbilityContext, url: string, allowBrowser: boolean): void {
  // A Telegram resource must never bounce to its web landing page. Besides
  // being jarring for an in-message tap, a cold-start deep link can otherwise
  // loop browser -> app -> browser. Only genuinely external URLs use openUrl.
  if (allowBrowser && !isTelegramInternalUrl(url)) {
    openWebUrl(context, url);
  } else {
    promptAction.showToast({ message: str('tglink_unrecognized'), duration: 1700 });
  }
}

function openProfileForChat(chat: TdObject, draftText: string = '', openProfile: boolean = false): void {
  const chatId = (chat['id'] as number | undefined) ?? 0;
  if (chatId === 0) {
    return;
  }
  const type = chat['type'] as TdObject | undefined;
  const typeName = type !== undefined ? ((type['@type'] as string | undefined) ?? '') : '';
  if (typeName === 'chatTypePrivate') {
    const userId = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
    if (userId > 0) {
      const params: Record<string, Object> = { 'userId': userId };
      if (draftText !== '') {
        params['draftText'] = draftText;
      }
      // 曾经是 router.pushUrl('pages/profile/ProfilePage')——两张资料页都已迁成
      // HdsNavDestination 并从 main_pages.json 摘出，整页路由跳不动，走漏斗。
      navigateToProfile(params);
      return;
    }
  }
  const params: Record<string, Object> = { 'chatId': chatId };
  if (draftText !== '') {
    params['draftText'] = draftText;
  }
  if (openProfile) {
    navigateToChatProfile(params);
    return;
  }
  navigateToChat(params).catch(logChatNavFailure);
}

function resolvePublicChat(context: common.UIAbilityContext, username: string, draftText: string,
    openProfile: boolean, original: string, allowBrowser: boolean): void {
  if (username === '') {
    onLinkUnresolved(context, original, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = username;
  getTdClient().send(req).then((chat: TdObject): void => {
    if (((chat['id'] as number | undefined) ?? 0) === 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    openProfileForChat(chat, draftText, openProfile);
  }).catch((error: TdError): void => {
    logE(`openTelegramLink.searchPublicChat(${username}) failed: ${error.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

function openMessageLink(context: common.UIAbilityContext, link: string, original: string,
    allowBrowser: boolean): void {
  const req: TdRequest = { '@type': 'getMessageLinkInfo' };
  req['url'] = link;
  getTdClient().send(req).then((info: TdObject): void => {
    const chatId = (info['chat_id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    const msg = info['message'] as TdObject | undefined;
    const msgId = msg !== undefined ? ((msg['id'] as number | undefined) ?? 0) : 0;
    const params: Record<string, Object> = { 'chatId': chatId };
    if (msgId > 0) {
      params['jumpTo'] = msgId;
    }
    navigateToChat(params).catch(logChatNavFailure);
  }).catch((error: TdError): void => {
    logE(`openTelegramLink.getMessageLinkInfo failed: ${error.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

function openProxyLink(type: TdObject): void {
  const proxy = type['proxy'] as TdObject | undefined;
  if (proxy === undefined) {
    promptAction.showToast({ message: str('tglink_proxy_unsupported'), duration: 1800 });
    return;
  }
  const proxyType = proxy['type'] as TdObject | undefined;
  const server = (proxy['server'] as string | undefined) ?? '';
  const port = (proxy['port'] as number | undefined) ?? 0;
  if (server === '' || port <= 0 || proxyType === undefined) {
    promptAction.showToast({ message: str('tglink_proxy_incomplete'), duration: 1800 });
    return;
  }
  const params: Record<string, Object> = {
    'proxyServer': server,
    'proxyPort': port,
    'proxyType': (proxyType['@type'] as string | undefined) ?? 'proxyTypeSocks5',
    'proxyUsername': (proxyType['username'] as string | undefined) ?? '',
    'proxyPassword': (proxyType['password'] as string | undefined) ?? '',
    'proxySecret': (proxyType['secret'] as string | undefined) ?? '',
    'proxyHttpOnly': (proxyType['http_only'] as boolean | undefined) ?? false
  };
  // 代理页已迁成 HdsNavDestination、从 main_pages.json 摘掉，router.pushUrl 对它
  // 必然失败。走设置页签的路由栈——和 SettingsPage 那张列表同一个漏斗，params
  // 原封不动交给 pushPath 的 param，页面在 onRouteParams 里取。
  // 这是唯一一条**带参数**的设置深链，settingsNav.settingFrameKey 为它开了按
  // 「服务器:端口」区分实例的口子，见那里的注释。
  if (!navigateToSetting('ProxyPage', params)) {
    promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
  }
}

function openSelfProfile(): void {
  getTdClient().send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
    const userId = (me['id'] as number | undefined) ?? 0;
    if (userId > 0) {
      const params: Record<string, Object> = { 'userId': userId };
      navigateToProfile(params);
    }
  }).catch((error: TdError): void => {
    logE(`openTelegramLink.getMe failed: ${error.message}`);
    promptAction.showToast({ message: str('tglink_cannot_open_profile'), duration: 1600 });
  });
}

function openSavedMessages(): void {
  getTdClient().send({ '@type': 'getMe' } as TdRequest).then((me: TdObject): void => {
    const userId = (me['id'] as number | undefined) ?? 0;
    if (userId <= 0) {
      promptAction.showToast({ message: str('tglink_cannot_open_saved'), duration: 1600 });
      return;
    }
    const req: TdRequest = { '@type': 'createPrivateChat' };
    req['user_id'] = userId;
    req['force'] = false;
    getTdClient().send(req).then((chat: TdObject): void => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      if (chatId > 0) {
        openChatPage(chatId);
      }
    }).catch((error: TdError): void => {
      logE(`openTelegramLink.createSavedMessages failed: ${error.message}`);
      promptAction.showToast({ message: str('tglink_cannot_open_saved'), duration: 1600 });
    });
  }).catch((error: TdError): void => {
    logE(`openTelegramLink.getMeForSaved failed: ${error.message}`);
    promptAction.showToast({ message: str('tglink_cannot_open_saved'), duration: 1600 });
  });
}

function openStoryOwner(context: common.UIAbilityContext, username: string, original: string,
    allowBrowser: boolean, live: boolean): void {
  if (username === '') {
    onLinkUnresolved(context, original, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = username;
  getTdClient().send(req).then((chat: TdObject): void => {
    openProfileForChat(chat, '', true);
    promptAction.showToast({
      message: live ? str('tglink_opened_profile_no_live') : str('tglink_opened_stories'),
      duration: live ? 2200 : 1400
    });
  }).catch((error: TdError): void => {
    logE(`openTelegramLink.storyOwner(${username}) failed: ${error.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

function openPhoneNumberUser(context: common.UIAbilityContext, type: TdObject, original: string,
    allowBrowser: boolean): void {
  const phone = (type['phone_number'] as string | undefined) ?? '';
  if (phone === '') {
    onLinkUnresolved(context, original, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'searchUserByPhoneNumber' };
  req['phone_number'] = phone;
  req['only_local'] = false;
  getTdClient().send(req).then((user: TdObject): void => {
    const userId = (user['id'] as number | undefined) ?? 0;
    if (userId <= 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    const draftText = (type['draft_text'] as string | undefined) ?? '';
    if ((type['open_profile'] as boolean | undefined) ?? false) {
      const params: Record<string, Object> = { 'userId': userId };
      if (draftText !== '') {
        params['draftText'] = draftText;
      }
      navigateToProfile(params);
      return;
    }
    const create: TdRequest = { '@type': 'createPrivateChat' };
    create['user_id'] = userId;
    create['force'] = false;
    getTdClient().send(create).then((chat: TdObject): void => {
      const chatId = (chat['id'] as number | undefined) ?? 0;
      if (chatId > 0) {
        const params: Record<string, Object> = { 'chatId': chatId };
        if (draftText !== '') {
          params['draftText'] = draftText;
        }
        navigateToChat(params).catch(logChatNavFailure);
      }
    }).catch((error: TdError): void => {
      logE(`openTelegramLink.createPhoneChat failed: ${error.message}`);
      onLinkUnresolved(context, original, allowBrowser);
    });
  }).catch((error: TdError): void => {
    logE(`openTelegramLink.searchUserByPhoneNumber failed: ${error.message}`);
    promptAction.showToast({ message: str('tglink_phone_not_found'), duration: 1800 });
  });
}

function openSettingsSection(type: TdObject): void {
  const section = type['section'] as TdObject | undefined;
  if (section === undefined) {
    promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
    return;
  }
  const sectionName = (section['@type'] as string | undefined) ?? '';
  let page = '';
  if (sectionName === 'settingsSectionEditProfile') {
    // 账号编辑页已迁成 HdsNavDestination、从 main_pages.json 摘掉，走设置页签的
    // 路由栈——理由同下面 settingsSectionPowerSaving 那一支。
    if (!navigateToSetting('AccountEditPage')) {
      promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
    }
    return;
  } else if (sectionName === 'settingsSectionAppearance') {
    // 聊天设置已迁成 HdsNavDestination、从 main_pages.json 摘掉，走设置页签的
    // 路由栈——理由同下面 settingsSectionPowerSaving 那一支。
    if (!navigateToSetting('ChatSettingsPage')) {
      promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
    }
    return;
  } else if (sectionName === 'settingsSectionChatFolders') {
    // 文件夹页已迁成 HdsNavDestination、从 main_pages.json 摘掉，走设置页签的
    // 路由栈——理由同下面 settingsSectionPowerSaving 那一支。
    if (!navigateToSetting('ChatFoldersPage')) {
      promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
    }
    return;
  } else if (sectionName === 'settingsSectionPrivacyAndSecurity') {
    const subsection = (section['subsection'] as string | undefined) ?? '';
    // 两支目标现在性质不同，所以不能再共用底下那一句 router.pushUrl：
    // BlockedUsersPage 这一轮没迁，仍是 router 页；隐私与安全页已迁成
    // HdsNavDestination，只能走设置页签的路由栈。
    if (subsection.startsWith('blocked')) {
      page = 'pages/main/BlockedUsersPage';
    } else {
      if (!navigateToSetting('PrivacySecurityPage')) {
        promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
      }
      return;
    }
  } else if (sectionName === 'settingsSectionDevices') {
    // 设备（登录会话）页已迁成 HdsNavDestination、从 main_pages.json 摘掉，走
    // 设置页签的路由栈——理由同下面 settingsSectionPowerSaving 那一支。
    if (!navigateToSetting('ActiveSessionsPage')) {
      promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
    }
    return;
  } else if (sectionName === 'settingsSectionDataAndStorage') {
    // 数据与存储页已迁成 HdsNavDestination、从 main_pages.json 摘掉，走设置
    // 页签的路由栈——理由同下面 settingsSectionPowerSaving 那一支。
    if (!navigateToSetting('DataStoragePage')) {
      promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
    }
    return;
  } else if (sectionName === 'settingsSectionPowerSaving') {
    // 耗电页已经迁成 HdsNavDestination、从 main_pages.json 摘掉了，router.pushUrl
    // 对它必然失败（而且这里原本连 catch 都没有，会是"点了深链什么都不发生"）。
    // 走设置页签的路由栈——和 SettingsPage 那张列表同一个漏斗。
    // 【每迁一个设置子页，就有一条 else-if 要从上面搬到这里来。】
    if (!navigateToSetting('PowerUsagePage')) {
      // 栈还没注册：只可能是 SettingsPage 尚未挂树（登录前/冷启动早期）。
      promptAction.showToast({ message: str('tglink_use_bottom_bar'), duration: 1700 });
    }
    return;
  }
  if (page !== '') {
    router.pushUrl({ url: page });
  } else {
    promptAction.showToast({ message: str('tglink_settings_section_missing'), duration: 1800 });
  }
}

function unsupportedLinkLabel(typeName: string): string {
  if (typeName === 'internalLinkTypeBackground') { return str('tglink_kind_background'); }
  if (typeName === 'internalLinkTypeTheme') { return str('tglink_kind_theme'); }
  if (typeName === 'internalLinkTypeLanguagePack') { return str('tglink_kind_language'); }
  if (typeName === 'internalLinkTypeGroupCall') { return str('tglink_kind_group_call'); }
  if (typeName === 'internalLinkTypeInvoice') { return str('tglink_kind_payment'); }
  if (typeName === 'internalLinkTypePremiumGiftCode') { return str('tglink_kind_gift_code'); }
  if (typeName === 'internalLinkTypeAuthenticationCode') { return str('tglink_kind_login_code'); }
  if (typeName === 'internalLinkTypeWebApp' || typeName === 'internalLinkTypeMainWebApp') {
    return 'Mini App';
  }
  if (typeName === 'internalLinkTypeBotStartInGroup') { return str('tglink_kind_bot_to_group'); }
  if (typeName === 'internalLinkTypeBotAddToChannel') { return str('tglink_kind_bot_to_channel'); }
  if (typeName === 'internalLinkTypeUnknownDeepLink') { return str('tglink_kind_generic'); }
  return str('tglink_kind_generic');
}

function handleInternalLinkType(context: common.UIAbilityContext, type: TdObject, original: string,
    allowBrowser: boolean): void {
  const typeName = (type['@type'] as string | undefined) ?? '';
  if (typeName === 'internalLinkTypePublicChat') {
    resolvePublicChat(context,
      (type['chat_username'] as string | undefined) ?? '',
      (type['draft_text'] as string | undefined) ?? '',
      (type['open_profile'] as boolean | undefined) ?? false,
      original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeBotStart') {
    const action: ChatLinkAction = {
      username: (type['bot_username'] as string | undefined) ?? '',
      startParam: (type['start_parameter'] as string | undefined) ?? '',
      draftText: ''
    };
    openChatLinkAction(context, action, original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeChatInvite') {
    openInviteLink(context, (type['invite_link'] as string | undefined) ?? original,
      original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeMessage') {
    openMessageLink(context, (type['url'] as string | undefined) ?? original,
      original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeChatFolderInvite') {
    openChatFolderInviteLink((type['invite_link'] as string | undefined) ?? original);
    return;
  }
  if (typeName === 'internalLinkTypeStickerSet') {
    const sticker: StickerSetLink = {
      name: (type['sticker_set_name'] as string | undefined) ?? '',
      expectCustomEmoji: (type['expect_custom_emoji'] as boolean | undefined) ?? false
    };
    if (sticker.name !== '') {
      openStickerSetLink(sticker);
    } else {
      onLinkUnresolved(context, original, allowBrowser);
    }
    return;
  }
  if (typeName === 'internalLinkTypeProxy') {
    openProxyLink(type);
    return;
  }
  if (typeName === 'internalLinkTypeUserPhoneNumber') {
    openPhoneNumberUser(context, type, original, allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeSearch') {
    navigateToSearch();
    return;
  }
  if (typeName === 'internalLinkTypeCallsPage') {
    router.pushUrl({ url: 'pages/main/CallsPage' });
    return;
  }
  if (typeName === 'internalLinkTypeNewGroupChat') {
    router.pushUrl({ url: 'pages/main/NewGroupPage' });
    return;
  }
  if (typeName === 'internalLinkTypeSettings') {
    openSettingsSection(type);
    return;
  }
  if (typeName === 'internalLinkTypeMyProfilePage') {
    openSelfProfile();
    return;
  }
  if (typeName === 'internalLinkTypeSavedMessages') {
    openSavedMessages();
    return;
  }
  if (typeName === 'internalLinkTypeStory' || typeName === 'internalLinkTypeLiveStory') {
    openStoryOwner(context,
      (type['story_poster_username'] as string | undefined) ?? '', original, allowBrowser,
      typeName === 'internalLinkTypeLiveStory');
    return;
  }
  if (typeName === 'internalLinkTypeStoryAlbum') {
    openStoryOwner(context,
      (type['story_album_owner_username'] as string | undefined) ?? '', original, allowBrowser, false);
    return;
  }
  if (typeName === 'internalLinkTypeWebApp' || typeName === 'internalLinkTypeMainWebApp') {
    openMiniAppLink(context, type, typeName === 'internalLinkTypeMainWebApp', original,
      allowBrowser);
    return;
  }
  if (typeName === 'internalLinkTypeVideoChat') {
    // The chat page owns live-state resolution and presents its existing entry
    // banner once TDLib has refreshed the chat's current group call.
    resolvePublicChat(context, (type['chat_username'] as string | undefined) ?? '', '', false,
      original, allowBrowser);
    return;
  }
  promptAction.showToast({
    message: str('tglink_kind_unsupported', unsupportedLinkLabel(typeName)),
    duration: 2100
  });
}

// Mini App links (t.me/<bot>/<app>): resolve the bot, ask TDLib for the real
// https app URL, then render it in the in-app browser.
function openMiniAppLink(context: common.UIAbilityContext, type: TdObject, isMain: boolean,
    original: string, allowBrowser: boolean): void {
  const username = (type['bot_username'] as string | undefined) ?? '';
  if (username === '') {
    onLinkUnresolved(context, original, allowBrowser);
    return;
  }
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = username;
  getTdClient().send(req).then((chat: TdObject): Promise<string> => {
    const chatType = chat['type'] as TdObject | undefined;
    const botId = chatType !== undefined ? ((chatType['user_id'] as number | undefined) ?? 0) : 0;
    const chatId = (chat['id'] as number | undefined) ?? 0;
    if (botId === 0) { return Promise.reject(new TdError(404, 'not a bot')); }
    return isMain
      ? getMainMiniApp(chatId, botId)
      : getMiniAppLinkUrl(chatId, botId,
        (type['web_app_short_name'] as string | undefined) ?? '',
        (type['start_parameter'] as string | undefined) ?? '');
  }).then((url: string): void => {
    if (url === '') {
      promptAction.showToast({ message: str('tglink_cannot_open_miniapp'), duration: 1700 });
      return;
    }
    openWebUrl(context, url);
  }).catch((error: TdError): void => {
    logE(`openMiniAppLink failed: ${error.message}`);
    promptAction.showToast({ message: str('tglink_cannot_open_miniapp'), duration: 1700 });
  });
}

function classifyTelegramLink(context: common.UIAbilityContext, url: string,
    allowBrowser: boolean): void {
  const req: TdRequest = { '@type': 'getInternalLinkType' };
  req['link'] = url;
  getTdClient().send(req).then((type: TdObject): void => {
    handleInternalLinkType(context, type, url, allowBrowser);
  }).catch((error: TdError): void => {
    logE(`openTelegramLink.getInternalLinkType failed: ${error.message}`);
    // Keep a compatibility fallback for older TDLib builds: the two oldest
    // public link shapes can still be resolved without opening a browser.
    const bareName = bareUsernameOf(url);
    if (bareName !== '') {
      resolvePublicChat(context, bareName, '', false, url, allowBrowser);
      return;
    }
    const normalized = normalizeTelegramLink(url);
    if (normalized !== '') {
      openMessageLink(context, normalized, url, allowBrowser);
      return;
    }
    onLinkUnresolved(context, url, allowBrowser);
  });
}

// Private invite link (t.me/+hash): preview the chat via checkChatInviteLink;
// already a member → straight into the chat, otherwise confirm and join.
export function openInviteLink(context: common.UIAbilityContext, invite: string, original: string,
    allowBrowser: boolean = true): void {
  const req: TdRequest = { '@type': 'checkChatInviteLink' };
  req['invite_link'] = invite;
  getTdClient().send(req).then((info: TdObject) => {
    const chatId = (info['chat_id'] as number | undefined) ?? 0;
    if (chatId !== 0) {
      openChatPage(chatId);
      return;
    }
    const title = (info['title'] as string | undefined) ?? '';
    const count = (info['member_count'] as number | undefined) ?? 0;
    const inviteType = (info['type'] as TdObject | undefined)
      ?? (info['chat_type'] as TdObject | undefined);
    const inviteTypeName = (inviteType?.['@type'] as string | undefined) ?? '';
    const isChannel: boolean = ((info['is_channel'] as boolean | undefined) ?? false) ||
      inviteTypeName.indexOf('Channel') >= 0 || inviteTypeName.indexOf('channel') >= 0;
    promptAction.showDialog({
      title: str('tglink_join_title'),
      message: count > 0 ? str('tglink_quoted_title_members', title, count) : str('tglink_quoted_title', title),
      buttons: [
        { text: str('tglink_cancel'), color: '#8E8E93' },
        { text: str('tglink_join'), color: $r('app.color.primary') }
      ]
    }).then((r) => {
      if (r.index !== 1) {
        return;
      }
      const join: TdRequest = { '@type': 'joinChatByInviteLink' };
      join['invite_link'] = invite;
      getTdClient().send(join).then((chat: TdObject) => {
        const id = (chat['id'] as number | undefined) ?? 0;
        if (id !== 0) {
          openChatPage(id, true, isChannel);
        }
      }).catch((e: TdError) => {
        logE(`openInviteLink.join failed: ${e.message}`);
        promptAction.showToast({ message: str('tglink_join_failed') });
      });
    });
  }).catch((e: TdError) => {
    // Expired or invalid Telegram resources stay in-app and show a precise
    // failure instead of opening Telegram's web landing page.
    logE(`openInviteLink.check failed: ${e.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

function folderNameOf(info: TdObject): string {
  const folder = info['chat_folder_info'] as TdObject | undefined;
  const name = folder !== undefined ? (folder['name'] as TdObject | undefined) : undefined;
  const text = name !== undefined ? (name['text'] as TdObject | undefined) : undefined;
  return text !== undefined ? ((text['text'] as string | undefined) ?? '') : '';
}

// Shared folder links are Telegram resources, not web pages. Preview the
// folder and add all chats that aren't present yet after explicit confirmation.
export function openChatFolderInviteLink(invite: string): void {
  const req: TdRequest = { '@type': 'checkChatFolderInviteLink' };
  req['invite_link'] = invite;
  getTdClient().send(req).then((info: TdObject): void => {
    const missing = (info['missing_chat_ids'] as number[] | undefined) ?? [];
    const added = (info['added_chat_ids'] as number[] | undefined) ?? [];
    const name = folderNameOf(info);
    const displayName = name !== ''
      ? str('folder_link_quoted_name', name) : str('folder_link_this_folder');
    if (missing.length === 0) {
      promptAction.showToast({
        message: added.length > 0
          ? str('folder_link_already_added', displayName)
          : str('folder_link_nothing_to_add'),
        duration: 1700
      });
      return;
    }
    // Two whole sentences rather than one with an appended clause: a fragment
    // like "，另有 N 个已在文件夹中" cannot be translated on its own, because
    // where it attaches and how it joins differ per language.
    const message = added.length > 0
      ? str('folder_link_add_message_with_existing', displayName, missing.length, added.length)
      : str('folder_link_add_message', displayName, missing.length);
    promptAction.showDialog({
      title: str('folder_link_add_title'),
      message,
      buttons: [
        { text: str('tglink_cancel'), color: '#8E8E93' },
        { text: str('folder_link_add'), color: $r('app.color.primary') }
      ]
    }).then((result): void => {
      if (result.index !== 1) {
        return;
      }
      const add: TdRequest = { '@type': 'addChatFolderByInviteLink' };
      add['invite_link'] = invite;
      add['chat_ids'] = missing;
      getTdClient().send(add).then((): void => {
        promptAction.showToast({ message: str('folder_link_added_toast'), duration: 1600 });
      }).catch((error: TdError): void => {
        logE(`openChatFolderInviteLink.add failed: ${error.message}`);
        promptAction.showToast({ message: str('folder_link_add_failed'), duration: 1800 });
      });
    }).catch((): void => {});
  }).catch((error: TdError): void => {
    logE(`openChatFolderInviteLink.check failed: ${error.message}`);
    promptAction.showToast({ message: str('folder_link_invalid'), duration: 1800 });
  });
}

// Resolve a sticker-set short name, show its actual server-side metadata, then
// install/activate it in-place. Custom emoji links use the same TDLib object.
export function openStickerSetLink(link: StickerSetLink): void {
  const req: TdRequest = { '@type': 'searchStickerSet' };
  req['name'] = link.name;
  req['ignore_cache'] = false;
  getTdClient().send(req).then((set: TdObject): void => {
    const setId = (set['id'] as number | undefined) ?? 0;
    const title = (set['title'] as string | undefined) ?? link.name;
    const installed = (set['is_installed'] as boolean | undefined) ?? false;
    const stickers = (set['stickers'] as TdObject[] | undefined) ?? [];
    const type = set['sticker_type'] as TdObject | undefined;
    const isCustomEmoji = link.expectCustomEmoji ||
      (type !== undefined && type['@type'] === 'stickerTypeCustomEmoji');
    const resourceName = isCustomEmoji ? str('sticker_kind_emoji') : str('sticker_kind_stickers');
    promptAction.showDialog({
      title: installed
        ? str('sticker_link_installed_title', resourceName)
        : str('sticker_link_add_title', resourceName),
      message: stickers.length > 0
        ? str('sticker_link_message_with_count', title, stickers.length)
        : str('sticker_link_message', title),
      buttons: [
        { text: str('tglink_close'), color: '#8E8E93' },
        { text: installed ? str('tglink_added') : str('folder_link_add'), color: $r('app.color.primary') }
      ]
    }).then((result): void => {
      if (result.index !== 1 || installed || setId <= 0) {
        return;
      }
      const change: TdRequest = { '@type': 'changeStickerSet' };
      change['set_id'] = setId;
      change['is_installed'] = true;
      change['is_archived'] = false;
      getTdClient().send(change).then((): void => {
        promptAction.showToast({ message: str('sticker_link_added_toast', resourceName), duration: 1500 });
      }).catch((error: TdError): void => {
        logE(`openStickerSetLink.change failed: ${error.message}`);
        promptAction.showToast({ message: str('sticker_link_add_failed', resourceName), duration: 1800 });
      });
    }).catch((): void => {});
  }).catch((error: TdError): void => {
    logE(`openStickerSetLink.search(${link.name}) failed: ${error.message}`);
    promptAction.showToast({ message: str('sticker_link_invalid'), duration: 1800 });
  });
}

// Chat link carrying an action payload: resolve the username, enter the chat,
// then auto-send /start (bot ?start= links) or prefill the draft (?text=).
export function openChatLinkAction(context: common.UIAbilityContext, action: ChatLinkAction,
    original: string, allowBrowser: boolean): void {
  const req: TdRequest = { '@type': 'searchPublicChat' };
  req['username'] = action.username;
  getTdClient().send(req).then((chat: TdObject) => {
    const chatId = (chat['id'] as number | undefined) ?? 0;
    if (chatId === 0) {
      onLinkUnresolved(context, original, allowBrowser);
      return;
    }
    const params: Record<string, Object> = { 'chatId': chatId };
    if (action.draftText !== '') {
      params['draftText'] = action.draftText;
    }
    navigateToChat(params).catch(logChatNavFailure);
    if (action.startParam === '') {
      return;
    }
    const type = chat['type'] as TdObject | undefined;
    const uid = type !== undefined ? ((type['user_id'] as number | undefined) ?? 0) : 0;
    if (uid <= 0) {
      return; // ?start= is only meaningful on a private bot chat
    }
    const start: TdRequest = { '@type': 'sendBotStartMessage' };
    start['bot_user_id'] = uid;
    start['chat_id'] = chatId;
    start['parameter'] = action.startParam;
    getTdClient().send(start).catch((e: TdError) => {
      logE(`openTelegramLink.sendBotStartMessage failed: ${e.message}`);
      promptAction.showToast({ message: str('tglink_start_failed'), duration: 1500 });
    });
  }).catch((e: TdError) => {
    logE(`openTelegramLink.searchPublicChat(${action.username}) failed: ${e.message}`);
    onLinkUnresolved(context, original, allowBrowser);
  });
}

// Full in-app routing for a tapped link outside the chat page (profile bios,
// channel descriptions, ...): text mentions open the profile card, usernames
// resolve to a profile/chat, message links open the chat at the message, and
// external web URLs still go to the system browser.
export function openTelegramLink(context: common.UIAbilityContext, url: string,
    allowBrowser: boolean = true): void {
  const raw = url.trim();
  if (raw === '') {
    return;
  }
  if (raw.startsWith('tg://user?id=')) {
    const uid = Number(raw.substring('tg://user?id='.length));
    if (uid > 0) {
      const params: Record<string, Object> = { 'userId': uid };
      navigateToProfile(params);
    }
    return;
  }
  const folderInvite = chatFolderInviteLinkOf(raw);
  if (folderInvite !== '') {
    openChatFolderInviteLink(folderInvite);
    return;
  }
  const stickerSet = stickerSetLinkOf(raw);
  if (stickerSet !== null) {
    openStickerSetLink(stickerSet);
    return;
  }
  const invite = inviteLinkOf(raw);
  if (invite !== '') {
    openInviteLink(context, invite, raw, allowBrowser);
    return;
  }
  // ?start= / ?text= actions take priority over plain username routing —
  // bareUsernameOf drops the query string, which would lose the payload.
  const action = chatLinkActionOf(raw);
  if (action !== null) {
    openChatLinkAction(context, action, raw, allowBrowser);
    return;
  }
  // Plain @mentions aren't accepted by getInternalLinkType; resolve those
  // directly. Every real t.me/telegram.me/telegram.dog/tg:// URL goes through
  // TDLib so reserved routes such as /proxy aren't mistaken for usernames.
  if (raw.startsWith('@')) {
    const bareName = bareUsernameOf(raw);
    if (bareName !== '') {
      resolvePublicChat(context, bareName, '', false, raw, allowBrowser);
    } else {
      onLinkUnresolved(context, raw, allowBrowser);
    }
    return;
  }
  if (isTelegramInternalUrl(raw)) {
    classifyTelegramLink(context, raw, allowBrowser);
    return;
  }
  onLinkUnresolved(context, raw, allowBrowser);
}
