import { MessageEntry } from '../store/MessageEntry';
import {
  isUnformattedPlainText, messageUrls, parseFormattedText, RichSegment
} from './richText';
import { linkPreviewPresentation } from './linkPreview';
import { parseRichMessage, RichBlock, RichSpan } from './richBlocks';
import { TdObject } from '../tdkit/TdTypes';

// Structural inputs owned by ChatPage rather than MessageEntry. Optional media
// fields let older callers/tests keep constructing the text-only subset while
// the same signature function now covers every message family.
export interface MessageBubbleReuseContext {
  albumItemCount: number;
  memberCount: number;
  hasDateSeparator: boolean;
  showUnreadDivider: boolean;
  isGroup: boolean;
  isChannel: boolean;
  showAvatar: boolean;
  showSenderName: boolean;
  translationActive: boolean;
  menuEditable: boolean;
  albumShape?: string;
  albumCaptionShape?: string;
  playSlotActive?: boolean;
  animationPaused?: boolean;
  animationForcePlay?: boolean;
  animationPlaybackFailed?: boolean;
  isPinnedMsg?: boolean;
  liveSharing?: boolean;
  paidMediaPending?: boolean;
  liveVideoChatTappable?: boolean;
  audioQueuePosition?: number;
  audioQueueLength?: number;
  pollExpired?: boolean;
}

export type PlainTextBubbleReuseContext = MessageBubbleReuseContext;

export const MESSAGE_BUBBLE_REUSE_ENABLED: boolean = true;
export const PLAIN_TEXT_REUSE_ENABLED: boolean = MESSAGE_BUBBLE_REUSE_ENABLED;

function hashShape(value: string): string {
  let hash: number = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(36);
}

const UNFORMATTED_TEXT_SHAPE: string = hashShape('t:n;');

export function formattedTextReuseShape(
  text: string,
  entities: TdObject[],
  inlineCustomEmojiIds: string[],
  inlineCustomEmojiPaths: string[]
): string {
  if (text.trim() === '') {
    return 'empty';
  }
  if (isUnformattedPlainText(text, entities)) {
    return UNFORMATTED_TEXT_SHAPE;
  }
  const segments: RichSegment[] = parseFormattedText(text, entities);
  let shape: string = '';
  for (const segment of segments) {
    if (segment.kind === 'pre') {
      shape += 'p;';
      continue;
    }
    shape += segment.kind === 'quote' ? (segment.expandable ? 'qe:' : 'q:') : 't:';
    for (const run of segment.runs) {
      if (run.spoiler) {
        shape += 's';
      } else if (run.customEmojiId !== '') {
        const idx: number = inlineCustomEmojiIds.indexOf(run.customEmojiId);
        const path: string = idx >= 0 && idx < inlineCustomEmojiPaths.length
          ? inlineCustomEmojiPaths[idx] : '';
        shape += path !== '' ? 'e' : 'n';
      } else if (run.url !== '') {
        shape += 'u';
      } else {
        shape += 'n';
      }
    }
    shape += ';';
  }
  return hashShape(shape);
}

function formattedTextShape(msg: MessageEntry): string {
  return formattedTextReuseShape(
    msg.text,
    msg.textEntities,
    msg.inlineCustomEmojiIds,
    msg.inlineCustomEmojiPaths
  );
}

function linkPreviewShape(msg: MessageEntry): string {
  const hasPreview: boolean = msg.linkUrl !== '' || msg.linkSiteName !== '' ||
    msg.linkTitle !== '' || msg.linkDescription !== '' || msg.linkPhotoFileId !== 0;
  if (!hasPreview) {
    return 'no-preview';
  }
  const kind: string = linkPreviewPresentation(
    msg.linkUrl, msg.linkPreviewType, msg.linkSiteName).kind;
  const compact: boolean = msg.linkPhotoFileId !== 0 &&
    (kind === 'telegramChat' || kind === 'telegramInvite');
  return `preview-${compact ? 1 : 0}-${msg.linkTitle !== '' ? 1 : 0}` +
    `-${msg.linkDescription !== '' ? 1 : 0}-${msg.linkPhotoFileId !== 0 ? 1 : 0}` +
    `-${msg.linkPhotoPath !== '' ? 1 : 0}-${msg.linkPhotoFailed ? 1 : 0}` +
    `-${msg.linkPhotoProgress > 0 && msg.linkPhotoProgress < 100 ? 1 : 0}`;
}

function reactionShape(msg: MessageEntry): string {
  if (msg.reactions.length === 0) {
    return 'no-reactions';
  }
  let shape: string = '';
  for (const reaction of msg.reactions) {
    shape += reaction.customEmojiId === '' ? 'u' : (reaction.customEmojiPath === '' ? 'p' : 'i');
  }
  return `reactions-${hashShape(shape)}`;
}

function inlineButtonShape(msg: MessageEntry): string {
  let shape: string = '';
  for (const row of msg.inlineButtons) {
    shape += `r${row.length}:`;
    for (const button of row) {
      shape += button.isGame ? 'g' : (button.url !== '' ? 'u'
        : (button.callbackData !== '' ? 'c' : 'n'));
      shape += `${button.style};`;
    }
  }
  return shape === '' ? 'no-buttons' : `buttons-${hashShape(shape)}`;
}

function pollShape(msg: MessageEntry, ctx: MessageBubbleReuseContext): string {
  let shape: string = `${msg.pollOptions.length}:${msg.pollIsQuiz ? 1 : 0}` +
    `:${msg.pollIsAnonymous ? 1 : 0}:${msg.pollAllowMultiple ? 1 : 0}` +
    `:${msg.pollIsClosed ? 1 : 0}:${ctx.pollExpired ? 1 : 0}` +
    `:${msg.pollVotePending ? 1 : 0}:${msg.pollVoteError !== '' ? 1 : 0}` +
    `:${msg.pollExplanation !== '' ? 1 : 0}`;
  for (const option of msg.pollOptions) {
    shape += `:${option.isChosen ? 1 : 0}:${option.isBeingChosen ? 1 : 0}` +
      `:${option.votePercentage > 0 ? 1 : 0}`;
  }
  return hashShape(shape);
}

function richBlocksShape(msg: MessageEntry): string {
  const wrapper: TdObject = { '@type': 'messageRichMessage' };
  const inner: TdObject = { '@type': 'richMessage' };
  inner['blocks'] = msg.richBlocks ?? [];
  wrapper['message'] = inner;
  const blocks: RichBlock[] = parseRichMessage(wrapper);
  let shape: string = '';
  for (const block of blocks) {
    shape += richBlockShape(block);
  }
  return `${blocks.length}-${hashShape(shape)}`;
}

function richSpanShape(span: RichSpan): string {
  return `${span.bold ? 1 : 0}${span.italic ? 1 : 0}${span.underline ? 1 : 0}` +
    `${span.strike ? 1 : 0}${span.code ? 1 : 0}${span.url !== '' ? 1 : 0}`;
}

function richBlockShape(block: RichBlock): string {
  let shape: string = `${block.kind}:${block.level}:s${block.spans.length}:`;
  for (const span of block.spans) {
    shape += richSpanShape(span);
  }
  shape += `:c${block.children.length}:`;
  for (const child of block.children) {
    shape += richBlockShape(child);
  }
  return `${shape};`;
}

function stickerShape(msg: MessageEntry): string {
  const suspendedFallback: string = msg.photoPath === '' ? 'empty-thumb' : 'thumb';
  const source: string = msg.stickerPath !== ''
    ? `${msg.stickerFormat}-ready` : (msg.stickerFileId !== 0 ? 'source-pending' : 'no-source');
  const status: string = msg.stickerPath === '' && msg.stickerFileId !== 0
    ? 'source-status' : (msg.photoPath === '' && msg.photoFileId !== 0 ? 'thumb-status' : 'no-status');
  return `${suspendedFallback}:${source}:${status}:${msg.stickerFailed ? 1 : 0}` +
    `:${msg.photoFailed ? 1 : 0}:${msg.isEmojiSticker ? 1 : 0}`;
}

function mediaShape(msg: MessageEntry, ctx: MessageBubbleReuseContext): string {
  const main: string = ctx.playSlotActive && msg.contentType === 'video' && msg.videoFileId !== 0
    ? 'play-slot' : (msg.isAnimation && msg.videoPath !== '' && !ctx.animationPaused &&
      !ctx.animationPlaybackFailed ? 'loop-video'
      : (msg.photoFileId !== 0 || msg.photoPath !== '' ? 'thumb' : 'placeholder'));
  return `${main}:photo-${msg.photoPath !== '' ? 1 : 0}-${msg.photoFileId !== 0 ? 1 : 0}` +
    `-${msg.photoFailed ? 1 : 0}:video-${msg.videoPath !== '' ? 1 : 0}` +
    `-${msg.videoFailed ? 1 : 0}:meta-${msg.videoDuration > 0 || msg.videoFileSize > 0 ? 1 : 0}` +
    `:caption-${msg.text !== '' ? formattedTextShape(msg) : 'none'}` +
    `:translation-${msg.translatedText !== '' ? (msg.translationHidden ? 'hidden' : 'shown') : 'none'}`;
}

function messageBodyShape(msg: MessageEntry, ctx: MessageBubbleReuseContext): string {
  if (ctx.albumItemCount > 1) {
    return `album:${ctx.albumShape ?? ctx.albumItemCount.toString()}` +
      `:${ctx.albumCaptionShape ?? 'caption-unknown'}`;
  }
  switch (msg.contentType) {
    case 'richMessage':
      return `rich:${richBlocksShape(msg)}`;
    case 'text':
      return `text:${formattedTextShape(msg)}:${linkPreviewShape(msg)}` +
        `:${msg.translatedText === '' ? 'no-translation'
          : (msg.translationHidden ? 'translation-hidden' : 'translation-visible')}`;
    case 'photo':
    case 'video':
      return `${msg.contentType}:${mediaShape(msg, ctx)}`;
    case 'videoNote':
      return `video-note:${msg.photoPath !== '' ? 'poster' : 'placeholder'}` +
        `:${msg.videoPath !== '' ? 'playable' : 'download'}`;
    case 'voice':
      return `voice:${msg.videoFileId === 0 && msg.videoPath === '' ? 'unavailable'
        : (msg.videoPath !== '' ? 'ready' : 'download')}` +
        `:${msg.videoFailed ? 'failed' : 'ok'}:${msg.speechState}` +
        `:${msg.speechText !== '' ? 'speech-text' : 'no-speech-text'}` +
        `:${msg.videoProgress > 0 ? 'progress' : 'no-progress'}` +
        `:${msg.voiceListened ? 'listened' : 'unlistened'}`;
    case 'audio':
      return `audio:${msg.videoFileId === 0 && msg.videoPath === '' ? 'unavailable'
        : (msg.videoPath !== '' ? 'ready' : 'download')}` +
        `:${msg.videoFailed ? 'failed' : 'ok'}:${msg.mediaDownloadActive ? 'active' : 'idle'}` +
        `:${msg.videoProgress > 0 ? 'progress' : 'no-progress'}` +
        `:${msg.photoPath !== '' ? 'cover' : 'no-cover'}` +
        `:${msg.text !== '' ? formattedTextShape(msg) : 'no-caption'}` +
        `:${(ctx.audioQueuePosition ?? 0) > 0 && (ctx.audioQueueLength ?? 0) > 1
          ? 'queue-label' : 'no-queue-label'}`;
    case 'file':
      return `file:${msg.videoFileId === 0 && msg.videoPath === '' ? 'unavailable'
        : (msg.videoPath !== '' ? 'ready' : 'download')}` +
        `:${msg.videoFailed ? 'failed' : 'ok'}:${msg.mediaDownloadActive ? 'active' : 'idle'}` +
        `:${msg.videoProgress > 0 ? 'progress' : 'no-progress'}` +
        `:${msg.text !== '' ? formattedTextShape(msg) : 'no-caption'}`;
    case 'contact':
      return `contact:${msg.contactAvatarPath !== '' ? 'avatar' : 'initials'}` +
        `:${msg.contactPhone !== '' ? 'phone' : 'no-phone'}` +
        `:${msg.contactUserId > 0 || msg.contactVcard !== '' ? 'open' : 'unavailable'}`;
    case 'location':
    case 'venue':
      return `${msg.contentType}:${msg.locationValid ? 'valid' : 'invalid'}` +
        `:${msg.locationLivePeriod > 0 ? 'live' : 'fixed'}` +
        `:${msg.venueTitle !== '' ? 'title' : 'no-title'}` +
        `:${msg.venueAddress !== '' ? 'address' : 'no-address'}` +
        `:${msg.locationAccuracy > 0 ? 'accuracy' : 'no-accuracy'}` +
        `:${msg.locationProximityRadius > 0 ? 'proximity' : 'no-proximity'}`;
    case 'poll':
      return `poll:${pollShape(msg, ctx)}`;
    case 'dice':
      return `dice:${msg.diceLayerPaths.length === 5 ? 'layers' :
        (msg.stickerPath !== '' ? 'sticker' : 'placeholder')}` +
        `:${msg.diceHasFinalState && msg.diceValue > 0 ? 'final' : 'waiting'}`;
    case 'game':
      return `game:${msg.photoPath !== '' ? 'cover' : 'placeholder'}` +
        `:${msg.photoFileId !== 0 ? (msg.photoFailed ? 'retry' : 'loading') : 'no-file'}` +
        `:${msg.gameText.trim() !== '' && msg.gameDescription.trim() !== ''
          ? 'extra-text' : 'single-text'}`;
    case 'paidMedia':
      return `paid:${msg.paidMediaLocked ? 'locked' : 'open'}` +
        `:${msg.photoPath !== '' ? 'photo' : 'placeholder'}:${msg.photoFailed ? 'failed' : 'ok'}` +
        `:${msg.photoFileId !== 0 ? (msg.photoProgress > 0 ? 'progress' : 'loading') : 'no-file'}` +
        `:${msg.paidMediaKind === 'video' ? 'video' : 'other'}` +
        `:${msg.text !== '' ? 'caption' : 'no-caption'}:${msg.paidMediaCount > 1 ? 'multi' : 'single'}`;
    case 'gift':
      return `gift:${msg.photoPath !== '' ? 'photo' : 'placeholder'}` +
        `:${msg.photoFileId !== 0 ? (msg.photoFailed ? 'retry'
          : (msg.photoProgress > 0 ? 'progress' : 'loading')) : 'no-file'}` +
        `:${msg.giftCode !== '' ? 'code' : 'no-code'}:${msg.giftRefunded ? 'refunded' : 'active'}` +
        `:${msg.giftValue !== '' ? 'value' : 'no-value'}:${msg.text !== '' ? 'text' : 'no-text'}`;
    case 'giveaway':
      return `giveaway:${msg.photoPath !== '' ? 'photo' : 'no-photo'}` +
        `:${msg.giveawayMessageId !== 0 ? 'origin' : 'no-origin'}` +
        `:${msg.giveawayDescription !== '' && msg.giveawayState !== 'prize' ? 'description' : 'no-description'}` +
        `:${msg.giveawayWinnerCount > 0 ? 'winners' : 'no-winners'}` +
        `:${msg.giveawayOnlyNewMembers ? 'new-only' : 'all'}` +
        `:${msg.giveawayUnclaimedCount > 0 ? 'unclaimed' : 'claimed'}`;
    case 'emoji':
    case 'customEmoji':
      return `${msg.contentType}:${msg.text !== '' ? 'text' : 'fallback'}` +
        `:${msg.photoFailed ? 'failed' : 'loading'}`;
    case 'sticker':
      return `sticker:${stickerShape(msg)}`;
    case 'system':
      return `system:${ctx.liveVideoChatTappable ? 'live-action' : 'plain'}`;
    default:
      return `${msg.contentType}:${msg.isUnsupportedMessage ? 'unsupported' : 'fallback'}`;
  }
}

export function canReuseMessageBubble(
  msg: MessageEntry,
  ctx: MessageBubbleReuseContext
): boolean {
  if (!MESSAGE_BUBBLE_REUSE_ENABLED) {
    return false;
  }
  return true;
}

export function canReusePlainTextBubble(
  msg: MessageEntry,
  ctx: PlainTextBubbleReuseContext
): boolean {
  return canReuseMessageBubble(msg, ctx);
}

// Strict gate for the genuinely small renderer. Anything that needs the rich
// text tree, a preview/footer/keyboard, album semantics or completed translation
// stays on MessageBubble. Reply quotes, transient translation status and the
// ordinary group-chat chrome are intentionally allowed because they are common
// in the first visible screen and the lightweight renderer implements them.
export function canRenderLightweightPlainText(
  msg: MessageEntry,
  ctx: MessageBubbleReuseContext
): boolean {
  if (msg.contentType !== 'text' || msg.isUnsupportedMessage ||
    ctx.memberCount !== 1 || ctx.albumItemCount > 1) {
    return false;
  }
  if (!isUnformattedPlainText(msg.text, msg.textEntities) ||
    msg.forwardFrom !== '' || msg.reactions.length > 0 ||
    msg.inlineButtons.length > 0 || msg.commentCount > 0 ||
    msg.translatedText !== '') {
    return false;
  }
  return msg.linkUrl === '' && msg.linkSiteName === '' && msg.linkTitle === '' &&
    msg.linkDescription === '' && msg.linkDescriptionEntities.length === 0 &&
    msg.linkPhotoFileId === 0 && msg.linkPhotoPath === '' && msg.linkPreviewType === '';
}

// reuseId describes structure only. Message identity must never enter it: doing
// so turns every row into a one-entry pool and defeats reuse entirely.
export function messageBubbleReuseId(
  msg: MessageEntry,
  ctx: MessageBubbleReuseContext,
  lightweightPlainText: boolean = canRenderLightweightPlainText(msg, ctx)
): string {
  const direction: string = msg.isOutgoing ? 'out' : (ctx.isGroup ? 'group-in' : 'direct-in');
  const edited: string = msg.editDate > 0 ? 'edited' : 'plain';
  const senderHistory: string = ctx.isGroup && msg.senderIsUser && msg.senderId > 0
    ? 'sender-history' : 'no-sender-history';
  const senderLabel: string = ctx.isGroup && !msg.isOutgoing && ctx.showSenderName &&
    msg.senderName !== '' ? 'sender-label' : 'no-sender-label';
  const reply: string = msg.replyToMessageId !== 0 ? 'reply' : 'no-reply';
  const forwarded: string = msg.forwardFrom !== '' ? 'forward' : 'no-forward';
  const comments: string = ctx.isChannel && msg.commentCount > 0
    ? (msg.commentReplierIds.length > 0
      ? `comments-avatars-${msg.commentReplierIds.length}` : 'comments') : 'no-comments';
  return `${lightweightPlainText ? 'plain-text' : 'message'}:${direction}` +
    `:${ctx.isChannel ? 'channel' : 'chat'}` +
    `:avatar-${ctx.showAvatar ? 1 : 0}:sender-${ctx.showSenderName ? 1 : 0}:${edited}` +
    `:${ctx.menuEditable ? 'editable' : 'fixed'}:${senderHistory}:${senderLabel}` +
    `:${ctx.hasDateSeparator ? 'date' : 'no-date'}` +
    `:${ctx.showUnreadDivider ? 'unread' : 'no-unread'}:${reply}:${forwarded}` +
    `:${messageBodyShape(msg, ctx)}:${reactionShape(msg)}` +
    `:${msg.text !== '' ? 'menu-translate' : 'no-menu-translate'}` +
    `:${messageUrls(msg.text, msg.textEntities).length > 0 ? 'copy-url' : 'no-copy-url'}` +
    `:${inlineButtonShape(msg)}:${comments}` +
    `:pinned-${ctx.isPinnedMsg ? 1 : 0}:sharing-${ctx.liveSharing ? 1 : 0}` +
    `:paid-pending-${ctx.paidMediaPending ? 1 : 0}`;
}

export function plainTextBubbleReuseId(
  msg: MessageEntry,
  ctx: PlainTextBubbleReuseContext
): string {
  return messageBubbleReuseId(msg, ctx);
}
