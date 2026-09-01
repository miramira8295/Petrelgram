import { str } from './strings';

// What the chat header shows for a conversation whose identity may still be
// loading, already resolved, or failed to resolve.

export interface ChatHeaderInput {
  title: string;      // resolved chat title, '' while unknown
  subtitle: string;   // member count / last-seen line, '' when not derived yet
  state: string;      // loading | ready | error
  loadError: string;  // reason shown in place of the subtitle when state=error
  kind: string;       // private | group | channel | secret | '' (unresolved)
}

export interface ChatHeaderPresentation {
  titleText: string;
  subtitleText: string;
}

export interface ChatHeaderTitleInput {
  chatTitle: string;      // title from the chat itself, '' when still unknown
  topicName: string;      // forum topic / comment thread name, '' when unnamed
  forumTopicId: number;   // > 0 when viewing a forum topic
  directMessagesTopicId: number; // > 0 when viewing one channel-DM sender
  threadRootId: number;   // > 0 when viewing a comment thread
}

// Which name the header shows. A topic or comment-thread view is titled after
// the topic, not the chat.
//
// Single source of truth on purpose: this rule used to be written twice and the
// two disagreed — entering a thread derived `topicName || '评论'`, but the
// refresh that ran on every chat-list update overwrote it with a bare '评论',
// so a named thread lost its name a moment after opening.
export function chatHeaderTitle(input: ChatHeaderTitleInput): string {
  if (input.directMessagesTopicId > 0) {
    return input.topicName !== '' ? input.topicName : str('chat_header_kind_user');
  }
  if (input.forumTopicId > 0) {
    return input.topicName !== '' ? input.topicName : str('chat_header_topic');
  }
  if (input.threadRootId > 0) {
    return input.topicName !== '' ? input.topicName : str('chat_header_comments');
  }
  return input.chatTitle;
}

// A known title always wins — a chat whose title is cached should not flash
// "正在加载" just because the identity request is still in flight.
export function chatHeaderPresentation(input: ChatHeaderInput): ChatHeaderPresentation {
  return {
    titleText: headerTitleText(input),
    subtitleText: headerSubtitleText(input)
  };
}

function headerTitleText(input: ChatHeaderInput): string {
  if (input.title !== '') {
    return input.title;
  }
  return input.state === 'error' ? str('chat_header_unreadable') : str('chat_header_loading');
}

function headerSubtitleText(input: ChatHeaderInput): string {
  // A derived subtitle (member count, last seen) outranks the generic
  // chat-kind label below.
  if (input.subtitle !== '') {
    return input.subtitle;
  }
  if (input.state === 'loading') {
    return str('chat_header_resolving');
  }
  if (input.state === 'error') {
    return input.loadError !== '' ? input.loadError : str('chat_header_tap_retry');
  }
  if (input.kind === 'channel') {
    return str('chat_header_kind_channel');
  }
  if (input.kind === 'group') {
    return str('chat_header_kind_group');
  }
  if (input.kind === 'secret') {
    return str('chat_header_kind_secret');
  }
  return str('chat_header_kind_user');
}
