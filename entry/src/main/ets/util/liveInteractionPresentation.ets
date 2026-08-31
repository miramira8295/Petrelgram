import { str } from './strings';
export interface LiveInteractionEntry {
  key: string;
  revision: string;
  source: string;
  id: number;
  senderKey: string;
  senderName: string;
  senderInitials: string;
  senderAvatarPath: string;
  colorSeed: number;
  date: number;
  text: string;
  photoPath: string;
  emojiOnly: boolean;
  isFromOwner: boolean;
  sendState: string;
  arrivalOrder: number;
}

export interface LiveInteractionPresentationInput {
  valid: boolean;
  resolved: boolean;
  active: boolean;
  joined: boolean;
  joinedOnce: boolean;
  recovering: boolean;
  messagesAllowed: boolean;
  canSendMessages: boolean;
  messageCount: number;
  channelAttached: boolean;
  channelHistoryState: string;
  channelHistoryError: string;
}

export interface LiveInteractionPresentation {
  kind: string;
  statusText: string;
  statusTone: string;
  subtitle: string;
  emptyTitle: string;
  emptyDetail: string;
  composerEnabled: boolean;
  composerHint: string;
  showProgress: boolean;
  showHistoryRetry: boolean;
}

function normalizedMessageText(value: string): string {
  return value.trim().toLocaleLowerCase();
}

export function sameLiveInteraction(left: LiveInteractionEntry, right: LiveInteractionEntry): boolean {
  if (left.key === right.key) { return true; }
  if (left.source === right.source || left.senderKey === '' || left.senderKey !== right.senderKey) {
    return false;
  }
  if (Math.abs(left.date - right.date) > 1) { return false; }
  const leftText = normalizedMessageText(left.text);
  return leftText !== '' && leftText === normalizedMessageText(right.text);
}

// The live overlay and channel history are separate TDLib namespaces. Merge by
// server date, then keep a page-local arrival order as the deterministic tie
// breaker. Cross-source dedupe is intentionally conservative so repeated emoji
// sent by a real user are never collapsed merely because they look alike.
export function mergeLiveInteractions(
  candidates: LiveInteractionEntry[], limit: number
): LiveInteractionEntry[] {
  const ordered = candidates.slice();
  ordered.sort((left: LiveInteractionEntry, right: LiveInteractionEntry): number => {
    if (left.date !== right.date) { return left.date - right.date; }
    if (left.arrivalOrder !== right.arrivalOrder) { return left.arrivalOrder - right.arrivalOrder; }
    return left.key < right.key ? -1 : (left.key > right.key ? 1 : 0);
  });
  const deduped: LiveInteractionEntry[] = [];
  for (const candidate of ordered) {
    const duplicateIndex = deduped.findIndex(
      (entry: LiveInteractionEntry): boolean => sameLiveInteraction(entry, candidate)
    );
    if (duplicateIndex < 0) {
      deduped.push(candidate);
    } else if (candidate.source === 'call' && deduped[duplicateIndex].source !== 'call') {
      // Group-call messages carry Telegram's authoritative owner flag.
      deduped[duplicateIndex] = candidate;
    }
  }
  const boundedLimit = Math.max(1, limit);
  return deduped.length > boundedLimit
    ? deduped.slice(deduped.length - boundedLimit) : deduped;
}

export function isSupportedLiveChannelMessage(contentType: string, isAnimation: boolean): boolean {
  if (contentType === 'text' || contentType === 'photo' || contentType === 'emoji' ||
    contentType === 'customEmoji' || contentType === 'sticker') {
    return true;
  }
  return contentType === 'video' && isAnimation;
}

export function looksLikeEmojiOnly(raw: string): boolean {
  const value = raw.trim();
  if (value === '') { return false; }
  let hasEmoji = false;
  for (let i = 0; i < value.length;) {
    const first = value.charCodeAt(i);
    let codePoint = first;
    let width = 1;
    if (first >= 0xD800 && first <= 0xDBFF && i + 1 < value.length) {
      const second = value.charCodeAt(i + 1);
      if (second >= 0xDC00 && second <= 0xDFFF) {
        codePoint = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
        width = 2;
      }
    }
    i += width;
    if (codePoint === 0x200D || codePoint === 0xFE0E || codePoint === 0xFE0F ||
      codePoint === 0x20E3 || codePoint === 0x0020) {
      continue;
    }
    const emoji = (codePoint >= 0x1F000 && codePoint <= 0x1FAFF) ||
      (codePoint >= 0x2600 && codePoint <= 0x27BF) ||
      (codePoint >= 0x2300 && codePoint <= 0x23FF) ||
      (codePoint >= 0x2B00 && codePoint <= 0x2BFF) ||
      codePoint === 0x00A9 || codePoint === 0x00AE || codePoint === 0x2122 ||
      codePoint === 0x3030 || codePoint === 0x303D || codePoint === 0x3297 || codePoint === 0x3299;
    if (!emoji) { return false; }
    hasEmoji = true;
  }
  return hasEmoji;
}

export function liveInteractionLooksLikeEmojiOnly(raw: string): boolean {
  return looksLikeEmojiOnly(raw);
}

export function liveInteractionPresentation(
  input: LiveInteractionPresentationInput
): LiveInteractionPresentation {
  const historyFailed = input.channelAttached && input.channelHistoryState === 'error';
  const historyLoading = input.channelAttached && input.channelHistoryState === 'loading' &&
    input.messageCount === 0;
  if (!input.valid) {
    return {
      kind: 'invalid', statusText: str('live_chat_unavailable_short'), statusTone: 'muted',
      subtitle: str('live_chat_channel_unavailable'), emptyTitle: str('live_chat_invalid_title'),
      emptyDetail: str('live_chat_invalid_detail'), composerEnabled: false,
      composerHint: str('live_chat_no_channel'), showProgress: false,
      showHistoryRetry: false
    };
  }
  if (input.resolved && !input.active) {
    return {
      kind: 'ended', statusText: str('live_chat_ended_short'), statusTone: 'muted',
      subtitle: str('live_chat_ended_readable'), emptyTitle: str('live_chat_ended_title'),
      emptyDetail: str('live_chat_ended_empty'), composerEnabled: false,
      composerHint: str('live_chat_ended_closed'), showProgress: false,
      showHistoryRetry: historyFailed
    };
  }
  if (input.recovering) {
    return {
      kind: 'recovering', statusText: str('live_chat_reconnecting_short'), statusTone: 'accent',
      subtitle: str('live_chat_recovering_note'), emptyTitle: str('live_chat_recovering_title'),
      emptyDetail: str('live_chat_recovering_detail'), composerEnabled: false,
      composerHint: str('live_chat_recovering_status'), showProgress: input.messageCount === 0,
      showHistoryRetry: historyFailed
    };
  }
  if (!input.joined && !input.joinedOnce) {
    return {
      kind: 'connecting', statusText: str('live_chat_connecting_short'), statusTone: 'accent',
      subtitle: str('live_chat_loading_detail'), emptyTitle: str('live_chat_loading_title'),
      emptyDetail: str('live_chat_loading_note'), composerEnabled: false,
      composerHint: str('live_chat_connecting_status'), showProgress: true, showHistoryRetry: historyFailed
    };
  }
  if (historyLoading) {
    return {
      kind: 'loading', statusText: str('live_chat_syncing_short'), statusTone: 'accent',
      subtitle: str('live_chat_syncing_detail'), emptyTitle: str('live_chat_syncing_title'),
      emptyDetail: str('live_chat_syncing_note'),
      composerEnabled: input.messagesAllowed && input.canSendMessages,
      composerHint: str('live_chat_input_hint'), showProgress: true, showHistoryRetry: false
    };
  }
  if (!input.messagesAllowed) {
    return {
      kind: 'disabled', statusText: str('live_chat_off_short'), statusTone: 'muted',
      subtitle: historyFailed ? str('live_chat_off_detail') :
        (input.channelAttached ? str('live_chat_off_note') : str('live_chat_off_title')),
      emptyTitle: str('live_chat_off_empty'), emptyDetail: str('live_chat_off_hint'),
      composerEnabled: false, composerHint: str('live_chat_no_channel'),
      showProgress: false, showHistoryRetry: historyFailed
    };
  }
  if (!input.canSendMessages) {
    return {
      kind: 'readonly', statusText: str('live_chat_readonly_short'), statusTone: 'muted',
      subtitle: historyFailed ? str('live_chat_readonly_detail') : str('live_chat_readonly_note'),
      emptyTitle: str('live_chat_readonly_empty'), emptyDetail: str('live_chat_readonly_reason'),
      composerEnabled: false, composerHint: str('live_chat_readonly_hint'),
      showProgress: false, showHistoryRetry: historyFailed
    };
  }
  return {
    kind: 'live', statusText: str('live_chat_live_short'), statusTone: 'live',
    subtitle: historyFailed ? str('live_chat_readonly_detail') :
      (input.channelAttached ? str('live_chat_live_detail') : str('live_chat_live_note')),
    emptyTitle: str('live_chat_readonly_empty'), emptyDetail: str('live_chat_live_empty'), composerEnabled: true,
    composerHint: str('live_chat_input_hint'), showProgress: false, showHistoryRetry: historyFailed
  };
}
