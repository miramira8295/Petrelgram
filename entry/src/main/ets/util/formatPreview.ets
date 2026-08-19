import { str } from './strings';
import { flattenRichMessage } from './richMessage';
import { TdObject } from '../tdkit/TdTypes';

function captionText(content: TdObject): string {
  const cap = content['caption'] as TdObject | undefined;
  if (cap === undefined) {
    return '';
  }
  const t = cap['text'] as string | undefined;
  return t ?? '';
}

function mediaLabel(icon: string, word: string, content: TdObject): string {
  const cap = captionText(content);
  return cap !== '' ? `${icon} ${cap}` : `${icon} ${word}`;
}

// Chinese labels for service / status messages so the chat-list preview (and the
// bubble placeholder) never falls back to the bare English 'Message'.
// Values are resource keys, not copy: this is a module-level constant, so a
// resolved string would be produced before the string source is installed and
// would never follow a language change. Callers resolve with str().
export const SERVICE_LABEL_KEYS: Record<string, string> = {
  // Group / channel operations
  'messageChatAddMembers': 'service_chat_add_members',
  'messageChatDeleteMember': 'service_chat_delete_member',
  'messageChatChangeTitle': 'service_chat_change_title',
  'messageChatChangePhoto': 'service_chat_change_photo',
  'messageChatDeletePhoto': 'service_chat_delete_photo',
  'messageChatJoinByLink': 'service_chat_join_by_link',
  'messageChatJoinByRequest': 'service_chat_join_by_request',
  'messagePinMessage': 'service_pin_message',
  'messageChatSetMessageAutoDeleteTime': 'service_chat_set_message_auto_delete_time',
  'messageBasicGroupChatCreate': 'service_basic_group_chat_create',
  'messageSupergroupChatCreate': 'service_supergroup_chat_create',
  'messageChatUpgradeTo': 'service_chat_upgrade_to',
  'messageChatUpgradeFrom': 'service_chat_upgrade_from',
  // Membership / social notices
  'messageContactRegistered': 'service_contact_registered',
  'messageChatSetTheme': 'service_chat_set_theme',
  'messageChatSetBackground': 'service_chat_set_background',
  'messageChatHasProtectedContentDisableRequested': 'service_chat_has_protected_content_disable_requested',
  'messageChatHasProtectedContentToggled': 'service_chat_has_protected_content_toggled',
  'messageChatOwnerChanged': 'service_chat_owner_changed',
  'messageChatOwnerLeft': 'service_chat_owner_left',
  'messageScreenshotTaken': 'service_screenshot_taken',
  'messageChatBoost': 'service_chat_boost',
  // Forum topics
  'messageForumTopicCreated': 'service_forum_topic_created',
  'messageForumTopicEdited': 'service_forum_topic_edited',
  'messageForumTopicIsClosedToggled': 'service_forum_topic_is_closed_toggled',
  'messageForumTopicIsHiddenToggled': 'service_forum_topic_is_hidden_toggled',
  // Video / voice chats
  'messageVideoChatScheduled': 'service_video_chat_scheduled',
  'messageVideoChatStarted': 'service_video_chat_started',
  'messageVideoChatEnded': 'service_video_chat_ended',
  'messageInviteVideoChatParticipants': 'service_invite_video_chat_participants',
  'messageProximityAlertTriggered': 'service_proximity_alert_triggered',
  // Gifts / premium / giveaways
  'messageGiftedPremium': 'service_gifted_premium',
  'messageGiftedStars': 'service_gifted_stars',
  'messagePremiumGiftCode': 'service_premium_gift_code',
  'messageGift': 'service_gift',
  'messageUpgradedGift': 'service_upgraded_gift',
  'messageGiveawayCreated': 'service_giveaway_created',
  'messageGiveaway': 'service_giveaway',
  'messageGiveawayCompleted': 'service_giveaway_completed',
  'messageGiveawayWinners': 'service_giveaway_winners',
  'messageGiveawayPrizeStars': 'service_giveaway_prize_stars',
  // Payments / passport / bot access / sharing
  'messagePaymentSuccessful': 'service_payment_successful',
  'messagePaymentSuccessfulBot': 'service_payment_successful_bot',
  'messagePaymentRefunded': 'service_payment_refunded',
  'messagePassportDataSent': 'service_passport_data_sent',
  'messagePassportDataReceived': 'service_passport_data_received',
  'messageWebAppDataSent': 'service_web_app_data_sent',
  'messageWebAppDataReceived': 'service_web_app_data_received',
  'messageBotWriteAccessAllowed': 'service_bot_write_access_allowed',
  'messageUsersShared': 'service_users_shared',
  'messageChatShared': 'service_chat_shared',
  'messageGameScore': 'service_game_score',
  // Channel paid / direct messages
  'messageDirectMessagePriceChanged': 'service_direct_message_price_changed',
  'messagePaidMessagePriceChanged': 'service_paid_message_price_changed',
  'messagePaidMessagesRefunded': 'service_paid_messages_refunded',
  'messageCustomServiceAction': 'service_custom_service_action',
  'messageCall': 'service_call'
};

// Pull any embedded text/caption from an otherwise-unhandled content object.
function embeddedText(content: TdObject): string {
  const cap = content['caption'] as TdObject | undefined;
  const capText = cap !== undefined ? ((cap['text'] as string | undefined) ?? '') : '';
  if (capText !== '') {
    return capText;
  }
  const rawText = content['text'];
  if (typeof rawText === 'string') {
    return rawText;
  }
  const txt = rawText as TdObject | undefined;
  return txt !== undefined ? ((txt['text'] as string | undefined) ?? '') : '';
}

export function formatPreview(message: TdObject | null): string {
  if (message === null) {
    return '';
  }
  const rawContent = message['content'];
  if (rawContent === undefined || rawContent === null) {
    return '';
  }
  const content = rawContent as TdObject;
  const type = content['@type'] as string;
  if (type === 'messageText') {
    const text = content['text'] as TdObject | undefined;
    if (text === undefined) {
      return '';
    }
    const inner = text['text'] as string | undefined;
    return inner ?? '';
  }
  if (type === 'messagePhoto') {
    return mediaLabel('📷', str('preview_photo'), content);
  }
  if (type === 'messageVideo') {
    return mediaLabel('📹', str('preview_video'), content);
  }
  if (type === 'messageVoiceNote') {
    return str('preview_voice');
  }
  if (type === 'messageDocument') {
    return mediaLabel('📎', str('preview_file'), content);
  }
  if (type === 'messageSticker') {
    const st = content['sticker'] as TdObject | undefined;
    const emoji = st !== undefined ? (st['emoji'] as string) : '';
    return emoji !== '' && emoji !== undefined ? str('preview_sticker_emoji', emoji) : str('preview_sticker');
  }
  if (type === 'messageAnimation') {
    return 'GIF';
  }
  if (type === 'messageAudio') {
    return str('preview_music');
  }
  if (type === 'messageLocation') {
    return str('preview_location');
  }
  if (type === 'messageLiveLocation') {
    return str('preview_live_location');
  }
  if (type === 'messageVenue') {
    return str('preview_venue');
  }
  if (type === 'messageContact') {
    return str('preview_contact');
  }
  if (type === 'messagePoll') {
    const poll = content['poll'] as TdObject | undefined;
    const q = poll !== undefined ? ((poll['question'] as TdObject | undefined)) : undefined;
    const qText = q !== undefined ? ((q['text'] as string | undefined) ?? '') : '';
    return qText !== '' ? str('preview_poll_question', qText) : str('preview_poll');
  }
  if (type === 'messageDice') {
    const e = content['emoji'] as string | undefined;
    return e !== undefined && e !== '' ? e : '🎲';
  }
  if (type === 'messageVideoNote') {
    return str('preview_video_note');
  }
  if (type === 'messageCall') {
    return str('preview_call');
  }
  if (type === 'messageExpiredPhoto') {
    return str('preview_photo_expired');
  }
  if (type === 'messageExpiredVideo') {
    return str('preview_video_expired');
  }
  if (type === 'messageExpiredVideoNote') {
    return str('preview_video_note_expired');
  }
  if (type === 'messageExpiredVoiceNote') {
    return str('preview_voice_expired');
  }
  if (type === 'messageRichMessage') {
    // 富文本长帖：摊平后取正文，会话列表里就不再是一行"暂不支持"。
    const flat = flattenRichMessage(content);
    if (flat.text !== '') {
      return flat.text.replace(/\n+/g, ' ');
    }
  }
  if (type === 'messageUnsupported') {
    return str('preview_unsupported');
  }
  if (type === 'messageStory') {
    return str('preview_story');
  }
  if (type === 'messageGame') {
    return str('preview_game');
  }
  if (type === 'messageInvoice') {
    return str('preview_invoice');
  }
  if (type === 'messagePaidMedia') {
    const stars = Math.max(0, (content['star_count'] as number | undefined) ?? 0);
    return stars > 0 ? str('preview_paid_stars', stars) : str('preview_paid');
  }
  if (type === 'messageGiftedStars') {
    const stars = Math.max(0, (content['star_count'] as number | undefined) ?? 0);
    return stars > 0 ? str('preview_gift_stars_n', stars) : str('preview_gift_stars');
  }
  if (type === 'messageGiftedTon') {
    return str('preview_gift_ton');
  }
  if (type === 'messageGiftedPremium') {
    const months = Math.max(0, (content['month_count'] as number | undefined) ?? 0);
    return months > 0 ? str('preview_gift_premium_n', months) : str('preview_gift_premium');
  }
  if (type === 'messagePremiumGiftCode') {
    return str('preview_premium_code');
  }
  if (type === 'messageGift') {
    return ((content['was_refunded'] as boolean | undefined) ?? false)
      ? str('preview_gift_refunded') : str('preview_gift');
  }
  if (type === 'messageUpgradedGift') {
    const gift = content['gift'] as TdObject | undefined;
    const title = gift !== undefined ? ((gift['title'] as string | undefined) ?? '') : '';
    return title !== '' ? str('preview_gift_titled', title) : str('preview_gift_collectible');
  }
  if (type === 'messageGiveaway') {
    return str('preview_giveaway');
  }
  if (type === 'messageGiveawayWinners' || type === 'messageGiveawayCompleted') {
    return str('preview_giveaway_results');
  }
  if (type === 'messageGiveawayPrizeStars') {
    const stars = Math.max(0, (content['star_count'] as number | undefined) ?? 0);
    return stars > 0 ? str('preview_giveaway_won_stars', stars) : str('preview_giveaway_won');
  }
  if (type === 'messageAnimatedEmoji') {
    const emoji = (content!['emoji'] as string | undefined) ?? '';
    if (emoji !== '') {
      return emoji;
    }
  }
  if (type === 'messageCustomServiceAction') {
    const text = ((content['text'] as string | undefined) ?? '').trim();
    return text !== '' ? text : str('preview_chat_state_updated');
  }
  const svcKey: string | undefined = SERVICE_LABEL_KEYS[type];
  if (svcKey !== undefined) {
    return str(svcKey);
  }
  // Last resort: any embedded text/caption, else a readable compatibility
  // label. Never expose a raw TDLib type or the old ambiguous "[通知]".
  const embedded = embeddedText(content);
  if (embedded !== '') {
    return embedded;
  }
  return str('preview_unsupported');
}
