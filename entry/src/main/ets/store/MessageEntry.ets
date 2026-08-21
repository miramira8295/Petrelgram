import { TdObject } from '../tdkit/TdTypes';
import { UserStore } from './UserStore';
import { buttonStyleOf } from './ReplyKeyboard';
import { formatMsgContent, MsgContent, PollOptionInfo } from '../util/formatMsgContent';
import { SERVICE_LABEL_KEYS } from '../util/formatPreview';
import { plural, str } from '../util/strings';
import { monthDayTime } from '../util/intlFormat';
import { logW } from '../util/log';

export interface MessageEntry {
  id: number;
  // 列表行身份，只给行 key 用，其余一切（回复、菜单、选择、已读）仍然用 id。
  //
  // 发送成功时 TDLib 会把临时 id 换成真实 id（updateMessageSendSucceeded），
  // 而 id 直接进行 key，于是那一行被当成新 item 销毁重建——界面上就是发完
  // 消息"闪一下"。rowId 在这次替换中由新条目继承旧条目的值（见
  // MessageStore.onSendSucceeded），行因此保持同一个身份，只有状态图标从
  // 时钟换成对号。新建条目时 rowId 就等于 id。
  rowId: number;
  isOutgoing: boolean;
  senderName: string;
  // 群成员标签（chatMemberTag），消息对象自带（sender_tag），全员可见。
  senderTag: string;
  senderId: number;
  senderIsUser: boolean;
  senderInitials: string;
  senderAvatarPath: string;
  date: number;
  editDate: number;       // TDLib edit_date; 0 means the message was never edited
  contentType: string;
  text: string;
  photoFileId: number;
  photoPath: string;
  photoProgress: number; // 0-100 download progress of the inline thumbnail
  photoFailed: boolean;  // bounded thumbnail retries exhausted; tap retries
  photoWidth: number;
  photoHeight: number;
  placeholderLabel: string;
  // 富文本长帖的原始页面块。可选：只有 contentType === 'richMessage' 才有，
  // 其余构造点不用改。
  richBlocks?: TdObject[];
  // Semantic category used only to decorate centered service-message pills.
  // The message keeps the same timeline position regardless of category.
  systemKind: string;
  // Kept so names that arrive after history can refresh member/call notices
  // without retaining the full raw TDLib message.
  systemType: string;
  systemUserIds: number[];
  // Unknown/future TDLib content stays a normal left/right bubble, but gets a
  // deliberate readable fallback instead of a blank or raw type name.
  isUnsupportedMessage: boolean;
  // True only for a live messageVideoChatStarted service message — the bubble
  // becomes tappable (opens the live viewer) when the chat's video chat is
  // still active. Ended/scheduled video-chat pills stay display-only.
  isVideoChatStarted: boolean;
  replyToMessageId: number;
  replySenderName: string;
  replyText: string;
  sendState: string;
  albumId: string;
  textEntities: TdObject[];
  // Unique custom-emoji ids referenced inside a mixed text message. Paths are
  // parallel and fill asynchronously with a static WEBP/thumbnail suitable
  // for ArkUI ImageSpan; the Unicode alternative remains the loading fallback.
  inlineCustomEmojiIds: string[];
  inlineCustomEmojiPaths: string[];
  forwardFrom: string;   // display name of the forward origin ('' = not forwarded)
  forwardChatId: number; // origin channel/chat id to resolve a title for (0 = none/resolved)
  // Tappable origin of a forward: the original post (channel/chat) or its
  // author (user). All 0 for a hidden-origin forward, which can't be opened.
  forwardOriginChatId: number;
  forwardOriginMsgId: number;
  forwardOriginUserId: number;
  commentCount: number;         // channel post comment count (0 = no comments row)
  commentReplierIds: number[];  // up to 3 recent commenter user ids (for avatar stack)
  commentReplierAvatarPaths: string[]; // parallel to commentReplierIds, filled in as avatars download
  linkSiteName: string;         // link preview card ('' = no preview)
  linkTitle: string;
  linkDescription: string;
  linkDescriptionEntities: TdObject[];
  linkPhotoFileId: number;
  linkPhotoPath: string;
  linkPhotoWidth: number;
  linkPhotoHeight: number;
  linkPhotoProgress: number;
  linkPhotoFailed: boolean;
  linkPhotoDownloadActive: boolean;
  linkPreviewType: string;
  linkUrl: string;              // tap target to open the preview's link/message
  reactions: ReactionInfo[];    // emoji reaction pills (empty = none)
  inlineButtons: InlineBtn[][]; // bot inline keyboard rows (empty = none)
  photoFullFileId: number;      // full-resolution photo file id (0 = no upgrade available)
  photoFullPath: string;        // local path once the full-resolution photo is downloaded (on tap)
  photoFullProgress: number;    // 0-100 download progress of the full-resolution photo
  photoFullFailed: boolean;     // last on-demand full-resolution request failed; viewer may retry
  videoFileId: number;          // full-resolution video file id (0 = not a video)
  videoFileSize: number;        // bytes (0 = unknown)
  videoMimeType: string;        // source mime type from TDLib, e.g. video/mp4
  videoFileName: string;        // original file name ('' = unknown)
  videoDuration: number;        // seconds
  isAnimation: boolean;         // Telegram GIF/messageAnimation
  videoPath: string;            // local path once the full video is downloaded
  videoProgress: number;        // 0-100 download progress of the full video file
  videoFailed: boolean;         // last full-video download failed; save/retry UI may recover
  mediaDownloadActive: boolean; // full media request is currently active
  voiceWaveform: string;        // base64 packed waveform, '' when unavailable
  voiceListened: boolean;       // incoming voice note has been opened/listened
  // 语音转文字。'' 表示未识别过；pending 期间可能已有部分文本。
  speechState: string;          // '' | 'pending' | 'done' | 'error'
  speechText: string;
  // 整聊天翻译。translatedText 为空表示无译文（未翻译/与原文相同）；
  // translationHidden 是用户点「隐藏译文」后的单条折叠状态。
  // 译文属于展示层缓存而非消息内容，消息被编辑后由 editDate 变化使其失效
  // （TranslationService 的缓存键含 editDate）。
  translatedText: string;
  translatedLang: string;       // 译文对应的目标语言码，防止切目标语言后误用
  translationHidden: boolean;
  audioTitle: string;           // music metadata; '' falls back to file name
  audioPerformer: string;       // music artist/performer; '' = unknown
  stickerFileId: number;        // animated (TGS) sticker source file id, 0 otherwise
  customEmojiId: string;        // single custom-emoji message, pending sticker resolution
  stickerFormat: string;        // 'webp' | 'tgs' | 'webm', '' for non-stickers
  isEmojiSticker: boolean;      // obeys chat Emoji playback policy
  stickerPath: string;          // local path of the downloaded TGS/WEBM source
  stickerProgress: number;      // 0-100 source download progress
  stickerFailed: boolean;       // source download failed; tap retries
  stickerDownloadActive: boolean;
  contactPhone: string;
  contactFirstName: string;
  contactLastName: string;
  contactVcard: string;
  contactUserId: number;
  contactAvatarPath: string;
  locationLatitude: number;
  locationLongitude: number;
  locationAccuracy: number;
  locationValid: boolean;
  locationLivePeriod: number;
  locationExpiresIn: number;
  locationHeading: number;
  locationProximityRadius: number;
  venueTitle: string;
  venueAddress: string;
  venueProvider: string;
  venueId: string;
  venueType: string;
  pollId: string;
  pollQuestion: string;
  pollOptions: PollOptionInfo[];
  pollTotalVoterCount: number;
  pollIsAnonymous: boolean;
  pollIsQuiz: boolean;
  pollAllowMultiple: boolean;
  pollCorrectOptionId: number;
  pollExplanation: string;
  pollOpenPeriod: number;
  pollCloseDate: number;
  pollIsClosed: boolean;
  pollVotePending: boolean;
  pollVoteError: string;
  diceEmoji: string;
  diceValue: number;
  diceSuccessFrame: number;
  diceHasFinalState: boolean;
  // 🎰 老虎机：5 层 TGS（背景/拉杆/左中右转轮）文件 id 与本地路径（平行数组）。
  diceLayerFileIds: number[];
  diceLayerPaths: string[];
  gameId: string;
  gameShortName: string;
  gameTitle: string;
  gameDescription: string;
  gameText: string;
  paidMediaLocked: boolean;
  paidMediaStarCount: number;
  paidMediaCount: number;
  paidMediaKind: string;
  giftKind: string;
  giftTitle: string;
  giftValue: string;
  giftStatus: string;
  giftCode: string;
  giftRefunded: boolean;
  giveawayState: string;
  giveawayWinnerCount: number;
  giveawayPrize: string;
  giveawayDescription: string;
  giveawaySelectionDate: number;
  giveawayUnclaimedCount: number;
  giveawayMessageId: number;
  giveawayBoostedChatId: number;
  giveawayRefunded: boolean;
  giveawayOnlyNewMembers: boolean;
}

export interface ReactionInfo {
  emoji: string;           // 标准 emoji（自定义 emoji 反应为 ''）
  count: number;
  isChosen: boolean;
  customEmojiId: string;   // reactionTypeCustomEmoji 的 int64 id，字符串承载（标准反应为 ''）
  customEmojiPath: string; // 自定义 emoji 位图本地路径（'' = 尚未下载完成，显示占位）
}

// One bot inline-keyboard button. Exactly one of url/callbackData is set for
// the types we support; unsupported types render but do nothing on tap.
export interface InlineBtn {
  text: string;
  url: string;
  callbackData: string; // base64 payload for inlineKeyboardButtonTypeCallback
  isGame: boolean;      // inlineKeyboardButtonTypeCallbackGame
  style: string;        // 'primary' | 'success' | 'danger' | '' (default look)
}

// Parse message.reply_markup (replyMarkupInlineKeyboard) into button rows.
export function parseInlineKeyboard(replyMarkup: TdObject | undefined): InlineBtn[][] {
  if (replyMarkup === undefined || replyMarkup['@type'] !== 'replyMarkupInlineKeyboard') {
    return [];
  }
  const rows = (replyMarkup['rows'] as TdObject[][] | undefined) ?? [];
  const out: InlineBtn[][] = [];
  for (const row of rows) {
    const btns: InlineBtn[] = [];
    for (const b of row) {
      const t = b['type'] as TdObject | undefined;
      const tt = t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '';
      btns.push({
        text: (b['text'] as string | undefined) ?? '',
        url: tt === 'inlineKeyboardButtonTypeUrl' ? ((t!['url'] as string | undefined) ?? '') : '',
        callbackData: tt === 'inlineKeyboardButtonTypeCallback' ? ((t!['data'] as string | undefined) ?? '') : '',
        isGame: tt === 'inlineKeyboardButtonTypeCallbackGame',
        style: buttonStyleOf(b)
      });
    }
    if (btns.length > 0) {
      out.push(btns);
    }
  }
  return out;
}

export function cloneMessage(m: MessageEntry): MessageEntry {
  return {
    id: m.id, rowId: m.rowId, isOutgoing: m.isOutgoing, senderName: m.senderName,
    senderTag: m.senderTag,
    senderId: m.senderId, senderIsUser: m.senderIsUser,
    senderInitials: m.senderInitials, senderAvatarPath: m.senderAvatarPath, date: m.date,
    editDate: m.editDate,
    contentType: m.contentType, text: m.text, photoFileId: m.photoFileId, photoPath: m.photoPath,
    photoProgress: m.photoProgress, photoFailed: m.photoFailed,
    photoWidth: m.photoWidth, photoHeight: m.photoHeight,
    placeholderLabel: m.placeholderLabel, richBlocks: m.richBlocks, systemKind: m.systemKind,
    systemType: m.systemType, systemUserIds: m.systemUserIds.slice(),
    isUnsupportedMessage: m.isUnsupportedMessage,
    isVideoChatStarted: m.isVideoChatStarted,
    replyToMessageId: m.replyToMessageId,
    replySenderName: m.replySenderName, replyText: m.replyText, sendState: m.sendState,
    albumId: m.albumId, textEntities: m.textEntities,
    inlineCustomEmojiIds: m.inlineCustomEmojiIds.slice(),
    inlineCustomEmojiPaths: m.inlineCustomEmojiPaths.slice(),
    forwardFrom: m.forwardFrom, forwardChatId: m.forwardChatId,
    forwardOriginChatId: m.forwardOriginChatId, forwardOriginMsgId: m.forwardOriginMsgId,
    forwardOriginUserId: m.forwardOriginUserId,
    commentCount: m.commentCount, commentReplierIds: m.commentReplierIds,
    commentReplierAvatarPaths: m.commentReplierAvatarPaths,
    linkSiteName: m.linkSiteName, linkTitle: m.linkTitle, linkDescription: m.linkDescription,
    linkDescriptionEntities: m.linkDescriptionEntities, linkPhotoFileId: m.linkPhotoFileId,
    linkPhotoPath: m.linkPhotoPath, linkPhotoWidth: m.linkPhotoWidth,
    linkPhotoHeight: m.linkPhotoHeight, linkPhotoProgress: m.linkPhotoProgress,
    linkPhotoFailed: m.linkPhotoFailed, linkPhotoDownloadActive: m.linkPhotoDownloadActive,
    linkPreviewType: m.linkPreviewType, linkUrl: m.linkUrl,
    reactions: m.reactions,
    inlineButtons: m.inlineButtons,
    photoFullFileId: m.photoFullFileId, photoFullPath: m.photoFullPath,
    photoFullProgress: m.photoFullProgress, photoFullFailed: m.photoFullFailed,
    videoFileId: m.videoFileId, videoFileSize: m.videoFileSize, videoMimeType: m.videoMimeType,
    videoFileName: m.videoFileName, videoDuration: m.videoDuration, isAnimation: m.isAnimation,
    videoPath: m.videoPath, videoProgress: m.videoProgress, videoFailed: m.videoFailed,
    mediaDownloadActive: m.mediaDownloadActive,
    voiceWaveform: m.voiceWaveform, voiceListened: m.voiceListened,
    speechState: m.speechState, speechText: m.speechText,
    translatedText: m.translatedText, translatedLang: m.translatedLang,
    translationHidden: m.translationHidden,
    audioTitle: m.audioTitle, audioPerformer: m.audioPerformer,
    stickerFileId: m.stickerFileId, stickerFormat: m.stickerFormat,
    isEmojiSticker: m.isEmojiSticker, stickerPath: m.stickerPath,
    stickerProgress: m.stickerProgress, stickerFailed: m.stickerFailed,
    stickerDownloadActive: m.stickerDownloadActive,
    contactPhone: m.contactPhone, contactFirstName: m.contactFirstName,
    contactLastName: m.contactLastName, contactVcard: m.contactVcard,
    contactUserId: m.contactUserId, contactAvatarPath: m.contactAvatarPath,
    locationLatitude: m.locationLatitude, locationLongitude: m.locationLongitude,
    locationAccuracy: m.locationAccuracy, locationValid: m.locationValid,
    locationLivePeriod: m.locationLivePeriod, locationExpiresIn: m.locationExpiresIn,
    locationHeading: m.locationHeading, locationProximityRadius: m.locationProximityRadius,
    venueTitle: m.venueTitle, venueAddress: m.venueAddress, venueProvider: m.venueProvider,
    venueId: m.venueId, venueType: m.venueType,
    pollId: m.pollId, pollQuestion: m.pollQuestion,
    pollOptions: m.pollOptions.map((option: PollOptionInfo): PollOptionInfo => ({
      text: option.text,
      voterCount: option.voterCount,
      votePercentage: option.votePercentage,
      isChosen: option.isChosen,
      isBeingChosen: option.isBeingChosen
    })),
    pollTotalVoterCount: m.pollTotalVoterCount,
    pollIsAnonymous: m.pollIsAnonymous, pollIsQuiz: m.pollIsQuiz,
    pollAllowMultiple: m.pollAllowMultiple, pollCorrectOptionId: m.pollCorrectOptionId,
    pollExplanation: m.pollExplanation, pollOpenPeriod: m.pollOpenPeriod,
    pollCloseDate: m.pollCloseDate, pollIsClosed: m.pollIsClosed,
    pollVotePending: m.pollVotePending, pollVoteError: m.pollVoteError,
    diceEmoji: m.diceEmoji, diceValue: m.diceValue,
    diceSuccessFrame: m.diceSuccessFrame, diceHasFinalState: m.diceHasFinalState,
    diceLayerFileIds: [...m.diceLayerFileIds], diceLayerPaths: [...m.diceLayerPaths],
    gameId: m.gameId, gameShortName: m.gameShortName, gameTitle: m.gameTitle,
    gameDescription: m.gameDescription, gameText: m.gameText,
    paidMediaLocked: m.paidMediaLocked, paidMediaStarCount: m.paidMediaStarCount,
    paidMediaCount: m.paidMediaCount, paidMediaKind: m.paidMediaKind,
    giftKind: m.giftKind, giftTitle: m.giftTitle, giftValue: m.giftValue,
    giftStatus: m.giftStatus, giftCode: m.giftCode, giftRefunded: m.giftRefunded,
    giveawayState: m.giveawayState, giveawayWinnerCount: m.giveawayWinnerCount,
    giveawayPrize: m.giveawayPrize, giveawayDescription: m.giveawayDescription,
    giveawaySelectionDate: m.giveawaySelectionDate,
    giveawayUnclaimedCount: m.giveawayUnclaimedCount,
    giveawayMessageId: m.giveawayMessageId,
    giveawayBoostedChatId: m.giveawayBoostedChatId,
    giveawayRefunded: m.giveawayRefunded,
    giveawayOnlyNewMembers: m.giveawayOnlyNewMembers,
    customEmojiId: m.customEmojiId
  };
}

interface FwdOrigin {
  name: string;
  chatId: number;
  // Where the forward came from, kept for the tappable "转发自" header. chatId
  // above doubles as a "title still to resolve" marker and gets cleared once
  // resolved, so the origin is recorded separately here.
  originChatId: number;
  originMsgId: number;
  originUserId: number;
}

// Parse a message's forward_info into a display name (user/hidden origin) or a
// chat id to resolve a title for (channel/chat origin).
function forwardOrigin(message: TdObject, users: UserStore): FwdOrigin {
  const fi = message['forward_info'] as TdObject | undefined;
  const origin = fi !== undefined ? (fi['origin'] as TdObject | undefined) : undefined;
  if (origin === undefined) {
    return { name: '', chatId: 0, originChatId: 0, originMsgId: 0, originUserId: 0 };
  }
  const ot = origin['@type'] as string | undefined;
  if (ot === 'messageOriginUser') {
    const uid = (origin['sender_user_id'] as number | undefined) ?? 0;
    return {
      name: users.displayName(uid), chatId: 0,
      originChatId: 0, originMsgId: 0, originUserId: uid
    };
  }
  if (ot === 'messageOriginHiddenUser') {
    // Origin deliberately hidden — nothing to open.
    return {
      name: (origin['sender_name'] as string | undefined) ?? '', chatId: 0,
      originChatId: 0, originMsgId: 0, originUserId: 0
    };
  }
  if (ot === 'messageOriginChannel') {
    const cid = (origin['chat_id'] as number | undefined) ?? 0;
    return {
      name: '', chatId: cid,
      originChatId: cid, originMsgId: (origin['message_id'] as number | undefined) ?? 0,
      originUserId: 0
    };
  }
  if (ot === 'messageOriginChat') {
    const cid = (origin['sender_chat_id'] as number | undefined) ?? 0;
    return {
      name: '', chatId: cid,
      originChatId: cid, originMsgId: 0, originUserId: 0
    };
  }
  return { name: '', chatId: 0, originChatId: 0, originMsgId: 0, originUserId: 0 };
}

export interface CommentInfo {
  count: number;
  replierIds: number[];
}

// Channel posts carry their discussion-group comment count and recent
// commenters in interaction_info.reply_info (messageReplyInfo).
function commentInfo(message: TdObject): CommentInfo {
  return commentInfoFromInteraction(message['interaction_info'] as TdObject | undefined);
}

export function commentInfoFromInteraction(ii: TdObject | undefined): CommentInfo {
  const ri = ii !== undefined ? (ii['reply_info'] as TdObject | undefined) : undefined;
  if (ri === undefined) {
    return { count: 0, replierIds: [] };
  }
  const count = (ri['reply_count'] as number | undefined) ?? 0;
  const repliers = (ri['recent_replier_ids'] as TdObject[] | undefined) ?? [];
  const ids: number[] = [];
  for (const s of repliers) {
    if (s['@type'] === 'messageSenderUser') {
      const uid = s['user_id'] as number | undefined;
      if (uid !== undefined) {
        ids.push(uid);
      }
    }
    if (ids.length >= 3) {
      break;
    }
  }
  return { count, replierIds: ids };
}

interface SystemMessageInfo {
  label: string;
  kind: string;
}

function emptySystemMessage(): SystemMessageInfo {
  return { label: '', kind: 'info' };
}

function actorName(message: TdObject, users: UserStore): string {
  if ((message['is_outgoing'] as boolean | undefined) ?? false) {
    return str('sm_you');
  }
  const actor = senderName(message, users);
  return actor !== '' ? actor : str('cp_someone');
}

function userNames(ids: number[], users: UserStore): string {
  const names: string[] = [];
  for (const id of ids) {
    const name = users.displayName(id);
    if (name !== '') {
      names.push(name);
    } else {
      users.ensure(id);
    }
  }
  return names.join('、');
}

function systemUserIdsOf(content: TdObject | undefined, type: string): number[] {
  if (content === undefined) {
    return [];
  }
  if (type === 'messageChatAddMembers') {
    return ((content['member_user_ids'] as number[] | undefined) ?? []).slice();
  }
  if (type === 'messageInviteVideoChatParticipants') {
    return ((content['user_ids'] as number[] | undefined) ?? []).slice();
  }
  if (type === 'messageChatDeleteMember') {
    const id = (content['user_id'] as number | undefined) ?? 0;
    return id > 0 ? [id] : [];
  }
  return [];
}

// A service row can arrive before updateUser for an invited/removed member.
// Refresh only the name-bearing variants when that user record appears.
export function refreshSystemUserLabel(entry: MessageEntry, users: UserStore): MessageEntry {
  if (entry.contentType !== 'system' || entry.systemUserIds.length === 0) {
    return entry;
  }
  const who = entry.isOutgoing ? str('sm_you') : (entry.senderName !== '' ? entry.senderName : str('cp_someone'));
  let nextLabel = entry.placeholderLabel;
  if (entry.systemType === 'messageChatAddMembers') {
    if (entry.systemUserIds.length === 1 && entry.systemUserIds[0] === entry.senderId) {
      nextLabel = str('sm_joined_group', who);
    } else {
      const names = userNames(entry.systemUserIds, users);
      nextLabel = names !== '' ? str('sm_invited_names', who, names) : str('sm_invited_members', who);
    }
  } else if (entry.systemType === 'messageChatDeleteMember') {
    const targetId = entry.systemUserIds[0];
    if (targetId === entry.senderId) {
      nextLabel = str('sm_left_group', who);
    } else {
      const name = users.displayName(targetId);
      if (name === '') {
        users.ensure(targetId);
      }
      nextLabel = name !== '' ? str('sm_removed_name', who, name) : str('sm_removed_member', who);
    }
  } else if (entry.systemType === 'messageInviteVideoChatParticipants') {
    const names = userNames(entry.systemUserIds, users);
    nextLabel = names !== '' ? str('sm_invited_to_call_names', who, names) : str('sm_invited_to_call', who);
  }
  if (nextLabel === entry.placeholderLabel) {
    return entry;
  }
  const next = cloneMessage(entry);
  next.placeholderLabel = nextLabel;
  return next;
}

// Counted units go through plural(): "1 hour" and "2 hours" differ in English
// even though Chinese has one form.
function compactDuration(totalSeconds: number): string {
  const total = Math.max(0, Math.floor(totalSeconds));
  if (total < 60) {
    return plural('unit_seconds', total, total);
  }
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours > 0) {
    return minutes > 0
      ? str('unit_hours_minutes', hours, minutes) : plural('unit_hours', hours, hours);
  }
  return plural('unit_minutes', minutes, minutes);
}

function autoDeleteDuration(totalSeconds: number): string {
  const seconds = Math.max(0, Math.floor(totalSeconds));
  if (seconds >= 86400 && seconds % 86400 === 0) {
    const days = seconds / 86400;
    return plural('unit_days', days, days);
  }
  if (seconds >= 3600 && seconds % 3600 === 0) {
    const hours = seconds / 3600;
    return plural('unit_hours', hours, hours);
  }
  if (seconds >= 60 && seconds % 60 === 0) {
    const minutes = seconds / 60;
    return plural('unit_minutes', minutes, minutes);
  }
  return compactDuration(seconds);
}

function scheduledDateLabel(unixSeconds: number): string {
  if (unixSeconds <= 0) {
    return '';
  }
  // Date and time in one Intl formatter: the separator and the field order are
  // locale business, and the app already renders this shape elsewhere.
  return monthDayTime(new Date(unixSeconds * 1000));
}

function senderUserName(sender: TdObject | undefined, users: UserStore): string {
  if (sender === undefined || sender['@type'] !== 'messageSenderUser') {
    return '';
  }
  const id = (sender['user_id'] as number | undefined) ?? 0;
  return id > 0 ? users.displayName(id) : '';
}

function systemKindOf(type: string): string {
  if (type === 'messagePinMessage') {
    return 'pin';
  }
  if (type.indexOf('VideoChat') >= 0 || type === 'messageCall') {
    return 'call';
  }
  if (type.indexOf('Member') >= 0 || type.indexOf('Join') >= 0 ||
    type.indexOf('Owner') >= 0 || type === 'messageContactRegistered') {
    return 'people';
  }
  if (type.indexOf('AutoDelete') >= 0) {
    return 'timer';
  }
  if (type.indexOf('ForumTopic') >= 0) {
    return 'topic';
  }
  if (type.indexOf('Gift') >= 0 || type.indexOf('Giveaway') >= 0 ||
    type.indexOf('Paid') >= 0 || type.indexOf('Payment') >= 0) {
    return 'payment';
  }
  if (type.indexOf('ProtectedContent') >= 0 || type === 'messageScreenshotTaken' ||
    type === 'messagePassportDataSent' || type === 'messagePassportDataReceived') {
    return 'security';
  }
  return 'info';
}

// Service/system messages (chat title/photo changes, member joins, pinned
// notices, ...) rendered as a centered pill instead of a normal bubble.
// Returns an empty label when the content type isn't a recognized service row.
function systemMessageInfo(message: TdObject, users: UserStore): SystemMessageInfo {
  const content = message['content'] as TdObject | undefined;
  const type = content !== undefined ? (content['@type'] as string | undefined) : undefined;
  if (content === undefined || type === undefined) {
    return emptySystemMessage();
  }
  // These content types have dedicated cards. Let formatMsgContent own them
  // instead of collapsing their actionable state into a generic system pill.
  const richSpecialTypes: string[] = [
    'messagePaidMedia', 'messageGiftedPremium', 'messageGiftedStars',
    'messageGiftedTon', 'messagePremiumGiftCode', 'messageGift',
    'messageUpgradedGift', 'messageGiveaway',
    'messageGiveawayWinners', 'messageGiveawayCompleted',
    'messageGiveawayPrizeStars'
  ];
  if (richSpecialTypes.indexOf(type) >= 0) {
    return emptySystemMessage();
  }
  const who = actorName(message, users);
  const kind = systemKindOf(type);
  if (type === 'messageChatChangeTitle') {
    const title = ((content['title'] as string | undefined) ?? '').trim();
    return { label: title !== '' ? str('sm_renamed_group', who, title) : str('sm_changed_group_name', who), kind };
  }
  if (type === 'messageChatChangePhoto') {
    return { label: str('sm_updated_group_photo', who), kind };
  }
  if (type === 'messageChatDeletePhoto') {
    return { label: str('sm_removed_group_photo', who), kind };
  }
  if (type === 'messageChatAddMembers') {
    const ids = (content['member_user_ids'] as number[] | undefined) ?? [];
    const actorId = senderIdOf(message);
    if (ids.length === 1 && actorId > 0 && ids[0] === actorId) {
      return {
        label: ((message['is_outgoing'] as boolean | undefined) ?? false)
          ? str('cp_joined_group') : str('sm_joined_group', who),
        kind
      };
    }
    const names = userNames(ids, users);
    return { label: names !== '' ? str('sm_invited_names', who, names) : str('sm_invited_members', who), kind };
  }
  if (type === 'messageChatDeleteMember') {
    const uid = content['user_id'] as number | undefined;
    const name = uid !== undefined ? users.displayName(uid) : '';
    if (uid !== undefined && uid > 0 && uid === senderIdOf(message)) {
      return { label: str('sm_left_group', who), kind };
    }
    return { label: name !== '' ? str('sm_removed_name', who, name) : str('sm_removed_member', who), kind };
  }
  if (type === 'messageChatJoinByLink') {
    return {
      label: ((message['is_outgoing'] as boolean | undefined) ?? false)
        ? str('cp_joined_group') : str('sm_joined_by_link', who),
      kind
    };
  }
  if (type === 'messageChatSetMessageAutoDeleteTime') {
    const secs = (content['message_auto_delete_time'] as number | undefined) ?? 0;
    const fromUserId = (content['from_user_id'] as number | undefined) ?? 0;
    if (secs <= 0) {
      return { label: str('sm_auto_delete_off', who), kind };
    }
    const duration = autoDeleteDuration(secs);
    const fromName = fromUserId > 0 ? users.displayName(fromUserId) : '';
    if (fromName !== '' && fromUserId !== senderIdOf(message)) {
      return { label: str('sm_auto_delete_default', fromName, duration), kind };
    }
    return { label: str('sm_auto_delete_set', who, duration), kind };
  }
  if (type === 'messageChatJoinByRequest') {
    return {
      label: ((message['is_outgoing'] as boolean | undefined) ?? false)
        ? str('cp_joined_group') : str('sm_join_request_approved', who),
      kind
    };
  }
  if (type === 'messageChatUpgradeTo' || type === 'messageChatUpgradeFrom') {
    return { label: str('sm_upgraded_supergroup'), kind };
  }
  if (type === 'messagePinMessage') {
    return { label: str('sm_pinned_message', who), kind };
  }
  if (type === 'messageBasicGroupChatCreate' || type === 'messageSupergroupChatCreate') {
    const title = ((content['title'] as string | undefined) ?? '').trim();
    return { label: title !== '' ? str('sm_created_group_named', who, title) : str('sm_created_group', who), kind };
  }
  if (type === 'messageContactRegistered') {
    return { label: str('sm_joined_telegram', who), kind };
  }
  if (type === 'messageChatSetTheme') {
    const themeName = ((content['theme_name'] as string | undefined) ?? '').trim();
    return {
      label: themeName !== '' ? str('sm_set_theme', who, themeName) : str('sm_theme_off', who),
      kind
    };
  }
  if (type === 'messageChatSetBackground') {
    return { label: str('sm_changed_background', who), kind };
  }
  if (type === 'messageScreenshotTaken') {
    return { label: str('sm_screenshot', who), kind };
  }
  if (type === 'messageChatHasProtectedContentDisableRequested') {
    return { label: str('sm_protection_request', who), kind };
  }
  if (type === 'messageChatHasProtectedContentToggled') {
    const oldProtected = (content['old_has_protected_content'] as boolean | undefined) ?? false;
    const newProtected = (content['new_has_protected_content'] as boolean | undefined) ?? false;
    const requestId = (content['request_message_id'] as number | undefined) ?? 0;
    if (requestId !== 0 && oldProtected === newProtected) {
      return { label: str('sm_protection_request_denied'), kind };
    }
    return { label: str('sm_protection_toggled', who, newProtected ? str('sm_turned_on') : str('sm_turned_off')), kind };
  }
  if (type === 'messageChatBoost') {
    const count = Math.max(0, (content['boost_count'] as number | undefined) ?? 0);
    return {
      label: count > 1 ? str('sm_boosted_n', who, count) : str('sm_boosted', who),
      kind: 'payment'
    };
  }
  if (type === 'messageForumTopicCreated') {
    const name = ((content['name'] as string | undefined) ?? '').trim();
    return { label: name !== '' ? str('sm_created_topic_named', who, name) : str('sm_created_topic', who), kind };
  }
  if (type === 'messageForumTopicEdited') {
    const name = ((content['name'] as string | undefined) ?? '').trim();
    return {
      label: name !== '' ? str('sm_renamed_topic', who, name) : str('sm_changed_topic_icon', who),
      kind
    };
  }
  if (type === 'messageForumTopicIsClosedToggled') {
    const closed = (content['is_closed'] as boolean | undefined) ?? false;
    return { label: str('sm_topic_toggled', who, closed ? str('sm_closed_word') : str('sm_reopened_word')), kind };
  }
  if (type === 'messageForumTopicIsHiddenToggled') {
    const hidden = (content['is_hidden'] as boolean | undefined) ?? false;
    return { label: str('sm_general_topic_toggled', who, hidden ? str('sm_hid_word') : str('sm_showed_word')), kind };
  }
  if (type === 'messageVideoChatScheduled') {
    const scheduled = scheduledDateLabel((content['start_date'] as number | undefined) ?? 0);
    return {
      label: scheduled !== '' ? str('sm_scheduled_call_at', who, scheduled) : str('sm_scheduled_call', who),
      kind
    };
  }
  if (type === 'messageVideoChatStarted') {
    return { label: str('sm_started_call', who), kind };
  }
  if (type === 'messageVideoChatEnded') {
    const duration = (content['duration'] as number | undefined) ?? 0;
    return {
      label: duration > 0 ? str('sm_call_ended_after', compactDuration(duration)) : str('sm_call_ended'),
      kind
    };
  }
  if (type === 'messageInviteVideoChatParticipants') {
    const names = userNames((content['user_ids'] as number[] | undefined) ?? [], users);
    return {
      label: names !== '' ? str('sm_invited_to_call_names', who, names) : str('sm_invited_to_call', who),
      kind
    };
  }
  if (type === 'messageCall') {
    const duration = (content['duration'] as number | undefined) ?? 0;
    const video = (content['is_video'] as boolean | undefined) ?? false;
    const reason = content['discard_reason'] as TdObject | undefined;
    const reasonType = reason !== undefined ? ((reason['@type'] as string | undefined) ?? '') : '';
    const callLabel = video ? str('sm_video_call') : str('sm_voice_call');
    if (duration > 0) {
      return { label: `${callLabel} · ${compactDuration(duration)}`, kind };
    }
    if (reasonType === 'callDiscardReasonMissed' || reasonType === 'callDiscardReasonDeclined') {
      return {
        label: ((message['is_outgoing'] as boolean | undefined) ?? false)
          ? str('sm_call_not_answered', callLabel) : str('sm_missed_call', video ? str('sm_video_call_word') : str('sm_call_word')),
        kind
      };
    }
    return { label: callLabel, kind };
  }
  if (type === 'messageProximityAlertTriggered') {
    const traveler = senderUserName(content['traveler_id'] as TdObject | undefined, users);
    const watcher = senderUserName(content['watcher_id'] as TdObject | undefined, users);
    const distance = Math.max(0, (content['distance'] as number | undefined) ?? 0);
    if (traveler !== '' && watcher !== '') {
      return {
        label: str('sm_proximity', traveler, watcher,
          distance > 0 ? plural('sm_proximity_metres', distance, distance)
            : str('sm_proximity_near')),
        kind: 'people'
      };
    }
    return { label: str('sm_proximity_triggered'), kind: 'people' };
  }
  if (type === 'messageCustomServiceAction') {
    const text = ((content['text'] as string | undefined) ?? '').trim();
    return { label: text !== '' ? text : str('preview_chat_state_updated'), kind };
  }
  if (type === 'messagePaidMessagePriceChanged') {
    const stars = Math.max(0, (content['paid_message_star_count'] as number | undefined) ?? 0);
    return {
      label: stars > 0 ? plural('sm_paid_per_message', stars, stars) : str('sm_paid_messages_off'),
      kind
    };
  }
  if (type === 'messagePaidMessagesRefunded') {
    const count = Math.max(0, (content['message_count'] as number | undefined) ?? 0);
    const stars = Math.max(0, (content['star_count'] as number | undefined) ?? 0);
    if (count > 0 && stars > 0) {
      return { label: str('sm_paid_refunded_n', count, stars), kind };
    }
    return { label: stars > 0 ? plural('sm_refunded_stars', stars, stars) : str('sm_paid_refunded'), kind };
  }
  // Channel direct-message (paid DM) settings — show the concrete star price /
  // enabled state, matching the official client's wording.
  if (type === 'messageDirectMessagePriceChanged') {
    const enabled = (content['is_enabled'] as boolean | undefined) ?? false;
    const stars = (content['paid_message_star_count'] as number | undefined) ?? 0;
    if (!enabled) {
      return { label: str('sm_channel_dm_off'), kind };
    }
    return {
      label: stars > 0 ? plural('sm_channel_dm_price', stars, stars) : str('sm_channel_dm_on'),
      kind
    };
  }
  // Fallback for other service messages (video chats, gifts, giveaways, forum
  // topics, payments, …) → shown as a centered pill.
  const svcKey: string | undefined = SERVICE_LABEL_KEYS[type];
  if (svcKey !== undefined) {
    return { label: str(svcKey), kind };
  }
  return emptySystemMessage();
}

// Content types intentionally hidden from the timeline. Empty by default — all
// service messages are now surfaced as centered pills via systemMessageInfo /
// SERVICE_LABELS instead of being hidden.
const HIDDEN_CONTENT_TYPES: string[] = [];

function isHiddenContent(message: TdObject): boolean {
  const content = message['content'] as TdObject | undefined;
  const t = content !== undefined ? (content['@type'] as string | undefined) : undefined;
  return t !== undefined && HIDDEN_CONTENT_TYPES.indexOf(t) >= 0;
}

function reactions(message: TdObject): ReactionInfo[] {
  return reactionsFromInteraction(message['interaction_info'] as TdObject | undefined);
}

export function reactionsFromInteraction(ii: TdObject | undefined): ReactionInfo[] {
  const rx = ii !== undefined ? (ii['reactions'] as TdObject | undefined) : undefined;
  const list = rx !== undefined ? (rx['reactions'] as TdObject[] | undefined) : undefined;
  if (list === undefined) {
    return [];
  }
  const out: ReactionInfo[] = [];
  for (const r of list) {
    const t = r['type'] as TdObject | undefined;
    const tt = t !== undefined ? ((t['@type'] as string | undefined) ?? '') : '';
    let emoji = '';
    let customEmojiId = '';
    if (tt === 'reactionTypeEmoji') {
      emoji = (t!['emoji'] as string | undefined) ?? '';
    } else if (tt === 'reactionTypePaid') {
      emoji = '⭐';
    } else if (tt === 'reactionTypeCustomEmoji') {
      // 位图要等 getCustomEmojiStickers + 下载，这里只记 id，路径由
      // MessageStore 解析完成后回填（未就绪时气泡显示占位而非空白）。
      const raw = t!['custom_emoji_id'];
      customEmojiId = raw !== undefined ? `${raw}` : '';
      if (customEmojiId === '' || customEmojiId === '0') {
        continue;
      }
    } else {
      continue; // 未知反应类型（未来的 TDLib 扩展）静默跳过
    }
    out.push({
      emoji,
      count: (r['total_count'] as number | undefined) ?? 0,
      isChosen: (r['is_chosen'] as boolean | undefined) ?? false,
      customEmojiId,
      customEmojiPath: ''
    });
  }
  return out;
}

function albumIdOf(message: TdObject): string {
  const v = message['media_album_id'];
  if (v === undefined) {
    return '';
  }
  const s = `${v}`;
  return s === '0' ? '' : s;
}

function senderName(message: TdObject, users: UserStore): string {
  const sender = message['sender_id'] as TdObject | undefined;
  if (sender === undefined) {
    return '';
  }
  if (sender['@type'] === 'messageSenderUser') {
    return users.displayName(sender['user_id'] as number);
  }
  return '';
}

function senderIdOf(message: TdObject): number {
  const sender = message['sender_id'] as TdObject | undefined;
  if (sender === undefined) {
    return 0;
  }
  const st = sender['@type'] as string | undefined;
  if (st === 'messageSenderUser') {
    return (sender['user_id'] as number | undefined) ?? 0;
  }
  if (st === 'messageSenderChat') {
    return (sender['chat_id'] as number | undefined) ?? 0;
  }
  return 0;
}

function senderIsUserOf(message: TdObject): boolean {
  const sender = message['sender_id'] as TdObject | undefined;
  return sender !== undefined && sender['@type'] === 'messageSenderUser';
}

function outgoingState(message: TdObject): string {
  const st = message['sending_state'] as TdObject | undefined;
  if (st === undefined) {
    return 'sent';
  }
  if (st['@type'] === 'messageSendingStatePending') {
    return 'sending';
  }
  if (st['@type'] === 'messageSendingStateFailed') {
    return 'failed';
  }
  return 'sent';
}

function replyId(message: TdObject): number {
  const r = message['reply_to'] as TdObject | undefined;
  if (r === undefined || r['@type'] !== 'messageReplyToMessage') {
    return 0;
  }
  return (r['message_id'] as number | undefined) ?? 0;
}

// messageReplyToMessage.quote 里带着被引用的那段文字（用户划选的片段）。
// 它是自带的，不依赖原消息是否已加载 —— 桌面端就是直接渲染它。之前只取了
// message_id，原消息不在已加载窗口里时引用块就是空的。
function replyQuoteText(message: TdObject): string {
  const r = message['reply_to'] as TdObject | undefined;
  if (r === undefined || r['@type'] !== 'messageReplyToMessage') {
    return '';
  }
  const quote = r['quote'] as TdObject | undefined;
  const text = quote !== undefined ? (quote['text'] as TdObject | undefined) : undefined;
  return text !== undefined ? ((text['text'] as string | undefined) ?? '') : '';
}

function inlineCustomEmojiIds(entities: TdObject[]): string[] {
  const ids: string[] = [];
  for (const entity of entities) {
    const type = entity['type'] as TdObject | undefined;
    if (type === undefined || type['@type'] !== 'textEntityTypeCustomEmoji') {
      continue;
    }
    const id = `${type['custom_emoji_id'] ?? ''}`;
    if (id !== '' && ids.indexOf(id) < 0) {
      ids.push(id);
    }
  }
  return ids;
}

export function buildMessageEntry(message: TdObject, users: UserStore): MessageEntry {
  const c: MsgContent = formatMsgContent(message);
  const isOutgoing = (message['is_outgoing'] as boolean | undefined) ?? false;
  const name = senderName(message, users);
  const fwd: FwdOrigin = forwardOrigin(message, users);
  const cmt: CommentInfo = commentInfo(message);
  const sys = systemMessageInfo(message, users);
  const hidden = isHiddenContent(message);
  const rawContent = message['content'] as TdObject | undefined;
  const rawType = rawContent !== undefined
    ? ((rawContent['@type'] as string | undefined) ?? '') : '';
  const isVideoChatStarted = !hidden && rawContent !== undefined
    && rawContent['@type'] === 'messageVideoChatStarted';
  // Log genuinely unhandled content types — not hidden, not given a description
  // (still the bare 'Message' fallback) — so missing types surface in hilog.
  if (!hidden && c.contentType === 'other') {
    const rc = message['content'] as TdObject | undefined;
    const rt = rc !== undefined ? ((rc['@type'] as string | undefined) ?? 'unknown') : 'unknown';
    logW(`[UNHANDLED_MSG] type=${rt} id=${(message['id'] as number | undefined) ?? 0}`);
  }
  return {
    id: (message['id'] as number | undefined) ?? 0,
    rowId: (message['id'] as number | undefined) ?? 0,
    isOutgoing,
    senderName: name,
    senderTag: (message['sender_tag'] as string | undefined) ?? '',
    senderId: senderIdOf(message),
    senderIsUser: senderIsUserOf(message),
    senderInitials: name.length > 0 ? name.substring(0, 1).toUpperCase() : '?',
    senderAvatarPath: '',
    date: (message['date'] as number | undefined) ?? 0,
    editDate: (message['edit_date'] as number | undefined) ?? 0,
    contentType: hidden ? 'hidden' : (sys.label !== '' ? 'system' : c.contentType),
    text: c.text,
    photoFileId: c.photoFileId,
    photoPath: c.photoLocalPath ?? '',
    photoProgress: c.photoLocalPath !== undefined && c.photoLocalPath !== ''
      ? 100 : (c.photoInitialProgress ?? 0),
    photoFailed: false,
    photoWidth: c.photoWidth,
    photoHeight: c.photoHeight,
    placeholderLabel: sys.label !== '' ? sys.label : c.placeholderLabel,
    richBlocks: c.richBlocks,
    systemKind: sys.kind,
    systemType: sys.label !== '' ? rawType : '',
    systemUserIds: sys.label !== '' ? systemUserIdsOf(rawContent, rawType) : [],
    isUnsupportedMessage: !hidden && sys.label === '' && c.contentType === 'other',
    isVideoChatStarted,
    replyToMessageId: replyId(message),
    replySenderName: '',
    replyText: replyQuoteText(message),
    sendState: isOutgoing ? outgoingState(message) : 'none',
    albumId: albumIdOf(message),
    textEntities: c.entities,
    inlineCustomEmojiIds: inlineCustomEmojiIds(c.entities),
    inlineCustomEmojiPaths: [],
    forwardFrom: fwd.name,
    forwardChatId: fwd.chatId,
    forwardOriginChatId: fwd.originChatId,
    forwardOriginMsgId: fwd.originMsgId,
    forwardOriginUserId: fwd.originUserId,
    commentCount: cmt.count,
    commentReplierIds: cmt.replierIds,
    commentReplierAvatarPaths: [],
    linkSiteName: c.linkSiteName,
    linkTitle: c.linkTitle,
    linkDescription: c.linkDescription,
    linkDescriptionEntities: c.linkDescriptionEntities,
    linkPhotoFileId: c.linkPhotoFileId,
    linkPhotoPath: c.linkPhotoLocalPath ?? '',
    linkPhotoWidth: c.linkPhotoWidth ?? 0,
    linkPhotoHeight: c.linkPhotoHeight ?? 0,
    linkPhotoProgress: c.linkPhotoLocalPath !== undefined && c.linkPhotoLocalPath !== ''
      ? 100 : (c.linkPhotoInitialProgress ?? 0),
    linkPhotoFailed: false,
    linkPhotoDownloadActive: c.linkPhotoInitialActive ?? false,
    linkPreviewType: c.linkPreviewType ?? '',
    linkUrl: c.linkUrl,
    reactions: reactions(message),
    inlineButtons: parseInlineKeyboard(message['reply_markup'] as TdObject | undefined),
    photoFullFileId: c.photoFullFileId,
    photoFullPath: '',
    photoFullProgress: 0,
    photoFullFailed: false,
    videoFileId: c.videoFileId,
    videoFileSize: c.videoFileSize,
    videoMimeType: c.videoMimeType,
    videoFileName: c.videoFileName,
    videoDuration: c.videoDuration,
    isAnimation: c.isAnimation ?? false,
    videoPath: c.videoLocalPath ?? '',
    videoProgress: c.videoLocalPath !== undefined && c.videoLocalPath !== ''
      ? 100 : (c.videoInitialProgress ?? 0),
    videoFailed: false,
    mediaDownloadActive: c.videoInitialActive ?? false,
    voiceWaveform: c.voiceWaveform ?? '',
    voiceListened: isOutgoing || (c.voiceListened ?? false),
    speechState: c.speechState ?? '',
    speechText: c.speechText ?? '',
    // 译文不从 TDLib 消息构建——它由 TranslationService 事后写入。
    // buildMessageEntry 重建条目（内容更新/发送成功）时译文清空，由可见范围
    // 驱动器按新内容重新翻译。
    translatedText: '',
    translatedLang: '',
    translationHidden: false,
    audioTitle: c.audioTitle ?? '',
    audioPerformer: c.audioPerformer ?? '',
    stickerFileId: c.stickerFileId ?? 0,
    stickerFormat: c.stickerFormat ?? '',
    isEmojiSticker: c.isEmojiSticker ?? false,
    stickerPath: c.stickerLocalPath ?? '',
    stickerProgress: c.stickerLocalPath !== undefined && c.stickerLocalPath !== ''
      ? 100 : (c.stickerInitialProgress ?? 0),
    stickerFailed: false,
    stickerDownloadActive: c.stickerInitialActive ?? false,
    contactPhone: c.contactPhone ?? '',
    contactFirstName: c.contactFirstName ?? '',
    contactLastName: c.contactLastName ?? '',
    contactVcard: c.contactVcard ?? '',
    contactUserId: c.contactUserId ?? 0,
    contactAvatarPath: '',
    locationLatitude: c.locationLatitude ?? 0,
    locationLongitude: c.locationLongitude ?? 0,
    locationAccuracy: c.locationAccuracy ?? 0,
    locationValid: c.locationValid ?? false,
    locationLivePeriod: c.locationLivePeriod ?? 0,
    locationExpiresIn: c.locationExpiresIn ?? 0,
    locationHeading: c.locationHeading ?? 0,
    locationProximityRadius: c.locationProximityRadius ?? 0,
    venueTitle: c.venueTitle ?? '',
    venueAddress: c.venueAddress ?? '',
    venueProvider: c.venueProvider ?? '',
    venueId: c.venueId ?? '',
    venueType: c.venueType ?? '',
    pollId: c.pollId ?? '',
    pollQuestion: c.pollQuestion ?? '',
    pollOptions: c.pollOptions ?? [],
    pollTotalVoterCount: c.pollTotalVoterCount ?? 0,
    pollIsAnonymous: c.pollIsAnonymous ?? true,
    pollIsQuiz: c.pollIsQuiz ?? false,
    pollAllowMultiple: c.pollAllowMultiple ?? false,
    pollCorrectOptionId: c.pollCorrectOptionId ?? -1,
    pollExplanation: c.pollExplanation ?? '',
    pollOpenPeriod: c.pollOpenPeriod ?? 0,
    pollCloseDate: c.pollCloseDate ?? 0,
    pollIsClosed: c.pollIsClosed ?? false,
    pollVotePending: false,
    pollVoteError: '',
    diceEmoji: c.diceEmoji ?? '',
    diceValue: c.diceValue ?? 0,
    diceSuccessFrame: c.diceSuccessFrame ?? 0,
    diceHasFinalState: c.diceHasFinalState ?? false,
    diceLayerFileIds: c.diceLayerFileIds ?? [],
    diceLayerPaths: c.diceLayerPaths ?? [],
    gameId: c.gameId ?? '',
    gameShortName: c.gameShortName ?? '',
    gameTitle: c.gameTitle ?? '',
    gameDescription: c.gameDescription ?? '',
    gameText: c.gameText ?? '',
    paidMediaLocked: c.paidMediaLocked ?? false,
    paidMediaStarCount: c.paidMediaStarCount ?? 0,
    paidMediaCount: c.paidMediaCount ?? 0,
    paidMediaKind: c.paidMediaKind ?? '',
    giftKind: c.giftKind ?? '',
    giftTitle: c.giftTitle ?? '',
    giftValue: c.giftValue ?? '',
    giftStatus: c.giftStatus ?? '',
    giftCode: c.giftCode ?? '',
    giftRefunded: c.giftRefunded ?? false,
    giveawayState: c.giveawayState ?? '',
    giveawayWinnerCount: c.giveawayWinnerCount ?? 0,
    giveawayPrize: c.giveawayPrize ?? '',
    giveawayDescription: c.giveawayDescription ?? '',
    giveawaySelectionDate: c.giveawaySelectionDate ?? 0,
    giveawayUnclaimedCount: c.giveawayUnclaimedCount ?? 0,
    giveawayMessageId: c.giveawayMessageId ?? 0,
    giveawayBoostedChatId: c.giveawayBoostedChatId ?? 0,
    giveawayRefunded: c.giveawayRefunded ?? false,
    giveawayOnlyNewMembers: c.giveawayOnlyNewMembers ?? false,
    customEmojiId: c.customEmojiId ?? ''
  };
}
